#!/usr/bin/env python3
"""passk.py — consistency and balance across k repeated blind-rater runs of ONE arm.

    python3 bench/skillrater/passk.py KEY_TSV ANSWERS1 [ANSWERS2 ...]

The k answer files are k independent runs of the same rater on the same packet. Prints, for the arm:
  per-run hit@1 on positives and negatives held quiet (top1 == none);
  per-run balanced accuracy = (hit@1 rate on positives + quiet rate on negatives) / 2 — the corpus holds far
    more positives than negatives, so a plain accuracy rewards a rater that fires on everything;
  pass^k = rows right in ALL k runs (positives: top1 in the permitted set; negatives: top1 == none), and
    pass@k = rows right in at least one run, each split by positive / negative.
A missing or malformed id counts as wrong in that run, never skipped (score.py's rule).
"""
import pathlib, sys

sys.path.insert( 0, str( pathlib.Path( __file__ ).resolve().parent ) )
from score import read_key, read_answers  # noqa: E402

def right( permitted, top1 ):
    return ( top1 == "none" ) if not permitted else ( top1 in permitted )

def main():
    if len( sys.argv ) < 3:
        print( __doc__ ); return 2
    key = read_key( sys.argv[1] )
    runs = [ read_answers( f ) for f in sys.argv[2:] ]
    pos = [ pid for pid, ( p, _ ) in key.items() if p ]
    neg = [ pid for pid, ( p, _ ) in key.items() if not p ]
    for f, ans in zip( sys.argv[2:], runs ):
        hp = sum( right( key[i][0], ans.get( i, ( "", "" ) )[0] ) for i in pos )
        hn = sum( right( key[i][0], ans.get( i, ( "", "" ) )[0] ) for i in neg )
        bal = ( hp / len( pos ) + hn / len( neg ) ) / 2
        print( f"{pathlib.Path( f ).name}: positives {hp}/{len( pos )}  negatives quiet {hn}/{len( neg )}  balanced {bal:.3f}" )
    k = len( runs )
    def tally( ids ):
        allk = sum( all( right( key[i][0], a.get( i, ( "", "" ) )[0] ) for a in runs ) for i in ids )
        anyk = sum( any( right( key[i][0], a.get( i, ( "", "" ) )[0] ) for a in runs ) for i in ids )
        return allk, anyk
    pa, pn = tally( pos ), tally( neg )
    print( f"k={k}  pass^k positives {pa[0]}/{len( pos )}  negatives {pn[0]}/{len( neg )}"
           f"  |  pass@k positives {pa[1]}/{len( pos )}  negatives {pn[1]}/{len( neg )}" )
    return 0

if __name__ == "__main__":
    sys.exit( main() )
