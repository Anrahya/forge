#!/usr/bin/env bash
# G4 scope: the diff stays out of the task's declared non-goals.
#
# Why: weak models "improve" neighboring code, which grows the diff, hides the
# real change from the reviewer, and breaks things nobody asked to touch.
#   - Any changed path (added, modified, deleted, untracked) matching a glob in
#     task.md "non_goals" fails the gate.
#   - Changed paths not listed under "## Files likely touched" in ground.md only
#     print a NOTE for the reviewer; GROUND is a forecast, not a contract.
# Globs use bash pattern matching, where "*" also matches "/", so "src/legacy/**"
# and "src/legacy/*" both cover the whole subtree. A glob ending in "/" is a
# directory prefix.
#
# Usage: g04-scope.sh --task-dir .forge/<id> [--base <ref>]

GATE_ID=g04
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
forge_parse_args "$@"
forge_require_task
forge_git_init

path_matches() { # <path> <glob>
  local p="$1" g="$2"
  g="${g#./}"
  case "$g" in
    */) case "$p" in "$g"*) return 0 ;; esac; return 1 ;;
  esac
  # shellcheck disable=SC2053
  [[ "$p" == $g ]] && return 0
  # a bare directory name or path covers everything under it
  case "$p" in "$g"/*) return 0 ;; esac
  return 1
}

nongoals=()
while IFS= read -r g; do [ -n "$g" ] && nongoals+=("$g"); done < <(forge_meta non_goals)

likely=()
GROUND="$TASK_DIR/ground.md"
if [ -f "$GROUND" ]; then
  while IFS= read -r g; do [ -n "$g" ] && likely+=("$g"); done < <(awk '
    /^## / { insec = (tolower($0) ~ /^## +files likely touched/); next }
    /^# / { insec = 0 }
    insec && /^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]+/ {
      line = $0
      sub(/^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]+/, "", line)
      if (match(line, /`[^`]+`/)) { print substr(line, RSTART + 1, RLENGTH - 2); next }
      sub(/[[:space:]].*$/, "", line); sub(/[:,]$/, "", line)
      print line
    }
  ' "$GROUND")
fi

blocked=""
unlisted=""
total=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  total=$((total + 1))
  for g in "${nongoals[@]}"; do
    if path_matches "$f" "$g"; then blocked="${blocked}$f (non-goal: $g)
"; break; fi
  done
  if [ "${#likely[@]}" -gt 0 ]; then
    hit=0
    for g in "${likely[@]}"; do
      if path_matches "$f" "$g"; then hit=1; break; fi
    done
    [ "$hit" -eq 1 ] || unlisted="$unlisted $f"
  fi
done < <(forge_changed_files)

if [ ! -f "$GROUND" ]; then
  gate_note "$GROUND not found; cannot compare the diff with the files GROUND expected."
elif [ "${#likely[@]}" -eq 0 ]; then
  gate_note "$GROUND has no list under '## Files likely touched'; cannot compare the diff with it."
elif [ -n "$unlisted" ]; then
  gate_note "changed but not in ground.md 'Files likely touched' (reviewer: check these are needed):$unlisted"
fi

if [ -n "$blocked" ]; then
  gate_fail "the diff touches paths that task.md declares as non-goals. Revert every change to these paths (git checkout <base> -- <path>, or delete the new file). If the task cannot be done without touching them, stop and report that instead of editing them." "$(printf '%s' "$blocked")"
fi
gate_pass "$total changed path(s), none under the ${#nongoals[@]} non-goal glob(s)."
