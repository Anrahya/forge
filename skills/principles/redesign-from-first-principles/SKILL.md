---
name: redesign-from-first-principles
description: "Apply when a new requirement lands on an existing design and the easy path is to bolt it on as a special case."
disable-model-invocation: true
---

# Redesign from first principles

## Rule

Ask what you would build if the new requirement had been known from day one. Aim at that design. Carry the change through every reference, including types, docs, examples, and tests. Deliver it in small steps, but point each step at the redesigned target.

## Why

A bolted-on requirement keeps the old shape and adds a special case that every reader must learn.

## Self-check

- Did I read every file the requirement touches before choosing the change?
- Would a fresh design that included this requirement look like what I am about to write?
- Did the change reach types, docs, and examples, not only the code path I tested?

Fix every no before you move on.

## Enforced by

Playbook only. No gate checks this, so the self-check above is the only guard.
