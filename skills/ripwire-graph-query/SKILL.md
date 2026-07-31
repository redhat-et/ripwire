---
name: ripwire-graph-query
description: >
  Compose a call-graph question the fixed ripwire verbs don't pre-answer — "which high-complexity
  functions can reach X?", "what in src/ has 10+ callers?". A small, closed expression language
  (--graph-query) over the symbol graph: sources, kind/cx/fanin/file filters, bounded callers/callees
  closure, and/or/not joins. Use when --callers/--callees/--impact alone can't phrase the question.
  Backed by ripwire (deterministic, on PATH).
allowed-tools: Bash, Read
---

# Graph queries with ripwire

> One-hop questions have cheaper verbs — **ripwire-navigate** (`--callers`, `--callees`, `--uses`,
> `--path`, `--impact`). Reach for `--graph-query` only when you need to COMBINE conditions.
> Repo-wide architecture health (not one query) → **ripwire-layers**.

## Planning a refactor: find the cluster AND its blast radius

The refactor-planning question is always two conditions at once — "what's messy" AND "what would
touching it affect" — which is exactly what a single fixed verb can't phrase:

```
# the refactor short-list: high-complexity functions in the target area
ripwire <dir> --graph-query='and(cx(all,15),file(all,"src/"))'

# now the blast radius: everyone who transitively calls into that cluster (≤3 hops)
ripwire <dir> --graph-query='callers(and(cx(all,15),file(all,"src/")),3)'
```
(Verified on this repo's shape, not its exact numbers — `count=` drifts every commit: the first query returns
the high-cx symbols under `src/`, each `<s t= n= p=>` (kind/name/path); the second returns the transitive
caller set, typically smaller than the cluster itself because many hits are leaf-ish or call each other. Read
the header's own `count=`/`shown=` on your run, don't trust a number pasted here. Narrow `file(...)` to your
actual target directory before trusting the numbers.)

Run the first to size the cluster, the second to size the risk — a small high-cx cluster with a huge
`callers()` closure is a refactor that needs a compatibility shim or a staged rollout, not a rewrite in
place; a small cluster with a small closure is safe to just rewrite.

`ripwire <dir> --graph-query='EXPR'` evaluates a small functional expression to a deterministic,
ranked node set (capped at `--top-k`, default 200). It is a fixed, closed operator set — **not**
Datalog: no user rules, no unbounded recursion.

## The operators

| Kind | Form | Meaning |
|---|---|---|
| source | `name("X")` | symbols named X (unions same-name defs) |
| source | `all` | every INDEXED symbol |
| filter | `kind(EXPR, K)` | keep kind K: `fn` `method` `cls` `struct` `iface` `var` `sec` |
| filter | `cx(EXPR, N)` | keep cyclomatic complexity ≥ N |
| filter | `fanin(EXPR, N)` | keep in-degree (caller count) ≥ N |
| filter | `file(EXPR, "RE")` | keep symbols whose file path matches the ECMAScript regex RE |
| closure | `callers(EXPR [, D=1])` | nodes that transitively (≤ D hops) CALL anything in EXPR |
| closure | `callees(EXPR [, D=1])` | nodes transitively (≤ D hops) CALLED BY anything in EXPR |
| join | `and(A, B)` / `or(A, B)` | intersection / union |
| join | `not(A, B)` | difference (A minus B) |

## Verified examples (single-quote the whole expression for the shell)

```
# the functions that transitively (≤2 hops) call buildGraph
ripwire <dir> --graph-query='and(callers(name("buildGraph"),2),kind(all,fn))'

# high-complexity symbols in src/  (the refactor short-list)
ripwire <dir> --graph-query='and(cx(all,15),file(all,"src/"))'

# heavily-depended-on symbols (10+ callers) — the de-facto API surface
ripwire <dir> --graph-query='fanin(all,10)'

# everything main can reach within 2 hops
ripwire <dir> --graph-query='callees(name("main"),2)'

# functions NOT reachable from main's callers  (difference)
ripwire <dir> --graph-query='not(kind(all,fn),callers(name("main")))'

# a two-symbol watchlist
ripwire <dir> --graph-query='or(name("buildGraph"),name("rankGraph"))'
```

## Calibration

- Results come back **importance-ranked and capped at top-k** — `count=` vs `shown=` in the header
  tells you if the cap bit; narrow the query or raise `--top-k`.
- Closures walk the same **name-based** edges as `--callers` — dynamic dispatch / callbacks / macros
  can be missing, and `amb` edges were guessed. Verify in source when which-target matters.
- A malformed expression (unknown operator, bad `file()` regex) reports the parse error and yields
  nothing — it never half-answers.
