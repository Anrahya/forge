#!/usr/bin/env bash
# evals/runners/dsh.sh --cwd <repo> --mode bare|forge --model <m> --prompt <text>
# Drives one agent run in DeepSeek Harness. Stub until the forge adapter is installed in a DSH profile:
# replace the body with the dsh CLI invocation for a non-interactive run (see adapters/dsh/README.md).
set -euo pipefail
cwd=""; mode=bare; model=""; prompt=""
while [ $# -gt 0 ]; do case "$1" in --cwd) cwd="$2"; shift 2;; --mode) mode="$2"; shift 2;; --model) model="$2"; shift 2;; --prompt) prompt="$2"; shift 2;; *) shift;; esac; done
if [ "$mode" = forge ]; then prompt="/forge $prompt"; fi
echo "STUB: would run dsh in $cwd with model '$model' and prompt: $prompt" >&2
exit 3
