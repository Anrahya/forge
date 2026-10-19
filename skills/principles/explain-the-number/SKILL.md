---
name: explain-the-number
description: "Apply when you are about to trust, report, or act on any measured number, such as a speedup, a regression, a latency, a throughput, or an eval score."
disable-model-invocation: true
---

# Explain the number

## Rule

Name what limits the number, using a profile or counters taken during a run. Then list what else the number could be measuring, such as errors, cached or skipped work, code that never ran, an untuned side, or noise. Rule out each one with evidence. Keep the run count, the spread, and the limiter next to the number.

## Why

A number you cannot explain may be measuring something other than the work.

## Self-check

- Can I say why the result is not twice as good?
- Did I rule out errors, skipped work, and noise with evidence from runs?
- Does the report give the run count, the median, the range, and the limiter?

Fix every no before you move on.

## Enforced by

The perf playbook runs the seven questions in `micro/benchmark-checklist` before any number is reported.
