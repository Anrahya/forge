---
name: fix-root-causes
description: "Apply when debugging a failure, or when tempted to add a guard, retry, or default at the place an error showed up."
disable-model-invocation: true
---

# Fix root causes

## Rule

Reproduce first. Then ask why until you reach a wrong decision in the code, not a consequence of an earlier one. Fix it there. A guard at the symptom is a fix only when the state it handles is legitimate. If the state should never exist, find what produced it. Search for the same fault elsewhere and fix every instance.

## Why

A symptom fix hides the evidence and lets the fault show up again somewhere else.

## Self-check

- Do I have a reproduction that fails before the fix?
- Can I name the first line where the system did something it should not?
- Does my fix avoid swallowing an error, clamping a value, or adding a retry to hide the fault?

Fix every no before you move on.

## Enforced by

The bug playbook allows no fix without a reproduction and a traced mechanism. G1 red-proof requires a failing log from before the change.
