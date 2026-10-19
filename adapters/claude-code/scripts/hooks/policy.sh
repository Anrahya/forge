#!/usr/bin/env bash
# forge PreToolUse hook for Claude Code: per-phase tool policy and the
# referee-file rule (gate G11). Shell port of adapters/dsh/src/policy.ts and
# src/shell.ts; adapters/dsh/tests/claude-code-policy.test.ts checks parity.
#
# Input: the PreToolUse JSON on stdin (tool_name, tool_input, cwd).
# Allow: exit 0 with no output. Deny: exit 2 with the reason on stderr,
# which Claude Code shows to the model and which blocks the tool call.
# Inactive (no .forge/current up the tree): exit 0.

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"

INPUT=$(cat)

deny() { printf '%s\n' "$1" >&2; exit 2; }

if ! have_jq; then
  dir=$PWD
  while :; do
    if [ -s "$dir/.forge/current" ]; then
      deny "forge: the policy hook needs jq to read tool calls, and forge is active in $dir. Install jq (brew install jq, apt install jq) or clear .forge/current."
    fi
    [ "$dir" = "/" ] && exit 0
    dir=$(dirname "$dir")
  done
fi

CWD=$(json_get "$INPUT" '.cwd')
[ -z "$CWD" ] && CWD=$PWD
forge_state "$CWD" || exit 0
MODE=$(phase_mode "$PHASE")
TOOL=$(json_get "$INPUT" '.tool_name')

RULES_HINT='If a gate or referee file looks wrong, stop and report it (stop condition S5); never edit it.'

readonly_reason() {
  if [ -z "$PHASE" ]; then
    printf 'forge: %s. Until state.json names a phase (ground, scout, shape, build, verify, review, report), only writes under .forge/ are allowed. Blocked: %s.' "${STATE_PROBLEM:-.forge/$TASK_ID/state.json has no valid phase}" "$1"
    return
  fi
  local next
  case "$PHASE" in
    review) next='Record findings in review.md; blocking findings send the task back to BUILD.' ;;
    verify) next='VERIFY runs gates only; a failure returns to BUILD with the gate message.' ;;
    *) next="Put what you learned in .forge/$TASK_ID/$PHASE.md; code changes wait for BUILD." ;;
  esac
  printf 'forge: phase "%s" is read-only. Writes are allowed only under .forge/ and scratch directories. Blocked: %s. %s' "$PHASE" "$1" "$next"
}

referee_reason() {
  printf 'forge: %s %s. Agents never write referee files in any phase. %s' "$1" "${2:-targets a referee file (gate scripts, forge-verify.sh, test runner config, lint config, CI workflows, verify.log)}" "$RULES_HINT"
}

shown_path() {
  local rel
  rel=$(rel_path "$FORGE_ROOT" "$1")
  case "$rel" in ../*) printf '%s\n' "$1" ;; *) printf '%s\n' "$rel" ;; esac
}

# cargo_check <abs> <what> <kind>: kind is write | edit | multiedit | shell | none.
cargo_check() {
  local abs="$1" what="$2" kind="$3"
  case "$kind" in
    write)
      local cur="" new
      [ -f "$abs" ] && cur=$(devdeps_text < "$abs")
      new=$(json_get "$INPUT" '.tool_input.content' | devdeps_text)
      [ "$cur" != "$new" ] && deny "$(referee_reason "$what" 'changes the [dev-dependencies] section')"
      ;;
    edit)
      local old new
      old=$(json_get "$INPUT" '.tool_input.old_string')
      new=$(json_get "$INPUT" '.tool_input.new_string')
      { mentions_dev_deps "$old" || mentions_dev_deps "$new"; } && deny "$(referee_reason "$what" 'adds or removes a [dev-dependencies] header')"
      edit_in_dev_deps "$abs" "$old" && deny "$(referee_reason "$what" 'edits the [dev-dependencies] section')"
      ;;
    multiedit)
      local count k old new
      count=$(printf '%s' "$INPUT" | jq -r '.tool_input.edits | length')
      for ((k = 0; k < count; k++)); do
        old=$(json_get "$INPUT" ".tool_input.edits[$k].old_string")
        new=$(json_get "$INPUT" ".tool_input.edits[$k].new_string")
        { mentions_dev_deps "$old" || mentions_dev_deps "$new"; } && deny "$(referee_reason "$what" 'adds or removes a [dev-dependencies] header')"
        edit_in_dev_deps "$abs" "$old" && deny "$(referee_reason "$what" 'edits the [dev-dependencies] section')"
      done
      ;;
    shell)
      deny "$(referee_reason "$what" 'is a shell write to Cargo.toml, so the [dev-dependencies] section cannot be checked (use the edit tool)')"
      ;;
  esac
  return 0
}

# judge_path <abs> <via> <cargo kind>: deny (exits) or return.
judge_path() {
  local abs="$1" via="$2" kind="$3" rel what
  rel=$(rel_path "$FORGE_ROOT" "$abs")
  what="$via $(shown_path "$abs")"
  case "$rel" in
    ../*)
      in_scratch "$abs" && return 0
      [ "$MODE" = read-only ] && deny "$(readonly_reason "$what")"
      return 0
      ;;
  esac
  is_verify_log "$rel" && deny "$(referee_reason "$what" 'targets verify.log, which only scripts/forge-verify.sh writes')"
  case "$rel" in .forge|.forge/*) return 0 ;; esac
  [ "$MODE" = read-only ] && deny "$(readonly_reason "$what")"
  is_referee "$rel" && deny "$(referee_reason "$what")"
  [ "$(basename "$rel")" = "Cargo.toml" ] && cargo_check "$abs" "$what" "$kind"
  return 0
}

# ---------------------------------------------------------------------------
# Shell write analysis (port of src/shell.ts). Results land in OUT_* arrays.

OUT_KIND=() OUT_A=() OUT_VIA=() OUT_DEV=()
BASE=$CWD
DEPTH=0
INLINE_WRITE_API="writeFile|appendFile|createWriteStream|unlink|rmSync|rmdir|mkdir|rename|copyFile|truncate|open\\([^)]*['\"][wax][+]?['\"]|write_text|write_bytes|os\\.remove|shutil\\.|File\\.write|IO\\.write"

record_path() { OUT_KIND+=(path); OUT_A+=("$(norm_path "$BASE" "$1")"); OUT_VIA+=("$2"); OUT_DEV+=(0); }
record_opaque() { OUT_KIND+=(opaque); OUT_VIA+=("$1"); OUT_A+=("$2"); OUT_DEV+=("${3:-0}"); }

is_option() { [[ "$1" == -* ]] && [ "$1" != "-" ]; }

# record_word <index>: a path write, or opaque when the word is unresolved.
record_word() {
  if [ "${u[$1]}" = 1 ]; then record_opaque "$2" ""; else record_path "${w[$1]}" "$2"; fi
}

# operands <start> [valued options...]: OPS gets indices of non-option words.
operands() {
  local start=$1 k v opt skip=0 end=0
  shift
  OPS=()
  for ((k = start; k < n; k++)); do
    v=${w[$k]}
    if [ $skip = 1 ]; then skip=0; continue; fi
    if [ $end = 0 ] && [ "$v" = "--" ]; then end=1; continue; fi
    if [ $end = 0 ] && is_option "$v"; then
      for opt in "$@"; do [ "$v" = "$opt" ] && skip=1; done
      continue
    fi
    OPS+=("$k")
  done
}

# after_options <start> [valued...]: index of the first non-option word.
after_options() {
  local k=$1 opt valued
  shift
  while [ "$k" -lt "$n" ] && is_option "${w[$k]}"; do
    valued=0
    for opt in "$@"; do [ "${w[$k]}" = "$opt" ] && valued=1; done
    k=$((k + 1 + valued))
  done
  AFTER=$k
}

has_short() {
  local k v
  for ((k = $1; k < n; k++)); do
    v=${w[$k]}
    [[ "$v" == --* ]] && continue
    if [[ "$v" =~ ^-([A-Za-z]+) ]] && [[ "${BASH_REMATCH[1]}" == *"$2"* ]]; then return 0; fi
  done
  return 1
}

has_long() {
  local s=$1 k v name
  shift
  for ((k = s; k < n; k++)); do
    v=${w[$k]}
    for name in "$@"; do
      if [ "$v" = "$name" ] || [[ "$v" == "$name="* ]]; then return 0; fi
    done
  done
  return 1
}

has_word() {
  local s=$1 k name
  shift
  for ((k = s; k < n; k++)); do
    for name in "$@"; do [ "${w[$k]}" = "$name" ] && return 0; done
  done
  return 1
}

# mentions <index...>: newline-joined absolute forms of resolved non-option words.
mentions() {
  local k v out=""
  for k in "$@"; do
    [ "${u[$k]}" = 1 ] && continue
    v=${w[$k]}
    is_option "$v" && continue
    [ -z "$v" ] && continue
    [[ "$v" =~ ^[A-Za-z_][A-Za-z0-9_-]*= ]] && v=${v#*=}
    out="$out$(norm_path "$BASE" "$v")"$'\n'
  done
  printf '%s' "$out"
}

range() { local k; for ((k = $1; k < $2; k++)); do printf '%s ' "$k"; done; }

# analyze_words <word> ...: analyze one synthetic segment (no redirects).
analyze_words() {
  SW=() SU=() RO=() RT=() RU=()
  local x
  for x in "$@"; do
    if [ "$x" = $'\x01' ]; then SW+=("<input>"); SU+=(1); else SW+=("$x"); SU+=(0); fi
  done
  analyze_segment
}

# writes_with_unknown <word> ...: true if the command writes when its unknown
# operand (\x01) is filled in. Probe only: results and cd are rolled back.
writes_with_unknown() {
  local before=${#OUT_KIND[@]} saved_base=$BASE grew=1
  analyze_words "$@"
  [ ${#OUT_KIND[@]} -gt "$before" ] && grew=0
  if [ "$before" -eq 0 ]; then
    OUT_KIND=() OUT_A=() OUT_VIA=() OUT_DEV=()
  else
    OUT_KIND=("${OUT_KIND[@]:0:$before}") OUT_A=("${OUT_A[@]:0:$before}")
    OUT_VIA=("${OUT_VIA[@]:0:$before}") OUT_DEV=("${OUT_DEV[@]:0:$before}")
  fi
  BASE=$saved_base
  return $grew
}

inline_interp() {
  local cmd=$1 k idx=-1
  for ((k = i + 1; k < n; k++)); do
    case "${w[$k]}" in -e|--eval|-p|--print|-c|-E) idx=$k; break ;; esac
    if [ "$cmd" = deno ] && [ "${w[$k]}" = eval ]; then idx=$k; break; fi
  done
  [ $idx -lt 0 ] && return
  local code=${w[$((idx + 1))]}
  printf '%s' "$code" | grep -Eq "$INLINE_WRITE_API" || return
  local m lit
  m=$(mentions $(range $((idx + 2)) "$n"))
  while IFS= read -r lit; do
    [ -z "$lit" ] && continue
    lit=${lit#?}; lit=${lit%?}
    m="$m$(norm_path "$BASE" "$lit")"$'\n'
  done <<EOF
$(printf '%s' "$code" | grep -oE "['\"]([^'\" ]+/[^'\" ]*|[^'\" ]+\\.[A-Za-z]{1,5})['\"]")
EOF
  record_opaque "$cmd inline code" "$m"
}

analyze_segment() {
  local -a w u ro rt ru
  w=("${SW[@]}") u=("${SU[@]}") ro=("${RO[@]}") rt=("${RT[@]}") ru=("${RU[@]}")
  local n=${#w[@]} k

  for ((k = 0; k < ${#ro[@]}; k++)); do
    [ "${ro[$k]}" = "<" ] && continue
    if [ "${ru[$k]}" = 2 ]; then record_opaque "${ro[$k]}" ""; continue; fi
    case "${rt[$k]}" in /dev/null|/dev/stdout|/dev/stderr|/dev/tty) continue ;; esac
    if [ "${ru[$k]}" = 1 ]; then record_opaque "redirect ${ro[$k]}" ""; else record_path "${rt[$k]}" "redirect ${ro[$k]}"; fi
  done

  local i=0 v name
  while [ $i -lt $n ]; do
    v=${w[$i]}
    name=${v##*/}
    if [[ "$v" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then i=$((i + 1)); continue; fi
    case "$name" in
      env)
        i=$((i + 1))
        while [ $i -lt $n ] && { is_option "${w[$i]}" || [[ "${w[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; }; do i=$((i + 1)); done
        continue ;;
      timeout)
        after_options $((i + 1)) -s -k --signal --kill-after
        i=$((AFTER + 1))
        continue ;;
      sudo|command|builtin|nice|nohup|time|exec|doas|stdbuf)
        i=$((i + 1))
        while [ $i -lt $n ] && is_option "${w[$i]}"; do i=$((i + 1)); done
        continue ;;
      xargs)
        operands $((i + 1)) -I -n -P -L -d -E -s
        [ ${#OPS[@]} -eq 0 ] && return
        local inner=() o
        for o in "${OPS[@]}"; do inner+=("${w[$o]}"); done
        if writes_with_unknown "${inner[@]}" $'\x01'; then
          record_opaque "xargs ${inner[0]##*/}" "$(mentions "${OPS[@]}")"
        fi
        return ;;
    esac
    break
  done
  [ $i -ge $n ] && return

  local cmd=${w[$i]##*/} s=$((i + 1)) last o
  case "$cmd" in
    cd|pushd)
      operands $s
      if [ ${#OPS[@]} -gt 0 ]; then
        o=${OPS[0]}
        [ "${u[$o]}" = 1 ] || [ "${w[$o]}" = "-" ] || BASE=$(norm_path "$BASE" "${w[$o]}")
      fi ;;
    rm|rmdir|unlink|touch|mkdir|shred)
      operands $s -m
      for o in "${OPS[@]}"; do record_word "$o" "$cmd"; done ;;
    truncate)
      operands $s -s -r
      for o in "${OPS[@]}"; do record_word "$o" "$cmd"; done ;;
    chmod|chown|chgrp)
      operands $s --reference
      for o in "${OPS[@]:1}"; do record_word "$o" "$cmd"; done ;;
    mv)
      operands $s -t -S
      for o in "${OPS[@]}"; do record_word "$o" "$cmd"; done ;;
    cp|ln|install|rsync)
      for ((k = s; k < n; k++)); do
        if [ "${w[$k]}" = "-t" ] || [ "${w[$k]}" = "--target-directory" ]; then
          [ $((k + 1)) -lt $n ] && { record_word $((k + 1)) "$cmd"; return; }
        fi
      done
      operands $s -m -o -g -S -e --exclude --include
      if [ ${#OPS[@]} -gt 0 ]; then last=${OPS[$((${#OPS[@]} - 1))]}; record_word "$last" "$cmd"; fi ;;
    tee)
      operands $s
      for o in "${OPS[@]}"; do record_word "$o" "$cmd"; done ;;
    dd)
      for ((k = s; k < n; k++)); do
        case "${w[$k]}" in of=*)
          if [ "${u[$k]}" = 1 ]; then record_opaque dd ""; else record_path "${w[$k]#of=}" dd; fi ;;
        esac
      done ;;
    sed|perl|ruby)
      if has_short $s i || has_long $s --in-place; then
        local given=1
        has_word $s -e -f || has_long $s --expression --file || given=0
        operands $s -e -f --expression --file
        local files=("${OPS[@]}")
        [ $given = 0 ] && files=("${OPS[@]:1}")
        for o in "${files[@]}"; do record_word "$o" "$cmd -i"; done
      elif [ "$cmd" != sed ]; then
        inline_interp "$cmd"
      fi ;;
    node|python|python3|deno)
      inline_interp "$cmd" ;;
    bash|sh|zsh|dash)
      for ((k = s; k < n; k++)); do
        if [ "${w[$k]}" = "-c" ] || [[ "${w[$k]}" =~ ^-[a-z]*c$ ]]; then
          if [ $((k + 1)) -lt $n ] && [ $DEPTH -lt 4 ]; then
            DEPTH=$((DEPTH + 1)); analyze_command "${w[$((k + 1))]}"; DEPTH=$((DEPTH - 1))
          fi
          break
        fi
      done ;;
    eval)
      if [ $DEPTH -lt 4 ]; then
        DEPTH=$((DEPTH + 1)); analyze_command "${w[*]:$s}"; DEPTH=$((DEPTH - 1))
      fi ;;
    find)
      if has_word $s -delete -fprint -fprintf -fls; then record_opaque "find -delete" "$(mentions $(range $s "$n"))"; return; fi
      for ((k = s; k < n; k++)); do
        case "${w[$k]}" in -exec|-execdir|-ok|-okdir) ;; *) continue ;; esac
        local inner=() j
        for ((j = k + 1; j < n; j++)); do
          [ "${w[$j]}" = ";" ] || [ "${w[$j]}" = "+" ] && break
          if [ "${w[$j]}" = "{}" ]; then inner+=($'\x01'); else inner+=("${w[$j]}"); fi
        done
        if [ ${#inner[@]} -gt 0 ] && writes_with_unknown "${inner[@]}"; then
          record_opaque "find ${w[$k]} ${inner[0]##*/}" "$(mentions $(range $s "$n"))"
        fi
      done ;;
    curl)
      for ((k = s; k < n; k++)); do
        if [ "${w[$k]}" = "-o" ] || [ "${w[$k]}" = "--output" ]; then
          [ $((k + 1)) -lt $n ] && record_word $((k + 1)) "curl -o"
          break
        fi
      done
      has_word $s -O --remote-name --remote-name-all && record_opaque "curl -O" "" ;;
    wget)
      local found=0
      for ((k = s; k < n; k++)); do
        if [ "${w[$k]}" = "-O" ] || [ "${w[$k]}" = "--output-document" ]; then
          found=1
          [ $((k + 1)) -lt $n ] && [ "${w[$((k + 1))]}" != "-" ] && record_word $((k + 1)) "wget -O"
          break
        fi
      done
      [ $found = 0 ] && record_opaque wget "$(mentions $(range $s "$n"))" ;;
    tar)
      if has_short $s x || [[ "${w[$s]:-}" =~ ^[a-z]*x ]] || has_long $s --extract --get; then
        record_opaque "tar -x" "$(mentions $(range $s "$n"))"
      fi ;;
    unzip|gunzip|bunzip2|unxz)
      has_short $s l || has_short $s t || record_opaque "$cmd" "$(mentions $(range $s "$n"))" ;;
    patch)
      record_opaque patch "$(mentions $(range $s "$n"))" ;;
    git)
      operands $s -C -c --git-dir --work-tree --namespace
      [ ${#OPS[@]} -eq 0 ] && return
      local sub=${w[${OPS[0]}]}
      case "$sub" in
        add|am|apply|checkout|cherry-pick|clean|commit|init|merge|mv|pull|push|rebase|reset|restore|revert|rm|stash|switch|tag|worktree|submodule)
          record_opaque "git $sub" "$(mentions "${OPS[@]:1}")" ;;
        branch)
          [ ${#OPS[@]} -gt 1 ] && record_opaque "git branch" "$(mentions "${OPS[@]:1}")" ;;
      esac ;;
    npx|bunx|pnpx)
      after_options $s -p --package -c
      [ "$AFTER" -lt "$n" ] && analyze_words "${w[@]:$AFTER}" ;;
    npm|pnpm|yarn|bun)
      operands $s --prefix -C --filter --dir -w --cwd
      if [ ${#OPS[@]} -eq 0 ]; then [ "$cmd" = bun ] && inline_interp "$cmd"; return; fi
      local sub=${w[${OPS[0]}]}
      case "$sub" in
        exec|dlx|x)
          after_options $((${OPS[0]} + 1)) -p --package -c
          [ "$AFTER" -lt "$n" ] && analyze_words "${w[@]:$AFTER}"
          return ;;
        install|i|ci|add|remove|rm|uninstall|un|update|up|upgrade|link|unlink|dedupe|prune|init|version|publish|patch|import)
          record_opaque "$cmd $sub" "$(mentions $(range $s "$n"))"; return ;;
      esac
      [ "$cmd" = bun ] && inline_interp "$cmd" ;;
    pip|pip3|uv|poetry|pipx)
      operands $s
      [ ${#OPS[@]} -eq 0 ] && return
      case "${w[${OPS[0]}]}" in install|uninstall|add|remove|sync|lock|update|init)
        record_opaque "$cmd ${w[${OPS[0]}]}" "$(mentions $(range $s "$n"))" ;;
      esac ;;
    cargo)
      operands $s --manifest-path -p --package -Z --config
      [ ${#OPS[@]} -eq 0 ] && return
      local sub=${w[${OPS[0]}]} dev=0 all
      all=$(mentions $(range $s "$n"))
      { has_long $s --dev || has_word $s -D; } && dev=1
      case "$sub" in
        add|remove|rm)
          if [ $dev = 1 ]; then record_opaque "cargo $sub --dev" "$all" 1; else record_opaque "cargo $sub" "$all"; fi ;;
        update|fix|install|new|init|generate-lockfile|vendor)
          record_opaque "cargo $sub" "$all" ;;
        fmt)
          has_long $s --check || record_opaque "cargo fmt" "$all" ;;
        clippy)
          has_long $s --fix && record_opaque "cargo clippy --fix" "$all" ;;
      esac ;;
    rustfmt|black)
      has_long $s --check || record_opaque "$cmd" "$(mentions $(range $s "$n"))" ;;
    gofmt|goimports)
      has_short $s w && record_opaque "$cmd -w" "$(mentions $(range $s "$n"))" ;;
    prettier)
      { has_long $s --write || has_word $s -w; } && record_opaque "prettier --write" "$(mentions $(range $s "$n"))" ;;
    eslint)
      has_long $s --fix && record_opaque "eslint --fix" "$(mentions $(range $s "$n"))" ;;
    biome)
      has_long $s --write --apply --apply-unsafe --fix && record_opaque "biome --write" "$(mentions $(range $s "$n"))" ;;
    ruff)
      if has_long $s --fix || { [ "${w[$s]:-}" = format ] && ! has_long $s --check; }; then
        record_opaque "ruff --fix" "$(mentions $(range $s "$n"))"
      fi ;;
  esac
  return 0
}

# analyze_command <text>: tokenize and analyze every segment.
analyze_command() {
  local tokens kind a b pending=""
  tokens=$(CMD="$1" tokenize)
  SW=() SU=() RO=() RT=() RU=()
  while IFS=$'\t' read -r kind a b; do
    case "$kind" in
      S)
        [ -n "$pending" ] && { RO+=("$pending"); RT+=(""); RU+=(2); pending=""; }
        analyze_segment
        SW=() SU=() RO=() RT=() RU=() ;;
      R)
        [ -n "$pending" ] && { RO+=("$pending"); RT+=(""); RU+=(2); }
        pending=$a ;;
      W)
        if [ -n "$pending" ]; then RO+=("$pending"); RT+=("$b"); RU+=("$a"); pending=""
        else SW+=("$b"); SU+=("$a"); fi ;;
    esac
  done <<EOF
$tokens
EOF
  [ -n "$pending" ] && { RO+=("$pending"); RT+=(""); RU+=(2); }
  analyze_segment
}

judge_shell() {
  local k via what m rel
  for ((k = 0; k < ${#OUT_KIND[@]}; k++)); do
    if [ "${OUT_KIND[$k]}" = path ]; then
      judge_path "${OUT_A[$k]}" "${OUT_VIA[$k]}" shell
      continue
    fi
    via=${OUT_VIA[$k]}
    what="shell command \"$via\""
    while IFS= read -r m; do
      [ -z "$m" ] && continue
      rel=$(rel_path "$FORGE_ROOT" "$m")
      case "$rel" in ../*) continue ;; esac
      is_referee "$rel" && deny "$(referee_reason "$what on $rel")"
    done <<EOF
${OUT_A[$k]}
EOF
    [ "${OUT_DEV[$k]}" = 1 ] && deny "$(referee_reason "$what" 'changes Cargo.toml [dev-dependencies]')"
    [ "$MODE" = read-only ] && deny "$(readonly_reason "$what (it may write files outside .forge/)")"
  done
  return 0
}

# ---------------------------------------------------------------------------

case "$TOOL" in
  Write)
    p=$(json_get "$INPUT" '.tool_input.file_path')
    [ -n "$p" ] && judge_path "$(norm_path "$CWD" "$p")" Write write ;;
  Edit)
    p=$(json_get "$INPUT" '.tool_input.file_path')
    [ -n "$p" ] && judge_path "$(norm_path "$CWD" "$p")" Edit edit ;;
  MultiEdit)
    p=$(json_get "$INPUT" '.tool_input.file_path')
    [ -n "$p" ] && judge_path "$(norm_path "$CWD" "$p")" MultiEdit multiedit ;;
  NotebookEdit)
    p=$(json_get "$INPUT" '.tool_input.notebook_path')
    [ -n "$p" ] && judge_path "$(norm_path "$CWD" "$p")" NotebookEdit none ;;
  Bash)
    c=$(json_get "$INPUT" '.tool_input.command')
    if [ -n "$c" ]; then
      analyze_command "$c"
      judge_shell
    fi ;;
esac
exit 0
