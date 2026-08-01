# GATE_DECISION — acceptance-gate modernization (Phase B1)

**Status: PROPOSAL for a reviewed policy decision. Not a policy change.** `compare_runs.py --gate=two-tier`
is opt-in code — it changes nothing about the legacy `--enforce` predicate the A7 acceptance run is currently
blocked on. The numbers below (absolute ceilings, cost weights, the minimum quality-per-cost ratio `R`) are
proposals grounded in measured evidence, not decided defaults; the flags have no built-in default and the
tool refuses to run in `two-tier` mode until a human supplies them explicitly. See
the Phase B1 research and R4 eval-methodology notes for the research this
implements, and the A7 execution history for why this matters right
now: the A7 router candidate is a real, measured +33.3pp strict file@10 win that the legacy flat-relative-cap
predicate rejects outright because of a warm/cold/token cost increase, with no way to express "is this
tradeoff worth it" — only "did every cost dimension individually stay under a fixed relative cap."

## Why the flat AND predicate needs replacing (R4 rationale)

The legacy predicate is `mean(strict_delta) >= 2pp AND clustered-bootstrap-LB(strict_delta) > 0 AND
lenient/MRR/multi-file don't regress beyond small tolerances AND warm p50/p95 <= +5%/+10% AND token
p50/p95 <= +5%/+5% AND cold p50/p95 <= +5%/+10% AND index p50/p95 <= +5%/+10% AND category strata don't
regress beyond 2pp AND all-patch doesn't regress beyond 0.5pp`. Two structural problems, both named in R4:

1. **All caps are relative to the previous release, not absolute.** Each release can drift the ceiling by
   its own +5%/+10%, compounding indefinitely; there is no floor tied to what "interactive" actually means
   for a CLI positioned as "the ripgrep of AI context."
2. **The predicate is blind to magnitude.** A cost dimension either passes or fails its cap; a quality win
   of any size cannot buy back a cost overrun of any size, even when the trade is obviously worth it (here:
   +33.3pp strict file@10, LB +25.0pp, for roughly +9-10% weighted latency/token cost). R4 frames this as
   quality-adjusted acceptance over fixed budgets vs. a flat AND of independent caps; production systems
   pair an absolute SLA ceiling with a *separate* accuracy/utility gate rather than one compound relative
   predicate.

The two-tier design keeps both properties the flat predicate was protecting (a hard latency floor; require
quality to actually improve) while fixing both problems: tier 1 is absolute (no drift), tier 2 explicitly
prices the tradeoff instead of vetoing it category-by-category.

## The exact new predicate (as implemented in `compare_runs.py`)

Opt-in via `--gate=two-tier` (default remains `--gate=legacy`, byte-identical to today — see
"Legacy byte-identity proof" below). All of the legacy report lines are still printed in both modes so a
release comparison stays fully comparable; only the ACCEPT/REJECT predicate and the two `[two-tier]` lines
change.

**Tier 1 — hard absolute interactive-SLA ceiling (unconditional).**
Computed only from the *candidate* ("after") run's own measurements, not relative to baseline — this is the
property that stops ceiling drift:

```
warm_p95_abs_ms = 1000 * p95_across_instances( candidate[i].arms[ARM].wall_p95 for i in held_out_ids )
cold_p95_abs_ms = 1000 * p95_across_instances( candidate[i].arms[ARM].cold_wall for i in held_out_ids )
tier1_ok = warm_p95_abs_ms <= --abs-warm-p95-ms  AND  cold_p95_abs_ms <= --abs-cold-p95-ms
```

`p95_across_instances` is the same population-p95-by-rank formula already used for the paired ratio
quantiles (`ratios[max(0, ceil(.95*n) - 1)]`), just applied to absolute per-instance values instead of
before/after ratios. `wall_p95` is itself the p95 of that instance's 5 warm samples (already computed by
`run_locbench.py`); `cold_wall` is the single `--no-cache` cold sample per instance. Tier 1 fails the run
regardless of how good tier 2 looks — this is deliberate: R4 calls it "unconditional," protecting the
product positioning independent of any quality argument.

**Tier 2 — soft utility gate (clustered-bootstrap lower bound of quality per unit of cost).**

```
quality_lb          = clustered_bootstrap_95pct_lower_bound( strict_file_at_10_delta )   # reused as-is from the legacy gate
weighted_cost_delta = --cost-weight-warm * warm_p50_delta  +  --cost-weight-token * token_p50_delta
if weighted_cost_delta <= 0:
    tier2_ok = quality_lb > 0        # cost flat/down + quality up is Pareto-dominant: auto-accept
else:
    quality_per_cost = quality_lb / max(0, weighted_cost_delta)
    tier2_ok = quality_per_cost >= --min-quality-per-cost
```

`quality_lb` is exactly the existing `lower` variable (repository-clustered paired bootstrap, 10,000
deterministic resamples, seeded — no new randomness). `warm_p50_delta` and `token_p50_delta` are the
existing paired-ratio-quantile computations (`paired_ratio_quantiles("wall_median")` /
`paired_ratio_quantiles("output_tokens_ceiling")`), reused unchanged. `--cost-weight-warm` and
`--cost-weight-token` default to 0.5/0.5 (equal weight between interactive latency and context-budget
cost — a sane starting point per the task's instruction that these specific two get defaults; `R` and the
two absolute ceilings do not, see below).

`two_tier_ok = tier1_ok AND tier2_ok`. The pre-existing paired-comparison contract refusals (dataset/split
mismatch, exclusion-count mismatch, instance-set mismatch, per-instance repo/gold_files/primary_files/
gold_funcs mismatch) run unconditionally before either gate, in both modes — unchanged, verified in
`test_compare_gate.py::test_mismatched_contract_still_refused`.

### Flags added

| Flag | Default | Meaning |
|---|---|---|
| `--gate` | `legacy` | `legacy` \| `two-tier`. Opt-in; `legacy` output is byte-identical to pre-B1. |
| `--abs-warm-p95-ms` | *(none — required in two-tier mode)* | tier 1 ceiling |
| `--abs-cold-p95-ms` | *(none — required in two-tier mode)* | tier 1 ceiling |
| `--min-quality-per-cost` | *(none — required in two-tier mode)* | tier 2 ratio `R` |
| `--cost-weight-warm` | `0.5` | weight of warm p50 delta in the cost scalar |
| `--cost-weight-token` | `0.5` | weight of token p50 delta in the cost scalar |

The three policy numbers have **no default on purpose**: baking in a specific SLA ceiling or acceptance
ratio as a silent default would itself be the policy decision this memo is asking for, not a code change. If
`--gate=two-tier` is passed without all three, the tool refuses before reading any input files.

## Legacy byte-identity proof

Method: the pre-edit `compare_runs.py` was preserved verbatim (as read before any change) into a scratch
copy; six synthetic paired fixtures (120 instances / 20 repos each, covering accept, reject-on-cost,
tier1-would-fail, tier2-accept, tier2-reject, and cost-flat-or-down cases) were run through both the
pre-edit copy and the edited file with identical arguments (`--arm anchor`, with and without `--enforce`,
`--gate` omitted i.e. legacy default). `diff -q` on stdout plus exit-code comparison matched on all 12
runs (6 fixtures × 2 enforce states); zero byte differences, zero exit-code differences. The same check is
re-run as `test_compare_gate.py::test_legacy_byte_identity_golden`, which additionally locks in a literal
golden capture of the exact stdout bytes for a fixed-seed fixture so any future edit that changes even one
character of legacy output fails the test immediately, and confirms `--gate legacy` passed explicitly
produces byte-identical output to `--gate` omitted.

## Proposed default ceilings — grounded, but explicitly an open question

Two very different absolute-latency reference points exist in the record, and they disagree by roughly an
order of magnitude, which is itself the finding this memo surfaces for review:

**A6 canonical representative-budget numbers** (A6 closeout, `Mac17,8`,
`bench/representative_perfgate.sh`): a fixed, content-and-path-hash-pinned **480-file / 1,120-symbol /
320-edge / 183,040-byte synthetic fixture**. Independent five-sample closeout: warm rich-index `--for`
**21.866 ms** (budget 30 ms), cold **54.979 ms** (budget 100 ms). This is a controlled, small, CI-friendly
regression gate — it is not representative of LocBench's real-world repo sizes.

**A7 real-corpus absolute numbers**, computed directly from the actual A7 release artifacts
(baseline and router-candidate held-out result JSONs, arm=`for`, N=243 held-out real GitHub repos):

| | warm p50 | warm p95 | cold p50 | cold p95 | token p50 | token p95 |
|---|---|---|---|---|---|---|
| A7 baseline | 122.5 ms | 675.3 ms | 289.3 ms | 1,434.7 ms | 5,102 | 6,833 |
| A7 router candidate | 149.9 ms | 756.8 ms | 316.7 ms | 1,501.1 ms | 5,483 | 8,144 |

The real corpus runs **~10-30x slower** than the A6 synthetic fixture at p50 and p95 — LocBench repos are
substantially larger and more variable than the pinned 480-file fixture, so the A6 numbers characterize the
tool's floor under controlled conditions, not the interactive experience on the actual held-out corpus. A
tier-1 ceiling literally set at the A6 numbers (e.g. 30 ms / 100 ms, or even a generous 10x = 300 ms /
1,000 ms) would **reject today's already-accepted baseline** (p95 675 ms / 1,435 ms), which is almost
certainly not the intended SLA — it would silently redefine "acceptable" to mean "small repos only."

**Proposed anchor for review** (not a default in code): ceiling = baseline's own measured p95 on the real
corpus + 15% headroom, i.e. **warm p95 ceiling ≈ 780 ms, cold p95 ceiling ≈ 1,650 ms**. This keeps tier 1
genuinely absolute (fixed numbers, doesn't move with the candidate) while being grounded in what the corpus
the tool is actually measured against looks like today, rather than the unrepresentative small fixture.
Reviewers may reasonably prefer a tighter number if the intent is to force perf work before any further
quality trade, in which case the A6 fixture stays as the separate, already-existing CI regression gate
(`bench/representative_perfgate.sh`) — this memo does not propose merging the two.

**Illustrative (not decisional) retroactive check against the actual A7 numbers:** applying the tier-1
proposal above, the A7 router candidate's own p95 (756.8 ms warm, 1,501.1 ms cold) passes both. Tier 2 with
default weights (0.5/0.5) on the recorded A7 deltas (warm p50 +9.5%, token p50 +8.7%) gives
`weighted_cost_delta ≈ +9.1%`; with `quality_lb = +25.0pp = 0.25`, `quality_per_cost ≈ 0.25 / 0.091 ≈ 2.75`.
So the open question below is effectively "is 2.75 quality-points-of-LB per weighted cost-point a good
trade" — this memo takes no position; it exists so the reviewer has the actual number instead of guessing.

## Open question: what should `R` (`--min-quality-per-cost`) be?

No proposed value is asserted as correct. Three anchors, for review:

- **R ≈ 1.0** (permissive): accept any statistically-confident win where the quality LB in percentage
  points is at least as large as the weighted cost increase in percent. Very few realistic candidates would
  fail tier 2 under this bar; most of the gate's power would come from tier 1.
- **R ≈ 2.5–3.0** (near the A7 candidate's own measured ratio, ~2.75): a bar that makes the actual pending
  A7 decision a close call rather than an obvious accept or reject — useful if the intent is "this specific
  tradeoff should be genuinely debated," not rubber-stamped.
- **R ≈ 5.0** (conservative): requires a strongly dominant win; A7's router candidate would fail tier 2 at
  this bar even though it clears tier 1, i.e. quality alone would not be enough to justify its cost profile.

This also interacts with the cost weights: shifting weight toward `--cost-weight-token` (candidates that
are quality-neutral but verbose cost more) vs `--cost-weight-warm` (candidates that are quality-neutral but
slow cost more) changes which future candidates clear the bar; 0.5/0.5 is presented only as a sane,
unopinionated starting point per the task's instruction to give the weights (not `R` or the absolute
ceilings) a default.

## Appendix — file@3 / function@3 k-sweep (NOT applied; belongs in `run_locbench.py`, which is SHA-pinned
mid-A7)

Two different situations, worth separating:

- **file@k for arbitrary k is already available with zero `run_locbench.py` changes.** The per-instance
  `file_worst` field already holds the *unrestricted* worst rank across all primary gold files (or `None`
  if any gold file is entirely absent from the universe) — it is not capped at k=10. `compare_runs.py`'s
  existing `hit(row, arm, key, k=10)` already takes `k` as a parameter, so `hit(row, arm, "file_worst", 3)`
  is already the correct strict file@3 predicate today. A file@3 report line could be added to
  `compare_runs.py` alone.
- **function@k for arbitrary k needs one new field.** The per-instance JSON only exports `func_first`
  (first-hit rank, used for lenient/MRR), not the ALL-gold-funcs worst-case rank; the aggregate accumulator
  computes `fn5`/`fn10` (`acc_all_at(nranks, 5|10)`) but only as a corpus-level sum, not per-instance, so it
  cannot feed the paired bootstrap comparator at an arbitrary k. This needs a `func_worst` field mirroring
  the existing `file_worst`/`all_file_worst` pattern. Proposed patch (NOT applied — `run_locbench.py` is
  SHA-pinned mid-A7; Phase B1 explicitly defers this):

```diff
--- a/bench/locbench/run_locbench.py
+++ b/bench/locbench/run_locbench.py
@@ -425,7 +425,9 @@ for idx, ( inst, arm_out ) in enumerate( ... ):
             ff = first_hit( franks )
             m["anyf10"]  += ( ff is not None and ff < 10 )
             m["anyfn10"] += ( fh is not None and fh < 10 )
             arm_out[arm] = dict( file_first=ff, file_worst=( max( franks ) if franks and all( r is not None for r in franks ) else None ),
                                  all_file_worst=( max( all_franks ) if all_franks and all( r is not None for r in all_franks ) else None ),
-                                 func_first=fh, wall_median=round( wall_med, 4 ), wall_p95=round( wall_p95, 4 ),
+                                 func_first=fh,
+                                 func_worst=( max( nranks ) if nranks and all( r is not None for r in nranks ) else None ),
+                                 wall_median=round( wall_med, 4 ), wall_p95=round( wall_p95, 4 ),
                                  cold_wall=round( cold_wall, 4 ), index_wall=round( index_wall, 4 ),
                                  output_bytes=len( payloads[0].encode( "utf-8" ) ), output_tokens_ceiling=estimated_output_tokens( payloads[0] ),
                                  candidate_bytes=len( candidate_xml.encode( "utf-8" ) ) )
```

Once `func_worst` exists, `compare_runs.py` can add `strict3_delta` / `func3_delta` report lines using the
same `hit(..., k=3)` pattern already in place, and Phase B1's "make @3 a first-class acceptance metric"
bullet can be revisited as its own reviewed predicate change (out of scope here — this memo's code change
is the two-tier gate only).
