---
name: forge-correct
description: "Find the mistakes agents keep repeating in this repo and make each one impossible at the highest level that works: architecture, then types, then a lint whose error names the fix, then a test, docs last. Use for /forge-correct or after the same correction lands twice."
user-invocable: true
disable-model-invocation: true
---

# forge-correct

Assume every contributor is an agent that sees only the files it opened, copies the nearest example, and takes the shortest path that compiles. Change the repo so a change that looks right from one file is right for the whole repo. This is `encode-lessons-in-structure` applied to a codebase.

## 1. Find the mistake classes

Read recent commits, reverts, review comments, `review.md` files under `.forge/`, agent instruction files, and comments that explain workarounds. Group the mistakes. A class counts once it has happened twice.

## 2. Fix each class at the highest level that works

1. Architecture: give each piece of state one owner and each task one supported way. Hide internals so the wrong import fails. Delete the old way an agent would copy.
2. Types: make the bad state unrepresentable. If bad code still compiles, add a lint or a CI check whose error message names the file, type, or function to use instead. When the pattern is already common, fail only on new instances.
3. Tests: fix or delete any test that still passes when the behavior it checks breaks.
4. Docs and agent rules last, only for judgment calls, because nothing fails when an agent skips them.

## 3. Prove each check

Every new check must fail on a real past instance of the mistake. Run the same command locally and in CI. Exceptions go on the offending line with a reason, an expiry date, and a human's approval.

## 4. Keep the rule table

Maintain a table in AGENTS.md (the project's, not forge's) pairing each rule with what enforces it. When a human corrects an agent, add the rule. If the rule was already there with nothing enforcing it, that is a repeat: enforce it at the highest level in the same change. Drop a rule once its mistake cannot happen.

## Report

Each class with its evidence, the level chosen, and why a higher level did not work.
