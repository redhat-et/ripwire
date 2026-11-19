#!/usr/bin/env python3
"""pathfold.py — the REFERENCE reader and writer of the folded test-path list (pf= on a <g> row, "(n folded):" on a
--situ line). Written from the rule in src/testmap.h's PATH-FOLD header, not from its code: it shares no line with
the C++, which is what makes it a second reference (test/affectedfoldcheck.sh) rather than a restatement.

THE FORM
    <g hops="2" n="4" pf="src/{a/{x,y}.test.ts,b.ts},README" run_each="node {p}"/>
 == <g hops="2" n="4" p="src/a/x.test.ts,src/a/y.test.ts,src/b.ts,README" run_each="node {p}"/>

THE READER'S RULE (expand). Split the list on the commas OUTSIDE braces. In each item PRE{A,B,…}SUF stands for
PREASUF,PREBSUF,… in that order, and an alternative may itself hold a brace group. It is bash brace expansion over
comma lists. A group of one alternative, an unclosed '{' and a stray '}' are malformed (ValueError): the writer never
produces them, so a reader that met one is not looking at this form.

THE WRITER'S RULE (fold), left to right over a list already in evidence order:
    a RUN is the maximal CONTIGUOUS stretch of items that share their first path component ("dir/");
    for a run of two or more: P = the longest common DIRECTORY prefix (it ends in '/'); strip it from each;
    S = the longest common suffix of the stripped items that starts at a '.', holds no '/', and leaves every item a
    non-empty file name (else shrunk to the next '.', else empty); strip it; the run is written P{fold(stripped)}S when
    that is strictly shorter than the run joined by commas, otherwise verbatim.
A list in which any path holds '{' or '}' is never folded. A row is folded only when that saves ROW_MIN bytes, and a
document only when its folded rows save DOC_MIN bytes in total — both measured on the unescaped, comma-joined list, so
the XML and the text dialect take the same decision.

    pathfold.py fold    < comma-list        pathfold.py expand < folded-list (one path per line)
    pathfold.py unfold xml|text FILE        the document with every folded row written back flat (the legacy bytes)
"""
import re
import sys

ROW_MIN = 8
DOC_MIN = 256


def _common_prefix( a, b ):
    n = min( len( a ), len( b ) )
    i = 0
    while i < n and a[i] == b[i]:
        i += 1
    return a[:i]


def _dir_prefix( run ):
    p = run[0]
    for s in run[1:]:
        p = _common_prefix( p, s )
    return p[ :p.rfind( "/" ) + 1 ]


def _suffix_ok( items, s ):
    return all( len( x ) > len( s ) and not x[ :-len( s ) ].endswith( "/" ) for x in items )


def _dot_suffix( items ):
    s = items[0][::-1]
    for x in items[1:]:
        s = _common_prefix( s, x[::-1] )
    s = s[::-1]
    s = s[ s.rfind( "/" ) + 1: ]
    while True:
        k = s.find( ".", 1 ) if s.startswith( "." ) and not _suffix_ok( items, s ) else s.find( "." )
        if k < 0:
            return ""
        s = s[k:]
        if _suffix_ok( items, s ):
            return s


def fold_items( items, sep = "," ):
    out = []
    i = 0
    while i < len( items ):
        cut = items[i].find( "/" )
        j = i + 1
        if cut >= 0:
            first = items[i][ :cut + 1 ]
            while j < len( items ) and items[j].startswith( first ):
                j += 1
        run = items[i:j]
        if len( run ) >= 2:
            P = _dir_prefix( run )
            inner = [ x[ len( P ): ] for x in run ]
            S = _dot_suffix( inner )
            if S:
                inner = [ x[ :-len( S ) ] for x in inner ]
            cand = P + "{" + fold_items( inner ) + "}" + S
            if len( cand ) < len( ",".join( run ) ):
                out.append( cand )
            else:
                out.extend( run )
        else:
            out.extend( run )
        i = j
    return sep.join( out )


def fold_row( paths ):
    """The folded list for one row, or None when the row keeps its flat form (a brace in a path, or under ROW_MIN)."""
    flat = ",".join( paths )
    if "{" in flat or "}" in flat:
        return None
    f = fold_items( paths )
    return f if len( flat ) - len( f ) >= ROW_MIN else None


def document_folds( rows ):
    """rows: one path list per group row of the document. True when the document is served folded."""
    saved = 0
    for paths in rows:
        f = fold_row( paths )
        if f is not None:
            saved += len( ",".join( paths ) ) - len( f )
    return saved >= DOC_MIN


def expand( text ):
    pos = 0

    def plist( inside ):
        nonlocal pos
        items = []
        while True:
            items.extend( pitem() )
            if pos < len( text ) and text[pos] == ",":
                pos += 1
                continue
            if inside and ( pos >= len( text ) or text[pos] != "}" ):
                raise ValueError( "unclosed '{' in %r" % text[:80] )
            return items

    def pitem():
        nonlocal pos
        cur = [ "" ]
        while pos < len( text ) and text[pos] not in ",}":
            if text[pos] == "{":
                pos += 1
                inner = plist( True )
                pos += 1
                if len( inner ) < 2:
                    raise ValueError( "a brace group of one alternative in %r" % text[:80] )
                cur = [ c + x for c in cur for x in inner ]
            else:
                j = pos
                while j < len( text ) and text[j] not in ",{}":
                    j += 1
                cur = [ c + text[pos:j] for c in cur ]
                pos = j
        return cur

    items = plist( False )
    if pos != len( text ):
        raise ValueError( "stray '}' at byte %d of %r" % ( pos, text[:80] ) )
    if any( x == "" for x in items ):
        raise ValueError( "an empty path in %r" % text[:80] )
    return items


def split_top( text, sep = "," ):
    """The items of a folded list, split on the separators outside braces (each item still folded). XML joins the
    top-level items with ',', the text dialect with ', ' — inside braces it is ',' in both."""
    out, depth, start, k = [], 0, 0, 0
    while k < len( text ):
        c = text[k]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif depth == 0 and text.startswith( sep, k ):
            out.append( text[start:k] )
            start = k + len( sep )
            k = start - 1
        k += 1
    out.append( text[start:] )
    return out


def expand_text_list( text ):
    """A folded text-dialect list ("a/{x,y}.py, b.py") as its full paths, in order."""
    return [ p for item in split_top( text, ", " ) for p in expand( item ) ]


_PF_ROW   = re.compile( r'(<g\b[^>]*?) pf="([^"]*)"' )
_TEXT_ROW = re.compile( r"^(\s*(?:\[[^\]]*\] )*\(\d+) folded\): (.*?)(\s{3}\(run(?: each)?: .*\))$" )


def unfold_xml( doc ):
    """Every pf="…" written back as p="…". XML escapes never produce ',', '{' or '}', so the escaped text is expanded
    as it stands and the result is the escaped flat list — no decode/encode round trip to get wrong."""
    return _PF_ROW.sub( lambda m: m.group( 1 ) + ' p="' + ",".join( expand( m.group( 2 ) ) ) + '"', doc )


def unfold_text( doc ):
    out = []
    for line in doc.split( "\n" ):
        m = _TEXT_ROW.match( line )
        if m:
            line = m.group( 1 ) + "): " + ", ".join( expand_text_list( m.group( 2 ) ) ) + m.group( 3 )
        out.append( line )
    return "\n".join( out )


def main( argv ):
    if len( argv ) >= 2 and argv[1] == "fold":
        sys.stdout.write( fold_items( sys.stdin.read().rstrip( "\n" ).split( "," ) ) + "\n" )
        return 0
    if len( argv ) >= 2 and argv[1] == "expand":
        sys.stdout.write( "".join( p + "\n" for p in expand( sys.stdin.read().rstrip( "\n" ) ) ) )
        return 0
    if len( argv ) == 4 and argv[1] == "unfold" and argv[2] in ( "xml", "text" ):
        doc = open( argv[3], encoding = "utf-8", newline = "" ).read()
        sys.stdout.write( unfold_xml( doc ) if argv[2] == "xml" else unfold_text( doc ) )
        return 0
    sys.stderr.write( __doc__ )
    return 2


if __name__ == "__main__":
    try:
        sys.exit( main( sys.argv ) )
    except ValueError as e:
        sys.stderr.write( "pathfold: malformed folded list: %s\n" % e )
        sys.exit( 2 )
