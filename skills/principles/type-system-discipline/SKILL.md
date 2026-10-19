---
name: type-system-discipline
description: "Apply when designing types, writing a function signature, or handling external data in a statically typed language."
disable-model-invocation: true
---

# Type system discipline

## Rule

Make illegal states impossible to represent. Give distinct meanings distinct types, such as `UserId` and `OrderId`, even when both are strings underneath. Treat external data as untyped until one parse function turns it into the model. Handle every variant of a union. Derive types from the schema that owns the shape instead of writing a parallel copy by hand.

## Why

The compiler checks a type on every build, while a runtime check only catches the cases a test happens to reach.

## Self-check

- Do the types reject every state the domain forbids?
- Does external data pass through one parse function before the rest of the code sees it?
- Will every switch over a union fail to compile when a new variant appears?

Fix every no before you move on.

## Enforced by

Reviewer checklist. G3 diff-hygiene bans `as any`, `@ts-ignore`, `unwrap()` and `expect()` in non-test Rust, and new `#[allow(` attributes.
