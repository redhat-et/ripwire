# GATE_DECISION — R1-cpp anchor-hop retry (pre-registered 2026-07-22, BEFORE any candidate C++ run)

**Task:** R1-cpp — retry the R1 anchor-hop expansion with the **C++ metric primary**
(the owner is C++-first; the recorded R1 positive signal was C++: SFML strict@10 31.3% → 33.9%, +2.6pp at
α=0.10 while Python LocBench held-out gave +0.41pp / LB +0.00pp → honest REJECT). This document is written
and committed in spirit **before** the calibration sweep and before any held-out candidate run; nothing
below is adjusted after numbers exist. Deviations, if any become unavoidable, must be logged in the verdict
file with the reason and count as evidence against the run, not for it.

## The candidate (fixed before any run)

1. The **exact R1 implementation** re-applied from `bench/locbench/results/r1_anchorhop/
   r1_candidate_implementation.patch` (drift resolved by hand: `LensRanking`/`runPackTask` moved to
   `src/packtask.h` since R1; the pack-task `--json` tail gained the mirroring `"hop"` key). Contract
   re-proven on this branch before any bench run: name-exact route, `--no-route`, and the plain map are
   **byte-identical to a main-built binary** (native AND ASan; `nr`/`ne`/`plain` diffs), and
   `RIPWIRE_NO_ANCHORHOP=1` on the conceptual route is byte-identical to main too (the env-ablated arm IS
   the baseline). Gates: `test/anchorhopcheck.sh` (from the R1 archive) green.
2. **The R1-recorded future-work cost lever, implemented: a top-m-anchor-restricted exact bound that
   re-enables MaxScore pruning under expansion.** R1 disabled pruning whenever the hop was active (the
   expansion needed exact base scores) — the recorded root cause of its cost tier (warm p95 +10.2%).
   R1-cpp keeps pruning ON: K' = max(consumerK, m) keeps the top-m anchors provably exact, hop mass is
   computed from anchor scores + edge evidence only, and the ≤2m θ-surviving candidates are re-scored
   exactly on demand from the retained integer BM25 stats (`LexRescorer`, bit-identical floats). Gate
   written first: `test/anchorhopprunecheck.sh` (pruned vs `RIPWIRE_NO_PRUNE=1` byte-identical under a
   FIRING expansion, three consumer shapes incl. K < m; ablated-path prune-eq; mutation self-test) — wired
   into `test/regression.sh`'s absorb list.
3. **α/θ re-calibrated on the C++ train split ONLY** (below). All other mechanics (m=10, 1-hop
   call/import/decl-use, ω=1/(1+ambOut), MAX-not-SUM combination, 2m cap) are R1-decided constants and are
   NOT re-tuned.

## Train / held-out split over the C++ instances (decided here, with reasons)

- **TRAIN = bench/cppbench SFML (n=115 scored, 1 repo, commit-message queries).** SFML is a single
  repository, so it cannot support clustered inference as a held-out set — but it is a fine calibration
  set, and the R1 informational signal was measured on it (at α=0.10), so treating it as anything other
  than train would be double-dipping.
- **HELD-OUT = bench/multiswe C++ split (n=121 scored; 5 repos: nlohmann/json 51, fmt 39, simdjson 20,
  Catch2 10, cpp-httplib 1; issue-report queries, human-verified PRs).** Never touched by any R1 or R1-cpp
  candidate before the one acceptance run. The split is therefore **repo-disjoint AND query-style-disjoint**
  (calibrate on post-hoc commit messages, accept on issue reports) — the strongest generalization test the
  two frozen locks can express. Both `dataset.lock`s are frozen; no re-mining.

## Calibration protocol (train only)

`run_cppbench.py --arms for` against the SFML lock, binary = this branch's `build/ripwire`:
baseline arm = `RIPWIRE_NO_ANCHORHOP=1`; sweep arms = `RIPWIRE_ANCHORHOP_ALPHA ∈ {0.05, 0.10, 0.15, 0.20,
0.30, 0.40}` at θ=0.50, plus θ ∈ {0.25, 0.75} at the best α (8 candidate points, the R1 convention).
Selection rule (decided now): maximize train strict file@10 delta; ties broken by least strict@1/MRR
damage, then by smaller α (less reshaping). Chosen constants are baked into `graph.h anchorhopcfg` before
the held-out run; the full sweep lands in `bench/locbench/results/r1cpp_anchorhop/anchorhop_calib_cpp.json`
(same convention as `bench/locbench/anchorhop_calib.json`). Rank metrics are deterministic (every arm run
is verified byte-identical twice by the harness), so single-run sweep points are valid.

## Acceptance gate (two-tier, A7 shape, applied to the held-out C++ run)

**One shot.** After constants are baked, the held-out multiswe C++ run happens ONCE per arm
(baseline = same binary `RIPWIRE_NO_ANCHORHOP=1`, candidate = default), plus the timing protocol below.
No re-runs after seeing numbers.

- **Primary quality metric: strict file@10** (ALL primary gold files in the top-10 of the flat
  `--format=candidates` rank — LocAgent's definition, identical to both benches' scoreboards), paired
  per-instance, candidate − baseline, over the n=121 held-out instances.
- **Tier 1 — absolute SLA ceiling (reused from A7 unchanged: warm p95 ≤ 775 ms, cold p95 ≤ 1650 ms).**
  Computed from the candidate run's own production-bundle timing protocol (below) across held-out
  instances (population p95 by rank). Honesty note, recorded in advance: the C++ corpus is lighter than
  LocBench's Python repos, so tier 1 is expected to be a weak constraint here — it is kept because
  inventing new C++ ceilings would be a second knob, and the A7 numbers are the pre-registered product SLA.
  The binding cost control on this corpus is tier 2 + the Python cost spot-guard.
- **Tier 2 — utility ratio (R = 2.5, weights 0.5 warm-p50 / 0.5 token-p50, reused from A7 unchanged).**
  `quality_lb` = clustered-bootstrap 95% lower bound of the paired strict@10 delta, **clustered by
  repository (5 clusters, one a singleton)** — the honest cluster unit for a 5-repo corpus; 10,000
  deterministic seeded resamples (seed 20260722). An instance-level (unclustered) LB is reported as
  sensitivity but is NOT the acceptance number. `weighted_cost_delta` = 0.5·(warm p50 paired-ratio delta)
  + 0.5·(token p50 paired-ratio delta) from the timing protocol. Pareto rule as in A7: if
  `weighted_cost_delta ≤ 0`, tier 2 = (`quality_lb` > 0); else `quality_lb / weighted_cost_delta ≥ 2.5`.
- **Timing protocol (the perf tier only — quality numbers never reuse these runs):** per held-out
  instance, the production `--for` bundle (no `--format=candidates`), **5 warm samples + 1 cold
  (`--no-cache`) per arm**, arms sequential, run alone on the machine; token ceiling = the locbench
  `estimated_output_tokens` of the warm payload. Implemented by a standalone archived script
  (`timing_multiswe.py` in this results dir) — `run_multiswe.py` itself is not modified for this.

## Python LocBench held-out — no-regression guard (quality) + cost spot-guard

- **Quality guard (n=243 held-out, arm `for`, single warm run per instance — quality only, deterministic):**
  candidate (final baked constants) vs baseline (`RIPWIRE_NO_ANCHORHOP=1`), paired strict file@10 delta.
  **Guard fails if** mean delta < −1.0pp **or** the repo-clustered (78 clusters) bootstrap 95% CI lies
  entirely below 0 (a statistically resolved drop). "Noise-level wobble" (CI straddling 0 and mean within
  1pp of 0) holds the guard.
- **Cost spot-guard:** the R1 cost risk lived on large Python repos (the pruning giveback). With pruning
  restored the mechanism is gone by construction; verify empirically on the **3 largest held-out Python
  repos by symbol count**: warm production `--for`, 5 samples each side, per-repo median delta must be
  ≤ +5% on each of the 3 (the A7 warm-p50 cap applied as a spot check).

## Shipping-surface decision tree (decided now, before numbers)

1. C++ gate PASS + both Python guards HOLD → **ship always-on** (the same default-on surface R1 specified;
   the retrieval design record updated with the R1-cpp gate record + pruning-restoration contract).
2. C++ gate PASS + Python quality guard FAILS → **opt-in flag, default off** (`RIPWIRE_ANCHORHOP=1` stays
   an env/eval surface; no language-conditional ranking — a ranker that behaves differently per corpus
   language is rejected here as a determinism/simplicity product smell).
3. C++ gate FAIL → **honest REJECT** (B3): revert product bytes, keep gates + archives + this record.

## Artifacts contract

Everything lands in `bench/locbench/results/r1cpp_anchorhop/`: this file, `anchorhop_calib_cpp.json`,
held-out baseline/candidate JSONs, the timing JSONs, the comparator verdict (`gate_verdict.txt`), the
final candidate diff (or revert evidence), and the Python guard JSONs + spot-guard numbers.
