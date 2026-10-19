---
name: outcome-oriented-execution
description: "Apply when a planned rewrite or migration tempts you to keep every intermediate step working by writing temporary compatibility code."
disable-model-invocation: true
---

# Outcome-oriented execution

## Rule

Aim at the end state. Accept planned, scoped, reversible breakage between explicit checkpoints instead of writing shims that keep each step smooth. Write down up front where breakage is allowed. Keep checks running on the areas you touch, and run full static and runtime verification at the end.

## Why

Temporary compatibility code tends to stay, and it becomes debt nobody planned.

## Self-check

- Did I write down where temporary breakage is allowed and where it is not?
- Is every shim I added deleted again within this same task?
- Does the final state pass every gate with no compatibility layer left?

Fix every no before you move on.

## Enforced by

Playbook only. No gate checks this, so the self-check above is the only guard.
