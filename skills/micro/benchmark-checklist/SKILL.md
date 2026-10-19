---
name: benchmark-checklist
description: "Use before you report or act on any measured performance number, such as a speedup, a regression, or a library comparison."
user-invocable: true
---

# Benchmark checklist

Write down the claim you expect to make. Then answer each question from real runs, not from reading code.

1. What limits it? Name the bound resource or code path from a profile or counters taken in a separate run. Confirm the load generator is not the limit.
2. Did every side run tuned? Use release builds, production flags, the same data and versions, and comparable cache state. A side left on defaults means you compared configurations.
3. Does it break a physical limit? Compare it against disk, network, and core capacity, and against the share of time the changed piece took. A result past a limit measured something else.
4. Did anything error? Count failures and wrong outputs.
5. Does it reproduce? Run each side at least five times, alternating between them. Report the median and the range. A gap inside the run-to-run spread is no measurable difference.
6. Does it matter end to end? Measure the path a user waits on and report the micro result as a share of it.
7. Did the work happen inside the timed region? Confirm the request arrived, the rows were written, and the result was used.

## Verdict

Lead with one of four verdicts: faster, slower, no measurable difference, or inconclusive. Then give the number with its unit, the run count, the median, the range, and the limiter. Call it inconclusive when you cannot name the limiter, a side ran untuned, or questions 4 or 7 went unchecked, and name the gap.
