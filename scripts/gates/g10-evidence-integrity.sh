#!/usr/bin/env bash
# G10 evidence-integrity: every evidence pointer resolves to a file that is newer than the code it vouches for.
#
# Why: a report can cite a log that does not exist, or one captured before the
# last edit. Either way the claim is unproven. This gate reads:
#   - report.md and PR.md: the value after every "evidence:" (any case, anywhere on a line);
#   - decisions.tsv: the column whose header is "evidence".
# An "evidence:" inside an inline code span is a syntax example and is ignored.
# Each value is split into tokens. A token is a pointer when it contains "/" or
# ends in a known artifact extension (.log .txt .json .png .jpg .html .md .tsv ...);
# markdown links contribute their target. URLs are not checked here (G13 covers
# sources). "guess", "none", "-" and "n/a" are honest labels and pass. A value
# with no pointer and no label fails.
# A pointer must exist (relative to the project root, or to the task dir) and must
# not be older than any changed file. red.log and repro.log are exempt from the
# age check because they must predate the fix. A ":<line>" suffix is ignored.
#
# Usage: g10-evidence-integrity.sh --task-dir .forge/<id> [--base <ref>] [--phase <phase>]
# Skips when neither report.md nor decisions.tsv exists, except in the report
# phase, where a missing report.md fails.

GATE_ID=g10
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
forge_parse_args "$@"
forge_git_init

REPORT="$TASK_DIR/report.md"
PRMD="$TASK_DIR/PR.md"
DECISIONS="$TASK_DIR/decisions.tsv"
if [ ! -f "$REPORT" ] && [ "$PHASE" = report ]; then
  gate_fail "$REPORT does not exist. The report phase must write report.md with an evidence pointer for each claim."
fi
if [ ! -f "$REPORT" ] && [ ! -f "$PRMD" ] && [ ! -f "$DECISIONS" ]; then
  gate_skip "neither report.md, PR.md nor decisions.tsv exists yet in $TASK_DIR, so there are no evidence pointers to check."
fi

# values: "source<TAB>value"
values="$(
  for prose in "$REPORT" "$PRMD"; do
    [ -f "$prose" ] || continue
    awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      {
        # drop inline code spans that themselves contain "evidence:" (syntax examples)
        rest = $0; line = ""
        while (match(rest, /`[^`]*`/)) {
          span = substr(rest, RSTART, RLENGTH)
          line = line substr(rest, 1, RSTART - 1) (tolower(span) ~ /evidence:/ ? "" : span)
          rest = substr(rest, RSTART + RLENGTH)
        }
        line = line rest
        l = tolower(line); p = index(l, "evidence:")
        if (p == 0) { p = index(l, "evidence**:"); if (p) p += 2 }
        if (p == 0) next
        v = substr(line, p + 9); gsub(/\*\*/, "", v)
        print FILENAME ":" FNR "\t" v
      }
    ' "$prose"
  done
  if [ -f "$DECISIONS" ]; then
    awk -F'\t' '
      FNR == 1 { for (i = 1; i <= NF; i++) { h = tolower($i); gsub(/[[:space:]]/, "", h); if (h == "evidence") col = i }
                 if (!col) { print FILENAME ":1\t__NO_EVIDENCE_COLUMN__"; exit } ; next }
      /^[[:space:]]*$/ { next }
      { print FILENAME ":" FNR "\t" $col }
    ' "$DECISIONS"
  fi
)"

changed=()
while IFS= read -r f; do changed+=("$f"); done < <(forge_changed_existing)

is_changed() { local c; for c in "${changed[@]}"; do [ "$c" = "$1" ] && return 0; done; return 1; }

problems=""
checked=0
while IFS="$(printf '\t')" read -r src val; do
  [ -n "$src" ] || continue
  if [ "$val" = "__NO_EVIDENCE_COLUMN__" ]; then
    problems="${problems}$src: decisions.tsv has no 'evidence' column in its header row
"
    continue
  fi
  pointers=0
  label=0
  # markdown link targets first, then plain tokens
  tokens="$(printf '%s\n' "$val" | sed 's/\[[^]]*\](\([^)]*\))/ \1 /g' | tr ',;|' '   ' | tr -s ' \t' '\n\n')"
  while IFS= read -r t; do
    t="$(printf '%s' "$t" | sed "s/^[\`\"'(<\[]*//; s/[\`\"')>.,:;!?]*\$//; s/\]\$//")"
    [ -n "$t" ] || continue
    case "$(printf '%s' "$t" | tr 'A-Z' 'a-z')" in
      guess|none|-|n/a|na) label=1; continue ;;
      http://*|https://*) label=1; continue ;;
    esac
    path="$(printf '%s' "$t" | sed 's/:[0-9][0-9]*\(-[0-9][0-9]*\)\{0,1\}$//')"
    case "$path" in
      */*|*.log|*.txt|*.json|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.svg|*.html|*.md|*.tsv|*.csv|*.xml|*.out|*.har|*.mp4|*.webm|*.pdf) ;;
      *) continue ;;
    esac
    pointers=$((pointers + 1))
    checked=$((checked + 1))
    resolved=""
    if [ -e "$path" ]; then resolved="$path"
    elif [ -e "$TASK_DIR/$path" ]; then resolved="$TASK_DIR/$path"
    fi
    if [ -z "$resolved" ]; then
      problems="${problems}$src: '$path' does not exist
"
      continue
    fi
    is_changed "$resolved" && continue
    case "${resolved##*/}" in red.log|repro.log) continue ;; esac
    if [ "${#changed[@]}" -gt 0 ]; then
      newer="$(forge_newer_than "$resolved" "${changed[@]}" | head -n 3 | tr '\n' ' ')"
      [ -n "$newer" ] && problems="${problems}$src: '$path' is older than changed file(s) $newer
"
    fi
  done <<EOF_TOKENS
$tokens
EOF_TOKENS
  if [ "$pointers" -eq 0 ] && [ "$label" -eq 0 ]; then
    problems="${problems}$src: evidence value '$(printf '%s' "$val" | sed 's/^[[:space:]]*//' | cut -c1-80)' has no file pointer (write a path to the log or artifact, or the word guess)
"
  fi
done <<EOF_VALUES
$values
EOF_VALUES

if [ -n "$problems" ]; then
  gate_fail "evidence pointers are dangling or stale, listed below. Every evidence value must point at a file that exists and was produced after the last code edit. Rerun the check that produces each artifact (for tests: scripts/lib/run-tests.sh --log green), update the pointer to the new file, or label the claim 'guess'. Never point at a file you did not produce from a run." "$(printf '%s' "$problems")"
fi
gate_pass "$checked evidence pointer(s) resolve and are current."
