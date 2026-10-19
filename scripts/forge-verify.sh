#!/usr/bin/env bash
# forge-verify.sh: run the gates a phase needs and write <task-dir>/verify.log.
#
# Why: "done" means the gates passed, and the record of that is verify.log, which
# only this runner writes. The harness's end-of-turn hook calls this script; a
# failing gate's paragraph becomes the model's next input.
#
# Usage (from the project root):
#   scripts/forge-verify.sh --task-dir .forge/<id> --phase <phase> [--base <ref>]
# Phase to gates:
#   intake  G0            ground  G0          scout   G0 G13       shape  G0
#   build   G1 G2 G3 G5 G6 G7 G8 G11
#   verify  G0 to G13 except G12
#   review  (none)        report  G10 G12        done  (none)
# Exit: 0 when no gate failed (skips are allowed and listed), 1 when any gate failed.
# verify.log holds each gate's status and full output. Its sha256 goes to
# verify.log.sha256 so G11 can tell a runner-written log from an edited one.

FORGE_VERIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATES="$FORGE_VERIFY_DIR/gates"
. "$FORGE_VERIFY_DIR/lib/common.sh"
GATE_ID=verify

task_dir=""; phase=""; base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --task-dir) task_dir="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --task-dir=*) task_dir="${1#*=}"; shift ;;
    --phase) phase="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --phase=*) phase="${1#*=}"; shift ;;
    --base) base="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --base=*) base="${1#*=}"; shift ;;
    *) echo "forge-verify.sh: unknown argument '$1'. Usage: forge-verify.sh --task-dir .forge/<id> --phase <phase> [--base <ref>]" >&2; exit 1 ;;
  esac
done
task_dir="${task_dir%/}"
if [ -z "$task_dir" ] || [ ! -d "$task_dir" ]; then
  echo "forge-verify.sh: --task-dir must name an existing task directory (got '$task_dir')." >&2
  exit 1
fi

case "$phase" in
  intake|ground|shape) ids="00" ;;
  scout) ids="00 13" ;;
  build) ids="01 02 03 05 06 07 08 11" ;;
  verify) ids="00 01 02 03 04 05 06 07 08 09 10 11 13" ;;
  review|done) ids="" ;;
  report) ids="10 12" ;;
  *) echo "forge-verify.sh: unknown phase '$phase'. Use intake, ground, scout, shape, build, verify, review, report or done." >&2; exit 1 ;;
esac

args=(--task-dir "$task_dir" --phase "$phase")
[ -n "$base" ] && args+=(--base "$base")

LOG="$task_dir/verify.log"
tmp="$(mktemp "${TMPDIR:-/tmp}/forge-verify.XXXXXX")"
body="$(mktemp "${TMPDIR:-/tmp}/forge-verify-body.XXXXXX")"
trap 'rm -f "$tmp" "$body"' EXIT

npass=0; nfail=0; nskip=0
summary=""
for id in $ids; do
  gate="$(ls "$GATES"/g"$id"-*.sh 2>/dev/null | head -n 1)"
  if [ -z "$gate" ]; then
    echo "forge-verify.sh: gate g$id is missing from $GATES" >&2
    nfail=$((nfail + 1)); summary="${summary}g$id MISSING
"
    continue
  fi
  name="$(basename "$gate" .sh)"
  bash "$gate" "${args[@]}" > "$tmp" 2>&1
  code=$?
  case "$code" in
    0) status=PASS; npass=$((npass + 1)) ;;
    2) status=SKIP; nskip=$((nskip + 1)) ;;
    *) status=FAIL; nfail=$((nfail + 1)) ;;
  esac
  summary="${summary}$name $status
"
  { printf '=== %s %s (exit %s)\n' "$name" "$status" "$code"; cat "$tmp"; printf '\n'; } >> "$body"
  # stream failures to the caller so the paragraph reaches the model
  if [ "$status" = FAIL ]; then cat "$tmp"; else head -n 1 "$tmp"; fi
done

result=PASS
[ "$nfail" -gt 0 ] && result=FAIL
{
  printf 'forge verify\n'
  printf 'phase: %s\n' "$phase"
  printf 'task: %s\n' "$task_dir"
  printf 'base: %s\n' "${base:-auto}"
  printf 'time: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'head: %s\n' "$(git rev-parse --short HEAD 2>/dev/null || echo none)"
  printf 'result: %s (%s passed, %s failed, %s skipped)\n' "$result" "$npass" "$nfail" "$nskip"
  printf '\n%s\n' "$summary"
  cat "$body"
} > "$LOG"
forge_hash "$LOG" > "$LOG.sha256"

echo "forge-verify: phase $phase $result ($npass passed, $nfail failed, $nskip skipped). Log: $LOG"
[ "$nfail" -eq 0 ]
