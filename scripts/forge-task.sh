#!/usr/bin/env bash
# forge-task.sh: create a task directory from templates and track the current phase.
#   forge-task.sh new <slug>        -> prints the task id, writes .forge/current
#   forge-task.sh phase <name>      -> sets state.json phase for the current task
#   forge-task.sh current           -> prints the current task id
#   forge-task.sh show              -> prints task id and phase
# Run from the target project's root. FORGE_HOME must point at the forge checkout
# (defaults to the directory above this script).
set -euo pipefail

FORGE_HOME="${FORGE_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PHASES="intake ground scout shape build verify review report done"

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

cmd="${1:-}"; shift || true
case "$cmd" in
  new)
    slug="${1:-}"; [ -n "$slug" ] || usage
    slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')"
    id="$(date +%Y%m%d)-$slug"
    dir=".forge/$id"
    if [ -e "$dir" ]; then echo "task exists: $dir" >&2; exit 1; fi
    mkdir -p "$dir/scratch"
    for t in task ground scout shape review report; do cp "$FORGE_HOME/templates/$t.md" "$dir/$t.md"; done
    cp "$FORGE_HOME/templates/decisions.tsv" "$dir/decisions.tsv"
    : > "$dir/fetch.log"
    printf '{ "task": "%s", "phase": "intake", "loops": { "build": 0, "review": 0 } }\n' "$id" > "$dir/state.json"
    printf '%s\n' "$id" > .forge/current
    echo "$id"
    ;;
  phase)
    name="${1:-}"; [ -n "$name" ] || usage
    case " $PHASES " in *" $name "*) ;; *) echo "unknown phase: $name (one of: $PHASES)" >&2; exit 2;; esac
    id="$(cat .forge/current 2>/dev/null || true)"; [ -n "$id" ] || { echo "no current task; run: forge-task.sh new <slug>" >&2; exit 1; }
    f=".forge/$id/state.json"
    # minimal JSON edit without jq: replace the phase value
    sed -i.bak -E "s/\"phase\": \"[a-z]+\"/\"phase\": \"$name\"/" "$f" && rm -f "$f.bak"
    echo "$id -> $name"
    ;;
  current)
    cat .forge/current
    ;;
  show)
    id="$(cat .forge/current)"; echo "task: $id"; cat ".forge/$id/state.json"
    ;;
  *) usage ;;
esac
