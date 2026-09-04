#!/usr/bin/env python3
"""scip_pin_precision.py — the S6-C SILENT-PIN precision census (docs/EVALS.md, registered 2026-08-31).

WHAT THIS MEASURES, AND WHY IT IS NOT scip_amb_precision.py
-----------------------------------------------------------
`src/graph.h`'s S6-C locality tie-break resolves a still-ambiguous call to whichever surviving
candidate shares the longest whole-SEGMENT canonical-id prefix with the caller, and when exactly one
survivor remains it emits a CONFIDENT edge whose pin is deliberately NOT counted in `amb=`. Nothing in
the shipped map distinguishes that pin from an evidence-backed resolution: an edge serializes as
`<c n="NAME"/>`, a callee NAME with no target identity.

`bench/scip_amb_precision.py` inherits exactly that blindness. It groups by name collision and scores a
covered bucket `min(pinned, emitted)/emitted`; a locality-pinned site has emitted==1 and SCIP's
replacement carries the SAME name, so the bucket scores 1.0 whether the pin was right or wrong. The
answer is therefore not a regrouping — the identity the join needs is absent from the output. This
harness consumes `--pin-census` instead, which emits that identity, and joins on it.

PROTOCOL (two runs of ONE binary over ONE corpus; deterministic, full census, no sampling)
-------------------------------------------------------------------------------------------
  1.  ripwire CORPUS --pin-census=plain.tsv --no-cache
        -> `C` rows: per DECIDED call site, the mechanism that resolved it and the canonical id
           (`path::scope::name#NODEID`) of every surviving target. This is shipped behaviour: no
           overlay, no oracle, the resolver deciding exactly as it does for a real user.
  2.  ripwire CORPUS --scip=INDEX --pin-census=scip.tsv --no-cache
        -> `O` rows: the SCIP index's own covered call sites, transcribed into the SAME id space.
  3.  Join on (caller_id, callee_name) and compare TARGET IDENTITY. NodeIds are assigned from the
      sorted crawl at ingest, before resolution, so --scip cannot move them; test/pincensuscheck.sh
      arm (I) asserts that stability rather than assuming it.

A pinned edge is CONFIRMED iff the target the resolver committed to is one of the targets SCIP
resolved that site to. Precision is reported only over sites WHERE SCIP SPEAKS — SCIP's silence is not
disconfirmation, and the covered count `n` is printed beside every figure.

STRATA (the registration's reference bands, reported in one table)
  locality      the population under audit — S6-C pinned it and `amb=` says nothing
  qualified / receiver-rule / cone / arity
                the OTHER silent pins: also uncounted in `amb=`, but each carries qualifier or
                receiver evidence the locality prior lacks. The expected upper reference.
  split         today's `amb=` population — per-TARGET precision, the continuation of the
                2026-07-11 census's 0.378 (loguru) / 0.841 (rq). The expected lower reference.
  unique        the tier held one candidate all along. ~1.0 BY CONSTRUCTION (one possible target, so
                SCIP cannot pick differently) — a sanity floor, never an independent result.

THE FULL ORACLE (phase 3, registered 2026-09-03 — docs/EVALS.md "Phase 3 — the SCIP join diagnosed")
  An `O` row may carry a SENTINEL target instead of an id: `@external` (SCIP resolved the site to a
  builtin or another package's symbol) or `@nondef` (to an in-index parameter, local, or attribute
  ripwire extracts no symbol for). The index SPOKE on that site and named something that is not any
  ripwire definition, so under the registration's rule — confirmed iff SCIP's target IS the pinned
  definition — the site is COVERED and every in-repo pin on it is DISCONFIRMED. Before phase 3 these
  sites were indistinguishable from silence. Two coverage figures are printed per mechanism: the full
  definition (`covered`, the primary) and the phase-2 in-repo-only one (`n-inrepo`, for continuity).

KNOWN LIMITS, stated here so they cannot be discovered in a writeup
  * The overlay keys coverage by (fromSymbol, calleeName), not by source position. Two call sites in
    one caller naming the same callee share one oracle answer; `multi_site_groups` counts how often
    that happens so the reader can price it.
  * SCIP is imperfect for dynamic dispatch, and scip-python resolves against whatever environment it
    was run in. A disconfirmed pin is disagreement with SCIP, not proof of a wrong edge.
  * Rows are a FLOOR on call sites: a site that produced no edge made no commitment and is absent.

USAGE
    python3 bench/scip_pin_precision.py --bin ./build/ripwire --repo DIR --scip INDEX.scip
    python3 bench/scip_pin_precision.py ... --label astropy-14365 --json out.json
"""
import argparse
import collections
import json
import os
import subprocess
import sys

MECHS = [ "locality", "qualified", "receiver-rule", "cone", "arity", "split", "unique", "scip", "binding", "external" ]
# The registered strata, in the order the result table prints them.
SILENT_PINS = [ "qualified", "receiver-rule", "cone", "arity" ]


def run_census( binp, repo, out, extra ):
    cmd = [ binp, repo, "--pin-census=" + out, "--no-cache" ] + extra
    r = subprocess.run( cmd, capture_output = True, text = True )
    if r.returncode != 0:
        sys.stderr.write( "FAILED: %s\n%s\n" % ( " ".join( cmd ), r.stderr[ :2000 ] ) )
        sys.exit( 2 )
    if not os.path.exists( out ):
        sys.stderr.write( "no census written at %s\n" % out )
        sys.exit( 2 )
    return out


def parse_census( path ):
    """-> ( decisions, oracle )
    decisions: list of dicts { mech, pre, post, flags, caller, callee, targets:[id] }
    oracle:    dict[ (caller, callee) ] -> set(id)
    """
    decisions = []
    oracle = {}
    with open( path, "r", encoding = "utf-8", errors = "replace" ) as fh:
        for line in fh:
            if line.startswith( "#" ):
                continue
            parts = line.rstrip( "\n" ).split( "\t" )
            if parts[ 0 ] == "C" and len( parts ) >= 8:
                decisions.append( {
                    "mech":    parts[ 1 ],
                    "pre":     int( parts[ 2 ] ),
                    "post":    int( parts[ 3 ] ),
                    "flags":   parts[ 4 ],
                    "caller":  parts[ 5 ],
                    "callee":  parts[ 6 ],
                    "targets": [ t for t in parts[ 7 ].split( "|" ) if t ],
                } )
            elif parts[ 0 ] == "O" and len( parts ) >= 4:
                key = ( parts[ 1 ], parts[ 2 ] )
                oracle.setdefault( key, set() ).update( t for t in parts[ 3 ].split( "|" ) if t )
    return decisions, oracle


def measure( decisions, oracle ):
    """Precision per mechanism over COVERED sites only, plus the coverage that produced it."""
    stat = collections.defaultdict( lambda: {
        "sites": 0, "covered": 0, "confirmed": 0,          # site-level (a pin is one decision), FULL oracle
        "covered_inrepo": 0, "confirmed_inrepo": 0,        # the phase-2 definition: SCIP named an in-repo def
        "sentinel_external": 0, "sentinel_nondef": 0,      # covered ONLY by a sentinel: disconfirmed by kind
        "tgt_covered": 0, "tgt_confirmed": 0,              # target-level (for `split`, which emits k edges)
    } )
    group_sites = collections.Counter()
    for d in decisions:
        s = stat[ d[ "mech" ] ]
        s[ "sites" ] += 1
        key = ( d[ "caller" ], d[ "callee" ] )
        group_sites[ key ] += 1
        truth = oracle.get( key )
        if truth is None:
            continue                                        # SCIP is silent here; silence is not disconfirmation
        s[ "covered" ] += 1
        inrepo = any( not t.startswith( "@" ) for t in truth )
        # site-level: the resolver committed to this target set; confirmed iff EVERY emitted target is
        # one SCIP resolved to. For a single-target pin (every mech but `split`) that is the pin being
        # right. For `split` it is the strict reading, and the per-target rate below is the lenient one.
        # A sentinel never equals an id, so a site SCIP resolved only to a non-definition is disconfirmed.
        confirmed = all( t in truth for t in d[ "targets" ] )
        if d[ "mech" ] == "external":
            # Phase 5: a VETO row names no target. It is right iff SCIP says the site was bound outside the
            # tree (`@external`) and wrong iff SCIP names an in-repo definition; a `@nondef`-only answer is
            # neither (reported in the @nondef column, and excluded from the veto-precision denominator the
            # registration states: confirmed / (covered - @nondef)).
            confirmed = ( "@external" in truth ) and not inrepo
        if confirmed:
            s[ "confirmed" ] += 1
        if inrepo:
            s[ "covered_inrepo" ] += 1
            if confirmed:
                s[ "confirmed_inrepo" ] += 1
        elif "@external" in truth:
            s[ "sentinel_external" ] += 1
        else:
            s[ "sentinel_nondef" ] += 1
        for t in d[ "targets" ]:
            s[ "tgt_covered" ] += 1
            if t in truth:
                s[ "tgt_confirmed" ] += 1
    multi = sum( 1 for k, v in group_sites.items() if v > 1 )
    return stat, multi, len( group_sites )


def pct( num, den ):
    return ( float( num ) / den ) if den else None


def fmt( x ):
    return "%.3f" % x if x is not None else "  n/a"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--bin", default = "./build/ripwire" )
    ap.add_argument( "--repo", required = True )
    ap.add_argument( "--scip", required = True, help = "a SCIP index over the SAME checkout" )
    ap.add_argument( "--workdir", default = None, help = "where the two census files are written" )
    ap.add_argument( "--label", default = None )
    ap.add_argument( "--exclude", action = "append", default = [] )
    ap.add_argument( "--json", default = None )
    a = ap.parse_args()

    work = a.workdir or os.path.dirname( os.path.abspath( a.scip ) )
    label = a.label or os.path.basename( os.path.abspath( a.repo ) )
    extra = [ "--exclude=" + e for e in a.exclude ]

    plain = run_census( a.bin, a.repo, os.path.join( work, label + ".plain.tsv" ), extra )
    withs = run_census( a.bin, a.repo, os.path.join( work, label + ".scip.tsv" ), extra + [ "--scip=" + a.scip ] )

    decisions, _ = parse_census( plain )
    _, oracle = parse_census( withs )

    stat, multi, groups = measure( decisions, oracle )

    print( "=" * 118 )
    print( "S6-C silent-pin precision census — %s" % label )
    print( "  repo   %s" % os.path.abspath( a.repo ) )
    print( "  scip   %s (%d covered call sites)" % ( os.path.abspath( a.scip ), len( oracle ) ) )
    print( "  census %d decided call sites, %d distinct (caller,callee) groups, %d of them multi-site"
           % ( len( decisions ), groups, multi ) )
    print( "=" * 118 )
    print( "%-16s %8s %9s %10s   %8s %9s   %6s %6s   %8s %10s %10s" %
           ( "mechanism", "sites", "covered", "precision", "n-inrepo", "p-inrepo", "@ext", "@nondef", "targets", "tgt-conf", "tgt-prec" ) )
    rows = {}
    for m in [ "locality" ] + SILENT_PINS + [ "split", "unique", "external", "scip", "binding" ]:
        s = stat.get( m )
        if not s or s[ "sites" ] == 0:
            continue
        p = pct( s[ "confirmed" ], s[ "covered" ] )
        pi = pct( s[ "confirmed_inrepo" ], s[ "covered_inrepo" ] )
        tp = pct( s[ "tgt_confirmed" ], s[ "tgt_covered" ] )
        rows[ m ] = { "sites": s[ "sites" ], "covered": s[ "covered" ], "confirmed": s[ "confirmed" ],
                      "precision": p, "covered_inrepo": s[ "covered_inrepo" ], "confirmed_inrepo": s[ "confirmed_inrepo" ],
                      "precision_inrepo": pi, "sentinel_external": s[ "sentinel_external" ],
                      "sentinel_nondef": s[ "sentinel_nondef" ], "targets_covered": s[ "tgt_covered" ],
                      "targets_confirmed": s[ "tgt_confirmed" ], "target_precision": tp }
        print( "%-16s %8d %9d %10s   %8d %9s   %6d %6d   %8d %10d %10s" %
               ( m, s[ "sites" ], s[ "covered" ], fmt( p ), s[ "covered_inrepo" ], fmt( pi ),
                 s[ "sentinel_external" ], s[ "sentinel_nondef" ], s[ "tgt_covered" ], s[ "tgt_confirmed" ], fmt( tp ) ) )

    # The registered verdict, applied mechanically to the primary metric so it cannot be nudged in prose.
    loc = rows.get( "locality" )
    print( "-" * 118 )
    if not loc or loc[ "covered" ] < 100:
        n = loc[ "covered" ] if loc else 0
        print( "VERDICT: INCONCLUSIVE — %d SCIP-covered locality-pinned sites (< 100 registered floor)." % n )
        print( "         The only funded follow-up is corpus growth. No band is widened to reach a decision." )
    elif loc[ "precision" ] >= 0.90:
        print( "VERDICT: SILENCE JUSTIFIED — locality precision %.3f (n=%d) >= 0.90."
               % ( loc[ "precision" ], loc[ "covered" ] ) )
        print( "         The lane's own premise is REFUTED; no disclosure fix is funded." )
    elif loc[ "precision" ] < 0.80:
        print( "VERDICT: SILENCE UNJUSTIFIED — locality precision %.3f (n=%d) < 0.80."
               % ( loc[ "precision" ], loc[ "covered" ] ) )
        print( "         Funds the disclosure fix, judged non-inferior at a +2.0%% ambiguous= ceiling." )
    else:
        print( "VERDICT: INCONCLUSIVE — locality precision %.3f (n=%d) in the 0.80-0.90 band."
               % ( loc[ "precision" ], loc[ "covered" ] ) )

    if a.json:
        with open( a.json, "w" ) as fh:
            json.dump( { "label": label, "repo": os.path.abspath( a.repo ), "scip": os.path.abspath( a.scip ),
                         "decided_sites": len( decisions ), "oracle_sites": len( oracle ),
                         "groups": groups, "multi_site_groups": multi, "mechanisms": rows, "rows": rows }, fh, indent = 2, sort_keys = True )
        print( "wrote %s" % a.json )
    return 0


if __name__ == "__main__":
    sys.exit( main() )
