### Opening a PR

Runs at the end of a task that produced a diff. Small ordered commits, evidence in the body, nothing merged.

1. Rebase the task's commits into small ordered units, each ending in a check (`sequence-verifiable-units`). A commit that only reverts an earlier one in the same task disappears.
2. Write `.forge/<id>/PR.md` from `report.md`: first line `# <title>`, then "For the consumer", "For the maintainer", "Verification" with log paths as `evidence:` pointers, and "Not done". No implementation narrative. Bugs paste failing-then-passing output.
3. `micro/unslop` on PR.md. `$FORGE_HOME/scripts/forge-verify.sh --task-dir .forge/<id> --phase report` runs G10 and G12 on it.
4. `$FORGE_HOME/scripts/forge-pr.sh open <base>` pushes the branch and runs `gh pr create` with PR.md as the body. It refuses when G10 or G12 fail.
5. Reply with the PR link as `https://github.com/<owner>/<repo>/pull/<number>` and the "Not done" list.

Never merge. Merging is a different decision.

**Reply:** the PR link and what is not done.
