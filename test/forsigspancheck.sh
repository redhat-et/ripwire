#!/usr/bin/env bash
# forsigspancheck.sh — a --for <d> row says where its definition ENDS (e=), the one-hop slots go to top rows whose
# edges are proven, and the defining code outranks the docs that describe it.
#
#   test/forsigspancheck.sh                          # uses build/ripwire on test/forcompletefix
#   RIPWIRE_BIN=asan/ripwire test/forsigspancheck.sh
#   test/forsigspancheck.sh build_base/ripwire       # the RED run (a pre-change binary)
#
# THE GAPS (each seen in graded answers; the fixture paraphrases them as minimal code):
#   (1) SPAN. A <d> row carried only l= (the line of the definition's name). "Which body holds line N" — the question a
#       reader asks of every gold item that lives INSIDE a function — was not answerable from the row; a peer that
#       printed start-end lines got the credit.
#   (2) HOP SLOT. The compact answer hop-expands its ranked head in rank order and the first row with ANY resolved
#       callee took the slot: an off-topic getter whose one callee row was a call bound by name alone (`bag.lookup()`
#       on an untyped local) spent the slot and printed a false edge.
#   (3) DOCS FIRST. Markdown headings that repeat the question's words filled the ranked rows above the code that
#       defines the answer (on one graded answer about half of the shown rows were headings).
#
# THE CONTRACT.
#   (1) Every <d> row of a --for answer whose definition extent is KNOWN carries e="N" right after l=: the 1-based line
#       of the definition's LAST line (body-inclusive; a declaration's own last line; e == l for a one-line definition).
#       l= keeps its meaning (the NAME's line), so a definition may start above l= (a return type on the line before,
#       a decorator). e= is ABSENT — never 0, never a guess — when the extent is not known: a row flagged
#       extent_suspect=, a markdown/doc row (not a code body). Other verbs keep their bytes (no e= outside --for).
#   (2) A hop slot (<h> row) goes only to a top-ranked row with at least ONE proven callee edge; a row whose every
#       callee edge was bound by name alone gets no <h> row. Rows that keep a slot keep it in rank order.
#   (3) When the question does not name docs, no markdown row ranks above the code rows that define the answer, and
#       markdown rows are at most a quarter of the shown <d> rows. A question that names docs still gets a docs row
#       in its top five (the twin that must hold).
#
# ARMS (one fixture root per language under test/forcompletefix/; each indexed on its own):
#   (E)  e= values: C Sampler_average l=6 e=14 (return type on the line above the name), Sampler_scale l=3 e=3
#        (a one-line definition), the header prototype Sampler_collectAll l=57 e=57; TS createContext l=11 e=18 (a
#        multi-line signature), handle l=20 e=22; Python _compute l=12 e=13 (a decorator above), evict_entries l=15
#        e=20 (a multi-line signature). Oracle on EVERY row that carries e=: l <= e <= the file's line count, and
#        the e= line closes the definition (brace languages, unless e == l: the line holds `}` or ends with `;`/`)`; Python: the next
#        non-blank line is indented no deeper than the def, or EOF). e= sits right after l=.
#   (U)  unknown extent: Sampler_window and SampleWindow (extent_suspect="head") and every docs/*.md row carry NO
#        e=; every other <d> row carries one (a present e= is never dropped silently either).
#   (B)  an explicit --token-budget TIGHTER than the default signature budget (1200 tokens): no e= row and no e= clause,
#        XML and JSON (the budget's rows and est_tokens promise stay what they were; charging e= there cost rows, exempting
#        it broke the promise). Twin: --token-budget=8000 (above the default share) carries e= on its rows.
#   (O)  outside --for: --pack-signatures <d> rows and the default map's rows carry no e=.
#   (H)  hop slots: TS — contextHost (only callee: a name-only `bag.lookup()`) has no <h> row; createContext keeps
#        one. Python — Downloader.pull (only callee: a name-only `source.fetch_entry()`) has no <h> row; fetch_entry
#        keeps one. C near miss — Sampler_collectAll keeps its <h> row. <h> rows follow the <d> rows' r= order.
#        The two "no <h> row" arms need the receiver-evidence hedge (a name-only row marked via="name"); on a binary
#        without it they SKIP by name ("expects FE-B"), detected on this fixture — never a silent PASS.
#   (R)  code above docs as a REORDER of the shown set (coordinator rule: it reorders, never shrinks the doc rows shown):
#        the TS questions answered with the rule and with RIPWIRE_NO_DOCS_AFTER_CODE=1 (plain score order) show the
#        same row SET and r= multiset; with the rule every code row precedes every doc row, rows stay in r= order, and
#        <sigs docs_after_code="N"> counts the doc rows that moved (with its reading). Near misses: the same at a
#        --token-budget that cuts <sigs> (a demotion would evict docs there: red on the score-demotion build), and a
#        question whose topic ("dropped after the response") only a docs row names keeps that row. Twin: "Where do the
#        docs describe the context lifecycle?" keeps a docs row in its top five.
#   (T)  a TIGHT explicit ceiling (--token-budget / MCP budget_tokens below the default signature share) gets neither the
#        reorder nor its uncharged note: the answer is byte-equal to the RIPWIRE_NO_DOCS_AFTER_CODE=1 twin (which is the
#        pre-reorder answer), XML, JSON and MCP, at 700 and 1200 on the TS fixture. At 1200 (forbudget-soft, rule 4: an
#        explicit --token-budget is a SOFT target over the <sigs> rows, est_tokens may exceed N) the old "est_tokens <= 1200,
#        no over_ceiling the twin lacks" half is replaced by NOLBL (no over_ceiling= on either answer) + ST (the rows' charge
#        fits T = N x 2.36 x 0.9 bytes or is the rank 1..4 floor; a cut is maximal against the uncut plain-order answer and
#        carries capped + next=), XML and JSON (RED on base d4325a8c: the hard ceiling cut 10 of 16 / 13 of 16 rows with
#        room left under T).
#        MCP est_tokens is the twin's (already above 1200 on base; not this rule's to fix). Near misses: no ceiling and
#        --token-budget=8000 still reorder and carry docs_after_code= with its reading, XML, JSON and MCP; a question that
#        names docs keeps score order at 1200 too.
#        A BODY ceiling (--max-tokens=N --detail=K, XML only: --json refuses the pair, MCP `for` has no max_tokens) is the third tight
#        ceiling: the same twin equality, est_tokens <= N, on the TS fixture at 1700 and the Python+docs fixture (pydocs) at 1760
#        (round C re-anchor: 1600 / 1660 before the tail carried the file page)
#        (RED at f4253d45: est 1634 > 1600 / 1725 > 1660, over_ceiling="1"); near miss --detail alone still reorders.
#   (J)  dialect parity: --for --json "sigs" entries carry "e" equal to the XML rows' e= (and none where XML has none).
#   (M)  the MCP `for` twin: the same e= on the C rows, none on the extent_suspect rows, and a legend clause for e=.
#   (L)  legend: --legend=full defines e= and says what it does NOT mean (absent = unknown, not 0; l= is the name's
#        line, not the definition's first line).
#   (N)  the experimental RIPWIRE_FOR_ENDLINES switch (serialize.h forEndLinesMode; default auto = arm (B)'s rule):
#        always — e= on the --token-budget=1200 rows, XML and JSON, and on the MCP `for` rows under budget_tokens=1200,
#        with the SAME <d> row set (n p l r) as auto there (e= never costs a row); est_tokens vs the budget is REPORTED
#        (may exceed it — that is why auto is the default), not gated. never — no e= and no e= clause at the default
#        ceiling (XML, JSON, MCP), same row set as auto. auto — byte-identical to unset (default and 1200). An unknown
#        value ("sometimes", "Always", "") — byte-identical to unset (so e= stays at the default: never read as never)
#        plus one stderr line naming the switch. Near miss: always does not put e= on --pack-signatures rows.
#   (K)  the predicates can fail: a row with e= < l=, a row with e= on an md row, a missing e= on a code row, and a
#        name-only hop row are each caught; a document with no --for root is never a pass. Every run must exit 0.
#
# FLOORS — named, not gated here:
#   * e= is the parser's span: a definition spliced by the preprocessor or a recovered parse is covered only by
#     extent_suspect= (rows with an unflagged but wrong span are not detected).
#   * the code-over-docs rule is checked on one fixture; the threshold for "names docs" is the question's wording.
#
# Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # a gate that indexes a repo must not inherit GIT_DIR/GIT_WORK_TREE (gitenvhermeticcheck D)
export RIPWIRE_TESTLIB="$ROOT/test/lib"   # softbudget.py: the soft-target readers, shared helpers (CHECKLIST 32)
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
CORPUS="$ROOT/test/forcompletefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "forsigspancheck: BIN=$BIN  CORPUS=$CORPUS"

run(){ local r="$1" f="$2"; shift 2; ( cd "$CORPUS/$r" && "$BIN" . --no-cache "$@" >"$f" 2>"$f.err" ); printf '%s' "$?" >"$f.rc"; }
ran_ok(){ local rc; rc="$( cat "$1.rc" 2>/dev/null )"; [ "$rc" = 0 ] && return 0; no "$2: the binary exited rc=${rc:-missing}"; return 1; }
ask(){ local f="$TMP/$1.$2.xml"; run "$1" "$f" "--for=$3"; printf '%s' "$f"; }

cat >"$TMP/rows.py" <<'PY'
import re, sys
def attrs( tag ):
    return dict( re.findall( r'\s([a-z_]+)="([^"]*)"', tag ) )
def load( path ):
    return open( path, encoding="utf-8", errors="replace" ).read()
def ctx_ok( doc ):
    return re.search( r"<ctx [^>]*>", doc ) is not None and "<sigs" in doc
def drows( doc ):
    """[(open tag, attrs)] of every <d …> row, in document order."""
    return [ ( t, attrs( t ) ) for t in re.findall( r"<d\s[^>]*>", strip_comments( doc ) ) ]
def hrows( doc ):
    return [ attrs( t ) for t in re.findall( r"<h\s[^>]*>", strip_comments( doc ) ) ]
def strip_comments( doc ):
    # legend text inside <!-- --> spells row shapes (`<d cx= ccx=>`); only real elements are rows
    return re.sub( r"<!--.*?-->", "", doc, flags=re.S )
def is_doc_row( a ):
    return a.get( "p", "" ).endswith( ( ".md", ".markdown", ".rst", ".txt" ) )
PY

# echeck ANSWER LABEL ROOTDIR SPEC… — SPEC = name:path:l:e  (a row n=name p=path l=l must carry e=e)
echeck(){
    local f="$1" label="$2" rootdir="$3"; shift 3
    python3 - "$TMP/rows.py" "$f" "$label" "$rootdir" "$@" <<'PY'
import os, re, sys
exec( open( sys.argv[ 1 ] ).read() )
path, label, rootdir = sys.argv[ 2: 5 ]
specs = sys.argv[ 5: ]
doc = load( path )
if not ctx_ok( doc ):
    print( "  FAIL  %s: NOROOT" % label ); sys.exit( 1 )
rows = drows( doc )
bad = 0
for spec in specs:
    n, p, l, e = spec.rsplit( ":", 3 )
    hit = [ ( t, a ) for t, a in rows if a.get( "n" ) == n and a.get( "p" ) == p and a.get( "l" ) == l ]
    if not hit:
        print( "  FAIL  %s: no <d n=%s p=%s l=%s> row (premise)" % ( label, n, p, l ) ); bad = 1; continue
    t, a = hit[ 0 ]
    if a.get( "e" ) != e:
        print( "  FAIL  %s: %s l=%s carries e=%r, expected %s" % ( label, n, l, a.get( "e" ), e ) ); bad = 1; continue
    if not re.match( r'<d l="[0-9]+" e="[0-9]+" ', t ):
        print( "  FAIL  %s: %s — e= does not sit right after l=: %s" % ( label, n, t[ :60 ] ) ); bad = 1; continue
    print( "  PASS  %s: %s l=%s e=%s" % ( label, n, l, e ) )
sys.exit( bad )
PY
    [ $? -eq 0 ] || { fail=1; return 1; }
}

# oracle ANSWER LABEL ROOTDIR — (E) oracle + (U) on every <d> row of one answer
oracle(){
    python3 - "$TMP/rows.py" "$1" "$2" "$3" <<'PY'
import os, re, sys
exec( open( sys.argv[ 1 ] ).read() )
path, label, rootdir = sys.argv[ 2: 5 ]
doc = load( path )
if not ctx_ok( doc ):
    print( "  FAIL  %s: NOROOT" % label ); sys.exit( 1 )
bad = []
checked = 0
for t, a in drows( doc ):
    n, p = a.get( "n" ), a.get( "p", "" )
    unknown = is_doc_row( a ) or "extent_suspect" in a
    if unknown:
        if "e" in a: bad.append( "%s (%s) carries e= though its extent is unknown" % ( n, p ) )
        continue
    if "e" not in a:
        bad.append( "%s (%s:%s) has a known extent and no e=" % ( n, p, a.get( "l" ) ) ); continue
    if not ( re.fullmatch( r"[0-9]+", a[ "e" ] ) and re.fullmatch( r"[0-9]+", a.get( "l", "" ) ) ):
        bad.append( "%s: l=/e= not numeric" % n ); continue
    l, e = int( a[ "l" ] ), int( a[ "e" ] )
    try:
        lines = open( os.path.join( rootdir, p ), encoding="utf-8", errors="replace" ).read().split( "\n" )
    except OSError:
        bad.append( "%s: cannot read %s (premise)" % ( n, p ) ); continue
    if lines and lines[ -1 ] == "": lines = lines[ :-1 ]
    if not ( 1 <= l <= e <= len( lines ) ):
        bad.append( "%s: l=%d e=%d outside 1..%d or e < l" % ( n, l, e, len( lines ) ) ); continue
    last = lines[ e - 1 ].rstrip()
    if p.endswith( ".py" ):
        ind = len( lines[ l - 1 ] ) - len( lines[ l - 1 ].lstrip() )
        nxt = next( ( x for x in lines[ e: ] if x.strip() ), None )
        if not last.strip() or ( nxt is not None and len( nxt ) - len( nxt.lstrip() ) > ind ):
            bad.append( "%s: e=%d does not close the def (line %r)" % ( n, e, last ) )
    elif e != l and not ( "}" in last or last.endswith( ";" ) or last.endswith( ")" ) ):
        bad.append( "%s: e=%d line %r does not close the definition" % ( n, e, last ) )
    checked += 1
if bad:
    for b in bad: print( "  FAIL  %s: %s" % ( label, b ) )
    sys.exit( 1 )
if checked == 0:
    print( "  FAIL  %s: no row carried e= (nothing checked)" % label ); sys.exit( 1 )
print( "  PASS  %s: %d e= rows close their definitions; unknown extents carry none" % ( label, checked ) )
PY
    [ $? -eq 0 ] || { fail=1; return 1; }
}

echo "(E)/(U) e= on <d> rows"
CE="$( ask c avg 'How does the sampler compute the average reading window?' )"
if ran_ok "$CE" "E/C"; then
    echeck "$CE" "E/C" "$CORPUS/c" Sampler_average:src/window.c:6:14 Sampler_scale:src/window.c:3:3 Sampler_collectAll:src/monitor.h:57:57
    oracle "$CE" "E+U/C" "$CORPUS/c"
    python3 - "$TMP/rows.py" "$CE" <<'PY'
import sys
exec( open( sys.argv[ 1 ] ).read() )
rows = [ a for _, a in drows( load( sys.argv[ 2 ] ) ) if a.get( "n" ) in ( "Sampler_window", "SampleWindow" ) ]
if len( rows ) < 2 or any( "extent_suspect" not in a for a in rows ):
    print( "  FAIL  U/C: premise — Sampler_window and SampleWindow are not both shown with extent_suspect=" ); sys.exit( 1 )
if any( "e" in a for a in rows ):
    print( "  FAIL  U/C: an extent_suspect row carries e=" ); sys.exit( 1 )
print( "  PASS  U/C: the two extent_suspect rows carry no e=" )
PY
    [ $? -eq 0 ] || fail=1
fi
TE="$( ask ts ctx 'How is a per-request context created?' )"
if ran_ok "$TE" "E/TS"; then
    echeck "$TE" "E/TS" "$CORPUS/ts" Application.createContext:src/application.ts:11:18 Application.handle:src/application.ts:20:22   # js-def-naming: a TS method row names its class
    oracle "$TE" "E+U/TS" "$CORPUS/ts"
fi
PE="$( ask py compute 'What does LookupCache._compute return, and how are entries evicted?' )"
if ran_ok "$PE" "E/PY"; then
    echeck "$PE" "E/PY" "$CORPUS/py" LookupCache._compute:src/pump/cache.py:12:13 LookupCache.evict_entries:src/pump/cache.py:15:20
    oracle "$PE" "E+U/PY" "$CORPUS/py"
fi
JE="$( ask js run 'How does a queued job get run?' )"
if ran_ok "$JE" "E/JS"; then
    oracle "$JE" "E+U/JS" "$CORPUS/js"
fi

echo "(B) an explicit token budget: no e= at all (its rows and its est_tokens promise stay what they were)"
for spec in "xml|" "json|--json"; do
    tag="${spec%%|*}"; extra="${spec#*|}"; f="$TMP/ts.budget.$tag"
    if [ -n "$extra" ]; then run ts "$f" "--for=How is a per-request context created?" --token-budget=1200 "$extra"; else run ts "$f" "--for=How is a per-request context created?" --token-budget=1200; fi
    if ran_ok "$f" "B/$tag"; then
        if ! grep -q -e '<d ' -e '"sigs"' "$f"; then no "B/$tag: no rows to check (premise)"
        elif grep -Eq ' e="[0-9]+"|,"e":[0-9]+|e= on a d row|d e= its last line' "$f"; then no "B/$tag: a budgeted answer carries e= or its legend clause"
        else ok "B/$tag: --token-budget=1200 answer carries no e= and no e= clause"; fi
    fi
done

W8="$TMP/ts.budget8000"; run ts "$W8" "--for=How is a per-request context created?" --token-budget=8000
if ran_ok "$W8" "B twin"; then
    if grep -Eq '<d l="[0-9]+" e="[0-9]+"' "$W8"; then ok "B twin: --token-budget=8000 (at or above the default share) carries e="; else no "B twin: --token-budget=8000 carries no e="; fi
fi

echo "(O) outside --for: no e= on other verbs' rows"
for spec in "packsig:--pack-signatures" "map:"; do
    tag="${spec%%:*}"; arg="${spec#*:}"; f="$TMP/c.out.$tag.xml"
    if [ -n "$arg" ]; then run c "$f" "$arg"; else run c "$f"; fi
    if ran_ok "$f" "O/$tag"; then
        if [ -s "$f" ] && grep -q -e '<d ' -e '<s ' "$f" && ! grep -Eq '<(d|s) [^>]* e="[0-9]' "$f"; then
            ok "O/$tag: rows present, none carries e="
        else
            no "O/$tag: no rows to check, or a row carries e= outside --for"
        fi
    fi
done

echo "(H) hop slots go to top rows with a proven callee edge"
hopcheck(){
    python3 - "$TMP/rows.py" "$@" <<'PY'
import sys
exec( open( sys.argv[ 1 ] ).read() )
path, label, mode, name = sys.argv[ 2: 6 ]
doc = load( path )
if not ctx_ok( doc ):
    print( "  FAIL  %s: NOROOT" % label ); sys.exit( 1 )
hs = hrows( doc )
names = [ h.get( "n" ) for h in hs ]
if mode == "nohop":
    good = name not in names; why = "no <h n=%s> (every callee edge name-only)" % name
elif mode == "hop":
    good = name in names; why = "<h n=%s> kept (a proven callee edge)" % name
elif mode == "order":
    # a <d> row prints Owner.name / Owner::name (QUALNAME-1); an <h> hop row keeps the BARE name: join on (bare name, p, l)
    bare = lambda n: ( n or "" ).replace( "::", "." ).split( "." )[ -1 ]
    rank = { ( bare( a.get( "n" ) ), a.get( "p" ), a.get( "l" ) ): int( a[ "r" ] ) for _, a in drows( doc ) if a.get( "r", "" ).isdigit() }
    rs = [ rank.get( ( bare( h.get( "n" ) ), h.get( "p" ), h.get( "l" ) ) ) for h in hs ]
    good = bool( rs ) and None not in rs and rs == sorted( rs ); why = "<h> rows in r= order %s" % rs
else:
    print( "  FAIL  %s: unknown mode" % label ); sys.exit( 1 )
print( "  %s  %s: %s" % ( "PASS" if good else "FAIL", label, why ) )
sys.exit( 0 if good else 1 )
PY
    [ $? -eq 0 ] || { fail=1; return 1; }
}
# CAPABILITY (checklist 17): the "only name-only edges" premise needs the receiver-evidence hedge — a binary that marks a
# call bound by name alone via="name". Detected here, on this fixture: Downloader.pull's `source.fetch_entry( url )` is
# such a call. A binary without the hedge cannot tell that edge from a proven one, so the two nohop arms SKIP BY NAME;
# every other arm (the near misses, rank order) runs either way.
FEB="$TMP/py.callers.fetch_entry.xml"; run py "$FEB" --callers=fetch_entry
FEB_ON=0
if ran_ok "$FEB" "H premise"; then
    if ! grep -q '<callers ' "$FEB" || ! grep -q 'n="Downloader.pull"' "$FEB"; then
        no "H premise: --callers=fetch_entry did not answer with the pull row (cannot decide the hedge capability)"
    elif grep -Eq '<s [^>]*n="Downloader.pull"[^>]*via="name"|<s [^>]*via="name"[^>]*n="Downloader.pull"' "$FEB"; then
        FEB_ON=1
    fi
fi
nohop_or_skip(){
    if [ "$FEB_ON" = 1 ]; then hopcheck "$@"; else printf '  SKIP  %s: expects FE-B (this binary marks no name-only row via="name")\n' "$2"; fi
}
if ran_ok "$TE" "H/TS"; then
    nohop_or_skip "$TE" "H/TS getter with a name-only edge" nohop contextHost
    hopcheck "$TE" "H/TS near miss" hop createContext
    hopcheck "$TE" "H/TS order" order -
fi
PH="$( ask py fetch 'How does the lookup cache fetch or evict an entry?' )"
if ran_ok "$PH" "H/PY"; then
    nohop_or_skip "$PH" "H/PY untyped-parameter caller" nohop pull
    hopcheck "$PH" "H/PY near miss" hop fetch_entry
    hopcheck "$PH" "H/PY order" order -
fi
CH="$( ask c collect 'How does the sampler collect probe readings?' )"
if ran_ok "$CH" "H/C"; then
    hopcheck "$CH" "H/C near miss" hop Sampler_collectAll
fi

echo "(R) code above docs: the SHOWN set reordered, never shrunk"
# rset ANSWER — the shown <d> rows as sorted "n|p|l" lines (the SET), and a line "DOCS k" with the doc-row count
# rcheck LABEL ON OFF [premise_doc_row] — ON (the rule) and OFF (RIPWIRE_NO_DOCS_AFTER_CODE=1, plain score order) show the
#   same row SET and the same doc rows; in ON every code row precedes every doc row; the r= values are the same multiset;
#   ON carries docs_after_code=N exactly when it moved N doc rows above which OFF had a code row below; the reading rides.
rcheck(){
    python3 - "$TMP/rows.py" "$@" <<'PY'
import re, sys
exec( open( sys.argv[ 1 ] ).read() )
label, on, off = sys.argv[ 2: 5 ]
need = sys.argv[ 5 ] if len( sys.argv ) > 5 else None
don, doff = load( on ), load( off )
if not ctx_ok( don ) or not ctx_ok( doff ):
    print( "  FAIL  %s: NOROOT" % label ); sys.exit( 1 )
ron = [ a for _, a in drows( don ) ]
roff = [ a for _, a in drows( doff ) ]
key = lambda a: ( a.get( "n" ), a.get( "p" ), a.get( "l" ) )
bad = []
if sorted( map( key, ron ) ) != sorted( map( key, roff ) ):
    lost = sorted( set( map( key, roff ) ) - set( map( key, ron ) ) )
    bad.append( "the shown set changed (rows only in plain score order: %s)" % lost[ :4 ] )
if sorted( a.get( "r" ) for a in ron ) != sorted( a.get( "r" ) for a in roff ):
    bad.append( "the r= values are not the same multiset" )
kinds = [ is_doc_row( a ) for a in ron ]
if True in kinds and False in kinds and kinds.index( True ) < len( kinds ) - 1 - kinds[ ::-1 ].index( False ):
    bad.append( "a doc row precedes a code row in the reordered answer" )
rs = [ int( a[ "r" ] ) for a in ron if a.get( "r", "" ).isdigit() ]
if rs != sorted( rs ):
    bad.append( "rows are not in r= order" )
koff = [ is_doc_row( a ) for a in roff ]
lastCode = max( ( i for i, d in enumerate( koff ) if not d ), default=-1 )
moved = sum( 1 for i, d in enumerate( koff ) if d and i < lastCode )
sig = re.search( r"<sigs[^>]*>", strip_comments( don ) )
attr = re.search( r' docs_after_code="([0-9]+)"', sig.group( 0 ) ) if sig else None
if moved and ( not attr or int( attr.group( 1 ) ) != moved ):
    bad.append( "docs_after_code= is %s, expected %d" % ( attr.group( 1 ) if attr else "absent", moved ) )
if not moved and attr:
    bad.append( "docs_after_code= present though nothing moved" )
if moved and "docs_after_code=N:" not in don:
    bad.append( "the answer carries docs_after_code= without its reading" )
if need and not [ a for a in ron if a.get( "n" ) == need and is_doc_row( a ) ]:
    bad.append( "premise: the doc row %r is not shown" % need )
if bad:
    for b in bad: print( "  FAIL  %s: %s" % ( label, b ) )
    sys.exit( 1 )
print( "  PASS  %s: same %d rows (%d docs), code first, docs_after_code=%s" % ( label, len( ron ), kinds.count( True ), attr.group( 1 ) if attr else "-" ) )
PY
    [ $? -eq 0 ] || { fail=1; return 1; }
}
# offr ROOT TAG QUESTION [ARGS…] — the same question in plain score order (the A/B handle)
offr(){ local r="$1" t="$2" q="$3"; shift 3; local f="$TMP/$r.$t.off.xml"; ( cd "$CORPUS/$r" && RIPWIRE_NO_DOCS_AFTER_CODE=1 "$BIN" . --no-cache "--for=$q" "$@" >"$f" 2>"$f.err" ); printf '%s' "$?" >"$f.rc"; printf '%s' "$f"; }
onr(){ local r="$1" t="$2" q="$3"; shift 3; local f="$TMP/$r.$t.on.xml"; run "$r" "$f" "--for=$q" "$@"; printf '%s' "$f"; }
Q1='How is a per-request context created?'
Q2='How is a per-request context created and dropped after the response?'   # only the docs lifecycle section names "dropped after the response"
for spec in "r1|$Q1|" "r2|$Q2|"; do
    tag="${spec%%|*}"; rest="${spec#*|}"; q="${rest%%|*}"; extra="${rest#*|}"
    if [ -n "$extra" ]; then ON="$( onr ts "$tag" "$q" "$extra" )"; OFF="$( offr ts "$tag" "$q" "$extra" )"; else ON="$( onr ts "$tag" "$q" )"; OFF="$( offr ts "$tag" "$q" )"; fi
    if ran_ok "$ON" "R/$tag" && ran_ok "$OFF" "R/$tag (plain order)"; then
        case "$tag" in
            r2) rcheck "R/$tag only a docs row names the topic: it stays" "$ON" "$OFF" "Context lifecycle" ;;
            *)  rcheck "R/$tag${extra:+ ($extra)}" "$ON" "$OFF" ;;
        esac
    fi
done
# (T) a tight explicit ceiling: neither the reorder nor its uncharged note (B1 of the review of 9d0ad7aa)
echo "(T) a tight explicit ceiling carries no reorder and no note; the near misses still reorder"
cat >"$TMP/tight.py" <<'PY'
import json, re, sys
exec( open( sys.argv[ 1 ] ).read() )
# tight.py ROWS.PY LABEL MODE ON OFF [BUDGET]  — MODE: tight | reorders
label, mode, on, off = sys.argv[ 2: 6 ]
budget = int( sys.argv[ 6 ] ) if len( sys.argv ) > 6 and sys.argv[ 6 ].isdigit() else 0
def body( path ):
    t = load( path )
    if path.endswith( ".mcp.json" ):
        ls = [ l for l in t.splitlines() if l.strip() ]
        t = json.loads( ls[ -1 ] )[ "result" ][ "content" ][ 0 ][ "text" ]
    return t
A, B = body( on ), body( off )
isjson = A.lstrip().startswith( "{" )
if isjson:
    try:
        nrows = len( json.loads( A ).get( "sigs", [] ) ) if B.lstrip().startswith( "{" ) else 0
    except ValueError:
        nrows = 0
else:
    nrows = len( drows( A ) ) if ctx_ok( A ) and ctx_ok( B ) else 0
if nrows == 0:
    print( "  FAIL  %s: no shown rows (premise)" % label ); sys.exit( 1 )
bad = []
moved = re.search( r'docs_after_code="[0-9]+"|"docs_after_code":[0-9]+', A ) is not None
note = "docs_after_code=N:" in A
if mode == "tight":
    if open( on, "rb" ).read() != open( off, "rb" ).read():
        bad.append( "differs from the NO_DOCS_AFTER_CODE=1 twin (the pre-reorder answer)" )
    if moved or note:
        bad.append( "carries docs_after_code= or its reading" )
    # forbudget-soft (rule 4): an explicit --token-budget (a REF is passed) is a SOFT target over the <sigs> rows (T = N x kMinBytesPerToken x
    # kBudgetHeadroom bytes), so est_tokens may exceed N and nothing is labelled over_ceiling. The old "est_tokens <= N, no
    # over_ceiling the twin lacks" half is replaced by NOLBL (no over_ceiling= on either answer) + ST (the rows fit T, or are
    # the rank 1..4 floor; a cut is maximal against the uncut plain-order REF and carries next=). RED on base (d4325a8c): the
    # hard ceiling cut the XML rows at 10 of 16 / the JSON rows at 13 with room left under T.
    m = re.search( r'<ctx [^>]*\best_tokens="([0-9]+)"', A ) or re.search( r'"est_tokens":([0-9]+)', A )
    if budget and not on.endswith( ".mcp.json" ) and len( sys.argv ) <= 7:
        # a HARD body ceiling (--max-tokens; no REF passed): est_tokens stays <= N, no over_ceiling the twin lacks — unchanged
        if not m: bad.append( "no est_tokens to compare with the budget (premise)" )
        elif int( m.group( 1 ) ) > budget: bad.append( "est_tokens %s > budget %d" % ( m.group( 1 ), budget ) )
        if "over_ceiling" in A and "over_ceiling" not in B: bad.append( "over_ceiling the twin lacks" )
    elif budget and not on.endswith( ".mcp.json" ):
        tb = float( sys.argv[ 8 ] ) if len( sys.argv ) > 8 and re.fullmatch( r"[0-9.]+", sys.argv[ 8 ] ) else 0.0
        if tb <= 0: bad.append( "no target bytes-per-token constant (premise: src/serialize.h kMinBytesPerToken x kBudgetHeadroom)" )
        if re.search( r'over_ceiling', A ) or re.search( r'over_ceiling', B ):
            bad.append( "NOLBL: over_ceiling on a soft --token-budget answer" )
        def charged( doc ):
            """(row charges in rank order, total charged bytes, cut?, next?) — XML: the bytes inside <sigs> plus the zero
            cx=/ccx=/in= the lean spelling elides (the ladder's entryCost); JSON: the compact bytes of each "sigs" entry."""
            if doc.lstrip().startswith( "{" ):
                try: j = json.loads( doc )
                except ValueError: return None
                rows = [ ( int( e.get( "r", 10**9 ) ), len( json.dumps( e, separators=( ",", ":" ), ensure_ascii=False ).encode() ) + 1 )
                         for e in j.get( "sigs", [] ) ]
                rows.sort()
                cut = bool( j.get( "capped" ) ) or j.get( "sigs_shown", len( rows ) ) != j.get( "sigs_total", len( rows ) )
                return [ c for _, c in rows ], sum( c for _, c in rows ), cut, bool( j.get( "sigs_next" ) )
            m2 = re.search( r'<sigs\b([^>]*)>(.*?)</sigs>', doc, re.S )
            if not m2: return None
            rows = []; elided = 0
            for d in re.finditer( r'<d ([^>]*)>.*?</d>|<d ([^>]*)/>', m2.group( 2 ), re.S ):
                a = d.group( 1 ) or d.group( 2 ); r = re.search( r'\br="(\d+)"', a ); pr = len( d.group( 0 ).encode() )
                c = pr + sum( n for k, n in ( ( "cx", 7 ), ( "ccx", 8 ), ( "in", 7 ) ) if not re.search( r'\b' + k + r'="', a ) )
                elided += c - pr; rows.append( ( int( r.group( 1 ) ) if r else 10**9, c ) )
            rows.sort()
            return [ c for _, c in rows ], len( m2.group( 2 ).encode() ) + elided, 'capped="1"' in m2.group( 1 ), " next=" in m2.group( 1 )
        a, ref = charged( A ), charged( body( sys.argv[ 7 ] ) ) if len( sys.argv ) > 7 else None
        T = int( budget * tb )
        # forbudget-soft round C (owner decision 2026-10-14: RESERVE SECTIONS FIRST; rule 4): the trailing sections are served
        # first and the rows past the target cut fill what they leave of T — maximality is judged against T less their bytes
        # (U: XML, everything after </sigs> but </ctx>, plus the <hdr> rows; JSON, the "tail" object)
        if A.lstrip().startswith( "{" ):
            try: U = len( json.dumps( json.loads( A ).get( "tail", {} ), separators=( ",", ":" ), ensure_ascii=False ).encode() )
            except ValueError: U = 0
        else:
            U = ( len( A.split( "</sigs>", 1 )[ 1 ].encode() ) - len( "</ctx>" ) if "</sigs>" in A else 0 )
            U += sum( len( h.encode() ) for h in re.findall( r'<hdr [^>]*/>', A.split( "<sigs", 1 )[ 0 ] ) )
            # the tail size: test/lib/softbudget.py, shared by the five soft-target readers (the FIX1 R1 tail floor)
            import os as _os, sys as _sys; _sys.path.insert( 0, _os.environ[ "RIPWIRE_TESTLIB" ] ); from softbudget import tail_size
            if len( sys.argv ) > 7: U += max( 0, tail_size( body( sys.argv[ 7 ] ) ) - tail_size( A ) )
        if a is None or ref is None or not ref[ 0 ]: bad.append( "ST: no rows to charge (premise: answer and uncut reference)" )
        elif tb > 0:
            k = len( a[ 0 ] ); fits = a[ 1 ] <= T or k <= 4
            if not fits: bad.append( "ST: rows charged %d B > target %d B with %d rows (floor 4)" % ( a[ 1 ], T, k ) )
            if k < len( ref[ 0 ] ):
                if a[ 1 ] + ref[ 0 ][ k ] <= T - U - 160: bad.append( "ST: cut at %d of %d rows with %d B charged, the next row (%d B) fits T=%d less the sections U=%d" % ( k, len( ref[ 0 ] ), a[ 1 ], ref[ 0 ][ k ], T, U ) )
                if not ( a[ 2 ] and a[ 3 ] ): bad.append( "NX: rows cut (%d of %d) without capped + next=" % ( k, len( ref[ 0 ] ) ) )
                # FIX2 C1 (rule 4): the upper-bound twin of maximality (test/lib/softbudget.py upper_bound): rows past the floor
                # stop where T less the other sections and the tail reserve runs out; RED on a binary that ignores the tail reserve
                import os as _os, sys as _sys; _sys.path.insert( 0, _os.environ[ "RIPWIRE_TESTLIB" ] ); from softbudget import upper_bound
                up, udet = upper_bound( A, body( sys.argv[ 7 ] ), T, k, len( ref[ 0 ] ), U )
                if not up: bad.append( "UP: " + udet )
            print( "  ....  %s: ST rows=%d/%d charged=%d T=%d" % ( label, k, len( ref[ 0 ] ), a[ 1 ], T ) )
else:
    if not moved: bad.append( "no docs_after_code= (the reorder did not apply)" )
    if not note and not isjson: bad.append( "no reading for docs_after_code=" )   # the JSON twin carries the count only
    if open( on, "rb" ).read() == open( off, "rb" ).read(): bad.append( "equals the plain score-order twin (nothing moved)" )
if bad:
    for b in bad: print( "  FAIL  %s: %s" % ( label, b ) )
    sys.exit( 1 )
print( "  PASS  %s" % label )
PY
tcheck(){ python3 "$TMP/tight.py" "$TMP/rows.py" "$@"; [ $? -eq 0 ] || { fail=1; return 1; }; }
# mcpfor OUT TWIN(0|1) TASK [EXTRA_ARGS_JSON] — the MCP `for` answer; TWIN=1 sets RIPWIRE_NO_DOCS_AFTER_CODE=1
mcpfor(){ local out="$1" twin="$2" task="$3" extra="${4:-}"; mkdir -p "$TMP/mcphome"
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
                   '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$CORPUS/ts"'","task":"'"$task"'"'"$extra"'}}}' \
      | ( cd "$CORPUS/ts" && if [ "$twin" = 1 ]; then TMPDIR="$TMP/mcphome" RIPWIRE_NO_DOCS_AFTER_CODE=1 "$BIN" --mcp; else TMPDIR="$TMP/mcphome" env -u RIPWIRE_NO_DOCS_AFTER_CODE "$BIN" --mcp; fi >"$out" 2>/dev/null ); printf '%s' "$?" >"$out.rc"; }
# forbudget-soft (rule 4): the soft target's bytes per token, read from source (a missing constant FAILS the ST half, never skips)
TBPT="$( python3 -c "import re,sys; s=open(sys.argv[1]).read(); g=lambda k:float(re.search(r'inline constexpr double '+k+r' *= *([0-9.]+);',s).group(1)); print(g('kMinBytesPerToken')*g('kBudgetHeadroom'))" "$ROOT/src/serialize.h" 2>/dev/null )"
for b in 700 1200; do
    for spec in "xml|" "json|--json"; do
        tag="${spec%%|*}"; extra="${spec#*|}"
        if [ -n "$extra" ]; then ON="$( onr ts "t$b$tag" "$Q1" "--token-budget=$b" "$extra" )"; OFF="$( offr ts "t$b$tag" "$Q1" "--token-budget=$b" "$extra" )"
        else ON="$( onr ts "t$b$tag" "$Q1" "--token-budget=$b" )"; OFF="$( offr ts "t$b$tag" "$Q1" "--token-budget=$b" )"; fi
        if ran_ok "$ON" "T/$b/$tag" && ran_ok "$OFF" "T/$b/$tag (twin)"; then
            REF="$( offr ts "r$tag" "$Q1" $extra )"   # the uncut plain-order answer (no budget): the rank order a soft cut is a prefix of
            ran_ok "$REF" "T/$b/$tag (uncut reference)" || continue
            tcheck "T/$tag --token-budget=$b: byte-equal to the plain-order twin, no docs_after_code=$([ "$b" = 1200 ] && echo ", NOLBL + ST (soft target)")" tight "$ON" "$OFF" "$([ "$b" = 1200 ] && echo 1200 || echo 0)" "$REF" "$TBPT"
        fi
    done
    mcpfor "$TMP/t$b.on.mcp.json" 0 "$Q1" ",\"budget_tokens\":$b"; mcpfor "$TMP/t$b.off.mcp.json" 1 "$Q1" ",\"budget_tokens\":$b"
    if ran_ok "$TMP/t$b.on.mcp.json" "T/$b/mcp" && ran_ok "$TMP/t$b.off.mcp.json" "T/$b/mcp (twin)"; then
        tcheck "T/mcp budget_tokens=$b: byte-equal to the plain-order twin, no docs_after_code= (est_tokens not gated: base MCP is already over)" tight "$TMP/t$b.on.mcp.json" "$TMP/t$b.off.mcp.json"
    fi
done
# (T) body ceiling (--max-tokens=N --detail=K): the third tight explicit ceiling (B1' of the delta review of f4253d45).
# est_tokens must stay <= N exactly as it did before the reorder: the answer is byte-equal to the plain-order twin. Both fixtures
# sit in the window where the uncharged note alone pushed a within-ceiling answer over (RED at f4253d45: ts 1534 -> 1634 with
# over_ceiling="1" at 1600; pydocs 1626 -> 1725 at 1660). JSON refuses the pair and MCP `for` has no body-ceiling input.
QP='How is a message delivered to its handler?'
# forbudget-soft round C (FOLD C; rule 4): the default answer's <tail> now carries page 0 of the file page (+94 / +87 tokens on
# these two answers), so the windows move with it: 1600 -> 1700, 1660 -> 1760 (est 1628 / 1713 on the round C binary).
for spec in "ts|$Q1|1700" "pydocs|$QP|1760"; do
    r="${spec%%|*}"; rest="${spec#*|}"; q="${rest%|*}"; mt="${rest##*|}"
    ON="$( onr "$r" "bc$mt" "$q" "--max-tokens=$mt" --detail=1 )"; OFF="$( offr "$r" "bc$mt" "$q" "--max-tokens=$mt" --detail=1 )"
    if ran_ok "$ON" "T/body/$r" && ran_ok "$OFF" "T/body/$r (twin)"; then
        tcheck "T/body $r --max-tokens=$mt --detail=1: byte-equal to the plain-order twin, no docs_after_code=, est_tokens <= $mt" tight "$ON" "$OFF" "$mt"
    fi
    # near miss: --detail alone is not a ceiling (no --max-tokens), so the reorder and its note still apply
    ON="$( onr "$r" "bd" "$q" --detail=1 )"; OFF="$( offr "$r" "bd" "$q" --detail=1 )"
    if ran_ok "$ON" "T/body/near/$r" && ran_ok "$OFF" "T/body/near/$r (twin)"; then
        tcheck "T/body/near $r --detail=1 without --max-tokens: the reorder and its note still apply" reorders "$ON" "$OFF"
    fi
done
# --json refuses the pair (the arm above is XML-only), and MCP `for` takes no max_tokens: if either ever accepts it, this arm must be
# replaced by a byte-equal one.
( cd "$CORPUS/ts" && "$BIN" . --no-cache "--for=$Q1" --max-tokens=1600 --detail=1 --json >"$TMP/bcj.out" 2>"$TMP/bcj.err" ); jrc=$?
if [ "$jrc" -ne 0 ] && grep -q 'two output SHAPES' "$TMP/bcj.err"; then ok "T/body --json: refuses --max-tokens with --detail (no JSON body-ceiling answer to gate)"; else no "T/body --json: expected the two-shapes refusal, rc=$jrc"; fi
mcpfor "$TMP/bcm.mcp.json" 0 "$Q1" ',"max_tokens":1600,"detail":1'
if grep -q "unknown field: 'max_tokens'" "$TMP/bcm.mcp.json"; then ok "T/body mcp: for refuses max_tokens (no MCP body-ceiling input to gate)"; else no "T/body mcp: for no longer refuses max_tokens — add a byte-equal arm"; fi
# near misses: the SAME question with no explicit ceiling, and a ceiling at/above the default share, still reorder
for b in 0 8000; do
    for spec in "xml|" "json|--json"; do
        tag="${spec%%|*}"; extra="${spec#*|}"; set -- "$Q1"; [ "$b" != 0 ] && set -- "$@" "--token-budget=$b"; [ -n "$extra" ] && set -- "$@" "$extra"
        ON="$( onr ts "n$b$tag" "$@" )"; OFF="$( offr ts "n$b$tag" "$@" )"
        if ran_ok "$ON" "T/near/$b/$tag" && ran_ok "$OFF" "T/near/$b/$tag (twin)"; then
            tcheck "T/near $tag $([ "$b" = 0 ] && echo "no ceiling" || echo "--token-budget=$b"): the reorder and its note still apply" reorders "$ON" "$OFF"
        fi
    done
    if [ "$b" = 0 ]; then ex=""; else ex=",\"budget_tokens\":$b"; fi
    mcpfor "$TMP/n$b.on.mcp.json" 0 "$Q1" "$ex"; mcpfor "$TMP/n$b.off.mcp.json" 1 "$Q1" "$ex"
    if ran_ok "$TMP/n$b.on.mcp.json" "T/near/$b/mcp" && ran_ok "$TMP/n$b.off.mcp.json" "T/near/$b/mcp (twin)"; then
        tcheck "T/near mcp $([ "$b" = 0 ] && echo "no ceiling" || echo "budget_tokens=$b"): the reorder and its note still apply" reorders "$TMP/n$b.on.mcp.json" "$TMP/n$b.off.mcp.json"
    fi
done
# a question naming docs keeps score order at 1200 as well (the existing rule is untouched by the tight-ceiling one)
ON="$( onr ts d1200 "Where do the docs describe the context lifecycle?" --token-budget=1200 )"; OFF="$( offr ts d1200 "Where do the docs describe the context lifecycle?" --token-budget=1200 )"
if ran_ok "$ON" "T/docsq" && ran_ok "$OFF" "T/docsq (twin)"; then
    if cmp -s "$ON" "$OFF"; then ok "T/docsq: a question naming docs is byte-equal to the plain-order twin at 1200"; else no "T/docsq: a docs question differs from the plain-order twin"; fi
fi
TD="$( ask ts docs 'Where do the docs describe the context lifecycle?' )"
if ran_ok "$TD" "R twin"; then
    python3 - "$TMP/rows.py" "$TD" <<'PY'
import sys
exec( open( sys.argv[ 1 ] ).read() )
rows = [ a for _, a in drows( load( sys.argv[ 2 ] ) ) if a.get( "r", "" ).isdigit() ]
top = [ a for a in rows if int( a[ "r" ] ) <= 5 and is_doc_row( a ) ]
if not rows or not top:
    print( "  FAIL  R twin: a question that names docs has no docs row in its top five" ); sys.exit( 1 )
print( "  PASS  R twin: docs row %s in the top five" % top[ 0 ].get( "n" ) )
PY
    [ $? -eq 0 ] || fail=1
fi

echo "(J) --for --json carries the same e= values"
TJ="$TMP/ts.ctx.json"; run ts "$TJ" "--for=How is a per-request context created?" --json
if ran_ok "$TJ" "J"; then
    python3 - "$TMP/rows.py" "$TE" "$TJ" <<'PY'
import json, sys
exec( open( sys.argv[ 1 ] ).read() )
x = { ( a.get( "n" ), a.get( "p" ), a.get( "l" ) ): a.get( "e" ) for _, a in drows( load( sys.argv[ 2 ] ) ) }
try:
    j = json.loads( load( sys.argv[ 3 ] ) )
except ValueError as err:
    print( "  FAIL  J: not JSON (%s)" % err ); sys.exit( 1 )
js = { ( r.get( "n" ), r.get( "p" ), str( r.get( "l" ) ) ): ( None if r.get( "e" ) is None else str( r.get( "e" ) ) ) for r in j.get( "sigs", [] ) }
common = set( x ) & set( js )
if not common or not any( x[ k ] for k in common ):
    print( "  FAIL  J: no shared row carries e= (premise)" ); sys.exit( 1 )
diff = sorted( k for k in common if x[ k ] != js[ k ] )
if diff:
    print( "  FAIL  J: XML/JSON e= differ on %s" % diff[ :4 ] ); sys.exit( 1 )
print( "  PASS  J: %d shared rows agree on e=" % len( common ) )
PY
    [ $? -eq 0 ] || fail=1
fi

echo "(M) the MCP for twin carries the same e= values, with the same exclusions"
MC="$TMP/mcp.c.json"; mkdir -p "$TMP/mcphome"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
               '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$CORPUS/c"'","task":"How does the sampler compute the average reading window?"}}}' \
  | ( cd "$CORPUS/c" && TMPDIR="$TMP/mcphome" "$BIN" --mcp >"$MC" 2>/dev/null ); printf '%s' "$?" >"$MC.rc"
if ran_ok "$MC" "M"; then
    python3 - "$TMP/rows.py" "$MC" "$CORPUS/c" <<'PY'
import json, os, sys
exec( open( sys.argv[ 1 ] ).read() )
lines = [ l for l in open( sys.argv[ 2 ], encoding="utf-8", errors="replace" ) if l.strip() ]
try:
    text = json.loads( lines[ -1 ] )[ "result" ][ "content" ][ 0 ][ "text" ]
except Exception as err:
    print( "  FAIL  M: no readable MCP for answer (%s)" % err ); sys.exit( 1 )
rows = { a.get( "n" ) + "@" + a.get( "p", "" ) + ":" + a.get( "l", "" ): a for _, a in drows( text ) }
want = { "Sampler_average@src/window.c:6": "14", "Sampler_scale@src/window.c:3": "3" }
bad = [ "%s e=%r, expected %s" % ( k, rows[ k ].get( "e" ) if k in rows else "(row absent)", v ) for k, v in want.items() if k not in rows or rows[ k ].get( "e" ) != v ]
bad += [ "%s is extent_suspect and carries e=" % k for k, a in rows.items() if "extent_suspect" in a and "e" in a ]
if "e=" not in " ".join( __import__( "re" ).findall( r"<!--(.*?)-->", text, __import__( "re" ).S ) ):
    bad.append( "the MCP answer defines no e= in its legend" )
if bad:
    for b in bad: print( "  FAIL  M: %s" % b )
    sys.exit( 1 )
print( "  PASS  M: MCP for rows carry the CLI's e= values; suspect rows none; legend defines e=" )
PY
    [ $? -eq 0 ] || fail=1
fi

echo "(L) legend defines e= and what it does not mean"
LG="$TMP/ts.legend.xml"; run ts "$LG" "--for=How is a per-request context created?" --legend=full
if ran_ok "$LG" "L"; then
    python3 - "$LG" <<'PY'
import re, sys
legend = " ".join( re.findall( r"<!--(.*?)-->", open( sys.argv[ 1 ], encoding="utf-8", errors="replace" ).read(), re.S ) )
need = [ ( r"\be=", "defines e=" ), ( r"(?i)absent[^.;]*(unknown|not known)", "says absent = unknown" ),
         ( r"(?i)(never 0|not 0|never zero)", "says e= is never 0" ), ( r"(?i)l=[^.;]{0,60}(name's line|line of (the|its) (definition's )?name)", "says l= is the name's line" ) ]
bad = [ w for rx, w in need if not re.search( rx, legend ) ]
if bad:
    print( "  FAIL  L: the legend does not %s" % "; ".join( bad ) ); sys.exit( 1 )
print( "  PASS  L: e= defined with its NOT-meaning" )
PY
    [ $? -eq 0 ] || fail=1
fi

echo "(N) RIPWIRE_FOR_ENDLINES=always|auto|never (experimental; unset = auto)"
NQ="--for=How is a per-request context created?"
# runenv VALUE OUT ARGS… — VALUE "-" leaves the switch unset
runenv(){ local v="$1" f="$2"; shift 2
    if [ "$v" = "-" ]; then ( cd "$CORPUS/ts" && env -u RIPWIRE_FOR_ENDLINES "$BIN" . --no-cache "$@" >"$f" 2>"$f.err" )
    else ( cd "$CORPUS/ts" && RIPWIRE_FOR_ENDLINES="$v" "$BIN" . --no-cache "$@" >"$f" 2>"$f.err" ); fi
    printf '%s' "$?" >"$f.rc"; }
# rowset FILE — the <d> rows (XML) or "sigs" entries (JSON) as "n p l r" lines, e= ignored; "NOROWS" when none
cat >"$TMP/rowset.py" <<'PY'
import json, re, sys
exec( open( sys.argv[ 1 ] ).read() )
text = load( sys.argv[ 2 ] )
if text.lstrip().startswith( "{" ):
    rows = [ ( r.get( "n" ), r.get( "p" ), str( r.get( "l" ) ), str( r.get( "r" ) ) ) for r in json.loads( text ).get( "sigs", [] ) ]
    est = json.loads( text ).get( "est_tokens" )
else:
    rows = [ ( a.get( "n" ), a.get( "p" ), a.get( "l" ), a.get( "r" ) ) for _, a in drows( text ) ]
    m = re.search( r'<ctx [^>]*\best_tokens="([0-9]+)"', text ); est = m.group( 1 ) if m else None
print( "EST %s" % est )
print( "\n".join( " ".join( map( str, r ) ) for r in rows ) if rows else "NOROWS" )
PY
rowset(){ python3 "$TMP/rowset.py" "$TMP/rows.py" "$1" | sed 1d; }
estof(){ python3 "$TMP/rowset.py" "$TMP/rows.py" "$1" | sed -n '1s/^EST //p'; }
has_e(){ grep -Eq ' e="[0-9]+"|"e":[0-9]+' "$1"; }
has_e_clause(){ grep -Eq 'e= on a d row|d e= its last line' "$1"; }
for spec in "xml|" "json|--json"; do
    tag="${spec%%|*}"; extra="${spec#*|}"
    set -- "$NQ" --token-budget=1200; [ -n "$extra" ] && set -- "$@" "$extra"
    NA="$TMP/n.always.$tag"; NU="$TMP/n.unset1200.$tag"; NX="$TMP/n.auto1200.$tag"
    runenv always "$NA" "$@"; runenv - "$NU" "$@"; runenv auto "$NX" "$@"
    if ran_ok "$NA" "N/always/$tag" && ran_ok "$NU" "N/unset1200/$tag" && ran_ok "$NX" "N/auto1200/$tag"; then
        if [ "$( rowset "$NU" )" = NOROWS ]; then no "N/always/$tag: the 1200-token answer has no rows (premise)"
        elif ! has_e "$NA"; then no "N/always/$tag: RIPWIRE_FOR_ENDLINES=always carries no e= under --token-budget=1200"
        elif has_e "$NU"; then no "N/always/$tag: premise — the unset 1200-token answer already carries e= (arm B's rule moved)"
        elif [ "$( rowset "$NA" )" != "$( rowset "$NU" )" ]; then no "N/always/$tag: forcing e= changed the shown row set (e= cost or moved a row)"
        else ok "N/always/$tag: e= present under --token-budget=1200, same $( rowset "$NU" | wc -l | tr -d ' ' ) rows as auto (est_tokens $( estof "$NU" ) -> $( estof "$NA" ) vs budget 1200, reported not gated)"; fi
        if cmp -s "$NX" "$NU"; then ok "N/auto/$tag: RIPWIRE_FOR_ENDLINES=auto is byte-identical to unset at --token-budget=1200"
        else no "N/auto/$tag: auto differs from unset at --token-budget=1200"; fi
    fi
    set -- "$NQ"; [ -n "$extra" ] && set -- "$@" "$extra"
    NN="$TMP/n.never.$tag"; ND="$TMP/n.unset.$tag"; NXD="$TMP/n.auto.$tag"
    runenv never "$NN" "$@"; runenv - "$ND" "$@"; runenv auto "$NXD" "$@"
    if ran_ok "$NN" "N/never/$tag" && ran_ok "$ND" "N/unset/$tag" && ran_ok "$NXD" "N/auto/$tag"; then
        if ! has_e "$ND"; then no "N/never/$tag: premise — the unset default answer carries no e="
        elif has_e "$NN" || has_e_clause "$NN"; then no "N/never/$tag: RIPWIRE_FOR_ENDLINES=never still carries e= or its clause at the default ceiling"
        elif [ "$( rowset "$NN" )" != "$( rowset "$ND" )" ]; then no "N/never/$tag: dropping e= changed the shown row set"
        else ok "N/never/$tag: no e= and no e= clause at the default ceiling, same rows as auto"; fi
        if cmp -s "$NXD" "$ND"; then ok "N/auto/$tag: RIPWIRE_FOR_ENDLINES=auto is byte-identical to unset at the default"
        else no "N/auto/$tag: auto differs from unset at the default"; fi
        [ -s "$ND.err" ] && no "N/unset/$tag: the unset run wrote to stderr: $( head -c 200 "$ND.err" )"
    fi
done
nu=0
for bad in sometimes Always ""; do
    NB="$TMP/n.unknown.$nu"; nu=$(( nu + 1 ))
    runenv "$bad" "$NB" "$NQ"
    if ran_ok "$NB" "N/unknown '$bad'"; then
        if ! cmp -s "$NB" "$TMP/n.unset.xml"; then no "N/unknown '$bad': stdout differs from unset (an unknown value must fall back to auto)"
        elif ! has_e "$NB"; then no "N/unknown '$bad': no e= at the default (read as never)"
        elif [ "$( grep -c 'RIPWIRE_FOR_ENDLINES' "$NB.err" )" != 1 ]; then no "N/unknown '$bad': expected exactly one stderr line naming RIPWIRE_FOR_ENDLINES, got: $( head -c 300 "$NB.err" )"
        else ok "N/unknown '$bad': falls back to auto (stdout == unset, e= kept) and says so once on stderr"; fi
    fi
done
for v in always never; do
    NM="$TMP/n.mcp.$v.json"; mkdir -p "$TMP/mcphome"
    if [ "$v" = always ]; then bargs=',"budget_tokens":1200'; else bargs=''; fi
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
                   '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$CORPUS/ts"'","task":"How is a per-request context created?"'"$bargs"'}}}' \
      | ( cd "$CORPUS/ts" && TMPDIR="$TMP/mcphome" RIPWIRE_FOR_ENDLINES="$v" "$BIN" --mcp >"$NM" 2>/dev/null ); printf '%s' "$?" >"$NM.rc"
    if ran_ok "$NM" "N/mcp/$v"; then
        python3 - "$TMP/rows.py" "$NM" "$v" <<'PY'
import json, re, sys
exec( open( sys.argv[ 1 ] ).read() )
v = sys.argv[ 3 ]
lines = [ l for l in open( sys.argv[ 2 ], encoding="utf-8", errors="replace" ) if l.strip() ]
try:
    text = json.loads( lines[ -1 ] )[ "result" ][ "content" ][ 0 ][ "text" ]
except Exception as err:
    print( "  FAIL  N/mcp/%s: no readable MCP for answer (%s)" % ( v, err ) ); sys.exit( 1 )
rows = drows( text )
withE = [ a for _, a in rows if "e" in a ]
if not rows:
    print( "  FAIL  N/mcp/%s: no <d> rows (premise)" % v ); sys.exit( 1 )
if v == "always" and not withE:
    print( "  FAIL  N/mcp/always: budget_tokens=1200 rows carry no e=" ); sys.exit( 1 )
if v == "never" and ( withE or "e= on a d row" in text or "d e= its last line" in text ):
    print( "  FAIL  N/mcp/never: e= or an e= legend clause at the default ceiling" ); sys.exit( 1 )
print( "  PASS  N/mcp/%s: MCP for %s (%d of %d rows with e=)" % ( v, "carries e= under budget_tokens=1200" if v == "always" else "carries no e= and no clause", len( withE ), len( rows ) ) )
PY
        [ $? -eq 0 ] || fail=1
    fi
done
NP="$TMP/n.packsig.xml"; ( cd "$CORPUS/c" && RIPWIRE_FOR_ENDLINES=always "$BIN" . --no-cache --pack-signatures >"$NP" 2>"$NP.err" ); printf '%s' "$?" >"$NP.rc"
if ran_ok "$NP" "N/near-miss"; then
    if ! grep -q '<d ' "$NP"; then no "N/near-miss: --pack-signatures produced no <d> rows (premise)"
    elif has_e "$NP"; then no "N/near-miss: RIPWIRE_FOR_ENDLINES=always put e= on --pack-signatures rows (the switch is --for only)"
    else ok "N/near-miss: RIPWIRE_FOR_ENDLINES=always leaves --pack-signatures rows without e="; fi
fi

echo "(K) the predicates can fail"
K="$TMP/k.xml"
printf '<ctx task="t"><sigs><d l="11" e="9" n="createContext" p="src/application.ts" r="1">x</d></sigs></ctx>' >"$K"
if ( oracle "$K" "K1 (expected FAIL)" "$CORPUS/ts" ) >/dev/null 2>&1; then no "K1: e= < l= not caught"; else ok "K1: e= < l= is caught"; fi
printf '<ctx task="t"><sigs><d l="1" e="3" n="Context" p="docs/context.md" r="1">x</d><d l="11" e="18" n="createContext" p="src/application.ts" r="2">x</d></sigs></ctx>' >"$K"
if ( oracle "$K" "K2 (expected FAIL)" "$CORPUS/ts" ) >/dev/null 2>&1; then no "K2: e= on a docs row not caught"; else ok "K2: e= on a docs row is caught"; fi
printf '<ctx task="t"><sigs><d l="11" n="createContext" p="src/application.ts" r="1">x</d></sigs></ctx>' >"$K"
if ( oracle "$K" "K3 (expected FAIL)" "$CORPUS/ts" ) >/dev/null 2>&1; then no "K3: a code row without e= not caught"; else ok "K3: a code row without e= is caught"; fi
printf '<ctx task="t"><sigs><d l="7" n="contextHost" p="src/request.ts" r="1">x</d></sigs><hops><h l="7" p="src/request.ts" n="contextHost"></h></hops></ctx>' >"$K"
if ( hopcheck "$K" "K4 (expected FAIL)" nohop contextHost ) >/dev/null 2>&1; then no "K4: a name-only hop row not caught"; else ok "K4: a name-only hop row is caught"; fi
printf '<callers of="x" found="0"/>' >"$K"
if ( oracle "$K" "K5 (expected FAIL)" "$CORPUS/ts" ) >/dev/null 2>&1; then no "K5: NOROOT passed"; else ok "K5: a document with no --for root is never a pass"; fi
K6ON="$TMP/k6on.xml"; K6OFF="$TMP/k6off.xml"
printf '<ctx task="t"><sigs><d l="11" n="createContext" p="src/application.ts" r="1">x</d></sigs></ctx>' >"$K6ON"
printf '<ctx task="t"><sigs><d l="17" n="Context lifecycle" p="docs/context.md" r="1">x</d><d l="11" n="createContext" p="src/application.ts" r="2">x</d></sigs></ctx>' >"$K6OFF"
if ( rcheck "K6 (expected FAIL)" "$K6ON" "$K6OFF" ) >/dev/null 2>&1; then no "K6: an evicted doc row not caught"; else ok "K6: a doc row the reorder evicted is caught"; fi

if [ "$fail" -ne 0 ]; then
    echo "forsigspancheck: FAIL"
    exit 1
fi
echo "forsigspancheck: PASS"
exit 0
