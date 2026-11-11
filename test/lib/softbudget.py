# softbudget.py — the soft --token-budget readers' shared helpers (lane forbudget-soft; CHECKLIST 32: one copy, not five).
#
# Five gates read a soft-target answer's ST invariant (fornotesbudgetcheck, forsoftbudgetcheck, compactlegendcheck,
# estchargecheck, forsigspancheck). Each keeps its own row reader (their dialects and row charges differ); what they share
# lives here. The gates export RIPWIRE_TESTLIB="$ROOT/test/lib" and import this file (sys.path insert), as crashsweepcheck
# does shardmatch.py. No state; pure functions of the answer text.
import json, re


# K-WRONGSYM / K-LEGEND: blocks appended after the ranked answer on their own allowance, outside est_tokens (the <syms> block, or its held
# stub, each with the legend comment right before it). A soft-target reader leaves them out of the sections it reserves from T.
APPENDED = re.compile( r"<!-- (?:ripwire for )?syms:(?:(?!-->).)*-->(?:<syms [^>]*/>|<syms .*?</syms>)(?=<graph fmt=|</ctx>)", re.S )
def strip_appended( t ):
    """The answer text less its appended, unpriced blocks (APPENDED)."""
    return APPENDED.sub( "", t )
def strip_appended_bytes( b ):
    """strip_appended on a bytes answer, byte-exact for the rest (surrogateescape keeps any non-UTF-8 byte as it was)."""
    return strip_appended( b.decode( 'utf-8', 'surrogateescape' ) ).encode( 'utf-8', 'surrogateescape' )


def tail_size( t ):
    """Bytes of the answer's tail: XML, the whole <tail>…</tail> element; JSON, the compact "tail" object.

    FIX1 R1: the refill reserves the tail at its HEAD-scoped size (the tail of the no-budget answer) when that is what binds,
    so maximality counts the tail at no less than the reference tail (an upper bound on the reserve: the check stays a bound).
    """
    if t.lstrip().startswith( "{" ):
        try: return len( json.dumps( json.loads( t ).get( "tail", {} ), separators=( ",", ":" ), ensure_ascii=False ).encode() )
        except ValueError: return 0
    m = re.search( r"<tail\b.*?</tail>", t, re.S )
    return len( m.group( 0 ).encode() ) if m else 0


def old_walk_tail_size( t ):
    """FOR-TAIL-WIDE fix 1 (review F1): bytes of the part of the answer's tail the old 40-row walk lists — the tail less its
    trailing p_only= rows (the widened, path-only rows come last) and the p_only attribute / keys. The soft refill reserves the
    tail at THIS size of the head-scoped tail (src/verbs_for.h, fileTailOldWalk), never at the widened rows. Its next= offset can
    differ from the old walk's by a digit or two (inside the readers' row slack)."""
    if t.lstrip().startswith( "{" ):
        try: tl = dict( json.loads( t ).get( "tail", {} ) )
        except ValueError: return 0
        k = int( tl.pop( "p_only", 0 ) or 0 ); tl.pop( "p_only_why", None )
        if k > 0:
            for key in ( "files", "sym" ):
                tl[ key ] = ( tl.get( key ) or [] )[ :-k ]
        return len( json.dumps( tl, separators=( ",", ":" ), ensure_ascii=False ).encode() )
    m = re.search( r"<tail\b.*?</tail>", t, re.S )
    if not m:
        return 0
    el = m.group( 0 ); km = re.search( r' p_only="(\d+)"', el.split( ">", 1 )[ 0 ] )
    if not km:
        return len( el.encode() )
    rows = re.findall( r"<t [^>]*/>", el ); k = int( km.group( 1 ) )
    return len( el.encode() ) - len( km.group( 0 ) ) - sum( len( r.encode() ) for r in rows[ -k: ] )


# ── FIX2 C1 (review rv-forbudget-soft-fix1; rule 4, CHECKLIST 1): the UPPER-bound twin of the relaxed maximality ──────────────
# FIX1 floored maximality's tail at the reference (no-budget) answer's tail: that only loosened the LOWER bound. Its twin bounds
# the rows from above: a cut served past the rank floor stops where T, less the other sections and the tail's reserve, runs out.
# A binary that ignores the tail's reserve (reserve = 0) serves rows into the bytes the tail was promised: RED here, while the
# lower bound and fits (rows <= T) both stay green on it. What bounds the rows (src/verbs_for.h, the soft refill and the tail's
# share; src/serialize.h forSigsBudgets / forSoftRowDropFill):
#   XML    rows = max(the cut, the refill). The refill charges every served section and the tail's reserve, min(its share, the
#          head-scoped tail): rows' charge <= T - sections - reserve + 13 (the "<sigs></sigs>" frame). At the cut, the tail's
#          share is T less the cut's PRINTED rows and the sections, and the tail fills that share (its last row may cross it). So
#          in both cases the PRINTED rows (the bytes inside <sigs>, without the zero cx=/ccx=/in= the ladder also charges) are
#          <= T - sections - min(served tail, ref tail) + the served tail's last row + 13. "sections" is the reader's U less the
#          tail: U here carries FIX1's floor (= sections + max(served, ref tail)), so sections = U - max(served tail, ref tail).
#   JSON   rows = max(the cut, the refill). The refill reserves only the tail; the cut is T less the stanzas the sigs budget
#          charges (header, surface counts, notes: the keys below that are neither the rows, the tail, nor the cut's own
#          disclosure). So rows <= T - min(those stanzas, min(served tail, ref tail)) + the tail's last row + 13.
JSON_UNCHARGED_KEYS = frozenset( ( "sigs", "tail", "sigs_shown", "sigs_total", "sigs_next", "sigs_next_offset", "sigs_past_target",
                                   "capped", "dropped_positive", "budget_tokens", "budget_bytes", "est_tokens", "over_ceiling" ) )
SIGS_FRAME_BYTES = 13   # "<sigs>" + "</sigs>": forSoftRowDropFill adds it to the rows' budget (serialize.h kSigsWrapperBytes)


def _jlen( v ):
    return len( json.dumps( v, separators=( ",", ":" ), ensure_ascii=False ).encode() )


def rows_printed( t ):
    """The rows as printed: XML, the bytes inside <sigs>; JSON, each "sigs" entry's compact bytes plus its comma. None when absent."""
    if t.lstrip().startswith( "{" ):
        try: d = json.loads( t )
        except ValueError: return None
        return sum( _jlen( e ) + 1 for e in d[ "sigs" ] ) if isinstance( d.get( "sigs" ), list ) else None
    m = re.search( r"<sigs\b[^>]*>(.*?)</sigs>", t, re.S )
    return len( m.group( 1 ).encode() ) if m else None


def tail_last_row( t ):
    """Bytes of the served tail's LAST row, the one that may cross the tail's share. XML: the last <t .../>; JSON: the last
    "files" entry plus its "sym" entry (each with its comma)."""
    if t.lstrip().startswith( "{" ):
        try: tl = json.loads( t ).get( "tail", {} )
        except ValueError: return 0
        f, s = tl.get( "files" ) or [], tl.get( "sym" ) or []
        return ( _jlen( f[ -1 ] ) + 1 if f else 0 ) + ( _jlen( s[ -1 ] ) + 1 if s else 0 )
    m = re.search( r"<tail\b.*?</tail>", t, re.S )
    rows = re.findall( r"<t [^>]*/>", m.group( 0 ) ) if m else []
    return len( rows[ -1 ].encode() ) if rows else 0


def json_charged_stanzas( t ):
    """Bytes of a JSON answer's stanzas the sigs budget charges: every top-level key (with its quotes, colon and comma) but the
    rows, the tail and the cut's own disclosure keys (JSON_UNCHARGED_KEYS)."""
    try: d = json.loads( t )
    except ValueError: return 0
    return sum( len( k.encode() ) + 4 + _jlen( v ) for k, v in d.items() if k not in JSON_UNCHARGED_KEYS )


def upper_bound( answer, ref, T, k, total, u_floored, ref_old=None ):
    """The upper-bound twin. Returns (ok, detail). Applies only to a cut (k < total) served past the rank floor (k > 4).
    `u_floored` is the reader's U including FIX1's tail floor (XML; ignored for JSON). A missing <sigs> is not ok.
    `ref_old`: the same reference answer on the pre-TAIL-SYM-WIDE tail (RIPWIRE_TAIL_SYM_WIDE_ROWS=0), whose widened rows are the
    p_only= suffix again, so the reserve's cap (the old walk's part) is read off it; without it, off `ref` (where a widened row
    with sym= reads as an old-walk row: a smaller room, so a reader that cannot pass it may fail where the binary is right).
    Resolution (forbudget-soft fix-1 review, F1): the XML twin carries about 1.8-2.8 rows of slack (measured on the fornotes
    corpus), because at a cut the tail fills less than its share and that unused share is real headroom the answer does not
    show, so this reader cannot recover it. A 1-row over-serve is therefore NOT caught in XML; JSON, which states its tail,
    catches it at most rungs. A tighter XML twin needs the cut disclosed in the answer."""
    if k >= total or k <= 4:
        return True, "upper=n/a"
    rows = rows_printed( answer )
    if rows is None:
        return False, "upper: no rows to measure (premise)"
    st, rt, ro = tail_size( answer ), tail_size( ref ), old_walk_tail_size( ref if ref_old is None else ref_old )   # ro: the reserve's cap (FOR-TAIL-WIDE F1)
    if answer.lstrip().startswith( "{" ):
        room = T - min( json_charged_stanzas( answer ), min( st, ro ) )
    else:
        room = T - ( u_floored - max( st, rt ) ) - min( st, ro )
    slack = tail_last_row( answer ) + SIGS_FRAME_BYTES
    ok = rows <= room + slack
    return ok, "upper: rows printed %d B %s room %d B + %d B slack (served tail %d, ref tail %d)" % (
        rows, "<=" if ok else ">", room, slack, st, rt )

# ── lane hrr (train 31; PROCESS rule 4, orchestrator ruling FIX1 §4(a)): the SET-prefix twin of an order-prefix arm ─────────────
# The routed no-budget --for answer reorders its first 8 rows (files_first=: each file's best row first), so a budgeted answer's
# rows are an ORDER prefix of it only in score order. Every order-prefix arm keeps running unchanged on the RIPWIRE_NO_HEAD_RR=1
# twin; with the reorder ON what must still hold is this: the reorder serves the twin's rows (as a set) and a budgeted / cut
# answer's rows are, as a set, the twin's first K rows (score ranks 1..K), so the continuation resumes with no gap and no repeat.
# Compared as MULTISETS (sorted lists), not sets: a row key (p:l:n, or (n, p)) can repeat — two overloads in one file — and a
# repeat in A beyond OFF's own count is still caught.
def set_prefix( a, on, off ):
    return bool( a ) and sorted( on ) == sorted( off ) and sorted( a ) == sorted( off[ :len( a ) ] )

def _row_lines( p ):
    return [ x for x in open( p, encoding='utf-8', errors='replace' ).read().split( "\n" ) if x ]

def strip_selftest():
    """CR 4486667657: a `<!-- syms:` quoted inside a body CDATA must not make strip_appended swallow body bytes up to the real block.
    -> list of failure texts (empty: all hold)."""
    body = '<b><![CDATA[x <!-- syms: quoted --> text <syms files="1"> more]]></b>'
    real = '<!-- syms: legend --><syms files="1"><y p="a.py:1" n="n" by="name"/></syms>'
    held = '<!-- ripwire for syms: held --><syms held="budget" next="--for=x"/>'
    graph = '<graph fmt="mermaid"><![CDATA[g]]></graph>'
    cases = [ ( "block", '<ctx>' + body + real + '</ctx>', '<ctx>' + body + '</ctx>' ),
              ( "held stub", '<ctx>' + body + held + '</ctx>', '<ctx>' + body + '</ctx>' ),
              ( "before <graph>", '<ctx>' + body + real + graph + '</ctx>', '<ctx>' + body + graph + '</ctx>' ),
              ( "twin: no block", '<ctx>' + body + '</ctx>', '<ctx>' + body + '</ctx>' ) ]
    bad = [ "%s: got %r" % ( name, strip_appended( src ) ) for name, src, want in cases if strip_appended( src ) != want ]
    # the bytes form (estchargecheck's A9/A10 readers): the same strip, and a non-UTF-8 byte outside the block survives it untouched
    raw = b'<ctx>\xff' + real.encode() + b'</ctx>'
    return bad + ( [] if strip_appended_bytes( raw ) == b'<ctx>\xff</ctx>' else [ "bytes: got %r" % strip_appended_bytes( raw ) ] )


if __name__ == "__main__":   # python3 softbudget.py setprefix A ON OFF  (rows files, one p:l:n per line): exit 0 | 1;  python3 softbudget.py strip-selftest: exit 0 | 1
    import sys
    if len( sys.argv ) == 2 and sys.argv[ 1 ] == "strip-selftest":
        bad = strip_selftest()
        print( "\n".join( bad ) )
        sys.exit( 1 if bad else 0 )
    if len( sys.argv ) != 5 or sys.argv[ 1 ] != "setprefix": sys.exit( 2 )
    sys.exit( 0 if set_prefix( *( _row_lines( p ) for p in sys.argv[ 2:5 ] ) ) else 1 )
