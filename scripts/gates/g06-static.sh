#!/usr/bin/env bash
# G6 static: lint, typecheck and format check all exit 0.
#
# Why: a change that does not typecheck or that the project's linter rejects is
# not done, whatever the tests say. Commands come from scripts/lib/run-tests.sh
# (task.md lint_cmd / typecheck_cmd, else language defaults):
#   ts:   "npx eslint ." if an eslint config exists; "npx tsc --noEmit" if tsconfig.json exists
#   rust: "cargo clippy -- -D warnings"; "cargo fmt --check"
# Each command runs from the project root; output goes to <task-dir>/g06.log.
# Skips (exit 2) when no command resolves, so an unconfigured project is visible.
#
# Usage: g06-static.sh --task-dir .forge/<id> [--base <ref>]

GATE_ID=g06
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
forge_parse_args "$@"

cmds=()
for kind in lint typecheck format; do
  while IFS= read -r c; do [ -n "$c" ] && cmds+=("$c"); done < <(forge_cmds "$kind" "$TASK_DIR")
done
if [ "${#cmds[@]}" -eq 0 ]; then
  gate_skip "no lint, typecheck or format command found (languages: $("$FORGE_LIB_DIR/detect-lang.sh" .)). Set lint_cmd or typecheck_cmd in task.md front matter if the project has them."
fi

LOG="$TASK_DIR/g06.log"
: > "$LOG"
failed=""
details=""
for c in "${cmds[@]}"; do
  missing="$(forge_npx_missing "$c")"
  if [ -n "$missing" ]; then
    failed="$failed '$c' (not installed: $(printf '%s' "$missing" | tr '\n' ' ' | sed 's/ $//'))"
    details="${details}--- $c: the tool is not in node_modules/.bin, so the check cannot run. Run npm install (npx would otherwise download an unrelated package).
"
    continue
  fi
  out="$(mktemp "${TMPDIR:-/tmp}/forge-g06.XXXXXX")"
  CI=1 bash -c "$c" > "$out" 2>&1 < /dev/null
  code=$?
  { printf '=== %s (exit %s)\n' "$c" "$code"; cat "$out"; } >> "$LOG"
  if [ "$code" -ne 0 ]; then
    failed="$failed '$c' (exit $code)"
    details="${details}--- $c (exit $code), last lines:
$(forge_strip_ansi < "$out" | sed '/^[[:space:]]*$/d' | tail -n 15)
"
  fi
  rm -f "$out"
done

if [ -n "$failed" ]; then
  gate_fail "static checks failed:$failed. Fix the reported errors in the code you changed. Do not silence them with disable comments, @ts-ignore, #[allow], or config edits; those paths are referee-owned. For a format failure, run the formatter on the files you changed. Full output: $LOG." "$(printf '%s' "$details")"
fi
gate_pass "all ${#cmds[@]} static check(s) exit 0: $(printf '%s; ' "${cmds[@]}")"
