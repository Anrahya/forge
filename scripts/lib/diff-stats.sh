#!/usr/bin/env bash
# diff-stats.sh: count added and removed lines in the diff under test.
#
# Why: G5 (diff budget) and the reviewer need one agreed number. The diff under
# test is merge-base(<base>, HEAD) to the working tree, plus untracked files,
# minus .forge/ state. Lockfiles are listed but not counted: a dependency bump
# rewrites hundreds of generated lines that say nothing about change size.
#
# Usage: diff-stats.sh --task-dir .forge/<id> [--base <ref>]
# Output: one "added<TAB>removed<TAB>path" line per file (binary files show "-"),
#         lockfiles marked "(lockfile, not counted)", then "total<TAB>A<TAB>R".

if [ "${BASH_SOURCE[0]}" = "$0" ]; then GATE_ID="diff-stats"; fi
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

forge_is_lockfile() {
  case "${1##*/}" in
    package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml|bun.lockb|bun.lock|Cargo.lock) return 0 ;;
  esac
  return 1
}

# forge_diff_numstat: "added<TAB>removed<TAB>path" for every changed file.
forge_diff_numstat() {
  local f
  forge_changed_files | while IFS= read -r f; do
    if forge_is_untracked "$f"; then
      git diff --no-index --numstat -- /dev/null "$f" 2>/dev/null | awk -F'\t' -v p="$f" '{ print $1 "\t" $2 "\t" p }'
    else
      git diff --numstat --no-renames --relative "$MERGE_BASE" -- "$f" | awk -F'\t' -v p="$f" '{ print $1 "\t" $2 "\t" p }'
    fi
  done
}

forge_diff_stats_main() {
  forge_parse_args "$@"
  forge_git_init
  local a r p ta=0 tr=0
  while IFS="$(printf '\t')" read -r a r p; do
    [ -n "$p" ] || continue
    if forge_is_lockfile "$p"; then
      printf '%s\t%s\t%s (lockfile, not counted)\n' "$a" "$r" "$p"
      continue
    fi
    printf '%s\t%s\t%s\n' "$a" "$r" "$p"
    case "$a" in ''|*[!0-9]*) a=0 ;; esac
    case "$r" in ''|*[!0-9]*) r=0 ;; esac
    ta=$((ta + a)); tr=$((tr + r))
  done < <(forge_diff_numstat)
  printf 'total\t%s\t%s\n' "$ta" "$tr"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  forge_diff_stats_main "$@"
fi
