#!/usr/bin/env bash
# G2 green-after-edit: the full test command passed after the last edit.
#
# Why: "tests pass" is a claim until a log says so, and a log only counts if it
# was written after the code it vouches for. This gate reads green.log (written
# by "scripts/lib/run-tests.sh --task-dir <dir> --log green") and requires:
#   - it was written by run-tests.sh (command, exit and output header present);
#   - the command is the project's resolved test command (not a narrowed one);
#   - exit 0;
#   - no file in the diff under test has an mtime newer than the log.
# Mtimes are compared with "find -newer", which is portable and uses full resolution.
#
# Applies to: every type except investigate and research (no code changes).
# Usage: g02-green-after-edit.sh --task-dir .forge/<id> [--base <ref>]

GATE_ID=g02
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
forge_parse_args "$@"
forge_require_type
case "$TASK_TYPE" in
  investigate|research) gate_skip "task type '$TASK_TYPE' changes no code, so there is no green run to check." ;;
esac
forge_git_init

LOG="$TASK_DIR/green.log"
RUN="scripts/lib/run-tests.sh --task-dir $TASK_DIR --log green"

[ -f "$LOG" ] || gate_fail "$LOG does not exist, so nothing shows the tests pass with this change. Run '$RUN' after your last edit and fix any failure it reports."

exit_line="$(sed -n 's/^exit: *//p' "$LOG" | head -n 1)"
cmd_line="$(sed -n 's/^command: *//p' "$LOG" | head -n 1)"
if [ -z "$cmd_line" ] || [ -z "$exit_line" ] || ! grep -q '^--- output ---$' "$LOG"; then
  gate_fail "$LOG was not written by run-tests.sh (missing the command, exit or output header). Do not write logs by hand; run '$RUN'."
fi

expected="$(forge_test_cmd "$TASK_DIR")"
if [ -n "$expected" ] && [ "$cmd_line" != "$expected" ]; then
  gate_fail "$LOG ran '$cmd_line' but the project's test command is '$expected'. A green run must cover the whole suite. Run '$RUN' without overriding the command."
fi

case "$exit_line" in ''|*[!0-9]*) gate_fail "$LOG has a non-numeric exit code '$exit_line'. Rerun '$RUN'." ;; esac
if [ "$exit_line" -ne 0 ]; then
  gate_fail "$LOG shows the test command exited $exit_line, so the suite is not green. Read the failures below, fix the code (not the tests, unless the test itself is wrong and you can say why), and rerun '$RUN'." "$(sed -n '/^--- output ---$/,$p' "$LOG" | sed '1d' | forge_strip_ansi | tail -n 20)"
fi

files=()
while IFS= read -r f; do files+=("$f"); done < <(forge_changed_existing)
newer=""
if [ "${#files[@]}" -gt 0 ]; then
  newer="$(forge_newer_than "$LOG" "${files[@]}")"
fi
if [ -n "$newer" ]; then
  gate_fail "$LOG is stale: these changed files were edited after the last green run, so the log does not cover them. Rerun '$RUN' after your final edit." "$(printf '%s\n' "$newer" | head -n 20)"
fi

gate_pass "$LOG exit 0 with '$cmd_line', newer than all ${#files[@]} changed file(s)."
