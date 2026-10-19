---
name: minimize-reader-load
description: "Apply when writing or reviewing code that a reader must trace through several layers, or hold hidden state in mind, to understand."
disable-model-invocation: true
---

# Minimize reader load

## Rule

Count two costs: the layers between a question and its answer, and the state a reader must keep in mind. Inline wrappers that have one caller and adapters that have one implementation. Keep state as local as it can be. Prefer return values to mutation, locals to fields, and fields to globals.

## Why

A reader's working memory is small, and each extra layer or hidden variable spends it.

## Self-check

- Can a new reader find where a value comes from and what changes it in under a minute?
- Does every layer I added change the abstraction instead of passing calls through?
- Is each piece of mutable state at the narrowest scope that works?

Fix every no before you move on.

## Enforced by

Reviewer checklist. G3 diff-hygiene bans escape hatches such as `as any`, `@ts-ignore`, and `unwrap()` in non-test Rust.
