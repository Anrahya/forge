---
name: subtract-before-you-add
description: "Apply when an addition, refactor, or rewrite lands in code that still carries dead paths, stale guards, or unused references."
disable-model-invocation: true
---

# Subtract before you add

## Rule

Remove what is dead or redundant first, then build on the smaller base. Do not add validators, guards, or options the spec does not ask for. When a reference adds nothing, delete it instead of leaving a stub.

## Why

New code built beside dead code inherits its confusion, and the dead code gets harder to remove later.

## Self-check

- Did I look for dead code, unused flags, and redundant checks in this area before adding anything?
- Does each new guard or option trace to a line in `task.md`?
- Is the code I leave behind no more complex than what I found?

Fix every no before you move on.

## Enforced by

Reviewer checklist. G3 diff-hygiene flags new code added beside a deprecated sibling.
