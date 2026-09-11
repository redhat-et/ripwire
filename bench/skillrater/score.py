#!/usr/bin/env python3
"""score.py — score blind rater answers against a packet key, and pair arms.

    python3 bench/skillrater/score.py KEY_TSV ANSWERS_TSV [ANSWERS2_TSV ...] [--exclude-labels=a,b]

ANSWERS is `id<TAB>top1<TAB>top2` (a header line, blank lines and `#` comments are ignored; ids may
appear in any order). Prints per-answer-file hit@1 / hit@2 on positive rows (top-1 ∈ permitted set),
false fires on negative rows (top1 != none), and the per-label won/rows table; with several answer
files it also prints the pairwise net flipped rows (file2 − file1) on the positive rows, and the mean.
`--exclude-labels` drops positive rows whose permitted set touches any listed label (the merge-
inflation control). Missing or malformed ids are listed and counted as misses, never skipped.
"""
import pathlib, sys

def read_key( path ):
    key = {}
    for line in pathlib.Path( path ).read_text( encoding = "utf-8" ).splitlines()[1:]:
        if not line.strip():
            continue
        pid, label, prov = line.split( "\t" )
        key[pid] = ( set( label.split( "," ) ) if label != "none" else set(), prov )
    return key

def read_answers( path ):
    ans = {}
    for line in pathlib.Path( path ).read_text( encoding = "utf-8" ).splitlines():
        s = line.strip()
        if not s or s.startswith( "#" ) or s.lower().startswith( "id" ):
            continue
        cols = [ c.strip().strip( "`*" ) for c in s.replace( " | ", "\t" ).split( "\t" ) ]
        if len( cols ) < 2:
            continue
        ans[cols[0]] = ( cols[1], cols[2] if len( cols ) > 2 else "" )
    return ans

def score( key, ans, excluded ):
    hit1 = hit2 = pos = neg = fires = 0
    missing = []
    per = {}
    outcomes = {}
    for pid, ( permitted, prov ) in key.items():
        if pid not in ans:
            missing.append( pid )
        top1, top2 = ans.get( pid, ( "", "" ) )
        if not permitted:
            neg += 1
            fires += 1 if top1 and top1 != "none" else 0
            continue
        if excluded & permitted:
            continue
        pos += 1
        label = ",".join( sorted( permitted ) )
        per.setdefault( label, [ 0, 0 ] )[1] += 1
        ok1 = top1 in permitted
        hit1 += ok1
        hit2 += ok1 or ( top2 in permitted )
        per[label][0] += ok1
        outcomes[pid] = ok1
    return dict( hit1 = hit1, hit2 = hit2, pos = pos, neg = neg, fires = fires, missing = missing, per = per, outcomes = outcomes )

def main():
    opts = { a.split( "=", 1 )[0]: a.split( "=", 1 )[1] for a in sys.argv[1:] if a.startswith( "--" ) and "=" in a }
    pos = [ a for a in sys.argv[1:] if not a.startswith( "--" ) ]
    excluded = set( opts.get( "--exclude-labels", "" ).split( "," ) ) - { "" }
    key = read_key( pos[0] )
    results = []
    for path in pos[1:]:
        r = score( key, read_answers( path ), excluded )
        results.append( ( path, r ) )
        print( f"{path}: hit@1 {r['hit1']}/{r['pos']} ({100.0 * r['hit1'] / max( 1, r['pos'] ):.1f}%)  hit@2 {r['hit2']}/{r['pos']}"
               f"  neg-fires {r['fires']}/{r['neg']}  missing={len( r['missing'] )}{' ' + ','.join( r['missing'] ) if r['missing'] else ''}" )
        for label in sorted( r["per"] ):
            print( f"    {label:<45} {r['per'][label][0]:>2}/{r['per'][label][1]}" )
    if len( results ) >= 2:
        base = results[0][1]["outcomes"]
        for path, r in results[1:]:
            up = sum( 1 for p, ok in r["outcomes"].items() if ok and not base.get( p, False ) )
            down = sum( 1 for p, ok in r["outcomes"].items() if not ok and base.get( p, False ) )
            print( f"paired vs {results[0][0]}: {path}: newly-correct {up}, newly-wrong {down}, net {up - down:+d}" )
        print( f"mean hit@1 over {len( results )} files: {sum( r['hit1'] for _, r in results ) / len( results ):.1f}/{results[0][1]['pos']}" )

if __name__ == "__main__":
    sys.exit( main() )
