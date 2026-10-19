#!/usr/bin/env bash
# G3 diff-hygiene: banned patterns in lines the diff adds.
#
# Why: weak models leave markers that look like progress and hide unfinished or
# unsafe work: TODOs, skipped or focused tests, type escapes, swallowed errors,
# debug output, commented-out code, and comments that narrate the edit instead of
# explaining the code. Only added lines are checked, so existing debt does not
# block the task.
#
# Rules (TS/JS = .ts .tsx .mts .cts .js .jsx .mjs .cjs, Rust = .rs):
#   all:   TODO, FIXME; commented-out code (2+ consecutive added comment lines that
#          parse as code); phase-narrating comments ("Step 1", "Now we", "Added the ...",
#          "as requested", "this change ...")
#   TS/JS: it/test/describe .skip( .only( .todo(, xit( xdescribe( xtest(, and any
#          .skip( / .only( in test files; "as any"; @ts-ignore, @ts-nocheck;
#          eslint-disable; empty catch {} and .catch(() => {}); console.log( in non-test files
#   Rust:  .unwrap() and .expect( in non-test code; #[allow( and #![allow(; #[ignore];
#          todo!(; empty error arms "Err(_) => {}" / "Err(_) => ()"
# Test code: a path rule (scripts/lib/common.sh forge_is_test_path) plus, for Rust,
#   every line after the first #[cfg(test)] in the file. Test code is exempt from the
#   console.log and unwrap/expect rules only.
# Other file types are not checked and are listed in a NOTE.
#
# Usage: g03-diff-hygiene.sh --task-dir .forge/<id> [--base <ref>]

GATE_ID=g03
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
forge_parse_args "$@"
forge_git_init

attrs="$(mktemp "${TMPDIR:-/tmp}/forge-g03a.XXXXXX")"
added="$(mktemp "${TMPDIR:-/tmp}/forge-g03b.XXXXXX")"
trap 'rm -f "$attrs" "$added"' EXIT
forge_file_attrs > "$attrs"
forge_added_lines > "$added"

code_files="$(awk -F'\t' '$2 != "other"' "$attrs" | wc -l | tr -d ' ')"
other_files="$(awk -F'\t' '$2 == "other" { print $1 }' "$attrs")"
if [ "$code_files" -eq 0 ]; then
  if [ "$(sed -n '1p' "$attrs")" = "" ] && [ "$("$FORGE_LIB_DIR/detect-lang.sh" .)" != unknown ]; then
    gate_pass "no changed files in the diff under test."
  fi
  gate_skip "no TypeScript/JavaScript or Rust files changed (changed: $(printf '%s' "$other_files" | tr '\n' ' ')); diff-hygiene rules exist only for those languages."
fi
[ -n "$other_files" ] && gate_note "not checked (no rules for this file type): $(printf '%s' "$other_files" | tr '\n' ' ')"

findings="$(awk -F'\t' '
  function lc(s) { return tolower(s) }
  function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
  function report(rule) {
    shown = trim(content); if (length(shown) > 120) shown = substr(shown, 1, 117) "..."
    print file ":" ln ": " rule ": " shown
  }
  # comment_text: the text of a // or /* or * comment on this line, or "" if none.
  function comment_text(s,   t, p) {
    t = trim(s)
    if (t ~ /^\/\//) { sub(/^\/\/+!?[[:space:]]*/, "", t); return t }
    if (t ~ /^\/\*/) { sub(/^\/\*+[[:space:]]*/, "", t); sub(/\*\/.*$/, "", t); return t }
    if (t ~ /^\*[^\/]/ || t == "*") { sub(/^\*[[:space:]]*/, "", t); return t }
    p = index(s, " // ")
    if (p > 0) { t = substr(s, p + 4); return trim(t) }
    return ""
  }
  function is_line_comment(s,   t) { t = trim(s); return (t ~ /^\/\//) }
  function looks_like_code(t) {
    if (t ~ /;[[:space:]]*$/) return 1
    if (t ~ /[{][[:space:]]*$/) return 1
    if (t ~ /^(\}|\]|\))/) return 1
    if (t ~ /^(const|let|var)[[:space:]]+[A-Za-z_$]/) return 1
    if (t ~ /^(import|export|use|fn|pub|impl|struct|enum|mod)[[:space:]]/ && t ~ /(from|::|;|\{|\(|=)/) return 1
    if (t ~ /^[A-Za-z_$][A-Za-z0-9_$.]*\(.*\)[;,]?$/) return 1
    if (t ~ /^[A-Za-z_$][A-Za-z0-9_$.]*[[:space:]]*(=|\+=|-=)[^=]/) return 1
    return 0
  }
  function narrates(t,   l) {
    l = lc(t)
    if (l ~ /^step[[:space:]]*[0-9]+/) return 1
    if (l ~ /^(now|here)[[:space:]]+(we|i)([[:space:]]|$)/) return 1
    if (l ~ /^(added|changed|fixed|updated|removed|modified|refactored|replaced|moved)[[:space:]]+(this|the|a|an|to|for|in|new|bug|issue|check|support|logic|code|handling|call|import|function|method|test|tests)([[:space:]]|$|:)/) return 1
    if (l ~ /^(new|updated|fixed|changed|added)[[:space:]]*:/) return 1
    if (l ~ /^(previously|originally)([[:space:]]|,|$)/) return 1
    if (l ~ /(before|after) this change|this (change|fix|pr|commit) (adds|fixes|makes|changes|updates|removes)|as requested|per the (task|request|ticket)|(i|we) (added|changed|fixed|updated|removed|modified)[[:space:]]/) return 1
    return 0
  }
  FNR == NR { lang[$1] = $2; istest[$1] = $3; cfgline[$1] = $4; next }
  {
    file = $1; ln = $2 + 0; content = $3
    for (i = 4; i <= NF; i++) content = content "\t" $i
    L = lang[file]
    if (L == "" || L == "other") next
    test = (istest[file] == 1) || (L == "rust" && cfgline[file] > 0 && ln > cfgline[file])

    if (content ~ /(^|[^A-Za-z0-9_])(TODO|FIXME)([^A-Za-z0-9_]|$)/) report("TODO/FIXME marker")

    ct = comment_text(content)
    if (ct != "" && narrates(ct)) report("comment narrates the change instead of explaining the code")

    # commented-out code: consecutive added // lines that look like code
    if (is_line_comment(content) && looks_like_code(comment_text(content))) {
      if (prevfile == file && prevln == ln - 1 && prevcode) { if (!blockreported) { report("commented-out code block"); blockreported = 1 } }
      else blockreported = 0
      prevcode = 1
    } else { prevcode = 0; blockreported = 0 }
    prevfile = file; prevln = ln

    if (L == "ts") {
      if (content ~ /(^|[^A-Za-z0-9_$.])(it|test|describe|suite|context|bench)\.(skip|only|todo)[[:space:]]*\(/) report("skipped or focused test")
      else if (content ~ /(^|[^A-Za-z0-9_$.])x(it|describe|test)[[:space:]]*\(/) report("skipped test (x-prefixed)")
      else if (test && content ~ /\.(skip|only)[[:space:]]*\(/) report("skipped or focused test")
      if (content ~ /(^|[^A-Za-z0-9_$])as[[:space:]]+any([^A-Za-z0-9_$]|$)/) report("\"as any\" type escape")
      if (content ~ /@ts-(ignore|nocheck)/) report("@ts-ignore/@ts-nocheck suppression")
      if (content ~ /eslint-disable/) report("eslint-disable suppression")
      if (content ~ /catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}/) report("empty catch block swallows the error")
      else if (content ~ /\.catch\([[:space:]]*(\([^)]*\)|[A-Za-z_$][A-Za-z0-9_$]*)?[[:space:]]*=>[[:space:]]*(\{[[:space:]]*\}|undefined|null)[[:space:]]*\)/) report("empty .catch handler swallows the error")
      if (!test && content ~ /console\.log[[:space:]]*\(/) report("console.log in non-test code")
    }
    if (L == "rust") {
      if (!test && content ~ /\.unwrap\(\)/) report("unwrap() in non-test Rust")
      if (!test && content ~ /\.expect\(/) report("expect() in non-test Rust")
      if (content ~ /#!?\[allow\(/) report("new #[allow(...)] lint suppression")
      if (content ~ /#\[ignore/) report("#[ignore] skips a test")
      if (content ~ /(^|[^A-Za-z0-9_])todo!/) report("todo!() placeholder")
      if (content ~ /Err\(_\)[[:space:]]*=>[[:space:]]*(\{[[:space:]]*\}|\(\))/) report("empty error arm swallows the error")
    }
  }
' "$attrs" "$added")"

if [ -n "$findings" ]; then
  count="$(printf '%s\n' "$findings" | wc -l | tr -d ' ')"
  gate_fail "found $count banned pattern(s) in lines this diff adds, listed below as file:line: rule: line. Fix what each one stands in for rather than hiding it: finish or delete TODO work, unskip or unfocus tests, replace 'as any' and @ts-ignore with a real type, handle or propagate errors instead of empty catch blocks, use '?' or a handled error instead of unwrap()/expect(), remove debug logging and commented-out code, and rewrite narrating comments to explain why the code is this way (or delete them). Do not add a suppression comment to get past this gate." "$findings"
fi
gate_pass "no banned patterns in $(wc -l < "$added" | tr -d ' ') added line(s) across $code_files code file(s)."
