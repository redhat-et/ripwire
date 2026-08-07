# r5 pre-registration — file-level evidence pooling (the multi-file stratum retry)

**Registered 2026-08-06, BEFORE the candidate code ran on any benchmark instance.** Freezes
hypothesis, mechanism, grid, metrics, and decision tree; anything not written here is post-hoc.

## Prior art this must answer (why this is not siblift again)

Three candidates have now been rejected at **+0.00pp** held-out or train strict@10 — `r1_anchorhop/`,
`r1cpp_anchorhop/`, and `r4_siblift/`. All three shared one shape: **pick a neighbour, then move it.**
The anchor-hop pair added score mass along call/import edges from mention anchors; siblift lifted the
highest-scoring same-directory sibling of each top file. r4's own post-mortem names the failure
precisely:

> sibling CHOICE by highest best-symbol score is the weak link. Real directories hold many
> query-relevant siblings and the top-scoring one is rarely the gold one — **score-adjacent is not
> gold-adjacent**. When the chooser guesses right the gold was already close; when wrong, wider
> settings displace legitimate rows.

This candidate **selects no neighbour at all.** There is no chooser to be wrong. It changes how a
file's existing evidence is *summarised*, and every file in the corpus is re-summarised by the same
rule. That is the mechanism r4's verdict explicitly nominated as the surviving hypothesis:

> what survives for the next pre-registration: … **FILE-LEVEL EVIDENCE POOLING** — rank files by
> pooled symbol evidence rather than lifting guessed neighbors — as the shaped hypothesis, with
> multi-file-primary as the registered metric.

## Hypothesis

Today a file's rank is set by its **single best symbol** (`fileBest = max` over the file's symbols,
and in the emitted candidate rows a file first appears at its strongest symbol). That is a max-pool,
and a max-pool cannot distinguish *one strong hit* from *five moderate hits*.

Multi-file gold sets are predicted to be the second kind. When a change spans
`django/forms/{fields,forms,renderers}.py` or `src/transformers/{modeling_utils,trainer,training_args}.py`,
each gold file is expected to carry **several** moderately-relevant symbols rather than one dominant
one — while the files that currently outrank them carry one sharp lexical hit and nothing else.

**H1.** Ranking files by pooled symbol evidence instead of max symbol evidence raises strict file@10
on the **multi-file** stratum.
**H0.** It does not, or it pays for the multi-file gain out of the single-file stratum.

The single-file stratum currently sits at 90.6% on the held-out slice and is the thing most at risk:
a pooled score rewards files with many symbols, and a large file with many mediocre symbols could
displace a small file with one correct one. The grid and the decision rule below are built around
that risk, not around the upside.

## Mechanism

`poolScore(f) = Σ of the top-K symbol scores in f`, K fixed per cell, symbols ordered by existing
`lensRank`. Files are then placed on the **same slot ladder the mention boost and siblift already
use** (`kMentionTopGapStep`, forced placement strictly below the current top), ordered by
`poolScore`. Rank #1 is never displaced.

Three deliberate constraints:

- **Top-K, not all.** An unbounded sum makes file size the ranking signal — a 4,000-line module with
  200 weak symbols would outrank a 40-line one with two correct symbols. K caps the volume a file can
  accumulate.
- **Positive evidence only.** A symbol with a non-positive score contributes nothing; a file with no
  positive symbol is never placed. Same anti-noise guard siblift used, kept because it is the one part
  of siblift that was not implicated in its failure.
- **Routed path only, env-gated, inert by default.** `RIPWIRE_POOL="<K>,<blend×100>"`. With the env
  unset the binary is byte-identical, which `test/determinismcheck` and the golden-output gate both
  already assert.

`blend` interpolates between today's max-pool and the new sum-pool:
`effective(f) = (1 − blend)·max(f) + blend·poolScore_normalised(f)`. `blend=0` must reproduce the
baseline exactly — that is cell (K,0) and it is the harness's own control.

## Grid (frozen)

K ∈ {3, 5, 10} × blend ∈ {0.25, 0.50, 1.00}, plus `blend=0` as the identity control. Nine live cells.

## Metrics (frozen, in decision order)

1. **multi-file strict file@10** — the registered primary, per r4's verdict.
2. **single-file strict file@10** — the guard.
3. overall strict file@10, any@10, wall — reported, not decisive.

## Decision tree (frozen)

Calibration runs on the **train** split only. The held-out 60 is not touched during calibration —
those instances are the published number and tuning against them would make the 58.3% meaningless.

- **Advance** iff some cell improves multi-file strict@10 by **≥ +2.00pp** AND costs **< 1.00pp** on
  single-file strict@10, both on train. Ties broken toward the smaller K, then smaller blend.
- **Reject** otherwise, write the verdict, leave the default off, keep the scaffolding.
- If a cell advances, **one** held-out run is spent on it, reported whatever it says — including if it
  fails to reproduce the train gain, which is itself the finding.
- The identity control (blend=0) must reproduce baseline **exactly**. If it does not, the harness is
  wrong and no cell in that run may be read.

## What would make this round worthless

Reporting any number from a cell chosen after seeing held-out results; quoting a train number as if it
were held-out; or moving the ±2.00pp bar after the grid has run. All three are how a tuning round
launders itself into a headline, and the reason this file is written first.
