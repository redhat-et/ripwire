#!/usr/bin/env python3
# analyze.py — paired per-task/seed analysis for Phase B4 agent-in-the-loop eval results.
#
# WHAT THIS DOES. Consumes the record schema written by run_agentloop.py (SCHEMA
# "ripwire-agentloop-results-v2") and computes paired arm deltas (baseline vs ripwire_cli) per
# (instance_id, seed), then a REPOSITORY-CLUSTERED bootstrap 95% lower bound on the resolved-rate
# delta — because multiple SWE-bench instances from one repo are not independent trials any more than
# multiple LocBench issues from one repo are.
#
# ATTRIBUTION: the clustered-bootstrap approach (resample REPOS with replacement, not individual rows,
# then pool every paired delta belonging to the sampled repos) is adapted from
# bench/locbench/compare_runs.py's `main()` (the repository-clustered paired bootstrap over LocBench
# instances). That file is not imported (its bootstrap is inlined in `main()`, not a reusable function,
# and it is single-purpose for the LocBench JSON shape) and is not modified by this script — this is an
# independent re-implementation of the same statistical method for the agentloop record schema.
#
# SELF-TEST (`--self-test`): builds a tiny synthetic in-memory fixture (a handful of fake repos/
# instances/seeds with a manufactured resolved-rate lift for ripwire_cli) and asserts the pipeline
# produces the expected sign and a positive bootstrap lower bound — proves the math runs correctly
# without needing any real (paid) run data.
#
# USAGE:
#   python3 bench/agentloop/analyze.py --self-test
#   python3 bench/agentloop/analyze.py --results results.json
import argparse, json, math, pathlib, random, statistics, sys

sys.path.insert( 0, str( pathlib.Path( __file__ ).resolve().parent ) )
import select_tasks   # train_contaminated_repos(): the ONE re-derivation of the split contract

SCHEMA = "ripwire-agentloop-results-v3"   # v3: three arms, resolved_model + harness_version fields
ARM_BASELINE, ARM_RIPWIRE = "baseline", "ripwire_cli"

def mean( xs ): return sum( xs ) / len( xs ) if xs else 0.0

def load_results( path ):
    data = json.loads( pathlib.Path( path ).read_text() )
    if data.get( "schema" ) != SCHEMA:
        raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expected {SCHEMA!r}); refusing" )
    # The mirror of run_agentloop.load_tasks_lock()'s contract check, on the OTHER side of the seam,
    # through the SAME imported re-derivation. A results file was necessarily produced against some
    # tasks.lock at run time, but a stale copy of that lock, a hand-edited results file, or records
    # merged in from an older run could still carry a repo that the CURRENT split contract sends to
    # LocBench train — the 2026-08-05 pilot scored pydata__xarray-3364 exactly that way. Every record
    # names its own repo, so this re-derives with no dependency on which lock produced it; fail closed
    # before any statistic is averaged. QUESTIONS-mode results (local scenario trees, whose "repo"
    # names are not SWE-bench repos at all) are the one source the split contract does not apply to —
    # refusing them would break the E1 bank for no hygiene gain.
    if not str( data.get( "tasks_lock_content_sha256", "" ) ).startswith( "questions:" ):
        train_repos = select_tasks.train_contaminated_repos( r["repo"] for r in data.get( "records", () ) )
        if train_repos:
            raise SystemExit(
                f"{path}: records from repo(s) that re-derive to LocBench TRAIN under the current "
                f"split rule, not heldout: {train_repos}. The repo-disjointness contract forbids "
                f"scoring them — refusing (fail-closed). These results were produced against a lock "
                f"that has since gone stale (or never honored the split contract); regenerate "
                f"tasks.lock with select_tasks.py and re-run." )
    return data

def pair_by_task_seed( records ):
    """Group records by (instance_id, seed, arm); return list of (instance_id, repo, seed, base_rec, ctx_rec)
    for pairs where BOTH arms have status=='ok' (a completed run with real metrics). Anything else — a
    stub/not_implemented/errored run, or a one-sided completion — is reported separately, never silently
    dropped into the paired set (that would bias the paired comparison toward whichever arm happened to
    finish more often). resolved=None (--evaluator none) still pairs: that stage's supported claims are
    localization/token/wall, and analyze() reports the resolved stats themselves as n/a."""
    by_key = {}
    for r in records:
        by_key.setdefault( ( r["instance_id"], r["seed"] ), {} )[ r["arm"] ] = r
    paired, incomplete = [], []
    for ( instance_id, seed ), arms in sorted( by_key.items() ):
        base, ctx = arms.get( ARM_BASELINE ), arms.get( ARM_RIPWIRE )
        if base and ctx and base["status"] == "ok" and ctx["status"] == "ok":
            paired.append( ( instance_id, base["repo"], seed, base, ctx ) )
        else:
            incomplete.append( ( instance_id, seed,
                                 base["status"] if base else "missing", ctx["status"] if ctx else "missing" ) )
    return paired, incomplete

def clustered_bootstrap_lower( pairs, value_fn, n_boot, seed_str, alpha=0.025 ):
    """Repository-clustered paired bootstrap (see module docstring / bench/locbench/compare_runs.py
    for the source method): resample REPOS with replacement len(repos) times per bootstrap draw, pool
    every paired value belonging to the sampled repos, take the mean; repeat n_boot times; return the
    alpha-quantile.

    THE DEFAULT IS 97.5%, NOT 95% — corrected 2026-08-10. The 2.5th percentile is the lower edge of a
    TWO-sided 95% interval, which as a one-sided bound is 97.5%. A genuine 95% one-sided bound is the
    5th percentile (alpha=0.05). The behaviour is unchanged and deliberately kept: erring conservative
    is the right direction for an acceptance gate. Only the label was wrong, and a bound that claims
    to be 95% while actually being 97.5% understates the effect this eval can detect by 1.5-4.6pp
    (measured — see power_sim.py). README.md's acceptance criterion is worded in terms of this bound,
    so read it as 97.5% one-sided.

    ALSO WORTH KNOWING BEFORE TRUSTING A NUMBER FROM THIS: with equal paired-row counts per repo — the
    case for every configuration this harness runs — pooling then averaging is algebraically identical
    to resampling the G repo-level MEAN deltas themselves. The entire bootstrap distribution is a
    resample of G numbers, and G is the locked repo count — 8 at the current tasks.lock (6 before the
    2026-08-20 partition fix; power_sim_results.json was computed at G=6, so its MDEs are slightly
    pessimistic now). Still the textbook few-clusters regime (reliable coverage wants G >~ 20-40),
    which is why adding instances inside the existing repos cannot buy power. See power_sim.py."""
    repos = sorted( { repo for _, repo, *_ in pairs } )
    if not repos: return 0.0, []
    by_repo = {}
    for instance_id, repo, seed, base, ctx in pairs:
        by_repo.setdefault( repo, [] ).append( value_fn( base, ctx ) )
    rng = random.Random( seed_str )
    boots = []
    for _ in range( n_boot ):
        sampled_repos = [ rng.choice( repos ) for _ in repos ]
        vals = [ v for r in sampled_repos for v in by_repo[r] ]
        boots.append( mean( vals ) )
    boots.sort()
    lower = boots[ max( 0, int( alpha * len( boots ) ) ) ]
    return lower, boots

def resolved_delta( base, ctx ): return float( bool( ctx["resolved"] ) ) - float( bool( base["resolved"] ) )
def loc_hit_delta( base, ctx ):
    if base["localization_hit"] is None or ctx["localization_hit"] is None: return 0.0
    return float( bool( ctx["localization_hit"] ) ) - float( bool( base["localization_hit"] ) )

def paired_ratio( pairs, field ):
    # (ctx - base) / base for a positive-valued cost/perf field, paired per (instance,seed); undefined
    # (skipped) pairs where base's value is falsy/zero/None rather than divide-by-zero.
    ratios = []
    for _, _, _, base, ctx in pairs:
        bv, cv = base.get( field ), ctx.get( field )
        if bv: ratios.append( cv / bv - 1 )
    if not ratios: return None, None
    ratios.sort()
    p50 = statistics.median( ratios )
    p95 = ratios[ max( 0, math.ceil( 0.95 * len( ratios ) ) - 1 ) ]
    return p50, p95

def substitution_rate( rec ):
    """ripwire_calls / (ripwire_calls + native_read_calls) for ONE run, or None if unmeasured.

    This is the metric every skill/hook/primer change is trying to move, and the one the harness could
    not previously express: `ripwire_calls` alone cannot tell a run that used the tool for everything
    apart from one that used it once and then read twenty files.

    None (never 0.0) when either count is missing — claude records before 2026-08-22 carried neither
    count (the session transcript was not parsed; backfill_claude_transcripts.py repairs an archived
    bundle), and a missing
    measurement rendered as 0.0 would read as "defaulted every time", inverting the conclusion. A run
    that genuinely did neither (no reads AND no ripwire calls) is also None: no denominator, no rate."""
    rw, native = rec.get( "ripwire_calls" ), rec.get( "native_read_calls" )
    if rw is None or native is None:
        return None
    total = rw + native
    return ( rw / total ) if total else None

def mean_substitution( recs ):
    vals = [ v for v in ( substitution_rate( r ) for r in recs ) if v is not None ]
    return ( mean( vals ), len( vals ) ) if vals else ( None, 0 )

def analyze( records, n_boot=10000, bootstrap_seed="ripwire-b4-agentloop-bootstrap-v1" ):
    paired, incomplete = pair_by_task_seed( records )
    repos = sorted( { repo for _, repo, *_ in paired } )
    # Contamination count (arm-isolation fix, 2026-08-20 outcome-harness-fixes lane): a baseline record
    # with status="contaminated" (run_agentloop.py's baseline_contamination_note()) is already excluded
    # from `paired` by pair_by_task_seed()'s status=="ok" requirement — this is the count IV.6 of the
    # prereg asks be REPORTED, not the mechanism that excludes it. Must be 0 for a trustworthy round;
    # any non-zero value means the isolation held at the environment level (the run still executed) but
    # the agent disobeyed the prompt contract anyway, and analyze() must never silently absorb that into
    # n_incomplete without a name.
    n_contaminated_baseline = sum( 1 for r in records
                                   if r.get( "arm" ) == ARM_BASELINE and r.get( "status" ) == "contaminated" )
    out = dict( n_pairs=len( paired ), n_repos=len( repos ), n_incomplete=len( incomplete ),
                n_contaminated_baseline=n_contaminated_baseline )
    if not paired:
        out["note"] = "zero complete paired (baseline,ripwire_cli) runs — nothing to analyze yet"
        return out
    # Resolution stats only over pairs BOTH arms actually scored (--evaluator swebench); an unscored
    # run must surface as n/a, never as a fabricated 0.0 delta.
    scored = [ p for p in paired if p[3]["resolved"] is not None and p[4]["resolved"] is not None ]
    out["n_resolved_pairs"] = len( scored )
    rdeltas = [ resolved_delta( b, c ) for *_ , b, c in scored ]
    ldeltas = [ loc_hit_delta( b, c ) for *_ , b, c in paired ]
    lower = clustered_bootstrap_lower( scored, resolved_delta, n_boot, bootstrap_seed )[0] if scored else None
    tok_p50, tok_p95 = paired_ratio( paired, "tokens_out" )
    wall_p50, wall_p95 = paired_ratio( paired, "wall_seconds" )
    cost_p50, cost_p95 = paired_ratio( paired, "cost_usd" )
    # Substitution rate is reported PER ARM, not as a paired delta: the baseline arm has no ripwire on
    # PATH at all, so its rate is 0 by construction and a delta against it measures nothing. The number
    # that matters is how close the ripwire arm gets to 1.0 — i.e. how often, when it needed to read or
    # search, it actually reached for the tool instead of defaulting.
    sub_base, n_sub_base = mean_substitution( [ b for *_, b, _ in paired ] )
    sub_ctx,  n_sub_ctx  = mean_substitution( [ c for *_, _, c in paired ] )
    out.update(
        resolved_delta_mean=mean( rdeltas ) if scored else None,
        resolved_delta_bootstrap_95_lower=lower,
        localization_hit_delta_mean=mean( ldeltas ),
        tokens_out_ratio_p50=tok_p50, tokens_out_ratio_p95=tok_p95,
        wall_seconds_ratio_p50=wall_p50, wall_seconds_ratio_p95=wall_p95,
        cost_usd_ratio_p50=cost_p50, cost_usd_ratio_p95=cost_p95,
        substitution_rate_baseline=sub_base, n_substitution_baseline=n_sub_base,
        substitution_rate_ripwire=sub_ctx,  n_substitution_ripwire=n_sub_ctx,
    )
    return out

def print_report( out ):
    def pct( x ): return f"{100*x:+.2f}pp" if x is not None else "n/a"
    def rat( x ): return f"{100*x:+.1f}%" if x is not None else "n/a"
    print( f"paired agentloop analysis: n_pairs={out['n_pairs']} n_repos={out['n_repos']} "
           f"n_incomplete={out['n_incomplete']} n_contaminated_baseline={out.get('n_contaminated_baseline', 0)}" )
    contaminated = out.get( "n_contaminated_baseline", 0 )
    if contaminated:
        print( f"  ** {contaminated} baseline run(s) invoked ripwire despite the no-ripwire contract "
               f"(status=\"contaminated\") — excluded from n_pairs, but a non-zero count here means the "
               f"round is not clean; see run_agentloop.py's baseline_contamination_note() **" )
    if "note" in out:
        print( f"  {out['note']}" ); return
    print( f"  resolved-rate delta {pct(out['resolved_delta_mean'])}; "
           f"repo-clustered bootstrap 95% lower {pct(out['resolved_delta_bootstrap_95_lower'])} "
           f"(over {out['n_resolved_pairs']} resolution-scored pairs)" )
    print( f"  localization-hit delta {pct(out['localization_hit_delta_mean'])}" )
    print( f"  tokens_out ratio p50/p95 {rat(out['tokens_out_ratio_p50'])}/{rat(out['tokens_out_ratio_p95'])}" )
    print( f"  wall_seconds ratio p50/p95 {rat(out['wall_seconds_ratio_p50'])}/{rat(out['wall_seconds_ratio_p95'])}" )
    print( f"  cost_usd ratio p50/p95 {rat(out['cost_usd_ratio_p50'])}/{rat(out['cost_usd_ratio_p95'])}" )
    def sub( x ): return f"{100*x:.1f}%" if x is not None else "n/a"
    print( f"  substitution rate (ripwire_calls / read+search calls): "
           f"ripwire arm {sub(out.get('substitution_rate_ripwire'))} "
           f"(n={out.get('n_substitution_ripwire', 0)}), "
           f"baseline {sub(out.get('substitution_rate_baseline'))} "
           f"(n={out.get('n_substitution_baseline', 0)})" )
    print(  "    ^ how often the agent reached for ripwire instead of defaulting to a read/grep/glob."
            " Baseline is 0% by construction (no ripwire on PATH); n counts runs where BOTH counts were"
            " measured — unmeasured runs (claude records from before 2026-08-22, unless backfilled) are"
            " excluded rather than scored 0." )

# ── self-test: synthetic fixture, no real run data needed ────────────────────────────────────────────
def _fixture_record( repo, instance_id, seed, arm, resolved, tokens_out, wall_seconds, cost_usd ):
    return dict( instance_id=instance_id, repo=repo, base_commit="deadbeef",
                 arm=arm, seed=seed, harness="fixture", model="fixture",
                 status="ok", resolved=resolved, localization_hit=resolved,
                 tokens_in=1000, tokens_out=tokens_out, wall_seconds=wall_seconds, cost_usd=cost_usd,
                 command_calls=1,
                 ripwire_calls=0 if arm == ARM_BASELINE else 3,
                 ripwire_commands=[] if arm == ARM_BASELINE else [ "ripwire . --for=fixture" ],
                 # 0/4 baseline vs 3/4 treatment — a deterministic, checkable substitution rate. The
                 # baseline reads 4 files and reaches for ripwire zero times (it has none); the
                 # treatment reaches for it 3 of 4 times, i.e. still defaults once.
                 native_read_calls=4 if arm == ARM_BASELINE else 1,
                 events_path=None,
                 error=None, started_unix=0, finished_unix=0 )

def synthetic_fixture():
    # 3 fake repos x 3 instances/repo x seeds 1..3 = 27 pairs. ripwire_cli resolves ~2/3 of the time,
    # baseline ~1/3 — a manufactured, unambiguous positive lift, so the bootstrap lower bound MUST be
    # positive (that's the assertion --self-test checks) and tokens/wall/cost are set to a mild,
    # deterministic ripwire_cli overhead (+8%) so the ratio math has something non-trivial to compute.
    rng = random.Random( "agentloop-selftest-fixture-v1" )
    records = []
    for repo in ( "fake/repoA", "fake/repoB", "fake/repoC" ):
        for i in range( 3 ):
            instance_id = f"{repo.split('/')[1]}-{i}"
            for seed in ( 1, 2, 3 ):
                base_resolved = rng.random() < 1/3   # rng draw order is part of the fixture contract:
                ctx_resolved  = rng.random() < 2/3   # baseline first, treatment second, per (instance, seed)
                records.append( _fixture_record( repo, instance_id, seed, ARM_BASELINE, base_resolved,
                                                 tokens_out=10000, wall_seconds=120.0, cost_usd=0.50 ) )
                records.append( _fixture_record( repo, instance_id, seed, ARM_RIPWIRE, ctx_resolved,
                                                 tokens_out=10800, wall_seconds=129.6, cost_usd=0.54 ) )
    # one deliberately incomplete pair (baseline never finished) — must land in n_incomplete, not paired.
    records.append( dict( instance_id="repoA-orphan", repo="fake/repoA", base_commit="deadbeef",
                          arm=ARM_RIPWIRE, seed=1, harness="fixture", model="fixture", status="ok",
                          resolved=True, localization_hit=True, tokens_in=1000, tokens_out=9000,
                          wall_seconds=100.0, cost_usd=0.4, error=None, started_unix=0, finished_unix=0 ) )
    # one deliberately CONTAMINATED baseline (arm-isolation fix): its ripwire_cli counterpart for the
    # same (instance_id, seed) completed status="ok", proving contamination excludes the pair even when
    # the other side is otherwise complete — status != "ok" on either side is enough, per
    # pair_by_task_seed(), and this must show up as n_contaminated_baseline=1, not silently as just
    # another n_incomplete entry.
    records.append( dict( instance_id="repoB-contam", repo="fake/repoB", base_commit="deadbeef",
                          arm=ARM_BASELINE, seed=1, harness="fixture", model="fixture",
                          status="contaminated",
                          resolved=False, localization_hit=False, tokens_in=1000, tokens_out=9000,
                          wall_seconds=100.0, cost_usd=0.4, command_calls=1, ripwire_calls=1,
                          ripwire_commands=[ "ripwire . --for=oops" ], native_read_calls=0,
                          events_path=None,
                          error="CONTAMINATED: baseline arm invoked ripwire 1 time(s)",
                          started_unix=0, finished_unix=0 ) )
    records.append( dict( instance_id="repoB-contam", repo="fake/repoB", base_commit="deadbeef",
                          arm=ARM_RIPWIRE, seed=1, harness="fixture", model="fixture", status="ok",
                          resolved=True, localization_hit=True, tokens_in=1000, tokens_out=9800,
                          wall_seconds=108.0, cost_usd=0.43, command_calls=1, ripwire_calls=3,
                          ripwire_commands=[ "ripwire . --for=x" ], native_read_calls=1,
                          events_path=None, error=None, started_unix=0, finished_unix=0 ) )
    return records

def self_test():
    records = synthetic_fixture()
    out = analyze( records, n_boot=4000 )
    print_report( out )
    failures = []
    if out["n_pairs"] != 27: failures.append( f"expected 27 paired runs, got {out['n_pairs']}" )
    if out["n_incomplete"] != 2:
        failures.append( f"expected 2 incomplete pairs (the orphan + the contaminated-baseline pair), "
                          f"got {out['n_incomplete']}" )
    if out["n_repos"] != 3: failures.append( f"expected 3 repos, got {out['n_repos']}" )
    if out.get( "n_contaminated_baseline" ) != 1:
        failures.append( f"expected exactly 1 contaminated baseline run counted, "
                          f"got {out.get('n_contaminated_baseline')}" )
    if not ( out["resolved_delta_mean"] > 0 ): failures.append( "expected a positive resolved-rate delta" )
    if not ( out["resolved_delta_bootstrap_95_lower"] > 0 ):
        failures.append( "expected a POSITIVE bootstrap 95% lower bound for a manufactured 1/3 -> 2/3 lift" )
    if out["tokens_out_ratio_p50"] is None or abs( out["tokens_out_ratio_p50"] - 0.08 ) > 1e-6:
        failures.append( f"expected tokens_out ratio p50 == +8.0% exactly (fixture is deterministic), "
                          f"got {out['tokens_out_ratio_p50']}" )
    if out.get( "n_resolved_pairs" ) != 27:
        failures.append( f"expected all 27 pairs resolution-scored, got {out.get('n_resolved_pairs')}" )
    # substitution rate: the fixture pins 0/4 baseline and 3/4 treatment, exactly.
    if out.get( "substitution_rate_baseline" ) != 0.0:
        failures.append( f"expected baseline substitution rate 0.0 (no ripwire on PATH), "
                          f"got {out.get('substitution_rate_baseline')}" )
    if out.get( "substitution_rate_ripwire" ) is None or abs( out["substitution_rate_ripwire"] - 0.75 ) > 1e-9:
        failures.append( f"expected ripwire-arm substitution rate 0.75 exactly (fixture is 3 ripwire / "
                          f"1 native per run), got {out.get('substitution_rate_ripwire')}" )
    if out.get( "n_substitution_ripwire" ) != 27:
        failures.append( f"expected 27 substitution-scored ripwire runs, got {out.get('n_substitution_ripwire')}" )
    # an UNMEASURED run (claude -p: neither count logged) must be excluded, never scored 0.0 — a
    # missing measurement rendered as "defaulted every time" would invert the conclusion.
    blind = [ dict( r, ripwire_calls=None, native_read_calls=None ) for r in records ]
    out3 = analyze( blind, n_boot=100 )
    if out3.get( "substitution_rate_ripwire" ) is not None or out3.get( "n_substitution_ripwire" ) != 0:
        failures.append( "unmeasured substitution counts must report n/a with n=0, not a fabricated rate" )
    # evaluator=none pilot mode: resolved is None in BOTH arms — pairs must still form so the
    # localization/token/wall claims that stage supports remain analyzable; resolved stats say n/a.
    unscored = [ dict( r, resolved=None ) for r in records ]
    out2 = analyze( unscored, n_boot=100 )
    if out2["n_pairs"] != 27:
        failures.append( f"evaluator-none: expected 27 pairs, got {out2['n_pairs']}" )
    if out2["n_resolved_pairs"] != 0:
        failures.append( f"evaluator-none: expected 0 resolution-scored pairs, got {out2['n_resolved_pairs']}" )
    if out2["resolved_delta_mean"] is not None or out2["resolved_delta_bootstrap_95_lower"] is not None:
        failures.append( "evaluator-none: resolved stats must be n/a (None), never a fabricated zero" )
    if out2["tokens_out_ratio_p50"] is None or abs( out2["tokens_out_ratio_p50"] - 0.08 ) > 1e-6:
        failures.append( "evaluator-none: tokens_out ratio must still compute on unscored pairs" )
    if failures:
        print( "\nSELF-TEST FAIL:" )
        for f in failures: print( f"  - {f}" )
        return 1
    print( "\nSELF-TEST PASS: pairing, repo-clustering, bootstrap sign, and ratio math all check out." )
    return 0

def main():
    ap = argparse.ArgumentParser( description=__doc__.split( "\n\n" )[0] if __doc__ else "" )
    ap.add_argument( "--results", default="", help="run_agentloop.py results JSON (schema=%s)" % SCHEMA )
    ap.add_argument( "--bootstrap", type=int, default=10000 )
    ap.add_argument( "--self-test", action="store_true", help="run the synthetic-fixture self-test; no --results needed" )
    a = ap.parse_args()

    if a.self_test:
        return self_test()

    if not a.results:
        raise SystemExit( "--results PATH is required (or pass --self-test to validate the math on a fixture)" )
    data = load_results( a.results )
    out = analyze( data["records"], n_boot=a.bootstrap )
    print_report( out )
    return 0

if __name__ == "__main__":
    sys.exit( main() )
