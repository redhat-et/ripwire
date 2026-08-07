#!/usr/bin/env python3
"""nestcal — pre/post comparison against the round's pre-registered invariants.

Usage: compare.py PRE.tsv POST.tsv [BAR]

Checks, per symbol matched by id (symbols present on only one side are reported, never silently
dropped):
  I1  nest_post <= nest_pre                      (the fix only removes phantom depth)
  I2  cx_post   == cx_pre                        (cyclomatic is untouched by the fix)
  I3  ccx_post  <= ccx_pre                       (inflated nesting could only over-charge cognitive)
  I4  humps_post > 0  iff  nest_post >= BAR      (arm-5 equivalence survives, checked on POST rows)
Exit 0 when all four hold; 1 otherwise. Prints the distribution shift either way.
"""
import sys


def load( p ):
    rows = {}
    with open( p ) as f:
        next( f )
        for line in f:
            sid, nest, humps, deep, cx, ccx, loc = line.rstrip( "\n" ).split( "\t" )
            rows[sid] = ( int( nest ), int( humps ), int( deep ), int( cx ), int( ccx ), int( loc ) )
    return rows


def hist( rows ):
    h = {}
    for nest, *_ in rows.values():
        h[nest] = h.get( nest, 0 ) + 1
    return h


def main() -> int:
    pre, post = load( sys.argv[1] ), load( sys.argv[2] )
    bar = int( sys.argv[3] ) if len( sys.argv ) > 3 else 4
    only_pre  = sorted( set( pre ) - set( post ) )
    only_post = sorted( set( post ) - set( pre ) )
    shared    = sorted( set( pre ) & set( post ) )
    bad = { "I1": [], "I2": [], "I3": [], "I4": [] }
    moved = 0
    for sid in shared:
        pn, ph, pd, pcx, pccx, _ = pre[sid]
        qn, qh, qd, qcx, qccx, _ = post[sid]
        if qn > pn:
            bad["I1"].append( f"{sid}: nest {pn} -> {qn}" )
        if qcx != pcx:
            bad["I2"].append( f"{sid}: cx {pcx} -> {qcx}" )
        if qccx > pccx:
            bad["I3"].append( f"{sid}: ccx {pccx} -> {qccx}" )
        if ( qh > 0 ) != ( qn >= bar ):
            bad["I4"].append( f"{sid}: post nest={qn} humps={qh}" )
        if ( pn, ph, pd ) != ( qn, qh, qd ):
            moved += 1
    hp, hq = hist( pre ), hist( post )
    print( f"symbols: pre={len( pre )} post={len( post )} shared={len( shared )} "
           f"only_pre={len( only_pre )} only_post={len( only_post )}" )
    print( f"rows whose (nest,humps,deep) moved: {moved} ({100.0 * moved / max( 1, len( shared ) ):.1f}%)" )
    print( "nest   pre -> post" )
    for k in sorted( set( hp ) | set( hq ) ):
        print( f"  {k}: {hp.get( k, 0 ):6d} -> {hq.get( k, 0 ):6d}" )
    print( f"total humps: {sum( r[1] for r in pre.values() )} -> {sum( r[1] for r in post.values() )}" )
    print( f"rows with humps: {sum( 1 for r in pre.values() if r[1] > 0 )} -> "
           f"{sum( 1 for r in post.values() if r[1] > 0 )}" )
    print( f"total deep: {sum( r[2] for r in pre.values() )} -> {sum( r[2] for r in post.values() )}" )
    ok = True
    for k, v in bad.items():
        if v:
            ok = False
            print( f"VIOLATION {k} ({len( v )}):" )
            for line in v[:20]:
                print( f"  {line}" )
    for tag, ids in ( ( "only_pre", only_pre ), ( "only_post", only_post ) ):
        for sid in ids[:10]:
            print( f"note {tag}: {sid}" )
    print( "RESULT:", "PASS" if ok else "FAIL" )
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit( main() )
