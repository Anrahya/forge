#!/usr/bin/env bash
# run-tests.sh: resolve the project's test, lint, typecheck and format commands,
# and run the tests into a log the gates can read.
#
# Why: G1 and G2 trust logs, not claims. The model never types the test command
# itself; it calls this script, which picks the command from task.md or from the
# language defaults and records command, exit code and output.
#
# Usage (from the project root):
#   run-tests.sh --task-dir .forge/<id> --log red|green
#       Runs the test command, streams output, writes <task-dir>/<red|green>.log,
#       exits with the test command's exit code.
#   run-tests.sh --task-dir .forge/<id> --print test|lint|typecheck|format
#       Prints the resolved command(s), one per line, and exits 0.
#
# Resolution order: task.md front matter (test_cmd, lint_cmd, typecheck_cmd), then
# defaults by language (scripts/lib/detect-lang.sh):
#   ts    test: "npx vitest run" if package.json mentions vitest, else "npm test"
#         lint: "npx eslint ." if an eslint config exists
#         typecheck: "npx tsc --noEmit" if tsconfig.json exists
#   rust  test: "cargo test"; lint: "cargo clippy -- -D warnings"; format: "cargo fmt --check"
# lint_cmd replaces both the lint and the format defaults. When both languages are
# present the test commands are joined with " && ".
#
# Log format (one header field per line, then the raw output):
#   command: <cmd>
#   exit: <code>
#   started: <UTC ISO time>
#   finished: <UTC ISO time>
#   --- output ---
#
# This file is also sourced by scripts/lib/common.sh for forge_cmds and forge_test_cmd.

_FORGE_RT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_forge_eslint_configured() {
  local f
  for f in eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts eslint.config.mts eslint.config.cts \
           .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml; do
    [ -f "$f" ] && return 0
  done
  [ -f package.json ] && grep -q '"eslintConfig"' package.json && return 0
  return 1
}

# forge_cmds <kind> <task-dir>: prints the resolved command(s) for kind, one per line.
forge_cmds() {
  local kind="$1" td="$2" key="" override="" found=1 lang
  case "$kind" in
    test) key=test_cmd ;;
    lint|format) key=lint_cmd ;;
    typecheck) key=typecheck_cmd ;;
    *) echo "forge_cmds: unknown kind '$kind'" >&2; return 2 ;;
  esac
  if [ -f "$td/task.md" ]; then
    override="$("$_FORGE_RT_DIR/task-meta.sh" "$td/task.md" "$key" 2>/dev/null)"
    found=$?
  fi
  if [ "$found" -eq 0 ] && [ -n "$override" ]; then
    [ "$kind" = format ] && return 0
    printf '%s\n' "$override"
    return 0
  fi
  for lang in $("$_FORGE_RT_DIR/detect-lang.sh" .); do
    case "$lang:$kind" in
      ts:test)
        if grep -q '"vitest"' package.json 2>/dev/null; then echo "npx vitest run"; else echo "npm test"; fi ;;
      ts:lint) _forge_eslint_configured && echo "npx eslint ." ;;
      ts:typecheck) [ -f tsconfig.json ] && echo "npx tsc --noEmit" ;;
      rust:test) echo "cargo test" ;;
      rust:lint) echo "cargo clippy -- -D warnings" ;;
      rust:format) echo "cargo fmt --check" ;;
    esac
  done
  return 0
}

# forge_test_cmd <task-dir>: the single test command string (multiple joined with " && ").
forge_test_cmd() {
  forge_cmds test "$1" | awk 'NF { out = (out == "" ? $0 : out " && " $0) } END { print out }'
}

# forge_npx_missing <cmd>: prints each tool the command runs through npx that is not
# installed in node_modules/.bin. With CI set, npx would otherwise download a package
# of that name from the registry, which for "tsc" is an unrelated stub.
forge_npx_missing() {
  local w next=0
  set -f
  for w in $1; do
    if [ "$next" -eq 1 ]; then
      case "$w" in -*) continue ;; esac
      [ -x "node_modules/.bin/$w" ] || printf '%s\n' "$w"
      next=0
      continue
    fi
    [ "$w" = npx ] && next=1
  done
  set +f
}

# forge_run_logged <cmd> <logfile> [quiet]: run cmd, write the log, return its exit code.
forge_run_logged() {
  local cmd="$1" log="$2" quiet="${3:-}" tmp code started finished
  tmp="$log.tmp.$$"
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ -n "$quiet" ]; then
    CI=1 bash -c "$cmd" > "$tmp" 2>&1 < /dev/null
    code=$?
  else
    CI=1 bash -c "$cmd" 2>&1 < /dev/null | tee "$tmp"
    code=${PIPESTATUS[0]}
  fi
  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    printf 'command: %s\n' "$cmd"
    printf 'exit: %s\n' "$code"
    printf 'started: %s\n' "$started"
    printf 'finished: %s\n' "$finished"
    printf -- '--- output ---\n'
    cat "$tmp"
  } > "$log.new.$$"
  rm -f "$tmp"
  mv -f "$log.new.$$" "$log"
  return "$code"
}

_forge_run_tests_main() {
  local td="" logkind="" printkind=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --task-dir) td="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
      --task-dir=*) td="${1#*=}"; shift ;;
      --log) logkind="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
      --log=*) logkind="${1#*=}"; shift ;;
      --print) printkind="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
      --print=*) printkind="${1#*=}"; shift ;;
      *) echo "run-tests.sh: unknown argument '$1'. Usage: run-tests.sh --task-dir .forge/<id> --log red|green" >&2; return 2 ;;
    esac
  done
  if [ -z "$td" ] || [ ! -d "$td" ]; then
    echo "run-tests.sh: --task-dir must name an existing directory (got '$td')" >&2
    return 2
  fi
  if [ -n "$printkind" ]; then
    forge_cmds "$printkind" "$td"
    return $?
  fi
  case "$logkind" in
    red|green) ;;
    *) echo "run-tests.sh: --log must be red or green (got '$logkind')" >&2; return 2 ;;
  esac
  local cmd
  cmd="$(forge_test_cmd "$td")"
  if [ -z "$cmd" ]; then
    echo "run-tests.sh: no test command. Set test_cmd in $td/task.md front matter; no package.json or Cargo.toml was found to pick a default." >&2
    return 2
  fi
  local missing
  missing="$(forge_npx_missing "$cmd")"
  if [ -n "$missing" ]; then
    echo "run-tests.sh: $(printf '%s' "$missing" | tr '\n' ' ')not installed in node_modules/.bin. Run npm install first; npx would otherwise download an unrelated package. No log written." >&2
    return 2
  fi
  echo "forge: running: $cmd"
  forge_run_logged "$cmd" "$td/$logkind.log"
  local code=$?
  echo "forge: wrote $td/$logkind.log (exit $code)"
  return "$code"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _forge_run_tests_main "$@"
  exit $?
fi
