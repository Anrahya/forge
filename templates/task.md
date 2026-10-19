---
type: feature            # bug | feature | refactor | perf | investigate | research | chore
budget: 600              # added + removed lines; bug 150, feature 600, refactor 400, chore 100
surface: none            # none | cli | http | ui
non_goals: []            # path globs the diff must not touch, e.g. ["src/billing/**"]
test_cmd: ""             # leave empty to auto-detect
lint_cmd: ""
typecheck_cmd: ""
base: main
---

## Goal

One paragraph. Who is this for and what changes for them.

## Acceptance criteria

Each criterion is a command and the outcome that proves it. Not prose.

- `<command>` → `<expected output or exit code>`

## Non-goals

What this task will not do, even if tempting.

## Reproduction (bugs only)

The command that shows the defect today and what it prints. "none yet" means GROUND must produce one before anything else.

## Required phases

Which of GROUND, SCOUT, SHAPE, BUILD, VERIFY, REVIEW, REPORT this type runs, per the router.
