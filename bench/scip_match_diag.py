#!/usr/bin/env python3
"""scip_match_diag.py — WHY does a SCIP occurrence fail to match a ripwire site? The failure-class
census behind the `--scip` overlay's "SCIP matched N% of occurrences" honesty line (src/scip.h) and
behind the coverage the S6-C silent-pin census reaches (docs/EVALS.md, "The census, RUN":
SCIP spoke on only 85 of 224 locality-pinned sites on astropy-14365 while the index was built from
that exact checkout — so the loss is in the JOIN, not in the index's age).

THE TWO JOINS `src/scip.h::buildScipOverlay` PERFORMS, reproduced here from the census side files so
each rejection can be named instead of guessed:
  DEF side  a SCIP *definition* occurrence at (relative_path, line) is a ripwire symbol iff a symbol
            is defined on EXACTLY that 1-based line ("first def wins" when several are).
  REF side  a SCIP *reference* occurrence whose symbol has a matched def is a covered call site iff
            ripwire holds a reference on EXACTLY that (file, line) — any role — inside a body, and the
            enclosing symbol is not the target itself.
The census (`--pin-census`, format v2) carries what this needs and the map does not: `S` rows (every
symbol with its def line), `C` rows (every DECIDED call site with its call-site line), `O` rows (the
overlay's covered sites, under --scip). The SCIP index is read by a stdlib protobuf walk — no
`google.protobuf` dependency, same as test/scipfix/make_index.py on the writing side.

WHAT IS REPORTED (every figure with its n; nothing here is a precision number)
  1. DEF side, per SCIP descriptor class (method `().`, type `#`, term `.`, parameter `(x)`, local,
     meta, other): definitions seen / matched a symbol on the exact line / near-miss (a same-named
     symbol within ±K lines — the decorator / multi-line-signature shape) / no such symbol at all.
  2. REF side, over occurrences the overlay counts as INTERNAL (target def matched): matched to a
     decided call site on that exact line / NON-CALL by construction (the SCIP symbol is a term,
     parameter or local — the census records calls, so these can never be covered) / line skew (a
     decided call to that callee sits within ±K lines of the occurrence) / self-loop / no decided
     call site at that line (ripwire extracted no Call reference, or its tier-3 drop left no row).
  3. SITE side — the number that binds the census: for every `C` row, and for the `locality` rows
     alone, covered (an `O` row exists) or one of: SCIP silent (no occurrence naming the callee inside
     the caller), SCIP local, target external to the index, def-side miss (near-miss or no symbol),
     def-line collision (another symbol won the line), line skew, self-loop.

USAGE
    python3 bench/scip_match_diag.py --bin ./build/ripwire --repo DIR --scip INDEX.scip [--window 5]
                                     [--label L] [--workdir W] [--json out.json] [--examples 3]
"""
import argparse
import collections
import json
import os
import re
import subprocess
import sys


# ---- SCIP index: stdlib protobuf walk ----------------------------------------------------------------
# Field numbers (scip.proto): Index.documents=2; Document.relative_path=1, occurrences=2, symbols=3;
# Occurrence.range=1 (packed int32 [startLine,startChar,(endLine,)endChar], 0-based), symbol=2,
# symbol_roles=3 (bit 0 = Definition); SymbolInformation.symbol=1, kind=5.

def _varint( b, i ):
    r = 0
    s = 0
    while True:
        c = b[ i ]
        i += 1
        r |= ( c & 0x7F ) << s
        s += 7
        if not ( c & 0x80 ):
            return r, i


def _fields( b ):
    i = 0
    n = len( b )
    while i < n:
        t, i = _varint( b, i )
        f, w = t >> 3, t & 7
        if w == 0:
            v, i = _varint( b, i )
            yield f, w, v
        elif w == 2:
            ln, i = _varint( b, i )
            yield f, w, b[ i:i + ln ]
            i += ln
        elif w == 1:
            yield f, w, b[ i:i + 8 ]
            i += 8
        elif w == 5:
            yield f, w, b[ i:i + 4 ]
            i += 4
        else:
            raise ValueError( "unsupported wire type %d" % w )


def _packed( b ):
    out = []
    i = 0
    while i < len( b ):
        v, i = _varint( b, i )
        out.append( v )
    return out


def read_scip( path ):
    """-> list of (relative_path, [ (line0, roles, symbol) ... ])"""
    data = open( path, "rb" ).read()
    docs = []
    for f, w, v in _fields( data ):
        if f != 2 or w != 2:
            continue
        rel = ""
        occs = []
        for df, dw, dv in _fields( v ):
            if df == 1 and dw == 2:
                rel = dv.decode( "utf-8", "replace" )
            elif df == 2 and dw == 2:
                rng = None
                sym = ""
                roles = 0
                for of, ow, ov in _fields( dv ):
                    if of == 1 and ow == 2:
                        rng = _packed( ov )
                    elif of == 1 and ow == 0:
                        rng = ( rng or [] ) + [ ov ]
                    elif of == 2 and ow == 2:
                        sym = ov.decode( "utf-8", "replace" )
                    elif of == 3 and ow == 0:
                        roles = ov
                if rng and sym:
                    occs.append( ( rng[ 0 ], roles, sym ) )
        docs.append( ( rel, occs ) )
    return docs


# ---- SCIP symbol grammar: the LAST descriptor names the thing and says what it is ---------------------
# `scheme manager pkg version descriptor+` — descriptors: `ns/` `Type#` `term.` `method().` `(param)`
# `meta:` `macro!`; `local N` for a file-local. Names may be backtick-quoted.

def last_descriptor( sym ):
    """-> (name, cls) with cls in method|type|term|parameter|meta|macro|local|other"""
    if sym.startswith( "local " ):
        return sym[ 6: ], "local"
    s = sym.rstrip()
    if s.endswith( ")." ):
        i = s.rfind( "(" )
        head = s[ :i ]
        return _tail_name( head ), "method"
    if s.endswith( ")" ):
        i = s.rfind( "(" )
        return s[ i + 1:-1 ].strip( "`" ), "parameter"
    tail = s[ -1 ]
    cls = { "#": "type", ".": "term", ":": "meta", "!": "macro", "/": "namespace" }.get( tail, "other" )
    return _tail_name( s[ :-1 ] ), cls


def _tail_name( s ):
    if s.endswith( "`" ):
        j = s.rfind( "`", 0, len( s ) - 1 )
        return s[ j + 1:-1 ]
    m = re.search( r"[^/#.:!() ]+$", s )
    return m.group( 0 ) if m else s


# ---- census side files -------------------------------------------------------------------------------

def run_census( binp, repo, out, extra ):
    cmd = [ binp, repo, "--pin-census=" + out, "--no-cache" ] + extra
    r = subprocess.run( cmd, capture_output = True, text = True )
    if r.returncode != 0:
        sys.stderr.write( "FAILED: %s\n%s\n" % ( " ".join( cmd ), r.stderr[ :2000 ] ) )
        sys.exit( 2 )
    note = [ ln for ln in r.stderr.splitlines() if "SCIP matched" in ln ]
    return out, ( note[ 0 ] if note else "" )


def id_path( cid ):
    """`path::scope::name#N` -> path (the first `::` ends the path segment; paths hold no `::`)."""
    return cid.split( "::", 1 )[ 0 ]


def id_name( cid ):
    core = cid.rsplit( "#", 1 )[ 0 ]
    return core.rsplit( "::", 1 )[ -1 ]


def parse_census( path ):
    syms = []        # (id, kind, line)
    calls = []       # dict rows
    oracle = set()   # (caller_id, callee)
    with open( path, "r", encoding = "utf-8", errors = "replace" ) as fh:
        for line in fh:
            if line.startswith( "#" ):
                continue
            p = line.rstrip( "\n" ).split( "\t" )
            if p[ 0 ] == "S" and len( p ) >= 4:
                syms.append( ( p[ 1 ], p[ 2 ], int( p[ 3 ] ) ) )
            elif p[ 0 ] == "C" and len( p ) >= 9:
                calls.append( { "mech": p[ 1 ], "caller": p[ 5 ], "callee": p[ 6 ],
                                "targets": [ t for t in p[ 7 ].split( "|" ) if t ], "line": int( p[ 8 ] ) } )
            elif p[ 0 ] == "O" and len( p ) >= 4:
                oracle.add( ( p[ 1 ], p[ 2 ] ) )
    return syms, calls, oracle


# ---- the diagnosis -----------------------------------------------------------------------------------

def source_lines( repo ):
    cache = {}

    def get( rel, line1 ):
        if rel not in cache:
            try:
                with open( os.path.join( repo, rel ), "r", encoding = "utf-8", errors = "replace" ) as fh:
                    cache[ rel ] = fh.read().split( "\n" )
            except OSError:
                cache[ rel ] = []
        ls = cache[ rel ]
        return ls[ line1 - 1 ] if 0 < line1 <= len( ls ) else ""
    return get


def line_shape( text, name ):
    """file_scope (column-0 statement: no enclosing symbol, absent from the census BY DESIGN) |
       call (`name(` on the line) | mention (the name appears without a call: import, annotation,
       isinstance, passed as a value, inheritance)."""
    if text and not text[ 0 ].isspace():
        return "file_scope"
    if re.search( r"\b" + re.escape( name ) + r"\s*\(", text ):
        return "call"
    return "mention"


def diagnose( docs, syms, calls, oracle, window, n_examples, src ):
    # symbol tables
    sym_at = {}                                  # (path, line) -> [ (id, kind) ]  in id order ("first def wins")
    sym_by_name = collections.defaultdict( list )   # (path, name) -> [ line ]
    paths = set()
    for cid, kind, line in syms:
        p = id_path( cid )
        paths.add( p )
        sym_at.setdefault( ( p, line ), [] ).append( ( cid, kind ) )
        sym_by_name[ ( p, id_name( cid ) ) ].append( line )

    # decided call sites
    call_at = collections.defaultdict( list )       # (path, line) -> [ row ]
    call_by_callee = collections.defaultdict( list )   # (path, callee) -> [ line ]
    for row in calls:
        p = id_path( row[ "caller" ] )
        call_at[ ( p, row[ "line" ] ) ].append( row )
        call_by_callee[ ( p, row[ "callee" ] ) ].append( row[ "line" ] )

    ex = collections.defaultdict( list )

    def example( key, text ):
        if len( ex[ key ] ) < n_examples:
            ex[ key ].append( text )

    # ---- 1. DEF side --------------------------------------------------------------------------------
    defs = {}                                    # scip symbol -> (path, line1) of its FIRST definition occurrence
    def_stat = collections.defaultdict( lambda: collections.Counter() )
    def_match = {}                               # scip symbol -> ripwire id (exact-line, first def wins)
    mapped_docs = 0
    for rel, occs in docs:
        if rel not in paths:
            continue
        mapped_docs += 1
        for line0, roles, sym in occs:
            if not ( roles & 1 ):
                continue
            name, cls = last_descriptor( sym )
            line1 = line0 + 1
            if sym not in defs:
                defs[ sym ] = ( rel, line1 )
            st = def_stat[ cls ]
            st[ "seen" ] += 1
            here = sym_at.get( ( rel, line1 ) )
            if here:
                st[ "matched" ] += 1
                if sym not in def_match:
                    def_match[ sym ] = here[ 0 ][ 0 ]
                if id_name( here[ 0 ][ 0 ] ) != name:
                    st[ "matched_other_name" ] += 1        # the line held a different symbol first
                    example( "def/" + cls + "/other-name", "%s:%d %s -> %s" % ( rel, line1, sym, here[ 0 ][ 0 ] ) )
                continue
            near = [ l for l in sym_by_name.get( ( rel, name ), [] ) if abs( l - line1 ) <= window ]
            if near:
                st[ "near_miss" ] += 1
                st[ "near_delta_%+d" % ( near[ 0 ] - line1 ) ] += 1
                example( "def/" + cls + "/near-miss", "%s:%d %s (symbol at %d)" % ( rel, line1, sym, near[ 0 ] ) )
            else:
                st[ "no_symbol" ] += 1
                example( "def/" + cls + "/no-symbol", "%s:%d %s" % ( rel, line1, sym ) )

    # ---- 2. REF side (the overlay's "internal" denominator) ----------------------------------------
    ref_stat = collections.Counter()
    ref_by_cls = collections.defaultdict( collections.Counter )
    for rel, occs in docs:
        if rel not in paths:
            continue
        for line0, roles, sym in occs:
            if roles & 1:
                continue
            ref_stat[ "seen" ] += 1
            tgt = def_match.get( sym )
            if tgt is None:
                ref_stat[ "external_or_unmatched_def" ] += 1
                continue
            ref_stat[ "internal" ] += 1
            name, cls = last_descriptor( sym )
            line1 = line0 + 1
            callee = id_name( tgt )
            rows = [ r for r in call_at.get( ( rel, line1 ), [] ) if r[ "callee" ] == callee ]
            bucket = ref_by_cls[ cls ]
            bucket[ "internal" ] += 1
            if rows:
                bucket[ "call_matched" ] += 1
                ref_stat[ "call_matched" ] += 1
                continue
            if cls in ( "term", "parameter", "local", "meta", "namespace" ):
                bucket[ "non_call_by_construction" ] += 1
                ref_stat[ "non_call_by_construction" ] += 1
                continue
            shape = line_shape( src( rel, line1 ), callee )
            near = [ l for l in call_by_callee.get( ( rel, callee ), [] ) if 0 < abs( l - line1 ) <= window ]
            enclosing = [ r for r in call_at.get( ( rel, line1 ), [] ) ]
            if shape == "file_scope":
                why = "file_scope"
            elif shape == "mention":
                why = "mention_not_call"
            elif any( r[ "caller" ] == tgt for r in enclosing ) or ( rel, line1 ) in sym_at and tgt in [ s[ 0 ] for s in sym_at[ ( rel, line1 ) ] ]:
                why = "self_or_def_line"
            elif near:
                why = "line_skew"
                example( "ref/" + cls + "/line-skew", "%s:%d %s (call rows at %s)" % ( rel, line1, sym, near[ :3 ] ) )
            else:
                why = "call_no_decided_site"
                example( "ref/" + cls + "/call-no-site", "%s:%d %s | %s" % ( rel, line1, sym, src( rel, line1 ).strip()[ :70 ] ) )
            bucket[ why ] += 1
            ref_stat[ why ] += 1

    # ---- 3. SITE side — what the census can cover --------------------------------------------------
    occ_by_file = {}
    for rel, occs in docs:
        if rel in paths:
            occ_by_file[ rel ] = occs
    site_stat = collections.defaultdict( collections.Counter )
    for row in calls:
        p = id_path( row[ "caller" ] )
        callee = row[ "callee" ]
        line1 = row[ "line" ]
        for key in ( "all", row[ "mech" ] ):
            st = site_stat[ key ]
            st[ "sites" ] += 1
        if ( row[ "caller" ], callee ) in oracle:
            for key in ( "all", row[ "mech" ] ):
                site_stat[ key ][ "covered" ] += 1
            continue
        # classify the miss
        cands = [ ( l0 + 1, roles, sym ) for ( l0, roles, sym ) in occ_by_file.get( p, [] )
                  if not ( roles & 1 ) and last_descriptor( sym )[ 0 ] == callee ]
        here = [ c for c in cands if c[ 0 ] == line1 ]
        nearby = [ c for c in cands if 0 < abs( c[ 0 ] - line1 ) <= window ]
        if here:
            _, _, sym = here[ 0 ]
            name, cls = last_descriptor( sym )
            if cls == "local":
                why = "scip_local"
            elif sym not in defs:
                why = "target_external_to_index"
            elif sym not in def_match:
                drel, dline = defs[ sym ]
                near = [ l for l in sym_by_name.get( ( drel, name ), [] ) if abs( l - dline ) <= window ]
                why = "def_near_miss" if near else "def_no_symbol"
            elif id_name( def_match[ sym ] ) != callee:
                why = "def_line_collision"
            elif def_match[ sym ] == row[ "caller" ]:
                why = "self_loop"
            else:
                why = "unexplained"
            example( "site/%s/%s" % ( row[ "mech" ], why ), "%s:%d %s -> %s" % ( p, line1, callee, sym ) )
        elif nearby:
            why = "line_skew"
            example( "site/%s/%s" % ( row[ "mech" ], why ), "%s:%d %s (occurrence at %s)" % ( p, line1, callee, [ c[ 0 ] for c in nearby[ :3 ] ] ) )
        else:
            why = "scip_silent"
            example( "site/%s/%s" % ( row[ "mech" ], why ), "%s:%d %s" % ( p, line1, callee ) )
        for key in ( "all", row[ "mech" ] ):
            site_stat[ key ][ why ] += 1

    return { "mapped_docs": mapped_docs, "docs": len( docs ), "def": def_stat, "ref": ref_stat,
             "ref_by_cls": ref_by_cls, "site": site_stat, "examples": ex }


def pct( a, b ):
    return ( 100.0 * a / b ) if b else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--bin", default = "./build/ripwire" )
    ap.add_argument( "--repo", required = True )
    ap.add_argument( "--scip", required = True )
    ap.add_argument( "--workdir", default = None )
    ap.add_argument( "--label", default = None )
    ap.add_argument( "--exclude", action = "append", default = [] )
    ap.add_argument( "--window", type = int, default = 5 )
    ap.add_argument( "--examples", type = int, default = 3 )
    ap.add_argument( "--json", default = None )
    a = ap.parse_args()

    work = a.workdir or os.path.dirname( os.path.abspath( a.scip ) )
    label = a.label or os.path.basename( os.path.abspath( a.repo ) )
    extra = [ "--exclude=" + e for e in a.exclude ]
    plain, _ = run_census( a.bin, a.repo, os.path.join( work, label + ".plain.tsv" ), extra )
    withs, note = run_census( a.bin, a.repo, os.path.join( work, label + ".scip.tsv" ), extra + [ "--scip=" + a.scip ] )

    syms, calls, _ = parse_census( plain )
    _, _, oracle = parse_census( withs )
    docs = read_scip( a.scip )
    d = diagnose( docs, syms, calls, oracle, a.window, a.examples, source_lines( a.repo ) )

    print( "=" * 100 )
    print( "SCIP match-rate diagnosis — %s" % label )
    print( "  bin    %s" % os.path.abspath( a.bin ) )
    print( "  repo   %s" % os.path.abspath( a.repo ) )
    print( "  scip   %s (%d documents, %d mapped to a ripwire file)" % ( os.path.abspath( a.scip ), d[ "docs" ], d[ "mapped_docs" ] ) )
    print( "  census %d symbols, %d decided call sites, %d oracle (caller,callee) keys" % ( len( syms ), len( calls ), len( oracle ) ) )
    if note:
        print( "  binary %s" % note.strip() )
    print( "=" * 100 )
    print( "1. DEF side — SCIP definition occurrences -> a ripwire symbol on the exact line" )
    print( "   %-10s %8s %8s %6s %10s %10s   %s" % ( "class", "seen", "matched", "%", "near-miss", "no-symbol", "near-miss line deltas" ) )
    for cls in sorted( d[ "def" ], key = lambda c: -d[ "def" ][ c ][ "seen" ] ):
        st = d[ "def" ][ cls ]
        deltas = ", ".join( "%s:%d" % ( k[ 11: ], v ) for k, v in sorted( st.items() ) if k.startswith( "near_delta_" ) )
        print( "   %-10s %8d %8d %5.1f%% %10d %10d   %s" % ( cls, st[ "seen" ], st[ "matched" ], pct( st[ "matched" ], st[ "seen" ] ),
                                                            st[ "near_miss" ], st[ "no_symbol" ], deltas ) )
    print()
    r = d[ "ref" ]
    print( "2. REF side — occurrences the overlay counts as INTERNAL (target def matched): %d of %d seen" % ( r[ "internal" ], r[ "seen" ] ) )
    keys = ( "call_matched", "non_call_by_construction", "file_scope", "mention_not_call", "self_or_def_line", "line_skew", "call_no_decided_site" )
    for k in keys:
        print( "   %-28s %8d  %5.1f%% of internal" % ( k, r[ k ], pct( r[ k ], r[ "internal" ] ) ) )
    callable_den = r[ "call_matched" ] + r[ "line_skew" ] + r[ "call_no_decided_site" ] + r[ "self_or_def_line" ]
    print( "   CALL-OCCURRENCE MATCH RATE (call-shaped, inside a body, target def matched): %d / %d = %.1f%%"
           % ( r[ "call_matched" ], callable_den, pct( r[ "call_matched" ], callable_den ) ) )
    print( "   by descriptor class:" )
    for cls in sorted( d[ "ref_by_cls" ], key = lambda c: -d[ "ref_by_cls" ][ c ][ "internal" ] ):
        b = d[ "ref_by_cls" ][ cls ]
        print( "     %-10s internal=%-7d " % ( cls, b[ "internal" ] ) + " ".join( "%s=%d" % ( k, b[ k ] ) for k in keys[ 1: ] ) )
    print()
    print( "3. SITE side — decided call sites the oracle covers, and why the rest are not" )
    whys = [ "covered", "scip_silent", "scip_local", "target_external_to_index", "def_near_miss", "def_no_symbol",
             "def_line_collision", "line_skew", "self_loop", "unexplained" ]
    print( "   %-14s %7s " % ( "mechanism", "sites" ) + " ".join( "%9s" % w[ :9 ] for w in whys ) )
    for mech in [ "all", "locality", "receiver-rule", "cone", "arity", "split", "unique", "qualified" ]:
        st = d[ "site" ].get( mech )
        if not st:
            continue
        print( "   %-14s %7d " % ( mech, st[ "sites" ] ) + " ".join( "%9d" % st[ w ] for w in whys ) )
    print()
    print( "examples (first %d per class):" % a.examples )
    for k in sorted( d[ "examples" ] ):
        for t in d[ "examples" ][ k ]:
            print( "   %-36s %s" % ( k, t ) )
    if a.json:
        out = { "label": label, "def": { k: dict( v ) for k, v in d[ "def" ].items() }, "ref": dict( d[ "ref" ] ),
                "ref_by_cls": { k: dict( v ) for k, v in d[ "ref_by_cls" ].items() },
                "site": { k: dict( v ) for k, v in d[ "site" ].items() }, "note": note.strip() }
        with open( a.json, "w" ) as fh:
            json.dump( out, fh, indent = 1, sort_keys = True )


if __name__ == "__main__":
    main()
