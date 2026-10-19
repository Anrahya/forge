#!/usr/bin/env bash
# evals/compare.sh: bare vs forge pass rate and diff size from results/*.json
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 -I - "$here/results" <<'PY'
import json, sys, glob, collections
rows = [json.load(open(f)) for f in glob.glob(sys.argv[1] + "/*.json")]
by = collections.defaultdict(list)
for r in rows: by[(r["task"], r["mode"])].append(r)
tasks = sorted({t for t, _ in by})
print(f"{'task':30} {'bare pass':>10} {'forge pass':>11} {'bare lines':>11} {'forge lines':>12}")
tot = collections.Counter(); n = collections.Counter()
for t in tasks:
    cell = {}
    for m in ("bare", "forge"):
        rs = by.get((t, m), [])
        p = sum(r["pass"] for r in rs); l = sum(r["diff_lines"] for r in rs)
        cell[m] = (f"{p}/{len(rs)}" if rs else "-", f"{l/len(rs):.0f}" if rs else "-")
        tot[m] += p; n[m] += len(rs)
    print(f"{t:30} {cell['bare'][0]:>10} {cell['forge'][0]:>11} {cell['bare'][1]:>11} {cell['forge'][1]:>12}")
print(f"{'total':30} {tot['bare']}/{n['bare']:>7} {tot['forge']}/{n['forge']:>8}")
PY
