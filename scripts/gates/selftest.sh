#!/usr/bin/env bash
# selftest.sh: prove every gate passes good input and fails bad input.
#
# Why: a gate that never fails proves nothing. For each gate this builds a
# throwaway git repo from fixtures/ (a TypeScript project with vitest, and a Rust
# crate when cargo is installed), creates a "good" state that must pass and one
# or more "bad" states that must fail, and asserts the exit code and the output
# contract (first status line "GATE gNN PASS|FAIL|SKIP:", no em dash anywhere).
#
# Usage: scripts/gates/selftest.sh [--only gNN[,gNN...]] [--keep]
#   --only   run only the listed gates (forge-verify cases use the id "verify",
#            task-meta.sh and detect-lang.sh cases use "lib")
#   --keep   keep the temp repos for inspection
#   --verbose  print every gate's output, not only for failed cases
# Requires node and npm (vitest and typescript are installed once into
# fixtures/ts/node_modules with npm install; no network means the self-test stops).
# Rust cases run only when cargo is on PATH.

set -o pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATES="$SELF_DIR"
FIX="$SELF_DIR/fixtures"
SCRIPTS="$(dirname "$SELF_DIR")"
LIB="$SCRIPTS/lib"
FORGE_ROOT="$(dirname "$SCRIPTS")"
EM="$(printf '\342\200\224')"

ONLY=""
KEEP=0
VERBOSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY=",${2:-},"; shift; [ $# -gt 0 ] && shift ;;
    --keep) KEEP=1; shift ;;
    --verbose|-v) VERBOSE=1; shift ;;
    *) echo "usage: selftest.sh [--only g03,g07] [--keep] [--verbose]" >&2; exit 2 ;;
  esac
done
want_gate() { [ -z "$ONLY" ] && return 0; case "$ONLY" in *",$1,"*) return 0 ;; esac; return 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/forge-selftest.XXXXXX")"
cleanup() { if [ "$KEEP" -eq 1 ]; then echo "kept: $WORK"; else rm -rf "$WORK"; fi; }
trap cleanup EXIT

NPASS=0; NFAIL=0
FAILED_CASES=""
PASS_PATHS=" "; FAIL_PATHS=" "; SKIP_PATHS=" "

# ---------- environment ----------

for tool in git node npm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "selftest: '$tool' is not on PATH; the TypeScript cases cannot run. Install it and rerun." >&2
    exit 1
  fi
done
HAVE_CARGO=0
if command -v cargo >/dev/null 2>&1; then HAVE_CARGO=1; fi
HAVE_CLIPPY=0
if [ "$HAVE_CARGO" -eq 1 ] && cargo clippy --version >/dev/null 2>&1 && cargo fmt --version >/dev/null 2>&1; then HAVE_CLIPPY=1; fi
echo "selftest: node $(node -v), npm $(npm -v), cargo: $([ "$HAVE_CARGO" -eq 1 ] && cargo --version || echo 'not found, Rust cases skipped')"

if [ ! -x "$FIX/ts/node_modules/.bin/vitest" ] || [ ! -x "$FIX/ts/node_modules/.bin/tsc" ]; then
  echo "selftest: installing vitest and typescript into $FIX/ts (once)"
  if ! (cd "$FIX/ts" && npm install --no-audit --no-fund --loglevel=error); then
    echo "selftest: npm install failed (no network or registry access?). The TypeScript cases need vitest; stopping instead of faking a pass." >&2
    exit 1
  fi
fi

export CARGO_NET_OFFLINE=true
export CARGO_TERM_COLOR=never
export NO_COLOR=1
export FORCE_COLOR=0

# ---------- helpers ----------

# new_repo <ts|rust> <type> [front matter lines...]: prints the repo dir. Base commit on main, work on branch "work".
new_repo() {
  local lang="$1" type="$2" dir
  shift 2
  dir="$(mktemp -d "$WORK/repo-$lang.XXXXXX")"
  (
    cd "$FIX/$lang" && tar cf - --exclude node_modules --exclude target --exclude gitignore.txt .
  ) | (cd "$dir" && tar xf -)
  cp "$FIX/$lang/gitignore.txt" "$dir/.gitignore"
  [ "$lang" = ts ] && ln -s "$FIX/ts/node_modules" "$dir/node_modules"
  (
    cd "$dir" || exit 1
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.name forge-selftest
    git config user.email selftest@forge.invalid
    git config commit.gpgsign false
    git config core.hooksPath /dev/null
    git add -A && git commit -q -m base
    git checkout -q -b work
    mkdir -p .forge/t1
  )
  write_task "$dir" "$type" "$@"
  printf '%s\n' "$dir"
}

# write_task <dir> <type> [extra front matter lines...]
write_task() {
  local dir="$1" type="$2"; shift 2
  {
    echo "---"
    echo "type: $type"
    echo "surface: none"
    echo "non_goals:"
    echo "  - src/legacy/**"
    for l in "$@"; do echo "$l"; done
    echo "---"
    echo "# Task"
    echo
    echo "## Goal"
    echo "Self-test task."
  } > "$dir/.forge/t1/task.md"
}

# check <gate-id> <label> <want-exit> <must-contain> <dir> <script> [args...]
check() {
  local gid="$1" label="$2" want="$3" must="$4" dir="$5" script="$6"; shift 6
  local out got first ok=1 why=""
  out="$(cd "$dir" && bash "$GATES/$script" --task-dir .forge/t1 "$@" 2>&1)"
  got=$?
  first="$(printf '%s\n' "$out" | grep -E '^GATE g[0-9]{2} (PASS|FAIL|SKIP):' | head -n 1)"
  [ "$got" -eq "$want" ] || { ok=0; why="exit $got, wanted $want"; }
  case "$want" in
    0) printf '%s' "$first" | grep -q " PASS:" || { ok=0; why="$why; no PASS line"; } ;;
    1) printf '%s' "$first" | grep -q " FAIL:" || { ok=0; why="$why; no FAIL line"; } ;;
    2) printf '%s' "$first" | grep -q " SKIP:" || { ok=0; why="$why; no SKIP line"; } ;;
  esac
  if [ -n "$must" ]; then
    local m rest="$must"
    while [ -n "$rest" ]; do
      m="${rest%%|*}"
      if [ "$m" = "$rest" ]; then rest=""; else rest="${rest#*|}"; fi
      printf '%s' "$out" | grep -qF -- "$m" || { ok=0; why="$why; output lacks '$m'"; }
    done
  fi
  if printf '%s' "$out" | LC_ALL=C grep -q "$EM"; then ok=0; why="$why; output contains an em dash"; fi
  record "$gid" "$label" "$want" "$ok" "$why" "$out"
}

# record <gid> <label> <want> <ok> <why> <output>
record() {
  local gid="$1" label="$2" want="$3" ok="$4" why="$5" out="$6" kind
  case "$want" in 0) kind=pass ;; 1) kind=fail ;; *) kind=skip ;; esac
  if [ "$ok" -eq 1 ]; then
    NPASS=$((NPASS + 1))
    printf 'ok    %-6s %-5s %s\n' "$gid" "$kind" "$label"
    [ "$VERBOSE" -eq 1 ] && [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/        | /' | head -n 40
    case "$kind" in
      pass) PASS_PATHS="$PASS_PATHS$gid " ;;
      fail) FAIL_PATHS="$FAIL_PATHS$gid " ;;
      skip) SKIP_PATHS="$SKIP_PATHS$gid " ;;
    esac
  else
    NFAIL=$((NFAIL + 1))
    FAILED_CASES="$FAILED_CASES  $gid $label ($why)
"
    printf 'FAIL  %-6s %-5s %s (%s)\n' "$gid" "$kind" "$label" "$why"
    printf '%s\n' "$out" | sed 's/^/        | /' | head -n 40
  fi
}

# assert <gid> <label> <condition-command...>: record a plain assertion as a pass-path check.
assert_true() {
  local gid="$1" label="$2"; shift 2
  if "$@"; then record "$gid" "$label" 0 1 "" ""; else record "$gid" "$label" 0 0 "assertion failed: $*" ""; fi
}

age() { touch -t 202001010000 "$@"; }   # make files old, deterministically
rt() { (cd "$1" && bash "$LIB/run-tests.sh" --task-dir .forge/t1 --log "$2" > /dev/null 2>&1); }

# ---------- TypeScript mutations ----------

ts_impl_multiply() {
  cat >> "$1/src/math.ts" <<'EOF'

export function multiply(a: number, b: number): number {
  return a * b;
}
EOF
}
ts_test_multiply() {
  cat > "$1/src/math.test.ts" <<'EOF'
import { describe, expect, it } from "vitest";
import { add, multiply } from "./math";

describe("add", () => {
  it("adds two numbers", () => {
    expect(add(2, 3)).toBe(5);
  });
});

describe("multiply", () => {
  it("multiplies two numbers", () => {
    expect(multiply(2, 3)).toBe(6);
  });
});
EOF
}
# a feature that is ready to verify: test red first, then impl, then green
ts_feature_done() {
  ts_test_multiply "$1"
  rt "$1" red
  ts_impl_multiply "$1"
  rt "$1" green
}

# ---------- Rust mutations ----------

rs_write_lib() { # <dir> <body-before-tests> <tests-inside-mod>
  {
    printf '%s\n' "$2"
    printf '\n#[cfg(test)]\nmod tests {\n    use super::*;\n\n    #[test]\n    fn adds_two_numbers() {\n        assert_eq!(add(2, 3), 5);\n    }\n'
    [ -n "$3" ] && printf '\n%s\n' "$3"
    printf '}\n'
  } > "$1/src/lib.rs"
}
RS_ADD='pub fn add(a: i32, b: i32) -> i32 {
    a + b
}'
RS_MUL="$RS_ADD

pub fn multiply(a: i32, b: i32) -> i32 {
    a * b
}"
RS_MUL_STUB="$RS_ADD

pub fn multiply(_a: i32, _b: i32) -> i32 {
    0
}"
RS_MUL_TEST='    #[test]
    fn multiplies_two_numbers() {
        assert_eq!(multiply(2, 3), 6);
    }'

# =====================================================================
echo "selftest: work dir $WORK"

# ---------- lib: task-meta.sh and detect-lang.sh ----------
if want_gate lib; then
  tm="$WORK/task-meta.md"
  cat > "$tm" <<'EOF'
---
type: feature            # bug | feature
budget: 600              # lines
non_goals: []            # e.g. ["src/billing/**"]
inline: ["a/**", 'b' ]   # comment
block:
  - x/**
  - "y z"
test_cmd: ""             # leave empty to auto-detect
lint_cmd: "npm run lint # not a comment"
---
## Goal
EOF
  meta() { "$LIB/task-meta.sh" "$tm" "$1" | tr '\n' '|'; }
  assert_true lib "task-meta: scalar with trailing comment" [ "$(meta type)" = "feature|" ]
  assert_true lib "task-meta: empty inline list prints nothing" [ "$(meta non_goals)" = "" ]
  assert_true lib "task-meta: inline list with quotes" [ "$(meta inline)" = "a/**|b|" ]
  assert_true lib "task-meta: block list" [ "$(meta block)" = "x/**|y z|" ]
  assert_true lib "task-meta: quoted empty string with comment is empty" [ "$(meta test_cmd)" = "|" ]
  assert_true lib "task-meta: # inside quotes is kept" [ "$(meta lint_cmd)" = "npm run lint # not a comment|" ]
  "$LIB/task-meta.sh" "$tm" absent > /dev/null; c=$?
  assert_true lib "task-meta: absent key exits 1" [ "$c" -eq 1 ]
  printf 'no front matter\n' > "$tm"; "$LIB/task-meta.sh" "$tm" type > /dev/null; c=$?
  assert_true lib "task-meta: no front matter exits 2" [ "$c" -eq 2 ]
  ld="$WORK/langs"; mkdir -p "$ld"
  assert_true lib "detect-lang: nothing is unknown" [ "$("$LIB/detect-lang.sh" "$ld")" = unknown ]
  touch "$ld/package.json" "$ld/Cargo.toml"
  assert_true lib "detect-lang: both manifests" [ "$("$LIB/detect-lang.sh" "$ld")" = "ts rust" ]
fi

# ---------- G0 phase-artifacts ----------
if want_gate g00; then
  export FORGE_TEMPLATES_DIR="$FIX/templates"
  d="$(new_repo ts bug)"
  cat > "$d/.forge/t1/ground.md" <<'EOF'
# Ground: t1

## Overview
The math module exports pure arithmetic helpers.

## How it works
add() returns a + b (src/math.ts:1).

## Files likely touched
- src/math.ts
EOF
  check g00 "ground.md with every section filled" 0 "" "$d" g00-phase-artifacts.sh --phase ground
  sed -i.bak '/^## How it works/,/^## Files/{/^## Files/!d;}' "$d/.forge/t1/ground.md"
  check g00 "ground.md missing a section" 1 "How it works" "$d" g00-phase-artifacts.sh --phase ground
  cat > "$d/.forge/t1/ground.md" <<'EOF'
## Overview
The math module exports pure arithmetic helpers.

## How it works
<!-- The mechanism, traced through the code, with file:line citations. -->

## Files likely touched
- path/to/file
EOF
  check g00 "ground.md sections left as template placeholders" 1 "How it works|Files likely touched" "$d" g00-phase-artifacts.sh --phase ground
  rm -f "$d/.forge/t1/ground.md"
  check g00 "ground.md absent" 1 "is missing" "$d" g00-phase-artifacts.sh --phase ground

  d="$(new_repo ts feature)"
  cat > "$d/.forge/t1/shape.md" <<'EOF'
## Data shape
Two pure functions over number.

## Candidates
### Candidate A
A multiply(a, b) function beside add.

## Pick
Candidate A.
EOF
  check g00 "feature shape.md with one candidate" 1 "two structurally distinct candidates" "$d" g00-phase-artifacts.sh --phase shape
  cat >> "$d/.forge/t1/shape.md" <<'EOF'
EOF
  awk '/^## Pick/ { print "### Candidate B"; print "A generic fold(op, xs) helper."; print "" } { print }' "$d/.forge/t1/shape.md" > "$d/x" && mv "$d/x" "$d/.forge/t1/shape.md"
  check g00 "feature shape.md with two candidates" 0 "" "$d" g00-phase-artifacts.sh --phase shape
  FORGE_TEMPLATES_DIR="$WORK/no-templates" check g00 "no template for the phase" 2 "" "$d" g00-phase-artifacts.sh --phase shape
  unset FORGE_TEMPLATES_DIR
fi

# ---------- G1 red-proof ----------
if want_gate g01; then
  d="$(new_repo ts feature)"
  ts_test_multiply "$d"; rt "$d" red
  check g01 "ts: red.log from a failing new test" 0 "multiplies two numbers" "$d" g01-red-proof.sh

  d="$(new_repo ts feature)"
  check g01 "ts: no red.log" 1 "does not exist" "$d" g01-red-proof.sh
  rt "$d" red
  check g01 "ts: red.log from a passing run" 1 "tests passed (exit 0)" "$d" g01-red-proof.sh

  d="$(new_repo ts feature 'test_cmd: forge-no-such-command-xyz')"
  rt "$d" red
  check g01 "ts: red.log from a missing command (exit 127)" 1 "could not run" "$d" g01-red-proof.sh

  d="$(new_repo ts feature 'test_cmd: "echo boom; exit 1"')"
  rt "$d" red
  check g01 "ts: red.log non-zero but no failing test named" 1 "names no failing test" "$d" g01-red-proof.sh

  d="$(new_repo ts feature)"
  printf 'exit: 1\nFAIL something\n' > "$d/.forge/t1/red.log"
  check g01 "ts: hand-written red.log" 1 "not written by run-tests.sh" "$d" g01-red-proof.sh

  d="$(new_repo ts refactor)"
  check g01 "refactor task skips" 2 "" "$d" g01-red-proof.sh

  if [ "$HAVE_CARGO" -eq 1 ]; then
    d="$(new_repo rust feature)"
    rs_write_lib "$d" "$RS_MUL_STUB" "$RS_MUL_TEST"; rt "$d" red
    check g01 "rust: red.log from a failing test against a stub" 0 "multiplies_two_numbers" "$d" g01-red-proof.sh
    d="$(new_repo rust feature)"
    rs_write_lib "$d" "$RS_ADD" "$RS_MUL_TEST"; rt "$d" red
    check g01 "rust: red.log from a compile error" 1 "names no failing test" "$d" g01-red-proof.sh
  else
    echo "skip  g01    rust cases: cargo not found"
  fi
fi

# ---------- G2 green-after-edit ----------
if want_gate g02; then
  d="$(new_repo ts feature)"
  ts_feature_done "$d"
  check g02 "ts: green.log after the last edit" 0 "" "$d" g02-green-after-edit.sh
  age "$d/.forge/t1/green.log"
  check g02 "ts: source edited after green.log" 1 "src/math.ts" "$d" g02-green-after-edit.sh

  d="$(new_repo ts feature)"
  check g02 "ts: no green.log" 1 "does not exist" "$d" g02-green-after-edit.sh
  ts_test_multiply "$d"; rt "$d" green
  check g02 "ts: green.log with failing tests" 1 "exited 1" "$d" g02-green-after-edit.sh
  ts_impl_multiply "$d"
  (cd "$d" && bash "$LIB/run-tests.sh" --task-dir .forge/t1 --print test > /dev/null)
  ( cd "$d" && . "$LIB/run-tests.sh" && forge_run_logged "npx vitest run src/math.test.ts -t add" .forge/t1/green.log quiet )
  check g02 "ts: green.log from a narrowed command" 1 "must cover the whole suite" "$d" g02-green-after-edit.sh

  if [ "$HAVE_CARGO" -eq 1 ]; then
    d="$(new_repo rust feature)"
    rs_write_lib "$d" "$RS_MUL" "$RS_MUL_TEST"; rt "$d" green
    check g02 "rust: green.log after the last edit" 0 "" "$d" g02-green-after-edit.sh
    age "$d/.forge/t1/green.log"
    check g02 "rust: source edited after green.log" 1 "src/lib.rs" "$d" g02-green-after-edit.sh
  fi
fi

# ---------- G3 diff-hygiene ----------
if want_gate g03; then
  d="$(new_repo ts feature)"
  ts_impl_multiply "$d"; ts_test_multiply "$d"
  cat >> "$d/src/math.test.ts" <<'EOF'

it("logs in tests are allowed", () => {
  console.log("debug output in a test file");
  expect(multiply(1, 1)).toBe(1);
});
EOF
  check g03 "ts: clean change, console.log only in a test file" 0 "" "$d" g03-diff-hygiene.sh
  cat >> "$d/src/math.ts" <<'EOF'

// TODO: handle overflow
export function unsafeDivide(a: number, b: number): number {
  console.log("dividing", a, b);
  return (a as any) / b;
}
EOF
  check g03 "ts: TODO, console.log and as any in source" 1 "TODO/FIXME marker|console.log in non-test code|\"as any\" type escape" "$d" g03-diff-hygiene.sh

  d="$(new_repo ts feature)"
  cat >> "$d/src/math.ts" <<'EOF'

// Added the subtract helper for the task
export function subtract(a: number, b: number): number {
  // const old = a - b - 0;
  // return old;
  try {
    return a - b;
  } catch {}
  return 0;
}
EOF
  cat >> "$d/src/math.test.ts" <<'EOF'

it.only("focused test", () => {
  expect(add(1, 1)).toBe(2);
});
EOF
  check g03 "ts: narration, commented-out code, empty catch, .only" 1 "narrates the change|commented-out code block|empty catch block|skipped or focused test" "$d" g03-diff-hygiene.sh

  d="$(new_repo ts feature)"
  printf '// eslint-disable-next-line\n// @ts-ignore\nexport const x: number = 1;\n' >> "$d/src/math.ts"
  check g03 "ts: eslint-disable and @ts-ignore" 1 "eslint-disable suppression|@ts-ignore/@ts-nocheck suppression" "$d" g03-diff-hygiene.sh

  d="$(new_repo ts feature)"
  printf '# notes\nTODO in a markdown file is not code\n' > "$d/NOTES.md"
  check g03 "ts: only a non-code file changed" 2 "" "$d" g03-diff-hygiene.sh

  if [ "$HAVE_CARGO" -eq 1 ]; then
    d="$(new_repo rust feature)"
    rs_write_lib "$d" "$RS_MUL" "$RS_MUL_TEST
    #[test]
    fn unwrap_is_fine_in_tests() {
        let v: Option<i32> = Some(add(1, 2));
        assert_eq!(v.unwrap(), 3);
    }"
    check g03 "rust: unwrap() inside #[cfg(test)] module" 0 "" "$d" g03-diff-hygiene.sh
    rs_write_lib "$d" "$RS_ADD

#[allow(dead_code)]
pub fn parse(s: &str) -> i32 {
    s.parse().unwrap()
}" ""
    check g03 "rust: unwrap() and #[allow] in library code" 1 "unwrap() in non-test Rust|new #[allow(...)] lint suppression" "$d" g03-diff-hygiene.sh
  fi
fi

# ---------- G4 scope ----------
if want_gate g04; then
  d="$(new_repo ts feature)"
  printf '## Files likely touched\n- `src/math.ts`\n' > "$d/.forge/t1/ground.md"
  ts_impl_multiply "$d"; ts_test_multiply "$d"
  check g04 "ts: changes outside non-goals (unlisted file only noted)" 0 "NOTE g04|src/math.test.ts" "$d" g04-scope.sh
  mkdir -p "$d/src/legacy" && printf 'export const old = 1;\n' > "$d/src/legacy/old.ts"
  check g04 "ts: new file under a non-goal glob" 1 "src/legacy/old.ts" "$d" g04-scope.sh
  rm -rf "$d/src/legacy"
  write_task "$d" feature
  sed -i.bak 's#  - src/legacy/\*\*#  - src/math.test.ts#' "$d/.forge/t1/task.md"
  check g04 "ts: edit to a file listed as a non-goal" 1 "src/math.test.ts (non-goal" "$d" g04-scope.sh
fi

# ---------- G5 diff-budget ----------
if want_gate g05; then
  d="$(new_repo ts feature 'budget: 30')"
  ts_impl_multiply "$d"; ts_test_multiply "$d"
  check g05 "ts: 11-line diff under a budget of 30" 0 "" "$d" g05-diff-budget.sh
  write_task "$d" feature 'budget: 5'
  check g05 "ts: same diff over a budget of 5" 1 "over the budget of 5" "$d" g05-diff-budget.sh
  write_task "$d" bug
  for i in $(seq 1 160); do echo "export const c$i = $i;"; done >> "$d/src/math.ts"
  check g05 "ts: 160+ lines over the bug default of 150" 1 "default for bug" "$d" g05-diff-budget.sh
fi

# ---------- G6 static ----------
if want_gate g06; then
  d="$(new_repo ts feature)"
  ts_impl_multiply "$d"
  check g06 "ts: tsc --noEmit clean" 0 "npx tsc --noEmit" "$d" g06-static.sh
  printf 'export const broken: number = "not a number";\n' >> "$d/src/math.ts"
  check g06 "ts: type error" 1 "npx tsc --noEmit" "$d" g06-static.sh
  rm -f "$d/node_modules"
  check g06 "ts: typescript not installed (npx must not download)" 1 "not installed" "$d" g06-static.sh
  (cd "$d" && bash "$LIB/run-tests.sh" --task-dir .forge/t1 --log green > /dev/null 2>&1); c=$?
  assert_true g06 "run-tests.sh refuses npx without local vitest and writes no log" [ "$c" -eq 2 -a ! -f "$d/.forge/t1/green.log" ]
  rm -f "$d/tsconfig.json"
  check g06 "ts: no lint or typecheck configured" 2 "" "$d" g06-static.sh
  if [ "$HAVE_CLIPPY" -eq 1 ]; then
    d="$(new_repo rust feature)"
    rs_write_lib "$d" "$RS_MUL" "$RS_MUL_TEST"
    check g06 "rust: clippy and fmt clean" 0 "" "$d" g06-static.sh
    printf 'pub fn sub(a:i32,b:i32)->i32{a-b}\n' >> "$d/src/lib.rs"
    check g06 "rust: unformatted code" 1 "cargo fmt --check" "$d" g06-static.sh
    rs_write_lib "$d" "$RS_ADD

pub fn is_positive(x: i32) -> bool {
    if x > 0 {
        true
    } else {
        false
    }
}" ""
    check g06 "rust: clippy warning (needless_bool)" 1 "cargo clippy -- -D warnings" "$d" g06-static.sh
  else
    echo "skip  g06    rust cases: cargo clippy/fmt not found"
  fi
fi

# ---------- G7 tests-need-impl ----------
if want_gate g07; then
  d="$(new_repo ts feature)"
  ts_impl_multiply "$d"; ts_test_multiply "$d"
  before="$(cd "$d" && shasum -a 256 src/math.ts src/math.test.ts 2>/dev/null || sha256sum src/math.ts src/math.test.ts)"
  mt_before="$(cd "$d" && ls -lT src/math.ts 2>/dev/null || ls -l --time-style=full-iso src/math.ts)"
  check g07 "ts: new test fails without the implementation" 0 "all files were restored" "$d" g07-tests-need-impl.sh
  after="$(cd "$d" && shasum -a 256 src/math.ts src/math.test.ts 2>/dev/null || sha256sum src/math.ts src/math.test.ts)"
  mt_after="$(cd "$d" && ls -lT src/math.ts 2>/dev/null || ls -l --time-style=full-iso src/math.ts)"
  assert_true g07 "ts: files byte-identical after the run" [ "$before" = "$after" ]
  assert_true g07 "ts: mtime preserved after the run" [ "$mt_before" = "$mt_after" ]
  assert_true g07 "ts: backup dir removed" [ ! -e "$d/.forge/t1/.g07-backup" ]

  (cd "$d" && git add -A && git commit -q -m "unit 1")
  check g07 "ts: implementation already committed is still reverted" 0 "" "$d" g07-tests-need-impl.sh
  assert_true g07 "ts: committed source tree clean after the run" [ -z "$(cd "$d" && git status --porcelain --untracked-files=no -- src)" ]

  d="$(new_repo ts feature)"
  ts_impl_multiply "$d"
  cat >> "$d/src/math.test.ts" <<'EOF'

it("passes whatever multiply does", () => {
  expect(add(1, 1)).toBe(2);
});
EOF
  check g07 "ts: new test passes without the implementation" 1 "still pass with every implementation change reverted" "$d" g07-tests-need-impl.sh
  assert_true g07 "ts: implementation restored after a failing verdict" grep -q multiply "$d/src/math.ts"

  d="$(new_repo ts feature)"
  ts_impl_multiply "$d"
  check g07 "ts: implementation changed with no test" 1 "no test" "$d" g07-tests-need-impl.sh

  d="$(new_repo ts feature 'test_cmd: "kill -TERM $PPID; sleep 5"')"
  ts_impl_multiply "$d"; ts_test_multiply "$d"
  (cd "$d" && bash "$GATES/g07-tests-need-impl.sh" --task-dir .forge/t1 > /dev/null 2>&1)
  code=$?
  assert_true g07 "ts: gate killed by SIGTERM mid-run exits 143 through its trap" [ "$code" -eq 143 ]
  assert_true g07 "ts: files restored after SIGTERM" grep -q multiply "$d/src/math.ts"
  assert_true g07 "ts: no backup left after SIGTERM" [ ! -e "$d/.forge/t1/.g07-backup" ]

  d="$(new_repo ts feature)"
  ts_impl_multiply "$d"; ts_test_multiply "$d"
  mkdir -p "$d/.forge/t1/.g07-backup"
  check g07 "ts: refuses to run over a leftover backup" 1 "did not finish restoring" "$d" g07-tests-need-impl.sh

  d="$(new_repo ts refactor)"
  check g07 "refactor task skips" 2 "" "$d" g07-tests-need-impl.sh

  if [ "$HAVE_CARGO" -eq 1 ]; then
    d="$(new_repo rust feature)"
    rs_write_lib "$d" "$RS_MUL" "$RS_MUL_TEST"
    check g07 "rust: inline test module kept, code above it reverted" 0 "" "$d" g07-tests-need-impl.sh
    assert_true g07 "rust: lib.rs restored" grep -q 'a \* b' "$d/src/lib.rs"
    d="$(new_repo rust feature)"
    rs_write_lib "$d" "$RS_MUL" '    #[test]
    fn adds_again() {
        assert_eq!(add(1, 1), 2);
    }'
    check g07 "rust: new test passes without the implementation" 1 "still pass" "$d" g07-tests-need-impl.sh
  fi
fi

# ---------- G8 test-quality ----------
if want_gate g08; then
  d="$(new_repo ts feature)"
  ts_impl_multiply "$d"; ts_test_multiply "$d"
  check g08 "ts: new test with a real assertion" 0 "" "$d" g08-test-quality.sh
  cat >> "$d/src/math.test.ts" <<'EOF'

it("runs multiply", () => {
  multiply(2, 3);
});
EOF
  check g08 "ts: new test with zero assertions" 1 "has no assertions" "$d" g08-test-quality.sh

  d="$(new_repo ts feature)"
  ts_impl_multiply "$d"
  cat > "$d/src/math.test.ts" <<'EOF'
import { describe, expect, it, vi } from "vitest";
import { add, multiply } from "./math";

vi.mock("./math");

describe("add", () => {
  it("adds two numbers", () => {
    expect(add(2, 3)).toBe(5);
  });
  it("is true", () => {
    expect(true).toBe(true);
  });
  it("matches itself", () => {
    expect(multiply(2, 3)).toBe(multiply(2, 3));
  });
  it("snapshots", () => {
    expect(multiply(2, 3)).toMatchSnapshot();
  });
});
EOF
  check g08 "ts: literal assert, self-computed expected, mocked subject, snapshot-only" 1 "asserts a literal|computed by calling multiply|mocks ./math|only through snapshots" "$d" g08-test-quality.sh

  d="$(new_repo ts feature)"
  ts_impl_multiply "$d"
  check g08 "ts: no test code in the diff" 2 "" "$d" g08-test-quality.sh

  if [ "$HAVE_CARGO" -eq 1 ]; then
    d="$(new_repo rust feature)"
    rs_write_lib "$d" "$RS_MUL" "$RS_MUL_TEST"
    check g08 "rust: new #[test] with assert_eq!" 0 "" "$d" g08-test-quality.sh
    rs_write_lib "$d" "$RS_MUL" '    #[test]
    fn calls_multiply() {
        let _ = multiply(2, 3);
    }

    #[test]
    fn always_true() {
        assert!(true);
    }'
    check g08 "rust: #[test] with no assertion and assert!(true)" 1 "has no assertions|asserts a literal" "$d" g08-test-quality.sh
  fi
fi

# ---------- G9 runtime ----------
if want_gate g09; then
  d="$(new_repo ts feature)"
  check g09 "surface none skips" 2 "" "$d" g09-runtime.sh
  write_task "$d" feature
  sed -i.bak 's/^surface: none/surface: cli/' "$d/.forge/t1/task.md"
  check g09 "surface cli with no verify skill" 1 "forge-verify-setup" "$d" g09-runtime.sh
  mkdir -p "$d/.agents/skills/verify-app/features"
  check g09 "verify skill with no feature files" 1 "no feature files" "$d" g09-runtime.sh
  cat > "$d/.agents/skills/verify-app/features/add.md" <<'EOF'
# Feature: add

## Drive
```bash
out="$(node --input-type=module -e 'import("./src/math.ts").catch(() => null); console.log(2 + 3)')"
test "$out" = "5"
```
EOF
  check g09 "journey reaches the expected end state" 0 "1 runtime journey" "$d" g09-runtime.sh
  cat > "$d/.agents/skills/verify-app/features/broken.md" <<'EOF'
# Feature: broken

## Drive
```bash
echo "expected 6, got 5"
exit 1
```
EOF
  check g09 "journey exits non-zero" 1 "broken.md: exit 1" "$d" g09-runtime.sh
  printf '# Feature: vague\n\n## Drive\nClick around and check it looks right.\n' > "$d/.agents/skills/verify-app/features/broken.md"
  check g09 "feature with no bash block is inconclusive" 1 "inconclusive" "$d" g09-runtime.sh
fi

# ---------- G10 evidence-integrity ----------
if want_gate g10; then
  d="$(new_repo ts feature)"
  check g10 "no report.md or decisions.tsv yet" 2 "" "$d" g10-evidence-integrity.sh
  ts_feature_done "$d"
  cat > "$d/.forge/t1/report.md" <<'EOF'
# Report

multiply() returns the product of two numbers. evidence: `.forge/t1/green.log`
The test failed before the change. Evidence: .forge/t1/red.log
Overflow behavior was not checked. evidence: guess
EOF
  printf 'ts\tphase\tdecision\twhy\tevidence\tresult\n2026-10-20\tbuild\tadd multiply\tfeature\t.forge/t1/green.log\tVERIFIED\n' > "$d/.forge/t1/decisions.tsv"
  check g10 "pointers exist and are newer than the code" 0 "" "$d" g10-evidence-integrity.sh
  printf 'Benchmarks ran. evidence: .forge/t1/bench.log\n' >> "$d/.forge/t1/report.md"
  check g10 "dangling pointer" 1 "bench.log' does not exist" "$d" g10-evidence-integrity.sh
  sed -i.bak '/bench.log/d' "$d/.forge/t1/report.md"
  age "$d/.forge/t1/green.log"
  check g10 "stale pointer (log older than the code)" 1 "is older than changed file" "$d" g10-evidence-integrity.sh
  rt "$d" green
  printf '2026-10-20\tbuild\tsecond decision\tbecause\t\tVERIFIED\n' >> "$d/.forge/t1/decisions.tsv"
  check g10 "decisions.tsv row with an empty evidence cell" 1 "has no file pointer" "$d" g10-evidence-integrity.sh
fi

# ---------- G11 referee-readonly ----------
if want_gate g11; then
  d="$(new_repo ts feature)"
  ts_impl_multiply "$d"; ts_test_multiply "$d"
  check g11 "ts: only source and test files changed" 0 "" "$d" g11-referee-readonly.sh
  sed -i.bak 's/"strict": true/"strict": false/' "$d/tsconfig.json" && rm -f "$d/tsconfig.json.bak"
  check g11 "ts: tsconfig.json edited" 1 "tsconfig.json (typecheck config)" "$d" g11-referee-readonly.sh
  (cd "$d" && git checkout -q -- tsconfig.json)
  printf 'export default {};\n' > "$d/vitest.config.ts"
  mkdir -p "$d/.github/workflows" "$d/scripts/gates"
  printf 'on: push\n' > "$d/.github/workflows/ci.yml"
  printf 'exit 0\n' > "$d/scripts/gates/g07-tests-need-impl.sh"
  check g11 "ts: vitest config, CI workflow and gate script added" 1 "vitest.config.ts|ci.yml|scripts/gates/g07" "$d" g11-referee-readonly.sh
  rm -rf "$d/vitest.config.ts" "$d/.github" "$d/scripts"
  (cd "$d" && bash "$SCRIPTS/forge-verify.sh" --task-dir .forge/t1 --phase shape > /dev/null 2>&1)
  check g11 "ts: verify.log as written by forge-verify.sh" 0 "" "$d" g11-referee-readonly.sh
  printf 'result: PASS\n' >> "$d/.forge/t1/verify.log"
  check g11 "ts: verify.log edited after the run" 1 "edited after forge-verify.sh wrote it" "$d" g11-referee-readonly.sh
  rm -f "$d/.forge/t1/verify.log.sha256"
  check g11 "ts: verify.log with no runner hash" 1 "not written by the runner" "$d" g11-referee-readonly.sh
  if [ "$HAVE_CARGO" -eq 1 ]; then
    d="$(new_repo rust feature)"
    sed -i.bak 's/^version = "0.1.0"/version = "0.1.1"/' "$d/Cargo.toml" && rm -f "$d/Cargo.toml.bak"
    check g11 "rust: Cargo.toml change outside [dev-dependencies]" 0 "" "$d" g11-referee-readonly.sh
    printf 'proptest = "1"\n' >> "$d/Cargo.toml"
    printf 'too-many-arguments-threshold = 20\n' > "$d/clippy.toml"
    check g11 "rust: [dev-dependencies] edited and clippy.toml added" 1 "[dev-dependencies] changed|clippy.toml" "$d" g11-referee-readonly.sh
  fi
fi

# ---------- G12 unslop-lint ----------
if want_gate g12; then
  d="$(new_repo ts feature)"
  check g12 "no report yet" 2 "" "$d" g12-unslop-lint.sh
  check g12 "report phase with no report.md" 1 "does not exist" "$d" g12-unslop-lint.sh --phase report
  cat > "$d/.forge/t1/report.md" <<'EOF'
# Report

multiply() now returns the product of two numbers. The new test failed before the change and passes after it.

```
robust example inside a code block is ignored
```

The flag `--robust` in inline code is ignored too.
EOF
  check g12 "plain report" 0 "" "$d" g12-unslop-lint.sh
  {
    printf 'This change is not just a fix but a %s improvement.\n' "robust"
    printf 'The parser %s handles empty input.\n' "seamlessly"
    printf 'Results %s good.\n' "$EM"
    printf 'Certainly, the tests pass.\n'
    printf -- '- **Risk:** none known.\n'
  } >> "$d/.forge/t1/report.md"
  check g12 "em dash, not just, AI vocabulary, chatbot phrase, bold label" 1 "em dash|\"not just\"|AI vocabulary \"robust\"|AI vocabulary \"seamlessly\"|chatbot phrase|bold-label list line" "$d" g12-unslop-lint.sh
  d="$(new_repo ts feature)"
  printf 'We leverage the existing helper.\n' > "$d/PR.md"
  check g12 "PR.md in the diff with AI vocabulary" 1 "AI vocabulary \"leverage\"" "$d" g12-unslop-lint.sh
fi

# ---------- G13 sources-fetched ----------
if want_gate g13; then
  d="$(new_repo ts research)"
  check g13 "no scout.md outside the scout phase" 2 "" "$d" g13-sources-fetched.sh
  check g13 "scout phase with no scout.md" 1 "does not exist" "$d" g13-sources-fetched.sh --phase scout
  cat > "$d/.forge/t1/scout.md" <<'EOF'
## Candidates
- vitest: https://vitest.dev/guide/ fits the existing setup.
- jest (https://jestjs.io/docs/getting-started), heavier.
EOF
  printf '2026-10-20T00:00:00Z\t200\thttps://vitest.dev/guide/\n2026-10-20T00:00:01Z\t200\thttps://jestjs.io/docs/getting-started\n' > "$d/.forge/t1/fetch.log"
  check g13 "every cited URL has a fetch record" 0 "all 2 cited" "$d" g13-sources-fetched.sh
  printf -- '- bun test: https://bun.sh/docs/cli/test was never fetched.\n' >> "$d/.forge/t1/scout.md"
  check g13 "a cited URL with no fetch record" 1 "https://bun.sh/docs/cli/test" "$d" g13-sources-fetched.sh
  printf '## Candidates\n- vitest, from memory.\n' > "$d/.forge/t1/scout.md"
  check g13 "scout.md cites no URL" 1 "cites no http(s) URL" "$d" g13-sources-fetched.sh

  # fetch-log.sh against a local HTTP server, when python3 is available
  if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    srv="$WORK/srv"; mkdir -p "$srv"; printf 'hello\n' > "$srv/page.html"
    port=$((20000 + $$ % 20000))
    (cd "$srv" && exec python3 -m http.server "$port" --bind 127.0.0.1 > /dev/null 2>&1) &
    spid=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s -o /dev/null "http://127.0.0.1:$port/page.html" && break; sleep 0.3; done
    d="$(new_repo ts research)"
    (cd "$d" && bash "$LIB/fetch-log.sh" --task-dir .forge/t1 "http://127.0.0.1:$port/page.html" > /dev/null 2>&1)
    c1=$?
    (cd "$d" && bash "$LIB/fetch-log.sh" --task-dir .forge/t1 "http://127.0.0.1:$port/missing.html" > /dev/null 2>&1)
    c2=$?
    kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null
    assert_true g13 "fetch-log.sh: 200 response exits 0 and is logged" [ "$c1" -eq 0 -a "$(grep -c "page.html" "$d/.forge/t1/fetch.log" 2>/dev/null)" = 1 ]
    assert_true g13 "fetch-log.sh: 404 response exits 1 and is not logged" [ "$c2" -eq 1 -a "$(grep -c "missing.html" "$d/.forge/t1/fetch.log" 2>/dev/null)" = 0 ]
    printf '## Sources\n- http://127.0.0.1:%s/page.html\n' "$port" > "$d/.forge/t1/scout.md"
    check g13 "URL recorded by fetch-log.sh passes" 0 "" "$d" g13-sources-fetched.sh
  else
    echo "skip  g13    fetch-log.sh cases: python3 or curl not found"
  fi
fi

# ---------- forge-verify.sh ----------
if want_gate verify; then
  d="$(new_repo ts feature 'budget: 50')"
  printf '## Files likely touched\n- src/math.ts\n- src/math.test.ts\n' > "$d/.forge/t1/ground.md"
  ts_feature_done "$d"
  out="$(cd "$d" && bash "$SCRIPTS/forge-verify.sh" --task-dir .forge/t1 --phase build 2>&1)"; code=$?
  ok=1; why=""
  [ "$code" -eq 0 ] || { ok=0; why="exit $code"; }
  grep -q '^result: PASS' "$d/.forge/t1/verify.log" 2>/dev/null || { ok=0; why="$why; verify.log lacks result: PASS"; }
  grep -q '^g07-tests-need-impl PASS' "$d/.forge/t1/verify.log" 2>/dev/null || { ok=0; why="$why; g07 not PASS in verify.log"; }
  [ -f "$d/.forge/t1/verify.log.sha256" ] || { ok=0; why="$why; no verify.log.sha256"; }
  record verify "build phase on a finished feature passes and writes verify.log" 0 "$ok" "$why" "$out"
  check g11 "verify.log written by forge-verify.sh is accepted" 0 "" "$d" g11-referee-readonly.sh

  printf '\n// FIXME: later\nexport const later = 1;\n' >> "$d/src/math.ts"
  out="$(cd "$d" && bash "$SCRIPTS/forge-verify.sh" --task-dir .forge/t1 --phase build 2>&1)"; code=$?
  ok=1; why=""
  [ "$code" -eq 1 ] || { ok=0; why="exit $code, wanted 1"; }
  grep -q '^result: FAIL' "$d/.forge/t1/verify.log" || { ok=0; why="$why; verify.log lacks result: FAIL"; }
  grep -q '^g02-green-after-edit FAIL' "$d/.forge/t1/verify.log" || { ok=0; why="$why; stale green not reported"; }
  grep -q '^g03-diff-hygiene FAIL' "$d/.forge/t1/verify.log" || { ok=0; why="$why; FIXME not reported"; }
  printf '%s' "$out" | grep -q 'GATE g03 FAIL:' || { ok=0; why="$why; failure paragraph not streamed"; }
  record verify "build phase after a late FIXME edit fails (G2 stale, G3 FIXME)" 1 "$ok" "$why" "$out"
fi

# ---------- real templates and forge-task.sh (integration) ----------
REAL_TEMPLATES="$FORGE_ROOT/templates"

# fill_md <file> [skip-heading-regex]: keep front matter and headings, replace each
# section body with real text (headings matching the regex keep their template body).
fill_md() {
  awk -v skip="${2:-^$}" '
    NR == 1 && /^---/ { fm = 1; print; next }
    fm { print; if (/^---/) fm = 0; next }
    /^## / {
      print; h = substr($0, 4)
      keep = (skip != "^$" && tolower(h) ~ skip)
      if (keep) next
      print ""
      if (tolower(h) ~ /files likely touched/) { print "- src/math.ts"; print "- src/math.test.ts" }
      else print "Self-test content for " h "."
      print ""; inskip = 0; next
    }
    keep { print; next }
  ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

if want_gate g00 && [ -f "$REAL_TEMPLATES/ground.md" ]; then
  d="$(new_repo ts feature)"
  cp "$REAL_TEMPLATES/ground.md" "$d/.forge/t1/ground.md"
  check g00 "real template: ground.md copied but not filled" 1 "Overview|How it works" "$d" g00-phase-artifacts.sh --phase ground
  fill_md "$d/.forge/t1/ground.md" "reproduction"
  check g00 "real template: feature leaves '(bugs only)' section as placeholder" 0 "" "$d" g00-phase-artifacts.sh --phase ground
  write_task "$d" bug
  check g00 "real template: bug leaves '(bugs only)' section as placeholder" 1 "Reproduction (bugs only)" "$d" g00-phase-artifacts.sh --phase ground
fi

if want_gate verify && [ -f "$REAL_TEMPLATES/task.md" ] && [ -f "$SCRIPTS/forge-task.sh" ]; then
  d="$(new_repo ts bug)"
  id="$(cd "$d" && FORGE_HOME="$FORGE_ROOT" bash "$SCRIPTS/forge-task.sh" new demo 2>/dev/null | tail -n 1)"
  td=".forge/$id"
  if [ -z "$id" ] || [ ! -f "$d/$td/task.md" ]; then
    record verify "forge-task.sh new creates a task dir from templates" 0 0 "no task dir created" ""
  else
    sed -i.bak 's/^type:.*/type: bug/; s/^budget:.*/budget: 150/' "$d/$td/task.md"
    ts_test_multiply "$d"
    (cd "$d" && bash "$LIB/run-tests.sh" --task-dir "$td" --log red > /dev/null 2>&1)
    ts_impl_multiply "$d"
    (cd "$d" && bash "$LIB/run-tests.sh" --task-dir "$td" --log green > /dev/null 2>&1)

    out="$(cd "$d" && bash "$SCRIPTS/forge-verify.sh" --task-dir "$td" --phase verify 2>&1)"; code=$?
    ok=1; why=""
    [ "$code" -eq 1 ] || { ok=0; why="exit $code, wanted 1"; }
    grep -q '^g00-phase-artifacts FAIL' "$d/$td/verify.log" || { ok=0; why="$why; G0 did not flag unfilled templates"; }
    grep -q '^g10-evidence-integrity FAIL' "$d/$td/verify.log" && { ok=0; why="$why; G10 failed on the report template"; }
    grep -q '^g13-sources-fetched FAIL' "$d/$td/verify.log" && { ok=0; why="$why; G13 failed on an untouched scout.md for a bug"; }
    record verify "forge-task.sh dir, verify phase, templates unfilled: only G0 fails" 1 "$ok" "$why" "$out"

    fill_md "$d/$td/task.md"; fill_md "$d/$td/ground.md"
    out="$(cd "$d" && bash "$SCRIPTS/forge-verify.sh" --task-dir "$td" --phase verify 2>&1)"; code=$?
    ok=1; why=""
    [ "$code" -eq 0 ] || { ok=0; why="exit $code, wanted 0"; }
    grep -q '^result: PASS' "$d/$td/verify.log" || { ok=0; why="$why; verify.log lacks result: PASS"; }
    record verify "forge-task.sh dir, verify phase, finished bug fix passes" 0 "$ok" "$why" "$out"

    fill_md "$d/$td/report.md"
    printf '\nmultiply() returns the product. evidence: %s/green.log\nThe test failed first. evidence: %s/red.log\n' "$td" "$td" >> "$d/$td/report.md"
    out="$(cd "$d" && bash "$SCRIPTS/forge-verify.sh" --task-dir "$td" --phase report 2>&1)"; code=$?
    ok=1; why=""
    [ "$code" -eq 0 ] || { ok=0; why="exit $code, wanted 0"; }
    grep -q '^g10-evidence-integrity PASS' "$d/$td/verify.log" || { ok=0; why="$why; G10 not PASS"; }
    grep -q '^g12-unslop-lint PASS' "$d/$td/verify.log" || { ok=0; why="$why; G12 not PASS"; }
    record verify "forge-task.sh dir, report phase with evidence pointers passes" 0 "$ok" "$why" "$out"
  fi
fi

# ---------- summary ----------
echo
echo "gate   pass-path  fail-path"
for g in g00 g01 g02 g03 g04 g05 g06 g07 g08 g09 g10 g11 g12 g13 verify; do
  want_gate "$g" || continue
  p="no"; f="no"
  case "$PASS_PATHS" in *" $g "*) p="yes" ;; esac
  case "$FAIL_PATHS" in *" $g "*) f="yes" ;; esac
  printf '%-6s %-10s %s\n' "$g" "$p" "$f"
done
echo
echo "selftest: $NPASS passed, $NFAIL failed"
if [ "$NFAIL" -gt 0 ]; then
  printf 'failed cases:\n%s' "$FAILED_CASES"
  exit 1
fi
exit 0
