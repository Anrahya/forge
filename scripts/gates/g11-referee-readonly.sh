#!/usr/bin/env bash
# G11 referee-readonly: the diff does not touch the files that judge the work.
#
# Why: a model that cannot make a check pass will weaken the check. The harness
# hook blocks these writes where it can; this gate is the after-the-fact check
# for harnesses without one. It fails when the diff under test (committed,
# staged, unstaged or untracked, including deletions) touches:
#   - gate scripts: scripts/gates/** at any depth
#   - test runner config: vitest.config.*, vitest.workspace.*, jest.config.*,
#     and vite.config.* when it holds a "test" block
#   - lint and format config: eslint.config.*, .eslintrc*, .eslintignore,
#     .prettierrc*, prettier.config.*, clippy.toml, .clippy.toml, rustfmt.toml, .rustfmt.toml
#   - typecheck config: tsconfig*.json
#   - Cargo.toml, only when a [dev-dependencies] section (including
#     [target.*.dev-dependencies]) differs from the base
#   - CI config: .github/workflows/**, .gitlab-ci.yml
#   - .forge/**/verify.log, when its content no longer matches the hash that
#     scripts/forge-verify.sh recorded beside it (verify.log.sha256). forge-verify
#     rewrites the log itself, so a plain "file changed" test would always fire.
#
# Usage: g11-referee-readonly.sh --task-dir .forge/<id> [--base <ref>]

GATE_ID=g11
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
forge_parse_args "$@"
forge_git_init

devdeps() { # stdin: Cargo.toml; stdout: dev-dependency sections, normalized
  awk '
    /^[[:space:]]*\[/ { insec = ($0 ~ /^[[:space:]]*\[(target\.[^]]*\.)?dev-dependencies(\.[^]]*)?\][[:space:]]*$/) }
    insec { line = $0; sub(/[[:space:]]+$/, "", line); if (line != "") print line }
  '
}

hits=""
add_hit() { hits="${hits}$1
"; }

while IFS= read -r f; do
  [ -n "$f" ] || continue
  b="${f##*/}"
  case "/$f" in
    */scripts/gates/*) add_hit "$f (gate script)"; continue ;;
    */.github/workflows/*) add_hit "$f (CI workflow)"; continue ;;
  esac
  case "$b" in
    vitest.config.*|vitest.workspace.*|jest.config.*) add_hit "$f (test runner config)"; continue ;;
    vite.config.*)
      if { [ -f "$f" ] && grep -q 'test[[:space:]]*:' "$f"; } || git show "$MERGE_BASE:./$f" 2>/dev/null | grep -q 'test[[:space:]]*:'; then
        add_hit "$f (vite config with a test block)"
      fi
      continue ;;
    eslint.config.*|.eslintrc|.eslintrc.*|.eslintignore|.prettierrc|.prettierrc.*|prettier.config.*) add_hit "$f (lint/format config)"; continue ;;
    clippy.toml|.clippy.toml|rustfmt.toml|.rustfmt.toml) add_hit "$f (lint/format config)"; continue ;;
    tsconfig.json|tsconfig.*.json|tsconfig-*.json) add_hit "$f (typecheck config)"; continue ;;
    .gitlab-ci.yml) add_hit "$f (CI config)"; continue ;;
    Cargo.toml)
      old="$(git show "$MERGE_BASE:./$f" 2>/dev/null | devdeps)"
      new=""; [ -f "$f" ] && new="$(devdeps < "$f")"
      [ "$old" != "$new" ] && add_hit "$f ([dev-dependencies] changed)"
      continue ;;
  esac
done < <(forge_changed_files_raw)

# verify.log integrity, for every task dir present
for v in .forge/*/verify.log; do
  [ -f "$v" ] || continue
  sha="$v.sha256"
  if [ ! -f "$sha" ]; then
    add_hit "$v (no hash recorded by forge-verify.sh, so it was not written by the runner)"
  elif [ "$(forge_hash "$v")" != "$(head -n 1 "$sha" | tr -d '[:space:]')" ]; then
    add_hit "$v (edited after forge-verify.sh wrote it)"
  fi
done

if [ -n "$hits" ]; then
  gate_fail "the diff touches referee-owned files, listed below. Gates, test runner config, lint and typecheck config, dev-dependencies and CI config judge the work, so changing them invalidates the verdict. Revert each one (git checkout <base> -- <path>, or delete it if new; for verify.log, rerun scripts/forge-verify.sh). If you believe a gate or config is wrong, stop and report it (stop condition S5) instead of editing it." "$(printf '%s' "$hits")"
fi
gate_pass "no referee-owned file is touched."
