### Added — the personalized rank's push approximation is MEASURABLE, default OFF, and cannot reach an answer (RANK-SPEED step 2)

`rankGraphTeleport` is the personalized PageRank, and at the anchors site (`src/graph.h`
`anchoredLexicalRank`, reached from `--for` through `computeLensRanking`) its teleport is seeded from the
QUERY. An agent asks a stream of *different* questions against one warm graph, so that rank is paid again on
every call and never amortises — unlike `buildGraph`, and unlike the working-set rank, whose teleport is the
git diff and which `src/mcpindex.h` `getIndex` computes once per index. This release adds an
Andersen–Chung–Lang push of that personalized part, together with the shadow arm that is the only thing
measuring it.

- **`pageRankPushPersonalized`** (`src/pagerank.h`, implemented in `src/pagerank.cpp`) estimates
  `(I − αP)⁻¹·seed` for a sparse seed, over the operator the power iteration already gathers. It walks
  `g.outOff` / `g.outTargets` / `g.outVals` **directly**: `buildGraph` fills those and `g.inEdges` from one
  flattened edge vector in one pass, accumulating `g.wOutDeg[e.from] += e.w` beside them, so the stored
  out-edge CSR is the exact transpose of what the kernel gathers and `wOutDeg` is exactly the kernel's
  divisor. No transpose is built, which at llvm scale is one power iteration and about 48 MB not spent.
  `test/pprlab.cpp` keeps a transpose only to **prove** that claim, and its header row reports whether the
  two agree edge for edge.
- **It is compiled in `src/pagerank.cpp`**, not in a header beside its caller. That file alone carries
  `-fno-fast-math` because the global profile is `-ffast-math` and PageRank reductions must not reassociate.
  The push's accumulations are compared coordinate by coordinate against that kernel's, so holding the two to
  different floating-point licences would make the comparison a measurement of the optimizer.
- **`RIPWIRE_PPR_PUSH=off|shadow|on`, default `off`** — an arming hook, not a flag: G5 says every flag is
  additive, parsed and in `--help`, and this is in none of those (the gate asserts the `--help` absence).
  Read once per process. Under `shadow` the binary computes both ranks, **serves the exact one**, and writes
  one TSV row per call to **stderr**, so stdout stays byte-identical to an unset run — an approximation that
  cannot reach the answer cannot ship a wrong one by accident. `on` is site-scoped: `anchoredLexicalRank`
  already discloses no `pr_iters=` (what leaves it is a blend, so no document ordered by it was ordered by a
  power iteration), whereas the default map does print it, and a push produces no iteration count at all.
- **The push's walk budget is DISCLOSED when it binds.** Termination is by construction — each push retires
  at least `(1−α)·ε·max(deg,1)` of a residual whose total never exceeds 1 — so the budget is a blow-up guard,
  and a row that hit it says so (`budget_hit=1`) rather than reading as a shorter walk that finished.
  `touchedNodeCount` is a floor on the push's support: a zero means no node was reached, never that none exists.
- **Gate `test/pprpushcheck.sh`, and its ratchet is that zero shadow rows is a FAILURE.** A shadow arm that
  never ran must not read as agreement. The binding criterion is tie-aware top-10 agreement: a position
  counts as a swap only when the reference's own gap there exceeds `τ = 2·tolerance/ranked`, because the
  power iteration stops at an L1 residual of 1e-6 and exact ties flip on any low-bit change. `top40_jacc` and
  `max_abs_err40` are in every row and are deliberately **not** asserted — both are satisfiable by a vector
  whose top 10 is wrong. The gate also checks the **consumer's** order, `blendMaxNorm`'s top 10, because a
  push under-estimates the tail more than the head and dividing by `max(ppr)` does not cancel that.

Nothing about a default run changes: with the hook unset the code path, the document and the byte count are
what they were. Whether the push ever serves an answer is a separate decision, on measured warm per-query
milliseconds at large-repo scale, and the default stays OFF until then.
