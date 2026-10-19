#!/usr/bin/env bash
# evals/run.sh <task-id> --mode bare|forge --model <provider/model>
# Checks out the task repo at base, runs the agent through the harness runner, runs the hidden check, records results.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
task="${1:-}"; shift || true
mode=bare; model=""
while [ $# -gt 0 ]; do case "$1" in --mode) mode="$2"; shift 2;; --model) model="$2"; shift 2;; *) echo "unknown arg $1" >&2; exit 2;; esac; done
[ -n "$task" ] || { echo "usage: run.sh <task-id> --mode bare|forge --model <m>" >&2; exit 2; }
tdir="$here/tasks/$task"; [ -f "$tdir/task.json" ] || { echo "no task $task" >&2; exit 1; }
py() { python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$tdir/task.json" "$1"; }
repo="$(py repo)"; base="$(py base)"; prompt="$(py prompt)"; check="$(py hidden_check)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
git clone -q "$repo" "$work/repo" && git -C "$work/repo" checkout -q "$base"
cp -r "$tdir/hidden" "$work/repo/hidden" 2>/dev/null || true
runner="$here/runners/${FORGE_HARNESS:-dsh}.sh"
start=$(date +%s)
"$runner" --cwd "$work/repo" --mode "$mode" --model "$model" --prompt "$prompt" > "$work/agent.log" 2>&1 || true
end=$(date +%s)
pass=0; (cd "$work/repo" && bash -c "$check") >/dev/null 2>&1 && pass=1
lines=$(git -C "$work/repo" diff --numstat "$base" | awk '{a+=$1; d+=$2} END {print a+d+0}')
gates=""; [ -f "$work/repo/.forge/current" ] && gates="$(grep -h '^GATE g[0-9]* FAIL' "$work/repo/.forge/$(cat "$work/repo/.forge/current")/verify.log" 2>/dev/null | awk '{print $2}' | sort | uniq -c | awk '{printf "%s:%s ", $2, $1}' || true)"
run_id="$(date +%Y%m%d-%H%M%S)-$task-$mode"
mkdir -p "$here/results"
printf '{ "run": "%s", "task": "%s", "mode": "%s", "model": "%s", "pass": %s, "diff_lines": %s, "gate_failures": "%s", "seconds": %s }\n' \
  "$run_id" "$task" "$mode" "$model" "$pass" "$lines" "$gates" "$((end-start))" > "$here/results/$run_id.json"
cat "$here/results/$run_id.json"
