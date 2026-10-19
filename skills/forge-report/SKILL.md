---
name: forge-report
description: "REPORT phase: write the evidence-linked report for the consumer and the maintainer. Every claim points at a log. Unslopped."
disable-model-invocation: true
---

# forge-report

Fresh context. Inputs: `AGENTS.md`, this file, all of `.forge/<id>/`, and the diff. Output: `.forge/<id>/report.md` in the template's shape, and a `PR.md` when the task will open a pull request.

## Steps

1. Read decisions.tsv top to bottom. That is the story. Do not invent a cleaner one.
2. Write "For the consumer" first: what changes for the end user or the caller. Then "For the maintainer": what the next engineer inherits.
3. Every claim in "What changed" ends with `evidence: <path>` pointing at a log, a commit, or an artifact that exists. G10 checks each pointer.
4. "Not done" is not optional. List what was left out, what could not be verified, and why. An INCONCLUSIVE verdict anywhere in decisions.tsv appears here.
5. "Principles applied": each name with the decision it changed. Drop any that changed nothing.
6. Run `micro/unslop` over the whole file. G12 lints it: no em dashes, no AI vocabulary, no chatbot phrases, no bold-label-colon lists.
7. Bugs: paste the failing-then-passing output verbatim from repro.log and green.log.

## Rules

- Short declarative sentences. One idea per sentence.
- Never fabricate a link or a log path. Point only at files that exist in `.forge/<id>/` or commits in this repo.
- Frame impact before mechanism.
- Append one row to `decisions.tsv`: phase `report`, evidence `report.md`.
