### Bug

Be scientific. Every shipped line traces to runtime evidence. A guard that "might help" is a hypothesis, not a fix, and does not ship.

1. GROUND: reproduce on the real surface yourself. Capture the failing run to `repro.log`. If it will not reproduce, tighten conditions or add instrumentation until it fires. Ask the human only with a specific reason the surface cannot be reached.
2. Binary-search the mechanism. List candidate hypotheses in `decisions.tsv`. Each pass, take the split that cuts the most remaining space, get runtime evidence, eliminate. No guessing.
3. After two failed fixes that share a premise, stop fixing. Write the premise down as a decision row and test it directly (`attack-the-premise`).
4. Confirm the surviving mechanism with runtime evidence before writing the fix.
5. BUILD: when a cheap test path exists, the failing test lands first (`micro/tdd`, `red.log`). Make the smallest change the evidence justifies. Revert anything a refuted hypothesis motivated.
6. VERIFY: the original repro now passes on the same surface. Inconclusive or wrong-surface is not a pass.
7. REVIEW, then REPORT. The report pastes failing-then-passing output verbatim.

**Reply:** what was broken, the root cause, the fix, how it was verified.
