#!/usr/bin/env bash
# forge Stop hook for Claude Code: no "done" without gates.
# Runs scripts/forge-verify.sh --task-dir .forge/<id> --phase <phase>.
#   exit 0 from the script: allow the stop (exit 0, no output).
#   anything else: block the stop with exit 2; stderr (the verify.log tail)
#   goes to the model as the reason to keep working.
# After FORGE_MAX_VERIFY_ROUNDS (default 3) blocked stops in a row the stop is
# allowed, with a systemMessage telling the user the gates still fail.

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"

INPUT=$(cat)
have_jq || exit 0
CWD=$(json_get "$INPUT" '.cwd')
[ -z "$CWD" ] && CWD=$PWD
forge_state "$CWD" || exit 0

MAX=${FORGE_MAX_VERIFY_ROUNDS:-3}
TAIL_LINES=${FORGE_VERIFY_TAIL_LINES:-80}
SESSION=$(json_get "$INPUT" '.session_id' | tr -cd 'A-Za-z0-9._-')
ACTIVE=$(json_get "$INPUT" '.stop_hook_active')
COUNTER="${TMPDIR:-/tmp}/forge-cc-stop-${SESSION:-default}"

# stop_hook_active is false on the first stop attempt after a user prompt.
[ "$ACTIVE" != "true" ] && rm -f "$COUNTER"
ROUND=$(( $(cat "$COUNTER" 2>/dev/null || echo 0) + 1 ))

if [ "$ROUND" -gt "$MAX" ]; then
  rm -f "$COUNTER"
  jq -n --arg m "forge: task $TASK_ID gates still fail after $MAX verify rounds. The turn ended without passing verification." '{systemMessage: $m}'
  exit 0
fi

block() {
  printf '%s' "$ROUND" > "$COUNTER"
  printf '%s\n\nVerify round %s of %s.\n' "$1" "$ROUND" "$MAX" >&2
  exit 2
}

if [ -z "$PHASE" ]; then
  block "forge: ${STATE_PROBLEM:-state.json has no valid phase}. The turn is not done. Set the phase in .forge/$TASK_ID/state.json so the gates can run."
fi

SCRIPT=""
for candidate in "$FORGE_ROOT/scripts/forge-verify.sh" "$(forge_dir)/scripts/forge-verify.sh"; do
  [ -f "$candidate" ] && { SCRIPT=$candidate; break; }
done
[ -z "$SCRIPT" ] && block "forge: verification could not run: scripts/forge-verify.sh was not found in the project or the forge install, so no gate ran. The turn is not done. Do not claim the phase passed. If you cannot fix the cause from your side, report stop condition S2 or S5 and stop."

LOG="$FORGE_ROOT/$TASK_DIR/verify.log"
# Fingerprint (checksum plus listing) instead of -nt: bash 3.2 compares whole seconds.
fingerprint() { [ -f "$LOG" ] && { cksum < "$LOG"; ls -l "$LOG"; }; }
BEFORE=$(fingerprint)
OUT=$(cd "$FORGE_ROOT" && FORGE_HARNESS=claude-code bash "$SCRIPT" --task-dir "$TASK_DIR" --phase "$PHASE" 2>&1)
CODE=$?
AFTER=$(fingerprint)

# Only a verify.log this run wrote is evidence; otherwise show the script output.
if [ -n "$AFTER" ] && [ "$AFTER" != "$BEFORE" ]; then TAIL=$(tail -n "$TAIL_LINES" "$LOG"); else TAIL=$(printf '%s\n' "$OUT" | tail -n "$TAIL_LINES"); fi

case "$CODE" in
  0) rm -f "$COUNTER"; exit 0 ;;
  1) block "forge: the $(printf '%s' "$PHASE" | tr '[:lower:]' '[:upper:]') gates failed (scripts/forge-verify.sh exit 1). The turn is not done. Fix what the gate names, rerun, and only then finish. Do not edit gate scripts or verify.log; if a gate is wrong, report stop condition S5.

Tail of .forge/$TASK_ID/verify.log:

$TAIL" ;;
  *) block "forge: verification could not run: forge-verify.sh ended with exit $CODE (expected 0 or 1). The turn is not done. Do not claim the phase passed. If you cannot fix the cause from your side, report stop condition S2 or S5 and stop.

$TAIL" ;;
esac
