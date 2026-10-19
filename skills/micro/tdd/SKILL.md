---
name: tdd
description: "Use when a bug fix or behavior change has a cheap local test path, or when the user asks for a failing test first."
user-invocable: true
---

# Test first

A cheap path is an existing test runner for this code that runs in seconds with no new setup.

## When a cheap path exists

1. Write one sentence stating the behavior the change should make true.
2. Write the smallest test that checks that behavior through the code's public interface.
3. Run it and save the output to `red.log`.
4. Confirm it fails for the right reason. The assertion about the target behavior must be what fails. A compile error, import error, missing fixture, or timeout is the wrong reason. Fix the test first.
5. Make the smallest change that should make it pass.
6. Rerun the test and its neighbors. Save the output.

## When no cheap path exists

Prefer no new test over a bad test. Use the closest executable check instead, such as a script that calls the real function, a reproduction command, or a driven run of the app. It must still fail before the change and pass after it.

A bad test is one that does any of these:

- passes with the implementation removed, or asserts on mocks of the code it claims to test
- pins internals such as call order or private helpers
- depends on timing, the network, or shared global state
- needs heavy new setup for a small fix, or gets deleted right after

## Guardrails

Never weaken or delete an assertion to match a wrong implementation. Change an existing assertion only when the required behavior changed, and log why in `decisions.tsv`.

## Final report

Name the failing-before evidence: the test or check, the command, the failure it printed, and the `red.log` path. Name the passing-after evidence the same way. If you could not show a failure before the change, say why and name the check you used instead. Gates G1, G2, G7, and G8 check this.
