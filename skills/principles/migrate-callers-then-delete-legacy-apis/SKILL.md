---
name: migrate-callers-then-delete-legacy-apis
description: "Apply when you add a new internal API while callers of the old one still exist."
disable-model-invocation: true
---

# Migrate callers then delete legacy APIs

## Rule

Move every caller to the new API and delete the old one in the same change. Do not leave an adapter, alias, or deprecated path for later. Update tests to assert the new contract, and delete tests that only protect the old internals. This holds when no outside user depends on the old API. If one does, say so in `task.md` and plan the removal there.

## Why

Two APIs for one job double what a reader must learn, and the old one gains new callers while it waits.

## Self-check

- Does a search for the old API name return no hits in live code?
- Did I delete the old API, not only mark it deprecated?
- Do the tests assert the new contract rather than the removed internals?

Fix every no before you move on.

## Enforced by

Reviewer checklist. G3 diff-hygiene flags new code added beside a deprecated sibling.
