#!/usr/bin/env bash
# G9 runtime: drive the real app through the project's verify skill and require every journey to pass.
#
# Why: tests are a proxy. A task with a user-facing surface (cli, http, ui) is not
# done until the built artifact was driven the way a user would and the
# observable end state was checked. forge-verify-setup writes a project-local
# skill at .agents/skills/verify-<app>/ with one feature file per user-facing
# feature; each feature file's "## Drive" section holds a fenced bash block that
# drives the feature and exits non-zero when the end state is wrong.
#
# Behavior:
#   surface none (or absent)        -> skip (exit 2)
#   no .agents/skills/verify-*/     -> fail: run forge-verify-setup first
#   no features/*.md                -> fail: the feature map is empty
#   a feature without a bash block  -> fail (inconclusive is not a pass)
#   each Drive block runs with bash from the project root, stdin closed, with a
#   timeout of $FORGE_G09_TIMEOUT seconds (default 300); output goes to
#   <task-dir>/g09/<skill>-<feature>.log. Any non-zero exit fails the gate.
#
# Usage: g09-runtime.sh --task-dir .forge/<id> [--base <ref>]

GATE_ID=g09
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
forge_parse_args "$@"
forge_require_task

surface="$(forge_meta surface)"
case "$surface" in
  ''|none) gate_skip "task.md surface is '${surface:-unset}', so there is no runnable surface to drive." ;;
  cli|http|ui) ;;
  *) gate_fail "task.md surface '$surface' is not one of none, cli, http, ui. Fix the front matter." ;;
esac

skills=()
for d in .agents/skills/verify-*/; do
  [ -d "$d" ] && skills+=("${d%/}")
done
if [ "${#skills[@]}" -eq 0 ]; then
  gate_fail "task.md declares surface '$surface' but the project has no verify skill (.agents/skills/verify-*/ is missing), so nothing can drive the real app. Run the forge-verify-setup skill to create one (Launch, Doctor, Drive, Evidence, Cleanup and a features/ map), commit it, then rerun this gate. Do not mark the task done on tests alone."
fi

features=()
for s in "${skills[@]}"; do
  for f in "$s"/features/*.md; do
    [ -f "$f" ] && features+=("$f")
  done
done
if [ "${#features[@]}" -eq 0 ]; then
  gate_fail "the verify skill (${skills[*]}) has no feature files under features/*.md, so there is no journey to run. Run forge-verify-maintain (or forge-verify-setup) to add a feature file for the behavior this task changes, with a '## Drive' section holding a bash block that exits non-zero when the end state is wrong."
fi

extract_drive() {
  awk '
    /^## / { insec = (tolower($0) ~ /^## +drive[[:space:]]*$/); next }
    insec && !inblock && /^[[:space:]]*```(bash|sh|shell)[[:space:]]*$/ { inblock = 1; found = 1; next }
    inblock && /^[[:space:]]*```[[:space:]]*$/ { exit }
    inblock { print }
    END { if (!found) exit 3 }
  ' "$1"
}

run_with_timeout() { # <secs> <log> <script>
  # The watchdog polls instead of sleeping the whole timeout, so it exits on its own
  # shortly after the journey ends and never has to be killed (no job noise on stderr).
  local secs="$1" log="$2" script="$3" pid wd code
  bash "$script" > "$log" 2>&1 < /dev/null &
  pid=$!
  (
    ticks=$((secs * 5))
    while kill -0 "$pid" 2>/dev/null; do
      ticks=$((ticks - 1))
      if [ "$ticks" -le 0 ]; then
        kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null
        break
      fi
      sleep 0.2
    done
  ) > /dev/null 2>&1 &
  wd=$!
  wait "$pid"
  code=$?
  wait "$wd" 2>/dev/null
  return "$code"
}

TIMEOUT="${FORGE_G09_TIMEOUT:-300}"
mkdir -p "$TASK_DIR/g09"
failed=""
passed=0
for f in "${features[@]}"; do
  skill="$(basename "$(dirname "$(dirname "$f")")")"
  name="$(basename "$f" .md)"
  log="$TASK_DIR/g09/$skill-$name.log"
  script="$(mktemp "${TMPDIR:-/tmp}/forge-g09.XXXXXX")"
  if ! extract_drive "$f" > "$script" || [ ! -s "$script" ]; then
    failed="${failed}$f: no fenced bash block under '## Drive', so the journey is inconclusive
"
    rm -f "$script"
    continue
  fi
  run_with_timeout "$TIMEOUT" "$log" "$script"
  code=$?
  rm -f "$script"
  if [ "$code" -ne 0 ]; then
    why="exit $code"
    [ "$code" -eq 143 ] && why="timed out after ${TIMEOUT}s or was terminated (exit 143)"
    failed="${failed}$f: $why; last output: $(forge_strip_ansi < "$log" | sed '/^[[:space:]]*$/d' | tail -n 3 | tr '\n' ' ')(log: $log)
"
  else
    passed=$((passed + 1))
  fi
done

if [ -n "$failed" ]; then
  gate_fail "runtime verification failed for the '$surface' surface: driving the real app did not reach the expected end state. Read each journey's log, fix the code (not the journey), and rerun. If a journey is out of date because the feature legitimately changed, update its feature file with forge-verify-maintain and say so in the report." "$(printf '%s' "$failed")"
fi
gate_pass "$passed runtime journey(s) passed for surface '$surface'. Logs: $TASK_DIR/g09/."
