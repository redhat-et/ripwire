#!/usr/bin/env python3
"""sitecount.py -- derive a self-repo call-site count from source text, so a gate's count pin moves with the tree.

usage: sitecount.py ROOT NAME        prints `CALLS DEFS` for NAME over ROOT/src/**/*.{h,cpp}

Contract (B43 PINNED-SELF-COUNTS): a site is the identifier NAME, optionally qualified (`detail::NAME`) and optionally
with explicit template arguments (`NAME<T>`), followed by `(`, outside // and /* */ comments, string, raw-string and
character literals. A site whose matching `)` is followed by `{` (after any const / noexcept / trailing return type) is a
DEFINITION (qualifiers and a noexcept( expr ) are skipped); every other site is a CALL. Declarations `T NAME( args );` count as calls -- no counted name has one.
It is a lexical count, not a resolver: the gate that uses it compares it to ripwire's own --uses count, and a mismatch
means one of the two is wrong, which is the finding. Exit 0; 2 on a usage error.
"""
import os, re, sys

# A raw string's delimiter is any d-char sequence (up to 16, no space, parens, backslash or control char), not only \w
# (CodeRabbit #626 4548924389: R"-( " readWholeFile() " )-" exposed a call inside a literal).
STRIP = re.compile( r'//[^\n]*|/\*.*?\*/|R"([^ ()\\\t\v\f\n]{0,16})\(.*?\)\1"|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'', re.S )
QUALIFIER = re.compile( r'\s*(const\b|volatile\b|noexcept\b|override\b|final\b|&&|&)' )

def blank( m ):
    """A removed comment or literal keeps its newlines, and is at least one space, so it never joins two tokens
    (CodeRabbit #626 4548924406: return/**/readWholeFile( p ) read as returnreadWholeFile)."""
    return "\n" * m.group( 0 ).count( "\n" ) or " "

def skip_parens( text, i ):
    """text[i] is '(' -> the index after its balanced ')'."""
    depth = 0
    while i < len( text ):
        depth += { "(": 1, ")": -1 }.get( text[i], 0 )
        i += 1
        if depth == 0:
            break
    return i

def is_definition( text, i ):
    """i is just past a site's argument list: a body `{` follows after qualifiers, noexcept( expr ) included
    (CodeRabbit #626 4548924399), and an optional trailing return type."""
    for _ in range( 8 ):
        m = QUALIFIER.match( text, i )
        if not m or m.end() == i:
            break
        i = m.end()
        j = i + len( text[i:i + 64] ) - len( text[i:i + 64].lstrip() )
        if m.group( 1 ) == "noexcept" and j < len( text ) and text[j] == "(":
            i = skip_parens( text, j )
    return re.match( r'\s*(?:->[^{;]{0,200})?\{', text[i:i + 220] ) is not None

def count( root, name ):
    site = re.compile( r'(?<![\w])' + re.escape( name ) + r'\s*(?:<[^;(){}]*>)?\s*\(' )
    calls = defs = 0
    for d, dirs, files in os.walk( os.path.join( root, "src" ) ):
        dirs.sort()
        for f in sorted( files ):
            if not f.endswith( ( ".h", ".cpp" ) ):
                continue
            text = open( os.path.join( d, f ), errors="replace" ).read()
            text = STRIP.sub( blank, text )
            for m in site.finditer( text ):
                if is_definition( text, skip_parens( text, m.end() - 1 ) ):
                    defs += 1
                else:
                    calls += 1
    return calls, defs

if __name__ == "__main__":
    if len( sys.argv ) != 3:
        print( __doc__, file=sys.stderr )
        sys.exit( 2 )
    print( "%d %d" % count( sys.argv[1], sys.argv[2] ) )
