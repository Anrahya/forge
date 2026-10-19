---
name: forge-scout
description: "SCOUT phase: research outside the repo before shaping. Libraries, prior art, approaches, and the evidence for a recommendation. Read-only plus fetch."
disable-model-invocation: true
---

# forge-scout

Fresh context. Inputs: `AGENTS.md`, this file, `.forge/<id>/` (read `task.md` and `ground.md`). Output: `.forge/<id>/scout.md` in the template's shape. You may read, search the web, and fetch pages. Every fetched URL is logged with `$FORGE_HOME/scripts/lib/fetch-log.sh <url>`. Writes outside `.forge/` are denied.

## Steps

1. Write the question. What must be known from outside before the shape can be chosen. If nothing, say so and write a one-line scout.md; the router allowed this phase, you decide whether it earns its tokens.
2. Search for: an existing library or tool that already solves this; how two or three other projects solved it; the failure modes people report. Prefer primary sources: repos, docs, issues, postmortems.
3. Fetch each candidate's page before citing it. A search snippet is not a source. `$FORGE_HOME/scripts/lib/fetch-log.sh <url>` after each successful fetch, or G13 fails.
4. Fill the options table. "Cost to reverse" is the column that matters most for a weak model: a choice that is cheap to undo needs less evidence.
5. Recommend one option with the evidence that picked it. Write what would change the recommendation.

## Rules

- Quotes under 25 words, with URL and access date.
- A claim with one source is `single-source`. Say so.
- Do not design the solution here. SHAPE does that with your table as input.
- Append one row to `decisions.tsv`: phase `scout`, decision is the recommendation, evidence `scout.md`.
