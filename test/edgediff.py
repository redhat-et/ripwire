#!/usr/bin/env python3
"""edgediff.py — the two-binary whole-tree edge audit (docs/EVALS.md §4, "Receiver-guard misfires").

Compares the call-edge surface of two ripwire maps of the SAME corpus and classifies every changed
caller, so a resolver change can be accounted site by site instead of read off `ambiguous=` — the gauge
in which a removed wrong pin and a recovered call NET to nearly zero (the depth-2 lane's REJECT finding,
lane/depth2-chains @ 21f75a9).

Usage:
    binaryA <corpus> --top-k=999999 --no-cache > a.xml
    binaryB <corpus> --top-k=999999 --no-cache > b.xml       # SAME corpus path — ids embed it
    python3 test/edgediff.py a.xml b.xml

Both maps must be full (--top-k at or above the symbol count); the script refuses truncated inputs by
checking shown= against symbols=.

What is compared, and what the classes mean:
  * A caller is keyed (file path, id-or-name, kind). Its edge surface is the MULTISET of its <c n=.../>
    children — the map emits one <c> per unique (caller, target definition) pair, so a call to a 2-def
    name carries multiplicity 2 — plus its amb="K" count.
  * RECOVERED      — a callee name gained its first edge under this caller (a call that emitted nothing
                     before: the shadow-deletion class).
  * SPLIT-WIDENED  — a name's multiplicity rose from >=1 (a lone pin became a wider split: the
                     wrong-narrow class), with amb corroborating.
  * REMOVED        — a name lost edges. The registered criterion requires this class EMPTY.
  * Header gauges (files/symbols/edges/ambiguous/unresolved) are diffed verbatim.
Every RECOVERED / SPLIT-WIDENED site is then hand-verified against source (--callees on the named
caller gives def-site targets); this script finds the sites, it does not judge them.

Deterministic: output sorted by (file, caller); exit 0 always (it is an instrument, not a gate — the
acceptance judgement lives in the EVALS registration it serves).
"""
import re
import sys
from collections import Counter


def parseMap( path ):
    text = open( path, encoding="utf-8", errors="replace" ).read()
    header = {}
    for gauge in ( "files", "symbols", "edges", "ambiguous", "unresolved", "shown" ):
        m = re.search( gauge + r"=(\d+)", text )
        header[ gauge ] = int( m.group( 1 ) ) if m else None
    callers = {}
    for fileMatch in re.finditer( r'<f p="([^"]*)"[^>]*>(.*?)</f>', text ):
        filePath, body = fileMatch.group( 1 ), fileMatch.group( 2 )
        for symMatch in re.finditer( r"<s ([^>]*)>((?:<c [^>]*/>)*)</s>", body ):
            attrs, children = symMatch.group( 1 ), symMatch.group( 2 )
            ident = re.search( r'id="([^"]*)"', attrs )
            name  = re.search( r'n="([^"]*)"', attrs )
            kind  = re.search( r't="([^"]*)"', attrs )
            amb   = re.search( r'amb="(\d+)"', attrs )
            key = ( filePath,
                    ident.group( 1 ) if ident else ( name.group( 1 ) if name else "?" ),
                    kind.group( 1 ) if kind else "?" )
            calleeNames = Counter( re.findall( r'<c n="([^"]*)"', children ) )
            ambCount = int( amb.group( 1 ) ) if amb else 0
            if key in callers:                       # same-named unscoped defs in one file: merge, stay deterministic
                oldNames, oldAmb = callers[ key ]
                calleeNames = oldNames + calleeNames
                ambCount += oldAmb
            callers[ key ] = ( calleeNames, ambCount )
    return header, callers


def main():
    if len( sys.argv ) != 3:
        print( __doc__ )
        return 2
    headerA, callersA = parseMap( sys.argv[ 1 ] )
    headerB, callersB = parseMap( sys.argv[ 2 ] )

    for label, header in ( ( "A", headerA ), ( "B", headerB ) ):
        if header[ "shown" ] is not None and header[ "symbols" ] is not None and header[ "shown" ] < header[ "symbols" ]:
            print( f"REFUSED: map {label} is truncated (shown={header['shown']} < symbols={header['symbols']}) — "
                   f"re-emit with --top-k at or above the symbol count" )
            return 2

    print( "== header gauges (A -> B)" )
    for gauge in ( "files", "symbols", "edges", "ambiguous", "unresolved" ):
        a, b = headerA[ gauge ], headerB[ gauge ]
        mark = "" if a == b else f"   DELTA {b - a:+d}"
        print( f"  {gauge}: {a} -> {b}{mark}" )

    recovered, widened, removed, ambOnly = [], [], [], []
    for key in sorted( set( callersA ) | set( callersB ) ):
        namesA, ambA = callersA.get( key, ( Counter(), 0 ) )
        namesB, ambB = callersB.get( key, ( Counter(), 0 ) )
        if namesA == namesB and ambA == ambB:
            continue
        filePath, ident, kind = key
        who = f"{filePath} :: {ident} [{kind}]"
        for name in sorted( set( namesA ) | set( namesB ) ):
            a, b = namesA[ name ], namesB[ name ]
            if a == 0 and b > 0:
                recovered.append( f"  {who}  +{name} x{b}  (amb {ambA}->{ambB})" )
            elif b > a:
                widened.append( f"  {who}  {name} x{a}->x{b}  (amb {ambA}->{ambB})" )
            elif b < a:
                removed.append( f"  {who}  {name} x{a}->x{b}  (amb {ambA}->{ambB})" )
        if namesA == namesB and ambA != ambB:
            ambOnly.append( f"  {who}  amb {ambA}->{ambB} with identical callee names" )

    for title, rows in ( ( "RECOVERED (a callee name gained its first edge — verify the call exists in source)", recovered ),
                         ( "SPLIT-WIDENED (a lone pin became a wider split — verify the old pin was wrong)", widened ),
                         ( "REMOVED (must be EMPTY under the registered criterion)", removed ),
                         ( "AMB-ONLY (amb moved with identical names — inspect by hand)", ambOnly ) ):
        print( f"== {title}: {len( rows )}" )
        for row in rows:
            print( row )
    return 0


if __name__ == "__main__":
    sys.exit( main() )
