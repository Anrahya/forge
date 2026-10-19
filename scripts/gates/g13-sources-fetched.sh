#!/usr/bin/env bash
# G13 sources-fetched: every URL cited in scout.md was actually fetched.
#
# Why: weak models cite search snippets, half-remembered pages and invented
# URLs. SCOUT claims must rest on pages that were read. The only accepted record
# is <task-dir>/fetch.log, appended by scripts/lib/fetch-log.sh <url> after a
# successful curl. A URL matches a fetch.log entry exactly, or with a trailing
# "/" or "#fragment" difference.
#
# Usage: g13-sources-fetched.sh --task-dir .forge/<id> [--phase <phase>]
# Skips when scout.md does not exist, except in the scout phase, where it fails.
# Fails when scout.md cites no URL at all and SCOUT is required (feature, refactor,
# perf, research, or the scout phase): every candidate needs a fetched source.
# For other types an untouched scout.md (forge-task.sh copies every template) skips.

GATE_ID=g13
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
forge_parse_args "$@"

SCOUT="$TASK_DIR/scout.md"
FETCH="$TASK_DIR/fetch.log"
if [ ! -f "$SCOUT" ]; then
  [ "$PHASE" = scout ] && gate_fail "$SCOUT does not exist. The scout phase must write scout.md with a fetched source for each candidate."
  gate_skip "no scout.md in $TASK_DIR, so there are no cited sources to check."
fi

norm() { sed 's/#.*$//; s#/$##'; }

urls="$(grep -Eo "https?://[^][[:space:]<>\"'\`()]+" "$SCOUT" | sed 's/[.,;:!?*_]*$//' | sort -u)"
scout_required=0
[ "$PHASE" = scout ] && scout_required=1
if [ -f "$TASK_DIR/task.md" ]; then
  case "$(forge_task_type)" in feature|refactor|perf|research) scout_required=1 ;; esac
fi
if [ -z "$urls" ] && [ "$scout_required" -eq 0 ]; then
  gate_skip "scout.md cites no URL and SCOUT is not required for this task type."
fi
[ -n "$urls" ] || gate_fail "$SCOUT cites no http(s) URL. Each candidate and claim in SCOUT needs a source you fetched: fetch it with scripts/lib/fetch-log.sh --task-dir $TASK_DIR <url> and cite that URL."

fetched=""
[ -f "$FETCH" ] && fetched="$(awk -F'\t' 'NF >= 3 { print $3 }' "$FETCH" | norm | sort -u)"

missing=""
n=0
while IFS= read -r u; do
  [ -n "$u" ] || continue
  n=$((n + 1))
  key="$(printf '%s\n' "$u" | norm)"
  if ! printf '%s\n' "$fetched" | grep -Fxq -- "$key"; then
    missing="${missing}$u
"
  fi
done <<EOF_URLS
$urls
EOF_URLS

if [ -n "$missing" ]; then
  gate_fail "$SCOUT cites URLs with no fetch record in $FETCH, listed below. A source counts only if it was fetched and read in this task. For each one run 'scripts/lib/fetch-log.sh --task-dir $TASK_DIR <url>', read what it returns, and keep the citation only if the page supports the claim; otherwise remove the claim or label it a guess." "$(printf '%s' "$missing")"
fi
gate_pass "all $n cited URL(s) in scout.md have a fetch record."
