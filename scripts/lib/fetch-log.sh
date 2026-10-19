#!/usr/bin/env bash
# fetch-log.sh: fetch a URL and, only if the fetch succeeds, record it in the task's fetch.log.
#
# Why: G13 (sources-fetched) refuses any URL in scout.md that was never fetched.
# A model that cites a search snippet or an invented URL has no fetch record.
#
# Usage: fetch-log.sh [--task-dir .forge/<id>] <url>
#   Without --task-dir, the task is read from .forge/current.
# Behavior: tries curl HEAD, falls back to GET when HEAD is refused. A final
#   status of 2xx or 3xx appends "<UTC time><TAB><status><TAB><url>" to
#   <task-dir>/fetch.log and exits 0. Anything else exits 1 and logs nothing.
#   Set FORGE_FETCH_SAVE=1 to also save the body under <task-dir>/sources/.

td=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    --task-dir) td="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --task-dir=*) td="${1#*=}"; shift ;;
    -*) echo "fetch-log.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) url="$1"; shift ;;
  esac
done
if [ -z "$td" ] && [ -f .forge/current ]; then
  td=".forge/$(head -n 1 .forge/current | tr -d '[:space:]')"
fi
if [ -z "$td" ] || [ ! -d "$td" ]; then
  echo "fetch-log.sh: no task directory. Pass --task-dir .forge/<id> or write the id to .forge/current." >&2
  exit 2
fi
case "$url" in
  http://*|https://*) ;;
  *) echo "fetch-log.sh: only http(s) URLs are recorded (got '$url')" >&2; exit 2 ;;
esac
command -v curl >/dev/null 2>&1 || { echo "fetch-log.sh: curl is not installed" >&2; exit 2; }

status="$(curl -sS -o /dev/null -I -L --max-time 20 -w '%{http_code}' "$url" 2>/dev/null)"
case "$status" in
  2??|3??) ;;
  *) status="$(curl -sS -o /dev/null -L --max-time 30 -w '%{http_code}' "$url" 2>/dev/null)" ;;
esac
case "$status" in
  2??|3??)
    printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$status" "$url" >> "$td/fetch.log"
    if [ "${FORGE_FETCH_SAVE:-0}" = 1 ]; then
      mkdir -p "$td/sources"
      name="$(printf '%s' "$url" | sed 's#^https\{0,1\}://##; s#[^A-Za-z0-9._-]#_#g' | cut -c1-120)"
      curl -sS -L --max-time 30 -o "$td/sources/$name" "$url" 2>/dev/null
    fi
    echo "fetched $status $url (logged to $td/fetch.log)"
    exit 0 ;;
  *)
    echo "fetch-log.sh: fetch failed for $url (status '${status:-none}'); nothing logged" >&2
    exit 1 ;;
esac
