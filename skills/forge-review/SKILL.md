---
name: forge-review
description: "REVIEW phase: adversarial review in a fresh context. Spec compliance first, then quality. Blocking findings need a demonstration. No writes."
disable-model-invocation: true
---

# forge-review

Fresh context, ideally a different model family than BUILD. Inputs: `AGENTS.md`, this file, and from `.forge/<id>/` only `task.md`, `shape.md`, `verify.log`, plus the diff (`git diff <base>...HEAD`). Do not read ground.md, scout.md, or decisions.tsv; you are meant to come in cold. Output: `.forge/<id>/review.md`. All other writes are denied.

Your job is to find the reason this should not merge. Agreement is not the default.

## Pass 1: spec compliance

For each acceptance criterion in task.md, name the check that covers it or write "not covered". Then list everything the diff does that task.md did not ask for. Scope creep is a `should` finding; a missed criterion is `blocking`.

## Pass 2: quality

Work through each question. A `blocking` finding needs a demonstration: an input, a command, or a file:line that shows the problem. Unease without a demonstration is a `nit`.

- For each new or changed test: which implementation change would it fail to catch? Which branch and which error path has no check?
- Does added code duplicate something that already exists nearby? Grep for it.
- Do naming, error style, and structure match the surrounding code?
- Is the data structure the one shape.md chose? Any list where a map or set belongs? Any quadratic loop?
- What input breaks it: empty, huge, unicode, concurrent, null, negative, out of order?
- What happens when the dependency is down, the retry overlaps, the write is partial?
- Any new abstraction with one caller? Any one-caller wrapper?
- Any error swallowed, logged and ignored, or turned into a default value?
- Any comment that narrates instead of explaining a non-obvious why?
- Would a senior engineer on this codebase accept this without comment?

## Output

Fill review.md. Each finding gets a disposition: `act`, `consider`, `noted`, or `dismissed` with a reason. With zero findings, write what you tried and why nothing turned up. End with the verdict: `merge`, `fix then merge`, or `redo`.

Append one row to `decisions.tsv`: phase `review`, decision is the verdict, evidence `review.md`.
