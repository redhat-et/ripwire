# ripwire-navigate — reference: blast-radius (read on demand; the recipe is in SKILL.md)

# Navigate with ripwire

> Nearest neighbours:
> • You DON'T know the symbol yet — orienting on a whole repo/subsystem → **ripwire-orient**.
> • You have a symptom and need to FIND the buggy code → **ripwire-find-bug**.
> • Your question needs to COMBINE conditions (cx + fanin + file + reachability) → **ripwire-graph-query**.
> • "Is this diff safe to merge" (not "is it safe to touch this symbol") → **ripwire-change-check**.

`<dir>` = the repo or subsystem. Calls are warm after the first parse. Tracing across a split
service+client checkout — pass every root, `ripwire dir1 dir2 --impact=SYM` — the merged graph carries the
cross-root evidence edges (include/import/FFI) a single-root call would never see.

## Keep the legend on the FIRST call, drop it on every call after

Every XML verb prefixes its answer with a legend defining the attributes. You need it once. After that
you are paying for prose you have already read — and the cost is worst on exactly the verbs you call
most, because the legend is a fixed size while these answers are small. Measured on ripwire's own repo:

| verb | saved by `--legend=compact` |
| --- | --- |
| `--callers=SYM` | **~70%** |
| `--uses=SYM` | **~65%** |
| `--impact=SYM` | **~50%** |
| `--affected=F1,F2` | **~67%** |
| `--for="..."` | ~4% |

**The payload is byte-identical** — the entire difference is legend prose. (Percentages, not byte counts:
an exact byte total goes stale the next time anyone edits a legend, and a stale number in a skill is worse
than no number. `ripwire --help` carries the range, and a gate holds it to it.) So:

- **Orientation** (`--for`, `--pack-task`): leave the legend on. It is ~4% there, and it is where you
  learn what `amb=`, `cx=` and `counts_floor=` mean. Reading a map whose legend you skipped is how
  confident misreadings happen.
- **Every navigation call after** (`--callers`, `--uses`, `--impact`, `--expand`): add
  `--legend=compact`. Across a seven-call session that is ~34% fewer bytes, ~2,900 tokens.

The CLI and the MCP server both default to compact now; the commands in these skills still spell the flag
(owner decision A1-2, 2026-09-12) so they read the same on a pre-0.6.2 binary, where the default was `full`.

## `--callers` is 1-hop — don't let it answer "is it safe to change X?"

`--callers=SYM` gives direct in-edges only. It under-counts on purpose (it's the *cheap* verb) — a caller
two hops away, a read/write that never calls SYM, or an `#include` that pulls it in all fall outside a
1-hop answer. Match the verb to the question:

- **"Is it safe to change/delete X?"** → `ripwire <dir> --impact=SYM --legend=compact` (transitive blast radius: everything
  that transitively reaches SYM through the call graph, not just direct callers) **+**
  `ripwire <dir> --uses=SYM --legend=compact` (the resolvable use-sites by role — `call|read|write|import|extends` — file:line; catches
  non-call references `--callers` never sees, e.g. a struct read or a header import). Run both — `--impact`
  gives depth (the call chain), `--uses` gives breadth (kinds of reference). `--callers` alone is the wrong
  tool for this question; reach for it only when you already know the change is local.
- **"Who breaks, AND which of those a test already reaches"** — `--impact`/`--callers`/`--callees` rows
  carry `tested="1"` when an indexed test transitively reaches that row (omitted, never a literal `0`, when
  none does); `--impact`'s root adds `radius_tested=`/`radius_untested=` over its transitive reach,
  `--callers`/`--callees`'s root adds `hop_tested=`/`hop_untested=` over their 1-hop count — one call
  answers both "what breaks" and "what's covered" instead of a second `--test-gate` round-trip.
- **"Who calls this, one hop"** (quick sanity check, not a safety judgment) → `--callers=SYM`.
- **"Where is this VARIABLE defined and used inside one function"** → `--slice=SYM:VAR` — per-line
  def/use rows (declaration/assignment/param vs read) inside the one resolved definition; bare
  `--slice=SYM` lists the sliceable locals first. Name-based and intra-procedural — the legend states
  the limits — so it answers "what touches this variable here" without reading the whole body.
- **"Where did this variable's VALUE come from / what does it flow into"** (still inside one function)
  → add `--slice-flow=back|fwd|both` — the transitive cross-statement data-flow slice over
  reaching-definition def-use edges: `back` = the statements whose values feed the seed variable,
  `fwd` = the statements its value reaches; each flow row carries the variable (`v=`), the BFS depth
  (`d=`) and the line it was reached from (`f=`). `--slice-depth=N` bounds the walk (default 8; a
  bound that cuts is disclosed as `flow_truncated="1"`). Stops at the function boundary by design —
  the inter-procedural half is `--callers`/`--impact`. Data dependence only — the guard deciding
  whether a def executes is never a row.
- **"I have a FILE:LINE, not a name"** (a compiler error, a diff hunk, a stack frame) →
  `ripwire <dir> --at=FILE:LINE --legend=compact` — the enclosing-definition chain at that location, outermost→innermost;
  `sym=` names the innermost. The SAME seed composes into any SYM selector as `@FILE:LINE`
  (`--callers=@src/f.cpp:120`, `--expand=@…`, `--edit-check=@…`, `--slice=@FILE:LINE:VAR`) and resolves
  to that innermost definition — skip the "what is this function called" grep entirely. A seed on a
  blank top-level line, an ambiguous path, or a line two definitions share is refused with a specific
  diagnosis, never guessed.
- **"I have a FILE:LINE and want the variable story THERE"** → `--slice=@FILE:LINE` (or `--at=FILE:LINE`
  beside any `--slice` spec — the pair composes as the slicer's seed, ARISE's own
  `(file, line[, variable])`). A seed line naming exactly ONE sliceable local pre-picks it (disclosed:
  `seed=`, `var_from="seed"`); zero or several serve the locals inventory with the candidates marked
  `seed="1"` — pick one and re-run with `:VAR`. A plain identifier beside `--at` reads as the seed's
  variable (`--slice=out --at=src/f.cpp:12`), and the seed also narrows an ambiguous SYM to the
  definition enclosing the line.
- **"Trace a FLOW: how does A reach B"** → `--path=A,B` (shortest call-path) or `--around=SYM
  [--around-depth=2]` (bounded neighborhood). Not `--for` — `--for` returns a ranked *set* of relevant
  signatures for a task, it does not trace a path between two named points.
- **"N task symbols — how do A, B and C RELATE, which intermediaries join them?"** →
  `ripwire <dir> --connect=A,B,C --legend=compact [--connect-radius=N]` — the minimal connecting subgraph: your terminals,
  the fewest joining intermediaries (with signatures), and the call edges in true caller→callee direction.
  Reach for `--connect` over `--path` in two cases: **N>2 symbols** (`--path` only ever takes SRC,DST — it
  has no notion of a third point), or **a pair `--path` calls unreachable**. The search is undirected, so it
  finds the *shared caller* joining two symbols — the most common way task symbols relate, which a directed
  `--path` can never see (`--path=A,B` says `reachable="0"` even when `main` calls both). Symbols that can't
  meet within the radius appear honestly in `<unconnected>`.
