#!/usr/bin/env bash
# detect-lang.sh: print the project languages forge supports, by manifest file.
#
# Why: gates choose banned patterns and default commands per language, and an
# unsupported language must skip loudly instead of passing silently.
#
# Usage: detect-lang.sh [project-dir]   (default: current directory)
# Prints: "ts" if package.json exists, "rust" if Cargo.toml exists,
#         "ts rust" if both, "unknown" otherwise.

dir="${1:-.}"
langs=""
[ -f "$dir/package.json" ] && langs="ts"
if [ -f "$dir/Cargo.toml" ]; then
  if [ -n "$langs" ]; then langs="$langs rust"; else langs="rust"; fi
fi
echo "${langs:-unknown}"
