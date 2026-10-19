---
name: forge-build
description: "BUILD phase: implement against the shape in small verifiable units with a hypothesis loop. Check first when cheap, smallest change, log every decision. Never touch referee paths."
disable-model-invocation: true
---

# forge-build

Fresh context. Inputs: `AGENTS.md`, this file, `.forge/<id>/` (read `task.md`, `ground.md`, `shape.md`, and `verify.log` or `review.md` when present). Output: the diff, `red.log` and `green.log` via the test helper, one `decisions.tsv` row per unit. Writes to gate scripts, test runner config, lint config, CI config are denied; if you believe one is wrong, write it in decisions.tsv as result `S5` and stop.

## The loop

For each unit of work, in this order:

1. State the hypothesis as one line: "after this change, `<check>` passes."
2. If a cheap test path exists, write the test first and run `$FORGE_HOME/scripts/lib/run-tests.sh --task-dir .forge/<id> --log red`. It must fail for the intended reason. If it passes, the test is wrong; fix the test, not the code. If no cheap path exists, name the closest executable check and use that (`micro/tdd`).
3. Make the smallest change that satisfies the hypothesis. Match the two cited examples in ground.md for naming, error style, and structure.
4. Run `$FORGE_HOME/scripts/lib/run-tests.sh --task-dir .forge/<id> --log green`.
5. Verdict: `VERIFIED` (check passes, nothing else broke), `NOT VERIFIED` (revert the change), or `INCONCLUSIVE` (could not run the check; say why; this is not a pass).
6. Append the decision row: what, why, evidence (log path or commit), result. Commit the unit.

Repeat. When `verify.log` is present, its failing gate is the first unit.

## Rules

- No TODO, no skipped test, no commented-out code, no `as any`, no `@ts-ignore`, no `unwrap()` outside tests, no empty catch. G3 will reject the diff and the time is wasted.
- No new abstraction with one caller (`laziness-protocol`). No drive-by refactor of lines the task does not need.
- Comments only for a non-obvious why. Never phase narration.
- When the shape keeps fighting you (the same workaround in two places, a cast to compile), stop and write result `shape-wrong` in decisions.tsv with the evidence. The router re-runs SHAPE.
- Stay under the budget in task.md. At twice the budget, stop: S3.
- Do not write report.md. REPORT does that from your log.
