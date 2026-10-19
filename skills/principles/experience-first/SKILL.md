---
name: experience-first
description: "Apply when a scope, UX, or API tradeoff sets what is easy to build against what the consumer of the work gets."
disable-model-invocation: true
---

# Experience first

## Rule

Choose the user's result over implementation convenience. The user is whoever consumes the work. That is the end user for a UI, the importing engineer for a library, and the next maintainer for all code. Ship fewer features that work well rather than more that work roughly. Get error states and feedback right, not only the happy path.

## Why

Users judge the result, and they never see how easy it was to build.

## Self-check

- Did I name who consumes this change?
- Did I check the error and empty states that this user will hit?
- Does every new option or control serve the main thing this user came to do?

Fix every no before you move on.

## Enforced by

Playbook only. No gate checks this, so the self-check above is the only guard.
