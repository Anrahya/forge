---
name: blast-radius
description: "Use on a small diff you do not fully trust, to find what else it could break and prove the fact that makes it safe."
user-invocable: true
---

# Blast radius

1. Read the diff. Write what the code now does differently, including what the diff does not spell out.
2. Find what else it could break beyond the callers that grep shows. Check the library source at its pinned version, when the code runs, wire and storage formats, flags, and other readers of the same data.
3. Name the one fact that makes the change safe, in one sentence. For example, "this only removes cache entries that have already expired."
4. Prove that fact by running code. Write a small script or test that calls the real function and fails loudly if the fact is false. Run it and keep the output.

Report the safety fact with its proof, or mark it unproven. Then list the confirmed risks with `file:line` and the risks you checked and cleared.
