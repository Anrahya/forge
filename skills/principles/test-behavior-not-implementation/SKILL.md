---
name: test-behavior-not-implementation
description: "Apply when you write, change, or decide to keep a test."
disable-model-invocation: true
---

# Test behavior, not implementation

## Rule

Assert what the code's users can observe. That means return values, errors, state they can read back, and effects outside the code such as a request sent or a row written. Do not assert private helpers, internal call order, or which collaborator did the work. Derive expected values from the requirement, never from a run of the code under test.

## Why

A test pinned to internals breaks on every refactor and still misses real bugs.

## Self-check

- If I broke the behavior, would this test fail?
- If I restructured the internals and kept the behavior, would this test still pass?
- Did I mock only things outside the module under test?

Fix every no before you move on.

## Enforced by

G7 tests-need-impl fails when the tests pass with the implementation stashed. G8 test-quality fails on zero assertions, `expect(true)`, a mock of the module under test, expected values computed by that module, and snapshot-only logic tests.
