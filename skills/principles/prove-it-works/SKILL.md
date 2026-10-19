---
name: prove-it-works
description: "Apply when you are about to say that a task, unit, or fix is done."
disable-model-invocation: true
---

# Prove it works

## Rule

Check the real artifact directly. Run the feature, read the actual value, and inspect the actual output. A clean compile, a passing proxy, a cached screenshot, or a subagent's report is not proof. Prefer a script that repeats the check so a reviewer can rerun it. When a check fails, suspect how you observed before you suspect the system.

## Why

Unverified work has unknown correctness, and acting on a wrong inference costs more than looking.

## Self-check

- Did I observe the real output in this session, after my last edit?
- Is the evidence a log, file, or command that a reviewer can rerun?
- Does every "works" claim in my reply point to that evidence?

Fix every no before you move on.

## Enforced by

G2 green-after-edit, G9 runtime, and G10 evidence-integrity. The turn-stopping gate blocks "done" until the phase gates pass.
