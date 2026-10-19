---
name: forge
description: "Run an engineering task through forge: classify it, open its playbook, and drive it phase by phase with gates. Use for /forge <task>, 'forge this', or any task that needs rigor."
user-invocable: true
disable-model-invocation: true
---

# forge

You own the task. You do not write the code in this context. Each phase runs in a fresh context with file pointers, and you read its artifact when it returns. Read `AGENTS.md` now and cite only principles whose leaf you have read this session.

## 1. Intake

1. Run `micro/sharpen` and `micro/in-your-own-words` on the request. Write the restatement in the reply.
2. Classify the type. One of: `bug`, `feature`, `refactor`, `perf`, `investigate`, `research`, `chore`, `prototype`, `pr-review`. When two fit, take the narrower one. `/forge review <target>` is always `pr-review` and skips to its playbook, which creates the task dir itself. `/forge open pr` on a finished task runs the `opening-a-pr` playbook instead of a new task.
3. Create the task: `$FORGE_HOME/scripts/forge-task.sh new <slug>` prints the task id, creates `.forge/<id>/` from `$FORGE_HOME/templates/`, writes `.forge/current`, and sets `state.json` to `intake`.
4. Fill `task.md`. Acceptance criteria are commands with expected outcomes. If you cannot write one, that is stop condition S1: ask, with the specific criterion you could not make runnable.
5. Open the playbook at `playbooks/<type>.md`. Copy its steps into the todo list verbatim before any task-specific items. A step you skip stays in the list as `skip: <reason>`.

## 2. Phases by type

| Type | GROUND | SCOUT | SHAPE | BUILD | VERIFY | REVIEW | REPORT |
|---|---|---|---|---|---|---|---|
| bug | yes | no | no | yes | yes | yes | yes |
| feature | yes | yes | yes | yes | yes | yes | yes |
| refactor | yes | yes | yes | yes | yes | yes | yes |
| perf | yes | yes | yes | yes | yes | yes | yes |
| investigate | yes | no | no | no | no | no | yes |
| research | no | yes | no | no | yes | yes | yes |
| chore | yes | no | no | yes | yes | no | yes |
| prototype | yes | optional | no | yes (scratch) | no | no | yes |
| pr-review | light | no | no | no | yes | yes | yes |

`opening-a-pr` is not a type. It runs after any type that produced a diff, when the human asks for a PR.

## 3. Running a phase

For each required phase, in order:

1. `$FORGE_HOME/scripts/forge-task.sh phase <name>` updates `state.json`. The harness reads it for tool policy and the done-gate.
2. Spawn a fresh context for the phase with role `<name>` (DSH: `forge_spawn`; elsewhere: a subagent). The prompt is three pointers and nothing else: `AGENTS.md`, `skills/forge-<name>/SKILL.md`, and `.forge/<id>/`. Never inline the artifacts. Never pass this conversation.
3. When it returns, read the artifact it wrote. Run `$FORGE_HOME/scripts/forge-verify.sh --task-dir .forge/<id> --phase <name>`. On failure, re-spawn the same phase with `verify.log` as the one additional pointer. Do not fix the artifact yourself.
4. Log one row in `decisions.tsv` for the phase outcome.

BUILD and VERIFY loop until VERIFY passes. REVIEW's blocking findings send the task back to BUILD with `review.md` as the extra pointer. After the second REVIEW loop with blocking findings open, stop condition S4: stop, write the report with the findings open, ask.

## 4. Roles and models

`forge.toml` maps roles to models. The `review` role defaults to a different family than `build`. The `escalation` role is never spawned without the human's yes in this conversation. Frontier models, when approved, do SHAPE review or REVIEW. Never BUILD.

## 5. Questions

Before asking the human anything, classify the question. If a run could answer it (behavior, timing, output, whether an approach works), spawn a `prototype` and let the observation decide. Only product and preference calls reach the human. Stop conditions S1 to S5 in `AGENTS.md` are the only other places this pipeline stops.

## 6. The reply

After REPORT, reply with the report's "For the consumer" and "For the maintainer" sections, the verification summary with log paths, what is not done, and the principles applied with the decision each changed. Short declarative sentences. No em dashes. `micro/unslop` applies. Paste failing-then-passing output verbatim for bugs.
