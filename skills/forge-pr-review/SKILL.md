---
name: forge-pr-review
description: "Review an arbitrary pull request, branch, or base..head range with forge's adversarial two-pass review, optionally as a two-family panel. Use for /forge review <target> or 'review this PR'."
user-invocable: true
disable-model-invocation: true
---

# forge-pr-review

You own the review. You do not write code. Nothing is posted to GitHub unless the human says so.

## 1. Resolve the target

`$FORGE_HOME/scripts/forge-pr.sh task <target>` where target is a PR number, a branch, or `base..head`. It creates `.forge/<id>/` with `task.md` synthesized from the PR title and body (acceptance criteria marked `inferred`), `pr.json`, `diff.patch`, `diff.stat`, and sets the phase to `ground`. Read `task.md` and `diff.stat`.

## 2. Light GROUND

Spawn the `ground` role with pointers to `AGENTS.md`, `skills/forge-ground/SKILL.md`, and `.forge/<id>/`, plus one instruction: ground only the files in `diff.stat`, cite two existing examples for each pattern the diff introduces, and skip the reproduction section. When it returns, run `$FORGE_HOME/scripts/forge-verify.sh --task-dir .forge/<id> --phase ground`.

## 3. Review

`$FORGE_HOME/scripts/forge-task.sh phase review`. Then:

- **Single reviewer** (default): spawn the `review` role with pointers to `AGENTS.md`, `skills/forge-review/SKILL.md`, `.forge/<id>/`, and the range from `$FORGE_HOME/scripts/forge-pr.sh range`. The reviewer reads `task.md`, `diff.patch`, and `ground.md`, and treats every `inferred` criterion as a claim to check, not a fact.
- **Panel** (when `forge.toml` maps `review` to two or more families, or the human asked for a panel): spawn two reviewers. The first is `forge_spawn` with role `review`. The second is `forge_spawn` with role `review` and `avoid_family` set to the first one's `family` from its spawn result, so the two come from different families. Each writes its own file: tell them `review.md` for the first and `review-2.md` for the second.

## 4. Lead pass (panel only)

In this context, read both reviews. Merge into one `review.md`: drop duplicates, keep the stronger demonstration, and give every finding a disposition. A finding both reviewers raised independently is high-signal; say so. A finding only one raised with no demonstration stays `consider` at most. Every `dismissed` needs a reason. Keep the verdict line.

## 5. Verify and report

`$FORGE_HOME/scripts/forge-verify.sh --task-dir .forge/<id> --phase review`. Print the findings table and the verdict in the reply, with the `act` items first. Apply `micro/unslop`.

## 6. Post only on request

If the human says to post: `$FORGE_HOME/scripts/forge-pr.sh post --yes` comments `review.md` on the PR. Never run it unasked. It refuses when the target was a branch or range rather than a PR number.

## Rules

- The review changes no code. If the human wants fixes, that is a new `/forge` task with `review.md` as input.
- Blocking findings need a demonstration: an input, a command, or a file:line. Unease without one is a `nit`.
- Scope creep in the diff is a `should` finding. A missed `inferred` criterion is `blocking` only when the diff clearly promised it.
