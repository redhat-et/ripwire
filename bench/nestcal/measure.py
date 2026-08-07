#!/usr/bin/env python3
"""nestcal — per-symbol nesting-metric extraction for the else/elif calibration round.

Runs `ripwire <corpus> --metrics --no-cache`, parses the per-symbol rows, and writes a TSV of
(id, nest, humps, deep, cx, ccx, loc) with ids made CORPUS-RELATIVE (never absolute — the public
check forbids home paths in committed bench artifacts) plus a summary JSON with the nest histogram.

Usage: measure.py BINARY CORPUS_ROOT LABEL OUTDIR
"""
import json, re, subprocess, sys
from pathlib import Path


def main() -> int:
    binary, corpus, label, outdir = sys.argv[1:5]
    corpus = str( Path( corpus ).resolve() )
    xml = subprocess.run( [ binary, corpus, "--metrics", "--no-cache", "--max-tokens=100000000" ],
                          capture_output=True, text=True, check=True ).stdout
    rows = []
    cur_file = ""
    for tag in xml.split( ">" ):
        fm = re.search( r'<f p="([^"]*)"', tag )
        if fm:
            cur_file = fm.group( 1 )
        if not tag.lstrip().startswith( "<s " ):
            continue
        a = dict( re.findall( r'(\w+)="([^"]*)"', tag ) )
        if "nest" not in a:                       # rows with no nest= carry no nesting facts at all
            continue
        rel  = cur_file[len( corpus ) + 1:] if cur_file.startswith( corpus ) else cur_file
        sid  = a.get( "id", "" )
        sid  = sid.replace( corpus + "/", "" ) if sid else f"{rel}::{a.get('n','?')}"
        rows.append( ( sid, int( a["nest"] ), int( a.get( "humps", 0 ) ), int( a.get( "deep", 0 ) ),
                       int( a.get( "cx", 0 ) ), int( a.get( "ccx", 0 ) ), int( a.get( "loc", 0 ) ) ) )
    rows.sort()
    out = Path( outdir )
    out.mkdir( parents=True, exist_ok=True )
    with open( out / f"{label}.tsv", "w" ) as f:
        f.write( "id\tnest\thumps\tdeep\tcx\tccx\tloc\n" )
        for r in rows:
            f.write( "\t".join( map( str, r ) ) + "\n" )
    hist = {}
    for r in rows:
        hist[r[1]] = hist.get( r[1], 0 ) + 1
    summary = {
        "label": label, "symbols_with_nest": len( rows ),
        "nest_hist": { str( k ): hist[k] for k in sorted( hist ) },
        "total_humps": sum( r[2] for r in rows ),
        "rows_with_humps": sum( 1 for r in rows if r[2] > 0 ),
        "total_deep": sum( r[3] for r in rows ),
        "max_nest": max( ( r[1] for r in rows ), default=0 ),
    }
    with open( out / f"{label}.summary.json", "w" ) as f:
        json.dump( summary, f, indent=2, sort_keys=True )
    print( json.dumps( summary, indent=2, sort_keys=True ) )
    return 0


if __name__ == "__main__":
    sys.exit( main() )
