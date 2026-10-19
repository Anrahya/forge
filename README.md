# forge

A verification-first engineering workflow for non-frontier coding models (DeepSeek, GLM, and other cheap open models), packaged as a DeepSeek Harness plugin. The discipline is pstack's (Lauren Tan). The enforcement is forge's: every rule that can be a gate is a gate, because a weaker model agrees with principles and then ignores them.

Design: [DESIGN.md](DESIGN.md). Contract and principle index: [AGENTS.md](AGENTS.md). Adapter internals: [adapters/DSH-ADAPTER.md](adapters/DSH-ADAPTER.md).

## Install into DeepSeek Harness

For an agent or a person. The repository root is the plugin package and `lib/` is committed, so a git install needs no build step and no pnpm build allowance.

Web profile, from a terminal:

```sh
dsh plugin --profile web add github:Anrahya/forge#v0.1.0
```

Then restart the Web Host once and reload the page. Check the layer loaded:

```sh
dsh --profile web --dump-config | grep forge-dsh
```

Desktop app: open Settings, then Plugins, then Add plugin, and enter `github:Anrahya/forge#v0.1.0` in "Package name or address". Reload when the app asks.

Startup logs print `[forge-dsh] loaded forgeRoot=<path>`. Remove with `dsh plugin --profile web remove forge-dsh`.

Requirements: DSH 0.2.1-rc.2 (also accepts 0.2.0-rc.2, where only `forge_spawn` is expected to fail), Node 22.19 or newer, bash, git. The gate scripts need the target project's own toolchain (node and npm for TypeScript, cargo for Rust).

## Use

In a project, type `/forge <task>`. The router classifies the task, opens its playbook, and runs the phases GROUND, SCOUT, SHAPE, BUILD, VERIFY, REVIEW, REPORT in fresh contexts. State lives in `.forge/<task-id>/`. The harness denies tool calls outside the current phase's policy and runs the gates before a turn may end as done.

Configure which model plays which role in `forge.toml` at your project root (copy the one here). The reviewer defaults to a different model family than the builder.

For runtime verification on a real app surface, run `/forge-verify-setup` once per project. It writes a project-local skill that launches, drives, and captures evidence from the app, which gate G9 then executes.

## What is here

| Path | What |
|---|---|
| `AGENTS.md` | The contract every phase reads, plus the 24-principle index |
| `skills/forge/` | The router and the eight playbooks |
| `skills/forge-*/` | Phase skills: ground, scout, shape, build, review, report, verify-setup, verify-maintain, correct |
| `skills/principles/` | One leaf per principle, loaded on demand |
| `skills/micro/` | sharpen, in-your-own-words, bro, unslop, tdd, benchmark-checklist, blast-radius |
| `templates/` | The artifact each phase writes; gate G0 checks the headings |
| `scripts/gates/` | Fourteen deterministic gates with a self-test (`npm run selftest`) |
| `scripts/forge-verify.sh` | Runs a phase's gates and writes verify.log |
| `scripts/forge-task.sh` | Creates a task dir and tracks the phase |
| `src/`, `lib/` | The DSH plugin: tool policy, playbook re-injection, the done-gate, role-routed spawn |
| `adapters/claude-code/` | The same four hooks for Claude Code |
| `evals/` | Bare vs forge comparison harness |
| `forge.toml` | Roles, budgets, loop limits |

## Develop

```sh
npm install --ignore-scripts
npm run check       # typecheck against the DSH packages, 206 unit tests, build lib/
npm run selftest    # 118 gate cases, each gate's pass and fail path
dsh plugin --profile web add "$PWD"     # link install; edits apply live
```

Commit `lib/` with every source change; a git install does not build.

## Portability

Skills, templates, and gate scripts are harness-neutral (Agent Skills format). Only `src/` and `adapters/` know about a harness. Adding one means mapping four hooks: deny a tool call, inject a message each step, run a check before the turn ends, spawn a role with a model.

## License

MIT. The 24 principle names and the shape of the router, playbooks, and verification skill follow pstack (MIT, Lauren Tan, `cursor/plugins/pstack`); the text here is original.
