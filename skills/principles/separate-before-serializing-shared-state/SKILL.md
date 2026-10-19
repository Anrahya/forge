---
name: separate-before-serializing-shared-state
description: "Apply when two or more concurrent actors might write the same file, key, branch, row, or state object."
disable-model-invocation: true
---

# Separate before serializing shared state

## Rule

First ask whether the actors need one shared object at all. Often each one publishes separate facts. Then give each actor its own file, key, or directory and merge only when reading. Add a lock, a single-writer queue, or compare-and-swap only when one shared write target is a real invariant. Instructions and naming conventions are not concurrency control.

## Why

Races on shared writes are intermittent, hard to reproduce, and expensive to debug.

## Self-check

- Did I list every place where two actors write the same target?
- For each one, did I try giving each actor its own target first?
- Is every remaining shared write protected by structure, not by a comment?

Fix every no before you move on.

## Enforced by

Reviewer checklist, applied to anything with retries or shared writes.
