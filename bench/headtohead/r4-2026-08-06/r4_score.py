#!/usr/bin/env python3
# Round-4 unified scoreboard: every arm scored from ranks that were computed by the SAME
# RL.file_ranks import inside r4_worker.py. This script only AGGREGATES — it never recomputes a
# rank, so there is no second notion of "the metric" that could drift from the first.
#
# Unlike r1/r2 this is a single paired table: one ripwire binary, one evaluator, one slice, so the
# arms are directly comparable to each other and no "do not compare across rounds" caveat applies.
import json, pathlib, statistics, sys

HERE = pathlib.Path( __file__ ).resolve().parent
R = HERE / "results"

rip = json.load( open( R / "r4_ripwire_for.json" ) )["instances"]

def load_arm( arm ):
    """Glob EVERY shard of an arm. A long arm gets sharded across processes with --tag, so reading
    only r4_<arm>.jsonl would silently drop most of it and quietly shrink the paired N."""
    out = {}
    for f in sorted( R.glob( f"r4_{arm}*.jsonl" ) ):
        for line in open( f ):
            r = json.loads( line )
            out[ r["instance_id"] ] = r
    return out

cs = load_arm( "codeseek" )
rw = load_arm( "repowise" )
cb = load_arm( "cbm" )
gf = load_arm( "graphify" )
ad = load_arm( "aider" )

ARMS = [ "ripwire", "repowise", "cbm", "graphify", "aider", "aider_noperson",
         "codeseek_idents", "codeseek_raw" ]

def trip( blk ):
    return ( blk["file_worst"], blk["file_first"], blk["wall"] ) if blk else None

def arm_ranks( iid, inst ):
    a = inst["arms"]["for"]
    out = { "ripwire": ( a["file_worst"], a["file_first"], a["wall_median"] ) }
    c, w, b, g, d = cs.get( iid ), rw.get( iid ), cb.get( iid ), gf.get( iid ), ad.get( iid )
    out["codeseek_raw"]    = trip( c["raw"] )       if c else None
    out["codeseek_idents"] = trip( c["idents"] )    if c else None
    out["repowise"]        = trip( w["search"] )    if w else None
    out["cbm"]             = trip( b["search"] )    if b else None
    out["graphify"]        = trip( g["search"] )    if g else None
    out["aider"]           = trip( d["search"] )    if d else None
    out["aider_noperson"]  = trip( d["nopersona"] ) if d else None
    return out

rows, missing = [], {}
for inst in rip:
    iid = inst["instance_id"]
    a = arm_ranks( iid, inst )
    absent = [ k for k, v in a.items() if v is None ]
    if absent:
        missing[iid] = absent; continue
    rows.append( ( iid, len( inst["primary_files"] ), a ) )

n = len( rows )
if not n:
    print( "no fully-paired instances yet; arms still running:", file=sys.stderr )
    for iid, absent in list( missing.items() )[:3]:
        print( f"  {iid}: missing {','.join(absent)}", file=sys.stderr )
    raise SystemExit( 1 )

print( f"# Round 4 — unified, N={n} paired (incomplete instances excluded: {len(missing)})\n" )

def strict10( v ): return v[0] is not None and v[0] < 10
def any10( v ):    return v[1] is not None and v[1] < 10

print( "| arm | strict file@10 | any@10 | median wall |" )
print( "| --- | --- | --- | --- |" )
for arm in ARMS:
    s = sum( strict10( a[arm] ) for _, _, a in rows )
    y = sum( any10( a[arm] ) for _, _, a in rows )
    wm = statistics.median( a[arm][2] for _, _, a in rows )
    print( f"| {arm} | {100*s/n:.1f}% | {100*y/n:.1f}% | {wm:.3f} s |" )

for stratum, keep in ( ( "single-file", lambda k: k == 1 ), ( "multi-file", lambda k: k > 1 ) ):
    sub = [ r for r in rows if keep( r[1] ) ]
    if not sub: continue
    print( f"\n{stratum} stratum, n={len(sub)}:" )
    for arm in ARMS:
        s = sum( strict10( a[arm] ) for _, _, a in sub )
        y = sum( any10( a[arm] ) for _, _, a in sub )
        print( f"  {arm:16} strict@10 {100*s/len(sub):5.1f}%   any@10 {100*y/len(sub):5.1f}%" )

print( "\npaired win/loss vs ripwire (strict@10):" )
for arm in ARMS[1:]:
    both  = sum( strict10( a["ripwire"] ) and strict10( a[arm] ) for _, _, a in rows )
    ronly = sum( strict10( a["ripwire"] ) and not strict10( a[arm] ) for _, _, a in rows )
    aonly = sum( not strict10( a["ripwire"] ) and strict10( a[arm] ) for _, _, a in rows )
    print( f"  vs {arm:16} both={both:2}  ripwire-only={ronly:2}  {arm}-only={aonly:2}  "
           f"neither={n-both-ronly-aonly:2}" )

print( "\nripwire strict losses (a competitor got ALL gold in top-10 where ripwire did not):" )
lost = 0
for iid, k, a in rows:
    losers = [ arm for arm in ARMS[1:] if strict10( a[arm] ) and not strict10( a["ripwire"] ) ]
    if losers:
        lost += 1
        print( f"  {iid} (gold={k}) won by {','.join(losers)}; "
               f"ripwire worst={a['ripwire'][0]} first={a['ripwire'][1]}" )
if not lost:
    print( "  (none)" )

print( "\nripwire near-misses (all gold found, worst rank just outside 10) — the improvement surface:" )
for iid, k, a in sorted( rows, key=lambda r: ( r[2]["ripwire"][0] is None, r[2]["ripwire"][0] or 1e9 ) ):
    w = a["ripwire"][0]
    if w is not None and 10 <= w < 30:
        print( f"  {iid} (gold={k}) worst={w} first={a['ripwire'][1]}" )
