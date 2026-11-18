---
name: ripwire-graph-query
description: >
  A call-graph question the fixed verbs can't phrase — 'which high-complexity functions can reach X?',
  'what has 10+ callers in src/?', 'untested symbols within one hop of main'. --graph-query: a small
  closed expression language — kind, complexity, fan-in, tested filters; a file or cluster; bounded
  hops; and/or/not.
allowed-tools: Bash, Read
---

# Graph queries with ripwire

> One-hop questions have cheaper verbs — **ripwire-navigate** (`--callers`, `--callees`, `--uses`, `--path`,
> `--impact`). Reach for `--graph-query` only when you need to COMBINE conditions. Repo-wide architecture health
> → **ripwire-layers**.

## The one call

`ripwire <dir> --graph-query='EXPR' --legend=compact` — a small closed expression language (not Datalog: no user
rules, no unbounded recursion) evaluated to a deterministic, importance-ranked node set capped at `--top-k`
(default 200). Single-quote the whole expression for the shell.

| Kind | Form | Meaning |
|---|---|---|
| source | `name("X")` · `all` | symbols named X · every indexed symbol |
| filter | `kind(EXPR, K)` | keep kind K: `fn` `method` `cls` `struct` `iface` `var` `sec` |
| filter | `cx(EXPR, N)` · `fanin(EXPR, N)` | complexity ≥ N · caller count ≥ N |
| filter | `file(EXPR, "RE")` | file path matches the ECMAScript regex RE |
| closure | `callers(EXPR [, D=1])` · `callees(EXPR [, D=1])` | nodes that reach / are reached within D hops |
| join | `and(A, B)` · `or(A, B)` · `not(A, B)` | intersection · union · A minus B |

```
# the refactor short-list, then its blast radius (≤3 hops)
ripwire <dir> --graph-query='and(cx(all,15),file(all,"src/"))' --legend=compact
ripwire <dir> --graph-query='callers(and(cx(all,15),file(all,"src/")),3)' --legend=compact
# the de-facto API surface: 10+ callers
ripwire <dir> --graph-query='fanin(all,10)' --legend=compact
```

## Stop rule and trust

One expression answers one question; narrow `file(...)` to your target before trusting the numbers. `count=` vs
`shown=` in the header says whether the cap bit. Closures walk name-based edges: dynamic dispatch, callbacks and
macros can be missing. A malformed expression reports the parse error and yields nothing — never half an answer.

## Reference file

`graph-query-reference.md` — refactor planning with cluster + blast radius, the full operator table, every
verified example, calibration.
