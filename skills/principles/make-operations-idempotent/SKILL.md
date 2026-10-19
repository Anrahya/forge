---
name: make-operations-idempotent
description: "Apply when writing a command, job, migration, or loop that can crash, restart, or retry partway through."
disable-model-invocation: true
---

# Make operations idempotent

## Rule

Each run reads the current state, compares it to the goal, and applies only the difference. A repeat run then finds nothing left to do. Anything a run leaves behind, such as a lock, a temp file, or a half-written record, must be something the next run can recognize as stale. Write to a temp path and rename it into place instead of writing in place.

## Why

When leftover state changes the next run's result, every restart turns into a debugging session.

## Self-check

- Does running this twice in a row give the same end state as running it once?
- If the last run crashed at any line, does the next run still reach the goal?
- Can the next run tell a stale lock or temp file from a live one?

Fix every no before you move on.

## Enforced by

Reviewer checklist, applied to anything with retries or shared writes.
