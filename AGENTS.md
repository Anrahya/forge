# forge contract

forge is a verification-first engineering workflow. Rigor lives in gates and hooks, not in the model's memory. Read this file at the start of every step. It is short on purpose.

## The contract

1. A phase is done when its artifact exists in `.forge/<task>/` and its gates pass. Never say "done" without `verify.log` showing it.
2. Every claim carries its evidence or its label in the same sentence: a log path, a command and its output, or the word "guess".
3. Smallest change that solves the task. Match the two cited examples from `ground.md`. No new abstraction with one caller.
4. Name the data shape and its organizing structure before writing logic.
5. Check first when a cheap check exists. The check must fail before the change and pass after it.
6. Never edit gate scripts, test runner config, lint config, or CI config. If a gate looks wrong, report it (stop condition S5).
7. A question a run could answer is not the human's to answer. Prototype it. Ask only on product or preference calls.
8. Each reply names the principles that changed a decision and the decision each changed. A name with no decision behind it is a tell.
9. Prose follows `micro/unslop`. No em dashes, no AI vocabulary, no chatbot phrases.
10. Log decisions in `decisions.tsv` as they happen, one row each, evidence as a pointer.

## Where forge lives

`$FORGE_HOME` is the directory this plugin is installed in. The harness states it in every forge context message, and the skills use it for `$FORGE_HOME/scripts/forge-task.sh`, `$FORGE_HOME/scripts/forge-verify.sh`, and the templates. Project state is always under `.forge/` in the project, never under `$FORGE_HOME`.

## Phases

`INTAKE → GROUND → SCOUT → SHAPE → BUILD ⇄ VERIFY → REVIEW → REPORT`

The router (`skills/forge/SKILL.md`) picks the playbook and says which phases this task type needs. State for the current task is in `.forge/current` (the task id) and `.forge/<task>/state.json` (the current phase).

## Stop conditions

Stop and ask only here: S1 acceptance criteria cannot be made runnable. S2 no way to run the tests or the app. S3 the estimated diff is over twice the budget. S4 two review loops with blocking findings still open. S5 a gate seems wrong. Everything else proceeds.

## Principle index

Apply the ones the work triggers. Read the leaf at `skills/principles/<name>/SKILL.md` before citing it.

**Core**
- `laziness-protocol`: smallest change that solves it; prefer deleting to adding; one source of truth per decision.
- `foundational-thinking`: choose core types and data structures before logic; scaffold and checks before features.
- `redesign-from-first-principles`: integrate a new requirement as if it had been there from day one.
- `attack-the-premise`: two failed fixes that share a premise mean the premise is the suspect; write it down and test it directly.
- `subtract-before-you-add`: remove dead weight first, then build on the simpler base.
- `minimize-reader-load`: collapse layers, one-caller wrappers, and hidden state a reader must hold in their head.
- `outcome-oriented-execution`: converge on the target design; do not preserve throwaway compatibility states.
- `experience-first`: the user's result beats implementation convenience.
- `exhaust-the-design-space`: with no precedent, build two or three competing sketches and compare.
- `build-the-lever`: build the script that does or proves the work so a reviewer can rerun it.

**Architecture**
- `model-the-domain`: encode a repeated rule in one structure (state machine, table, typed model), not scattered conditionals.
- `boundary-discipline`: validate at the boundary, trust internal types, keep business logic pure.
- `type-system-discipline`: make illegal states unrepresentable; parse external data at the edge.
- `make-operations-idempotent`: retries and replays converge on the same end state.
- `migrate-callers-then-delete-legacy-apis`: migrate every caller and delete the old API in one wave.
- `separate-before-serializing-shared-state`: remove the sharing before adding locks or coordination.

**Verification**
- `prove-it-works`: verify the real artifact, not a proxy, a self-report, or "it compiles".
- `fix-root-causes`: reproduce, trace to the first place the system went wrong, fix there.
- `sequence-verifiable-units`: each small unit ends in a check before the next starts.
- `test-behavior-not-implementation`: assert what users observe; the test fails when behavior breaks and survives internal change.
- `explain-the-number`: name what limits a measured number and rule out that it measured something else.

**Delegation**
- `guard-the-context-window`: route bulk reading to subagents; keep findings, not payloads, in the main thread.
- `never-block-on-the-human`: proceed on reversible work; ask only on product or preference calls.

**Meta**
- `encode-lessons-in-structure`: advice repeated twice becomes a lint, a check, or a script.
