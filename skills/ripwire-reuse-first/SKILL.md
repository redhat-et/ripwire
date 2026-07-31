---
name: ripwire-reuse-first
description: >
  About to write ONE symbol — a single function, class, helper, or utility — reuse before you reinvent. Use
  the moment you're about to author any named thing (even a "quick" one-liner: duplicates are born on tasks
  that feel too small to tool up for), and before adding a dependency. ripwire finds the existing building
  block, the repo's best-in-class exemplar to imitate (by ROLE, not text similarity), the duplicate you are
  about to recreate, and whether the dependency is already in the tree, so you compose instead of reinvent.
  The least code is the least complexity, the fewest bugs, the smallest review, and the most cache-friendly
  diff. For a whole multi-symbol FEATURE (plan/interface/sizing) → ripwire-before-you-build. Backed by
  ripwire (deterministic, on PATH).
allowed-tools: Bash, Read
---

# Reuse before you write

> Routing — pick the right door:
> • Starting a whole FEATURE (multi-symbol, needs a plan / interface / sizing) → **ripwire-before-you-build**.
> • The cross-cutting *map-before-you-read* token discipline for any read → **ripwire-efficient**.
> • Judging whether what you wrote got better or worse before "done" → **ripwire-quality-bar**.
> • Not sure which skill? → **ripwire-router**.

The cheapest, simplest, most readable code is the code you don't write. Before authoring anything
non-trivial, spend one `ripwire` call (on PATH) to find what already exists.

## Retrieve by ROLE, never by raw similarity
This is the load-bearing rule, not a style preference: **similarity-retrieved "here's similar code, paste
it" measurably HURTS** — up to **−15% Pass@1** (arXiv:2503.20589, `RESEARCH_agentQuality2026.md §2d`). What
helps is API/type-signature context (+17-20%) and dependency-graph-structured retrieval (+6 EM; enabled 5/6
multi-file edits vs 0/6 without a graph). ripwire's shape — signatures + call-graph + role-ranked exemplars —
is the validated retrieval shape; "find me a similar-looking snippet" is the anti-pattern to avoid, even
though it's the tempting first instinct.

## Before you write a function / class / util
1. **Get the exemplar to imitate** — `ripwire <dir> --exemplar=fn|method|class|struct|iface|var` (a kind) or
   `--exemplar="<task in words>"` (the top match's kind is inferred) → the repo's single best-in-class
   instance of that shape: highest fan-in, lowest cognitive complexity, `tested=1` where possible — selected
   by ROLE, **not** text similarity. It returns the full body under `<bodies>`. **Copy its shape (structure,
   error handling, naming), not its text** — it's a model to imitate, not a template to clone verbatim.
2. **Find the building block** — `ripwire <dir> --for="<what you're about to build>"` → ranked existing
   signatures (plus, when the code has them, the `<lego>` / `<compose>` HAS-A blocks — what a class already
   owns). If you can name the helper you suspect exists, query it verbatim (`--for="parseByteSize"`) — `--for`
   auto-routes to name-exact retrieval and lands it at recall@1 ~99%. It also carries
   the quality lens (`cx`/`ccx`/`in`/`churn`/`amp`/`tested`) so you see which
   candidates are safe to extend. Often the thing exists — compose from it.
3. **Find candidates by behavior/shape** — `ripwire <dir> --grep="<a word from the behavior>"`, or a NARROWED
   graph query: `--graph-query='and(file(all,"<area>"),kind(all,fn))'`. (Bare `kind(all,fn)` is ranked by
   importance + capped at `--top-k`, so it's safe — but narrowing by `file()`/`name()`/`callers()` finds the
   *relevant* building block, not just the globally-important one.) → implementations to reuse or extend.
4. **Don't duplicate** — `ripwire <dir> --clones` → if your intended body matches an existing one, call it
   instead. **Rule of Three:** extract a shared helper on the *third* occurrence, not the second — and prefer
   a little duplication over the *wrong* abstraction (a helper you bend with boolean flags is worse than two
   honest copies).

## Before you add a dependency
5. **Is it already here?** — `ripwire <dir> --external-surface` (what the tree already depends on) and
   `--uses=NAME` (the import role). Reuse an in-tree dependency before adding a new one: a new dep is build
   weight, supply-chain surface, and one more thing every reader must learn — it has to earn its place.
6. **Before adding/vendoring a NEW dependency, map the candidate repo first** — `ripwire <git-url>` (https://
   or git@; shallow-clones to a temp cache dir, then maps it like any local tree — `--refetch` forces a fresh
   clone instead of reusing the cached one). Run `--report`/`--hotspots`/`--deps` on it before you commit to
   the dependency: is it actually small and well-factored, or a god-file waiting to become your problem?

## When you do write
- **Match the local idiom** — `ripwire <dir> --for="<the area>"` shows the surrounding naming, layout, and
  error-handling style. Mirror it so your diff reads like the file, not like a graft (cache-friendly for the
  reader and for KV-cache reuse).
- **Less code wins on every metric at once:** lower complexity, fewer call edges, smaller blast radius, less
  to test, less to read. When in doubt, delete a parameter before adding one.

Then hand off to **`ripwire-quality-bar`** before you call it done.
