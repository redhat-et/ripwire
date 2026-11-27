---
name: ripwire-reuse-first
description: >
  About to write ONE symbol (even a 'quick' one-liner) or add a dependency: reuse before you reinvent.
  Finds the building block that already exists, the house pattern to imitate, the duplicate you'd
  recreate, a vendored dependency. An interface or whole feature → before-you-build. One --exemplar or
  --grep call at most.
allowed-tools: Bash, Read
---

# Reuse before you write

> Routing: a whole FEATURE (plan, interface, sizing) → **ripwire-before-you-build** · judging what you wrote before
> "done" → **ripwire-quality-bar**.

Duplicates are born on "quick" helpers. Spend one call to find what already exists.

1. **The building block first** — `ripwire <dir> --for="<what you're about to build>"`: ranked existing signatures with
   the quality lens (`cx`/`in`/`churn`/`tested`). Suspect a named helper exists? Query it verbatim
   (`--for="parseByteSize"`): name-exact routing lands it at recall@1 ~99%. Often it exists — compose from it.
2. **Optional, only if a style/shape question remains** — `ripwire <dir> --exemplar="<task in words>"` (or a kind:
   `--exemplar=fn|method|class|struct|iface|var`): the repo's best-in-class instance, chosen by ROLE (fan-in, low
   complexity, tested), not text similarity. Copy its shape, not its text.

Adding a dependency? `ripwire <dir> --external-surface --legend=compact` (what the tree already depends on) and `--uses=NAME` (its import
sites); reuse an in-tree one first; vet a candidate by mapping it, `ripwire <git-url>`.

## Stop rule

At most one `--exemplar` or `--grep` call after the `--for`. If the block exists, call it; if your body matches an
existing one (`ripwire <dir> --clones --legend=compact`), call that. Extract a shared helper on the third occurrence, not before. Mirror
the local idiom, then **ripwire-quality-bar** before done.

## Reference file

`reuse-reference.md` — why role beats similarity (the measurements), `<lego>`/`<compose>` blocks, behavior-shape search
with `--grep` and narrowed `--graph-query`, the dependency checks in full.
