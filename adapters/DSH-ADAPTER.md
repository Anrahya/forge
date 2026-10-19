# forge-dsh

DeepSeek Harness (DSH) adapter for forge. It moves the forge rules that can be enforced out of the prompt and into the harness: the phase tool policy, the "no done without gates" check, playbook re-injection, and role-routed subagents. See `../../DESIGN.md` sections 7 and 10.

Targets DSH **0.2.1-rc.2** (npm `latest` on 2026-10-20). Every hook and service call is typechecked against the published `@deepseek-ai/*@0.2.1-rc.2` declarations (devDependencies). `engines.dsh` and the peer ranges accept `0.2.0-rc.2` too, but the subagent API changed between those releases (`startActivation` replaced `start`/`startContinuable`), so on 0.2.0-rc.2 only `forge_spawn` is expected to fail. Node `^22.19.0 || >=24`.

The repository root is the plugin package. `src/` and `lib/` here are the adapter; `skills/`, `scripts/`, `templates/`, `AGENTS.md` and `forge.toml` are the portable forge layer the adapter serves.

## What it registers

Each registration is a Cordis effect, so unloading or hot-reloading the plugin removes it.

| # | DSH API | Behavior |
|---|---|---|
| 1 | `ctx.skills.registerProvider` | Exposes every `skills/**/SKILL.md` (router, phase skills, principles, micro) as bundled skills. Names must match `^[a-z0-9]+(?:-[a-z0-9]+)*$`; invalid files are skipped with a warning. Playbooks under `skills/forge/playbooks/` are resources of the `forge` skill, not skills. |
| 2 | `tools/pre-execute` waterfall | Reads `.forge/current` and `.forge/<id>/state.json` from the session cwd and applies the phase policy below. Denials come back to the model as the tool result `Error: <reason>`. No `.forge/current`: does nothing. |
| 3 | `agent/pre-step` waterfall | Enters one `user` message (source `{ kind: 'forge', form: 'instructions' }`) with the phase skill body and the `## Principle index` section of `AGENTS.md`. |
| 4 | `agent/turn-stopping` serial checkpoint | Runs `scripts/forge-verify.sh --task-dir .forge/<id> --phase <phase>`. On failure, `agent.steer()` queues the verify.log tail so the turn continues instead of ending as done. |
| 5 | `ctx.tools.register(defineTool(...))` | `forge_spawn` tool: `description`, `prompt`, `role`, `run_in_background`. Maps the role to `{ provider, model }` from `forge.toml` and calls `ctx.subagents.startActivation` with a reserved `childId`, `agentOptions`, and `delivery: 'parent'` (background, result delivered to the parent as a message) or `'caller'` (foreground, awaited). |
| 6 | `agent/request` waterfall | Sets `LlmCallConfig.reasoningEffort` for a role from `forge.toml [effort]`, only when `ctx.llm.resolveModelInfo(provider, model).reasoning.efforts` lists that id. |

`agent/disposed` is also observed to drop per-agent state.

## Build and install

The repository root is the package, and `lib/` is committed, so a git install needs no build step and no pnpm `allowBuilds` entry (DSH `docs/user/develop/basic/publish.md`, "Installing from GitHub").

```sh
dsh plugin --profile web add github:Anrahya/forge          # tracks the default branch
dsh plugin --profile web add github:Anrahya/forge#v0.1.0   # pinned, preferred
dsh --profile web --dump-config                            # shows a "# == forge-dsh" layer
```

Restart the Web Host once and reload the page. Startup prints `[forge-dsh] loaded forgeRoot=<path>`. Remove with `dsh plugin --profile web remove forge-dsh`.

**Desktop app.** Settings, Plugins, Add plugin, then enter `github:Anrahya/forge` (or the pinned form) in "Package name or address". The CLI above only writes the `web` profile; the Desktop app manages its own profile.

**From a local checkout** (development; edits apply live):

```sh
npm install --ignore-scripts
npm run check                      # typecheck, tests, build lib/
dsh plugin --profile web add /absolute/path/to/forge
```

`forgeRoot` resolves to the plugin `forgeRoot` config, else this package when it carries `AGENTS.md` and `skills/`, else `<package>/assets`.

## Configure roles: forge.toml

Put `forge.toml` at the project root (the nearest one up from the session cwd wins). Only these tables are read; the reader is a small built-in TOML subset (strings, numbers, booleans, arrays, `[table]` headers) and reports the line of anything else.

```toml
[roles]
# provider/model; the first "/" splits, so model ids may contain slashes
build  = "deepseek-official/deepseek-chat"
review = ["deepseek-official/deepseek-reasoner", "openrouter/qwen/qwen3-coder"]
scout  = "deepseek-official/deepseek-chat"
escalation = "inherit"

[effort]          # reasoning effort ids, applied only when the live route lists them
review = "high"
shape  = "high"

[families]        # optional; default family = leading letters of the model id
"deepseek-reasoner" = "deepseek"
```

- Roles: `ground`, `scout`, `shape`, `build`, `review`, `report`, `escalation`. An unmapped role, or `"inherit"`, runs the child on the parent conversation's route.
- `review` takes a list of candidates and uses the first whose model family differs from build's, so the reviewer is a different family whenever one is configured. If every candidate shares build's family, it uses the first and `forge_spawn` returns a `note` saying so.
- `[effort]` applies to children spawned with that role and to the main agent while the task is in the phase of the same name. An effort id the route does not list is ignored, never sent.
- `forge_spawn` with role `escalation` asks the human first (`tools/pre-execute` returns `ask`), per DESIGN.md decision 3. With no approval service DSH turns `ask` into a denial.
- Use the provider and model ids your DSH install shows in its model selector. forge passes them through as `agentOptions` without validating them first.

## Plugin settings

Override the plugin row in the profile's `cordis.patch.yml` (or `$DSH_HOME/cordis.patch.yml`). A patch replaces the whole `config`, so restate every key you set:

```yaml
- id: forge-dsh
  config:
    reinjectEverySteps: 4
    maxVerifyRounds: 3
    verifyTimeoutMs: 600000
```

| Key | Default | Meaning |
|---|---|---|
| `forgeRoot` | see above | Directory with `skills/`, `AGENTS.md`, `scripts/` |
| `reinjectEverySteps` | 4 | Steps between re-entries of unchanged forge context in one turn. 1 means every step |
| `maxInjectChars` | 24000 | Cap on the entered context |
| `verifyOnTurnStop` | true | Run forge-verify.sh before a top-level turn ends |
| `verifySubagents` | false | Also verify when a subagent's turn ends |
| `verifyTimeoutMs` | 600000 | Script time limit; the whole process group is stopped on timeout or cancel |
| `maxVerifyRounds` | 3 | Failed rounds per turn before the turn may end; then a notice is queued for the next turn |
| `verifyTailLines`, `verifyTailChars` | 80, 6000 | How much of verify.log is fed back |
| `spawnProvider` | `spawn` | `ctx.subagents` provider for `forge_spawn` (the base bundle's in-process provider) |
| `scratchDirs` | `[]` | Extra directories always writable; OS temp dirs are always included |

## Phase policy

| Phase | Mode | Writes allowed |
|---|---|---|
| ground, scout, review, verify | read-only | `.forge/**` and scratch dirs only |
| shape, build, report | guard referee | anything except referee paths |
| missing or invalid state.json | read-only (fail closed) | `.forge/**` only, so the router can repair state |

Referee paths, denied in every phase: `scripts/gates/**`, `scripts/forge-verify.sh`, `.github/workflows/**`, `.forge/**/verify.log`, and at any depth `vitest.config.*`, `vitest.workspace.*`, `jest.config.*`, `eslint.config.*`, `.eslintrc*`, `.eslintignore`, `tsconfig*.json`, `jsconfig.json`, `biome.json(c)`, `.prettierrc*`, `prettier.config.*`, `clippy.toml`, `rustfmt.toml`. `Cargo.toml` is content-checked: edits inside `[dev-dependencies]` (including `target.*.dev-dependencies`), adding such a header, `cargo add/remove --dev`, and shell writes to Cargo.toml are denied; `[dependencies]` stays writable.

A child started by `forge_spawn` is also held to its role's phase: a `review` child is read-only even while the task is in BUILD. Both the task phase and the role phase must allow a write.

Tools policed: `write`, `edit` (`file_path`), `str_replace_editor` (`create`, `str_replace`, `insert`), `bash` (`command`, `workdir`), `pwsh`, `terminal_send` (`text`). `run_code` is allowed because DSH runs each of its sub-calls through `tools/pre-execute` individually. Other tools, including MCP tools that write files, are not policed.

### Shell write heuristic

Static analysis of the command text (`src/shell.ts`), honoring quotes, dropping heredoc bodies, and following `cd`, `bash -c`, `eval`, `npx`, `xargs`, and `find -exec`. A command writes when it has:

- an output redirect (`>`, `>>`, `>|`, `&>`, `N>`), except to `/dev/null` and friends;
- a file command: `rm`, `rmdir`, `unlink`, `touch`, `mkdir`, `shred`, `truncate`, `chmod`, `chown`, `chgrp`, `mv`, `cp`, `ln`, `install`, `rsync`, `tee`, `dd of=`, `curl -o/-O`, `wget`, `tar -x`, `unzip`, `patch`, `find -delete`;
- an in-place edit: `sed -i`, `perl -i`, `ruby -i`;
- a mutating tool: `git` (add, commit, checkout, reset, restore, stash, merge, rebase, push, and similar), `npm`/`pnpm`/`yarn`/`bun` install-type subcommands, `pip`/`uv`/`poetry` installs, `cargo` add/remove/update/fix/install/new, `cargo fmt` without `--check`, `cargo clippy --fix`, `prettier --write`, `eslint --fix`, `biome --write`, `rustfmt`/`black` without `--check`, `gofmt -w`, `ruff --fix`;
- inline code (`node -e`, `python -c`, `ruby -e`, `perl -e`, `deno eval`) that calls a file-writing API.

Writes to a resolvable path are judged by path. Writes with an unknown target (a variable, `git commit`, `npm install`) are denied in read-only phases and, in guard phases, denied only when an argument names a referee path. Known gaps: anything a program does internally (`make`, `npm run <script>`, a script file, a test that writes snapshots) is invisible here. The gates are the backstop. `pwsh` support is coarser: cmdlets such as `Set-Content` and `Remove-Item` are unknown-target writes.

## Verify at turn end

`agent/turn-stopping` fires when the model owes no response. For top-level agents with forge active, the adapter runs `scripts/forge-verify.sh` (the project copy wins over the forge copy) from the project root.

- exit 0: the turn ends.
- exit 1: the tail of `.forge/<id>/verify.log` is steered back with "the turn is not done". Only a verify.log written during this run is used; a stale one is ignored in favor of the script output.
- other exit, timeout, missing script: steered back as an infrastructure error pointing at S2/S5.
- after `maxVerifyRounds` failures in one turn the turn may end, and a notice is queued with `agent.inject()` for the next turn.

## Injection cost

Each entered message becomes a durable `user/message` in the session log and stays in history until compaction. A phase skill is one page (1k to 2k tokens) plus about 600 for the index, so entering it on every step of a 30-step turn would add 50k or more tokens, above the 30k phase budget in DESIGN.md section 7. The adapter therefore enters it on the first step of each turn, whenever the content changes (phase change or edited skill), and otherwise every `reinjectEverySteps` steps (default 4). The dedupe state is in memory per agent; DSH 0.2.0-rc.2 exposes the session log, but reading it back for this was not worth the coupling.

## API confirmation

"Confirmed" means the shape is in the published 0.2.0-rc.2 type declarations and `tsc` checks this code against it. Nothing here has been run inside a live DSH host yet; `tests/plugin.smoke.test.ts` drives the real entry module through a fake Cordis context.

| Item | Status | Source |
|---|---|---|
| `tools/pre-execute(exec, next)`, `exec.name`, `exec.arguments`, `exec.agent`; decisions `allow`/`deny{reason}`/`ask{reason}` | Confirmed | `@deepseek-ai/dsh-tools` `lib/types/index.d.ts` |
| Deny reason shown to the model as `Error: <reason>` | Confirmed (runtime source) | `dsh-tools` `lib/types/index.js` pre-execute handling |
| `run_code` sub-calls pass through pre-execute individually | Confirmed (doc) | `docs/tool-execution-pipeline.md` |
| Session cwd at `agent.session.header.cwd` | Confirmed | `dsh-session` `SessionHeader.cwd`; `dsh-tool-fs` rc.2 `sessionCwd()` uses the same field |
| `agent/pre-step({agent, messages, turn, step, signal}, next)` returning `{kind:'enter', messages}` | Confirmed | `dsh-agent` `runtime-types.d.ts`; append pattern copied in spirit from `dsh-agent` `model-selection.js` |
| pre-step fires on tool-continuation steps, not only on turn start and steering | HYPOTHESIS | Inferred from the empty-batch guard in `model-selection.js`. Confirm with the agent-loop driver source (`packages/core/agent-loop`) or a live run. If false, injection happens once per turn and per steer only |
| Custom message source `{ kind: 'forge', form }` via `MessageSourceMap` merge | Confirmed | `dsh-llm` `message.d.ts` (merge-extensible; consumers fall through unknown kinds) |
| `agent/turn-stopping({agent, turn, signal})`, continue the turn with `agent.steer(message)` | Confirmed by declaration doc | `runtime-types.d.ts`: "a listener that objects steers (`agent.steer(...)`) and the machine re-reads its inbox: fresh steering runs another step". Not exercised in a live host |
| `agent.inject(message)` reaches the next turn without waking the agent | Confirmed by declaration doc | `runtime-types.d.ts` `Agent.inject` |
| Subagent detection via `header.origin === 'subagent'` / `delegationDepth` | Confirmed | `SessionHeader` |
| `ctx.subagents.start(name, SubagentStartRequest)`, `startContinuable({provider, label, childId, request, signal})`, `getProvider()`, continuation capability = `prepareContinuable` method presence | Confirmed | `dsh-subagent` `index.d.ts`, `types.d.ts`; `src/index.ts` has compile-time assertions that the request shapes fit |
| Provider name `spawn` exists in the base bundle | Confirmed (master), HYPOTHESIS for 0.2.1-rc.2 | `packages/bundle/base/cordis.patch.yml` on master; pstack-dsh HARNESS.md says the same for rc.2 |
| `agent/request({agent, turn, step, signal}, next)` returning `LlmCallConfig`; `resolveModelInfo().reasoning.efforts[].id` | Confirmed | `dsh-agent` `runtime-types.d.ts`; `dsh-llm` `types.d.ts` |
| Host-level `agent/request` fires for in-process children | HYPOTHESIS | Same caveat pstack-dsh HARNESS.md states. Confirm with `packages/subagent/subagent-spawn-in-process` source or a live run. Note 0.2.1-rc.2 `AgentOptions` also has `reasoningEffort`, which would set child effort at spawn time instead |
| `ctx.skills.registerProvider(create)` with `SkillCandidate`/`SkillDefinition` shapes, `BUNDLED_SKILL_RANK` | Confirmed | `dsh-skill` `index.d.ts` |
| `defineTool({ name, description, parameters, output: { schema, render }, execute })` | Confirmed | `dsh-tools` `schema.d.ts` |
| Tool names and args for `write`, `edit` (`file_path`), `bash` (`command`, `workdir`) | Confirmed | published `dsh-tool-fs` and `dsh-tool-bash` 0.2.0-rc.2 |
| `str_replace_editor`, `pwsh`, `terminal_send` names and args | HYPOTHESIS for 0.2.1-rc.2 | `docs/tool-catalog.md` on master; confirm against the rc.2 packages `dsh-tool-str-replace-editor`, `dsh-tool-pwsh`, `dsh-tool-terminal` |
| Install via `dsh plugin --profile web add <path>` | Confirmed (doc) | `docs/user/develop/basic/publish.md` |
| `dsh plugin add github:Anrahya/forge` installs this root-level package with committed `lib/` | Confirmed by the official publish doc (a git install fetches sources; no `prepare` script means no build allowance needed), not yet by a live `dsh` run | DSH `docs/user/develop/basic/publish.md`; pstack-dsh ships the same way |
| Profile override of the row's `config` by `- id: forge-dsh` | Confirmed (master doc) | `publish.md` "loading order"; `packages/bundle/web-app/cordis.patch.yml` |

## Development

```sh
npm test            # node --test: policy, shell, toml, roles, state, skills, inject, verify, spawn, plugin smoke, Claude Code parity
npm run typecheck
```

`tests/policy.test.ts`, `tests/toml.test.ts`, and `tests/runtime.test.ts` import only pure modules and need no DSH packages. `tests/plugin.smoke.test.ts` loads `src/index.ts` with the devDependency DSH packages and skips without them. `tests/claude-code-policy.test.ts` runs `../claude-code/scripts/hooks/policy.sh` and `src/policy.ts` on the same cases and requires identical decisions and reasons (skipped without bash and jq).

Source map: `src/index.ts` (wiring), `src/policy.ts` and `src/shell.ts` (policy), `src/state.ts` (task state, forge.toml), `src/roles.ts` and `src/toml.ts` (routing), `src/spawn.ts` (`forge_spawn`), `src/inject.ts` (pre-step context), `src/verify.ts` (turn-end gate), `src/skills.ts` (SKILL.md scan), `src/assets.ts` (forge root).
