#!/usr/bin/env bash
# G12 unslop-lint: report and PR prose carry none of the machine-writing tells.
#
# Why: a human decides whether to trust unattended work by reading the report.
# Filler vocabulary, chatbot phrases and bolded label lists make it longer and
# vaguer, and readers learn to skim it. These rules mirror skills/micro/unslop.
#
# Checks prose lines (fenced code blocks skipped, `inline code` removed) in:
#   - <task-dir>/report.md and <task-dir>/PR.md (every line; they are written for this task)
#   - any changed file named PR.md in the diff under test (added lines only)
# Fails on:
#   - the em dash character (U+2014)
#   - "not just"
#   - AI vocabulary: delve, leverage, robust, seamless, seamlessly, crucial,
#     pivotal, landscape, tapestry, testament, underscore, showcase, foster,
#     fostering, enhance, garner, intricate, vibrant (and their inflections)
#   - chatbot phrases: "I hope this helps", "Great question", "Certainly", "Let me know"
#   - bold-label-colon list lines: "- **Label:** text"
#
# Usage: g12-unslop-lint.sh --task-dir .forge/<id> [--base <ref>] [--phase <phase>]
# Skips when there is no prose to check, except in the report phase, where a
# missing report.md fails.

GATE_ID=g12
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
forge_parse_args "$@"

REPORT="$TASK_DIR/report.md"
if [ ! -f "$REPORT" ] && [ "$PHASE" = report ]; then
  gate_fail "$REPORT does not exist. The report phase must write report.md before it can be linted."
fi

inputs="$(mktemp "${TMPDIR:-/tmp}/forge-g12.XXXXXX")"
trap 'rm -f "$inputs"' EXIT
# "file<TAB>line<TAB>text"
for f in "$REPORT" "$TASK_DIR/PR.md"; do
  [ -f "$f" ] && awk -v f="$f" '{ print f "\t" FNR "\t" $0 }' "$f" >> "$inputs"
done
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  forge_git_init
  forge_added_lines | awk -F'\t' '$1 == "PR.md" || $1 ~ /\/PR\.md$/' >> "$inputs"
fi
[ -s "$inputs" ] || gate_skip "no report.md or PR.md to lint yet."

EM="$(printf '\342\200\224')"

# The word and phrase lists live in skills/micro/unslop/SKILL.md so the skill and the gate
# cannot drift apart: the first fenced block is the vocabulary, the second is chatbot phrases.
# The inline defaults below are only the fallback when that file is missing.
UNSLOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/skills/micro/unslop/SKILL.md"
VOCAB_DEFAULT="delve|delves|delved|delving|leverage|leverages|leveraged|leveraging|robust|robustly|robustness|seamless|seamlessly|crucial|crucially|pivotal|landscape|landscapes|tapestry|testament|underscore|underscores|underscored|underscoring|showcase|showcases|showcased|showcasing|foster|fosters|fostered|fostering|enhance|enhances|enhanced|enhancing|enhancement|enhancements|garner|garners|garnered|intricate|intricately|vibrant"
PHRASES_DEFAULT="i hope this helps|great question|(^|[^a-z])certainly([^a-z]|$)|let me know"
fenced_block() { # $1 = file, $2 = block number (1-based); prints the block's non-empty lines
  awk -v want="$2" '/^```/ { if (f) { f = 0; if (n == want) exit } else { f = 1; n++ }; next } f && n == want && NF' "$1"
}
if [ -f "$UNSLOP" ]; then
  VOCAB="$(fenced_block "$UNSLOP" 1 | tr ' ' '\n' | LC_ALL=C grep -E '^[a-z-]+$' | sort -u | paste -sd '|' -)"
  PHRASES="$(fenced_block "$UNSLOP" 2 | tr '[:upper:]' '[:lower:]' | sed 's/[][\\.*^$!?()+{}|]/\\&/g' | paste -sd '|' -)"
fi
[ -n "${VOCAB:-}" ] || VOCAB="$VOCAB_DEFAULT"
[ -n "${PHRASES:-}" ] || PHRASES="$PHRASES_DEFAULT"
findings="$(LC_ALL=C awk -F'\t' -v em="$EM" -v vocab="$VOCAB" -v phrases="$PHRASES" '
  function show(s) { gsub(em, "[em dash]", s); sub(/^[[:space:]]+/, "", s); if (length(s) > 100) s = substr(s, 1, 97) "..."; return s }
  function hit(rule) { print $1 ":" $2 ": " rule ": " show(text) }
  BEGIN {
    vre = "(^|[^a-z])(" vocab ")([^a-z]|$)"
  }
  $1 != lastfile { fence = 0; lastfile = $1 }
  {
    text = $3; for (i = 4; i <= NF; i++) text = text "\t" $i
    if (text ~ /^[[:space:]]*(```|~~~)/) { fence = !fence; next }
    if (fence) next
    prose = text; gsub(/`[^`]*`/, "", prose)
    l = tolower(prose)
    if (index(prose, em)) hit("em dash")
    if (l ~ /(^|[^a-z])not just([^a-z]|$)/) hit("\"not just\" construction")
    if (match(l, vre)) { w = substr(l, RSTART, RLENGTH); gsub(/[^a-z]/, "", w); hit("AI vocabulary \"" w "\"") }
    if (l ~ phrases) hit("chatbot phrase")
    if (text ~ /^[[:space:]]*[-*][[:space:]]*\*\*[^*]+:\*\*/) hit("bold-label list line")
  }
' "$inputs")"

if [ -n "$findings" ]; then
  count="$(printf '%s\n' "$findings" | wc -l | tr -d ' ')"
  gate_fail "found $count prose tell(s) in the report or PR text, listed below as file:line: rule: text. Rewrite each line plainly: use a comma, colon or period instead of an em dash; say the specific thing instead of the flagged word; drop chatbot phrases; state the claim directly instead of 'not just X but Y'; write list items as sentences instead of bold labels with colons." "$findings"
fi
gate_pass "no prose tells in $(cut -f1 "$inputs" | sort -u | wc -l | tr -d ' ') file(s)."
