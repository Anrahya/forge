#!/usr/bin/env bash
# Shared helpers for forge's Claude Code hooks. Sourced, not executed.
# Bash 3.2 compatible (macOS /bin/bash): no associative arrays, no mapfile.
# The policy rules mirror adapters/dsh/src/policy.ts and src/shell.ts; the
# parity test adapters/dsh/tests/claude-code-policy.test.ts runs both.

FORGE_HOOKS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# forge layer root (skills/, AGENTS.md, scripts/): FORGE_DIR, else the plugin
# root, else four levels above this file (<forge>/adapters/claude-code/scripts/hooks).
forge_dir() {
  if [ -n "${FORGE_DIR:-}" ]; then printf '%s\n' "$FORGE_DIR"; return; fi
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/AGENTS.md" ]; then printf '%s\n' "$CLAUDE_PLUGIN_ROOT"; return; fi
  (cd "$FORGE_HOOKS_DIR/../../../.." && pwd)
}

have_jq() { command -v jq >/dev/null 2>&1; }

# json_get <json> <jq filter>: raw string, empty when null.
json_get() { printf '%s' "$1" | jq -r "$2 // empty"; }

# forge_state <cwd>: sets FORGE_ROOT TASK_ID TASK_DIR PHASE STATE_PROBLEM.
# Returns 1 when forge is inactive (no .forge/current up the tree, or empty).
forge_state() {
  local dir="$1"
  FORGE_ROOT="" TASK_ID="" TASK_DIR="" PHASE="" STATE_PROBLEM=""
  while :; do
    if [ -f "$dir/.forge/current" ]; then FORGE_ROOT="$dir"; break; fi
    [ "$dir" = "/" ] || [ -z "$dir" ] && return 1
    dir=$(dirname "$dir")
  done
  TASK_ID=$(tr -d '[:space:]' < "$FORGE_ROOT/.forge/current")
  [ -z "$TASK_ID" ] && return 1
  if ! printf '%s' "$TASK_ID" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' || [[ "$TASK_ID" == *..* ]]; then
    STATE_PROBLEM=".forge/current holds \"$TASK_ID\", which is not a valid task id"
    TASK_ID="invalid-task-id"; TASK_DIR=".forge"
    return 0
  fi
  TASK_DIR=".forge/$TASK_ID"
  local state="$FORGE_ROOT/$TASK_DIR/state.json"
  if [ ! -f "$state" ]; then STATE_PROBLEM="$TASK_DIR/state.json is missing"; return 0; fi
  local phase
  if ! phase=$(jq -r 'if type == "object" then (.phase // "") else "" end' < "$state" 2>/dev/null); then
    STATE_PROBLEM="$TASK_DIR/state.json is not valid JSON"; return 0
  fi
  case "$phase" in
    ground|scout|shape|build|verify|review|report) PHASE="$phase" ;;
    *) STATE_PROBLEM="$TASK_DIR/state.json phase \"$phase\" is not one of ground, scout, shape, build, verify, review, report" ;;
  esac
  return 0
}

# phase_mode <phase>: read-only | guard-referee. Empty phase fails closed.
phase_mode() {
  case "$1" in
    shape|build|report) echo guard-referee ;;
    *) echo read-only ;;
  esac
}

# norm_path <base> <path>: absolute path with . and .. removed.
norm_path() {
  local p="$2"
  case "$p" in /*) ;; *) p="$1/$p" ;; esac
  local out="" part IFS=/
  for part in $p; do
    case "$part" in
      ''|.) ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$part" ;;
    esac
  done
  [ -z "$out" ] && out="/"
  printf '%s\n' "$out"
}

# rel_path <root> <abs>: project-relative path, or "../<abs>" when outside.
rel_path() {
  if [ "$2" = "$1" ]; then echo ""; return; fi
  case "$2" in
    "$1"/*) printf '%s\n' "${2#"$1"/}" ;;
    *) printf '../%s\n' "$2" ;;
  esac
}

is_verify_log() {
  case "$1" in .forge/*) [ "$(basename "$1")" = "verify.log" ] ;; *) return 1 ;; esac
}

REFEREE_BASENAME_RE='^(vitest\.(config|workspace)\.[cm]?[jt]s|jest\.config\.[cm]?[jt]s(on)?|eslint\.config\.[cm]?[jt]s|\.eslintrc(\.(js|cjs|mjs|json|ya?ml))?|\.eslintignore|tsconfig(\..+)?\.json|jsconfig\.json|biome\.jsonc?|\.prettierrc(\..+)?|prettier\.config\.[cm]?[jt]s|\.?clippy\.toml|\.?rustfmt\.toml)$'

# is_referee <rel>: same list as isRefereePath in policy.ts.
is_referee() {
  local rel="$1"
  case "$rel" in ''|../*) return 1 ;; esac
  case "$rel" in
    scripts/gates|scripts/gates/*|scripts/forge-verify.sh|.github/workflows|.github/workflows/*) return 0 ;;
  esac
  is_verify_log "$rel" && return 0
  local base
  base=$(basename "$rel")
  [[ "$base" =~ $REFEREE_BASENAME_RE ]]
}

# scratch_dirs: OS temp dirs where writes are always allowed.
scratch_dirs() {
  local d
  for d in /tmp /private/tmp "${TMPDIR:-/tmp}"; do
    d="${d%/}"
    [ -n "$d" ] || continue
    printf '%s\n' "$d"
    [ -d "$d" ] && (cd "$d" && pwd -P)
  done
}

in_scratch() {
  local abs="$1" d
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    case "$abs" in "$d"|"$d"/*) return 0 ;; esac
  done <<EOF
$(scratch_dirs)
EOF
  return 1
}

DEV_DEPS_RE='^[[:space:]]*\[[[:space:]]*(target\..+\.)?dev-dependencies(\.[^]]+)?[[:space:]]*\][[:space:]]*(#.*)?$'

# devdeps_text: stdin Cargo.toml, stdout the dev-dependency entries.
devdeps_text() {
  DEV_RE="$DEV_DEPS_RE" awk '
    BEGIN { re = ENVIRON["DEV_RE"] }
    /^[[:space:]]*\[\[?[^]]+\]\]?[[:space:]]*(#.*)?$/ { indev = ($0 ~ re); next }
    indev { line = $0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", line); if (line != "" && substr(line, 1, 1) != "#") print line }
  '
}

mentions_dev_deps() { printf '%s\n' "$1" | grep -Eq "$DEV_DEPS_RE"; }

# edit_in_dev_deps <file> <old text>: true when the first match of old text
# starts inside a dev-dependencies section.
edit_in_dev_deps() {
  [ -f "$1" ] || return 1
  [ -n "$2" ] || return 1
  OLD_TEXT="$2" DEV_RE="$DEV_DEPS_RE" awk '
    BEGIN { re = ENVIRON["DEV_RE"] }
    { text = text $0 "\n" }
    END {
      idx = index(text, ENVIRON["OLD_TEXT"])
      if (idx == 0) exit 1
      line = 1
      for (i = 1; i < idx; i++) if (substr(text, i, 1) == "\n") line++
      n = split(text, lines, "\n")
      indev = 0
      for (i = 1; i <= line && i <= n; i++) {
        if (lines[i] ~ /^[[:space:]]*\[\[?[^]]+\]\]?[[:space:]]*(#.*)?$/) indev = (lines[i] ~ re)
      }
      exit indev ? 0 : 1
    }
  ' "$1"
}

# tokenize: CMD env var in, one token per line out:
#   W<TAB><0|1 unresolved><TAB><word>   S   R<TAB><op>
# Quotes honored, heredoc bodies dropped, comments dropped. Port of tokenize() in shell.ts.
tokenize() {
  awk '
  function flush() {
    if (!inword) return
    if (expect_doc) { ndocs++; docs[ndocs] = word; strip[ndocs] = expect_strip; expect_doc = 0 }
    else { gsub(/\t|\n/, " ", word); printf "W\t%d\t%s\n", unres, word }
    word = ""; inword = 0; unres = 0
  }
  BEGIN {
    s = ENVIRON["CMD"]; n = length(s); i = 1; word = ""; inword = 0; unres = 0; ndocs = 0; expect_doc = 0
    while (i <= n) {
      c = substr(s, i, 1)
      if (c == "\\" && i < n) {
        if (substr(s, i + 1, 1) == "\n") { i += 2; continue }
        word = word substr(s, i + 1, 1); inword = 1; i += 2; continue
      }
      if (c == "\047") {
        j = i + 1; while (j <= n && substr(s, j, 1) != "\047") j++
        word = word substr(s, i + 1, j - i - 1); inword = 1; i = j + 1; continue
      }
      if (c == "\"") {
        j = i + 1
        while (j <= n && substr(s, j, 1) != "\"") {
          d = substr(s, j, 1)
          if (d == "\\" && j < n) { word = word substr(s, j + 1, 1); j += 2; continue }
          if (d == "$" || d == "`") unres = 1
          word = word d; j++
        }
        inword = 1; i = j + 1; continue
      }
      if (c == "$" && substr(s, i + 1, 1) == "(") {
        depth = 0; j = i + 1
        for (; j <= n; j++) { d = substr(s, j, 1); if (d == "(") depth++; else if (d == ")") { depth--; if (depth == 0) break } }
        word = word substr(s, i, j - i + 1); inword = 1; unres = 1; i = j + 1; continue
      }
      if (c == "`") {
        j = i + 1; while (j <= n && substr(s, j, 1) != "`") j++
        word = word substr(s, i, j - i + 1); inword = 1; unres = 1; i = j + 1; continue
      }
      if (c == "\n") {
        flush(); print "S"; i++
        for (k = 1; k <= ndocs; k++) {
          while (i <= n) {
            e = index(substr(s, i), "\n"); if (e == 0) { line = substr(s, i); i = n + 1 } else { line = substr(s, i, e - 1); i += e }
            if (strip[k]) sub(/^\t+/, "", line)
            if (line == docs[k]) break
          }
        }
        ndocs = 0
        continue
      }
      if (c == " " || c == "\t") { flush(); i++; continue }
      if (c == "#" && !inword) { e = index(substr(s, i), "\n"); i = (e == 0) ? n + 1 : i + e - 1; continue }
      three = substr(s, i, 3)
      if (substr(three, 1, 2) == "<<") {
        flush()
        if (substr(three, 3, 1) == "<") { i += 3; continue }
        expect_strip = (substr(three, 3, 1) == "-"); i += expect_strip ? 3 : 2; expect_doc = 1; continue
      }
      if (substr(three, 1, 2) == "&>") {
        flush(); op = (three == "&>>") ? "&>>" : "&>"; printf "R\t%s\n", op; i += length(op); continue
      }
      if (c == ">" || (c ~ /[0-9]/ && !inword && substr(s, i + 1, 1) == ">")) {
        flush(); j = i; if (c != ">") j++
        op = ">"; nx = substr(s, j + 1, 1)
        if (nx == ">") op = ">>"; else if (nx == "|") op = ">|"
        j += length(op)
        if (substr(s, j, 1) == "&") { j++; while (j <= n && substr(s, j, 1) ~ /[0-9-]/) j++; i = j; continue }
        printf "R\t%s\n", op; i = j; continue
      }
      if (c == "<") { flush(); print "R\t<"; i++; continue }
      if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")") {
        flush(); two = substr(s, i, 2)
        if (two == "&&" || two == "||" || two == "|&" || two == ";;") i += 2; else i++
        print "S"; continue
      }
      if (c == "$" || c == "*" || c == "?" || c == "[" || c == "{" || (c == "~" && !inword)) unres = 1
      word = word c; inword = 1; i++
    }
    flush()
  }'
}
