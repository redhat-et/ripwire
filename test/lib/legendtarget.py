# legendtarget.py — the legend SIZE gates' one verdict (PROCESS rule 5: stair-step TARGET + RUNAWAY GUARD; rule 4 twin).
#
# Sourced through test/lib/legendtarget.sh (lt_gate), never called by a gate directly. Five gates pin a legend's bytes
# (compactlegendcheck (U)/(L)/(M), graphlegendbudgetcheck, donelegendcheck, testgatelegendbudgetcheck, panellegendcheck);
# they share THIS verdict so the rule lives in one place (CHECKLIST 32), not five copies.
#
#   verdict ID MEASURED TARGET GMEASURED GUARD MODE REGISTRY DOC...   -> detail lines first, then the VERDICT as the LAST line
#                                                                      (a status word, then its message; the verdict is never followed by detail)
#       WITHIN      MEASURED <= TARGET (a smaller measure never fails)
#       EXPLAINED   MEASURED > TARGET and every excess byte is covered by registered PRESENT-ONLY clauses that ride
#       UNEXPLAINED MEASURED > TARGET and the registered riding clauses do not cover it (or none is registered)
#       OVERCLAIM   a registered clause claims more bytes than it renders (by > CLAIM_SLACK B): the registry is not trusted
#       NOTPRESENT  a registered clause rides while its attribute is not rendered: it is not present-only, so it explains nothing
#       STRICT      MODE=strict and MEASURED > TARGET: today's hard pin, the registry is not read (the rule 4 twin)
#       RUNAWAY     GMEASURED > GUARD: the hard ceiling well above typical; a bug signal, with the clause breakdown
#       BADINPUT    a number is missing/non-numeric, the registry is malformed, or a DOC is unreadable; also a 0 B measure or an
#                   answer with no legend comment at all (a vacuous size row never passes), unless the surface is named in
#                   LT_ALLOW_ZERO (space-separated ids; set by the gate after sourcing legendtarget.sh, which clears any inherited value)
#   validate REGISTRY                                                  -> "OK n" or "BAD reason"
#
# A clause RIDES when its marker (a verbatim substring of the clause) occurs in the answer's legend (every <!-- --> outside
# CDATA); it is PRESENT-ONLY on that answer when its attribute token (e.g. ` sites_at="`, `<near_sink`) occurs in the payload
# (everything else). Registry: test/legend_over_target.tsv, tab-separated, `#` lines are comments:
#   surface  clause  bytes  attr  marker  reason
import os, re, sys

CLAIM_SLACK = 24   # B: a registered clause may claim up to this many bytes more than the legend renders (separators, a trailing space)

COLS = ( "surface", "clause", "bytes", "attr", "marker", "reason" )


def split( b ):
    i = 0; n = len( b ); leg = []; pay = []
    while i < n:
        if b.startswith( "<![CDATA[", i ):
            j = b.find( "]]>", i ); j = n if j < 0 else j + 3; pay.append( b[ i:j ] ); i = j
        elif b.startswith( "<!--", i ):
            j = b.find( "-->", i ); j = n if j < 0 else j + 3; leg.append( b[ i:j ] ); i = j
        else:
            j = b.find( "<", i + 1 ); j = n if j < 0 else j; pay.append( b[ i:j ] ); i = j
    return "".join( leg ), "".join( pay )


def load( path ):
    rows = []; seen = set(); seen_markers = set()
    try:
        lines = open( path, encoding = "utf-8" ).read().split( "\n" )
    except OSError as e:
        return None, "cannot read registry %s: %s" % ( path, e.strerror )
    for k, line in enumerate( lines, 1 ):
        if not line.strip() or line.startswith( "#" ): continue
        f = line.split( "\t" )
        if len( f ) != len( COLS ): return None, "line %d has %d tab-separated fields, want %d (%s)" % ( k, len( f ), len( COLS ), " ".join( COLS ) )
        r = dict( zip( COLS, f ) )
        if not re.fullmatch( r"[1-9][0-9]*", r[ "bytes" ] ): return None, "line %d bytes=%r is not a positive integer" % ( k, r[ "bytes" ] )
        for c in ( "surface", "clause", "attr", "marker", "reason" ):
            if not r[ c ].strip(): return None, "line %d has an empty %s" % ( k, c )
        if "--" in r[ "marker" ]: return None, "line %d marker holds '--' (cannot occur inside an XML comment)" % k
        key = ( r[ "surface" ], r[ "clause" ] )
        if key in seen: return None, "line %d repeats %s %s" % ( k, key[ 0 ], key[ 1 ] )
        mkey = ( r[ "surface" ], r[ "marker" ] )   # two clauses on one marker would measure the one clause twice and double the allowance
        if mkey in seen_markers: return None, "line %d repeats the marker of %s %s (one clause per marker)" % ( k, mkey[ 0 ], r[ "clause" ] )
        seen.add( key ); seen_markers.add( mkey ); r[ "bytes" ] = int( r[ "bytes" ] ); rows.append( r )
    return rows, ""


def breakdown( leg, top = 6 ):
    # the clause breakdown a LEGEND-RUNAWAY prints: the legend cut at clause starts ("[", " | ", "<!--"), largest first
    parts = [ p for p in re.split( r"(?=\[)|(?<= \|) |(?=<!--)", leg ) if p.strip() ]
    parts.sort( key = lambda p: -len( p.encode() ) )
    return [ "  clause %5d B  %s" % ( len( p.encode() ), re.sub( r"\s+", " ", p )[ :72 ] ) for p in parts[ :top ] ]


def clause_bytes( leg, marker ):
    # the bytes the clause holding MARKER actually renders: from its start ("[", "<!--" or just after " | ") to the next such start or the comment end "-->";
    # -1 when the marker is not in the legend
    i = leg.find( marker )
    if i < 0: return -1
    starts = [ 0 ]; ends = [ len( leg ) ]
    for m in re.finditer( r"\[|<!--|-->| \| ", leg ):
        st = m.end() if m.group() == " | " else m.start()
        if st <= i: starts.append( st )
        elif st > i: ends.append( st )
    return len( leg[ max( starts ):min( ends ) ].rstrip().encode() )


def isnum( s ): return re.fullmatch( r"[0-9]+", s or "" ) is not None


def verdict( a ):
    if len( a ) < 8: print( "BADINPUT usage: verdict ID MEASURED TARGET GMEASURED GUARD MODE REGISTRY DOC..." ); return
    sid, meas, tgt, gmeas, guard, mode, reg = a[ :7 ]; docs = a[ 7: ]
    for nm, v in ( ( "measured", meas ), ( "target", tgt ), ( "guard measure", gmeas ), ( "guard", guard ) ):
        if not isnum( v ): print( "BADINPUT %s %r is not a number" % ( nm, v ) ); return
    if mode not in ( "target", "strict" ): print( "BADINPUT RIPWIRE_LEGEND_PINS=%r (want unset, target or strict)" % mode ); return
    meas, tgt, gmeas, guard = int( meas ), int( tgt ), int( gmeas ), int( guard )
    leg = pay = ""
    for d in docs:
        try: l, p = split( open( d, encoding = "utf-8", errors = "replace" ).read() )
        except OSError as e: print( "BADINPUT cannot read %s: %s" % ( d, e.strerror ) ); return
        leg += l; pay += p
    if sid not in os.environ.get( "LT_ALLOW_ZERO", "" ).split():
        if meas == 0 or gmeas == 0:
            print( "BADINPUT %s measured %d B (guard measure %d B): a 0 B legend is a vacuous size row, not a pass "
                   "(a surface that really has none must be named in LT_ALLOW_ZERO)" % ( sid, meas, gmeas ) ); return
        if docs and "<!--" not in leg:
            print( "BADINPUT %s: the answer carries no legend comment (<!--), so its size row measured nothing "
                   "(a surface that really has none must be named in LT_ALLOW_ZERO)" % sid ); return
    if gmeas > guard:
        for x in breakdown( leg ): print( x )
        print( "RUNAWAY %s legend %d B > runaway guard %d B (target %d B): a bug signal (a present-only builder loop or an unbounded clause)" % ( sid, gmeas, guard, tgt ) )
        return
    if meas <= tgt: print( "WITHIN" ); return
    if mode == "strict":
        print( "STRICT %s %d B > %d B, today's hard pin (RIPWIRE_LEGEND_PINS=strict: the registry is not read)" % ( sid, meas, tgt ) ); return
    rows, err = load( reg )
    if rows is None: print( "BADINPUT registry: " + err ); return
    riding = [ r for r in rows if r[ "surface" ] == sid and r[ "marker" ] in leg ]
    notpresent = [ r for r in riding if r[ "attr" ] not in pay ]
    if notpresent:
        print( "NOTPRESENT %s %d B > target %d B: registered clause(s) %s ride WITHOUT their attribute rendered — not present-only, so they explain nothing"
               % ( sid, meas, tgt, ", ".join( "%s (attr %r)" % ( r[ "clause" ], r[ "attr" ] ) for r in notpresent ) ) )
        return
    measured = { r[ "clause" ]: clause_bytes( leg, r[ "marker" ] ) for r in riding }
    over = [ r for r in riding if r[ "bytes" ] > measured[ r[ "clause" ] ] + CLAIM_SLACK ]
    lines = [ "OVER-TARGET %s measured=%d target=%d: clause %s %d B, rides when %s is rendered — %s"
              % ( sid, meas, tgt, r[ "clause" ], r[ "bytes" ], r[ "attr" ].strip(), r[ "reason" ] ) for r in riding ]
    for x in lines: print( x )
    if over:
        print( "OVERCLAIM %s measured=%d target=%d: registered clause(s) [%s] over-claim: the registry says more bytes than the legend renders (slack %d B) — fix test/legend_over_target.tsv"
               % ( sid, meas, tgt, ", ".join( "%s claims %d B, renders %d B" % ( r[ "clause" ], r[ "bytes" ], measured[ r[ "clause" ] ] ) for r in over ), CLAIM_SLACK ) )
        return
    allow = sum( min( r[ "bytes" ], measured[ r[ "clause" ] ] ) for r in riding ); excess = meas - tgt
    if excess <= allow:
        print( "EXPLAINED %s %d B over target, covered by %d B of registered present-only clause(s)" % ( sid, excess, allow ) )
    else:
        print( "UNEXPLAINED %s measured=%d target=%d: %d B over, registered riding present-only clauses cover %d B (min of registered and rendered bytes) — register the clause "
               "(present-only) in test/legend_over_target.tsv with its reason, or cut it" % ( sid, meas, tgt, excess, allow ) )


if __name__ == "__main__":
    if len( sys.argv ) >= 2 and sys.argv[ 1 ] == "verdict": verdict( sys.argv[ 2: ] )
    elif len( sys.argv ) == 3 and sys.argv[ 1 ] == "validate":
        rows, err = load( sys.argv[ 2 ] )
        print( "OK %d" % len( rows ) if rows is not None else "BAD " + err )
    else: print( "BADINPUT usage: legendtarget.py verdict|validate ..." )
