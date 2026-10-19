---
name: exhaust-the-design-space
description: "Apply when a design decision has no precedent in the codebase, or when SHAPE runs for a feature or refactor."
disable-model-invocation: true
---

# Exhaust the design space

## Rule

Sketch two or three structurally different candidates before picking one. Each sketch has types, signatures, and stub bodies, not prose. Compare them on the data shape, the number of branches, and what each one makes impossible. When a run could settle the choice, build a throwaway prototype and let the observation decide.

## Why

The first idea is often not the best one, and comparing sketches costs far less than rewriting code.

## Self-check

- Do I have at least two candidates that differ in structure, not only in naming?
- Did I write down why the pick beats the other candidate?
- Did I settle each empirical question with a prototype instead of an argument?

Fix every no before you move on.

## Enforced by

G0 phase-artifacts. The SHAPE template requires two candidates for feature and refactor tasks, and G0 fails when one is missing.
