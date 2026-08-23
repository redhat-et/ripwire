# Stage 2 pre-registration ADDENDUM

**Freeze marker:** `FROZEN: <pending> 2026-08-22` — filled in by the commit that lands this freeze (see
that commit's own follow-up, which stamps the exact SHA into this line; a document cannot cite its own
commit hash in the same commit that creates it).

This document is an ADDENDUM to the Stage 1 pre-registration, not a replacement: the arms (baseline
vs. ripwire_cli), the seed protocol (K=3, vary only the sampling seed per the Terminal-Bench "vary
only the harness" template), the task-selection discipline (repo-disjoint from LocBench train, see
`select_tasks.py`'s `frozen_partition()`), and the contamination gate (`baseline_contamination_note`)
all carry over unchanged. What changes is the primary endpoint, a new secondary endpoint, the instance
count and selection rule, and the pin.

## The pin has moved, and what that implies

Stage 1 built and ran its binary at commit `5f64820`. This addendum pins the **current head at freeze
time** instead of re-pinning Stage 1's binary. Between those two commits, one behavioral change landed
that touches the treatment arm's own invocation surface directly: on the CONCEPTUAL route — a `--for`
query the router sends to the subtoken+body ranker because it names no anchor symbol — the default
bundle is now compact (the ranked signature map plus one-hop callee names, no body CDATA) where Stage
1's binary always served bodies on that route. The name-exact/anchor route, `--detail=N`,
`--signatures-only`, `--pack-task`, `--expand` and `--no-route` are byte-identical across the two pins;
only the anchor-free conceptual route's default bundle differs, and `--auto-bodies` restores the old
bundle on that route as a standing opt-out.

The treatment arm's invocation is unchanged prose-to-CLI (`ripwire . --for="<short issue
description>" --token-budget=4000`), but a SWE-bench issue description is frequently anchor-free prose,
so a real share of this addendum's `--for` calls will route conceptual and see the compact bundle where
Stage 1's calls on the same kind of query did not.

**Implication, stated plainly: this addendum is not a Stage-1 replication. It is a measurement of
today's shipped serving defaults.** Any comparison between a Stage-1 number and a Stage-2 number is a
before/after-of-the-product comparison, not two runs of the same instrument — treat it accordingly in
any writeup, and do not average or otherwise pool the two stages' raw numbers as if they were repeated
draws of one population.

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

**This addendum re-aims the primary endpoint at cost rather than outcome**, following Stage 1's own
stated recommendation for the cost-focused design. The candidate direction (retrieval tooling changes
how much an agent has to read and reason over, not whether it eventually converges) is a better fit for
what Lite-stratum single-repo instances can actually discriminate, and it is the tool's stated value
proposition regardless of instance difficulty.

## Primary endpoint

**Output tokens per resolved task, paired.** For each (instance, seed) pair where BOTH arms reach
`status="ok"` AND both arms resolve the task (the paired-resolved subset — the only subset where "cost
to get the same answer" is a well-defined comparison), the endpoint is each arm's `tokens_out`
distribution, compared as a paired ratio (treatment / baseline) with a clustered bootstrap
confidence interval (cluster = repo, `analyze.py`'s existing `clustered_bootstrap_lower` /
`paired_ratio`, `tokens_out_ratio_p50`/`p95` — no new statistical machinery). Accept direction and
magnitude are left open below (see "What remains open at freeze") — this addendum registers the
endpoint and its estimator, not the acceptance band.

Secondary/report-only endpoints carried forward from Stage 1 without change: localization hit rate,
wall-clock, total recorded cost, and the substitution-rate instrumentation
(`ripwire_calls`/`native_read_calls`). None of these gate acceptance under this addendum; they are
reported alongside the primary endpoint for the same reason Stage 1 reported them — a token-cost win
that came with a localization or wall-clock regression would be a different, worse claim than the one
this endpoint is designed to test.

## Secondary endpoint (new): per-run native-read tokens

**Motivation.** A first observational transcript-mining pass over Stage 1's own runs (measurement-only,
result-free of any KEEP/REJECT verdict) found that in every body-serving `--for` episode that produced
an edit — 17 of 17, zero exceptions — a native `Read` of the file preceded the edit regardless of
whether the served body already contained the answer. The served bodies did not visibly substitute for
a native read in that sample; the read happened alongside the allowance rather than instead of it. With
the conceptual route now serving a different point on that same axis by default (fewer or no bodies,
more compactly), the open question this endpoint targets is direct: **does the agent's own native-read
volume change under the new serving default, compared to what Stage 1 observed under the old one?**

**Definition.** Per run: the count (and, where derivable, the estimated token cost — chars/4, a coarse
proxy; no tokenizer is run against the actual model, so treat this as directional, not exact, matching
the caveat the transcript-mining pass itself recorded) of native `Read` tool calls, sourced from the
harness's own persisted per-run trace — the `command_calls` / `native_read_calls` fields on the run
record — not from re-mining ad hoc session JSONL files by hand.

**Dependency, verified at freeze time, and it does not currently hold.** `command_calls` /
`native_read_calls` require the harness to actually persist a real per-tool-call trace. Stage 1's own
records did not: every `events/*.json` in that archive held only the final result-trailer summary
(cost/usage/session_id — no tool calls), and both fields stayed `null` on all 48 records. Two candidate
fixes for exactly this gap exist in this repo's history, on two different unpushed branches, neither an
ancestor of the other: one that persists every session's raw per-tool-call trace into the run's archive
directory, and one that additionally parses that trace into the two fields on the record. **As of this
freeze, checked directly (`git merge-base --is-ancestor <fix> origin/main`), neither is an ancestor of
`origin/main`** — the pin this addendum builds from does not yet carry either fix.

**Consequence.** This endpoint is registered here (definition, source fields, estimator) so the design
is frozen, but it is **conditionally measurable**: one of the two fixes (or a reconciliation of both)
must land on the commit Stage 2 actually builds from before this endpoint can report a number from run
records alone. If neither has landed by the small-pilot tranche (below), this endpoint is **declared
unmeasurable for this run — not silently reported as zero, and not worked around by hand-mining session
JSONL under `/tmp`**, which is exactly the fragile, non-durable path the transcript-mining pass itself
flagged as a harness gap rather than a repeatable method. Stage 2 proceeds on the primary endpoint alone
in that case; the dependency is recorded as a precondition for a later pass, the same "declared
underpowered, not null" discipline this codebase's own transcript-mining registration already uses.

This endpoint is report-only. Like every secondary endpoint, it does not gate acceptance.

## Instance count and selection rule

**Base pool: 265 eligible instances**, 8 repos, repo-disjoint from LocBench train — the same pool
`select_tasks.py` reports today (`eligible_after_exclusion=265`), unchanged since Stage 1.

**Stage 1's 8, held out and excluded from Stage 2** (reserved for any future replication of Stage 1
itself, not reused here): `astropy__astropy-12907`, `django__django-13448`, `psf__requests-2317`,
`pylint-dev__pylint-5859`, `pytest-dev__pytest-5103`, `scikit-learn__scikit-learn-11281`,
`sphinx-doc__sphinx-10451`, `sympy__sympy-11400`. This is exactly `run_agentloop.py`'s own
`limit_tasks_repo_round_robin()` applied with `limit=8` to the committed (alphabetically-ordered)
`tasks.lock` — the first instance per repo by instance-id order — cross-checked against the actual
Stage-1 patch archive, which names these 8 and no others.

**Mechanical rule for the ~30, using only existing, already-tested selection code (no new selection
logic):**

1. Regenerate the candidate pool with `select_tasks.py --target 48 --cap-per-repo 6 --seed
   ripwire-b4-agentloop-v1` — the same seed the committed `tasks.lock` already uses, cap raised from 4
   to 6. Six is the minimum eligible-instance count across the 8 held-out repos (astropy, psf/requests
   and pylint-dev/pylint each have exactly 6 eligible instances in the 265-pool), so raising the cap to
   6 caps every repo identically and starves none. This yields the maximum fully-balanced pool: 6
   instances x 8 repos = 48.
2. Remove the named Stage-1 8 (one per repo) from that pool, leaving 40 (5 per repo).
3. Apply `run_agentloop.py`'s own `limit_tasks_repo_round_robin()` — unmodified, the same function that
   already produced Stage 1's 8 — with `limit=30` to the alphabetically-sorted remainder. Round-robin by
   repo name yields 4 instances from 6 of the 8 repos and 3 from the remaining 2 (sphinx-doc/sphinx and
   sympy/sympy, the two repos last in alphabetical order, whichever hits the 30 cutoff first).

This was verified offline against the cached SWE-bench-Lite metadata dump already on disk from Stage 1
(the same HF row content a live re-fetch returns): it reproduces 265 eligible, the Stage-1 8 as exactly
the round-robin first-per-repo, and a 30-instance remainder split 4/4/4/4/4/4/3/3 across the 8 repos.
That is a confirmation the rule is realizable and repo-balanced — it is not a substitute for the live
regeneration and its own `content_sha256` lock, which the execution session must produce and verify
before any instance runs.

**Locking.** The live regeneration writes its own lock file, distinct from the committed Stage-1
32-instance `tasks.lock` (do not overwrite it — that file remains the record of what Stage 1 actually
ran). The Stage-2 lock is checked and refused on a `content_sha256` mismatch or a train-partition
re-derivation failure exactly per the harness's existing fail-closed contract; no lock file is ever
hand-edited.

## Cost / quota estimate

Stage 1's own realized per-run cost rate (recorded cost / run count, from the tranche's own results
report) is the planning multiplier here: **~$1.20/run equivalent**, plan-billed, both arms averaged —
used deliberately above Stage 1's raw realized rate as a margin, since this harness's own `--dry-run`
cost projection has previously under-shot a realized pilot rate and warns against trusting a literature
envelope at face value.

- **180 runs**: 30 instances x 2 arms x 3 seeds = 180 (K=3 unchanged from Stage 1 — this addendum does
  not revisit the seed axis or Stage 1's own seed-flip-rate threshold for dropping to K=1; that check is
  out of scope for the changes registered here).
- **180 x ~$1.20/run ≈ $216 central estimate.** Planning band **$150–$300**, plus Docker/emulated-scoring
  compute (wall-clock only, unbilled, per Stage 1's aarch64 pre-pull recipe).

**Tranche structure**, carried forward from Stage 1's own runbook, unchanged in shape and stop
conditions:

1. **Tranche A — isolation proof.** One real `--live-one` run (~$1), baseline arm, seed 1, not part of
   the scored matrix. Inspect the transcript for CLAUDE.md leakage, skill visibility, and
   ripwire-on-PATH before spending anything else — the same check Stage 1's own runbook required before
   its first paid call, re-run here because both the binary and the child-environment isolation code may
   have moved since Stage 1's proof.
2. **Tranche B — small pilot.** `--limit 6 --seeds 1` across both arms = 12 runs (~$14). Sanity-checks
   checkout, patch capture, token/cost accounting, and — new for this addendum — whether
   `native_read_calls` comes back non-null (the secondary-endpoint dependency above). This step is the
   3-task-scale pilot the harness's own README independently recommends before any full matrix; Stage 1
   skipped it for its smaller N, but a matrix 4x the size warrants it.
3. **Tranche C — full matrix.** The remaining runs via `--resume` against Tranche B's results (168 more,
   180 total, ~$150–$300). `--resume` skips the 12 `(instance, arm, seed)` tuples Tranche B already
   completed rather than re-spending on them; it refuses to merge against a different lock file, so
   Tranche B and Tranche C must run against the identical Stage-2 lock.

**Stop conditions**, unchanged from Stage 1's own runbook and the harness README's SAFETY NOTE:

1. No `--live`/`--live-one` call without an explicit, specific-run human go-ahead naming both the model
   and the billed credential/account — a standing prior authorization is not sufficient.
2. The `--dry-run` cost projection for the exact run count being requested must be read by a human
   before that specific run is invoked.
3. Contamination gate: `baseline_contamination_note` must report zero contaminated runs; any non-zero
   count stops the round rather than silently excluding the affected runs.
4. The Stage-2 lock must pass its own `content_sha256` check and train-repo-partition re-derivation
   before any instance in it runs; a mismatch refuses, never silently re-derives.
5. The runner checkpoints after every call; a timeout or crash retains partial results rather than
   losing the whole matrix, and resuming uses `--resume`, never a fresh `--live` from zero.
6. If neither trace-persistence fix has landed by the end of Tranche B, the secondary endpoint is
   declared unmeasurable for this run (see above) and Tranche C proceeds on the primary endpoint alone.

## Runbook commands

```sh
# 0. build the pinned binary in its own worktree (mirrors Stage 1's own build worktree pattern)
git worktree add ~/AppDevelopLocal/project2/rw-eval-t2 <this-addendum's-frozen-commit>
cd ~/AppDevelopLocal/project2/rw-eval-t2
cmake -S . -B build && cmake --build build -j
./build/ripwire --version   # confirm the built HEAD matches the frozen pin

# 1. regenerate the Stage-2 candidate pool (zero cost, deterministic, public metadata fetch only)
python3 bench/agentloop/select_tasks.py --work-dir /tmp/agentloop-t2 \
    --target 48 --cap-per-repo 6 --seed ripwire-b4-agentloop-v1 \
    --out bench/agentloop/tasks-stage2-pool.lock

# 2. apply the exclusion + round-robin cut from "Instance count and selection rule" above —
#    reuses run_agentloop.limit_tasks_repo_round_robin's own algorithm inline, no new code lands
python3 - <<'PY'
import json, hashlib
from collections import defaultdict
lock = json.load( open( "bench/agentloop/tasks-stage2-pool.lock" ) )
exclude = {
    "astropy__astropy-12907", "django__django-13448", "psf__requests-2317",
    "pylint-dev__pylint-5859", "pytest-dev__pytest-5103", "scikit-learn__scikit-learn-11281",
    "sphinx-doc__sphinx-10451", "sympy__sympy-11400",
}
remaining = sorted( ( i for i in lock["instances"] if i["instance_id"] not in exclude ),
                     key=lambda x: x["instance_id"] )
by_repo = defaultdict( list )
for i in remaining:
    by_repo[i["repo"]].append( i )
selected, row = [], 0
while len( selected ) < 30:
    added = False
    for repo in sorted( by_repo ):
        rows = by_repo[repo]
        if row < len( rows ):
            selected.append( rows[row] ); added = True
            if len( selected ) == 30: break
    if not added: break
    row += 1
canon = [ dict( instance_id=i["instance_id"], repo=i["repo"], base_commit=i["base_commit"] )
          for i in sorted( selected, key=lambda x: x["instance_id"] ) ]
chash = hashlib.sha256( json.dumps( canon, sort_keys=True, separators=( ",", ":" ) ).encode() ).hexdigest()
lock["instances"] = sorted( selected, key=lambda x: x["instance_id"] )
lock["selected_count"] = len( selected )
lock["selected_repo_count"] = len( { i["repo"] for i in selected } )
lock["content_sha256"] = chash
lock["stage2_excluded_stage1_ids"] = sorted( exclude )
json.dump( lock, open( "bench/agentloop/tasks-stage2.lock", "w" ), indent=2 )
print( "wrote tasks-stage2.lock", len( selected ), chash[:16] )
PY

# 3. zero-cost validation
python3 bench/agentloop/run_agentloop.py --dry-run \
    --tasks-lock bench/agentloop/tasks-stage2.lock --results-out /tmp/agentloop-t2/dry30.json
python3 bench/agentloop/analyze.py --self-test

# 4. credential export (owner's terminal — this document does not choose the account or model;
#    see bench/agentloop/README.md's --bare note: --bare forces ANTHROPIC_API_KEY and never reads
#    OAuth, so a --live-one first run is what proves which path this environment actually uses)
export ANTHROPIC_API_KEY=<owner-chosen>          # or confirm the OAuth profile: ant auth status

# 5. Tranche A — isolation proof (~$1, not part of the scored matrix)
python3 bench/agentloop/run_agentloop.py --live-one \
    --tasks-lock bench/agentloop/tasks-stage2.lock --limit 1 --arms baseline --seeds 1 \
    --harness claude-code-p --model <owner-named> \
    --ripwire-bin ~/AppDevelopLocal/project2/rw-eval-t2/build/ripwire \
    --work-dir /tmp/agentloop-t2 --evaluator none

# 6. Tranche B — small pilot (~$14, 12 runs)
python3 bench/agentloop/run_agentloop.py --live \
    --tasks-lock bench/agentloop/tasks-stage2.lock --limit 6 --seeds 1 \
    --arms baseline,ripwire_cli --harness claude-code-p --model <owner-named> --concurrency 2 \
    --ripwire-bin ~/AppDevelopLocal/project2/rw-eval-t2/build/ripwire \
    --work-dir /tmp/agentloop-t2 --evaluator swebench \
    --results-out /tmp/agentloop-t2/stage2-pilot.json
python3 bench/agentloop/analyze.py --results /tmp/agentloop-t2/stage2-pilot.json

# 7. read the dry-run/pilot cost projection for the full 180-run matrix and get the owner's explicit,
#    specific-run go-ahead (naming model + billed account) before this next call — the stop condition
#    above, not a formality.

# 8. Tranche C — full matrix (remaining ~168 runs, ~$150-$300 total across B+C)
python3 bench/agentloop/run_agentloop.py --live --resume /tmp/agentloop-t2/stage2-pilot.json \
    --tasks-lock bench/agentloop/tasks-stage2.lock --limit 30 --seeds 1,2,3 \
    --arms baseline,ripwire_cli --harness claude-code-p --model <owner-named> --concurrency 2 \
    --ripwire-bin ~/AppDevelopLocal/project2/rw-eval-t2/build/ripwire \
    --work-dir /tmp/agentloop-t2 --evaluator swebench \
    --results-out /tmp/agentloop-t2/stage2.json
python3 bench/agentloop/analyze.py --results /tmp/agentloop-t2/stage2.json
```

## What remains open at freeze

Freezing this addendum fixes the design — endpoints, instance selection, cost planning, and the
runbook — but not the items Stage 1's own runbook reserved for a live human at fire time, and this
addendum does not change that division:

- **The acceptance band for the primary ratio.** A direction with no magnitude is not a falsifiable
  claim; that number is an owner call, made before Tranche C, not before this freeze.
- **The billed credential/account and the model name.** Named at fire time, in the export/`--model`
  steps above — never assumed from a blanket authorization.
- **Explicit, specific-run approval for Tranche B and again for Tranche C** — a standing "yes, run
  Stage 2" is not the approval the harness's own SAFETY NOTE requires; each paid tranche gets its own.
- **Whether to also fund the alternative Stage 1 named** — hunting discordance directly on
  harder/multi-file/larger-repo strata where localization is more plausibly the bottleneck — as a
  separate, later round. Not decided here, and not a competing design for this addendum.
