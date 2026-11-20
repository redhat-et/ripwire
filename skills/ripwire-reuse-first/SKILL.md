---
name: ripwire-reuse-first
description: >
  About to write ONE symbol (even a 'quick' one-liner) or add a dependency: reuse before you reinvent.
  Finds the building block that already exists, the house pattern to imitate, the duplicate you'd
  recreate, a vendored dependency. An interface or whole feature → before-you-build. One --exemplar or --grep call
  at most.
allowed-tools: Bash, Read
---

# Reuse before you write

> Routing: a whole FEATURE (plan, interface, sizing) → **ripwire-before-you-build** · judging what you wrote
> before "done" → **ripwire-quality-bar** · unsure → **ripwire-router**.

The cheapest code is the code you don't write. Before authoring anything non-trivial — even a "quick" helper,
where duplicates are born — spend one `ripwire` call to find what already exists.

## The one call

1. **Find the building block first** — `ripwire <dir> --for="<what you're about to build>"` → ranked existing
   signatures with the quality lens (`cx`/`in`/`churn`/`tested`), so you see which candidates are safe to extend.
   If you can name the helper you suspect exists, query it verbatim (`--for="parseByteSize"`): name-exact routing
   lands it at recall@1 ~99%. Often the thing exists — compose from it.
2. **Optional, only if a style/shape question remains** — `ripwire <dir> --exemplar="<task in words>"` (or a kind:
   `--exemplar=fn|method|class|struct|iface|var`) returns the repo's best-in-class instance of that shape, chosen by
   ROLE (fan-in, low complexity, tested), not by text similarity. Copy its shape, not its text: similarity-
   retrieved "paste this similar code" measurably hurts.

Before adding a dependency: `ripwire <dir> --external-surface --legend=compact` (what the tree already depends on)
and `--uses=NAME` (its import sites). Reuse an in-tree dependency before adding a new one; to vet a candidate,
map it first with `ripwire <git-url>`.

## Stop rule

At most one `--exemplar` or `--grep` call after the `--for`. If the building block exists, call it; if your
intended body matches an existing one (`ripwire <dir> --clones --legend=compact`), call that instead. Rule of Three:
extract a shared helper on the third occurrence, and prefer a little duplication over the wrong abstraction.
When you do write, mirror the local idiom, then hand off to **ripwire-quality-bar** before you call it done.

## Reference file

`reuse-reference.md` — why role beats similarity (the measurements), `<lego>`/`<compose>` blocks, behavior-shape
search with `--grep` and narrowed `--graph-query`, and the dependency checks in full.
