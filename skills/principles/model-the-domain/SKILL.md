---
name: model-the-domain
description: "Apply when logic branches on the same rule in several places, when two booleans must stay in sync, or when a new case adds one more branch to an if/else chain."
disable-model-invocation: true
---

# Model the domain

## Rule

Put each domain rule in one structure instead of scattered conditionals. Use a state machine for a lifecycle, a typed model for a repeated shape, and a lookup table or tagged union for branching that spreads across files. Do not force a structure onto code that is already clear, local, and unlikely to grow.

## Why

A structure that matches the domain removes branches and makes invalid states impossible to build.

## Self-check

- Is each domain rule encoded in exactly one place?
- Does the next new case mean adding a row or a variant, not a branch in several files?
- Did the structure remove more branches or invalid states than the indirection it adds?

Fix every no before you move on.

## Enforced by

G0 phase-artifacts. The SHAPE template requires the data shape and organizing structure section, and BUILD stays locked until that section is filled in.
