---
name: laziness-protocol
description: "Apply when choosing how much code to write, when tempted to add a layer or helper, or when the diff grows past what the task needs."
disable-model-invocation: true
---

# Laziness protocol

## Rule

Make the smallest change that solves the task. Prefer deleting code to adding it. Make each decision in one place and pass the result along instead of repeating the choice.

## Why

Every added line is code a reviewer must read and every later change must work around.

## Self-check

- Is this the smallest diff that passes the acceptance checks?
- Does every new helper, flag, or layer have a second caller or a stated need in `task.md`?
- Is each decision made in exactly one place?

Fix every no before you move on.

## Enforced by

G5 diff-budget fails when added plus removed lines pass the task budget. The budgets are bug 150, feature 600, refactor 400, and chore 100. The reviewer spec pass flags anything `task.md` did not ask for.
