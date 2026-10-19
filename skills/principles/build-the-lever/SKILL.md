---
name: build-the-lever
description: "Apply when the work is more than a couple of obvious edits, such as a sweep, a migration, an analysis, or a check a reviewer must trust."
disable-model-invocation: true
---

# Build the lever

## Rule

Build the script, codemod, or generator that does or proves the work instead of doing it by hand. Do the first unit by hand to learn the recipe. Then write the tool and rerun it on that unit to confirm it matches. Keep the tool small and safe to rerun, and keep it in the diff or in `.forge/<task>/`.

## Why

A reviewer can rerun a script, but the only way to recheck hand edits is to redo them.

## Self-check

- Is there a script or tool a reviewer can rerun to check this work?
- Did I compare the tool's output against one unit done by hand?
- Is the tool the smallest one that does the job, not a framework?

Fix every no before you move on.

## Enforced by

`forge-correct` turns repeated corrections into gates. Proof artifacts are scripts a reviewer reruns.
