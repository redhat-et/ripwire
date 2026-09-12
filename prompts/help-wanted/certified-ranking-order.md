# Certified ranking order — say how far down the order is provably right

ripwire orders its default map and several ranked verbs by Personalized PageRank, computed by power
iteration until a residual drops below a tolerance. Every ranking therefore carries a small, knowable
error. Near the bottom of a shown list, neighbouring rows can sit **closer together than that error**,
so the order between them is not certified by the computation that produced it.

You are going to compute — **deterministically and conservatively** — how far down the ranking the
order is provably correct, and disclose it as an attribute on the ranked document. A working name is
`pr_order_certified_through="N"`; the final name is agreed with maintainers. It is defined in the
legend and absent when it would say nothing.

Work in a git worktree, not the main checkout. Run gates in the foreground.

---

## Why it matters

This project's third non-negotiable is honesty in output. Counts that cannot be totals are labelled
floors, caps are disclosed, and a zero means "none found". PageRank already reports on itself:
`pr_iters="N"` says how many iterations produced the order, and `pr_converged="0"` appears when the
iteration stopped at its ceiling. That contract exists because a truncated ranking once looked
identical to a converged one on every Release build (`docs/ARCHITECTURE.md`, "The convergence
disclosure contract").

**Converged is not the same as ordered.** A converged iteration still leaves every score inside an
error band. When two rows are closer than that band, the order between them is decided by the solver's
stopping point, not by the graph. An agent reads rank order as signal — which file first, which symbol
to open — and today nothing tells it where that signal ends.

This work gives the reader an honest line: **this far, the order is certain**. It is the same spirit as
floors and disclosed caps, one level finer.

---

## Background — read these, in this order

| File | What it holds |
| --- | --- |
| `src/pagerank.h` | `PageRankConfig` (the damping `alpha`, the `tolerance`, the `maxIterationCount`) and `PageRankRun`, which returns the iteration count and whether it converged — **not** the final residual |
| `src/pagerank.cpp` | `pageRankDouble`: the loop, the dangling-mass fold, the L1 residual, the stopping rule, the fixed 1024-element reduction blocks, the test-only `RIPWIRE_TEST_PR_MAXITERS` ceiling, and the contraction argument in its comments |
| `src/graph.h`, `rankGraphTeleport` | The caller: name-quality `biasPrior` on the teleport, renormalization, the `alpha` it actually passes, and the narrowing of the result to `float` |
| `src/graph.h`, `buildGraph` | Fills the in-edge CSR values and `wOutDeg[e.from] += e.w` from the same edge list |
| `src/infra/sortutil.h` | `lessByScoreDescId` / `radixSortByScoreDescId`: score descending, id ascending — on the **float** vector |
| `src/serialize.h` | The default map: the rank sort, the top-K `keep`, symbols bucketed by file in first-seen rank order, `--stable` (path order, `k=` omitted), important-last reversal, and `k="{:.4f}"` |
| `src/prconverge.h` | The **one** spelling of the convergence disclosure: `RankDisclosure`, the `DiscloseAs` forms, the legend clause, and why it stays one renderer |
| `docs/ARCHITECTURE.md` | "The convergence disclosure contract": the absence rules, and which documents carry `pr_iters` — not a lexical query score, not HITS; `--rank-by=rrf` does, because PageRank is one of its fused vectors |
| `test/prconvergecheck.sh` | Arms A to I: presence, truncation in plain and Release builds, the hook that can only lower, absence, every surface and its MCP twin, dialect parity, legend |
| `test/legendcoveragecheck.sh` | Every attribute a first screen shows must be defined there |
| `test/verify_pagerank.cpp` | Small hand-built fixtures, including three tied callers of one dangling hub |
| `docs/METHODOLOGY.md` §9 | Principle 4: honesty lives in attributes, not prose |

---

## The arithmetic — derive it from the code, then check this sketch against it

This is the shape of the bound. Every step is a claim about the code that you must confirm by
reading it; if the code disagrees, the code wins and the derivation changes.

**What the loop returns.** Each iteration computes `nextRank`, folds the L1 residual
`r = ‖x_{k+1} − x_k‖₁` in canonical block order, swaps, and stops when `r < tolerance`. The vector
copied out is the **newer** iterate, `x_{k+1}`.

**Why it is a contraction.** Write the update as `T(x) = α·P̃x + (α·d(x) + 1 − α)·p`, where `P̃`
holds the in-edge weights divided by `wOutDeg`, `d(x)` is the mass on dangling nodes, and `p` is the
teleport. Then `T(x) − T(y) = α·M(x − y)`, where `M` adds the dangling redistribution to `P̃`. If every
non-dangling column of `P̃` sums to exactly 1, `M` is non-negative and column-stochastic, so
`‖T(x) − T(y)‖₁ ≤ α·‖x − y‖₁` for any `x` and `y`. `src/pagerank.cpp` states the same argument.

**The a posteriori bound.** From the contraction, `‖x_{k+1} − x*‖₁ ≤ α/(1 − α) · r`. The loop stops
with `r < τ`, so the L1 error of the returned vector against the fixed point `x*` is below
`B = α·τ/(1 − α)`. Using the actual final residual instead of `τ` is tighter, but `PageRankRun` does
not carry it today.

**The `α` the loop sees is not 0.85.** `PageRankConfig` defaults to the double `0.85`, but
`rankGraphTeleport` takes a `float alpha = 0.85f` and passes `double( alpha )`. That is
0.850000023841857910…, so `α/(1 − α)` is about 5.6666677, and at `τ = 1e-6`, `B` is about 5.667e-6.
Compute it from the value the loop actually receives.

**From an L1 bound to an order.** For rows `i` above `j`, with computed scores `sᵢ > sⱼ`, the true
order agrees if `sᵢ − sⱼ > |eᵢ| + |eⱼ|`. Since `|eᵢ| + |eⱼ| ≤ ‖e‖₁ < B`, an adjacent gap above `B`
certifies that pair. The order is certified **through N** when every adjacent gap among the first
`N + 1` rows exceeds the bound. The gap between rows `N` and `N + 1` is what guarantees nothing below
row `N` climbs into the prefix. An exact tie is never certified.

**What that bound does not cover.** Each of these must be bounded rigorously, or padded
conservatively, and disclosed:

1. **Floating-point roundoff**, in every iteration and in the residual sum itself.
2. **Column sums that are not exactly 1 in floating point.** A column summing above 1 raises the
   contraction factor above `α`. `buildGraph` accumulates `wOutDeg` in double from the same float edge
   values the CSR stores; check how close to 1 that makes each column, then bound it.
3. **The narrowing to `float` before the sort.** The sort, and every tie it breaks by id, happens on
   floats. A gap certified on doubles the sort never saw can claim an order the output does not have.
4. **What "the true order" means.** The edge weights are floats as the graph builds them. The only
   order this code can certify is the fixed point of **the operator it builds**. Say so in the legend.

---

## Measure before you design the attribute

Instrument a scratch build to compute the adjacent gaps against the bound, and report the distribution
of `N` against the rows shown and the top-K kept:

- this repository's default map;
- at least two external corpora of clearly different sizes;
- one large rung. #127 used llvm-project (182,555 files) as its scale rung; small corpora cannot show
  what a million-node rank vector does to adjacent gaps.

`test/prconvergecheck.sh` records 28–52 iterations across four real corpora, so every real run
converges. The open question is how many rows the convergence certifies. If `N` almost always covers
the shown list, the attribute is mostly absent on the common path. If `N` is small on large corpora,
**that is the finding**, and it goes in the PR before any design decision rests on it.

---

## Design space and constraints

- **Return the residual.** `PageRankRun` gains the final residual. Use a structured return, never an
  out-parameter (CONTRIBUTING.md §3). No allocation inside the power-iteration loop (guardrail G2's
  scoped rule). The certification pass runs after the sort, over the rows that matter.
- **Deterministic.** Gaps and bounds come from values that are already deterministic, folded in
  canonical order. The PageRank translation unit is compiled without floating-point reassociation
  (non-negotiable 2), so do not move the arithmetic somewhere that is not.
- **Conservative.** Every approximation rounds toward *less* certified. A certified claim that is wrong
  is worse than no attribute.
- **Name and absence, to agree before code.**
  - Absent wherever `pr_iters` is absent. A document not ordered by PageRank must never borrow another
    ranking's numbers; `RankDisclosure`'s `isPageRank` rule already says so.
  - Then choose one convention. **(a)** Absent when the whole shown list is certified: absence means
    fine, zero bytes on the common path, like `pr_converged`. **(b)** Present on every PageRank-ordered
    document.
  - Either way, absence must never be readable as "certified" when certification was not computed.
    Your measurement decides which is honest and cheap.
- **Rank order, not emission order.** The default map buckets rows by file, `--stable` emits path
  order, and important-last reverses. Define `N` over the rank order that selected the rows, and say so
  in the legend.
- **`--rank-by=rrf` fuses rank positions.** PageRank's bound alone does not certify a fused order.
  Stay absent there, or derive a separate argument and gate it.
- **Truncated runs** (`pr_converged="0"`). The a posteriori bound still holds with the actual residual.
  Decide whether to certify there, which is honest, or stay absent, which is simpler, and say which.
- **One renderer.** The spelling goes into `src/prconverge.h`, as fields on `RankDisclosure` and the
  forms it already has, never a sibling function. That header records why: a cluster of small
  PageRank-vocabulary symbols pushed `pageRankDouble` from rank 1 to rank 6 for its own query.
- **Token density (G4).** The default map is the most-emitted document. The legend clause uses the
  compact `name=value(qualifier)` dialect, with no `--` digraph and no `<` inside the comment.
- **Every surface, every dialect.** XML and JSON carry the same keyset (arm F), and MCP twins agree
  with their CLI sibling (arm E).
- **Quality first.** Never lower `τ`, raise the iteration ceiling, or change `α` to make `N` bigger.
  Those constants move every ranking in the tool; changing them is a separate, pre-registered round.
- **Gate before code.** Write the gate against the current binary and watch it fail.

---

## Fixtures with known near-ties

Small graphs have fixed points you can compute **exactly**: rational arithmetic in a Python helper
inside the gate, not in C++. That gives an external oracle for "a certified pair agrees with the true
order".

- **An exact tie.** Structurally symmetric nodes, like `test/verify_pagerank.cpp`'s three callers of one
  hub. The id tie-break decides; certification must stop there.
- **A near-tie.** Built so the exact fixed-point gap is positive but below the bound. Never certified.
- **A clear separation**, far above the bound. Certified.
- **The all-separated control.** Every adjacent gap exceeds the bound, so `N` equals the rows shown, and
  your absence convention takes effect.
- **A truncated run**, armed with `RIPWIRE_TEST_PR_MAXITERS`, exercising whichever decision you made.
- **Determinism:** two runs byte-identical, warm equal to cold, and a Release binary (the
  `test/prconvergecheck.sh` B2 pattern), since the disclosure must survive `NDEBUG`.

---

## Acceptance criteria

1. **The derivation is written down** in `docs/ARCHITECTURE.md`, next to the convergence disclosure
   contract: the bound, each assumption checked against the code, and the treatment of each uncovered
   error source.
2. **The measurement report comes first:** the distribution of `N` on real corpora including one large
   rung, committed before the attribute's absence convention is chosen.
3. **`pageRankDouble` returns its final residual.** The loop gains no allocation, and every document is
   byte-identical to before apart from the new attribute.
4. **The attribute is on every PageRank-ordered surface** `test/prconvergecheck.sh` enumerates, in XML
   and JSON and on the MCP twins. It is absent where `pr_iters` is absent, defined in the legend, and
   `test/legendcoveragecheck.sh` is green.
5. **A new gate, red first**, over the near-tie fixtures with the exact oracle:
   - every certified pair agrees with the exact fixed point;
   - the certified prefix never exceeds the true agreeing prefix;
   - exact ties are never certified;
   - determinism, warm equal to cold, and the Release arm.
6. **Goldens and captures regenerated as their own commit,** diff reviewed by eye (CONTRIBUTING.md §6).
7. **Gates green in the foreground:** the new gate, `test/prconvergecheck.sh`,
   `test/legendcoveragecheck.sh`, `test/mcpmanifestcheck.sh`, the two-run determinism diff, and
   `xmllint --noout` on the map.

---

## Known traps

1. **`α` is `double( 0.85f )`,** not 0.85. Use the value the loop receives.
2. **The residual is not returned today.** `τ` gives a valid bound; the real residual gives a tighter one.
3. **The sort sees floats.** Ties and order are decided after narrowing. Certify what the output
   actually contains.
4. **Emission order is not rank order.** File bucketing, `--stable` and important-last all reorder.
   Define `N` on the rank order.
5. **`k=` prints four decimals.** A reader cannot re-derive certification from it, which is why the
   attribute exists. A gate that tries to derive it from `k=` is checking the rounding, not the claim.
6. **Absence rules are load-bearing.** One absent attribute meaning two different things is exactly the
   failure `src/prconverge.h` was written to prevent.
7. **Absence arms pass on a binary with no attribute.** `test/prconvergecheck.sh` says so in its own
   header: the presence arms carry the ratchet. Lead your gate with a presence arm.
8. **The MCP manifest has about 23 bytes of headroom.** On `main` at `d752d953`, `tools/list` measures
   42,177 B against `test/mcpmanifestcheck.sh`'s 42,200 B ceiling. If a tool description must mention
   the attribute, you will hit it. Read the gate's history before proposing a new ceiling, and never cut
   another tool's routing text to fit.
9. **Changing the solver to flatter `N`** — a lower `τ`, a higher ceiling, a different `α` — is out of
   scope, and it changes every ranking the tool emits.
10. **This is not the "stop when top-k separates" idea.** Some graph systems stop iterating once the
    top-k are separated. That is a different design, with different consequences for determinism and
    for every lower row. Take the intuition if it helps; derive this one from first principles.

---

## What the PR description should contain

- **The derivation**, with each assumption and the line of code that makes it true.
- **The measurement:** the distribution of `N` against rows shown and top-K on every corpus, with sizes.
- **The name and absence convention**, and why the measurement chose it.
- **The red gate run**, and the exact-oracle fixtures it uses.
- **Byte evidence:** the default map identical to before apart from the attribute, the legend's byte
  cost, and the MCP manifest before and after.
- **What stays uncertified:** rrf, truncated runs if you chose absence, and any error source you padded
  rather than bounded.

---

**Write the plan — the derivation to check, the measurement, the naming and absence proposal, the
fixtures and their exact oracle, and the surfaces the attribute lands on — then STOP for my go-ahead.**
