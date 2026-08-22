# Stage 2 pre-registration ADDENDUM — DRAFT, pending owner sign-off

**Status: DRAFT.** This is not a frozen pre-registration. Nothing below authorizes a run. It exists
so the design can be reviewed and, if accepted, promoted to a frozen document (following the shape of
`bench/lb3retry/PREREG.md`) before any instance is touched.

This document is an ADDENDUM to the Stage 1 pre-registration, not a replacement: the arms (baseline
vs. ripwire_cli), the seed protocol (K=3, vary only the sampling seed per the Terminal-Bench "vary
only the harness" template), the task-selection discipline (repo-disjoint from LocBench train, see
`select_tasks.py`'s `frozen_partition()`), and the contamination gate (`baseline_contamination_note`)
all carry over unchanged. What changes is the primary endpoint and the instance count.

## Why the primary endpoint moves

Stage 1 tranche 1 (48 runs: 8 instances x 2 arms x 3 seeds, single-repo SWE-bench-Lite instances) is
the local record this addendum cites; see the tranche's own results report for the full numbers and
methodology (not restated here — this file stays free of results, per house rule: pre-registrations
describe what will be measured and how it will be judged, not what a prior round found).

The single number that drives this addendum's design: **measured discordance = 0.083** (2 of 24 paired
instances had a different resolved/not-resolved outcome between arms; 5 pairs were resolved by both
arms every seed, 2 were resolved by neither). Discordance upper-bounds the arm effect a resolved-rate
endpoint can show — a delta cannot exceed the fraction of pairs where the two arms could possibly have
disagreed. At 0.083 measured against Stage 1's own pre-registered assumption of a much higher
discordance rate, the original power estimate for a resolved-rate endpoint no longer holds on this
instance mix. On the current pool (single-repo, Lite-stratum, run against a strong agent) resolution
outcome has very little room left to discriminate between arms: most instances are already resolved by
both arms or by neither, and the tool's effect — if it has one — is not showing up as "does the task
get solved" on this population.

**This addendum proposes re-aiming the primary endpoint at cost rather than outcome**, following Stage
1's own stated recommendation for the cost-focused design. The candidate direction (retrieval tooling
changes how much an agent has to read and reason over, not whether it eventually converges) is a
better fit for what Lite-stratum single-repo instances can actually discriminate, and it is the
tool's stated value proposition regardless of instance difficulty.

## Proposed primary endpoint

**Output tokens per resolved task, paired.** For each (instance, seed) pair where BOTH arms reach
`status="ok"` AND both arms resolve the task (the paired-resolved subset — the only subset where "cost
to get the same answer" is a well-defined comparison), the endpoint is each arm's `tokens_out`
distribution, compared as a paired ratio (treatment / baseline) with a clustered bootstrap
confidence interval (cluster = repo, following the existing `analyze.py` design — no new statistical
machinery). Accept direction and magnitude are NOT set in this draft; that decision, and its numeric
acceptance band, belongs in the frozen version after owner review.

Secondary/report-only endpoints carried forward from Stage 1 without change: localization hit rate,
wall-clock, total recorded cost, and the substitution-rate instrumentation
(`ripwire_calls`/`native_read_calls`). None of these gate acceptance under this draft; they are
reported alongside the primary endpoint for the same reason Stage 1 reported them — a token-cost win
that came with a localization or wall-clock regression would be a different, worse claim than the one
this endpoint is designed to test.

## Proposed instance count

**~30 instances** from the corrected task pool (the pool that passes `agentlooplockcheck.sh`'s
fail-closed partition re-derivation — no repo whose `frozen_partition()` resolves to LocBench-train).
This is roughly 4x Stage 1 tranche 1's instance count, chosen because a token-ratio endpoint on the
paired-resolved subset needs enough resolved-by-both pairs to power a paired comparison — Stage 1's
5-instance always-resolved-by-both-arms subset is too small on its own; a larger pool grows that
subset even though the discordant/never-resolved fraction is subtracted away. The exact number and its
power justification (what ratio delta is detectable at what pair count) is deliberately NOT computed
in this draft — that calculation belongs in the frozen version, informed by Stage 1's own observed
resolved-by-both fraction rather than a re-guess.

## What this draft deliberately leaves open

- The acceptance band for the primary ratio (a direction with no magnitude is not a falsifiable claim).
- Whether to also fund the alternative Stage 1 named — hunting discordance directly, on
  harder/multi-file/larger-repo strata where localization is more plausibly the bottleneck — as a
  separate, later round rather than a competing design for this one.
- The exact instance-selection procedure for the ~30-instance pool (round-robin by repo, as Stage 1's
  `limit_tasks_repo_round_robin` already does, is the default assumption but is not frozen here).
- Cost projection and the explicit human go-ahead the harness's own safety note requires before any
  `--live` run — this draft authorizes nothing.

## Next step

Owner review and sign-off. If accepted, this file is promoted to a frozen pre-registration (own file,
following `bench/lb3retry/PREREG.md`'s shape: frozen acceptance criteria, gates, and an ADDENDUM
section for anything appended before the first measurement) before any instance is run.
