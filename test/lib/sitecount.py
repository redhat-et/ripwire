#!/usr/bin/env python3
"""sitecount.py -- derive a self-repo call-site count from source text, so a gate's count pin moves with the tree.

usage: sitecount.py ROOT NAME        prints `CALLS DEFS` for NAME over ROOT/src/**/*.{h,cpp}

Contract (B43 PINNED-SELF-COUNTS): a site is the identifier NAME, optionally qualified (`detail::NAME`) and optionally
with explicit template arguments (`NAME<T>`), followed by `(`, outside // and /* */ comments, string, raw-string and
character literals. A site whose matching `)` is followed by `{` (after any const / noexcept / trailing return type) is a
DEFINITION; every other site is a CALL. Declarations `T NAME( args );` count as calls -- no counted name has one.
It is a lexical count, not a resolver: the gate that uses it compares it to ripwire's own --uses count, and a mismatch
means one of the two is wrong, which is the finding. Exit 0; 2 on a usage error.
"""
import os, re, sys

STRIP = re.compile( r'//[^\n]*|/\*.*?\*/|R"(\w*)\(.*?\)\1"|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'', re.S )
DEF_TAIL = re.compile( r'(?:\s|const\b|noexcept\b)*(?:->[^{;]*)?\{' )

def count( root, name ):
    site = re.compile( r'(?<![\w])' + re.escape( name ) + r'\s*(?:<[^;(){}]*>)?\s*\(' )
    calls = defs = 0
    for d, dirs, files in os.walk( os.path.join( root, "src" ) ):
        dirs.sort()
        for f in sorted( files ):
            if not f.endswith( ( ".h", ".cpp" ) ):
                continue
            text = open( os.path.join( d, f ), errors="replace" ).read()
            text = STRIP.sub( lambda m: "\n" * m.group( 0 ).count( "\n" ), text )
            for m in site.finditer( text ):
                i, depth = m.end(), 1
                while i < len( text ) and depth:
                    depth += { "(": 1, ")": -1 }.get( text[i], 0 )
                    i += 1
                if DEF_TAIL.match( text, i ) and DEF_TAIL.match( text, i ).end() - i < 200:
                    defs += 1
                else:
                    calls += 1
    return calls, defs

if __name__ == "__main__":
    if len( sys.argv ) != 3:
        print( __doc__, file=sys.stderr )
        sys.exit( 2 )
    print( "%d %d" % count( sys.argv[1], sys.argv[2] ) )
