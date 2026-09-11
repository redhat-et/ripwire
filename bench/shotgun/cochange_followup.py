#!/usr/bin/env python3
"""Follow-up measurement: when the forgotten-partner check would ALARM on commit c (a partner B of some file A in c,
deg>=MINDEG, B not in c), is B then touched within the next K commits? A high rate = the alarm names real forgets
(fixed later); a low rate = the alarm names files that simply did not need to change. Also: does the SCATTER of a
commit (files touched) predict a follow-up on one of its partners?
    python3 bench/shotgun/cochange_followup.py LOG.txt [K=3] [minDeg=0.5]"""
import sys, random, os
sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )
from cochange_history import load_commits, PairCounter
log = sys.argv[ 1 ]; K = int( sys.argv[ 2 ] ) if len( sys.argv ) > 2 else 3
MINDEG = float( sys.argv[ 3 ] ) if len( sys.argv ) > 3 else 0.5
top, warm = 8, 150
commits = load_commits( log ); pc = PairCounter()
alarms = []   # (idx, scatter, alarmedSet)
for idx, ( date, files ) in enumerate( commits ):
    pc.slide( date )
    if idx >= warm:
        fset = set( files ); named = set()
        for A in fset:
            if pc.cnt[ A ] < 3:
                continue
            cands = []
            for B in pc.cnt:
                if B == A or B in fset:
                    continue
                t = pc.together( A, B )
                if t >= 3 and t / pc.cnt[ A ] >= MINDEG:
                    cands.append( ( -t / pc.cnt[ A ], B ) )
            cands.sort(); named |= { b for _, b in cands[ :top ] }
        alarms.append( ( idx, len( fset ), named ) )
    pc.push( date, files )
def touchedWithin( idx, B, k ):
    return any( B in commits[ j ][ 1 ] for j in range( idx + 1, min( len( commits ), idx + 1 + k ) ) )
withAlarm = [ a for a in alarms if a[ 2 ] ]
hitAny = sum( 1 for idx, sc, named in withAlarm if any( touchedWithin( idx, B, K ) for B in named ) )
perAlarm = [ touchedWithin( idx, B, K ) for idx, sc, named in withAlarm for B in named ]
# BASELINE: the same question for a random active file (how often does ANY file with >=3 commits get touched within K?)
random.seed( 7 )
active = [ f for f, c in pc.cnt.items() if c >= 3 ]
base = [ touchedWithin( idx, random.choice( active ), K ) for idx, sc, named in withAlarm ]
print( f"K={K} minDeg={MINDEG}: commits scored={len(alarms)} with>=1 alarm={len(withAlarm)} ({100*len(withAlarm)/max(1,len(alarms)):.0f}%)" )
print( f"  a named partner IS touched within the next {K} commits: {100*hitAny/max(1,len(withAlarm)):.0f}% of alarmed commits; per named file {100*sum(perAlarm)/max(1,len(perAlarm)):.0f}% (n={len(perAlarm)})" )
print( f"  baseline (a random active file touched within {K}): {100*sum(base)/max(1,len(base)):.0f}%" )
print( f"  by commit SCATTER (files in the commit) -> alarm rate, follow-up rate" )
for lo, hi in [ ( 1, 1 ), ( 2, 3 ), ( 4, 7 ), ( 8, 15 ), ( 16, 30 ) ]:
    part = [ a for a in alarms if lo <= a[ 1 ] <= hi ]; pa = [ a for a in part if a[ 2 ] ]
    fu = sum( 1 for idx, sc, named in pa if any( touchedWithin( idx, B, K ) for B in named ) )
    if part:
        print( f"    {lo:2d}-{hi:2d} files: n={len(part):4d} alarmed={100*len(pa)/len(part):3.0f}%  follow-up={100*fu/max(1,len(pa)):3.0f}%" )
