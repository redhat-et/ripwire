# ARISE line ranking — results, SCORED, outcome FAIL

Scores `docs/research/arise-line-ranking-prereg.md` (round 3, signed `5b7f01c409ab94988ee59c62e2468f9e91dcf715`)
against the owner-supplied `r4-arise` asset tree. Raw outputs in this directory; the run commands and
every number are also recorded in the prereg doc's own Results section.

## Binaries

| binary | built_from | sha256 |
| --- | --- | --- |
| lane | `5b12674fa` | `f07ffc6f550ba52ab173c70422e4a77db69eb8306926d3d3920e91ec64c40c39` |
| baseline (§1.3 re-fingerprint) | `755f9026f` | `8bf705fe9e49b8714c079853e3312b04017baea9839eb572eccd3bc4b5c8706a` |

The baseline binary was built as a precaution for §1.3's binary-drift re-fingerprint; it was never
invoked — tiers (b)/(c) matched directly under the lane binary, so no drift rescue fired
(`binary_drift_disclosed: false` in `verdict.json`).

## Asset tree

`<assets>/r4-arise` (owner-supplied, not fetched by this lane). 88 held-out repo checkouts, all 182
registered rows' `base_commit`s resolve. Row list (`instance_id|repo|base_commit`, `instance_ids.txt`
in this directory) sha256: `8f2069c3bd7b0a0d23599b619786c5d71eabc5a9dc25510fac72c69d3f659028` — matches
the tree-construction record exactly.

## Tier (a) — dataset-only fingerprint: EXACT MATCH

| stage | rows | gold lines |
| --- | ---: | ---: |
| dataset | 560 | — |
| multi-function | 208 | 6,809 |
| single-function | 352 | 2,806 |
| **carried** | **182** | **1,040** |

`no_checkout=170, no_commit=0` on this tree (the clean 88-only checkout shape the pre-reg's §1.1
predicts).

## Tier (b) — binary-dependent counts: EXACT MATCH (lane binary, no drift rescue needed)

| stage | rows |
| --- | ---: |
| selector refused, plain | 3 |
| selector refused, scoped | 2 |
| `--expand` served no body | 2 |
| gold outside span | 2 |
| **scored instances** | **173** |

var_instances (scored instance, inventory variable pairs) = 498.

## Tier (c) — statistics, tolerance ±0.0005+1e-9: EXACT MATCH (lane binary)

| order | @1 (measured) | @1 (registered) | MRR (measured) | MRR (registered) |
| --- | ---: | ---: | ---: | ---: |
| R0 | 0.02935 | 0.029 | 0.15388 | 0.154 |
| CTL | 0.04230 | 0.042 | 0.23428 | 0.234 |
| R1 | 0.04769 | 0.048 | 0.28887 | 0.289 |
| R2 | 0.04769 | 0.048 | 0.28887 | 0.289 |

All four within tolerance under the lane binary directly — population PASS, no binary drift disclosed.

## §4 verdict — wide-pool: FAIL

| quantity | value |
| --- | ---: |
| R3 (this attempt) Recall@1 | 0.03440 |
| R3 MRR | 0.26311 |
| CTL Recall@1 | 0.04230 |
| R1 Recall@1 | 0.04769 |
| R0 Recall@1 | 0.02935 |
| margin (R3@1 − CTL@1) | **−0.00791** |
| 95% CI (paired bootstrap, seed `ripwire-arise-line-rank-v1`, 10,000 resamples) | **[−0.03103, 0.01890]** |
| clears margin bar (≥ 0.02) | **false** |
| CI excludes zero | **false** |
| beats R1 | **false** (0.0344 < 0.0477) |
| beats R0 | true (0.0344 > 0.0294) |
| n instances | 173 |

**1 of 4 required conditions holds. FAIL.** `verdict.json` in this directory is the scorer's raw
output (`score_arise_linerank.py --dataset ... --summary ... --results ... --verdict-out verdict.json`).

Per-instance split against R1 (n=173): better on 2, worse on 7, tied on 164 — R3 rarely diverges from
R1 (the signature-line structural ceiling, §3.4), and when it does, loses more often than it wins in
this measurement. Spot-checked by hand (`huggingface__accelerate-3248`, gold line 439): R3 promotes the
`child` declaration line (438, hasAnyDef=1, coverage=2) ahead of the actual gold call-site line (439,
coverage=4, no def on it) — R1 picks 439 correctly (coverage-max), R3 does not. Not a signature-line
case; a plain instance of the mechanism itself failing to help.

## §4.3.2 — narrow-pool arm (informational; wide-pool FAIL already means nothing ships)

Re-measured in this run, same corpus, `bench/slice/score_arise_narrowpool.py` (committed
`5b12674f` — the branch's second commit, before this scoring run):

| arm | var_instances (pairs) | MRR |
| --- | ---: | ---: |
| defuse (re-measured here) | 506 | 0.60212 |
| defrole (this attempt) | 506 | 0.57042 |
| defuse (EVALS.md published, for reference) | 478 | 0.628 |

Both counts (506 vs the registered 478) and defuse's re-measured MRR (0.602 vs the published 0.628) are
disclosed mismatches — expected per §4.3.2's own note that this is a fresh, committed re-implementation
of EVALS' uncommitted scratch arm, not an import of it, run against a possibly slightly different tree
construction. `defrole < defuse` either way: the narrow-pool bar (`MRR(defrole) >= MRR(defuse)`,
re-measured) also does not clear. Consistent with the wide-pool result, not merely uncontradicted by it.

## Outcome and licensed sentence (verbatim, `docs/research/arise-line-ranking-prereg.md` §6, FAIL row)

**FAIL.**

> "We pre-registered one honest attempt — definitions before uses, then coverage — before running it,
> per your rule that a ranking claiming to rank at chance is the `--adaptive` defect in another costume.
> It did not clear the pre-registered bar over the whole function span (R3@1 0.034 vs CTL@1 0.042, Δ =
> −0.008, 95% CI [−0.031, 0.019]; at our sample size this could mean either no real effect or an effect
> too small to detect — we report the numbers, not a claim about which). `--slice` does not claim to
> rank lines over the whole function beyond what is proven, and says so in the legend and `--help`. The
> narrower, already-shipped claim — that among the lines `--slice` already selects, def-use coverage
> beats a random shuffle — is unaffected and stays the default: source order was measured WORSE than
> random on those same rows, so replacing it with source order would be a regression, not a fix."

## What ships

**Nothing in `src/`.** Per §4.3.1: `order="defuse"` stays the default, `kSliceLineRankVerdict` stays
`Pending`. The legend/help disclosure change §4.3.1 pre-registers (scoping "ranked" to "these rows",
stating the whole-function coverage rule ranks at chance) is deliberately NOT shipped by this lane —
it is worded here for a future commit to land with this verdict, per §4.5's rule that outcome-describing
prose belongs to the commit that ships the outcome.

## Replication population

170 rows / 45 repos (disjoint from the scored 88-repo set) exist in the dataset and are the registered
replication population (§4.4). **Not fetched or scored** — an owner decision, stated rather than
silently treated as "no replication population exists," per §4.4's own registration. Moot for shipping
either way, since the wide-pool result already FAILs.
