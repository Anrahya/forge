#!/usr/bin/env bash
# G0 phase-artifacts: the current phase's artifact has every required section, and none is empty.
#
# Why: phases hand off through files only. A missing or placeholder section means
# the next phase works from a guess. Templates are the contract: every "## "
# heading in templates/<artifact>.md is required in .forge/<id>/<artifact>.md,
# and its body must hold something beyond HTML comments and the template's own
# placeholder lines. SHAPE for feature and refactor must also show two candidates.
#
# Usage: g00-phase-artifacts.sh --task-dir .forge/<id> --phase <phase>
#   (phase falls back to "phase" in <task-dir>/state.json)
# A heading that ends in "(<types> only)", such as "Reproduction (bugs only)", is
# required only when the task type is one of those types.
# Phase to artifacts: intake=task, ground=ground, scout=scout, shape=shape,
#   review=review, report=report, build/verify = every earlier artifact the task
#   type requires (task, ground unless chore, scout for feature/refactor/perf/research,
#   shape for feature/refactor/perf).
# Templates: $FORGE_TEMPLATES_DIR or <forge>/templates. A missing template skips that artifact;
#   if every template is missing the gate exits 2.

GATE_ID=g00
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
forge_parse_args "$@"

TEMPLATES="${FORGE_TEMPLATES_DIR:-$FORGE_ROOT/templates}"
[ -n "$PHASE" ] || gate_fail "no phase given. Pass --phase <ground|scout|shape|build|verify|review|report> or record the phase in $TASK_DIR/state.json."

type=""
if [ -f "$TASK_DIR/task.md" ]; then type="$(forge_task_type)"; fi

case "$PHASE" in
  intake) artifacts="task" ;;
  ground|scout|shape|review|report) artifacts="$PHASE" ;;
  build|verify)
    forge_require_type
    type="$TASK_TYPE"
    artifacts="task"
    [ "$type" != chore ] && artifacts="$artifacts ground"
    case "$type" in feature|refactor|perf|research) artifacts="$artifacts scout" ;; esac
    case "$type" in feature|refactor|perf) artifacts="$artifacts shape" ;; esac
    ;;
  *) gate_fail "unknown phase '$PHASE'. Use one of intake, ground, scout, shape, build, verify, review, report." ;;
esac

# check_sections <template> <artifact>: prints "MISSING<TAB>heading" or "EMPTY<TAB>heading".
check_sections() {
  awk '
    function norm(s) { gsub(/[[:space:]]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return tolower(s) }
    FNR == 1 { fi++; sec = ""; fence = 0; incomment = 0 }
    {
      line = $0; sub(/\r$/, "", line)
      if (!fence && line ~ /^## /) {
        sec = norm(substr(line, 4))
        if (fi == 1) { if (!(sec in seen)) { nreq++; req[nreq] = sec; orig[sec] = substr(line, 4); seen[sec] = 1 } }
        else have[sec] = 1
        next
      }
      if (!fence && line ~ /^# /) { sec = ""; next }
      if (line ~ /^[[:space:]]*(```|~~~)/) fence = !fence
      if (sec == "") next
      out = ""; rest = line
      while (1) {
        if (incomment) { p = index(rest, "-->"); if (!p) { rest = ""; break }; rest = substr(rest, p + 3); incomment = 0 }
        p = index(rest, "<!--"); if (!p) { out = out rest; break }
        out = out substr(rest, 1, p - 1); rest = substr(rest, p + 4); incomment = 1
      }
      t = norm(out)
      if (t == "") next
      if (fi == 1) tpl[sec SUBSEP t] = 1
      else if (!((sec SUBSEP t) in tpl)) content[sec] = 1
    }
    END {
      for (i = 1; i <= nreq; i++) {
        s = req[i]
        if (!(s in have)) print "MISSING\t" orig[s]
        else if (!(s in content)) print "EMPTY\t" orig[s]
      }
    }
  ' "$1" "$2"
}

# count_candidates <shape.md>: the larger of (subheadings inside a "## ...candidate..." section)
# and (headings that name a single candidate, like "## Candidate A").
count_candidates() {
  awk '
    { line = tolower($0) }
    /^```/ { fence = !fence; next }
    fence { next }
    /^## / { incand = (line ~ /candidate/); if (line ~ /candidate([^s]|$)/) named++; next }
    /^###+ / { if (incand) sub_n++; if (line ~ /candidate([^s]|$)/) named++ }
    END { n = (sub_n > named ? sub_n : named); print n + 0 }
  ' "$1"
}

# section_applies <heading>: a heading like "Reproduction (bugs only)" is required only
# for the task types it names; every other heading is always required.
section_applies() {
  local h scope w
  h="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  case "$h" in *"only)"*) ;; *) return 0 ;; esac
  scope="$(printf '%s' "$h" | sed -n 's/.*(\([a-z ,/]*\) only).*/\1/p' | tr ',/' '  ')"
  [ -n "$scope" ] || return 0
  for w in $scope; do
    w="${w%s}"
    [ "$w" = "$type" ] && return 0
  done
  return 1
}

problems=""
checked=0
skipped=""
for a in $artifacts; do
  tpl="$TEMPLATES/$a.md"
  art="$TASK_DIR/$a.md"
  if [ ! -f "$tpl" ]; then
    skipped="$skipped $a"
    continue
  fi
  checked=$((checked + 1))
  if [ ! -f "$art" ]; then
    problems="${problems}$art is missing (copy the headings from $tpl and fill each one)
"
    continue
  fi
  while IFS="$(printf '\t')" read -r kind heading; do
    [ -n "$kind" ] || continue
    section_applies "$heading" || continue
    case "$kind" in
      MISSING) problems="${problems}$art: required section '## $heading' is missing
" ;;
      EMPTY) problems="${problems}$art: section '## $heading' is empty or still holds only the template placeholder
" ;;
    esac
  done < <(check_sections "$tpl" "$art")
  if [ "$a" = shape ] && { [ "$type" = feature ] || [ "$type" = refactor ]; }; then
    n="$(count_candidates "$art")"
    if [ "$n" -lt 2 ]; then
      problems="${problems}$art: a $type needs two structurally distinct candidates, found $n (use a '## Candidates' section with one '### ' heading per candidate)
"
    fi
  fi
done

[ -n "$skipped" ] && gate_note "no template for:$skipped (looked in $TEMPLATES); those artifacts were not checked."
[ "$checked" -gt 0 ] || gate_skip "no template found for the $PHASE phase artifacts ($artifacts) in $TEMPLATES, so there are no required headings to check."

if [ -n "$problems" ]; then
  gate_fail "the $PHASE phase artifacts are incomplete. Every '## ' heading from the template must appear in the artifact with real content under it; HTML comments and unchanged template placeholder lines do not count. Fill each section listed below from your own reading and runs, then rerun the gate." "$(printf '%s' "$problems")"
fi
gate_pass "artifacts complete for phase $PHASE ($artifacts)."
