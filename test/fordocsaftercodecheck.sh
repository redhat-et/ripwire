#!/usr/bin/env bash
# fordocsaftercodecheck.sh — `<sigs docs_after_code="N">` states a TRUE fact about the rows the agent RECEIVED.
#
# THE CLAIM (serialize.h kForDocsAfterCodeNote): "N doc rows of the shown set moved below its code rows". The docs reorder
# (serialize.h reorderDocsAfterCode) counts the doc rows it moves when the sigs block renders. Under an explicit
# `--for --token-budget=N` the CLI answer is the UNBUDGETED answer U shed afterwards (forbudgetfit.h, TOKEN-BUDGET-MONOTONE),
# and its rows:N unit cuts the worst r= first — which, after the reorder, are the doc rows. Before lane DA1 the fitter rewrote
# shown= / docs_dropped= / past_target= / files_first= and left docs_after_code= at U's count: measured by lane FC1 on GA1 DEV
# n=89, 20 of the 20 answers carrying it at --token-budget=1600 and at 3000 showed NO doc row at all (e.g. 4 code rows,
# docs_after_code="3"), and on this fixture --token-budget=700 shows 4 code rows with docs_after_code="6". Now the fitter
# recounts it over the rows it keeps (absent at 0, its legend clause with it).
#
# ARMS (fixture test/forcompletefix/ts, the forsigspancheck (R)/(T) fixture: 9 code rows and 7 doc rows, 6 of the docs
# outranking a code row in score order):
#   (X)  EXACT, head round-robin off (RIPWIRE_NO_HEAD_RR=1, so score order is observable; SIBLING-DEMOTE and DECL-TWIN off as in
#        forsigspancheck (R), since they read the SERVED order and so point different rows in the two orders): the moved set is read off the
#        RIPWIRE_NO_DOCS_AFTER_CODE=1 twin at no budget — the doc rows printed above its last code row. Every --for answer
#        (no budget, and a sweep of --token-budget values) must carry docs_after_code= equal to how many of THOSE rows it shows
#        (absent at 0), its reading iff the attribute, and every shown doc row below every shown code row.
#   (U)  the same at the shipped default (head round-robin on): the moved set is the first N doc rows by r= of the unbudgeted
#        answer U (the reorder lists docs in score order after the code rows, so the moved ones lead them).
#   (C)  COVERAGE premise, (X) and (U) each: the sweep must hold an answer whose moved docs were ALL shed and one where only
#        SOME were — a fixture that stops producing either is a FAIL, never a quiet pass.
#   (S)  the other surfaces that print it count after their own cut (no post-render shed): MCP `for` (no budget,
#        budget_tokens 1200/1900/8000), --pack-task (no budget, 700/1900/3000) and --for --json (no budget, 1900): N <= the
#        doc rows shown, docs below code, reading iff attribute (XML).
#   (N)  NEGATIVE CONTROLS: the checker is handed three mutated answers — the all-shed answer with U's attribute put back
#        (the train-tip shape), the unbudgeted answer with its attribute removed, the partial answer with N+1 — and must
#        FAIL each. A checker that passes them is vacuous.
#   (W)  every XML answer is well formed (xmllint) and every call is deterministic (run twice, byte-identical).
#
# FLOOR, named: a "doc row" is read here by its p= extension (.md .markdown .rst .adoc .org .mdx — the Lang::Markdown rows
# of ingest_crawl.h kLangTable); the product reads the symbol's language. A renamed extension table must update both.
#
# Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/forcompletefix/ts"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/cache"; mkdir -p "$TMPDIR"   # a private warm cache (forsigspancheck: a shared one is a stderr flake)
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required (W)"; exit 2; }
echo "fordocsaftercodecheck: BIN=$BIN  CORPUS=$CORPUS"

Q='How is a per-request context created?'
BUDGETS="700 1200 1700 1800 1900 2000 3000"

# run OUT ENV... -- ARGS... : one call, twice; the second run must be byte-identical (W)
run(){
    local out="$1"; shift; local envs=(); while [ "$1" != "--" ]; do envs+=( "$1" ); shift; done; shift
    ( cd "$CORPUS" && env "${envs[@]}" "$BIN" . --no-cache "$@" >"$out" 2>"$out.err" ); printf '%s' "$?" >"$out.rc"
    ( cd "$CORPUS" && env "${envs[@]}" "$BIN" . --no-cache "$@" >"$out.again" 2>/dev/null )
}
# mcp OUT TWIN EXTRA_JSON : the MCP `for` answer's text
mcp(){
    local out="$1" extra="$2"
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
                  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$CORPUS"'","task":"'"$Q"'"'"$extra"'}}}' \
      | ( cd "$CORPUS" && "$BIN" --mcp ) >"$out.raw" 2>"$out.err"; printf '%s' "$?" >"$out.rc"
    python3 -c 'import json,sys; ls=[l for l in open(sys.argv[1]).read().splitlines() if l.strip()]; sys.stdout.write(json.loads(ls[-1])["result"]["content"][0]["text"])' \
        "$out.raw" >"$out" 2>/dev/null || printf 'mcp-parse-failed' >"$out.rc"
    cp "$out" "$out.again"   # one MCP session per call: determinism is held on the CLI calls
}
ran_ok(){ [ "$( cat "$1.rc" 2>/dev/null )" = 0 ] && return 0; no "$2: rc=$( cat "$1.rc" 2>/dev/null )"; return 1; }

cat >"$TMP/dac.py" <<'PY'
import json, re, sys
DOC_EXTS = ( ".md", ".markdown", ".rst", ".adoc", ".org", ".mdx" )
def strip_comments( doc ): return re.sub( r"<!--.*?-->", "", doc, flags=re.S )
def attrs( tag ): return dict( re.findall( r'\s([a-z_]+)="([^"]*)"', tag ) )
def key( a ): return "%s|%s" % ( a.get( "p", "" ), a.get( "n", a.get( "sym", "" ) ) )   # a demoted row is <t p= sym=>: no l=
def is_doc( a ): return a.get( "p", "" ).lower().endswith( DOC_EXTS )
def read( doc ):
    """(N or 0, has reading, [(attrs)] rows in document order) of the --for/MCP/pack answer's <sigs> block (XML or --json)."""
    if doc.lstrip().startswith( "{" ):
        j = json.loads( doc )
        n = j.get( "docs_after_code", ( j.get( "sigs_cut" ) or {} ).get( "docs_after_code", 0 ) if isinstance( j.get( "sigs_cut" ), dict ) else 0 )
        rows = [ { "p": e.get( "p", "" ), "n": e.get( "n", "" ), "l": str( e.get( "l", "" ) ), "r": str( e.get( "r", "" ) ) } for e in j.get( "sigs", [] ) ]
        return int( n or 0 ), None, rows
    bare = strip_comments( doc )
    m = re.search( r"<sigs\b([^>]*)>(.*?)</sigs>", bare, re.S )
    if not m:
        raise ValueError( "no <sigs> block" )
    n = re.search( r'\sdocs_after_code="([0-9]+)"', m.group( 1 ) )
    rows = [ attrs( " " + a ) for _, a in re.findall( r"<([dt])\s([^>]*?)/?>", m.group( 2 ) ) ]
    return int( n.group( 1 ) ) if n else 0, "[docs_after_code=N:" in doc, rows
def check( doc, moved=None, universe=None ):
    """The attribute's claim against the shown rows. moved: the row keys the reorder moved (exact arm) or None (structural)."""
    bad = []
    n, reading, rows = read( doc )
    docs = [ i for i, a in enumerate( rows ) if is_doc( a ) ]
    code = [ i for i, a in enumerate( rows ) if not is_doc( a ) ]
    if reading is not None and reading != ( n > 0 ):
        bad.append( "reading %s but docs_after_code=%s" % ( "present" if reading else "absent", n or "absent" ) )
    if n > len( docs ):
        bad.append( "docs_after_code=%d but only %d doc row(s) shown (of %d rows)" % ( n, len( docs ), len( rows ) ) )
    if n > 0 and docs and code and min( docs ) < max( code ):
        bad.append( "docs_after_code=%d but a doc row sits above a code row" % n )
    if universe is not None:
        stray = [ key( a ) for a in rows if key( a ) not in universe ]
        if stray:
            bad.append( "premise: %d shown row(s) not in the unbudgeted answer (%s)" % ( len( stray ), stray[ 0 ] ) )
    exp = None
    if moved is not None:
        exp = sum( 1 for i in docs if key( rows[ i ] ) in moved )
        if n != exp:
            bad.append( "docs_after_code=%s, but %d of the moved doc rows are shown" % ( n or "absent", exp ) )
    return bad, n, len( docs ), len( rows ), exp
def moved_from_twin( doc ):
    """the doc rows above the last code row of the plain score-order answer"""
    _, _, rows = read( doc )
    last = max( ( i for i, a in enumerate( rows ) if not is_doc( a ) ), default=-1 )
    return { key( a ) for i, a in enumerate( rows ) if is_doc( a ) and i < last }, { key( a ) for a in rows }
def moved_from_u( doc ):
    """the first N doc rows by r= of the unbudgeted answer (the reorder keeps the docs' score order below the code rows)"""
    n, _, rows = read( doc )
    docs = sorted( ( a for a in rows if is_doc( a ) ), key=lambda a: int( a.get( "r", "0" ) or 0 ) )
    return { key( a ) for a in docs[ :n ] }, { key( a ) for a in rows }, n
PY

# xarm LABEL ORACLE(twin|u) FILE... — the exact arms (X)/(U): one line per answer, then the coverage premise (C)
cat >"$TMP/arm.py" <<'PY'
import sys
exec( open( sys.argv[ 1 ] ).read() )
label, oracle, ref = sys.argv[ 2: 5 ]
answers = sys.argv[ 5: ]
txt = open( ref, encoding="utf-8", errors="replace" ).read()
if oracle == "twin":
    moved, universe = moved_from_twin( txt ); mU = len( moved )
else:
    moved, universe, mU = moved_from_u( txt )
fails = 0
if not moved:
    print( "  FAIL  %s: premise — the oracle answer moved no doc row (nothing to check)" % label ); sys.exit( 1 )
allShed = partial = 0
for path in answers:
    doc = open( path, encoding="utf-8", errors="replace" ).read()
    try:
        bad, n, ndocs, nrows, exp = check( doc, moved, universe )
    except ( ValueError, KeyError ) as e:
        print( "  FAIL  %s %s: %s" % ( label, path.rsplit( "/", 1 )[ -1 ], e ) ); fails += 1; continue
    tag = path.rsplit( "/", 1 )[ -1 ]
    allShed += 1 if exp == 0 else 0
    partial += 1 if 0 < exp < len( moved ) else 0
    if bad:
        fails += 1
        for b in bad: print( "  FAIL  %s %s: %s" % ( label, tag, b ) )
    else:
        print( "  PASS  %s %s: %d rows, %d doc rows, %d of the %d moved shown, docs_after_code=%s" % ( label, tag, nrows, ndocs, exp, len( moved ), n or "absent" ) )
if allShed == 0:
    print( "  FAIL  %s (C): no answer in the sweep shed every moved doc row (premise: the train-tip defect is not exercised)" % label ); fails += 1
else:
    print( "  PASS  %s (C): %d answer(s) shed every moved doc row" % ( label, allShed ) )
if partial == 0:
    print( "  FAIL  %s (C): no answer in the sweep kept SOME but not all moved doc rows (premise)" % label ); fails += 1
else:
    print( "  PASS  %s (C): %d answer(s) kept some of the moved doc rows" % ( label, partial ) )
sys.exit( 1 if fails else 0 )
PY

# (W) every ON answer: well formed (XML) and deterministic
wcheck(){
    local f="$1" label="$2"
    if ! cmp -s "$f" "$f.again"; then no "(W) $label: two runs differ"; fi
    case "$( head -c 1 "$f" )" in
        "{") python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null || no "(W) $label: not JSON" ;;
        *)   xmllint --noout "$f" 2>/dev/null || no "(W) $label: xmllint rejects the answer" ;;
    esac
}

echo "(X) exact, head round-robin off: the moved set from the plain score-order twin"
XENV="RIPWIRE_NO_HEAD_RR=1 RIPWIRE_NO_SIBLING_DEMOTE=1 RIPWIRE_NO_DECL_TWIN=1"
# shellcheck disable=SC2086
run "$TMP/x.twin" $XENV RIPWIRE_NO_DOCS_AFTER_CODE=1 -- "--for=$Q"
ran_ok "$TMP/x.twin" "(X) twin" || true
XS=()
run "$TMP/x.none" $XENV -- "--for=$Q"; ran_ok "$TMP/x.none" "(X) no budget" && XS+=( "$TMP/x.none" )
for b in $BUDGETS; do
    run "$TMP/x.b$b" $XENV -- "--for=$Q" "--token-budget=$b"; ran_ok "$TMP/x.b$b" "(X) --token-budget=$b" && XS+=( "$TMP/x.b$b" )
done
python3 "$TMP/arm.py" "$TMP/dac.py" "(X)" twin "$TMP/x.twin" "${XS[@]}" || fail=1
for f in "${XS[@]}"; do wcheck "$f" "(X) ${f##*/}"; done

echo "(U) exact, the shipped default (head round-robin on): the moved set from the unbudgeted answer"
US=()
run "$TMP/u.none" X=1 -- "--for=$Q"; ran_ok "$TMP/u.none" "(U) no budget" && US+=( "$TMP/u.none" )
for b in $BUDGETS; do
    run "$TMP/u.b$b" X=1 -- "--for=$Q" "--token-budget=$b"; ran_ok "$TMP/u.b$b" "(U) --token-budget=$b" && US+=( "$TMP/u.b$b" )
done
python3 "$TMP/arm.py" "$TMP/dac.py" "(U)" u "$TMP/u.none" "${US[@]}" || fail=1
for f in "${US[@]}"; do wcheck "$f" "(U) ${f##*/}"; done

echo "(S) the surfaces that count after their own cut: MCP for, --pack-task, --for --json"
cat >"$TMP/struct.py" <<'PY'
import sys
exec( open( sys.argv[ 1 ] ).read() )
label, path = sys.argv[ 2: 4 ]
doc = open( path, encoding="utf-8", errors="replace" ).read()
try:
    bad, n, ndocs, nrows, _ = check( doc )
except ( ValueError, KeyError ) as e:
    print( "  FAIL  %s: %s" % ( label, e ) ); sys.exit( 1 )
if nrows == 0:
    print( "  FAIL  %s: no sigs rows (premise)" % label ); sys.exit( 1 )
for b in bad: print( "  FAIL  %s: %s" % ( label, b ) )
if not bad: print( "  PASS  %s: %d rows, %d doc rows, docs_after_code=%s" % ( label, nrows, ndocs, n or "absent" ) )
sys.exit( 1 if bad else 0 )
PY
scheck(){ python3 "$TMP/struct.py" "$TMP/dac.py" "$2" "$1" || fail=1; }
sawMoved=0
for b in "" 1200 1900 8000; do
    f="$TMP/s.mcp${b:-none}"; mcp "$f" "${b:+,\"budget_tokens\":$b}"
    if ran_ok "$f" "(S) mcp ${b:-no budget}"; then scheck "$f" "(S) mcp for ${b:+budget_tokens=$b}"; grep -q 'docs_after_code="' "$f" && sawMoved=1; fi
done
for b in "" 700 1900 3000; do
    f="$TMP/s.pack${b:-none}"; run "$f" X=1 -- "--pack-task=$Q" ${b:+"--token-budget=$b"}
    if ran_ok "$f" "(S) pack-task ${b:-no budget}"; then scheck "$f" "(S) --pack-task ${b:+--token-budget=$b}"; wcheck "$f" "(S) pack ${b:-none}"; fi
done
for b in "" 1900; do
    f="$TMP/s.json${b:-none}"; run "$f" X=1 -- "--for=$Q" --json ${b:+"--token-budget=$b"}
    if ran_ok "$f" "(S) json ${b:-no budget}"; then scheck "$f" "(S) --for --json ${b:+--token-budget=$b}"; wcheck "$f" "(S) json ${b:-none}"; fi
done
[ "$sawMoved" = 1 ] && ok "(S) premise: an MCP answer carries docs_after_code= (the arm checks a printed count)" || no "(S) premise: no MCP answer carried docs_after_code="

echo "(N) negative controls: the checker must FAIL three mutated answers"
python3 - "$TMP/dac.py" "$TMP" <<'PY'
import re, sys, os
exec( open( sys.argv[ 1 ] ).read() )
T = sys.argv[ 2 ]
U = open( os.path.join( T, "u.none" ), encoding="utf-8" ).read()
moved, universe, mU = moved_from_u( U )
fails = 0
def expect_fail( label, doc ):
    global fails
    bad = check( doc, moved, universe )[ 0 ]
    if bad: print( "  PASS  (N) %s: caught (%s)" % ( label, bad[ 0 ] ) )
    else:   print( "  FAIL  (N) %s: the checker passed a false count (vacuous)" % label ); fails += 1
def sigs_tag( doc ): return re.search( r"<sigs\b[^>]*>", strip_comments( doc ) ).group( 0 )
picked = { "all": None, "partial": None }
for b in "700 1200 1700 1800 1900 2000 3000".split():
    p = os.path.join( T, "u.b" + b )
    if not os.path.exists( p ): continue
    d = open( p, encoding="utf-8" ).read()
    _, n, _, _, exp = check( d, moved, universe )
    if exp == 0 and picked[ "all" ] is None: picked[ "all" ] = d
    if exp and 0 < exp < len( moved ) and picked[ "partial" ] is None: picked[ "partial" ] = ( d, exp )
if picked[ "all" ] is None or picked[ "partial" ] is None:
    print( "  FAIL  (N) premise: no all-shed / partial answer to mutate" ); sys.exit( 1 )
d = picked[ "all" ]; t = sigs_tag( d )
t2 = re.sub( r'\sdocs_after_code="[0-9]+"', "", t ).replace( "<sigs", '<sigs docs_after_code="%d"' % mU, 1 )
expect_fail( "all-shed answer with U's docs_after_code=%d put back (the train-tip shape)" % mU, d.replace( t, t2, 1 ) )
t = sigs_tag( U )
expect_fail( "unbudgeted answer with docs_after_code= removed", U.replace( t, re.sub( r'\sdocs_after_code="[0-9]+"', "", t ), 1 ) )
d, exp = picked[ "partial" ]; t = sigs_tag( d )
expect_fail( "partial answer with docs_after_code=%d (one more than shown)" % ( exp + 1 ), d.replace( t, re.sub( r'docs_after_code="[0-9]+"', 'docs_after_code="%d"' % ( exp + 1 ), t ), 1 ) )
sys.exit( 1 if fails else 0 )
PY
[ $? -eq 0 ] || fail=1

if [ "$fail" -ne 0 ]; then echo "fordocsaftercodecheck: FAIL"; exit 1; fi
echo "fordocsaftercodecheck: PASS"
