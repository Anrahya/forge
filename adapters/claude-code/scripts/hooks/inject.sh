#!/usr/bin/env bash
# forge context hook for Claude Code (SessionStart and UserPromptSubmit).
# Prints the current phase skill body and the AGENTS.md principle index; for
# these two events Claude Code adds a hook's stdout to the model context.
# Claude Code has no per-step hook, so this runs once per prompt and after
# startup, resume, clear, and compaction (DSH re-enters it every few steps).

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"

INPUT=$(cat)
have_jq || exit 0
CWD=$(json_get "$INPUT" '.cwd')
[ -z "$CWD" ] && CWD=$PWD
forge_state "$CWD" || exit 0
MAX_CHARS=${FORGE_MAX_INJECT_CHARS:-24000}
FORGE=$(forge_dir)

if [ -z "$PHASE" ]; then
  printf '<forge-context task="%s">\nforge is active but %s. Fix .forge/%s/state.json (phase is one of ground, scout, shape, build, verify, review, report) before other work; only writes under .forge/ are allowed until then.\n</forge-context>\n' \
    "$TASK_ID" "${STATE_PROBLEM:-the task has no valid phase}" "$TASK_ID"
  exit 0
fi

SKILL="" LABEL=""
for pair in "$FORGE_ROOT/.agents/skills/forge-$PHASE/SKILL.md|.agents/skills/forge-$PHASE/SKILL.md" "$FORGE/skills/forge-$PHASE/SKILL.md|skills/forge-$PHASE/SKILL.md"; do
  file=${pair%%|*}
  if [ -f "$file" ]; then
    # Drop the YAML frontmatter.
    SKILL=$(awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { fm = 0; next } !fm' "$file" | sed "s|\$FORGE_HOME|$FORGE|g")
    LABEL=${pair#*|}
    break
  fi
done

INDEX=""
[ -f "$FORGE/AGENTS.md" ] && INDEX=$(awk '/^## Principle index[[:space:]]*$/ { on = 1; print; next } on && /^## / { exit } on' "$FORGE/AGENTS.md")

{
  printf '<forge-context task="%s" phase="%s">\n\n' "$TASK_ID" "$PHASE"
  printf 'forge is active. Task %s is in phase %s. State: .forge/%s/. The policy hook enforces this phase'"'"'s tool rules and the Stop hook runs %s/scripts/forge-verify.sh before the turn may end.\n\nFORGE_HOME=%s\n\n' \
    "$TASK_ID" "$(printf '%s' "$PHASE" | tr '[:lower:]' '[:upper:]')" "$TASK_ID" "$FORGE" "$FORGE"
  if [ -n "$SKILL" ]; then printf '## Phase playbook (%s)\n\n%s\n\n' "$LABEL" "$SKILL"
  else printf 'No phase skill found for %s. Follow skills/forge/SKILL.md.\n\n' "$PHASE"; fi
  [ -n "$INDEX" ] && printf '%s\n\n' "$INDEX"
  printf '</forge-context>\n'
} | head -c "$MAX_CHARS"
exit 0
