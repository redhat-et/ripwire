#!/usr/bin/env python3
"""Paired A7 acceptance test for two corrected LocBench JSON runs."""
import argparse, json, math, random, statistics, sys

def hit( row, arm, key, k=10 ):
    v = row["arms"][arm][key]
    return v is not None and v < k

def mrr( row, arm ):
    v = row["arms"][arm]["func_first"]
    return 0.0 if v is None else 1.0 / ( v + 1 )

def mean( xs ): return sum( xs ) / len( xs ) if xs else 0.0

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "before" ); ap.add_argument( "after" )
    ap.add_argument( "--arm", default="anchor" )
    ap.add_argument( "--bootstrap", type=int, default=10000 )
    ap.add_argument( "--enforce", action="store_true" )
    # Two-tier gate (opt-in, R4 Phase B1). Default stays "legacy": with no new
    # flags passed, output and exit code are byte-identical to the pre-existing flat-AND predicate. See
    # bench/locbench/GATE_DECISION.md for the rationale and proposed (not yet decided) default numbers.
    ap.add_argument( "--gate", choices=( "legacy", "two-tier" ), default="legacy" )
    ap.add_argument( "--abs-warm-p95-ms", type=float, default=None,
                      help="tier 1: hard ceiling on the candidate's absolute warm p95 latency, in ms" )
    ap.add_argument( "--abs-cold-p95-ms", type=float, default=None,
                      help="tier 1: hard ceiling on the candidate's absolute cold p95 latency, in ms" )
    ap.add_argument( "--min-quality-per-cost", type=float, default=None,
                      help="tier 2: minimum acceptable (quality LB) / (weighted cost delta) ratio" )
    ap.add_argument( "--cost-weight-warm", type=float, default=0.5,
                      help="tier 2: weight of warm p50 latency delta in the cost scalar (sane default)" )
    ap.add_argument( "--cost-weight-token", type=float, default=0.5,
                      help="tier 2: weight of token p50 delta in the cost scalar (sane default)" )
    a = ap.parse_args()
    if a.gate == "two-tier" and ( a.abs_warm_p95_ms is None or a.abs_cold_p95_ms is None or a.min_quality_per_cost is None ):
        raise SystemExit( "--gate=two-tier requires --abs-warm-p95-ms, --abs-cold-p95-ms, and --min-quality-per-cost "
                           "(no built-in default: these are a policy choice pending policy review, see GATE_DECISION.md)" )
    before, after = json.load( open( a.before ) ), json.load( open( a.after ) )
    for key in ( "dataset", "split", "split_contract" ):
        if before.get(key) != after.get(key): raise SystemExit( f"{key} differs; paired comparison refused" )
    if before.get("skipped") != after.get("skipped"): raise SystemExit( "exclusion counts differ; paired comparison refused" )
    b = { r["instance_id"]: r for r in before["instances"] }
    n = { r["instance_id"]: r for r in after["instances"] }
    if b.keys() != n.keys(): raise SystemExit( "instance sets differ; paired comparison refused" )
    ids = sorted( b )
    if len( ids ) < 100: raise SystemExit( f"held-out N={len(ids)} < 100" )
    for i in ids:
        for key in ( "repo", "gold_files", "primary_files", "gold_funcs" ):
            if b[i].get(key) != n[i].get(key): raise SystemExit( f"{i}: {key} differs; paired comparison refused" )

    strict_delta = [ float( hit( n[i],a.arm,"file_worst" ) ) - float( hit( b[i],a.arm,"file_worst" ) ) for i in ids ]
    strict_by_id = dict( zip( ids, strict_delta ) )
    lenient_delta = [ float( hit( n[i],a.arm,"file_first" ) ) - float( hit( b[i],a.arm,"file_first" ) ) for i in ids ]
    mrr_delta = [ mrr( n[i],a.arm ) - mrr( b[i],a.arm ) for i in ids ]
    multi = [ i for i in ids if len( b[i]["primary_files"] ) > 1 ]
    single = [ i for i in ids if len( b[i]["primary_files"] ) == 1 ]
    multi_delta = [ float( hit( n[i],a.arm,"file_worst" ) ) - float( hit( b[i],a.arm,"file_worst" ) ) for i in multi ]
    def category_delta( group, key ):
        return mean( [ float( hit( n[i],a.arm,key ) ) - float( hit( b[i],a.arm,key ) ) for i in group ] )

    # Repository-clustered paired bootstrap. Multiple issues from one project are not independent trials.
    repos = sorted( { b[i]["repo"] for i in ids } )
    by_repo = { r:[ i for i in ids if b[i]["repo"] == r ] for r in repos }
    rng = random.Random( "ripwire-a7-bootstrap-v1" )
    boots = []
    for _ in range( a.bootstrap ):
        sampled = [ rng.choice( repos ) for _ in repos ]
        vals = [ strict_by_id[i] for r in sampled for i in by_repo[r] ]
        boots.append( mean( vals ) )
    boots.sort(); lower = boots[ max( 0, int( 0.025 * len( boots ) ) ) ]

    def pct( x ): return f"{100*x:+.2f}pp"
    print( f"paired corrected LocBench: arm={a.arm} n={len(ids)} repos={len(repos)}" )
    print( f"  strict file@10 delta {pct(mean(strict_delta))}; clustered bootstrap 95% lower {pct(lower)}" )
    print( f"  lenient file@10 delta {pct(mean(lenient_delta))}; symbol MRR delta {mrr_delta and mean(mrr_delta):+.4f}" )
    print( f"  multi-file strict@10 delta {pct(mean(multi_delta))} (n={len(multi)})" )
    bm, am = before["arms"][a.arm], after["arms"][a.arm]
    # Cost is paired by issue just like quality. A ratio of independent corpus quantiles can compare different
    # repositories on each side and hide (or invent) a regression when repo-size mix is broad.
    def paired_ratio_quantiles( field ):
        ratios = sorted( n[i]["arms"][a.arm].get(field,0) / b[i]["arms"][a.arm].get(field,0) - 1
                         for i in ids if b[i]["arms"][a.arm].get(field,0) > 0 )
        if len( ratios ) != len( ids ): return 0.0, 0.0
        p50 = statistics.median( ratios )
        p95 = ratios[ max( 0, math.ceil( .95 * len( ratios ) ) - 1 ) ]
        return p50, p95
    wall_delta, p95_delta = paired_ratio_quantiles( "wall_median" )[0], paired_ratio_quantiles( "wall_p95" )[1]
    token_p50, token_p95 = paired_ratio_quantiles( "output_tokens_ceiling" )
    cold_p50, cold_p95 = paired_ratio_quantiles( "cold_wall" )
    index_p50, index_p95 = paired_ratio_quantiles( "index_wall" )
    single_strict, single_lenient = category_delta(single,"file_worst"), category_delta(single,"file_first")
    multi_strict, multi_lenient = category_delta(multi,"file_worst"), category_delta(multi,"file_first")
    b_all_n = bm["n"] + before.get("skipped",{}).get("unindexable",0)
    a_all_n = am["n"] + after.get("skipped",{}).get("unindexable",0)
    allpatch_delta = am["allf10"] / a_all_n - bm["allf10"] / b_all_n
    print( f"  warm latency p50 delta {100*wall_delta:+.1f}%; p95 delta {100*p95_delta:+.1f}%" )
    print( f"  production payload token ceiling p50 {100*token_p50:+.1f}%; p95 {100*token_p95:+.1f}%" )
    print( f"  cold p50/p95 {100*cold_p50:+.1f}%/{100*cold_p95:+.1f}%; index p50/p95 {100*index_p50:+.1f}%/{100*index_p95:+.1f}%" )
    print( f"  category deltas single strict/lenient {pct(single_strict)}/{pct(single_lenient)}; multi {pct(multi_strict)}/{pct(multi_lenient)}" )
    print( f"  all-patch secondary strict@10 delta {pct(allpatch_delta)} (zero-primary rows count as failures)" )

    ok = mean(strict_delta) >= 0.02 and lower > 0 and mean(lenient_delta) >= -0.005 \
         and mean(mrr_delta) >= -0.005 and mean(multi_delta) >= -0.005 \
         and wall_delta <= 0.05 and p95_delta <= 0.10 and token_p50 <= 0.05 and token_p95 <= 0.05 \
         and cold_p50 <= 0.05 and cold_p95 <= 0.10 and index_p50 <= 0.05 and index_p95 <= 0.10 \
         and min( single_strict, single_lenient, multi_strict, multi_lenient ) >= -0.02 and allpatch_delta >= -0.005

    # Two-tier gate (opt-in). Tier 1 is an ABSOLUTE interactive-SLA ceiling on the candidate's own latency
    # (never relative to baseline, so the ceiling cannot drift release over release). Tier 2 is a soft utility
    # test: does the clustered-bootstrap lower bound of the quality gain clear a minimum return per unit of
    # weighted cost. Legacy report lines above are unchanged and still printed so the two runs stay comparable.
    if a.gate == "two-tier":
        def p95_of( vals ):
            vals = sorted( vals )
            return vals[ max( 0, math.ceil( .95 * len( vals ) ) - 1 ) ] if vals else 0.0
        warm_p95_abs_ms = 1000 * p95_of( n[i]["arms"][a.arm].get( "wall_p95", 0.0 ) for i in ids )
        cold_p95_abs_ms = 1000 * p95_of( n[i]["arms"][a.arm].get( "cold_wall", 0.0 ) for i in ids )
        tier1_warm_ok = warm_p95_abs_ms <= a.abs_warm_p95_ms
        tier1_cold_ok = cold_p95_abs_ms <= a.abs_cold_p95_ms
        tier1_ok = tier1_warm_ok and tier1_cold_ok

        quality_lb = lower  # 95% clustered-bootstrap lower bound of the mean strict file@10 delta, already computed above
        weighted_cost_delta = a.cost_weight_warm * wall_delta + a.cost_weight_token * token_p50
        if weighted_cost_delta <= 0:
            # Quality up (or flat), cost flat or down: Pareto-dominant, auto-accept on tier 2 iff quality improved.
            quality_per_cost = math.inf if quality_lb > 0 else -math.inf
            tier2_ok = quality_lb > 0
        else:
            quality_per_cost = quality_lb / max( 0.0, weighted_cost_delta )
            tier2_ok = quality_per_cost >= a.min_quality_per_cost
        two_tier_ok = tier1_ok and tier2_ok

        qpc_str = "inf" if math.isinf( quality_per_cost ) and quality_per_cost > 0 else \
                  "-inf" if math.isinf( quality_per_cost ) else f"{quality_per_cost:.3f}"
        print( f"  [two-tier] tier1 absolute SLA: warm p95 {warm_p95_abs_ms:.1f}ms (ceiling {a.abs_warm_p95_ms:.1f}ms) "
               f"{'PASS' if tier1_warm_ok else 'FAIL'}; cold p95 {cold_p95_abs_ms:.1f}ms (ceiling {a.abs_cold_p95_ms:.1f}ms) "
               f"{'PASS' if tier1_cold_ok else 'FAIL'}" )
        print( f"  [two-tier] tier2 utility: quality LB {pct(quality_lb)} / weighted cost delta {100*weighted_cost_delta:+.2f}% "
               f"(weights warm={a.cost_weight_warm} token={a.cost_weight_token}) = {qpc_str} vs min {a.min_quality_per_cost} "
               f"{'PASS' if tier2_ok else 'FAIL'}" )
        ok = two_tier_ok

    if a.enforce:
        for row in list(b.values()) + list(n.values()):
            arm = row["arms"][a.arm]
            if arm.get("cold_wall",0) <= 0 or arm.get("index_wall",0) <= 0:
                raise SystemExit( "release comparison requires positive cold/index measurements on every row" )
    print( "ACCEPT" if ok else "REJECT" )
    if a.enforce and not ok: return 1
    return 0

if __name__ == "__main__": sys.exit( main() )
