# forge for Claude Code

The same enforcement as `../dsh`, built on Claude Code hooks.

| File | Role |
|---|---|
| `plugin.json` | Plugin manifest. Claude Code reads it from `<plugin root>/.claude-plugin/plugin.json`, and the plugin root must be the forge directory so `skills/` is found. Copy it there: `mkdir -p .claude-plugin && cp adapters/claude-code/plugin.json .claude-plugin/` (run in `forge/`). |
| `hooks.json` | Hook wiring, referenced from the manifest as `./adapters/claude-code/hooks.json`. |
| `scripts/hooks/policy.sh` | PreToolUse on `Write|Edit|MultiEdit|NotebookEdit|Bash`: the phase policy. |
| `scripts/hooks/stop.sh` | Stop: runs `scripts/forge-verify.sh`; blocks the stop on failure. |
| `scripts/hooks/inject.sh` | SessionStart and UserPromptSubmit: prints the phase skill and principle index as context. |
| `scripts/hooks/lib.sh` | Shared helpers, including the shell tokenizer. |

Requires `bash` (3.2 or later) and `jq`. Without jq the policy hook blocks write tools while forge is active and says why; the other hooks do nothing.

## Install

Local plugin directory (after copying the manifest as above):

```sh
claude --plugin-dir /path/to/forge
```

Or add the forge repo to a plugin marketplace and install `forge` from it. Without the plugin system, put the four hooks from `hooks.json` in the project's `.claude/settings.json`, replacing `${CLAUDE_PLUGIN_ROOT}` with the absolute forge path.

Environment knobs: `FORGE_DIR` (forge root, if not the plugin root), `FORGE_MAX_VERIFY_ROUNDS` (default 3), `FORGE_VERIFY_TAIL_LINES` (default 80), `FORGE_MAX_INJECT_CHARS` (default 24000).

## Behavior

- **Policy.** `policy.sh` is a port of `../dsh/src/policy.ts` and `src/shell.ts`: same phase modes, referee list, Cargo.toml dev-dependency check, and shell write heuristic, with the same deny text. `../dsh/tests/claude-code-policy.test.ts` runs both on 110 cases and requires identical decisions and reasons. Deny is exit 2 with the reason on stderr, which Claude Code shows to the model.
- **Verify.** `stop.sh` runs `scripts/forge-verify.sh --task-dir .forge/<id> --phase <phase>` (project copy first, then the forge copy). Exit 0 lets Claude stop. Exit 1 blocks the stop (exit 2) with the verify.log tail. Other exits block with an infrastructure message. After `FORGE_MAX_VERIFY_ROUNDS` blocked stops in a row, the stop is allowed and a `systemMessage` tells the user the gates still fail. The counter resets when `stop_hook_active` is false, which Claude Code sets on the first stop after a user prompt.
- **Injection.** `inject.sh` prints `<forge-context>` with the phase skill body (project `.agents/skills/forge-<phase>/` first) and the `## Principle index` section of `AGENTS.md`.

## Differences from the DSH adapter

| Area | DSH | Claude Code |
|---|---|---|
| Re-injection | `agent/pre-step`, inside the turn, every few steps | Once per user prompt and on session start, resume, clear, and compaction. There is no per-step hook, so drift inside a long tool loop is not reset |
| Continue after failed verify | `agent.steer()` inside `agent/turn-stopping` | Stop hook exit 2; Claude Code feeds stderr back and keeps going |
| Round cap notice | `agent.inject()` queues a notice into the next turn | `systemMessage` shown to the user |
| Subagents | `forge_spawn` routes each role to a model from `forge.toml` and holds the child to its role's phase | No `forge_spawn` and no per-role model routing. Task subagents run under the task's phase policy (PreToolUse applies to them); use Claude Code custom agents with a `model` field for routing |
| Escalation approval | `forge_spawn role=escalation` returns `ask` | Not applicable |
| Reasoning effort per role | `agent/request` | Not applicable |
| Tools policed | `write`, `edit`, `str_replace_editor`, `bash`, `pwsh`, `terminal_send` | `Write`, `Edit`, `MultiEdit`, `NotebookEdit`, `Bash`. MCP tools are not policed |
| Stale verify.log detection | mtime in milliseconds | checksum plus `ls -l` fingerprint (bash 3.2 `-nt` compares whole seconds). A rerun that writes byte-identical content in the same minute counts as stale, and the script's own output is shown instead |
| Skills | Plugin skills provider walks `skills/**/SKILL.md` | Claude Code discovers `skills/` under the plugin root. Whether it finds the nested `skills/principles/<name>/` and `skills/micro/<name>/` folders is unverified; if not, they still load through the router's file pointers |
| Timeout | Process group killed at `verifyTimeoutMs` | The Stop hook's `timeout` (900 s in `hooks.json`) |
