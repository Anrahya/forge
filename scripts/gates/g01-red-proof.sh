#!/usr/bin/env bash
# G1 red-proof: the check was seen failing before the change.
#
# Why: a test written after the fix, or one that never failed, proves nothing
# about the fix. BUILD writes the check first and records it with
# "scripts/lib/run-tests.sh --task-dir <dir> --log red". This gate reads that log:
# it must exist, come from run-tests.sh, have a non-zero exit, and name at least
# one failing test. A non-zero exit with no failing test named (missing command,
# broken config, compile error before any test ran) is not a red test.
#
# Applies to: bug and feature tasks. Other types skip (refactor and perf preserve
# behavior, so their tests should pass before the change; investigate, research
# and chore have no red step).
#
# Usage: g01-red-proof.sh --task-dir .forge/<id> [--base <ref>]

GATE_ID=g01
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
forge_parse_args "$@"
forge_require_type

case "$TASK_TYPE" in
  bug|feature) ;;
  *) gate_skip "task type '$TASK_TYPE' has no red step; red-proof applies to bug and feature tasks." ;;
esac

LOG="$TASK_DIR/red.log"
RUN="scripts/lib/run-tests.sh --task-dir $TASK_DIR --log red"

[ -f "$LOG" ] || gate_fail "$LOG does not exist, so there is no proof the check failed before the change. Write the test first, run '$RUN' while the implementation is still missing, confirm it fails for the reason you expect, then make the change."

exit_line="$(sed -n 's/^exit: *//p' "$LOG" | head -n 1)"
cmd_line="$(sed -n 's/^command: *//p' "$LOG" | head -n 1)"
if [ -z "$cmd_line" ] || [ -z "$exit_line" ] || ! grep -q '^--- output ---$' "$LOG"; then
  gate_fail "$LOG was not written by run-tests.sh (missing the command, exit or output header). Do not write logs by hand; run '$RUN'."
fi
case "$exit_line" in ''|*[!0-9]*) gate_fail "$LOG has a non-numeric exit code '$exit_line'. Rerun '$RUN'." ;; esac

if [ "$exit_line" -eq 0 ]; then
  gate_fail "$LOG shows the tests passed (exit 0) before the change, so the new check does not detect the problem. Make the test exercise the missing behavior or the bug's reproduction until it fails on the unchanged code, rerun '$RUN', then implement."
fi

output="$(sed -n '/^--- output ---$/,$p' "$LOG" | sed '1d' | forge_strip_ansi)"

if [ "$exit_line" -eq 126 ] || [ "$exit_line" -eq 127 ]; then
  gate_fail "$LOG exited $exit_line, which means the test command '$cmd_line' could not run (not found or not executable). That is not a failing test. Install dependencies or set test_cmd in task.md, then rerun '$RUN'."
fi

names="$(printf '%s\n' "$output" | LC_ALL=C grep -E \
  -e '^[[:space:]]*FAIL[[:space:]]+[^[:space:]]' \
  -e '(×|✗|✕|❯ .*\.(test|spec)\.)' \
  -e '^test [^[:space:]]+ \.\.\. FAILED' \
  -e '^[[:space:]]*●[[:space:]]+' \
  -e '^[[:space:]]+[0-9]+\) [^[:space:]]' \
  -e '^(FAILED|FAIL:|--- FAIL:)[[:space:]]' 2>/dev/null | head -n 10)"

if [ -z "$names" ]; then
  gate_fail "$LOG has exit $exit_line but names no failing test, so the run probably broke before any test executed (a compile error, a syntax error, or a misconfigured runner). A red proof needs a test that runs and fails. Give the code under test a stub that compiles (for example a 'not implemented' body), rerun '$RUN', and check that a named test fails." "$(printf '%s\n' "$output" | tail -n 15)"
fi

gate_pass "$LOG shows exit $exit_line with failing tests: $(printf '%s' "$names" | head -n 3 | sed 's/^[[:space:]]*//' | tr '\n' ';')"
