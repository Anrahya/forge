---
name: attack-the-premise
description: "Apply when two fixes that rest on the same assumption have both failed the same check."
disable-model-invocation: true
---

# Attack the premise

## Rule

Stop fixing. Write the assumption both fixes shared as one sentence. Then run an observation that would come out differently if that assumption were false. Follow what the run shows, not what the assumption predicts. If the run confirms the premise, ask the next why. If it refutes the premise, look for what the failures have in common.

## Why

Each failed fix is evidence against its premise, so a third fix on the same premise spends effort where the evidence says the cause is not.

## Self-check

- Is the shared premise written down as one sentence?
- Did I run a check that tests the premise directly, separate from any fix?
- Does my next fix follow from that check's result?

Fix every no before you move on.

## Enforced by

A bug playbook step. The decision log must show a premise row, with its test and result, before a third fix attempt.
