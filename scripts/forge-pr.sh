#!/usr/bin/env bash
# forge-pr.sh: plumbing for reviewing and opening pull requests.
#   forge-pr.sh task <target>      -> create .forge/<id>/ for a review of <target> and print the id
#   forge-pr.sh range              -> print the "base..head" diff range of the current review task
#   forge-pr.sh post [--yes]       -> post .forge/<id>/review.md as a comment on the reviewed PR
#   forge-pr.sh open <base>        -> open a PR from the current branch with .forge/<id>/PR.md as the body
# <target> is a PR number (needs gh), a branch name, or an explicit "base..head".
# Run from the target project's root. FORGE_HOME defaults to the directory above this script.
set -euo pipefail

FORGE_HOME="${FORGE_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
need_gh() { command -v gh >/dev/null 2>&1 || { echo "forge-pr.sh: gh is not installed; pass a branch or base..head instead of a PR number" >&2; exit 1; }; }
current_id() { cat .forge/current 2>/dev/null || { echo "forge-pr.sh: no current task" >&2; exit 1; }; }
default_base() { git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true; }

cmd="${1:-}"; shift || true
case "$cmd" in
  task)
    target="${1:-}"; [ -n "$target" ] || usage
    number=""; title=""; body=""; head=""; base=""; url=""
    case "$target" in
      *..*) base="${target%%..*}"; head="${target##*..}"; title="Review $target" ;;
      ''|*[!0-9]*) head="$target"; base="$(default_base)"; [ -n "$base" ] || base=main; title="Review branch $head" ;;
      *)
        need_gh; number="$target"
        json="$(gh pr view "$number" --json number,title,body,headRefName,baseRefName,url,headRefOid)"
        py() { printf '%s' "$json" | python3 -I -c "import json,sys; print(json.load(sys.stdin).get(sys.argv[1]) or '')" "$1"; }
        title="$(py title)"; body="$(py body)"; head="$(py headRefName)"; base="$(py baseRefName)"; url="$(py url)"
        git fetch -q origin "pull/$number/head:forge-pr-$number" 2>/dev/null || true
        git rev-parse -q --verify "forge-pr-$number" >/dev/null && head="forge-pr-$number"
        ;;
    esac
    git fetch -q origin "$base" 2>/dev/null || true
    git rev-parse -q --verify "$head" >/dev/null || { echo "forge-pr.sh: cannot resolve head '$head'" >&2; exit 1; }
    baseref="$base"; git rev-parse -q --verify "$baseref" >/dev/null || baseref="origin/$base"
    mb="$(git merge-base "$baseref" "$head")"
    case "$target" in *..*) slugsrc="$base-to-$head" ;; *) slugsrc="${number:+pr-$number}${number:-$head}" ;; esac
    slug="$(printf '%s' "$slugsrc" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')"
    id="$(FORGE_HOME="$FORGE_HOME" "$FORGE_HOME/scripts/forge-task.sh" new "review-$slug")"
    dir=".forge/$id"
    python3 -I - "$dir" "$number" "$title" "$body" "$head" "$base" "$mb" "$url" <<'PY'
import json, sys
d, number, title, body, head, base, mb, url = sys.argv[1:9]
json.dump({"number": number or None, "title": title, "body": body, "head": head, "base": base, "merge_base": mb, "url": url}, open(f"{d}/pr.json", "w"), indent=2)
criteria = "\n".join(f"- `inferred` {line.strip()}" for line in body.splitlines() if line.strip().startswith(("- ", "* ", "1.", "2.", "3."))) or "- `inferred` the change does what the title says; derive checks from the diff"
task = f"""---
type: review
budget: 0
surface: none
non_goals: []
test_cmd: ""
lint_cmd: ""
typecheck_cmd: ""
base: {mb}
---

## Goal

Review {('PR #' + number) if number else head}: {title}

{body.strip() or '(no description)'}

## Acceptance criteria

Inferred from the PR description; the reviewer treats each as a claim to check against the diff, not as proven.

{criteria}

## Non-goals

Rewriting the change. The output is review.md, not a diff.

## Reproduction (bugs only)

n/a

## Required phases

GROUND (light, over the touched files), REVIEW, REPORT.
"""
open(f"{d}/task.md", "w").write(task)
PY
    git diff "$mb..$head" > "$dir/diff.patch"
    git diff --stat "$mb..$head" > "$dir/diff.stat"
    printf '{ "task": "%s", "phase": "ground", "loops": { "build": 0, "review": 0 } }\n' "$id" > "$dir/state.json"
    echo "$id"
    ;;
  range)
    id="$(current_id)"; python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['merge_base']+'..'+d['head'])" ".forge/$id/pr.json"
    ;;
  post)
    need_gh; id="$(current_id)"; dir=".forge/$id"
    [ -f "$dir/review.md" ] || { echo "forge-pr.sh: $dir/review.md does not exist" >&2; exit 1; }
    number="$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1])).get('number') or '')" "$dir/pr.json")"
    [ -n "$number" ] || { echo "forge-pr.sh: this review is not of a PR number, nothing to post to" >&2; exit 1; }
    if [ "${1:-}" != "--yes" ]; then echo "forge-pr.sh: would post $dir/review.md to PR #$number. Re-run with --yes after the human agreed." >&2; exit 3; fi
    gh pr comment "$number" --body-file "$dir/review.md"
    ;;
  open)
    need_gh; base="${1:-$(default_base)}"; [ -n "$base" ] || base=main
    id="$(current_id)"; dir=".forge/$id"
    [ -f "$dir/PR.md" ] || { echo "forge-pr.sh: $dir/PR.md does not exist; REPORT writes it from report.md" >&2; exit 1; }
    FORGE_HOME="$FORGE_HOME" "$FORGE_HOME/scripts/forge-verify.sh" --task-dir "$dir" --phase report || { echo "forge-pr.sh: G10/G12 failed on PR.md; fix it before opening the PR" >&2; exit 1; }
    title="$(head -n 1 "$dir/PR.md" | sed 's/^# *//')"
    git push -u origin HEAD
    gh pr create --base "$base" --title "$title" --body-file "$dir/PR.md"
    ;;
  *) usage ;;
esac
