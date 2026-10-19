---
name: foundational-thinking
description: "Apply when you are about to write logic and have not yet chosen the core types, the data structures, or the order of scaffold and feature work."
disable-model-invocation: true
---

# Foundational thinking

## Rule

Pick the data shape before the logic. Define the core types, list how the code reads and writes them, and choose structures that fit the most common paths. Build shared scaffolding such as types, test setup, and lint config first, because every later step uses it.

## Why

When the data shape is right most of the logic is obvious, and when it is wrong every function pays for it.

## Self-check

- Did I write down the core types before the first function body?
- Does the chosen structure fit the most frequent read and write?
- If two actors touch this state at once, did I decide what happens?

Fix every no before you move on.

## Enforced by

G0 phase-artifacts. The SHAPE template requires a data shape and structure section, and BUILD stays locked until that section is filled in.
