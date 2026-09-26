#!/usr/bin/env python3
# analyze.py — §5.6 pooling, the repository-cluster bootstrap, §6's pass/fail and C1 decision, and §7's power
# arithmetic (used before freeze to read what a pilot SD implies for A3).
#
# Input: {repo: {window: {arm: {popt, recall20, ...}}}} (one label rule), as runrepo.py writes per repository.
# Deterministic: the bootstrap draws from random.Random(BOOTSTRAP_SEED); repositories are sorted first.
import math, random, statistics, sys, os

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
import common


def per_repo_means( table, metric="popt" ):
    """{repo: {arm: mean over the repo's valid windows}} — a window is valid for an arm when its value exists."""
    out = {}
    for repo in sorted( table ):
        acc = {}
        for win in sorted( table[ repo ] ):
            for arm, v in table[ repo ][ win ].items():
                if isinstance( v, dict ) and v.get( metric ) is not None:
                    acc.setdefault( arm, [] ).append( v[ metric ] )
        out[ repo ] = { arm: sum( vs ) / len( vs ) for arm, vs in acc.items() }
    return out


def deltas( means, a, b ):
    """Per-repository Δ(a, b) for repos where both exist, sorted by repo."""
    return [ ( r, means[ r ][ a ] - means[ r ][ b ] ) for r in sorted( means ) if a in means[ r ] and b in means[ r ] ]


def bootstrap_ci( values, level=0.95, resamples=common.BOOTSTRAP_RESAMPLES, seed=common.BOOTSTRAP_SEED ):
    """Percentile CI of the mean over repository-cluster resamples."""
    rng = random.Random( seed )
    n = len( values )
    stats = sorted( sum( values[ rng.randrange( n ) ] for _ in range( n ) ) / n for _ in range( resamples ) )
    lo = stats[ int( math.floor( ( 1 - level ) / 2 * resamples ) ) ]
    hi = stats[ min( resamples - 1, int( math.ceil( ( 1 + level ) / 2 * resamples ) ) - 1 ) ]
    return lo, hi


def beats( means_popt, means_recall, a, b, level=0.95 ):
    """§6.1's four conditions for "a beats b"."""
    d = [ v for _, v in deltas( means_popt, a, b ) ]
    dr = [ v for _, v in deltas( means_recall, a, b ) ]
    if not d:
        return dict( ok=False, reason="no data" )
    lo, hi = bootstrap_ci( d, level )
    point = sum( d ) / len( d )
    point_r = sum( dr ) / len( dr ) if dr else None
    sign = sum( 1 for v in d if v > 0 ) / len( d )
    conds = dict( a_ci_lower_gt0=lo > 0, b_point_ge_m=point >= common.MARGIN_M, c_recall_ge0=( point_r is not None and point_r >= 0 ),
                  d_sign_ge60=sign >= common.SIGN_CONSISTENCY )
    return dict( ok=all( conds.values() ), point=point, ci=( lo, hi ), recall_point=point_r, sign=sign, n=len( d ),
                 sd=statistics.stdev( d ) if len( d ) > 1 else None, **conds )


# ── §7 power, normal approximation (the registration's own arithmetic) ──────────────────────────────────
def _phi( z ):
    return 0.5 * ( 1 + math.erf( z / math.sqrt( 2 ) ) )


def _binom_tail( n, p, k ):
    return sum( math.comb( n, i ) * p ** i * ( 1 - p ) ** ( n - i ) for i in range( k, n + 1 ) )


def power( sd, n, true_delta, z=1.96, m=common.MARGIN_M, sign=common.SIGN_CONSISTENCY ):
    """P(declare "beats") ≈ P(point ≥ max(m, z·SE)) × P(≥ sign·n repositories with Δ > 0)."""
    se = sd / math.sqrt( n )
    p_ab = 1 - _phi( ( max( m, z * se ) - true_delta ) / se )
    p_d = _binom_tail( n, _phi( true_delta / sd ), math.ceil( sign * n ) )
    return p_ab * p_d


def sd_ci( s, n, level=0.95 ):
    """Chi-square CI for a normal SD from a sample SD s on n points (df = n - 1), tabulated for df 1..5."""
    chi = { 1: ( 0.000982, 5.0239 ), 2: ( 0.0506, 7.3778 ), 3: ( 0.2158, 9.3484 ), 4: ( 0.4844, 11.1433 ), 5: ( 0.8312, 12.8325 ) }
    lo_q, hi_q = chi[ n - 1 ]
    return s * math.sqrt( ( n - 1 ) / hi_q ), s * math.sqrt( ( n - 1 ) / lo_q )


def n_for_power( sd, true_delta, target=0.80, nmax=200 ):
    for n in range( 3, nmax + 1 ):
        if power( sd, n, true_delta ) >= target:
            return n
    return None


# ── CLI: the pre-freeze SD pilot readout ────────────────────────────────────────────────────────────────
def sd_pilot( outdirs, contrasts=( ( "HOT", "RANDOM" ), ( "HOT", "CCX" ), ( "HOT", "FANIN" ) ) ):
    """Reads each runrepo OUTDIR (manifest.json + scores.json), takes its PRIMARY rule, and prints per-repo
    Δ Popt per contrast, the between-repository SD with its chi-square CI, and what that SD implies for §7."""
    import json
    table, rows = {}, []
    for d in outdirs:
        m = json.load( open( os.path.join( d, "manifest.json" ) ) )
        s = json.load( open( os.path.join( d, m[ "scores_file" ] ) ) )
        rule = m[ "primary_rule" ]
        table[ m[ "full_name" ] ] = { w: s[ w ][ rule ] for w in s if rule in s[ w ] and "dropped" not in s[ w ][ rule ] }
        rows.append( ( m[ "full_name" ], rule, { w: ( s[ w ].get( "dropped" ) or s[ w ].get( rule, {} ).get( "dropped" ) ) for w in s } ) )
    mp = per_repo_means( table, "popt" )
    out = dict( repos=rows, contrasts={} )
    for a, b in contrasts:
        d = deltas( mp, a, b )
        vals = [ v for _, v in d ]
        sd = statistics.stdev( vals ) if len( vals ) > 1 else None
        out[ "contrasts" ][ "%s-%s" % ( a, b ) ] = dict(
            per_repo={ r: round( v, 4 ) for r, v in d }, mean=round( sum( vals ) / len( vals ), 4 ) if vals else None,
            sd=round( sd, 4 ) if sd is not None else None, sd_ci95=[ round( x, 4 ) for x in sd_ci( sd, len( vals ) ) ] if sd is not None and len( vals ) <= 6 else None,
            power_n24={ str( t ): round( power( sd, 24, t ), 3 ) for t in ( 0.05, 0.08 ) } if sd else None,
            n_for_80pct_at_0_08=n_for_power( sd, 0.08 ) if sd else None )
    return out


if __name__ == "__main__":
    import json
    if len( sys.argv ) > 2 and sys.argv[ 1 ] == "sd-pilot":
        print( json.dumps( sd_pilot( sys.argv[ 2: ] ), indent=1, sort_keys=True ) )
    else:
        sys.exit( "usage: analyze.py sd-pilot OUTDIR..." )
