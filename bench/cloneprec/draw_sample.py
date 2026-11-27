#!/usr/bin/env python3
"""cloneprec — draw the pre-registered salted sample from a run's gating population and print each
row with its members' bodies, so the adjudication is done against evidence and the evidence is
recorded beside the verdict.

Draw order is SHA-256( "cloneprec-1127:<range>:<kind>:<members joined by ' | '>" ) ascending, which
run_cloneprec.py already stored per row as "draw". n=30, pre-registered; if |P| <= 30 everything is
graded and there is no sample.

Usage: draw_sample.py results/<label>.jsonl [--n 30] [--bodies] [--repo PATH]
"""
import argparse, json, re, subprocess, sys


def body_of( repo, commit, path, name, window ):
    """Print the definition window for `name` in `path` at `commit`. Crude on purpose: it is evidence
    for a human reader, not a parse. Returns ( found, text )."""
    p = subprocess.run( [ "git", "-C", repo, "show", f"{commit}:{path}" ],
                        capture_output = True, text = True, errors = "replace" )
    if p.returncode != 0:
        return False, f"      [body unavailable: {path} not at {commit[:9]}]"
    lines = p.stdout.splitlines()
    hits = [ i for i, l in enumerate( lines )
             if re.search( r"\b" + re.escape( name ) + r"\s*\(", l ) and "return " not in l.split( name )[ 0 ] ]
    if not hits:
        return False, f"      [definition of {name} not located in {path} at {commit[:9]}]"
    i = hits[ 0 ]
    return True, "\n".join( f"      {n+1:>6}  {lines[n]}" for n in range( i, min( len( lines ), i + window ) ) )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "jsonl" )
    ap.add_argument( "--n", type = int, default = 30 )
    ap.add_argument( "--bodies", action = "store_true" )
    ap.add_argument( "--window", type = int, default = 14 )
    ap.add_argument( "--repo", default = "." )
    a = ap.parse_args()

    rows = []
    for line in open( a.jsonl ):
        rec = json.loads( line )
        if rec.get( "record" ) != "range":
            continue
        target = rec[ "range" ].split( ".." )[ -1 ]
        for r in rec[ "gating_detail" ]:
            r[ "range" ] = rec[ "range" ]
            r[ "target" ] = target
            rows.append( r )

    print( f"|P| (gating clone rows) = {len(rows)}" )
    if len( rows ) <= a.n:
        print( f"|P| <= n={a.n}: the WHOLE population is graded, there is no sample and no sampling error." )
        sample = sorted( rows, key = lambda r: r[ "draw" ] )
    else:
        sample = sorted( rows, key = lambda r: r[ "draw" ] )[ : a.n ]
        print( f"salted draw, n={a.n} of {len(rows)} (salt cloneprec-1127)" )

    for idx, r in enumerate( sample, 1 ):
        print( f"\n--- {idx}/{len(sample)}  {r['range'].split('~')[0][:9]}  {r['kind']}"
               f"  tokens={r.get('tokens')}  idiom={r.get('idiom')}  why={r.get('why')}  p={r.get('p')}" )
        for m in r[ "members" ]:
            print( f"    MEMBER {m}" )
            if a.bodies:
                path = m.split( "::" )[ 0 ]
                name = m.split( "::" )[ -1 ]
                _, text = body_of( a.repo, r[ "target" ], path, name, a.window )
                print( text )


if __name__ == "__main__":
    main()
