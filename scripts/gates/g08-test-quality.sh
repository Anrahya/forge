#!/usr/bin/env bash
# G8 test-quality: static heuristics on tests the diff adds.
#
# Why: a weak model can satisfy "write a test" with a test that cannot fail.
# G7 catches that dynamically; this gate catches the common shapes statically
# and names them, which is cheaper to act on.
#
# Fails when a NEW test (its it(/test( line or #[test] line is an added line):
#   - has zero assertions (TS: expect( expect. assert( assert. expectTypeOf( .should;
#     Rust: assert!/assert_eq!/assert_ne!/assert_matches!/prop_assert*/panic!,
#     #[should_panic], or "?" in a test that returns Result);
#   - asserts only through snapshots (toMatchSnapshot, toMatchInlineSnapshot,
#     insta assert_*snapshot!), which records whatever the code does today.
# Fails on any added test line that:
#   - asserts a literal: expect(true), expect(false), assert(true), assert!(true);
#   - computes the expected value by calling the code under test, for example
#     expect(f(x)).toBe(f(x)) or assert_eq!(f(x), f(x));
#   - mocks the module under test: vi.mock / jest.mock whose target has the same
#     module name as the test file's subject (foo.test.ts mocking './foo').
# Test code: test paths (common.sh forge_is_test_path) and, in Rust, lines after
# the first #[cfg(test)]. Brace and paren matching is approximate (string
# literals and // comments are stripped first).
#
# Usage: g08-test-quality.sh --task-dir .forge/<id> [--base <ref>]

GATE_ID=g08
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
forge_parse_args "$@"
forge_git_init

attrs="$(mktemp "${TMPDIR:-/tmp}/forge-g08a.XXXXXX")"
added="$(mktemp "${TMPDIR:-/tmp}/forge-g08b.XXXXXX")"
tadded="$(mktemp "${TMPDIR:-/tmp}/forge-g08c.XXXXXX")"
trap 'rm -f "$attrs" "$added" "$tadded"' EXIT
forge_file_attrs > "$attrs"
forge_added_lines > "$added"

# keep only added lines that are test code: "file<TAB>lang<TAB>line<TAB>content"
awk -F'\t' '
  FNR == NR { lang[$1] = $2; istest[$1] = $3; cfg[$1] = $4; next }
  {
    L = lang[$1]
    if (L != "ts" && L != "rust") next
    t = (istest[$1] == 1) || (L == "rust" && cfg[$1] > 0 && $2 + 0 > cfg[$1] + 0)
    if (!t) next
    c = $3; for (i = 4; i <= NF; i++) c = c "\t" $i
    print $1 "\t" L "\t" $2 "\t" c
  }
' "$attrs" "$added" > "$tadded"

if [ ! -s "$tadded" ]; then
  gate_skip "the diff adds no TypeScript/JavaScript or Rust test code, so there are no new tests to inspect (heuristics exist only for those languages)."
fi

# analyze_file <file> <lang> <comma-separated added line numbers>
# prints "file:line<TAB>name<TAB>asserts<TAB>snapshots" for every new test.
analyze_file() {
  awk -v addl="$3" -v lang="$2" -v file="$1" -v q="'" '
    BEGIN {
      n = split(addl, a, ","); for (i = 1; i <= n; i++) added[a[i]] = 1
      sq_re = q "[^" q "]*" q; ch_re = q "." q
      str_re = "[\"" q "`][^\"" q "`]*[\"" q "`]"
    }
    function strip(s) {
      gsub(/\\./, "", s)
      gsub(/"[^"]*"/, "\"\"", s)
      if (lang == "ts") { gsub(sq_re, "", s); gsub(/`[^`]*`/, "", s) }
      else gsub(ch_re, "", s)
      sub(/\/\/.*$/, "", s)
      return s
    }
    function count(s, re,   c) { c = gsub(re, "", s); return c }
    function finish(   asserts, snaps, b) {
      b = body
      if (lang == "ts") {
        snaps = count(b, "toMatch(Inline|File)?Snapshot|toThrowErrorMatching(Inline)?Snapshot")
        asserts = count(b, "expect[.(]|assert[.(]|expectTypeOf\\(|\\.should[.(]")
      } else {
        snaps = count(b, "assert_[a-z_]*snapshot!")
        asserts = count(b, "assert(_eq|_ne|_matches)?!\\(|prop_assert[a-z_]*!|panic!\\(|#\\[should_panic")
        if (sig ~ /->[[:space:]]*[A-Za-z_:]*Result/ && b ~ /\)\?/) asserts++
      }
      print file ":" start "\t" name "\t" asserts "\t" snaps
      intest = 0; body = ""; sig = ""
    }
    {
      raw = $0
      if (!intest) {
        if (lang == "ts" && added[NR] && raw ~ /^[[:space:]]*(it|test)(\.[A-Za-z]+)*[[:space:]]*\(/) {
          intest = 1; start = NR; depth = 0; opened = 0; body = ""
          name = raw; if (match(raw, str_re)) name = substr(raw, RSTART + 1, RLENGTH - 2); else name = "(unnamed)"
        } else if (lang == "rust" && added[NR] && raw ~ /^[[:space:]]*#\[([a-z_]+::)?test\]/) {
          intest = 1; start = NR; depth = 0; opened = 0; body = ""; name = "(unnamed)"
        } else next
      }
      body = body "\n" raw
      s = strip(raw)
      if (lang == "rust" && name == "(unnamed)" && match(raw, /fn[[:space:]]+[A-Za-z0-9_]+/)) { name = substr(raw, RSTART + 3, RLENGTH - 3); sub(/^[[:space:]]+/, "", name) }
      if (lang == "rust" && !opened) sig = sig " " raw
      if (lang == "ts") {
        depth += count(s, "\\(") - count(s, "\\)")
        if (depth <= 0) finish()
      } else {
        o = count(s, "\\{"); c = count(s, "\\}")
        if (o > 0) opened = 1
        depth += o - c
        if (opened && depth <= 0) finish()
      }
    }
    END { if (intest) finish() }
  ' "$1"
}

findings=""
add_finding() { findings="${findings}$1
"; }

# per-test checks
while IFS= read -r f; do
  lang="$(awk -F'\t' -v f="$f" '$1 == f { print $2; exit }' "$tadded")"
  lines="$(awk -F'\t' -v f="$f" '$1 == f { printf "%s%s", sep, $3; sep = "," }' "$tadded")"
  while IFS="$(printf '\t')" read -r loc name asserts snaps; do
    [ -n "$loc" ] || continue
    if [ "$lang" = ts ]; then nonsnap=$((asserts - snaps)); else nonsnap=$asserts; fi
    if [ "$asserts" -eq 0 ] && [ "$snaps" -eq 0 ]; then
      add_finding "$loc: test '$name' has no assertions"
    elif [ "$nonsnap" -le 0 ] && [ "$snaps" -gt 0 ]; then
      add_finding "$loc: test '$name' asserts only through snapshots"
    fi
  done < <(analyze_file "$f" "$lang" "$lines")
done < <(cut -f1 "$tadded" | sort -u)

# per-line checks on added test code
line_findings="$(awk -F'\t' -v q="'" '
  function stem(p,   b) { b = p; sub(/^.*\//, "", b); sub(/\.(test|spec)\..*$/, "", b); sub(/[._-](test|spec)$/, "", b); sub(/\.[^.]*$/, "", b); return b }
  function modname(p,   b) { b = p; sub(/\/index$/, "", b); sub(/^.*\//, "", b); sub(/\.[A-Za-z]+$/, "", b); return b }
  {
    file = $1; L = $2; ln = $3; c = $4; for (i = 5; i <= NF; i++) c = c "\t" $i
    loc = file ":" ln
    if (c ~ /expect\([[:space:]]*(true|false)[[:space:]]*\)/ || c ~ /(^|[^A-Za-z0-9_.])assert!?\([[:space:]]*true[[:space:]]*[,)]/ || c ~ /assert_eq!\([[:space:]]*true[[:space:]]*,[[:space:]]*true[[:space:]]*\)/)
      print loc ": asserts a literal, so it can never fail"
    if (L == "ts" && match(c, /expect\([[:space:]]*[A-Za-z_$][A-Za-z0-9_$.]*\(/)) {
      fn = substr(c, RSTART + 7, RLENGTH - 8); sub(/^[[:space:]]+/, "", fn)
      if (index(c, ".toBe(" fn "(") || index(c, ".toEqual(" fn "(") || index(c, ".toStrictEqual(" fn "("))
        print loc ": expected value is computed by calling " fn "() itself"
    }
    if (L == "rust" && match(c, /assert_(eq|ne)!\([[:space:]]*[A-Za-z_][A-Za-z0-9_:]*\(/)) {
      fn = substr(c, RSTART, RLENGTH - 1); sub(/^assert_(eq|ne)!\([[:space:]]*/, "", fn)
      rest = substr(c, RSTART + RLENGTH)
      if (index(rest, ", " fn "(") || index(rest, "," fn "("))
        print loc ": expected value is computed by calling " fn "() itself"
    }
    if (L == "ts" && match(c, "(vi|jest)\\.mock\\([[:space:]]*[\"" q "][^\"" q "]+[\"" q "]")) {
      m = substr(c, RSTART, RLENGTH); sub(/^(vi|jest)\.mock\([[:space:]]*/, "", m); m = substr(m, 2, length(m) - 2)
      if (m ~ /^\./ && modname(m) == stem(file))
        print loc ": mocks " m ", the module this test file is testing"
    }
  }
' "$tadded")"
[ -n "$line_findings" ] && findings="${findings}${line_findings}
"

if [ -n "$findings" ]; then
  findings="$(printf '%s' "$findings" | sed '/^$/d')"
  gate_fail "new tests have shapes that cannot catch a regression, listed below. Each new test must call the real code under test and assert an observable result against an independently known expected value: no literal assertions, no expected value computed by the same function, no mock of the module the test is about, and no snapshot as the only check of logic. Fix or delete each listed test, then rerun the tests." "$findings"
fi
gate_pass "new test code in $(cut -f1 "$tadded" | sort -u | wc -l | tr -d ' ') file(s) passes the heuristics."
