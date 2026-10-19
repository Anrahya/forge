#!/usr/bin/env bash
# G7 tests-need-impl: with the implementation taken out, the tests must fail.
#
# Why: the most common weak-model test passes no matter what the code does (it
# asserts a mock was called, or checks a constant). If the suite still passes
# after every non-test source change is reverted to the base, the new tests do
# not test the change.
#
# How:
#   1. Split the diff under test into test and non-test source files (.ts/.js/.rs;
#      manifests, lockfiles, configs and docs are left alone).
#   2. Move each non-test source file aside into <task-dir>/.g07-backup/ and put
#      the merge-base version in its place (new files are removed, deleted files
#      come back). Rust files keep their current "#[cfg(test)]" tail, so inline
#      test modules stay new while the code above them reverts.
#   3. Run the project's test command (log: <task-dir>/g07.log). Rust builds go to
#      target/forge-g07 so the normal target dir never caches reverted code.
#   4. Restore every file with mv (content and mtime are preserved, so G2 is not
#      disturbed), verify each restored file by hash, then delete the backup.
#      A trap restores on any exit, including INT/TERM/HUP.
# This reverts committed work too. "git stash" would only cover the working tree,
# and BUILD commits each unit, so stash would leave the implementation in place.
# If a backup dir is already present (a previous run was killed with SIGKILL),
# the gate refuses to run and tells you how to restore.
#
# Known limit: a brand-new Rust module whose only tests are inline disappears with
# the module (its "mod" line reverts too), so those tests do not run. Test a new
# module from its parent's test module or from tests/.
#
# Applies to bug and feature. refactor and perf preserve behavior, and chore,
# investigate and research add no behavior, so they skip.
# Usage: g07-tests-need-impl.sh --task-dir .forge/<id> [--base <ref>]

GATE_ID=g07
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
forge_parse_args "$@"
forge_require_type
case "$TASK_TYPE" in
  bug|feature) ;;
  *) gate_skip "task type '$TASK_TYPE' does not add behavior, so there is no new test that must fail without the implementation." ;;
esac
forge_git_init

BK="$TASK_DIR/.g07-backup"
if [ -e "$BK" ]; then
  gate_fail "$BK exists, so an earlier G7 run did not finish restoring files. Do not run gates until it is restored: for each line 'M<TAB>path' or 'A<TAB>path' in $BK/manifest, move $BK/files/<path> back to <path>; for each 'D<TAB>path', delete <path>. Then remove $BK and rerun." "$( [ -f "$BK/manifest" ] && cat "$BK/manifest")"
fi

tcmd="$(forge_test_cmd "$TASK_DIR")"
[ -n "$tcmd" ] || gate_fail "no test command resolved. Set test_cmd in $TASK_DIR/task.md front matter."
npx_missing="$(forge_npx_missing "$tcmd")"
[ -z "$npx_missing" ] || gate_fail "the test command '$tcmd' needs $(printf '%s' "$npx_missing" | tr '\n' ' ')installed in node_modules/.bin, and it is not. Run npm install, then rerun. G7 will not let npx download a package."

impl=()
test_changed=0
while IFS="$(printf '\t')" read -r f lang istest cfg; do
  [ -n "$f" ] || continue
  [ "$lang" = other ] && continue
  if [ "$istest" = 1 ]; then test_changed=1; continue; fi
  impl+=("$f")
done < <(forge_file_attrs)
# deleted non-test source files also count as implementation changes
while IFS= read -r f; do
  [ -e "$f" ] && continue
  [ "$(forge_file_lang "$f")" = other ] && continue
  forge_is_test_path "$f" && { test_changed=1; continue; }
  impl+=("$f")
done < <(forge_changed_files)
# inline Rust test modules: added lines after #[cfg(test)] count as test changes
if [ "$test_changed" -eq 0 ]; then
  if forge_added_lines | awk -F'\t' '$1 ~ /\.rs$/ { print $1 "\t" $2 }' | while IFS="$(printf '\t')" read -r f ln; do
       c="$(forge_cfg_test_line "$f")"; [ "$c" -gt 0 ] && [ "$ln" -gt "$c" ] && { echo yes; break; }
     done | grep -q yes; then
    test_changed=1
  fi
fi

[ "${#impl[@]}" -gt 0 ] || gate_skip "no non-test source files changed, so there is no implementation to take out."
if [ "$test_changed" -eq 0 ]; then
  gate_fail "the diff changes implementation (${impl[*]}) but no test. A $TASK_TYPE needs a test that fails without the change: add one that exercises the new behavior or reproduces the bug, capture it red with scripts/lib/run-tests.sh --log red, then implement."
fi

# ---------- revert, run, restore ----------
mkdir -p "$BK/files" || gate_fail "cannot create $BK."
MAN="$BK/manifest"
: > "$MAN"
RESTORED=0

restore() {
  [ "$RESTORED" -eq 1 ] && return 0
  RESTORED=1
  local action path want got bad=""
  while IFS="$(printf '\t')" read -r action path want; do
    [ -n "$path" ] || continue
    case "$action" in
      M|A)
        mkdir -p "$(dirname "$path")"
        if [ -e "$BK/files/$path" ]; then mv -f "$BK/files/$path" "$path" || bad="$bad $path"; fi
        got="$(forge_hash "$path" 2>/dev/null)"
        [ "$got" = "$want" ] || bad="$bad $path"
        ;;
      D) rm -f "$path" || bad="$bad $path" ;;
    esac
  done < "$MAN"
  if [ -z "$bad" ]; then
    rm -rf "$BK"
  else
    printf 'GATE g07 FAIL: could not restore%s after the test run. The originals are in %s/files (see %s/manifest). Move them back by hand before doing anything else.\n' "$bad" "$BK" "$BK"
    exit 1
  fi
}
trap 'restore' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

base_version() { # <path>: writes the merge-base content of path to stdout
  git show "$MERGE_BASE:./$1" 2>/dev/null
}
in_base() { git cat-file -e "$MERGE_BASE:./$1" 2>/dev/null; }

for f in "${impl[@]}"; do
  if [ -e "$f" ]; then
    h="$(forge_hash "$f")"
    mkdir -p "$BK/files/$(dirname "$f")"
    if in_base "$f"; then
      printf 'M\t%s\t%s\n' "$f" "$h" >> "$MAN"
      cur_cfg=0
      case "$f" in *.rs) cur_cfg="$(forge_cfg_test_line "$f")" ;; esac
      mv "$f" "$BK/files/$f"
      if [ "$cur_cfg" -gt 0 ]; then
        # keep the current inline test module, revert the code above it
        { base_version "$f" | awk '/^[[:space:]]*#\[cfg\(test\)\]/ { exit } { print }'
          sed -n "${cur_cfg},\$p" "$BK/files/$f"; } > "$f"
      else
        base_version "$f" > "$f"
      fi
    else
      printf 'A\t%s\t%s\n' "$f" "$h" >> "$MAN"
      mv "$f" "$BK/files/$f"
    fi
  elif in_base "$f"; then
    printf 'D\t%s\t-\n' "$f" >> "$MAN"
    mkdir -p "$(dirname "$f")"
    base_version "$f" > "$f"
  fi
done

LOG="$TASK_DIR/g07.log"
{
  printf 'command: %s\n' "$tcmd"
  printf 'reverted to %s:\n' "$MERGE_BASE"
  sed 's/^/  /' "$MAN"
  printf -- '--- output ---\n'
} > "$LOG"
CI=1 CARGO_TARGET_DIR="${FORGE_G07_TARGET_DIR:-$PWD/target/forge-g07}" bash -c "$tcmd" >> "$LOG" 2>&1 < /dev/null
code=$?
printf 'exit: %s\n' "$code" >> "$LOG"

restore
trap - EXIT INT TERM HUP

if [ "$code" -eq 126 ] || [ "$code" -eq 127 ]; then
  gate_fail "the test command '$tcmd' could not run with the implementation reverted (exit $code), so G7 is inconclusive. Make the test command runnable, then rerun. Log: $LOG."
fi
if [ "$code" -eq 0 ]; then
  gate_fail "the tests still pass with every implementation change reverted (${impl[*]} back to the base version), so they do not test this change. Common causes: the test asserts on a mock or a constant, mocks the module under test, or only checks that a function was called. Rewrite the test to call the real code and assert the observable result the task asks for, confirm it fails on the old code, and rerun. Log: $LOG."
fi
gate_pass "tests fail (exit $code) with the implementation reverted (${impl[*]}) and all files were restored. Log: $LOG."
