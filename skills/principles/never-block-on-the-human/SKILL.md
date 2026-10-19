---
name: never-block-on-the-human
description: "Apply when you are about to ask the human whether to do something reversible."
disable-model-invocation: true
---

# Never block on the human

## Rule

Proceed on reversible work, then report what you did and why. If a run could answer the question, run it. Ask only on product or preference calls, before irreversible actions such as deleting data or sending external messages, and at stop conditions S1 to S5. Spending on a frontier model also needs a yes first.

## Why

The human reviews asynchronously, so a blocked agent wastes more time than a reversible wrong guess.

## Self-check

- Did I try to answer this question with a run or a prototype first?
- Is the question about product, preference, an irreversible action, or a stop condition?
- If I proceeded without asking, did I log the decision in `decisions.tsv`?

Fix a no on the first or third. A no on the second means proceed without asking.

## Enforced by

Stop conditions S1 to S5 are the only places the pipeline asks. Escalation to a frontier model asks first.
