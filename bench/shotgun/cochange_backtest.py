#!/usr/bin/env python3
"""Backtest of the SHIPPED forgotten-partner check (--situ [3] / cochangePartners): walking history in order,
for each multi-file commit and each file A in it, predict A's partners from PRIOR history only (together>=3,
ranked by deg=together/commits(A), top 8 — the situ rule), and score against the files actually in the commit.
Zimmermann et al. 2004 (Mining Version Histories to Guide Software Changes) is the reference evaluation shape.
    python3 bench/shotgun/cochange_backtest.py LOG.txt [warmup=150] [minDeg=0.0]"""
import sys, statistics, os
sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )
from cochange_history import load_commits, PairCounter
log = sys.argv[ 1 ]; top = 8; warm = int( sys.argv[ 2 ] ) if len( sys.argv ) > 2 else 150
minDeg = float( sys.argv[ 3 ] ) if len( sys.argv ) > 3 else 0.0
commits = load_commits( log ); pc = PairCounter()
P = []; R = []; anyHit = 0; probes = 0; probesWithPred = 0; single = 0; singleAlarm = 0; singleAlarmHi = 0
for idx, ( date, files ) in enumerate( commits ):
    pc.slide( date )
    if idx >= warm:
        fset = set( files )
        for A in fset:
            if pc.cnt[ A ] < 3:
                continue
            cands = []
            for B in pc.cnt:
                if B == A:
                    continue
                t = pc.together( A, B )
                if t >= 3:
                    deg = t / pc.cnt[ A ]
                    if deg >= minDeg:
                        cands.append( ( -deg, B ) )
            cands.sort(); pred = { b for _, b in cands[ :top ] }
            if len( fset ) == 1:
                single += 1
                if pred:
                    singleAlarm += 1
                if any( -d >= 0.5 for d, _ in cands[ :top ] ):
                    singleAlarmHi += 1
                continue
            probes += 1
            if not pred:
                continue
            probesWithPred += 1
            hit = pred & ( fset - { A } )
            P.append( len( hit ) / len( pred ) ); R.append( len( hit ) / len( fset - { A } ) )
            if hit:
                anyHit += 1
    pc.push( date, files )
print( f"commits(kept, oldest-first)={len(commits)} warmup={warm} minDeg={minDeg} top={top}" )
print( f"multi-file probes={probes}  with>=1 predicted partner={probesWithPred} ({100*probesWithPred/max(1,probes):.0f}%)" )
print( f"  precision@{top}={statistics.mean(P) if P else 0:.3f}  recall={statistics.mean(R) if R else 0:.3f}  any-hit={100*anyHit/max(1,probesWithPred):.0f}% of predicted probes" )
print( f"single-file commits={single}: the check would name a 'forgotten' partner in {singleAlarm} ({100*singleAlarm/max(1,single):.0f}%), one with deg>=0.5 in {singleAlarmHi} ({100*singleAlarmHi/max(1,single):.0f}%)" )
