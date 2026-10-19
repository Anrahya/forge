### Perf

A measured slowness to improve against a baseline. Numbers without the checklist do not ship.

1. GROUND: capture the baseline with the exact command, machine state, and three runs. Record median and range.
2. SCOUT: how others made this fast; whether a library or an index already solves it.
3. SHAPE: name the limiter. CPU, memory, I/O, a lock, a query, an allocation pattern. The fix targets the limiter, nothing else.
4. BUILD as a hypothesis loop. Each unit: hypothesis, change, measure, keep or revert. One commit per accepted win.
5. VERIFY: `micro/benchmark-checklist` on the final number. Verdict is faster, slower, no measurable difference, or inconclusive.
6. REVIEW. REPORT with before, after, median, range, and the limiter named.

**Reply:** the number, what limits it now, what was tried and reverted.
