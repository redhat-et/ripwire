#!/usr/bin/env python3
# compare_cpp.py — R1-cpp acceptance comparator (GATE_DECISION_r1cpp.md, applied mechanically).
#
# Modes:
#   * default: held-out C++ gate — paired quality deltas over two run_multiswe.py JSONs, repo-clustered
#     bootstrap 95% LB of the strict file@10 delta, plus the two-tier verdict when --timing is given
#     (timing_multiswe.py JSON: per-instance baseline/candidate arms, 5 warm + cold + tokens).
#   * --python-guard: LocBench no-regression guard — paired strict@10 delta over two run_locbench.py
#     JSONs (arm `for`), guard = mean >= -1.0pp AND the repo-clustered 95% CI not entirely below 0.
#
# All gate numbers are pre-registered in GATE_DECISION_r1cpp.md and hardcoded here on purpose:
# tier1 warm/cold p95 ceilings 775/1650 ms (A7), tier2 R=2.5 with weights 0.5 warm-p50 / 0.5 token-p50,
# bootstrap 10,000 deterministic resamples seeded 20260722, cluster = repository.
import argparse, json, math, random, sys

SEED, BOOT = 20260722, 10000
ABS_WARM_P95_MS, ABS_COLD_P95_MS, MIN_R = 775.0, 1650.0, 2.5
W_WARM, W_TOKEN = 0.5, 0.5


def hit( arm_row, key, k ):
    v = arm_row.get( key )
    return v is not None and v < k


def load_rows( path, arm ):
    d = json.loads( open( path ).read() )
    rows = d.get( "instances" ) or d.get( "per_instance" )
    out = []
    for r in rows:
        rid = r.get( "instance_id" ) or r.get( "sha" )
        # multiswe rows carry org+repo; locbench rows carry repo; cppbench rows are one corpus (source_repo)
        repo = ( r["org"] + "/" + r["repo"] ) if "org" in r else r.get( "repo", d.get( "source_repo", "corpus" ) )
        out.append( dict( id=rid, repo=repo, primary=tuple( r.get( "primary_files", () ) ),
                          gold=tuple( r.get( "gold_files", () ) ), arm=r["arms"][arm] ) )
    return out


def contract( base, cand ):
    if len( base ) != len( cand ):
        sys.exit( f"CONTRACT REFUSAL: instance-count mismatch {len(base)} vs {len(cand)}" )
    for b, c in zip( base, cand ):
        if b["id"] != c["id"] or b["repo"] != c["repo"] or b["primary"] != c["primary"] or b["gold"] != c["gold"]:
            sys.exit( f"CONTRACT REFUSAL: row mismatch at {b['id']} vs {c['id']}" )


def cluster_bootstrap( deltas, clusters, lo_pct=2.5, hi_pct=97.5 ):
    # repo-clustered paired bootstrap: resample CLUSTERS with replacement, mean of the concatenated
    # per-instance deltas; deterministic seed. Returns (lb, ub, means_sorted_for_debug_len).
    byc = {}
    for d, c in zip( deltas, clusters ): byc.setdefault( c, [] ).append( d )
    keys = sorted( byc )
    rng  = random.Random( SEED )
    means = []
    for _ in range( BOOT ):
        picked = [ byc[ keys[ rng.randrange( len( keys ) ) ] ] for _ in range( len( keys ) ) ]
        flat   = [ x for grp in picked for x in grp ]
        means.append( sum( flat ) / len( flat ) )
    means.sort()
    lo = means[ max( 0, math.ceil( lo_pct / 100.0 * BOOT ) - 1 ) ]
    hi = means[ max( 0, math.ceil( hi_pct / 100.0 * BOOT ) - 1 ) ]
    return lo, hi


def paired_ratio_p( base_vals, cand_vals, pct ):
    ratios = sorted( c / b for b, c in zip( base_vals, cand_vals ) if b > 0 )
    return ratios[ max( 0, math.ceil( pct / 100.0 * len( ratios ) ) - 1 ) ]


def pop_p95( vals ):
    s = sorted( vals )
    return s[ max( 0, math.ceil( 0.95 * len( s ) ) - 1 ) ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--baseline", required=True )
    ap.add_argument( "--candidate", required=True )
    ap.add_argument( "--arm", default="for" )
    ap.add_argument( "--timing", default="", help="timing_multiswe.py JSON (enables the two-tier verdict)" )
    ap.add_argument( "--python-guard", action="store_true" )
    a = ap.parse_args()

    base = load_rows( a.baseline, a.arm ); cand = load_rows( a.candidate, a.arm )
    contract( base, cand )
    n = len( base )
    repos = sorted( { b["repo"] for b in base } )
    print( f"paired R1-cpp: arm={a.arm} n={n} repos={len(repos)}" )

    def pct_delta( key, k ):
        db = sum( hit( b["arm"], key, k ) for b in base )
        dc = sum( hit( c["arm"], key, k ) for c in cand )
        return ( dc - db ) / n * 100.0, db / n * 100.0, dc / n * 100.0

    for k in ( 1, 3, 5, 10 ):
        d, ab, ac = pct_delta( "file_worst", k )
        print( f"  strict file@{k}: {ab:.1f}% -> {ac:.1f}% ({d:+.2f}pp)" )
    d, ab, ac = pct_delta( "file_first", 10 )
    print( f"  lenient any@10: {ab:.1f}% -> {ac:.1f}% ({d:+.2f}pp)" )
    mb = sum( 1.0 / ( b["arm"]["file_first"] + 1 ) for b in base if b["arm"]["file_first"] is not None ) / n
    mc = sum( 1.0 / ( c["arm"]["file_first"] + 1 ) for c in cand if c["arm"]["file_first"] is not None ) / n
    print( f"  first-hit MRR: {mb:.4f} -> {mc:.4f} ({mc-mb:+.4f})" )

    # strata
    for label, pred in ( ( "single-file", lambda b: len( b["primary"] ) == 1 ), ( "multi-file", lambda b: len( b["primary"] ) > 1 ) ):
        idx = [ i for i in range( n ) if pred( base[i] ) ]
        if not idx: continue
        db = sum( hit( base[i]["arm"], "file_worst", 10 ) for i in idx )
        dc = sum( hit( cand[i]["arm"], "file_worst", 10 ) for i in idx )
        print( f"  {label} strict@10 (n={len(idx)}): {db/len(idx)*100:.1f}% -> {dc/len(idx)*100:.1f}% ({(dc-db)/len(idx)*100:+.2f}pp)" )

    deltas   = [ ( 1 if hit( c["arm"], "file_worst", 10 ) else 0 ) - ( 1 if hit( b["arm"], "file_worst", 10 ) else 0 )
                 for b, c in zip( base, cand ) ]
    clusters = [ b["repo"] for b in base ]
    mean = sum( deltas ) / n * 100.0
    lb, ub = cluster_bootstrap( [ d * 100.0 for d in deltas ], clusters )
    slb, sub = cluster_bootstrap( [ d * 100.0 for d in deltas ], list( range( n ) ) )
    print( f"  strict@10 delta {mean:+.2f}pp; repo-clustered ({len(repos)} clusters) bootstrap 95% CI [{lb:+.2f}, {ub:+.2f}]pp" )
    print( f"  (sensitivity, NOT the acceptance number: instance-level bootstrap 95% CI [{slb:+.2f}, {sub:+.2f}]pp)" )

    if a.python_guard:
        okmean = mean >= -1.0
        okci   = not ( ub < 0 )
        print( f"  [python-guard] mean {mean:+.2f}pp >= -1.0pp: {'PASS' if okmean else 'FAIL'}; "
               f"95% CI upper {ub:+.2f}pp not entirely below 0: {'PASS' if okci else 'FAIL'}" )
        print( "GUARD HOLDS" if okmean and okci else "GUARD FAILS" )
        sys.exit( 0 if okmean and okci else 4 )

    if not a.timing:
        print( "(no --timing: quality report only — the two-tier verdict needs the timing JSON)" )
        return

    t = json.loads( open( a.timing ).read() )
    trows = t["instances"]
    tmap  = { r["instance_id"]: r for r in trows }
    ids   = [ b["id"] for b in base ]
    missing = [ i for i in ids if i not in tmap ]
    if missing: sys.exit( f"CONTRACT REFUSAL: timing JSON missing {len(missing)} instances (e.g. {missing[:3]})" )

    warm_p95_ms = 1000.0 * pop_p95( [ tmap[i]["arms"]["candidate"]["wall_p95"] for i in ids ] )
    cold_p95_ms = 1000.0 * pop_p95( [ tmap[i]["arms"]["candidate"]["cold_wall"] for i in ids ] )
    tier1 = warm_p95_ms <= ABS_WARM_P95_MS and cold_p95_ms <= ABS_COLD_P95_MS

    warm_delta  = ( paired_ratio_p( [ tmap[i]["arms"]["baseline"]["wall_median"] for i in ids ],
                                    [ tmap[i]["arms"]["candidate"]["wall_median"] for i in ids ], 50 ) - 1.0 ) * 100.0
    token_delta = ( paired_ratio_p( [ tmap[i]["arms"]["baseline"]["output_tokens_ceiling"] for i in ids ],
                                    [ tmap[i]["arms"]["candidate"]["output_tokens_ceiling"] for i in ids ], 50 ) - 1.0 ) * 100.0
    warm_p95_delta = ( paired_ratio_p( [ tmap[i]["arms"]["baseline"]["wall_p95"] for i in ids ],
                                       [ tmap[i]["arms"]["candidate"]["wall_p95"] for i in ids ], 95 ) - 1.0 ) * 100.0
    cost = W_WARM * warm_delta + W_TOKEN * token_delta
    print( f"  warm latency p50 delta {warm_delta:+.1f}%; p95 delta {warm_p95_delta:+.1f}%; token ceiling p50 delta {token_delta:+.1f}%" )
    print( f"  [two-tier] tier1 absolute SLA: warm p95 {warm_p95_ms:.1f}ms (ceiling {ABS_WARM_P95_MS:.1f}ms) "
           f"{'PASS' if warm_p95_ms <= ABS_WARM_P95_MS else 'FAIL'}; cold p95 {cold_p95_ms:.1f}ms (ceiling {ABS_COLD_P95_MS:.1f}ms) "
           f"{'PASS' if cold_p95_ms <= ABS_COLD_P95_MS else 'FAIL'}" )
    if cost <= 0:
        tier2 = lb > 0
        print( f"  [two-tier] tier2 utility: weighted cost delta {cost:+.2f}% <= 0 (Pareto rule) -> quality LB {lb:+.2f}pp > 0: {'PASS' if tier2 else 'FAIL'}" )
    else:
        ratio = lb / cost if cost > 0 else float( "inf" )
        tier2 = ratio >= MIN_R
        print( f"  [two-tier] tier2 utility: quality LB {lb:+.2f}pp / weighted cost delta {cost:+.2f}% "
               f"(weights warm={W_WARM} token={W_TOKEN}) = {ratio:.3f} vs min {MIN_R} {'PASS' if tier2 else 'FAIL'}" )
    print( "ACCEPT" if tier1 and tier2 else "REJECT" )
    sys.exit( 0 if tier1 and tier2 else 4 )


if __name__ == "__main__":
    main()
