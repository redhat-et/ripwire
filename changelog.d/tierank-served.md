### Changed — a warm `--for` answer serves the tail tie-break's PageRank instead of running the power iteration again

`--for`'s tail prints up to two extra names on a row (`tsym=`), and their order is decided by the graph's plain
uniform-teleport PageRank (`src/forpage.h` `tailTermTieRank`). Uniform teleport makes that value a function of the
**graph alone** — no part of the task reaches it — yet it was recomputed from scratch on every answer, warm runs
included. Measured on llvm-project, warm, 3 reps: **399.7 ms per `--for` answer, 15.4% of the whole verb**, for a
number the run already had. The warm snapshot persists exactly that rank beside the graph it ranks
(`src/warmsnap_graph.h` `storedDefaultRank`, written by `readGraph` on a served run and by `buildGraphRecorded` on the
run that records), so a served run now reads it. It is **read, never taken**: the default map and `--lint` still
consume the slot through `defaultRank`, and both go through one new `storedRankFor( g )` so the rule "the stored rank
belongs to this graph" is written once.

Serving a persisted number in place of a computed one is only correct if they are the same number, and this is a
determinism question, so it was measured rather than argued. An in-process probe compared the persisted array against
a fresh `rankGraph( g )` element by element on served runs (`graph=loaded`), over six corpora: jq (2,461 nodes), this
repo (47,742), django (60,574), envoy (171,803), kubernetes (293,542) and llvm-project (1,399,402). **Bit-identical on
all six** — 0 differing elements, equal iteration counts, equal convergence flags. The snapshot cannot blur them
(`src/warmsnap.h`'s `RawRow`: a float row is its computed bit pattern, read back by one `memcpy`) and the power
iteration is deterministic by the §2 contract.

The ordering is a float comparison, so a cheaper near-equal number would have been the wrong trade however small the
difference: a tie-break that resolves the other way is a wrong answer, not a slow one. Nothing here is approximate.

A run with `RIPWIRE_SNAPSHOT_STATS` set now also says `tie_rank=served|computed n=<N>` on stderr, beside the existing
`snapshot-stats` line, so the saving is observable rather than inferred. `RIPWIRE_SNAPSHOT_STATS` is already a declared
observer (`src/warmsnap.h` `kObservers`), so setting it still does not move the snapshot's options key.

Not covered: the MCP server never fills that slot — `src/mcpindex.h` builds its graph with `buildGraph` directly rather
than through the warm snapshot — so an MCP `for` request still runs the power iteration once per answer (measured: 6
`tailTermTieRank` calls over 6 `for` requests in one process). The fix there is a per-index memo under the existing
MCP-CALL-MEMO rule that `McpIndex::impure` and `::qmetrics` already follow; it is not in this change.

Gate: `test/tierankservedcheck.sh` — the cold run computes and the warm run serves, the warm answer is the cold
answer's bytes, two served answers agree, and the arm that proves it is not vacuous: the fixture's tail must carry
`tsym="restorer_scheduling,restorer_cache"`, a pair whose ORDER is PageRank's (ten callers lift `restorer_cache` over
`config_restorer`), and the same run under `RIPWIRE_NO_TAIL_SYM_TERMS=1` must carry no `tsym=` at all.
