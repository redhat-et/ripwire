# r6 pre-registration — structural expansion from a confirmed top-ranked file

**Registered 2026-08-06, BEFORE the candidate code ran on any benchmark instance.** Freezes
hypothesis, mechanism, grid, metrics, and decision tree; anything not written here is post-hoc.
Read `FEASIBILITY.md` in this directory first — it is the probe that justified registering at all.

## The four rejected rounds, and the gap they leave

| round | seed | edge | verdict |
| --- | --- | --- | --- |
| `r1_anchorhop` | mention anchors | call/import | +0.00pp |
| `r1cpp_anchorhop` | mention anchors | call/import | +0.00pp |
| `r4_siblift` | top-ranked files | **same directory** | rejected at calibration |
| `r5_pooling` | *(no seed — re-summarised every file)* | *(none)* | +0.00pp held-out |

The gap is the diagonal. **siblift had the right seed and the wrong edge; anchorhop had the right
edge and the wrong seed.** r6 is the untried combination: seed from the files the ranker *already put
in the top 10*, walk *import/reference* edges.

r5's verdict also narrowed the diagnosis in a way this round must respect:

> all four re-weight evidence the query already produced, and for the sibling files that define this
> stratum the query produced NO evidence to re-weight.

r6 is the first candidate that **introduces evidence the query did not supply** — the edge comes from
the code, not from the issue text. That is the whole reason to expect a different outcome, and if it
fails the stratum should be considered closed to ranking-side mechanisms.

## Hypothesis

**H1.** Lifting the import/reference neighbours of the top-ranked files raises strict file@10 on the
multi-file stratum.
**H0.** It does not, or it pays for the gain out of the single-file stratum.

The mechanism behind the target: a sibling is a file that changed *because* the primary changed. The
primary carries the issue's vocabulary; the sibling carries the consequence. `FEASIBILITY.md` found
the required edge present for **28 of 40** gold files (70%) under a permissive test.

## Mechanism

For each of the top `S` ranked files, collect files connected by a **resolved import/reference edge**
in ripwire's own graph (not a text match — the probe's text test was deliberately permissive and
overcounts). Place up to `N` of them per seed on the existing slot ladder
(`kMentionTopGapStep`, forced strictly below #1, `max()` placement so it only ever raises).

Anti-noise guards, both inherited from the one part of siblift that was *not* implicated in its
failure: a neighbour with no positive lexical score is never lifted, and #1 is never displaced.

`RIPWIRE_EXPAND="<S>,<N>"`, routed path only, inert by default — with the env unset the binary must
be byte-identical, asserted by the golden and determinism gates.

## Grid (frozen)

S ∈ {2, 3, 5} × N ∈ {1, 2, 3}. Nine live cells, plus `S=0` as the off/identity control.

## Metrics (frozen, in decision order)

1. **multi-file strict file@10** — registered primary.
2. **single-file strict file@10** — the guard.
3. overall strict@10, any@10, wall — reported, not decisive.

## Decision tree (frozen)

Calibration on the **train** split only. The held-out 60 is the published 58.3%.

- **Advance** iff some cell flips **≥ 3 additional multi-file instances** to strict@10 on train, AND
  loses **0** single-file instances. Ties broken toward smaller S, then smaller N.
- **Reject** otherwise; write the verdict, default stays off, keep the scaffolding.
- If a cell advances, **one** held-out run is spent on it and reported whatever it says.
- The identity control must reproduce baseline **exactly**, or no cell in that run may be read.

**The bar is stated in INSTANCES, not percentage points, and this is the direct lesson of r5.** That
round set a "≥ +2.00pp multi-file" bar on a 43-instance stratum where one instance *is* 2.33pp — so
the bar sat below single-instance granularity and meant nothing stronger than "flip at least one". A
single train flip duly cleared it, advanced, and returned +0.00pp on held-out. Three instances is
above the noise floor that produced that false positive.

## What would make this round worthless

Reporting any number from a cell chosen after seeing held-out results; quoting a train number as if it
were held-out; moving the ≥3-instance bar after the grid has run; or counting a text-match edge as a
resolved graph edge because the resolved one was absent.
