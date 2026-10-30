#!/usr/bin/env python3
"""The Ruby slice of a `--pin-census` v3 file: which mechanism decided each Ruby call site, and which
method names the single-definition tier binds most.

Usage:
    ripwire <corpus> --no-cache --pin-census=OUT.tsv >/dev/null
    python3 -I bench/ruby/census.py OUT.tsv [TOP]

Prints aggregates and METHOD NAMES only, never a caller or target id, so its output can be quoted for a
client corpus (docs/research/ruby-roadmap.md, "Corpora"). A row is a Ruby site when its caller's file ends
in one of RUBY_EXT. Census rows are a FLOOR on call sites: a site whose name has no in-tree definition
writes no row (the `# dispositions` line's `undefined=` counts those, for every language at once).
"""
import collections
import sys

RUBY_EXT = ( ".rb", ".rake", ".jbuilder" )   # the crawl's Ruby rows (src/ingest_crawl.h kLangTable)


def unescape( field ):
    """Undo the v3 field escape: \\\\, \\t, \\n, \\r and \\xHH."""
    out, i = [], 0
    while i < len( field ):
        c = field[ i ]
        if c == "\\" and i + 1 < len( field ):
            n = field[ i + 1 ]
            if n == "x" and i + 3 < len( field ):
                out.append( chr( int( field[ i + 2:i + 4 ], 16 ) ) )
                i += 4
                continue
            out.append( { "\\": "\\", "t": "\t", "n": "\n", "r": "\r" }.get( n, n ) )
            i += 2
            continue
        out.append( c )
        i += 1
    return "".join( out )


def main():
    path = sys.argv[ 1 ]
    top = int( sys.argv[ 2 ] ) if len( sys.argv ) > 2 else 15
    mech = collections.Counter()
    single = collections.Counter()
    singleTargets = collections.defaultdict( set )
    split = collections.Counter()
    external = collections.Counter()
    otherLang = 0
    with open( path, encoding="utf-8", errors="replace" ) as fh:
        for line in fh:
            if not line.startswith( "C\t" ):
                continue
            f = line.rstrip( "\n" ).split( "\t" )
            if not unescape( f[ 5 ] ).split( "::", 1 )[ 0 ].endswith( RUBY_EXT ):
                otherLang += 1
                continue
            m, callee = f[ 1 ], unescape( f[ 6 ] )
            targets = [ t for t in f[ 7 ].split( "|" ) if t ] if len( f ) > 7 else []
            mech[ m ] += 1
            if m == "split":
                split[ callee ] += 1
            elif m == "external":
                external[ callee ] += 1
            elif len( targets ) == 1:
                single[ callee ] += 1
                singleTargets[ callee ].add( targets[ 0 ] )
    print( f"ruby_rows={sum( mech.values() )} other_language_rows={otherLang}" )
    print( "mech " + " ".join( f"{k}={v}" for k, v in mech.most_common() ) )
    print( f"top {top} single-target names (sites, distinct targets):" )
    for name, n in single.most_common( top ):
        print( f"  {name}\t{n}\t{len( singleTargets[ name ] )}" )
    print( f"top {top} split names:" )
    for name, n in split.most_common( top ):
        print( f"  {name}\t{n}" )
    print( f"top {top} external names:" )
    for name, n in external.most_common( top ):
        print( f"  {name}\t{n}" )


if __name__ == "__main__":
    main()
