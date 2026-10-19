# common.sh: shared helpers for forge gates. Sourced by every gate, never executed.
#
# Why: every gate needs the same argument parsing, the same definition of "the
# diff under test", the same test-file rule, and the same output contract. One
# copy keeps the gates consistent with each other and with scripts/README.md.
#
# Contract (see scripts/README.md):
#   exit 0 pass, 1 fail, 2 skip.
#   fail prints a paragraph starting "GATE gNN FAIL:", skip prints "GATE gNN SKIP:".
# Portability: bash 3.2 (macOS /bin/bash) and GNU/Linux. No associative arrays,
# no mapfile, no GNU-only flags without a fallback.

FORGE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_SCRIPTS_DIR="$(dirname "$FORGE_LIB_DIR")"
FORGE_ROOT="$(dirname "$FORGE_SCRIPTS_DIR")"
FORGE_GATES_DIR="$FORGE_SCRIPTS_DIR/gates"

GATE_ID="${GATE_ID:-g??}"
TASK_DIR=""
BASE_ARG=""
PHASE=""
BASE=""
MERGE_BASE=""

# ---------- output contract ----------

# gate_fail <paragraph> [details]: details are extra lines printed indented under the paragraph.
gate_fail() {
  printf 'GATE %s FAIL: %s\n' "$GATE_ID" "$1"
  if [ -n "${2:-}" ]; then printf '%s\n' "$2" | sed 's/^/  /'; fi
  exit 1
}
gate_skip() { printf 'GATE %s SKIP: %s\n' "$GATE_ID" "$1"; exit 2; }
gate_pass() { printf 'GATE %s PASS: %s\n' "$GATE_ID" "$1"; exit 0; }
gate_note() { printf 'NOTE %s: %s\n' "$GATE_ID" "$1"; }

# ---------- arguments ----------

# forge_parse_args "$@": sets TASK_DIR, BASE_ARG, PHASE. Unknown flags fail loudly.
forge_parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --task-dir) TASK_DIR="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
      --task-dir=*) TASK_DIR="${1#*=}"; shift ;;
      --base) BASE_ARG="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
      --base=*) BASE_ARG="${1#*=}"; shift ;;
      --phase) PHASE="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
      --phase=*) PHASE="${1#*=}"; shift ;;
      -h|--help)
        echo "usage: $(basename "$0") --task-dir .forge/<id> [--base <git ref>] [--phase <phase>]"
        exit 0 ;;
      *) gate_fail "unknown argument '$1'. Usage: $(basename "$0") --task-dir .forge/<id> [--base <git ref>] [--phase <phase>]." ;;
    esac
  done
  [ -n "$TASK_DIR" ] || gate_fail "missing --task-dir. Run the gate from the project root as: $(basename "$0") --task-dir .forge/<id>."
  TASK_DIR="${TASK_DIR%/}"
  [ -d "$TASK_DIR" ] || gate_fail "task directory '$TASK_DIR' does not exist. Run gates from the project root and pass the task directory that INTAKE created, for example --task-dir .forge/<id>."
  if [ -z "$PHASE" ] && [ -f "$TASK_DIR/state.json" ]; then
    PHASE="$(sed -n 's/.*"phase"[[:space:]]*:[[:space:]]*"\([A-Za-z_-]*\)".*/\1/p' "$TASK_DIR/state.json" | head -n 1)"
  fi
}

# ---------- task metadata ----------

forge_meta() { "$FORGE_LIB_DIR/task-meta.sh" "$TASK_DIR/task.md" "$1" 2>/dev/null; }

forge_require_task() {
  [ -f "$TASK_DIR/task.md" ] || gate_fail "$TASK_DIR/task.md is missing. INTAKE must write task.md with a YAML front matter block (type, budget, surface, non_goals) before this gate can run."
}

# forge_task_type: prints the validated task type or fails.
forge_task_type() {
  local t
  t="$(forge_meta type)"
  case "$t" in
    bug|feature|refactor|perf|investigate|research|chore) printf '%s\n' "$t" ;;
    *) return 1 ;;
  esac
}

forge_require_type() {
  forge_require_task
  TASK_TYPE="$(forge_task_type)" || gate_fail "task.md front matter has no valid 'type' (got '$(forge_meta type)'). Set type to one of bug, feature, refactor, perf, investigate, research, chore."
}

# ---------- git and the diff under test ----------

# forge_git_init: resolves BASE (--base, else task.md "base" when it resolves, else main,
# master, the first commit) and MERGE_BASE. The diff under test is
# MERGE_BASE..working tree (committed + staged + unstaged) plus untracked files.
forge_git_init() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || gate_fail "the current directory is not inside a git work tree. Run gates from the target project's root."
  git rev-parse --verify -q HEAD >/dev/null 2>&1 || gate_fail "the repository has no commits yet, so there is no base to diff against. Commit the starting state first."
  local task_base=""
  if [ -z "$BASE_ARG" ] && [ -n "$TASK_DIR" ] && [ -f "$TASK_DIR/task.md" ]; then
    task_base="$(forge_meta base)"
    if [ -n "$task_base" ] && ! git rev-parse --verify -q "${task_base}^{commit}" >/dev/null 2>&1; then
      task_base=""
    fi
  fi
  if [ -n "$BASE_ARG" ]; then
    git rev-parse --verify -q "${BASE_ARG}^{commit}" >/dev/null 2>&1 || gate_fail "base ref '$BASE_ARG' does not resolve to a commit. Pass an existing branch, tag, or sha with --base."
    BASE="$BASE_ARG"
  elif [ -n "$task_base" ]; then
    BASE="$task_base"
  elif git rev-parse --verify -q "main^{commit}" >/dev/null 2>&1; then
    BASE=main
  elif git rev-parse --verify -q "master^{commit}" >/dev/null 2>&1; then
    BASE=master
  else
    BASE="$(git rev-list --max-parents=0 HEAD | tail -n 1)"
  fi
  MERGE_BASE="$(git merge-base "$BASE" HEAD 2>/dev/null)" || gate_fail "no merge base between '$BASE' and HEAD. Pass the branch this work started from with --base."
}

# Paths excluded from "the diff under test": forge state and dependency/build dirs.
forge_is_excluded_path() {
  case "$1" in
    .forge|.forge/*|*/.forge/*|node_modules/*|*/node_modules/*|target/*) return 0 ;;
  esac
  return 1
}

forge_untracked_files() {
  git -c core.quotePath=false ls-files --others --exclude-standard
}

# forge_changed_files_raw: every changed path (added, modified, deleted, untracked), .forge included.
forge_changed_files_raw() {
  {
    git -c core.quotePath=false diff --name-only --no-renames --relative "$MERGE_BASE" --
    forge_untracked_files
  } | sed '/^$/d' | sort -u
}

# forge_changed_files: like raw, minus forge state and dependency dirs. Includes deleted paths.
forge_changed_files() {
  local f
  forge_changed_files_raw | while IFS= read -r f; do
    forge_is_excluded_path "$f" || printf '%s\n' "$f"
  done
}

# forge_changed_existing: changed files that exist on disk now.
forge_changed_existing() {
  local f
  forge_changed_files | while IFS= read -r f; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

forge_is_untracked() {
  [ -z "$(git ls-files -- "$1" 2>/dev/null)" ] && [ -e "$1" ]
}

# forge_diff: unified diff with zero context for every changed file (tracked and untracked).
forge_diff() {
  local f tracked_list=""
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/forge-diff.XXXXXX")"
  forge_changed_files > "$tmp"
  while IFS= read -r f; do
    if forge_is_untracked "$f"; then
      git -c core.quotePath=false diff --no-color --no-index -U0 -- /dev/null "$f" 2>/dev/null
    else
      git -c core.quotePath=false diff --no-color --no-renames --relative -U0 "$MERGE_BASE" -- "$f"
    fi
  done < "$tmp"
  rm -f "$tmp"
}

# forge_added_lines: prints "path<TAB>line<TAB>content" for every added line in the diff under test.
forge_added_lines() {
  forge_diff | awk '
    /^diff --git / { inhdr = 1; file = ""; next }
    inhdr && /^\+\+\+ / {
      f = substr($0, 5)
      sub(/\t.*$/, "", f)
      if (f ~ /^".*"$/) f = substr(f, 2, length(f) - 2)
      if (f == "/dev/null") file = ""
      else { sub(/^b\//, "", f); file = f }
      next
    }
    inhdr && /^(---|index |new file|deleted file|old mode|new mode|similarity|rename|Binary)/ { next }
    /^@@ / {
      inhdr = 0
      if (match($0, /\+[0-9]+/)) ln = substr($0, RSTART + 1, RLENGTH - 1) + 0
      next
    }
    inhdr { next }
    /^\+/ { if (file != "") print file "\t" ln "\t" substr($0, 2); ln++; next }
    /^ / { ln++; next }
  '
}

# ---------- file classification ----------

# forge_is_test_path <path>: a path segment or file name marks it as test code:
# __tests__/, test/, tests/, spec/, *.test.*, *.spec.*, *_test.*, test_*, tests.rs and similar.
# Plain substring matching would misclassify names like "latest.ts" or "attestation.rs".
forge_is_test_path() {
  local p="/$1" b
  case "$p" in
    */__tests__/*|*/test/*|*/tests/*|*/spec/*|*/specs/*|*/__mocks__/*) return 0 ;;
  esac
  b="$(printf '%s' "${1##*/}" | tr 'A-Z' 'a-z')"
  case "$b" in
    *.test.*|*.spec.*|*_test.*|*_spec.*|*-test.*|*-spec.*|test_*|spec_*|test.*|tests.*|spec.*) return 0 ;;
  esac
  return 1
}

# forge_file_lang <path>: ts, rust, or other, by extension.
forge_file_lang() {
  case "$1" in
    *.ts|*.tsx|*.mts|*.cts|*.js|*.jsx|*.mjs|*.cjs) echo ts ;;
    *.rs) echo rust ;;
    *) echo other ;;
  esac
}

# forge_cfg_test_line <file>: line number of the first #[cfg(test)] in a Rust file, or 0.
# Lines after it are treated as test code (the usual "mod tests" at the end of a file).
forge_cfg_test_line() {
  local n
  n="$(grep -n '^[[:space:]]*#\[cfg(test)\]' "$1" 2>/dev/null | head -n 1 | cut -d: -f1)"
  echo "${n:-0}"
}

# forge_file_attrs: prints "path<TAB>lang<TAB>is_test(0/1)<TAB>cfg_test_line" for each existing changed file.
forge_file_attrs() {
  local f lang t c
  forge_changed_existing | while IFS= read -r f; do
    lang="$(forge_file_lang "$f")"
    if forge_is_test_path "$f"; then t=1; else t=0; fi
    c=0
    [ "$lang" = rust ] && c="$(forge_cfg_test_line "$f")"
    printf '%s\t%s\t%s\t%s\n' "$f" "$lang" "$t" "$c"
  done
}

# ---------- misc ----------

forge_hash() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else cksum "$1" | awk '{print $1 "-" $2}'
  fi
}

# forge_newer_than <ref> <files...>: prints each file whose mtime is strictly newer than ref.
# Uses find -newer, which compares full-resolution mtimes on BSD and GNU alike.
forge_newer_than() {
  local ref="$1" f; shift
  for f in "$@"; do
    [ -e "$f" ] || continue
    if [ -n "$(find "$f" -prune -newer "$ref" 2>/dev/null)" ]; then printf '%s\n' "$f"; fi
  done
}

# forge_mtime <file>: epoch seconds, GNU stat first, BSD stat as fallback.
forge_mtime() {
  local m
  m="$(stat -c %Y "$1" 2>/dev/null)"
  case "$m" in ''|*[!0-9]*) m="$(stat -f %m "$1" 2>/dev/null)" ;; esac
  echo "${m:-0}"
}

# forge_strip_ansi: remove terminal color codes (BSD sed has no \x escapes, so build ESC with printf).
forge_strip_ansi() {
  local esc
  esc="$(printf '\033')"
  LC_ALL=C sed "s/${esc}\[[0-9;]*[A-Za-z]//g"
}

# forge_tail_file <file> <n>: last n lines, for embedding command output in a fail message.
forge_tail_file() { tail -n "${2:-30}" "$1" 2>/dev/null; }

# Load command resolution (forge_cmds, forge_test_cmd) from run-tests.sh without running its main.
# shellcheck source=run-tests.sh
. "$FORGE_LIB_DIR/run-tests.sh"
