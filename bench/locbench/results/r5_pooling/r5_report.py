#!/usr/bin/env python3
# r5 grid reader — applies the FROZEN decision rule from
# bench/locbench/results/r5_pooling/PREREG.md. It does not choose a winner by any other criterion,
# and it refuses to report anything at all if the identity control did not reproduce baseline.
import json, pathlib, sys

R = pathlib.Path( "/Users/qgames/AppDevelopLocal/project2/bench-assets/r4/results" )

def read( p ):
    d = json.load( open( p ) )
    ins = d["instances"]
    def acc( g ):
        if not g: return None
        return 100.0 * sum( 1 for i in g
                            if i["arms"]["for"]["file_worst"] is not None
                            and i["arms"]["for"]["file_worst"] < 10 ) / len( g )
    single = [ i for i in ins if len( i["primary_files"] ) == 1 ]
    multi  = [ i for i in ins if len( i["primary_files"] )  > 1 ]
    ranks  = { i["instance_id"]: i["arms"]["for"]["file_worst"] for i in ins }
    return dict( n=len( ins ), overall=acc( ins ), single=acc( single ), multi=acc( multi ),
                 n_single=len( single ), n_multi=len( multi ), ranks=ranks )

base_p = R / "r5_train_base.json"
if not base_p.exists():
    sys.exit( "baseline not written yet" )
base = read( base_p )

ctrl_p = R / "r5_train_5x0.json"
if ctrl_p.exists():
    ctrl = read( ctrl_p )
    if ctrl["ranks"] != base["ranks"]:
        diff = [ k for k in base["ranks"] if base["ranks"][k] != ctrl["ranks"].get( k ) ]
        sys.exit( f"IDENTITY CONTROL FAILED on {len(diff)} instances — per PREREG no cell may be read.\n"
                  f"  first: {diff[:3]}" )
    print( "identity control (5,0): reproduces baseline exactly ✓\n" )

print( f"train baseline  n={base['n']}  overall {base['overall']:.2f}%  "
       f"single(n={base['n_single']}) {base['single']:.2f}%  multi(n={base['n_multi']}) {base['multi']:.2f}%\n" )
print( f"{'cell':>9} | {'multi Δpp':>9} | {'single Δpp':>10} | {'overall Δpp':>11} | verdict" )
print( "-" * 62 )

advanced = []
for p in sorted( R.glob( "r5_train_*x*.json" ) ):
    cell = p.stem.replace( "r5_train_", "" ).replace( "x", "," )
    if cell.endswith( ",0" ):
        continue
    c  = read( p )
    dm = c["multi"]   - base["multi"]
    ds = c["single"]  - base["single"]
    do = c["overall"] - base["overall"]
    ok = dm >= 2.00 and ds > -1.00          # the frozen rule, verbatim
    if ok: advanced.append( ( cell, dm, ds, do ) )
    print( f"{cell:>9} | {dm:+9.2f} | {ds:+10.2f} | {do:+11.2f} | {'ADVANCE' if ok else '-'}" )

print()
if not advanced:
    print( "REJECT — no cell clears >= +2.00pp multi-file for < 1.00pp single-file cost." )
else:
    # frozen tie-break: smaller K, then smaller blend
    advanced.sort( key=lambda r: ( int( r[0].split(",")[0] ), int( r[0].split(",")[1] ) ) )
    w = advanced[0]
    print( f"ADVANCE {w[0]} (multi {w[1]:+.2f}pp, single {w[2]:+.2f}pp) — spend ONE held-out run on this cell." )
