---
name: forge-verify-setup
description: "Generate a project-local verification skill that launches, drives, and captures evidence from the real app, plus a feature map. Use for /forge-verify-setup or when G9 reports no verify skill."
user-invocable: true
disable-model-invocation: true
---

# forge-verify-setup

"Tests pass" is a proxy. This skill gives the next agent a scripted way to prove behavior on the real surface. The output is written for an agent that reads it cold mid-task, not for a human.

## 1. Interview the repo, not the user

Answer from the codebase. Ask the user only what the code cannot tell you.

- Surface: what does a user touch? Web UI, CLI, TUI, HTTP API, desktop, mobile, library. Pick the primary one, note the rest.
- Run: the repo's own documented dev command. Ports, env vars, seed data, auth.
- Drive: existing harnesses first (Playwright, Cypress, expect scripts, curl-able endpoints, a debug port). Only then a generic recipe: browser automation for web, a PTY or tmux session for CLI and TUI, plain HTTP for services.
- Observe: screenshots, terminal transcripts, response bodies, logs, exit codes, database rows.
- Isolate: can two instances run side by side? If not, the skill must say so and refuse to double-drive a shared instance.

If the checkout does not build or start as-is, fix that first or report it precisely. A skill written against a broken base teaches wrong steps.

## 2. Write `.agents/skills/verify-<app>/SKILL.md`

Frontmatter `name: verify-<app>` and a description naming the app, the surface, and when to reach for it. Sections, each grounded in what the interview found, no placeholders:

- Launch: the exact command, how to tell it is ready (a log line, a prompt, a usable state after migrations and seed data, not just a listening port), and teardown. For a short-lived CLI, launch means build once, then each drive runs in its own PTY.
- Doctor: one read-only check that says whether this instance is worth driving. Process up, right build, port owned by us, auth valid.
- Drive: the recipe with real selectors, commands, and routes from this repo. Prefer stable handles (ARIA labels, data attributes, prompt strings) over coordinates.
- Evidence: what to capture and where it goes. Exercise the real user path, not internal setters or test-only endpoints. Capture the action and the resulting state. Verify side effects (files written, rows inserted, messages sent). Mocks only where a production boundary already isolates the external system.
- Cleanup: tear down what the run created. Never kill by process name; kill what you started. Cleanup removes instances and scratch state, never the evidence.
- Helpers: any script the skill ships is executable and its invocation is shown in the body.

## 3. Seed the feature map

`.agents/skills/verify-<app>/features/README.md` as the index, then one file per user-facing feature (start with the top three to five from routes, commands, menus, or docs). Each file has four sections: `## Sub-features`, `## How to get to it`, `## Drive`, `## Gotchas`. The `## Drive` section contains a fenced `bash` block that runs the journey end to end and exits non-zero on failure; G9 executes exactly that block. If seed data lacks a precondition, the journey fails and the reason goes in Gotchas. Never weaken a journey to make it pass.

## 4. Prove it before handing over

Run the skill's own instructions once: launch, doctor, drive one mapped feature, capture evidence, clean up. After cleanup, confirm the evidence still exists where the skill says. Fix what fails and run cleanup after every failed attempt. A generated skill that was never executed is a draft, not a deliverable.

## 5. Report

What surface, what harness, which feature was proven, where the evidence lives, and what the stand-in environment (if any) did not cover. Point the user at `forge-verify-maintain` for keeping the map honest.
