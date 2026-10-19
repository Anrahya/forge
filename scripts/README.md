# forge scripts

The gates are the product. Each one reads files and logs, never the model's claims, and each one has been seen failing on bad input by `gates/selftest.sh`.

```
scripts/
  forge-verify.sh          run the gates a phase needs, write .forge/<id>/verify.log
  forge-task.sh            create a task dir from templates, track the phase
  gates/gNN-<name>.sh      one gate per file (G0 to G13)
  gates/selftest.sh        builds throwaway repos and proves each gate passes good input and fails bad input
  gates/fixtures/          ts/ (vitest + typescript), rust/ (one crate), templates/ (for G0)
  lib/common.sh            shared helpers, sourced by every gate
  lib/task-meta.sh         read one key from task.md front matter
  lib/detect-lang.sh       ts, rust, "ts rust", or unknown
  lib/run-tests.sh         resolve test/lint/typecheck/format commands; run tests into red.log or green.log
  lib/diff-stats.sh        added/removed line counts for the diff under test
  lib/fetch-log.sh         fetch a URL and record it in fetch.log (G13 reads it)
```

## Conventions

**Where and how gates run.** Gates are bash (3.2 compatible, so macOS `/bin/bash` works) and run from the target project's root. They use only git, sed, awk, grep, find, and the project's own toolchain. Where BSD and GNU tools differ the scripts pick a portable form (`find -newer` for mtimes, `stat -c %Y` with a `stat -f %m` fallback, `shasum -a 256` with a `sha256sum` fallback, `sed -i.bak`).

**Arguments.** Every gate takes:

| Flag | Meaning |
|---|---|
| `--task-dir .forge/<id>` | required |
| `--base <ref>` | optional. Default: `base` from task.md if it resolves, else `main`, else `master`, else the first commit |
| `--phase <phase>` | optional. Default: `phase` in `<task-dir>/state.json`. G0, G10, G12 and G13 use it |

**The diff under test** is `git diff <merge-base>...HEAD` plus the working tree (staged, unstaged) plus untracked files that are not ignored. In practice that is `git diff <merge-base>` for tracked files and `git diff --no-index /dev/null <file>` for untracked ones. Paths under `.forge/`, `node_modules/` and `target/` are excluded. Renames count as a delete plus an add.

**Exit codes and output.**

| Exit | Meaning | First status line |
|---|---|---|
| 0 | pass | `GATE gNN PASS: <summary>` |
| 1 | fail | `GATE gNN FAIL: <one paragraph: what was found, what to do>` |
| 2 | skipped (unsupported language or not applicable) | `GATE gNN SKIP: <reason>` |

A fail paragraph may be followed by indented detail lines (one finding per line). The paragraph and its details are fed to the model verbatim, so they say what to do, never contain an em dash, and never suggest editing the gate. A gate may also print `NOTE gNN: ...` lines for the reviewer; notes never change the exit code. A usage error (missing `--task-dir`, unknown flag) is a fail, not a skip.

**Test code.** A path is test code when a segment or the file name marks it: `__tests__/`, `test/`, `tests/`, `spec/`, `__mocks__/`, `*.test.*`, `*.spec.*`, `*_test.*`, `*-test.*`, `test_*`, `tests.*`. Plain substring matching was rejected because it misclassifies `latest.ts` and `attestation.rs`. In Rust, every line after the first `#[cfg(test)]` in a file is also test code.

**Languages.** `lib/detect-lang.sh` prints `ts` for `package.json`, `rust` for `Cargo.toml`, `ts rust` for both, else `unknown`. Per-file rules use the extension: `.ts .tsx .mts .cts .js .jsx .mjs .cjs` and `.rs`. Other files are not checked by G3 and G8, and the gates say so in a NOTE or a SKIP.

## task.md front matter

`.forge/<id>/task.md` starts with a YAML front matter block. `lib/task-meta.sh <task.md> <key>` reads one key with bash, sed and awk only.

| Key | Type | Used by |
|---|---|---|
| `type` | bug, feature, refactor, perf, investigate, research, chore | G0 G1 G2 G5 G7 G13 |
| `budget` | int, added + removed lines | G5 (default by type: bug 150, feature 600, refactor 400, chore 100, others 600) |
| `surface` | none, cli, http, ui | G9 |
| `non_goals` | list of path globs | G4 |
| `test_cmd`, `lint_cmd`, `typecheck_cmd` | string, optional; empty means detect | run-tests.sh, G1 G2 G6 G7 |
| `base` | git ref, optional | all gates that diff |

Supported YAML: `key: value`, quoted values, a trailing `# comment`, inline lists `[a, "b"]`, and block lists of `  - item`. Not supported: block scalars, nested maps. Exit codes: 0 found, 1 absent, 2 no front matter or usage error.

## ground.md

G4 reads the section `## Files likely touched`: one path or glob per list item (`- src/a.ts`, `- \`src/b/**\``; text after the path is ignored). Files in the diff that are not listed produce a NOTE, not a failure.

## Commands and logs

`lib/run-tests.sh` resolves commands in this order: task.md override, then the language default.

| Kind | TypeScript | Rust |
|---|---|---|
| test | `npx vitest run` if package.json mentions vitest, else `npm test` | `cargo test` |
| lint | `npx eslint .` if an eslint config exists | `cargo clippy -- -D warnings` |
| typecheck | `npx tsc --noEmit` if tsconfig.json exists | (clippy compiles) |
| format | (none) | `cargo fmt --check` |

`lint_cmd` replaces both the lint and the format defaults. With both languages present, test commands are joined with ` && `.

Any command that runs a tool through `npx` is refused (run-tests.sh exits 2, G6 and G7 fail) when the tool is not in `node_modules/.bin`. With `CI` set, npx would otherwise download a registry package of that name, and for `tsc` that package is an unrelated stub.

The model runs tests only through:

```
scripts/lib/run-tests.sh --task-dir .forge/<id> --log red     # before the change; expected to fail
scripts/lib/run-tests.sh --task-dir .forge/<id> --log green   # after the last edit; expected to pass
scripts/lib/run-tests.sh --task-dir .forge/<id> --print test  # show the resolved command
```

Log format (`red.log`, `green.log`):

```
command: npx vitest run
exit: 1
started: 2026-10-20T10:00:00Z
finished: 2026-10-20T10:00:02Z
--- output ---
<raw output>
```

Other files gates write in the task dir: `g06.log` (static check output), `g07.log` (test run with the implementation reverted), `g09/<skill>-<feature>.log` (runtime journeys), `verify.log` and `verify.log.sha256` (forge-verify.sh). `fetch.log` lines are `<UTC time><TAB><status><TAB><url>`, appended only by `lib/fetch-log.sh` after a 2xx or 3xx response.

## forge-verify.sh

```
scripts/forge-verify.sh --task-dir .forge/<id> --phase <phase> [--base <ref>]
```

| Phase | Gates |
|---|---|
| intake, ground, shape | G0 |
| scout | G0 G13 |
| build | G1 G2 G3 G5 G6 G7 G8 G11 |
| verify | every gate except G12 |
| review, done | none |
| report | G10 G12 |

It runs each gate, prints failures in full (first line only for pass and skip), and writes `verify.log` with a summary block (`gNN-name PASS|FAIL|SKIP`), a `result:` line, and every gate's full output. It then writes the log's sha256 to `verify.log.sha256`, which G11 uses to detect a hand-edited log. Exit 1 when any gate failed; skips do not fail the run.

## The gates

| Gate | Fails when | Skips when |
|---|---|---|
| G0 phase-artifacts | a `## ` heading from `templates/<artifact>.md` is missing or holds only comments or template placeholder lines; SHAPE for feature/refactor has fewer than two candidates. A heading ending in `(<types> only)` is required only for those types | no template exists for the phase's artifacts |
| G1 red-proof | `red.log` missing, not from run-tests.sh, exit 0, exit 126/127, or no failing test named in the output | type is not bug or feature |
| G2 green-after-edit | `green.log` missing, not from run-tests.sh, a narrower command than the project's, exit not 0, or any changed file is newer | investigate, research |
| G3 diff-hygiene | added lines contain banned patterns (see the script header for the full list) | no TS/JS or Rust file changed |
| G4 scope | a changed path matches a `non_goals` glob | never |
| G5 diff-budget | added + removed lines (lockfiles excluded) exceed the budget | never |
| G6 static | any lint, typecheck or format command exits non-zero | no command resolves |
| G7 tests-need-impl | tests pass with every non-test source change reverted to the merge base; or implementation changed with no test | type is not bug or feature; no implementation file changed |
| G8 test-quality | a new test has zero assertions or only snapshots; an added test line asserts a literal, computes the expected value with the code under test, or mocks the test's own subject | no test code added |
| G9 runtime | no verify skill, no feature files, a feature without a bash Drive block, or a journey exits non-zero or times out | surface is none |
| G10 evidence-integrity | an evidence pointer in report.md or decisions.tsv is missing, older than a changed file (red.log and repro.log exempt), or a value has no pointer and no `guess` label | neither file exists (outside the report phase) |
| G11 referee-readonly | the diff touches gate scripts, test runner, lint, format or typecheck config, Cargo.toml dev-dependencies, CI config, or verify.log no longer matches its recorded hash | never |
| G12 unslop-lint | report.md or PR.md prose has an em dash, "not just", listed AI vocabulary, chatbot phrases, or bold-label list lines. The vocabulary and phrase lists are read from the two fenced blocks in `skills/micro/unslop/SKILL.md`, so the skill and the gate share one list | no report.md or PR.md (outside the report phase) |
| G13 sources-fetched | a URL in scout.md has no fetch.log entry, or scout.md cites no URL when SCOUT is required | no scout.md (outside the scout phase); no URLs and SCOUT not required |

### G7 design note

The brief suggested `git stash` for non-test paths. G7 instead moves each non-test source file aside into `<task-dir>/.g07-backup/`, writes the merge-base version in its place, runs the tests, and moves the originals back. Reasons: BUILD commits each unit, and `git stash` cannot take out committed implementation, so a stash-based G7 would report "tests pass without the implementation" on correct work. The file-level approach covers committed, staged, unstaged and untracked changes alike, so there is no untracked-file case to refuse. Moving files (not copying) keeps content and mtime, so G2 is undisturbed. A trap restores on EXIT, INT, TERM and HUP; each restored file is checked against its recorded hash. If a backup dir is left behind (SIGKILL), G7 refuses to run and prints the manifest. Rust builds during G7 use `target/forge-g07` so the normal target dir never caches reverted code. Rust files keep their current `#[cfg(test)]` tail so inline test modules stay in place while the code above them reverts.

## Self-test

```
scripts/gates/selftest.sh                 # everything
scripts/gates/selftest.sh --only g07,g08  # some gates
scripts/gates/selftest.sh --verbose       # show every gate's output
scripts/gates/selftest.sh --keep          # keep the temp repos
```

It needs git, node and npm. On first run it installs vitest and typescript into `gates/fixtures/ts/node_modules` with `npm install`; without network it stops with a message instead of passing. Rust cases run when `cargo` is on PATH (clippy and rustfmt for G6), and are reported as skipped otherwise. Each case builds a fresh git repo from a fixture (base commit on `main`, work on a branch), creates a state, runs the gate, and asserts the exit code, the `GATE gNN` status line, required phrases in the output, and the absence of em dashes. The summary prints, per gate, whether its pass path and its fail path were exercised.

Change a gate, rerun the self-test. A gate change without a failing case for the new rule is not done.
