---
name: forge-shape
description: "SHAPE phase: settle the data shape, types, signatures, and boundaries before any logic. Two candidates, one pick, forks settled by prototype. Not an implementation plan."
disable-model-invocation: true
---

# forge-shape

Fresh context. Inputs: `AGENTS.md`, this file, `.forge/<id>/` (read `task.md`, `ground.md`, `scout.md`). Output: `.forge/<id>/shape.md` in the template's shape. You may write sketches and prototypes under `.forge/<id>/scratch/` only. Source writes are denied.

## Steps

1. Name the data shape first (`foundational-thinking`, `model-the-domain`). What are the core types, what organizes them (state machine, table, typed model, the right collection), what operations run on them, what is each operation's complexity. If you cannot name the shape, you are not ready to sketch.
2. Sketch Candidate A: types, function signatures, module map, bodies as `not implemented`. Write the caller's usage first, then the types that make that usage work.
3. Sketch Candidate B. A structurally different whole shape, not a variant of A (`exhaust-the-design-space`). If you cannot find a second shape, say what you tried.
4. Screen both against the red flags: one-caller wrappers, scattered booleans where a state machine belongs, validation deep inside instead of at the boundary, a cast or `any` needed to compile. Remove or note each.
5. Pick on interface depth: the candidate that hides more behind a smaller public surface wins unless scout.md's evidence says otherwise.
6. List the error types callers branch on and where each is raised (`boundary-discipline`). List the invariants and where each lives (`type-system-discipline`).
7. Any fork a run could settle (does this API behave like that, is this fast enough, does this layout work) gets a prototype in `scratch/`. Record the observation in shape.md. Do not ask the human what an experiment can answer.

## Rules

- No step-by-step implementation plan. The sketch is the contract; BUILD discovers the steps.
- Keep the sketch compilable in spirit: real type names from ground.md, real module paths.
- When BUILD later reports the sketch keeps fighting the code, the shape is wrong. Expect to be re-run.
- Append one row to `decisions.tsv`: phase `shape`, decision is the pick, evidence `shape.md`.
