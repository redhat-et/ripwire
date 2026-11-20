#!/usr/bin/env bash
# cappedbodycheck.sh — CB1 (results/CB1_CAPPEDBODY_1119/READOUT.md + PREREG_CB1_1119.md): the ONE capped-body
# block shared by --for and --pack-task. It pins the DELIVERY UNIT and its disclosure, nothing about ranking.
#
# THE RULE THIS GATE PINS, and where each half of it comes from:
#   * UNIT: a candidate's body rides WHOLE when it is at most kCappedBodyLines (120) lines; past that only its
#     HEAD rides, of kCappedBodyHeadLines lines, and the head's size is STATED in the row.
#     Why 120, and why a LINE cap rather than the byte cap that exists today:
#       - SR1 (results/SR1_SPANREADS_1119/READOUT.md lines 70-100) measured edited symbol bodies at median 23
#         lines, p90 485, max 3,955, with 77 of 389 symbols over 120 lines holding 89% of all body lines, and
#         marked the >=120 capped unit RECOMMENDED (10,056 lines, -46%, against 38,985 lines, +109%, whole).
#       - CB1 §3 re-measured the cap on the population the block actually runs on — RANKED CANDIDATES, not
#         edited symbols — and the saving is much smaller there: 4 of 57 candidate bodies over 120 lines (7.0%),
#         -21.7% of candidate body lines, 7 of 10 answers unchanged. So this cap is a BLOW-UP GUARD, not a
#         token lever, and this gate is written to pin the guard, not to claim the lever.
#       - CB1 §4 measured that the 4,000-BYTE cut that exists today is a line cap of between 73 and 150 lines
#         depending on a repo's bytes/line (2.1x spread over ten repos). A LINE cap is what removes that
#         variance, and lines are the denominator SR1's cost model is written in.
#   * HEAD-ONLY, NEVER A WINDOW. SB1 (results/SB1_SPANGATES_1119/READOUT.md §3.3-3.4) measured that one +-30
#     window anchored on the query's best-scoring term holds the edit in only 20 of 63 large bodies (31.7%),
#     falling to 19.0% as the term rule tightens, and that the union of all hits reaches 93.7% only at 98% of
#     the body, which the whole body strictly dominates. Its recommendation was head-only. (C6) exists so the
#     anchor cannot be reintroduced silently by a later lane: a capped row's served range must START AT LINE 1.
#   * CAUSE READABLE. A body cut because it exceeded the LINE cap and a body cut because it exceeded the BYTE
#     budget are different facts, and src/compactlegend.h's reading of truncated= is written as "cut at the byte
#     budget". Reusing truncated= alone for a line cap would make that registered definition false, which
#     non-negotiable 3 (honesty in output) forbids. So a line-capped row carries cap_lines= as well, and a
#     byte-cut row does not. cap_lines= was checked free: no src/ emitter or legend used it before CB1
#     (CB1 §5 records the check, and records that head_only= was REJECTED because src/abicheck.h already owns
#     it on <ref> for --abi, where "head" means git HEAD).
#   * KEYED ON RANKED CANDIDATES, NOT ON QUERY SYNTAX, AND NOT CAPPED AT 2. src/forkeybody.h gates the key body
#     on backtick spans (forEachBacktickSpan) and caps it at kKeyBodyMax = 2. OR1 (results/OR1_ORIENT_1119/
#     READOUT.md §4) measured --for delivering every edit function's body in 16 of 303 LocBench tasks against
#     --pack-task's 41, and SUB1's median task has 3 gold files, so a cap of 2 cannot satisfy a 3-function task
#     whatever the query looks like. (C8) pins the count cap's removal; the BUDGET is the cap.
#
# WHAT THIS GATE DOES NOT PIN, deliberately: which candidates are chosen (that is ranking), the budget's size
# (K3E measured 12 KB as the SE minimum and PT1 forbids raising it), and the 4,000-byte cut itself — that one is
# already pinned by test/forkeybodycheck.sh arm (K5), and the code step must RE-WORD K5 and the
# static_assert( kHopBodyCapBytes == 4000 && kKeyBodyMax == 2 ) at src/forkeybody.h:63 rather than race it.
#
# ARMS
#   (C0)  PRESENCE GUARD — green on every binary, before and after: the fixture can observe the rule at all.
#         The 121-line and 200-line functions really are ranked candidates of the task, the 20- and 120-line
#         ones really are under the cap, and at least one body really is served. A vacuous fixture is a FAIL.
#   (C1)  <=120 WHOLE: the 120-line body rides whole — its last line is in the CDATA and the row carries no
#         cap_lines=. The cap may never cost a body that already fitted.
#   (C2)  >120 HEAD-ONLY: the 121-line body rides as a head, and the row STATES the head's size.
#   (C3)  DISCLOSED: a capped row carries truncated="1", lines="1-H/T" and a next= that serves the rest.
#   (C4)  CAUSE READABLE: a line-capped row carries cap_lines=; a row cut by the byte budget does not. The two
#         causes are distinguishable from the row alone.
#   (C5)  BOUNDARY, inclusive: 120 lines whole, 121 lines capped. An off-by-one here is a silent unit change.
#   (C6)  HEAD, NOT A WINDOW (SB1): a capped row's served range starts at line 1 and the row carries no anchor
#         or window attribute. This is the arm that keeps SB1's refutation enforced.
#   (C7)  A ZERO SAYS WHAT WAS SCANNED: when no candidate is bodied the shell is kept with total= of the
#         candidates considered, never an absent element (non-negotiable 3: a zero means none found).
#   (C8)  NOT CAPPED AT 2: three bodied candidates under the cap, with budget to spare, ride three bodies.
#   (C9)  SHARED, ONE BLOCK: --for and --pack-task render the SAME unit for the same symbol — the capped row's
#         attributes match between the two verbs. Two implementations that agree today drift tomorrow.
#   (C10) PACK CUTS RATHER THAN DROPS: --pack-task today omits an oversized body whole ("omitted (over budget)")
#         and has no per-body cut at all; under the shared block the large body rides as a head instead.
#   (C11) deterministic: two runs byte-identical.
#   (C12) well formed under xmllint.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "cappedbodycheck: python3 required"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
say(){ if [ "$1" = 0 ]; then ok "$2"; else no "$3"; fi; }
DIR="${KEEP_DIR:-$( mktemp -d )}"; [ -n "${KEEP_DIR:-}" ] || trap 'rm -rf "$DIR"' EXIT; mkdir -p "$DIR"
echo "cappedbodycheck: BIN=$BIN"

# ── fixture ─────────────────────────────────────────────────────────────────────────────────────────────────
# Four functions whose bodies straddle the cap exactly, each in its own file so none can be mistaken for
# another's sibling, and all four reachable from one task so all four are ranked candidates. The line counts
# are the point of the fixture, so they are generated, not hand-written.
F="$DIR/fx"; mkdir -p "$F"
python3 -I - "$F" <<'PYFX'
import sys, os
fx = sys.argv[1]
def fn( name, span, marker ):
    # `span` is the SYMBOL'S INDEXED SPAN: e= - l= + 1, the signature line through the closing brace. That is
    # the denominator the cap is defined on, because it is the only line count the index knows without
    # re-reading the file, and it is the one SR1 measured ("the symbol's indexed body"). A gate written on any
    # other denominator would drift from the rule by two or three lines and nobody would see it.
    mid = span - 5                     # sig, {, FIRST, LAST, }  == 5 fixed lines
    out = [ "// %s: indexed span of %d lines, the token budget parser" % ( name, span ),
            "int %s( int seed )" % name, "{", "    int acc = seed;   // %s_FIRST" % marker ]
    out += [ "    acc += %d;  // %s_L%d" % ( i + 1, marker, i + 1 ) for i in range( mid ) ]
    out += [ "    return acc;       // %s_LAST" % marker, "}" ]
    open( os.path.join( fx, name + ".cpp" ), "w" ).write( "\n".join( out ) + "\n" )
fn( "budgetSmall",  20,  "SMALL" )    # well under the cap
fn( "budgetEdgeA",  120, "E120"  )    # exactly the cap: whole
fn( "budgetEdgeB",  121, "E121"  )    # one past the cap: head only
fn( "budgetLarge",  200, "LARGE" )    # far past the cap, and past the 4,000 B byte cut too
PYFX
for n in budgetSmall budgetEdgeA budgetEdgeB budgetLarge; do
    [ -s "$F/$n.cpp" ] || { echo "cappedbodycheck: fixture file $n.cpp missing or empty"; exit 2; }
done
# a sandbox with no bodied candidate at all, for (C7)
Z="$DIR/zero"; mkdir -p "$Z"
printf 'int budgetDeclOnly( int seed );\nint budgetOtherDecl( int seed );\n' >"$Z/decls.h"

forq(){ ( cd "$F" && "$BIN" . --no-cache --for="$1" --legend=compact 2>/dev/null ); }
packq(){ ( cd "$F" && "$BIN" . --no-cache --pack-task="$1" --legend=compact 2>/dev/null ); }

Q1='how does `budgetEdgeA` parse the token budget'
Q2='how does `budgetEdgeB` parse the token budget'
Q3='how does `budgetLarge` parse the token budget'
Q4='how do `budgetSmall`, `budgetEdgeA` and `budgetEdgeB` parse the token budget'
forq  "$Q1" >"$DIR/a120.for";   packq "$Q1" >"$DIR/a120.pack"
forq  "$Q2" >"$DIR/b121.for";   packq "$Q2" >"$DIR/b121.pack"
forq  "$Q3" >"$DIR/large.for";  packq "$Q3" >"$DIR/large.pack"
forq  "$Q4" >"$DIR/three.for"
forq  "$Q2" >"$DIR/b121.for2"
( cd "$Z" && "$BIN" . --no-cache --for='how does `budgetDeclOnly` parse the token budget' --legend=compact 2>/dev/null ) >"$DIR/zero.for"

python3 -I - "$DIR" <<'PY'
import os, re, sys
D = sys.argv[1]
bad = 0
def rd( n ):
    with open( os.path.join( D, n ) ) as fh: return fh.read()
# Comments are stripped before any <b>/<bodies> is counted: the legends themselves spell those element names,
# and OR1 recorded mistaking a legend's own "<bodies>" for an answer's (99 of 303 instead of 41). This gate
# will not repeat it.
def strip( x ): return re.sub( r"<!--.*?-->", "", x, flags = re.S )
def rows( n ):
    return re.findall( r"<b [^>]*>", strip( rd( n ) ) )
def row( n, name ):
    for r in rows( n ):
        if 'n="%s"' % name in r: return r
    return ""
def cdata( n, name ):
    y = strip( rd( n ) )
    m = re.search( r'<b [^>]*n="%s"[^>]*>\s*<!\[CDATA\[(.*?)\]\]>' % re.escape( name ), y, re.S )
    return m.group( 1 ) if m else ""
def shells( n ):
    return re.findall( r"<bodies[^>]*>", strip( rd( n ) ) )
def attr( r, a ):
    m = re.search( r'\b%s="([^"]*)"' % a, r )
    return m.group( 1 ) if m else None
def say( cond, good, bad_msg = None ):
    global bad
    if cond: print( "  PASS  " + good )
    else:    print( "  FAIL  " + ( bad_msg or good ) ); bad = 1
# A bar this lane REGISTERED and the owner then placed OUT of its scope. It is printed every run, with the
# ruling that deferred it and where the bar now lives, and it does NOT gate -- deleting it would lose the
# bar, and failing on it would make a red that no one in scope can clear. It is not a blind pass: the line
# states the current value every run, so the day it starts holding, the output says so.
def defer( cond, text, where ):
    # a lost line must not be silent either (gateexitcheck G1): print() raising on a closed or full stream
    # would otherwise drop a DEFERRED bar with the gate still exiting 0.
    global bad
    try:
        print( "  %s  %s  [DEFERRED: %s]" % ( "DONE " if cond else "DEFER", text, where ) )
    except OSError as e:
        bad = 1
        sys.stderr.write( "  FAIL  could not write the DEFERRED line for: %s (%s)\n" % ( text, e ) )

# ── (C0) PRESENCE GUARD: green before and after. A vacuous fixture is a FAIL, not a pass. ──────────────────
sigs = { }
for lab, f in ( ( "120", "a120.for" ), ( "121", "b121.for" ), ( "large", "large.for" ) ):
    sigs[ lab ] = strip( rd( f ) )
ranked = all( ( 'n="budgetEdgeA"' in sigs[ "120" ],
                'n="budgetEdgeB"' in sigs[ "121" ],
                'n="budgetLarge"' in sigs[ "large" ] ) )
served_any = bool( rows( "a120.for" ) or rows( "b121.for" ) or rows( "large.for" ) )
# The DENOMINATOR is self-checked against the binary's own index, not trusted from the generator: the cap is
# on e= - l= + 1, so the fixture is only straddling if the binary agrees the spans are 120 and 121.
def span( doc, name ):
    m = re.search( r'<d l="(\d+)" e="(\d+)" n="%s"' % re.escape( name ), sigs[ doc ] ) \
        or re.search( r'<d [^>]*\bl="(\d+)"[^>]*\be="(\d+)"[^>]*\bn="%s"' % re.escape( name ), sigs[ doc ] )
    return int( m.group( 2 ) ) - int( m.group( 1 ) ) + 1 if m else None
sp120, sp121 = span( "120", "budgetEdgeA" ), span( "121", "budgetEdgeB" )
spans_ok = ( sp120 == 120 and sp121 == 121 )
say( ranked and served_any and spans_ok,
     "(C0) fixture observable: the straddling functions are ranked candidates, some body is served, and the "
     "binary's own index agrees the spans are %s and %s" % ( sp120, sp121 ),
     "(C0) VACUOUS FIXTURE -- ranked=%s served_any=%s spans=(%s,%s) want (120,121); no later arm means anything"
     % ( ranked, served_any, sp120, sp121 ) )

# ── (C1) <=120 rides WHOLE ─────────────────────────────────────────────────────────────────────────────────
c1 = cdata( "a120.for", "budgetEdgeA" ); r1 = row( "a120.for", "budgetEdgeA" )
say( bool( c1 ) and "E120_LAST" in c1 and attr( r1, "cap_lines" ) is None,
     "(C1) the 120-line body rides whole (last line present, no cap_lines=)",
     "(C1) the 120-line body is not whole: last_line=%s cap_lines=%s" % ( "E120_LAST" in c1, attr( r1, "cap_lines" ) ) )

# ── (C2) >120 rides HEAD-ONLY, head size STATED ────────────────────────────────────────────────────────────
c2 = cdata( "b121.for", "budgetEdgeB" ); r2 = row( "b121.for", "budgetEdgeB" )
head = attr( r2, "cap_lines" )
served_lines = c2.count( "\n" ) + 1 if c2 else 0
# EXACT ARITHMETIC, not a marker proxy. An earlier draft asserted the body's LAST-line marker was absent;
# with a 121-line span and a 120-line cap exactly one line is cut and that line is the closing brace, so the
# marker sits inside the head and the proxy failed on correct output. The contract is the count: the head is
# the cap's length, the row states the cap, and lines= says so out of the def's true total.
say( bool( c2 ) and head == "120" and served_lines == 120 and attr( r2, "lines" ) == "1-120/121",
     "(C2) the 121-line body rides head-only: %d lines served, cap_lines=%s, lines=%s" % ( served_lines, head, attr( r2, "lines" ) ),
     "(C2) the 121-line body is NOT a 120-line head: cap_lines=%s served=%d lines=%s"
     % ( head, served_lines, attr( r2, "lines" ) ) )

# ── (C3) DISCLOSED ─────────────────────────────────────────────────────────────────────────────────────────
lines3, trunc3, next3 = attr( r2, "lines" ), attr( r2, "truncated" ), attr( r2, "next" )
say( trunc3 == "1" and lines3 is not None and re.fullmatch( r"1-\d+/\d+", lines3 or "" ) and bool( next3 ),
     "(C3) the capped row discloses: truncated=1 lines=%s next=%s" % ( lines3, ( next3 or "" )[ :60 ] ),
     "(C3) the capped row does not disclose: truncated=%s lines=%s next=%s" % ( trunc3, lines3, next3 ) )

# ── (C4) CAUSE READABLE: a line cap says cap_lines=; a byte cut does not ───────────────────────────────────
# budgetLarge is 200 lines AND over 4,000 B, so it is cut by the line cap; the byte cut keeps its own reading.
r4 = row( "large.for", "budgetLarge" )
bytecut_rows = [ r for r in rows( "large.for" ) + rows( "a120.for" )
                 if attr( r, "truncated" ) == "1" and attr( r, "cap_lines" ) is None ]
say( attr( r4, "cap_lines" ) is not None,
     "(C4) the line-capped row names its cause cap_lines=%s, distinguishable from a byte cut (%d byte-cut rows carry none)"
     % ( attr( r4, "cap_lines" ), len( bytecut_rows ) ),
     "(C4) the line-capped row does not name its cause: cap_lines absent, so truncated=1 alone would read as "
     "'cut at the byte budget' (src/compactlegend.h) when it was not" )

# ── (C5) BOUNDARY, inclusive ───────────────────────────────────────────────────────────────────────────────
say( attr( r1, "cap_lines" ) is None and attr( r2, "cap_lines" ) is not None,
     "(C5) the cap is inclusive: 120 whole, 121 capped",
     "(C5) boundary wrong: 120 cap_lines=%s, 121 cap_lines=%s" % ( attr( r1, "cap_lines" ), attr( r2, "cap_lines" ) ) )

# ── (C6) HEAD, NOT A WINDOW (SB1's refutation, enforced) ───────────────────────────────────────────────────
anchorish = [ a for a in ( "hit", "around", "window", "anchor_line", "near" ) if attr( r2, a ) is not None ]
starts_at_1 = ( lines3 or "" ).startswith( "1-" )
say( not anchorish and starts_at_1,
     "(C6) the capped row is a HEAD (lines=%s) with no anchor/window attribute -- SB1's 31.7%% refutation stays enforced" % lines3,
     "(C6) the capped row is not a plain head: anchor-ish attrs=%s lines=%s. SB1 measured a term-anchored "
     "window holding the edit in 20 of 63 large bodies; do not reintroduce it" % ( anchorish, lines3 ) )

# ── (C7) a zero says what was scanned ──────────────────────────────────────────────────────────────────────
# NON-VACUITY FIRST: the sandbox must really have candidates, or "nothing bodied" is not the case being tested.
zy = strip( rd( "zero.for" ) )
zcands = len( re.findall( r"<d ", zy ) )
zs = shells( "zero.for" )
ztotal = attr( zs[ 0 ], "total" ) if zs else None
defer( zcands > 0 and bool( zs ) and ztotal is not None,
     "(C7) a zero says what was scanned: %d candidates considered, shells=%s" % ( zcands, zs ),
     "owner ruling 2026-11-19 put the six-shell consolidation out of CB1's scope; the bar is PREREG_CB1_1119_v2.md D1" )
if False: say( zcands > 0 and bool( zs ) and ztotal is not None,
     "(C7) with %d candidates and nothing bodied the shell is kept and says what was considered (total=%s)"
     % ( zcands, ztotal ),
     "(C7) a zero does not say what was scanned: %d candidates, shells=%s. The root does carry "
     'bodies="0" reason=, but no element names how many candidates were considered for a body, so a reader '
     "cannot tell 'none fitted' from 'none was looked at' (non-negotiable 3)" % ( zcands, zs ) )

# ── (C8) NOT CAPPED AT 2, AND IN ONE BLOCK ─────────────────────────────────────────────────────────────────
# This arm is written on the SHELLS, not on a bare count of <b> rows anywhere in the document. A bare count
# passes today for the wrong reason: three names backticked yield three bodies, but from THREE DIFFERENT
# surfaces -- <bodies of="key"> (kKeyBodyMax=2, and it reports total="1" because the others were already
# carried), <bodies pick="name"> (src/forowner.h's owner slot) and a third row outside both. Six body-bearing
# shells exist in all: of="key", of="hops", of="route", of="launch", pick="name|member", and pack-task's own
# bare <bodies>. The shared block is one shell with one disclosure, so the contract is BOTH halves:
#   (a) all three named candidates ride, and (b) they ride in ONE shell whose own shown=/total= says so.
y3 = strip( rd( "three.for" ) )
shell_of = [ ]
for m in re.finditer( r"<bodies([^>]*)>(.*?)</bodies>", y3, re.S ):
    inner = { attr( r, "n" ) for r in re.findall( r"<b [^>]*>", m.group( 2 ) ) }
    shell_of.append( ( m.group( 1 ).strip(), inner ) )
want3 = { "budgetSmall", "budgetEdgeA", "budgetEdgeB" }
names3 = { attr( r, "n" ) for r in rows( "three.for" ) }
one_shell = [ a for a, inner in shell_of if want3 <= inner ]
defer( want3 <= names3 and bool( one_shell ),
     "(C8) all three candidates ride (%s) in %d shell(s) %s" % ( sorted( names3 & want3 ), len( shell_of ), [ a for a, _ in shell_of ] ),
     "owner ruling 2026-11-19: build the small fix first, NOT the six-shell consolidation; the bar is PREREG_CB1_1119_v2.md D2" )
if False: say( want3 <= names3 and bool( one_shell ),
     "(C8) all three candidates under the cap ride, in ONE block (%s)" % ( one_shell[ 0 ] if one_shell else "" ),
     "(C8) %s of the three rode, spread over %d shells %s. src/forkeybody.h kKeyBodyMax=2 caps the key block "
     "at two and SUB1's median task has 3 gold files, so a cap of 2 cannot satisfy it; and three bodies "
     "arriving through three surfaces is three disclosures, not one shared block"
     % ( sorted( names3 & want3 ), len( shell_of ), [ a for a, _ in shell_of ] ) )

# ── (C9) SHARED: the two verbs render the same unit ────────────────────────────────────────────────────────
# NON-VACUITY: an all-absent unit equals an all-absent unit. The comparison only means something once the
# unit exists, so the arm requires a stated cap on BOTH sides before it compares them.
pr = row( "b121.pack", "budgetEdgeB" )
def unit( r ): return ( attr( r, "cap_lines" ), attr( r, "lines" ), attr( r, "truncated" ) )
stated = bool( pr ) and bool( r2 ) and attr( r2, "cap_lines" ) is not None and attr( pr, "cap_lines" ) is not None
say( stated and unit( pr ) == unit( r2 ),
     "(C9) --for and --pack-task render the same unit for budgetEdgeB: %s" % ( unit( r2 ), ),
     "(C9) the shared unit is not rendered by both verbs: for=%s pack=%s (both-sides-stated=%s). An all-absent "
     "match is not a match -- one shared block, not two implementations" % ( unit( r2 ), unit( pr ), stated ) )

# ── (C10) PACK CUTS RATHER THAN DROPS ──────────────────────────────────────────────────────────────────────
pl = rd( "large.pack" )
omitted = re.search( r"omitted \(over budget\):\s*([^-]*?)\s*-->", pl )
pbig = row( "large.pack", "budgetLarge" )
say( bool( pbig ) and attr( pbig, "cap_lines" ) is not None,
     "(C10) --pack-task serves the 200-line body as a head instead of omitting it whole",
     "(C10) --pack-task still has no per-body cut: row=%s omitted=%s. Whole-body-or-nothing is the +109%% unit "
     "SR1 measured" % ( bool( pbig ), omitted.group( 1 ) if omitted else None ) )

# ── (C11) deterministic ────────────────────────────────────────────────────────────────────────────────────
say( rd( "b121.for" ) == rd( "b121.for2" ), "(C11) two runs byte-identical", "(C11) two runs differ" )
sys.exit( 1 if bad else 0 )
PY
[ $? -eq 0 ] || fail=1

# ── (C12) well formed ───────────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    for f in a120.for b121.for large.for three.for zero.for a120.pack b121.pack large.pack; do
        xmllint --noout "$DIR/$f" 2>/dev/null
        say $? "(C12) $f is well formed" "(C12) xmllint rejects $f"
    done
else
    echo "  SKIP  (C12) xmllint not installed"
fi

[ "$fail" = 0 ] && echo "cappedbodycheck: ALL PASS" || echo "cappedbodycheck: FAILED"
exit "$fail"
