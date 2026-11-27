#!/usr/bin/env python3
"""cloneprec — replay the frozen ranges and emit the two populations the README pre-registers.

Usage:
    run_cloneprec.py --bin PATH --root PATH --label NAME [--ranges FILE] [--out DIR]

One process at a time, --no-cache, no concurrency: the numbers are counts of rows, and a shared
cache or two ripwire processes would make them depend on timing.

It writes <out>/<label>.jsonl (one record per range) and prints a summary. It decides NOTHING about
truth: grading is a separate, human step over the per-row table this emits.
"""
import argparse, hashlib, json, os, re, subprocess, sys

ATTR = re.compile(r'(\w[\w-]*)="([^"]*)"')
CLONE_KINDS = ( "duplication", "new-clone-of-reused-helper" )


def attrs( tag ):
    return dict( ATTR.findall( tag ) )


def parse( xml ):
    """Return (root_attrs, [row_attrs]). Rows are <r ...> elements only; the legend's bare
    `<r kind= sym= ...>` template carries no quoted values, so attrs() yields nothing for it and it
    is dropped by the kind test below."""
    root, rows = {}, []
    for chunk in xml.split( "<" ):
        if chunk.startswith( "quality-delta " ):
            root = attrs( chunk )
        elif chunk.startswith( "r " ):
            a = attrs( chunk )
            if a.get( "kind" ) in CLONE_KINDS:
                rows.append( a )
    return root, rows


def members_of( row ):
    """A duplication row names its group in members=; a new-clone-of-reused-helper row names it in
    sym=. Both are canonical ids joined by ' | '. (Corrected 2026-11-27: the pre-registration said
    sym= for both, which is wrong for duplication rows — a factual error about the method, marked as
    such in the README.)"""
    raw = row.get( "members" ) or row.get( "sym" ) or ""
    return [ m.strip() for m in raw.split( "|" ) if m.strip() ]


def gates( row ):
    """Pre-registered rule: a row is in population P when it is not minor and not new-symbol.
    Acked rows never reach <r> (they are emitted as <sa>), so there is nothing to subtract here."""
    return row.get( "sev" ) != "minor" and row.get( "origin" ) != "new-symbol"


def components( rows ):
    """Connected components of the member graph induced by the given rows (README Part 2)."""
    parent = {}

    def find( x ):
        parent.setdefault( x, x )
        while parent[ x ] != x:
            parent[ x ] = parent[ parent[ x ] ]
            x = parent[ x ]
        return x

    def unite( a, b ):
        ra, rb = find( a ), find( b )
        if ra != rb:
            parent[ ra ] = rb

    for row in rows:
        ms = members_of( row )
        for m in ms[ 1: ]:
            unite( ms[ 0 ], m )
        for m in ms:
            find( m )
    return len( { find( m ) for m in parent } )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--bin", required = True )
    ap.add_argument( "--root", required = True )
    ap.add_argument( "--label", required = True )
    here = os.path.dirname( os.path.abspath( __file__ ) )
    ap.add_argument( "--ranges", default = os.path.join( here, "ranges.lock" ) )
    ap.add_argument( "--out", default = os.path.join( here, "results" ) )
    a = ap.parse_args()
    os.makedirs( a.out, exist_ok = True )

    ranges = [ l.strip() for l in open( a.ranges ) if l.strip() and not l.startswith( "#" ) ]
    ver = subprocess.run( [ a.bin, "--version" ], capture_output = True, text = True,
                          errors = "replace" ).stdout.strip().splitlines()[ 0 ]
    path = os.path.join( a.out, a.label + ".jsonl" )
    tot_rows = tot_gating = tot_comp = tot_minor = tot_disagree = 0
    with open( path, "w" ) as fh:
        fh.write( json.dumps( { "record": "header", "label": a.label, "bin": a.bin,
                                "version": ver, "root": a.root, "ranges": len( ranges ) } ) + "\n" )
        for rng in ranges:
            cmd = [ a.bin, a.root, "--quality-delta=" + rng,
                    "--quality-kinds=duplication,new-clone-of-reused-helper",
                    "--no-cache", "--legend=compact" ]
            p = subprocess.run( cmd, capture_output = True, text = True, errors = "replace" )
            root, rows = parse( p.stdout )
            g = [ r for r in rows if gates( r ) ]
            comp = components( g )
            # cross-check our per-row rule against the root's own gating= count, and report any
            # disagreement rather than trusting either silently.
            root_gating = int( root.get( "gating", -1 ) )
            disagree = root_gating != len( g )
            tot_rows += len( rows ); tot_gating += len( g ); tot_comp += comp
            tot_minor += sum( 1 for r in rows if r.get( "sev" ) == "minor" )
            tot_disagree += 1 if disagree else 0
            fh.write( json.dumps( {
                "record": "range", "range": rng, "rc": p.returncode,
                "clone_rows": len( rows ), "minor": sum( 1 for r in rows if r.get( "sev" ) == "minor" ),
                "gating_clone_rows": len( g ), "components": comp,
                "root_gating_all_kinds": root_gating, "gating_disagreement": disagree,
                "root_regressions": root.get( "regressions" ), "root_stale_tree": root.get( "stale_tree" ),
                "root_churn": root.get( "churn" ),
                # ADDED 2026-11-27, after the frozen run showed the GATING population is empty and so
                # can carry neither quantity: the same component count over ALL clone rows, gating or
                # not. Marked post-hoc in README.md; it does not replace the pre-registered gating
                # metric, which is reported as undefined where it is undefined.
                "components_all_rows": components( rows ),
                "detail": [ { "kind": r.get( "kind" ), "members": members_of( r ),
                              "sev": r.get( "sev" ), "origin": r.get( "origin" ),
                              "idiom": r.get( "idiom" ), "why": r.get( "why" ),
                              "tokens": r.get( "tokens" ), "p": r.get( "p" ), "gates": gates( r ) }
                            for r in rows ],
                "gating_detail": [ { "kind": r.get( "kind" ), "members": members_of( r ),
                                     "sev": r.get( "sev" ), "idiom": r.get( "idiom" ),
                                     "why": r.get( "why" ), "tokens": r.get( "tokens" ),
                                     "p": r.get( "p" ),
                                     "draw": hashlib.sha256(
                                         ( "cloneprec-1127:" + rng + ":" + str( r.get( "kind" ) ) + ":"
                                           + " | ".join( members_of( r ) ) ).encode() ).hexdigest() }
                                   for r in g ],
            } ) + "\n" )
            print( f"{a.label} {rng.split('~')[0][:9]} clone_rows={len(rows)} gating={len(g)} "
                   f"components={comp}" + ( "  DISAGREE" if disagree else "" ), flush = True )
    rpd = f"{tot_gating / tot_comp:.4f}" if tot_comp else "UNDEFINED (no gating clone row)"
    print( f"\n{a.label}: {ver}\n  clone rows={tot_rows}  minor={tot_minor}  "
           f"GATING |P|={tot_gating}  components={tot_comp}  rows_per_duplication(gating)={rpd}  "
           f"root-vs-row disagreements={tot_disagree}/{len(ranges)}\n  -> {path}" )


if __name__ == "__main__":
    main()
