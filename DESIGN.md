# forge: a verification-first engineering workflow for non-frontier models

Version 2, 2026-10-20. Target harness: DeepSeek Harness (DSH) first. The portable core (skills, gate scripts, AGENTS.md) reuses in Claude Code, OpenCode, Codex.

Lineage: the discipline is pstack's (Lauren Tan, `cursor/plugins/pstack`, read at 0.15.28). Superpowers contributes the fresh-subagent two-pass review. forge's own contribution is enforcement: every rule that can be a gate is a gate, because a weak model agrees with principles and then ignores them.

## 0. Thesis

Slop has four causes. A workflow that addresses one still produces slop.

| Cause | Looks like | Counter |
|---|---|---|
| The model does not know what good looks like *here* | Invented conventions, wrong abstractions, duplicate helpers | GROUND: build a mental model and cite existing examples before writing |
| The model does not know what good looks like *anywhere* | Reinvents a library, picks the wrong approach, ignores prior art | SCOUT: research the outside world before shaping |
| Nothing forces it to check | "Tests pass" with no run, "verified" with no artifact | Gates that read logs, not claims; a turn cannot end as "done" until gates pass |
| Context decay and reward for looking done | Drifts after 20k tokens; skips tests, leaves TODOs, swallows errors | Short file-to-file phases, playbook re-injected per step, diff hygiene gates, adversarial review |

## 1. Research is not planning

pstack ships no planning skill on purpose, and this design agrees. A written implementation plan is a guess that code contradicts within the hour. What is worth doing before code:

- **Ground** (pstack `how`): how does the affected subsystem work today, where do things live, what are the gotchas. Read-only. Output is an explanation a senior engineer onboarding would want, not a step list.
- **Scout**: what exists outside the repo. Libraries that already solve this, how others solved it, the tech-stack options, the reasons prior attempts failed. Output is a short options table with a recommendation and the evidence for it.
- **Shape** (pstack `architect`): the data shape and its organizing structure (state machine, table, typed model, the right collection), types and signatures with `not implemented` bodies, module boundaries, error types callers branch on. Two structurally distinct candidates before picking one. Not a sequence of edits.
- **Prototype** instead of debating: any fork a run could settle (behavior, timing, layout, whether an approach works) gets a throwaway sketch in a scratch dir, and the observation decides. Questions go to the human only for product or preference calls no experiment can settle.

The sketch is a contract, not a plan. When implementation keeps fighting it (the same workaround in unrelated places, `any` casts to make it compile), that is evidence the shape is wrong, and the shape gets redone rather than patched.

## 2. Principles: cover every base, drown nobody

pstack's 24 principles are adopted as-is in spirit (names kept so the vocabulary transfers). The mechanism for weak models is the split pstack already uses:

- **Index always on.** One line per principle, about 600 tokens total, in AGENTS.md so every phase sees it. The reply to each phase names the principles that changed a decision and what the decision was. A citation with no decision behind it is a tell the reviewer flags.
- **Leaf on demand.** The full rule (50 to 450 words in pstack) loads only when the phase playbook or the model's own index lookup needs it.
- **Gate where possible.** Each principle below maps to its enforcement. "Playbook" means instruction only, which is the weakest tier.

| Principle | Enforcement |
|---|---|
| Laziness Protocol (smallest change, bias to deletion) | G5 diff budget; reviewer spec pass |
| Foundational Thinking / Model the Domain (data shape first) | SHAPE template requires the data shape and structure section before BUILD unlocks |
| Exhaust the Design Space (two candidates) | SHAPE template requires two candidates for feature/refactor |
| Attack the Premise (two failed fixes share a premise) | Bug playbook step; decision log shows the premise row before the third attempt |
| Subtract Before You Add; Migrate Callers Then Delete | Reviewer checklist; G3 flags new code beside deprecated siblings |
| Minimize Reader Load; Boundary Discipline; Type System Discipline | Reviewer checklist; G3 bans `as any`, `@ts-ignore`, `unwrap()` in non-test Rust |
| Make Operations Idempotent; Separate Before Serializing | Reviewer checklist for anything with retries or shared writes |
| Prove It Works | G2, G9, G10, and the turn-stopping gate |
| Fix Root Causes | Bug playbook: no fix without reproduction and a traced mechanism; G1 red-proof |
| Sequence Work into Verifiable Units | BUILD loop: each unit ends in a check and a decision-log row |
| Test Behavior, Not Implementation | G7 tests-need-impl; G8 test heuristics |
| Explain the Number | Perf playbook runs the seven benchmark questions before any number is reported |
| Guard the Context Window | Phase budget; file-only handoff; bulk reads delegated |
| Never Block on the Human | Stop conditions are the only places the pipeline asks |
| Build the Lever; Encode Lessons in Structure | `forge-correct` turns repeated corrections into gates; proof artifacts are scripts a reviewer reruns |
| Experience First; Outcome-Oriented Execution; Redesign from First Principles | Playbook only |

The micro-skills are cheap and stay: `sharpen` (how would an expert do this, what is the user after, what is over/under-specified), `in-your-own-words` (restate the goal before INTAKE commits), `unslop` (AI-tell removal on every prose surface), `bro` (plain restatement on demand), `tdd`, `benchmark-checklist`, `blast-radius`.

## 3. Pipeline

One entry: `/forge <task>`. State lives in `.forge/<task-id>/`. Phases pass artifacts, never conversation. Each phase runs in a fresh context where the harness allows it.

```
INTAKE → GROUND → SCOUT → SHAPE → BUILD ⇄ VERIFY → REVIEW → REPORT
                  (skip for bug/chore)  (loop)       (loop ≤2, then stop condition)
```

**INTAKE.** `sharpen` and `in-your-own-words` first. Classify: `bug | feature | refactor | investigate | perf | research | chore`. Write `task.md`: goal, acceptance criteria as runnable checks (command plus expected outcome), non-goals, diff budget, required phases. Bugs add: reproduction command (or "none yet, GROUND must produce one"). Unrunnable acceptance criteria is stop condition S1.

**GROUND.** Read-only. `ground.md`: overview, key concepts, how it works, where things live, gotchas, test and lint commands, two cited examples per pattern about to be used (or "none found"). For bugs: the reproduction running and failing, captured to `repro.log`.

**SCOUT.** Required for feature, refactor, perf, research. `scout.md`: the question, candidates found (libraries, prior art, approaches) each with a fetched source, an options table with tradeoffs, a recommendation, and what would change it. Claims cite fetched pages, not search snippets (G13).

**SHAPE.** Required for feature, refactor, perf. `shape.md`: data shape and organizing structure with the operations and their complexity; two candidate sketches (types, signatures, `not implemented` bodies, module map); the pick and why; error types callers branch on; invariants and where each lives (type, schema, assertion, test); open forks settled by prototype with the observation attached. Design red flags screened: one-caller wrappers, scattered booleans where a state machine belongs, validation deep inside instead of at the boundary.

**BUILD.** The hypothesis loop from pstack's figure-it-out. Each unit: state what this change should make true, write the check first when cheap (red captured to `red.log`), make the smallest change, run the check, log one decision row, commit. Verdicts are `VERIFIED | NOT VERIFIED | INCONCLUSIVE`. Inconclusive is not a pass. A refuted hypothesis gets reverted, not kept as belt-and-suspenders. Tool policy: no writes to gate scripts, test config, lint config, CI config.

**VERIFY.** All gates, scripted, no model judgment. Runtime verification goes through the project's verify skill (section 5). Output `verify.log`. Failure returns to BUILD with the gate's message as the only new input.

**REVIEW.** Fresh context, different model family when configured, sees only the diff, `task.md`, `shape.md`, and `verify.log`. Pass 1 spec compliance: exactly task.md, each acceptance criterion covered by a check. Pass 2 quality: the checklist in section 4. `review.md` findings carry severity, file:line, reason, and for `blocking` a demonstration. Sorted into `act | consider | noted | dismissed` with a reason per dismissal. Zero findings must say what was tried. Blocking loops to BUILD; after two loops, S4.

**REPORT.** `report.md` plus `decisions.tsv`. What changed, for whom (the consumer, then the maintainer), evidence link per claim, what is not done, risks, principles applied with the decision each changed. `unslop` runs on it; G12 lints it.

### Per-type playbooks (one page each)
- **Bug**: reproduce on the real surface, binary-search hypotheses with runtime evidence, attack the premise after two failed fixes, fix the mechanism not the symptom, repro passes, failing check lands before the fix in history.
- **Feature**: full pipeline.
- **Refactor**: behavior-preserving; baseline captured before any change; G7 plus a behavior snapshot diff; no feature work mixed in.
- **Perf**: baseline, profile, hypothesis loop, benchmark checklist, report median and range and the limiter.
- **Investigate**: GROUND only, output the `how`-shaped explanation or a tradeoffs table. No code.
- **Research**: SCOUT as the main phase; claims-first (section 8).
- **Chore**: INTAKE, BUILD, VERIFY. No SHAPE, no SCOUT.
- **Prototype**: the one playbook where quality rules invert. Scratch dir, no tests, throwaway, decision plus observation is the deliverable.

## 4. Reviewer checklist

The reviewer's job is to find the reason this should not merge. For each item, a `blocking` finding needs a demonstration (input, command, line). Unsubstantiated unease is `nit`.

- For each test, which implementation change would it fail to catch? Which branch and which error path has no check?
- Does added code duplicate something `ground.md` found?
- Do naming, error style, and structure match the two cited examples?
- Is the data structure the one `shape.md` chose? Any list where a map or set belongs, any O(n²) hiding in a loop?
- What input breaks it: empty, huge, unicode, concurrent, null, negative, out of order?
- What happens when the dependency is down, the retry overlaps, the write is partial?
- Does the diff do anything `task.md` did not ask for? Any new abstraction with one caller?
- Any error swallowed, logged and ignored, or turned into a default?
- Any comment that narrates instead of explaining a non-obvious why?
- Would a senior engineer on this codebase accept this without comment?

## 5. Verification against the real artifact

"It compiles" and "tests pass" are proxies. pstack's `create-verification-skill` is adopted as `forge-verify-setup`: it interviews the repo (surface, launch command, how to drive it, what evidence to capture, whether two instances can coexist) and writes a project-local skill `verify-<app>/` with Launch, Doctor, Drive, Evidence, Cleanup, Helpers sections and a feature map (one file per user-facing feature: how to reach it, how to drive it, what observable end state proves it). The generator runs its own instructions once before handing over. G9 runs the declared feature journeys for anything task.md marks as having a runnable surface. `forge-verify-maintain` keeps the map honest as the app changes.

## 6. Gates

Each gate is `scripts/gates/gNN-name.sh`, exit 0/1, with a one-paragraph reason on failure fed back to the model verbatim. Language detection by lockfile. Unsupported language: skip with a warning, never silently pass.

| Gate | Checks | Fails when |
|---|---|---|
| G0 phase-artifacts | Required template sections of the current phase are non-empty | Missing section; SHAPE without two candidates on feature/refactor |
| G1 red-proof | `red.log` exists for the unit, exit≠0, failing test names listed | Check passed before the change, or no log, when a cheap test path was declared |
| G2 green-after-edit | Test run exit 0 and log newer than newest mtime in the diff | Stale log or failing tests |
| G3 diff-hygiene | Banned patterns in added lines per language | `TODO`, `FIXME`, `.skip(`, `xit(`, `.only(`, `as any`, `@ts-ignore`, new `eslint-disable`, `console.log` in non-test src, `unwrap()`/`expect()` in non-test Rust, new `#[allow(`, empty `catch {}`, commented-out code blocks, phase-narrating comments |
| G4 scope | Files in diff outside `ground.md`'s touched list are flagged to the reviewer; files under task.md non-goals block | Non-goal path touched |
| G5 diff-budget | Added+removed ≤ budget | bug 150, feature 600, refactor 400, chore 100, perf/investigate as feature |
| G6 static | Lint, typecheck, format check | Any non-zero |
| G7 tests-need-impl | Stash non-test changes, run tests, expect failure, restore | Tests pass without the implementation |
| G8 test-quality | Static heuristics on new tests | Zero assertions; `expect(true)`; mock target equals module under test; expected value computed by calling the code under test; snapshot-only for logic |
| G9 runtime | Feature journeys from the verify skill for the declared surface | Journey fails, inconclusive, or evidence artifact missing after cleanup |
| G10 evidence-integrity | Every evidence pointer in `report.md` and `decisions.tsv` resolves and is newer than the last edit | Dangling or stale pointer |
| G11 referee-readonly | Writes to `scripts/gates/**`, test runner config, lint config, CI config, `.forge/**/verify.log` | Any attempted write by the agent |
| G12 unslop-lint | Report and PR prose | Rule 7 vocabulary, em dashes, "not just X but Y", chatbot phrases, inline-header lists |
| G13 sources-fetched | SCOUT and research claims | A cited URL with no fetch record |

G7 is the keystone. It kills the most common weak-model failure: tests that assert a mock was called and pass regardless of the implementation.

## 7. Weak-model countermeasures

- **Phase budget** under about 30k tokens. Handoff is file-only. The phase playbook and principle index are re-injected at every step, not just at phase start, so drift resets.
- **Templates over prose.** Every artifact has required headings; G0 parses them.
- **Checklists over essays.** Each playbook is one page.
- **Tool policy per phase**, enforced by the harness where possible: GROUND and SCOUT are read-only plus fetch; BUILD cannot touch referee paths; REVIEW cannot write at all.
- **No "done" without gates.** The harness's end-of-turn checkpoint runs the current phase's gates and feeds a failure back as the next step instead of letting the turn end.
- **Classify before asking.** If a question is answerable by running something, prototype. Only product or preference calls reach the human.
- **Stop conditions**: S1 acceptance criteria not runnable; S2 no way to run tests or the app; S3 estimated diff over 2x budget; S4 two review loops with blocking findings open; S5 the model believes a gate is wrong (it reports, never edits).
- **Escalation ladder**: same cheap model, fresh context → different cheap family for review → stop and ask before any frontier spend. Frontier, when approved, does SHAPE review or REVIEW only. Never implementation.
- **Decision log** (`decisions.tsv`, pstack show-me-your-work format): one row per decision with ts, phase, decision, why, evidence pointer, result. Append-only. The audit trail is how a human trusts unattended work.

## 8. Research variant

SCOUT is the main phase. Claims-first: list the claims the answer needs, each `unverified`. For each, fetch a source and attach a quote under 25 words with URL and access date. Seek at least one source that contradicts the main claim. Label each claim `confirmed | single-source | contested`. G13 enforces fetch records. REVIEW asks for the strongest case against the answer.

## 9. Measuring whether it works

- Per-task `metrics.json`: gate failures by gate, review loops, escalations, tokens per phase, wall time.
- An eval set of 20 to 30 tasks with hidden reference outcomes (real bugs with the fix hidden, features with a hidden test suite). Run the cheap model bare vs. with forge. Compare pass rate, diff size, blocking findings. Re-run on every gate or playbook change.
- Post-merge defects per task type. A leaked bug tightens the gate that should have caught it, not the prompt. That is `forge-correct`: find the mistake classes agents repeat in this repo, fix each at the highest level that works (architecture, then types, then a lint whose error names the fix, then a test, docs last), prove each check fails on a real past mistake.

## 10. DSH adapter

DSH is a Cordis plugin host. Verified against `deepseek-ai/deepseek-harness` master docs on 2026-10-20 (`docs/agent-lifecycle.md`, `docs/tool-execution-pipeline.md`, `docs/cordis-primer.md`) and the existing port `aa2246740/pstack-dsh` (pinned to DSH 0.2.0-rc.2, MIT). The port's HARNESS.md is the best field guide to the subagent API and is reused as reference.

What the adapter registers, each as a reversible `ctx.effect()`:

| forge need | DSH hook | Behavior |
|---|---|---|
| Per-phase tool policy, G11 | `tools/pre-execute` waterfall | Deny with the reason when the tool or path is outside the current phase's policy, read from `.forge/<task>/state.json` |
| Playbook and principle re-injection | `agent/pre-step` waterfall | Enter the current phase playbook and the principle index as messages each step |
| No "done" without gates | `agent/turn-stopping` serial checkpoint | Run the phase's gates; on failure, queue the gate output as the next step instead of letting the turn end |
| Per-role model and effort | `agent/request` waterfall | Route reviewer and escalation roles to configured models; `LlmCallConfig.reasoningEffort` only from ids the route lists |
| Fresh-context phases and reviewer | `ctx.subagents.start` with `agentOptions { provider, model }` via a `forge_spawn` tool | Model-facing `subagent` only takes description, prompt, run_in_background, so a plugin tool carries the role |
| Skills | `.agents/skills/**/SKILL.md`, frontmatter `name` kebab-case, `description`, `whenToUse`, `disable-model-invocation`, `user-invocable` | Portable layer, unchanged |
| Settings | `settings.section` slot | Role to model mapping, budgets |
| Install | `dsh plugin --profile web add github:<owner>/forge` or Desktop Settings → Plugins | Ships built `lib/` |

Phase 1 ships pre-execute policy, turn-stopping gates, pre-step injection, and `forge_spawn`. Settings UI and `agent/request` effort mapping come after the eval loop shows the pipeline works. Nothing in pstack-dsh's plumbing is copied without reading it first; its subagent and overlay code is the reference for the Cordis calls.

## 11. Repo layout

```
forge/
  AGENTS.md                       # contract + principle index (always on)
  skills/                         # Agent Skills format, portable
    forge/SKILL.md                # router: INTAKE, phase runner
    forge/playbooks/{bug,feature,refactor,perf,investigate,research,chore,prototype}.md
    forge-ground/  forge-scout/  forge-shape/  forge-build/  forge-review/  forge-report/
    forge-verify-setup/  forge-verify-maintain/  forge-correct/
    principles/<24 leaves>/SKILL.md
    micro/{sharpen,in-your-own-words,unslop,bro,tdd,benchmark-checklist,blast-radius}/SKILL.md
  templates/{task,ground,scout,shape,review,report}.md, decisions.tsv
  scripts/gates/g00..g13*.sh, scripts/lib/{detect-lang,run-tests,diff-stats,fetch-log}.sh
  adapters/dsh/                   # Cordis plugin: src/index.ts, cordis.yml, package.json
  adapters/claude-code/           # hooks.json, plugin.json
  evals/                          # task set + runner
  forge.toml                      # roles, budgets, families
```

## 12. Decisions (settled 2026-10-20)

1. Diff budgets: bug 150, feature 600, refactor 400, chore 100; perf and investigate use feature.
2. Languages first: TypeScript/JavaScript and Rust. Others skip with a warning.
3. Escalation: ask first. No frontier spend without a yes.
4. SHAPE required for feature, refactor, perf. Bugs need a reproduction and traced mechanism instead.
5. No implementation-plan phase. GROUND, SCOUT, and SHAPE replace it; prototypes settle empirical forks.
6. DSH hooks are real and first-class (verified against the docs above). Tool policy and the done-gate are enforced in the harness, not by instruction.
7. pstack's 24 principle names are kept so the vocabulary transfers between tools.

## 13. What this does not solve

Architectural taste on large designs (frontier SHAPE review when approved). Novel algorithms. Naming and prose will be mediocre; `unslop` and the reviewer help, they do not fix it. A model can still write a test and a trivially satisfying implementation; G7, G8, the spec pass, and the eval set are the defense, and the eval set is how you find out when they are not enough.
