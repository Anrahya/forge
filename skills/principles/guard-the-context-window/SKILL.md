---
name: guard-the-context-window
description: "Apply when a step would pull large files, long logs, or many search results into the main context."
disable-model-invocation: true
---

# Guard the context window

## Rule

Send bulk reading to a subagent or a script, and keep only the findings in the main thread. Read the part of a file you need, not the whole file. Pass work between phases through files in `.forge/<task>/`, not through conversation. Stay inside the phase budget.

## Why

A crowded context degrades reasoning, and long contexts are where weaker models drift the most.

## Self-check

- Do I need all of the output I am about to read?
- Did I write my findings to a file the next phase can read?
- Am I still under the phase budget?

Fix every no before you move on.

## Enforced by

A phase budget of about 30k tokens, file-only handoff between phases, and bulk reads delegated to subagents.
