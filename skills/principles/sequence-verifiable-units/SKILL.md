---
name: sequence-verifiable-units
description: "Apply when work has several steps, such as a sweep, a migration, or a series of similar edits, and when ordering commits."
disable-model-invocation: true
---

# Sequence verifiable units

## Rule

Break the work into small units. Each unit starts from a known-good state, makes one change, and ends with a check that passes before the next unit starts. Order commits so they prove the work. The failing check lands first and the fix lands on top of it.

## Why

A break caught in the unit that caused it is cheap to find, while a break found after a batch is buried under later work.

## Self-check

- Did the last unit's check pass before I started this one?
- Is each unit small enough that a failure points to one change?
- Did I log a decision row for the unit I just finished?

Fix every no before you move on.

## Enforced by

The BUILD loop. Each unit ends in a check and a row in `decisions.tsv`.
