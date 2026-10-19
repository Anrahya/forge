---
name: encode-lessons-in-structure
description: "Apply when you write the same instruction or correction for the second time."
disable-model-invocation: true
---

# Encode lessons in structure

## Rule

Turn a repeated lesson into structure. Use the highest level that works, in this order: architecture, types, a lint whose message names the fix, a test, and docs last. Once the structure exists, delete the prose instruction it replaces. When the lesson needs judgment and cannot be encoded, put a concrete example of the failure next to the instruction.

## Why

Weak models agree with written rules and then skip them, while a check that fails cannot be skipped.

## Self-check

- Did I encode the lesson at the highest level that works?
- Does the new check fail on a real past instance of the mistake?
- Did I remove the prose instruction that the check now replaces?

Fix every no before you move on.

## Enforced by

`forge-correct` turns repeated corrections into gates and proves each one fails on a real past mistake. Proof artifacts are scripts a reviewer reruns.
