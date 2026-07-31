#!/usr/bin/env python3
# analyze.py — paired per-task/seed analysis for Phase B4 agent-in-the-loop eval results.
#
# WHAT THIS DOES. Consumes the record schema written by run_agentloop.py (SCHEMA
# "ripwire-agentloop-results-v1") and computes paired arm deltas (baseline vs ripwire_mcp) per
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
# instances/seeds with a manufactured resolved-rate lift for ripwire_mcp) and asserts the pipeline
# produces the expected sign and a positive bootstrap lower bound — proves the math runs correctly
# without needing any real (paid) run data.
#
# USAGE:
#   python3 bench/agentloop/analyze.py --self-test
#   python3 bench/agentloop/analyze.py --results results.json
import argparse, json, math, pathlib, random, statistics, sys

SCHEMA = "ripwire-agentloop-results-v1"
ARM_BASELINE, ARM_RIPWIRE = "baseline", "ripwire_mcp"

def mean( xs ): return sum( xs ) / len( xs ) if xs else 0.0

def load_results( path ):
    data = json.loads( pathlib.Path( path ).read_text() )
    if data.get( "schema" ) != SCHEMA:
        raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expected {SCHEMA!r}); refusing" )
    return data

def pair_by_task_seed( records ):
    """Group records by (instance_id, seed, arm); return list of (instance_id, repo, seed, base_rec, ctx_rec)
    for pairs where BOTH arms have status=='ok' (a completed run with real metrics). Anything else — a
    stub/not_implemented/errored run, or a one-sided completion — is reported separately, never silently
    dropped into the paired set (that would bias the paired comparison toward whichever arm happened to
    finish more often)."""
    by_key = {}
    for r in records:
        by_key.setdefault( ( r["instance_id"], r["seed"] ), {} )[ r["arm"] ] = r
    paired, incomplete = [], []
    for ( instance_id, seed ), arms in sorted( by_key.items() ):
        base, ctx = arms.get( ARM_BASELINE ), arms.get( ARM_RIPWIRE )
        if base and ctx and base["status"] == "ok" and ctx["status"] == "ok" \
           and base["resolved"] is not None and ctx["resolved"] is not None:
            paired.append( ( instance_id, base["repo"], seed, base, ctx ) )
        else:
            incomplete.append( ( instance_id, seed,
                                 base["status"] if base else "missing", ctx["status"] if ctx else "missing" ) )
    return paired, incomplete

def clustered_bootstrap_lower( pairs, value_fn, n_boot, seed_str, alpha=0.025 ):
    """Repository-clustered paired bootstrap (see module docstring / bench/locbench/compare_runs.py
    for the source method): resample REPOS with replacement len(repos) times per bootstrap draw, pool
    every paired value belonging to the sampled repos, take the mean; repeat n_boot times; return the
    alpha-quantile (default 2.5% => a 95% one-sided lower bound)."""
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

def analyze( records, n_boot=10000, bootstrap_seed="ripwire-b4-agentloop-bootstrap-v1" ):
    paired, incomplete = pair_by_task_seed( records )
    repos = sorted( { repo for _, repo, *_ in paired } )
    out = dict( n_pairs=len( paired ), n_repos=len( repos ), n_incomplete=len( incomplete ) )
    if not paired:
        out["note"] = "zero complete paired (baseline,ripwire_mcp) runs — nothing to analyze yet"
        return out
    rdeltas = [ resolved_delta( b, c ) for *_ , b, c in paired ]
    ldeltas = [ loc_hit_delta( b, c ) for *_ , b, c in paired ]
    lower, _ = clustered_bootstrap_lower( paired, resolved_delta, n_boot, bootstrap_seed )
    tok_p50, tok_p95 = paired_ratio( paired, "tokens_out" )
    wall_p50, wall_p95 = paired_ratio( paired, "wall_seconds" )
    cost_p50, cost_p95 = paired_ratio( paired, "cost_usd" )
    out.update(
        resolved_delta_mean=mean( rdeltas ),
        resolved_delta_bootstrap_95_lower=lower,
        localization_hit_delta_mean=mean( ldeltas ),
        tokens_out_ratio_p50=tok_p50, tokens_out_ratio_p95=tok_p95,
        wall_seconds_ratio_p50=wall_p50, wall_seconds_ratio_p95=wall_p95,
        cost_usd_ratio_p50=cost_p50, cost_usd_ratio_p95=cost_p95,
    )
    return out

def print_report( out ):
    def pct( x ): return f"{100*x:+.2f}pp" if x is not None else "n/a"
    def rat( x ): return f"{100*x:+.1f}%" if x is not None else "n/a"
    print( f"paired agentloop analysis: n_pairs={out['n_pairs']} n_repos={out['n_repos']} "
           f"n_incomplete={out['n_incomplete']}" )
    if "note" in out:
        print( f"  {out['note']}" ); return
    print( f"  resolved-rate delta {pct(out['resolved_delta_mean'])}; "
           f"repo-clustered bootstrap 95% lower {pct(out['resolved_delta_bootstrap_95_lower'])}" )
    print( f"  localization-hit delta {pct(out['localization_hit_delta_mean'])}" )
    print( f"  tokens_out ratio p50/p95 {rat(out['tokens_out_ratio_p50'])}/{rat(out['tokens_out_ratio_p95'])}" )
    print( f"  wall_seconds ratio p50/p95 {rat(out['wall_seconds_ratio_p50'])}/{rat(out['wall_seconds_ratio_p95'])}" )
    print( f"  cost_usd ratio p50/p95 {rat(out['cost_usd_ratio_p50'])}/{rat(out['cost_usd_ratio_p95'])}" )

# ── self-test: synthetic fixture, no real run data needed ────────────────────────────────────────────
def synthetic_fixture():
    # 3 fake repos x 3 instances/repo x seeds 1..3 = 27 pairs. ripwire_mcp resolves ~2/3 of the time,
    # baseline ~1/3 — a manufactured, unambiguous positive lift, so the bootstrap lower bound MUST be
    # positive (that's the assertion --self-test checks) and tokens/wall/cost are set to a mild,
    # deterministic ripwire_mcp overhead (+8%) so the ratio math has something non-trivial to compute.
    rng = random.Random( "agentloop-selftest-fixture-v1" )
    repos = [ "fake/repoA", "fake/repoB", "fake/repoC" ]
    records = []
    for repo in repos:
        for i in range( 3 ):
            instance_id = f"{repo.split('/')[1]}-{i}"
            for seed in ( 1, 2, 3 ):
                base_resolved = rng.random() < 1/3
                ctx_resolved  = rng.random() < 2/3
                base_tokens, ctx_tokens = 10000, 10800
                base_wall, ctx_wall = 120.0, 129.6
                base_cost, ctx_cost = 0.50, 0.54
                for arm, resolved, tokens, wall, cost in (
                    ( ARM_BASELINE, base_resolved, base_tokens, base_wall, base_cost ),
                    ( ARM_RIPWIRE,  ctx_resolved,  ctx_tokens,  ctx_wall,  ctx_cost ),
                ):
                    records.append( dict(
                        instance_id=instance_id, repo=repo, base_commit="deadbeef",
                        arm=arm, seed=seed, harness="fixture", model="fixture",
                        status="ok", resolved=resolved, localization_hit=resolved,
                        tokens_in=1000, tokens_out=tokens, wall_seconds=wall, cost_usd=cost,
                        error=None, started_unix=0, finished_unix=0 ) )
    # one deliberately incomplete pair (baseline never finished) — must land in n_incomplete, not paired.
    records.append( dict( instance_id="repoA-orphan", repo="fake/repoA", base_commit="deadbeef",
                          arm=ARM_RIPWIRE, seed=1, harness="fixture", model="fixture", status="ok",
                          resolved=True, localization_hit=True, tokens_in=1000, tokens_out=9000,
                          wall_seconds=100.0, cost_usd=0.4, error=None, started_unix=0, finished_unix=0 ) )
    return records

def self_test():
    records = synthetic_fixture()
    out = analyze( records, n_boot=4000 )
    print_report( out )
    failures = []
    if out["n_pairs"] != 27: failures.append( f"expected 27 paired runs, got {out['n_pairs']}" )
    if out["n_incomplete"] != 1: failures.append( f"expected 1 incomplete pair, got {out['n_incomplete']}" )
    if out["n_repos"] != 3: failures.append( f"expected 3 repos, got {out['n_repos']}" )
    if not ( out["resolved_delta_mean"] > 0 ): failures.append( "expected a positive resolved-rate delta" )
    if not ( out["resolved_delta_bootstrap_95_lower"] > 0 ):
        failures.append( "expected a POSITIVE bootstrap 95% lower bound for a manufactured 1/3 -> 2/3 lift" )
    if out["tokens_out_ratio_p50"] is None or abs( out["tokens_out_ratio_p50"] - 0.08 ) > 1e-6:
        failures.append( f"expected tokens_out ratio p50 == +8.0% exactly (fixture is deterministic), "
                          f"got {out['tokens_out_ratio_p50']}" )
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
