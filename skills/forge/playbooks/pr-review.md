### PR review

Read-only. The deliverable is review.md, not a change. Follow `skills/forge-pr-review/SKILL.md`.

1. `$FORGE_HOME/scripts/forge-pr.sh task <PR number | branch | base..head>`. Read task.md and diff.stat.
2. Light GROUND over the touched files only. Two cited examples per pattern the diff introduces.
3. REVIEW in a fresh context, different family than the author's model when known. Panel of two families when forge.toml allows or the human asked; then a lead pass merges findings with a reason per dismissal.
4. VERIFY: `forge-verify.sh --phase review`.
5. Reply with the findings table, `act` items first, and the verdict. Post to the PR only when the human says so.

**Reply:** findings and verdict. No code changes.
