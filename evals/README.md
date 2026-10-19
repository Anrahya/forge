# forge evals

"Above its weight class" is a claim. This directory is where it gets evidence.

## What an eval task is

A directory under `tasks/` with:

- `task.json`: `{ "id", "type", "repo" (git URL or local path), "base" (commit), "prompt" (what the user would type), "hidden_check" (a command run after the agent finishes; exit 0 means pass), "budget" }`
- `hidden/`: files the agent never sees, such as a reference test suite the hidden check copies in before running.

Good sources: real bugs from your own repos with the fix commit as the hidden reference, features whose tests you write before the agent starts.

## Running

`evals/run.sh <task-id> --mode bare|forge --model <provider/model>` checks out the repo at `base` in a temp dir, runs the agent in the chosen mode, then runs `hidden_check` and records to `results/<run-id>.json`: pass, diff size, gate failures by gate, review loops, tokens, wall time.

`evals/compare.sh` prints bare vs forge per task and in total.

The harness runner for each mode lives in `evals/runners/<harness>.sh`. The DSH runner is the first one; it is a stub until the adapter is installed in a DSH profile.

## Rule

Re-run the set on every gate or playbook change. A change that does not move pass rate or blocking-finding count is a change to revert.
