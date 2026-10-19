---
name: forge-ground
description: "GROUND phase: build a working mental model of the subsystem a task touches, cite existing examples, and capture the reproduction for bugs. Read-only."
disable-model-invocation: true
---

# forge-ground

You are in a fresh context. Inputs are `AGENTS.md`, this file, and `.forge/<id>/` (read `task.md` first). Output is `.forge/<id>/ground.md` in the template's shape. You may read, grep, and run tests or the app. You may not edit source. Writes outside `.forge/` are denied.

## Steps

1. Read `task.md`. Restate the goal in one line at the top of your notes.
2. Find the entry point for the path the task touches. Trace it to its effect. Write "How it works" from that trace, not from file names.
3. For every pattern the task will need (a handler, a query, an error, a test), find two existing instances in this repo and cite them as `path:line`. If none exist, write "none found" and say what the nearest thing is.
4. Record the commands: test, lint, typecheck, run. Run the test command once so you know it works and how long it takes. If there is no way to run tests or the app, that is stop condition S2: say so in ground.md under Gotchas and stop.
5. List the files likely touched. Be honest; the reviewer uses this list to spot scope creep, it is not a plan.
6. Bugs: reproduce on the real surface. Save the command and output to `repro.log`. If it does not reproduce, tighten conditions or add temporary instrumentation (in `.forge/<id>/scratch/`, not in source) until it fires. Do not guess at a mechanism yet.
7. Write Gotchas last: hidden state, ordering, flaky areas, anything that would surprise the build context.

## Rules

- No design here. Describe what is, not what should be.
- Bulk reading goes through subagents when the harness has them; keep findings, not file dumps, in this context (`guard-the-context-window`).
- Every claim about behavior names the file:line or the command output it came from.
- Append one row to `decisions.tsv` when done: phase `ground`, evidence `ground.md`.
