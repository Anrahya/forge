#!/usr/bin/env bash
# task-meta.sh: read one key from the YAML front matter of a forge task.md.
#
# Why: gates need type, budget, surface, non_goals and command overrides, and
# must not depend on yq or python. This reads the small YAML subset task.md uses.
#
# Usage: task-meta.sh <task.md> <key>
# Output: a scalar prints on one line (quotes and trailing "# comment" removed).
#         A list (block "- item" lines or inline [a, b]) prints one item per line.
# Exit:   0 key found (value may be empty), 1 key absent, 2 usage error or no front matter.
# Supported: "key: value", "key: 'v'", "key: \"v\"", "key: [a, b]", "key:" followed by "  - item".
# Not supported: block scalars (| and >), nested maps.

if [ $# -ne 2 ]; then
  echo "usage: task-meta.sh <task.md> <key>" >&2
  exit 2
fi
file="$1"
key="$2"
if [ ! -f "$file" ]; then
  echo "task-meta.sh: no such file: $file" >&2
  exit 2
fi

awk -v key="$key" '
  function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
  function unq(s,   q, rest, p) {
    s = trim(s)
    q = substr(s, 1, 1)
    if (q == "\"" || q == "'\''") {
      rest = substr(s, 2); p = index(rest, q)
      if (p > 0) return substr(rest, 1, p - 1)
    }
    sub(/[[:space:]]+#.*$/, "", s)
    return trim(s)
  }
  { sub(/\r$/, "") }
  NR == 1 { if ($0 !~ /^---[[:space:]]*$/) { nofm = 1; exit } ; next }
  /^(---|\.\.\.)[[:space:]]*$/ { exit }
  inlist {
    if ($0 ~ /^[[:space:]]*-([[:space:]]|$)/) { v = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", v); v = unq(v); if (v != "") print v; next }
    if ($0 ~ /^[[:space:]]*(#.*)?$/) next
    exit
  }
  index($0, key ":") == 1 {
    found = 1
    v = trim(substr($0, length(key) + 2))
    if (v == "" || v ~ /^#/) { inlist = 1; next }
    if (v ~ /^\[.*\][[:space:]]*(#.*)?$/) {
      sub(/\][[:space:]]*(#.*)?$/, "", v); v = substr(v, 2)
      n = split(v, parts, ",")
      for (i = 1; i <= n; i++) { p = unq(parts[i]); if (p != "") print p }
      exit
    }
    print unq(v)
    exit
  }
  END { if (nofm) exit 2; if (!found) exit 1 }
' "$file"
