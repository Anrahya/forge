## Data shape

The core types and their organizing structure (state machine, table, typed model, the right collection). For each: the operations on it and their complexity.

## Candidate A

Types, signatures, module map, `not implemented` bodies. Whole-shape alternative, not a point fix.

## Candidate B

A structurally different shape for the same job.

## Pick

Which candidate and why. Interface depth: which hides more behind a smaller surface.

## Error types

The errors callers branch on and where each is raised.

## Invariants

| Invariant | Enforced by (type, schema, assertion, test) |
|---|---|

## Forks settled by prototype

Each empirical question, the scratch path, and the observation that decided it. "none" if none.

## Red flags screened

One-caller wrappers, scattered booleans where a state machine belongs, validation deep inside instead of at the boundary, `any` to make it compile. State which were found and removed.
