### Refactor

Behavior-preserving. No feature work rides along.

1. GROUND. Record the behavior baseline before any change: run the tests and, when the surface allows, capture outputs or screenshots of the paths touched.
2. SCOUT only when the refactor introduces a pattern the repo does not have yet. Otherwise `skip: pattern exists in repo`.
3. SHAPE: the target structure and the migration order. Migrate every caller and delete the old path in the same change (`migrate-callers-then-delete-legacy-apis`). Subtract first (`subtract-before-you-add`).
4. BUILD in units that each leave the tests green. One unit per commit.
5. VERIFY: tests green, baseline outputs identical, G7 confirms the tests still need the implementation.
6. REVIEW with the question "what behavior could have changed?" as the first check.
7. REPORT, including the baseline comparison.

**Reply:** what moved, what was deleted, proof behavior held.
