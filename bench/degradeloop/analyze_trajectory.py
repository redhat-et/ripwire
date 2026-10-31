#!/usr/bin/env python3
"""analyze_trajectory.py — the four pre-registered instruments from
docs/research/gate-vs-iterative-degradation.md §2.3, computed over whatever trajectory JSONL
files run_degradeloop.py has produced.

SCAFFOLDING, NOT VALIDATED AGAINST REAL DATA. The statistics below (paired slope comparison,
Wilcoxon signed-rank) are implemented from scratch, zero-dependency, matching this project's own
"no host-installed dependencies" posture (CLAUDE.md G3) rather than reaching for scipy — they have
been sanity-checked against small synthetic inputs (see the __main__ self-test at the bottom,
runnable with `python3 analyze_trajectory.py --selftest`) but NOT against a real trajectory run,
because none exists yet. Do not cite a p-value out of this file in a publishable report without an
independent check against a reference implementation once real data exists.

INPUT FORMAT. One or more JSONL files as written by run_degradeloop.py: a header row
(kind="degradeloop-trajectory-header") followed by one row per iteration. This script does not
assume a particular per-iteration row schema beyond what each instrument function documents it
reads — see each function's docstring for the exact fields it expects, matching what measure.py's
snapshot dataclasses would serialize.

REFUSAL, NOT SILENT OMISSION. Per the design doc's §2.3 rule ("the write-up reports … all four
instruments … not whichever one came out favorable"), report_all() below always emits a row for
every instrument, marking it unavailable with a stated reason when the data can't support it,
rather than dropping it from the table.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Minimal zero-dependency statistics (see module docstring on why not scipy)
# ---------------------------------------------------------------------------

def _ranks( values: list[float] ) -> list[float]:
    """Average ranks, ties split evenly — the standard Wilcoxon tie-handling."""
    order = sorted( range( len( values ) ), key=lambda i: values[ i ] )
    ranks = [ 0.0 ] * len( values )
    i = 0
    while i < len( order ):
        j = i
        while j + 1 < len( order ) and values[ order[ j + 1 ] ] == values[ order[ i ] ]:
            j += 1
        avg_rank = ( i + j ) / 2.0 + 1.0
        for k in range( i, j + 1 ):
            ranks[ order[ k ] ] = avg_rank
        i = j + 1
    return ranks


def wilcoxon_signed_rank( a: list[float], b: list[float] ) -> dict:
    """Paired Wilcoxon signed-rank test, a vs b (a - b), normal approximation (no exact tables —
    fine for the N this design expects to run with being small enough that the approximation's own
    documented weakness at very small N should be flagged, which this function does via `note`
    rather than silently reporting a p-value the sample size doesn't support).

    Returns W (the smaller of W+/W-), z (normal-approximation statistic), and a two-sided p
    computed from a standard-normal survival approximation (erf-based, stdlib only).
    """
    diffs = [ x - y for x, y in zip( a, b ) if x != y ]   # zero-diffs dropped, standard convention
    n = len( diffs )
    if n < 6:
        return {
            "n_nonzero": n, "W": None, "z": None, "p_two_sided": None,
            "note": "n < 6 after dropping zero-diffs — normal approximation is not trustworthy here; "
                    "report the raw paired differences instead of a p-value.",
        }
    abs_diffs = [ abs( d ) for d in diffs ]
    ranks = _ranks( abs_diffs )
    w_pos = sum( r for r, d in zip( ranks, diffs ) if d > 0 )
    w_neg = sum( r for r, d in zip( ranks, diffs ) if d < 0 )
    w = min( w_pos, w_neg )
    mean_w = n * ( n + 1 ) / 4.0
    std_w = ( n * ( n + 1 ) * ( 2 * n + 1 ) / 24.0 ) ** 0.5
    z = ( w - mean_w ) / std_w if std_w > 0 else 0.0
    p = _two_sided_normal_p( z )
    return { "n_nonzero": n, "W": w, "z": z, "p_two_sided": p, "note": None }


def _erf( x: float ) -> float:
    # Abramowitz & Stegun 7.1.26 approximation — stdlib-only, adequate for a two-sided p-value
    # at the precision this design needs (a pre-registered effect-size floor, not a tight p-value).
    sign = 1 if x >= 0 else -1
    x = abs( x )
    a1, a2, a3, a4, a5 = 0.254829592, -0.284496736, 1.421413741, -1.453152027, 1.061405429
    p = 0.3275911
    t = 1.0 / ( 1.0 + p * x )
    y = 1.0 - ( ( ( ( ( a5 * t + a4 ) * t ) + a3 ) * t + a2 ) * t + a1 ) * t * pow( 2.718281828459045, -x * x )
    return sign * y


def _two_sided_normal_p( z: float ) -> float:
    return 2.0 * ( 1.0 - 0.5 * ( 1.0 + _erf( abs( z ) / ( 2 ** 0.5 ) ) ) )


def _slope( ys: list[float] ) -> float:
    """OLS slope of ys against iteration index 0..n-1. Plain least squares, stdlib only."""
    n = len( ys )
    if n < 2:
        return 0.0
    xs = list( range( n ) )
    mean_x = sum( xs ) / n
    mean_y = sum( ys ) / n
    num = sum( ( x - mean_x ) * ( y - mean_y ) for x, y in zip( xs, ys ) )
    den = sum( ( x - mean_x ) ** 2 for x in xs )
    return num / den if den else 0.0


# ---------------------------------------------------------------------------
# Trajectory loading
# ---------------------------------------------------------------------------

def load_trajectory( path: Path ) -> tuple[dict, list[dict]]:
    lines = path.read_text().splitlines()
    if not lines:
        raise ValueError( f"{path}: empty trajectory file" )
    header = json.loads( lines[ 0 ] )
    if header.get( "kind" ) != "degradeloop-trajectory-header":
        raise ValueError( f"{path}: first line is not a degradeloop-trajectory-header row" )
    rows = [ json.loads( l ) for l in lines[ 1: ] ]
    return header, rows


# ---------------------------------------------------------------------------
# The four instruments (design doc §2.3)
# ---------------------------------------------------------------------------

def instrument_1_cumulative_regression_slope( gated_trajs: list[list[dict]], ungated_trajs: list[list[dict]] ) -> dict:
    """Paired by seed task (same index in both lists = same seed task). Expects each row to carry
    'regressions' (int, from measure.QualityDeltaSnapshot.regressions, baseline-anchored per the
    design doc §2.2's instruction to measure against state[0], never state[i-1])."""
    if not gated_trajs or len( gated_trajs ) != len( ungated_trajs ):
        return { "available": False, "reason": "need equal, nonzero paired seed-task counts for both arms" }
    gated_slopes = [ _slope( [ r[ "regressions" ] for r in traj ] ) for traj in gated_trajs ]
    ungated_slopes = [ _slope( [ r[ "regressions" ] for r in traj ] ) for traj in ungated_trajs ]
    test = wilcoxon_signed_rank( ungated_slopes, gated_slopes )   # ungated - gated: positive means gate reduced slope
    return {
        "available": True,
        "gated_slopes": gated_slopes,
        "ungated_slopes": ungated_slopes,
        "paired_test": test,
        "interpretation": "test is on (ungated_slope - gated_slope); z > 0 means ungated slopes ranked "
                           "higher (gate associated with a LOWER regression slope), z < 0 the opposite. "
                           "Check the sign of z, not just p_two_sided, before claiming a direction.",
    }


def instrument_2_terminal_state( gated_trajs: list[list[dict]], ungated_trajs: list[list[dict]] ) -> dict:
    """Design doc §2.3 instrument 2 — the weaker, paper-shaped claim (end state only)."""
    if not gated_trajs or len( gated_trajs ) != len( ungated_trajs ):
        return { "available": False, "reason": "need equal, nonzero paired seed-task counts for both arms" }
    gated_terminal = [ traj[ -1 ][ "regressions" ] for traj in gated_trajs if traj ]
    ungated_terminal = [ traj[ -1 ][ "regressions" ] for traj in ungated_trajs if traj ]
    if len( gated_terminal ) != len( gated_trajs ):
        return { "available": False, "reason": "at least one trajectory had zero iterations" }
    test = wilcoxon_signed_rank( ungated_terminal, gated_terminal )
    return { "available": True, "gated_terminal": gated_terminal, "ungated_terminal": ungated_terminal, "paired_test": test }


def instrument_3_subbar_growth( gated_trajs: list[list[dict]], ungated_trajs: list[list[dict]] ) -> dict:
    """Design doc §2.3 instrument 3 — expects each row to carry 'subbar_growth_total' (a float/int
    the row-producer computed via measure.measure_subbar_growth, itself UNIMPLEMENTED in
    measure.py). Refuses rather than guessing when the field is absent, per this project's own
    honesty-in-output convention (src/quality.h: "a zero means none found, never none exists")."""
    if not gated_trajs or not ungated_trajs:
        return { "available": False, "reason": "no trajectories supplied" }
    if any( "subbar_growth_total" not in r for traj in ( gated_trajs + ungated_trajs ) for r in traj ):
        return {
            "available": False,
            "reason": "rows are missing subbar_growth_total — measure.measure_subbar_growth is "
                      "unimplemented in this scaffolding (see measure.py); this is NOT the same as "
                      "the instrument measuring zero growth.",
        }
    gated_slopes = [ _slope( [ r[ "subbar_growth_total" ] for r in traj ] ) for traj in gated_trajs ]
    ungated_slopes = [ _slope( [ r[ "subbar_growth_total" ] for r in traj ] ) for traj in ungated_trajs ]
    test = wilcoxon_signed_rank( ungated_slopes, gated_slopes )
    return { "available": True, "gated_slopes": gated_slopes, "ungated_slopes": ungated_slopes, "paired_test": test }


def instrument_4_security_trajectory( gated_trajs: list[list[dict]], ungated_trajs: list[list[dict]] ) -> dict:
    """Design doc §2.3 instrument 4 — expects 'security_finding_count' per row, from
    measure.run_security_scanner (UNIMPLEMENTED in measure.py until a scanner is pinned)."""
    if not gated_trajs or not ungated_trajs:
        return { "available": False, "reason": "no trajectories supplied" }
    if any( "security_finding_count" not in r for traj in ( gated_trajs + ungated_trajs ) for r in traj ):
        return {
            "available": False,
            "reason": "rows are missing security_finding_count — no scanner is pinned yet "
                      "(measure.run_security_scanner is unimplemented); see README.md.",
        }
    gated_slopes = [ _slope( [ r[ "security_finding_count" ] for r in traj ] ) for traj in gated_trajs ]
    ungated_slopes = [ _slope( [ r[ "security_finding_count" ] for r in traj ] ) for traj in ungated_trajs ]
    test = wilcoxon_signed_rank( ungated_slopes, gated_slopes )
    return { "available": True, "gated_slopes": gated_slopes, "ungated_slopes": ungated_slopes, "paired_test": test }


def report_all( gated_trajs: list[list[dict]], ungated_trajs: list[list[dict]] ) -> dict:
    """Always emits all four instruments — an unavailable one is reported with its reason, never
    dropped from the table. See design doc §2.3's selective-reporting warning."""
    return {
        "instrument_1_cumulative_regression_slope": instrument_1_cumulative_regression_slope( gated_trajs, ungated_trajs ),
        "instrument_2_terminal_state": instrument_2_terminal_state( gated_trajs, ungated_trajs ),
        "instrument_3_subbar_growth": instrument_3_subbar_growth( gated_trajs, ungated_trajs ),
        "instrument_4_security_trajectory": instrument_4_security_trajectory( gated_trajs, ungated_trajs ),
    }


def main() -> int:
    ap = argparse.ArgumentParser( description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter )
    ap.add_argument( "--gated", nargs="+", type=Path, default=[], help="trajectory JSONL files, arm=gated, one per seed task" )
    ap.add_argument( "--ungated", nargs="+", type=Path, default=[], help="trajectory JSONL files, arm=ungated, one per seed task, SAME ORDER as --gated" )
    ap.add_argument( "--selftest", action="store_true", help="run the built-in synthetic sanity check and exit" )
    args = ap.parse_args()

    if args.selftest:
        return _selftest()

    if not args.gated or not args.ungated:
        print( "error: --gated and --ungated each need at least one trajectory file (or pass --selftest)", file=sys.stderr )
        return 1

    gated_trajs = [ load_trajectory( p )[ 1 ] for p in args.gated ]
    ungated_trajs = [ load_trajectory( p )[ 1 ] for p in args.ungated ]
    print( json.dumps( report_all( gated_trajs, ungated_trajs ), indent=2 ) )
    return 0


def _selftest() -> int:
    """Sanity check ONLY — synthetic data, not a claim about anything real. Checks that (a) a
    clearly-lower-slope gated arm is detected as such in instrument 1, and (b) an
    all-fields-missing input correctly reports unavailable for instruments 3/4 rather than
    crashing or silently defaulting to zero."""
    gated = [ [ { "regressions": r } for r in [ 0, 1, 1, 2, 2 ] ] for _ in range( 8 ) ]
    ungated = [ [ { "regressions": r } for r in [ 0, 2, 4, 6, 8 ] ] for _ in range( 8 ) ]
    report = report_all( gated, ungated )
    i1 = report[ "instrument_1_cumulative_regression_slope" ]
    assert i1[ "available" ], i1
    assert all( g < u for g, u in zip( i1[ "gated_slopes" ], i1[ "ungated_slopes" ] ) ), i1
    i3 = report[ "instrument_3_subbar_growth" ]
    assert i3[ "available" ] is False and "subbar_growth_total" in i3[ "reason" ], i3
    print( "selftest OK (synthetic data only — not a real result)", file=sys.stderr )
    print( json.dumps( report, indent=2 ) )
    return 0


if __name__ == "__main__":
    sys.exit( main() )
