---
name: forge-verify-maintain
description: "Keep a project's verify skill and feature map honest after the app changes. Re-drive every mapped feature, fix drift in the map, report product regressions as regressions."
user-invocable: true
disable-model-invocation: true
---

# forge-verify-maintain

The feature map rots as the app changes. This skill re-runs it and separates two kinds of failure.

## Steps

1. Read `.agents/skills/verify-<app>/SKILL.md` and every file under `features/`. Run Doctor.
2. For each feature file, run its `## Drive` block. Record pass, fail, or could-not-run with the output.
3. Classify each failure:
   - Map drift: the app changed (a route moved, a label changed, a flag was renamed) and the journey is stale. Fix the feature file. Re-run. It must pass now.
   - Product regression: the journey is still correct and the app is wrong. Do not edit the map to hide it. Report it as a regression with the evidence, and stop; the fix is a separate bug task.
   - Environment: seed data or a dependency is missing. Note it in that feature's Gotchas and in the report.
4. Add feature files for user-facing features that have appeared since the last run (new routes, commands, menu items). Each new file is proven once before it is kept.
5. Record in the skill's SKILL.md the commit the map was last matched against.

## Report

Per feature: pass, drift fixed, regression found, or environment. Regressions listed first with their evidence paths. Never report a regression as fixed because the map was edited.
