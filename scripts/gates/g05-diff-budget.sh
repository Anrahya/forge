#!/usr/bin/env bash
# G5 diff-budget: added plus removed lines stay within the task's budget.
#
# Why: the smallest change that solves the task is the reviewable one. Weak models
# pad diffs with rewrites, helpers and drive-by refactors. The count comes from
# scripts/lib/diff-stats.sh (diff under test, .forge/ and lockfiles excluded).
# Budget: task.md "budget" if set, else the type default from DESIGN.md section 12:
#   bug 150, feature 600, refactor 400, chore 100, perf/investigate/research 600.
#
# Usage: g05-diff-budget.sh --task-dir .forge/<id> [--base <ref>]

GATE_ID=g05
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
. "$FORGE_LIB_DIR/diff-stats.sh"
forge_parse_args "$@"
forge_require_type
forge_git_init

budget="$(forge_meta budget)"
source_of_budget="task.md budget"
if [ -z "$budget" ]; then
  case "$TASK_TYPE" in
    bug) budget=150 ;;
    refactor) budget=400 ;;
    chore) budget=100 ;;
    *) budget=600 ;;
  esac
  source_of_budget="default for $TASK_TYPE"
fi
case "$budget" in
  *[!0-9]*|'') gate_fail "task.md budget '$budget' is not a whole number of lines. Set budget to an integer such as 150." ;;
esac

stats="$(forge_diff_stats_main --task-dir "$TASK_DIR" ${BASE_ARG:+--base "$BASE_ARG"})"
total_line="$(printf '%s\n' "$stats" | awk -F'\t' '$1 == "total"')"
added="$(printf '%s' "$total_line" | cut -f2)"
removed="$(printf '%s' "$total_line" | cut -f3)"
size=$((added + removed))

if [ "$size" -gt "$budget" ]; then
  top="$(printf '%s\n' "$stats" | awk -F'\t' '$1 != "total" && $1 ~ /^[0-9]+$/ { print ($1 + $2) "\t" $3 }' | sort -rn | head -n 8 | awk -F'\t' '{ print $2 ": " $1 " lines" }')"
  gate_fail "the diff is $size lines (+$added -$removed), over the budget of $budget ($source_of_budget). Shrink it: drop changes the task does not need, revert drive-by refactors and reformatting, reuse existing helpers instead of adding new ones, and delete code your change made dead. If the task truly needs more than twice the budget, stop and report (stop condition S3) rather than raising the budget yourself. Largest files:" "$top"
fi
gate_pass "diff is $size lines (+$added -$removed), within the budget of $budget ($source_of_budget)."
