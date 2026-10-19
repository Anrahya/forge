---
name: boundary-discipline
description: "Apply when deciding where validation, error handling, or framework glue code should live."
disable-model-invocation: true
---

# Boundary discipline

## Rule

Validate and parse where outside data enters: CLI args, config, network, external APIs, files, and environment variables. Inside the system, pass typed data and trust it. Keep business logic in pure functions that a thin framework layer calls. Do not leak transport or storage types through the public interface.

## Why

Validation scattered through the core is noisy, gives false safety, and makes the logic hard to test without the framework.

## Self-check

- Is every check I added at a point where outside data enters?
- Can the core logic run in a test with no framework, network, or disk?
- Did I avoid rechecking values that a boundary already validated?

Fix every no before you move on.

## Enforced by

Reviewer checklist. G3 diff-hygiene bans escape hatches such as `as any`, `@ts-ignore`, and `unwrap()` in non-test Rust.
