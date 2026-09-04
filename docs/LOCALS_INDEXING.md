# DESIGN — local-variable indexing, and the naming predicates gated on it (2026-08-06)

Origin: `naminglens.h` shipped with a stated invariant — *an un-indexed loop local can never be
flagged* — because ripwire indexes definitions, not their interiors. That invariant is honest, and it
is also a gap: the names most likely to be bad are the ones inside a function nobody can read.

This document is the design record for closing that gap in three phases, the thresholds that are
**measured rather than invented**, and the hard blocker that keeps Phase 2 opt-in. Phases 1 and 2
ship; Phase 3 does not. Code: `src/model.h` (the `locals` field), `src/ingest_metrics.h` (the walk),
`src/naminglens.h` (the predicates), `src/cli.h` (`--naming-locals`). Gates:
`test/localscountcheck.sh`, `test/naminglocalscheck.sh`.

## 1. Phase 1 — `locals`, threaded through the existing walk

One `std::uint32_t locals` field on `Symbol`, populated by extending the existing fused-DFS
complexity walk — the same one that already computes `cx`/`ccx`/`maxNest`. Zero new tree-sitter
queries, zero new indexed symbols, zero new allocation-heavy passes. It requires a `kParserVer`
cache-format bump in the same commit, and a `RuleSink`-style floor marker (`locals_floor="1"`) rather
than prose-only disclosure, because the count is a floor and saying so in prose is not the contract
this project keeps.

`locals=` is **absent** — never `"0"` — for any language Phase 1 does not cover. A zero would claim a
measurement that was never taken.

**Gate — `test/localscountcheck.sh`.** Three fixture functions with distinct hand-counted local
counts, so a single-constant-stub implementation cannot pass all three; a floor-boundary fixture
asserting the known declarator shapes (if-init, switch/case, catch-clause, structured bindings,
lambda init-captures) are NOT counted; a language-omission fixture proving `locals=`/`locals_floor=`
are absent rather than zero; and a stale-cache fixture proving the version guard rejects a pre-bump
cache blob instead of silently misreading it.

## 2. Phase 2 — naming predicates on local names

**This phase deliberately breaks `naminglens.h`'s stated invariant.** That is the point of it, and it
is said out loud here rather than quietly relaxed in the code.

A second, name-capturing walk runs ONLY for a function that already clears an existing
size/complexity gate — `loc>80 OR maxNest>4 OR ccx>=15`, all three reused unchanged from the shipped
`large-function`/`deep-nesting` rules — AND has `locals>=8`. Captured locals are lightweight
non-owning `LocalNameFact{ string_view name; line; declDepth }` records, never promoted to
`Symbol`/`NodeId`/the graph.

`checkNameShape` splits into a shared `checkNameShapeCore` (existing `Symbol`-based callers
unchanged) plus a new `checkLocalNameShape` entry point. `naming-short` additionally requires the
local's own `declDepth>=2` — nested, not the function's outermost block. That per-local gate sits on
top of the per-function one specifically because gating at function level alone reproduces the
withdrawn `naming-body-mismatch` rule's failure shape: plausible, and wrong on the axis that matters.

Explicitly out of scope: `naming-predicate`/`naming-setter` (need a known return type, not
transferable to a local) and `naming-confusable`/`naming-uninformative` (corpus-scale — folding
locals in risks exactly the blow-up this design avoids).

**MVP scope is C/C++ (ObjC/ObjC++ fast-follow), not all 14 languages.** C-family has the highest
locals/function ratio in the survey (5–15 per function, against roughly 3:1 for Python and 0.2–0.8
for Go/Rust), and the `large-function`/`deep-nesting` gate Phase 2 extends is *already* C-family-only
— so this extends shipped code instead of building a new cross-language subsystem. Go and Swift need
a Swift-style post-capture filter for a different reason (query-layer scope conflation) that this
walk-scoped design sidesteps; they are real second-wave candidates, not intrinsically harder.

### 2.1 The hard blocker on default-enable

`--naming-locals` is opt-in, and stays opt-in, for a reason that is not caution-in-general.

`renamemine.h`'s calibration join requires the new name to be `naminglens::eligibleSymbol` — indexed
at HEAD. Locals are never indexed, by Phase 1's own design, so `test/namingcalibrationcheck.sh`
**cannot calibrate a local-scoped rule as it stands.** Required before any default-enable: a
hand-curated fixture corpus, AND a manual audit of flagged output on a real corpus (ripwire's own
`src/`) checking for skew toward idiomatic-but-short names — `i`/`j`/`k`/`buf`/`tmp`/`err`.

That requirement is cited against this exact lens's own history, not invented as ceremony:
`naming-body-mismatch` passed its fixture gate, shipped, and was caught 4.5 hours later by a manual
audit of real output — 159 of 217 findings dominated by the tree's best-named functions. The
calibration harness built afterward produced zero usable signal (13 pairs, no scorable firings) on
this same repository. **Fixtures alone are demonstrated-insufficient on this lens specifically**, not
hypothetically insufficient.

## 3. Phase 3 — the composite finding (NOT SHIPPED)

Specified, deliberately unbuilt: a `--lint` tag (`large-function-bad-locals`), not a `quality.h`
`Regression` — a standing fact about the current tree has no `was`/`now` shape. It would fire once
per gated function when the count of Phase-2-flagged locals clears a threshold `K` (open question 5).
Both `N` (flagged count) and `M` (total locals) would carry the same floor caveat: both come from the
same undercounting walk, and neither is exactly known.

## 4. Open questions — unmeasured thresholds, each needing a call before it moves

These are referenced by number from the source comments and gates that depend on them.

1. **`locals>=8`** — invented, not measured. Ship Phase 1 alone first, look at the real distribution,
   then set this floor. *(Later measured on ripwire's own `src/`: median `locals`=9 among 377 gated
   functions — the shipped floor is that measurement, not the guess.)*
2. ~~Message-text fork~~ — resolved; the `checkNameShapeCore` extraction gives locals accurate text.
3. **Tag namespace** — reuse the existing tags with a `scope="local"` qualifier (recommended) versus
   new `-local`-suffixed tags, which would extend the position-pinned `tallies[9]`. Reuse is what
   shipped; `test/naminglocalscheck.sh`'s TAG-REUSE arm pins it.
4. **Validation path and timeline before default-enable** — the fixture+audit combination is
   required; the `renamemine.h` extension is a condition for staying enabled past a trial period.
   Exact trial length and audit sign-off owner is a real scope call, not a default to pick silently.
5. **Composite `K`** — the same measure-don't-guess problem as (1).
6. Whether Phase 3 eventually feeds `--quality-delta` (regression view) or stays `--lint`-only
   (standing-facts view — recommended for MVP).
7. *(Moot — branch/merge sequencing, resolved when `naminglens.h`/`renamemine.h` landed.)*
8. **How far `declDepth>=2` goes toward closing the idiomatic-short-name false-positive class.** It
   explicitly does not fully solve it — a deeply-nested loop counter still clears the gate. Resolve
   via the required real-corpus audit, not by inventing a further threshold here.
