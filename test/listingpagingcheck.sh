#!/usr/bin/env bash
# listingpagingcheck.sh — three LISTING verbs learn to page honestly: --doc-drift, --flags (with --flip)
# and --situ. The class is the one PR #108 closed on --edit-check, found again by the 2026-09-10 cap audit
# (C1 rows F-06, F-07, F-10) on the three verbs whose row listings no flag could reach:
#
#   F-06  --doc-drift cut its per-doc <a> listing at kMaxAnchorsShown=12 and disclosed it with nothing but a
#         <more drift=> remainder, while no output named the flag that lifts it. The audit's suggested fix —
#         route the cap through effectiveRowCap so --limit raises it — was BUILT AND REJECTED, with the
#         evidence coming from test/pagingsweepcheck.sh: the <a> rows are a SECONDARY listing under the
#         PRIMARY <doc> rows that --limit already windows, so one flag governing both makes the same doc
#         print shown_failed="3" at --limit=3 and shown_failed="6" at --limit=6 — page[0:3] + page[3:6]
#         stops equalling page[0:6] and the --offset continuity arm goes red, correctly. The tool had
#         already settled this shape (pageview.h kImportReachRowCap: a secondary listing "is NOT raisable
#         by --limit … discloses through shown_importers=/importers_capped= and nothing else"), so what
#         closes here is the SILENCE: the pair on the doc that was cut, and next= naming --detail.
#   F-07  src/darkflags.h and src/flipimpact.h emitted NO shown=/total=/capped= token at all (grep: 0 hits
#         in either file). --flags cut the <read> sites under a gate at 8 and --flip cut six listings at 25,
#         both in silence but for a bare <more …/> remainder, and no flag lifted either.
#   F-10  --situ — the mid-task verb CLAUDE.md's own protocol names — cut its blast radius to 8 of 69 files
#         and its co-change partners to 8 of 116, said so in PROSE ONLY, and REFUSED --limit outright.
#
# WHICH ROWS ARE THE ANSWER, AND THEREFORE NEVER PAGE. This is the whole design, so it is stated here and
# asserted below rather than left to the reader of a diff. It is read out of each verb's OWN legend:
#
#   --flags    the <gate> rows ARE the answer ("what is BUILT but DARK here"). They are never windowed,
#              capped or paged. What pages is the read SITES under one gate — context for a gate row.
#   --flip     "tests = test files reaching the hosts" is the tests_to_run family (flipimpact.h M21(b)),
#              the rows you RUN. They are served whole on every page, exactly as --test-gate's <t> listing
#              always has been. Everything else — lights r/b, hosts, downstream, untested, build sites —
#              is context and pages at 25 by default. (untested= pages like --test-gate's <u> rows, whose
#              verdict is the root COUNT and the exit code, not the emitted rows.)
#   --situ     section [2], tests to run, is the answer: --test-gate exits 4 on exactly those rows. It has
#              no cap at all any more. Sections [1] blast radius and [3] co-change partners are context.
#   --doc-drift  there is no answer LISTING — the answer is the per-doc verdict (drift=/dated=), which is
#              computed over the full anchor set. Every <a> row is context; it is capped, disclosed, and
#              lifted by --detail rather than windowed by --limit (see F-06 above).
#
# ARMS. Each verb gets the capdisclosurecheck triple plus the decisive one:
#   (CROSSING)    the fixture really is past the cap, proved from the UNCAPPED run's own row count — a green
#                 arm can never be a fixture that never reached the code under test.
#   (DISCLOSURE)  the cut answer says so in pageview.h's vocabulary (shown_<noun>=/<noun>_capped=, or the
#                 prose triple for --situ) AND carries next=, the exact pasteable follow-up.
#   (RE-DERIVATION) THE DECISIVE ONE. The same binary is run twice — default, and at the --limit the
#                 answer's own next= names — and every VERDICT/count attribute must be BYTE-IDENTICAL.
#                 "Does the bound trip" is green for a broken emitter too; "does the answer move when the
#                 bound is removed" is not.
#   (SILENCE)     a fixture that FITS carries none of the pair, and NOTHING anywhere emits a *_capped="0"
#                 of the new family or a shown_<noun>= equal to its total (the round's rule 1: a disclosure
#                 that can never fire is indistinguishable from one that cannot).
#   (ANSWER)      the answer rows above are complete at the default cap — count them.
#   (MUTATION)    the RE-DERIVATION comparison can go red. Done on a SYNTHESIZED document, not a scratch
#                 build: test/pargates.py runs this gate under a wall budget, and a compile inside a budgeted
#                 gate is the failure mode recorded as "a build inside a budgeted gate" — super-linear under
#                 contention, and a bigger budget cannot fix it. The mutation rewrites a verdict attribute to
#                 the WINDOW's row count, which is precisely the bug the arm exists to catch, and the arm
#                 must report it.
#
# MUTATION CONTROL (the red run this gate was written from): against a binary built before this change —
#     RIPWIRE_BIN=<pre-change>/ripwire bash test/listingpagingcheck.sh
# — 24 of 33 checks FAIL, measured at 6afaa457 on 2026-09-10. Note that the CROSSING halves fail there too,
# and that is not a weakness of the fixture: crossing is proved from the run at --limit=1000000, and the
# whole finding is that the pre-change binary does not honour it (--doc-drift served the same 12 rows,
# --flags/--flip/--situ REFUSED the flag). The three that still pass are (E)'s two silence arms and the
# per-doc verdict comparison — which is the point: those were already correct, and this change keeps them so.
#
# Usage:
#   bash test/listingpagingcheck.sh
#   RIPWIRE_BIN=asan/ripwire bash test/listingpagingcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success. Needs git + python3.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "listingpagingcheck: git required";     exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "listingpagingcheck: python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "listingpagingcheck: BIN=$BIN"

# Every cap is read from the source that DEFINES it, never retyped: a gate holding its own copy of "8" goes
# green the day the constant moves and the emitter stops agreeing with it.
capof(){ sed -n "s/.*$2 *= *\([0-9][0-9]*\).*/\1/p" "$ROOT/src/$1" | head -1; }
CAP_ANCHORS="$( capof docdrift.h   kMaxAnchorsShown )"
CAP_SITES="$(   capof darkflags.h  kMaxSitesShown )"
CAP_FLIP="$(    capof flipimpact.h kMaxFlipRows )"
CAP_BLAST="$(   capof situ.h       kSituBlastFilesShown )"
CAP_PARTNER="$( capof situ.h       kSituPartnerRowsShown )"
for v in CAP_ANCHORS CAP_SITES CAP_FLIP CAP_BLAST CAP_PARTNER; do
    eval "n=\$$v"
    case "$n" in ''|*[!0-9]*) echo "listingpagingcheck: could not read $v from src/"; exit 2 ;; esac
done
echo "  (kMaxAnchorsShown=$CAP_ANCHORS kMaxSitesShown=$CAP_SITES kMaxFlipRows=$CAP_FLIP kSituBlastFilesShown=$CAP_BLAST kSituPartnerRowsShown=$CAP_PARTNER)"

# ---------------------------------------------------------------------------------------------------
# FIXTURES, sized FROM the caps above so none of them lands one row short of the bound it is testing.
#
#  DD    one markdown doc carrying CAP_ANCHORS*3 failed anchors — backticked names this tree defines
#        NOWHERE, each on a line that also names a real symbol (docdrift.h kCorroborateWin: a mention only
#        counts as a claim about this code when a name the repo DOES define sits on the same line).
#  FL    one header gate read from CAP_FLIP*2 files, each read inside its own `#if` region — so the SAME
#        fixture crosses --flags' per-gate site cap AND --flip's per-listing row cap.
#  ST    a git tree where one header is called by CAP_BLAST*6 files (blast radius) and CAP_PARTNER*3 more
#        files were committed alongside it in every commit of its history (co-change partners), so both of
#        --situ's context sections are past their caps while section [2] stays the answer.
#  FIT   the SILENCE control: one tiny doc, one gate with one read, one file. Nothing can be cut.
# ---------------------------------------------------------------------------------------------------
python3 - "$TMP" "$CAP_ANCHORS" "$CAP_SITES" "$CAP_FLIP" "$CAP_BLAST" "$CAP_PARTNER" <<'PY'
import os, sys
tmp = sys.argv[1]
anchors, sites, fliprows, blast, partner = ( int( a ) for a in sys.argv[2:7] )

def w( path, text ):
    os.makedirs( os.path.dirname( path ), exist_ok=True )
    open( path, "w" ).write( text )

# ── DD ───────────────────────────────────────────────────────────────────────────────────────────────
nAnchors = anchors * 3
w( tmp + "/dd/src/code.h",
   "#pragma once\n" + "".join( "inline int realAnchorSymbol%03d() { return %d; }\n" % ( i, i ) for i in range( nAnchors ) ) )
lines = [ "# Drift fixture\n\n" ]
for i in range( nAnchors ):
    lines.append( "- `realAnchorSymbol%03d` is wired to `zzqPhantomGadget%03d` in the pipeline.\n" % ( i, i ) )
w( tmp + "/dd/DOC.md", "".join( lines ) )

# ── FL ───────────────────────────────────────────────────────────────────────────────────────────────
nSites = fliprows * 2
w( tmp + "/fl/wide.h", "#pragma once\n#ifndef FIXTURE_WIDE_GATE\n#define FIXTURE_WIDE_GATE 0\n#endif\n" )
for i in range( nSites ):
    w( tmp + "/fl/u%03d.cpp" % i,
       '#include "wide.h"\n'
       "int wideUser%03d()\n{\n#if FIXTURE_WIDE_GATE\n    return %d;\n#endif\n    return 0;\n}\n" % ( i, i ) )
# …and one test file per host, well past kMaxFlipRows, so "the tests_to_run rows are never cut" is an
# assertion about a listing that WOULD be cut rather than about an empty one.
for i in range( nSites ):
    w( tmp + "/fl/test/t%03d_test.cpp" % i,
       "int wideUser%03d();\nint checkWide%03d() { return wideUser%03d(); }\n" % ( i, i, i ) )

# ── ST ───────────────────────────────────────────────────────────────────────────────────────────────
nUsers    = blast * 6
nPartners = partner * 3
w( tmp + "/st/core.h", "#pragma once\ninline int coreEntryPoint() { return 7; }\n" )
for i in range( nUsers ):
    w( tmp + "/st/u%03d.cpp" % i, '#include "core.h"\nint stUser%03d() { return coreEntryPoint(); }\n' % i )
for i in range( nPartners ):
    w( tmp + "/st/p%03d.cpp" % i, "int stPartner%03d() { return %d; }\n" % ( i, i ) )
# section [2] is the ANSWER, so it needs more test rows than the cap it used to carry (25) for the "never
# cut" arm to mean anything.
for i in range( nUsers ):
    w( tmp + "/st/test/t%03d_test.cpp" % i, '#include "../core.h"\nint stCheck%03d() { return coreEntryPoint(); }\n' % i )

# ── FIT ──────────────────────────────────────────────────────────────────────────────────────────────
w( tmp + "/fit/src/code.h",
   "#pragma once\n#ifndef FIXTURE_TINY_GATE\n#define FIXTURE_TINY_GATE 0\n#endif\n"
   "inline int tinyRealSymbol() { return 1; }\n#if FIXTURE_TINY_GATE\ninline int tinyDark() { return 2; }\n#endif\n" )
w( tmp + "/fit/DOC.md", "# Tiny\n\n- `tinyRealSymbol` talks to `zzqPhantomOnlyOne` once.\n" )
PY

# ST's git history: EVERY commit touches core.h together with every p###.cpp, so the co-change miner sees a
# wide partner set; the working tree then modifies core.h alone. Committed with an isolated identity and
# `git -C` throughout (no cd, no reliance on the caller's config).
gitq(){ git -C "$TMP/st" -c user.name=gate -c user.email=gate@example.com -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
gitq init -q
gitq add -A
gitq commit -q -m "base"
i=0
while [ "$i" -lt 5 ]; do
    printf '// touch %s\n' "$i" >> "$TMP/st/core.h"
    j=0
    while [ "$j" -lt "$(( CAP_PARTNER * 3 ))" ]; do
        printf '// touch %s\n' "$i" >> "$TMP/st/p$( printf '%03d' "$j" ).cpp"
        j=$(( j + 1 ))
    done
    gitq add -A
    gitq commit -q -m "round $i"
    i=$(( i + 1 ))
done
printf 'inline int coreEntryPointTwo() { return 8; }\n' >> "$TMP/st/core.h"

run(){ dir="$1"; out="$2"; shift 2; "$BIN" "$dir" "$@" >"$TMP/$out" 2>"$TMP/$out.err"; }

# The one shared reader: pull an attribute off the FIRST element with the given tag.
attr(){ python3 - "$1" "$2" "$3" <<'PY'
import re, sys
doc  = open( sys.argv[1], errors="replace" ).read()
body = re.sub( r'\A(?:\s*<!--.*?-->)+', '', doc, flags=re.S )
m = re.search( r'<' + re.escape( sys.argv[2] ) + r'((?:\s+[\w:.-]+="[^"]*")*)\s*/?>', body )
if not m: sys.exit( 0 )
v = re.search( r'\s' + re.escape( sys.argv[3] ) + r'="([^"]*)"', m.group( 1 ) )
print( v.group( 1 ) if v else "" )
PY
}
countrows(){ grep -o "<$2 " "$TMP/$1" | wc -l | tr -d ' '; }

# ===================================================================================================
echo "=== (A) --doc-drift: the per-doc <a> listing pages, and the per-doc VERDICT does not (F-06) ==="
# ===================================================================================================
run "$TMP/dd" dd_def --doc-drift --no-cache
run "$TMP/dd" dd_all --doc-drift --no-cache --detail=1
A_DEF="$( countrows dd_def a )"
A_ALL="$( countrows dd_all a )"

# CROSSING — proved from the UNCAPPED run, not asserted from the fixture's source
if [ "$A_ALL" -gt "$CAP_ANCHORS" ]; then ok "(A) crossing: the uncapped run emits $A_ALL <a> rows, past the $CAP_ANCHORS cap"
else no "(A) crossing: uncapped run emits only $A_ALL <a> rows — the fixture never reaches the cap ($( head -c 200 "$TMP/dd_all" ))"; fi
if [ "$A_ALL" -gt "$A_DEF" ]; then ok "(A) --detail lifts the per-doc anchor cap: $A_DEF rows bare, $A_ALL under --detail"
else no "(A) --detail does not lift the anchor cap ($A_DEF bare, $A_ALL under --detail)"; fi
# THE SECONDARY-LISTING RULE (pageview.h rule 6): --limit windows the <doc> ROWS and must NOT reach into the
# listing under one of them, or a doc's own row count starts depending on which page served it — and
# page[0:3] + page[3:6] stops equalling page[0:6], which is pagingsweepcheck's --offset continuity contract.
A_L3="$( "$BIN" "$TMP/dd" --doc-drift --no-cache --limit=3 2>/dev/null | grep -o "<doc p=[^>]*>" | head -1 )"
A_L6="$( "$BIN" "$TMP/dd" --doc-drift --no-cache --limit=6 2>/dev/null | grep -o "<doc p=[^>]*>" | head -1 )"
if [ -n "$A_L3" ] && [ "$A_L3" = "$A_L6" ]; then
    ok "(A) rule 6: the first <doc> element is byte-identical at --limit=3 and --limit=6 — the window does not reach the secondary listing"
else
    no "(A) rule 6: the <doc> element CHANGES with --limit ($A_L3 vs $A_L6) — a paged walk is no longer equivalent to the whole"
fi

# DISCLOSURE
DD_SHOWN="$( attr "$TMP/dd_def" doc shown_failed )"
DD_CAP="$(   attr "$TMP/dd_def" doc failed_capped )"
DD_TOT="$(   attr "$TMP/dd_def" doc failed_total )"
DD_NEXT="$(  attr "$TMP/dd_def" doc-drift next )"
if [ "$DD_SHOWN" = "$CAP_ANCHORS" ] && [ "$DD_CAP" = "1" ] && [ -n "$DD_TOT" ] && [ "$DD_TOT" -gt "$CAP_ANCHORS" ]; then
    ok "(A) disclosure: <doc shown_failed=\"$DD_SHOWN\" failed_capped=\"1\" failed_total=\"$DD_TOT\">"
else
    no "(A) disclosure: the cut <doc> says shown_failed=\"$DD_SHOWN\" failed_capped=\"$DD_CAP\" failed_total=\"$DD_TOT\" — the cut is not disclosed"
fi
case "$DD_NEXT" in
    --doc-drift\ --detail=1) ok "(A) next=\"$DD_NEXT\" on the cut root — the flag that lifts this cap" ;;
    *) no "(A) the cut root carries next=\"$DD_NEXT\" — expected the pasteable --doc-drift --detail=1" ;;
esac
# the next= is PASTED AS THE WHOLE ARGV, which is what "pasteable" claims, and it must cut nothing at all
if [ -n "$DD_NEXT" ]; then
    # shellcheck disable=SC2086
    "$BIN" "$TMP/dd" $DD_NEXT --no-cache >"$TMP/dd_next" 2>"$TMP/dd_next.err"
    if [ -z "$( attr "$TMP/dd_next" doc failed_capped )" ] && [ "$( countrows dd_next a )" = "$A_ALL" ]; then
        ok "(A) next= is EXACT: pasted verbatim it emits all $A_ALL rows and cuts nothing"
    else
        no "(A) next=\"$DD_NEXT\" pasted verbatim still cuts rows ($( countrows dd_next a ) of $A_ALL): $( head -c 160 "$TMP/dd_next.err" )"
    fi
fi

# RE-DERIVATION — every verdict attribute, root and per-doc, byte-identical with the window removed
python3 - "$TMP/dd_def" "$TMP/dd_all" <<'PY'
import re, sys
PAGING = re.compile( r'\s(?:shown|capped|total|has_more|next_offset|offset|limit|next|at|est_tokens)="[^"]*"'
                     r'|\sshown_\w+="[^"]*"|\s\w+_capped="[^"]*"|\s\w+_total="[^"]*"' )
def verdicts( path ):
    body = re.sub( r'\A(?:\s*<!--.*?-->)+', '', open( path, errors="replace" ).read(), flags=re.S )
    out = []
    for m in re.finditer( r'<(doc-drift|doc)((?:\s+[\w:.-]+="[^"]*")*)\s*/?>', body ):
        out.append( m.group( 1 ) + PAGING.sub( '', m.group( 2 ) ) )
    return out
a, b = verdicts( sys.argv[1] ), verdicts( sys.argv[2] )
if a == b and len( a ) > 1:
    print( "  PASS  (A) re-derivation: %d <doc-drift>/<doc> verdict signatures byte-identical bare vs --detail" % len( a ) )
else:
    print( "  FAIL  (A) re-derivation: a verdict MOVED with the window" )
    for x, y in zip( a, b ):
        if x != y: print( "          bare: " + x + "\n          all : " + y ); break
    if len( a ) != len( b ): print( "          %d rows bare, %d under --detail" % ( len( a ), len( b ) ) )
    sys.exit( 1 )
PY
[ $? = 0 ] || fail=1

# ===================================================================================================
echo "=== (B) --flags: the read SITES page, the GATE rows are the answer and never do (F-07) ==="
# ===================================================================================================
run "$TMP/fl" fl_def --flags --no-cache
run "$TMP/fl" fl_all --flags --no-cache --limit=1000000
R_DEF="$( countrows fl_def read )"
R_ALL="$( countrows fl_all read )"
G_DEF="$( countrows fl_def gate )"
G_ALL="$( countrows fl_all gate )"

if [ "$R_ALL" -gt "$CAP_SITES" ]; then ok "(B) crossing: the uncapped run emits $R_ALL <read> rows, past the $CAP_SITES cap"
else no "(B) crossing: only $R_ALL <read> rows uncapped — the fixture never reaches the cap"; fi
if [ "$R_ALL" -gt "$R_DEF" ]; then ok "(B) --limit raises the per-gate site cap: $R_DEF sites bare, $R_ALL at --limit=1000000"
else no "(B) --limit does not reach the site cap ($R_DEF bare, $R_ALL at --limit=1000000)"; fi

FL_SHOWN="$( attr "$TMP/fl_def" gate shown_reads )"
FL_CAP="$(   attr "$TMP/fl_def" gate reads_capped )"
FL_NEXT="$(  attr "$TMP/fl_def" flags next )"
if [ "$FL_SHOWN" = "$CAP_SITES" ] && [ "$FL_CAP" = "1" ]; then
    ok "(B) disclosure: <gate … reads=\"N\" shown_reads=\"$FL_SHOWN\" reads_capped=\"1\">"
else
    no "(B) disclosure: the cut <gate> says shown_reads=\"$FL_SHOWN\" reads_capped=\"$FL_CAP\" — F-07's silent cut is still silent"
fi
case "$FL_NEXT" in
    --flags\ --limit=*) ok "(B) next=\"$FL_NEXT\" on the cut root" ;;
    *) no "(B) the cut <flags> root carries next=\"$FL_NEXT\" — expected --flags --limit=N" ;;
esac

# ANSWER: gate rows are never windowed — the count cannot move
if [ "$G_DEF" = "$G_ALL" ] && [ "$G_DEF" -gt 0 ]; then ok "(B) answer: $G_DEF <gate> rows at the default cap, the same $G_ALL uncapped — never windowed"
else no "(B) answer: $G_DEF <gate> rows bare vs $G_ALL uncapped — the ANSWER rows are being paged"; fi

python3 - "$TMP/fl_def" "$TMP/fl_all" <<'PY'
import re, sys
PAGING = re.compile( r'\snext="[^"]*"|\sshown_\w+="[^"]*"|\s\w+_capped="[^"]*"' )
def verdicts( path ):
    body = re.sub( r'\A(?:\s*<!--.*?-->)+', '', open( path, errors="replace" ).read(), flags=re.S )
    return [ m.group( 1 ) + PAGING.sub( '', m.group( 2 ) )
             for m in re.finditer( r'<(flags|gate)((?:\s+[\w:.-]+="[^"]*")*)\s*/?>', body ) ]
a, b = verdicts( sys.argv[1] ), verdicts( sys.argv[2] )
if a == b and len( a ) > 1:
    print( "  PASS  (B) re-derivation: %d <flags>/<gate> verdict signatures byte-identical bare vs --limit=1000000" % len( a ) )
else:
    print( "  FAIL  (B) re-derivation: a --flags verdict MOVED with the window" )
    for x, y in zip( a, b ):
        if x != y: print( "          bare: " + x[:200] + "\n          all : " + y[:200] ); break
    sys.exit( 1 )
PY
[ $? = 0 ] || fail=1

# ===================================================================================================
echo "=== (C) --flags --flip: six context listings page; the tests_to_run rows never do (F-07) ==="
# ===================================================================================================
run "$TMP/fl" fp_def --flags --flip=FIXTURE_WIDE_GATE --no-cache
run "$TMP/fl" fp_all --flags --flip=FIXTURE_WIDE_GATE --no-cache --limit=1000000
P_DEF="$( countrows fp_def r )"
P_ALL="$( countrows fp_all r )"
if [ "$P_ALL" -gt "$CAP_FLIP" ]; then ok "(C) crossing: the uncapped flip emits $P_ALL <r> rows, past the $CAP_FLIP cap"
else no "(C) crossing: only $P_ALL <r> rows uncapped — the fixture never reaches the cap ($( head -c 200 "$TMP/fp_all.err" ))"; fi
if [ "$P_ALL" -gt "$P_DEF" ]; then ok "(C) --limit raises the flip row cap: $P_DEF <r> rows bare, $P_ALL at --limit=1000000"
else no "(C) --limit does not reach the flip row cap ($P_DEF bare, $P_ALL uncapped)"; fi

FP_SHOWN="$( attr "$TMP/fp_def" lights shown_r )"
FP_CAP="$(   attr "$TMP/fp_def" lights r_capped )"
FP_NEXT="$(  attr "$TMP/fp_def" flip next )"
if [ "$FP_SHOWN" = "$CAP_FLIP" ] && [ "$FP_CAP" = "1" ]; then
    ok "(C) disclosure: <lights r=\"N\" shown_r=\"$FP_SHOWN\" r_capped=\"1\">"
else
    no "(C) disclosure: the cut <lights> says shown_r=\"$FP_SHOWN\" r_capped=\"$FP_CAP\" — the cut is not disclosed"
fi
case "$FP_NEXT" in
    --flags\ --flip=*--limit=*) ok "(C) next=\"$FP_NEXT\" on the cut root" ;;
    *) no "(C) the cut <flip> root carries next=\"$FP_NEXT\" — expected --flags --flip=NAME --limit=N" ;;
esac
# ANSWER: the <t> rows equal the tests= total at the DEFAULT cap
T_TOTAL="$( attr "$TMP/fp_def" flip tests )"
T_ROWS="$( countrows fp_def t )"
if [ "${T_TOTAL:-0}" = "$T_ROWS" ]; then ok "(C) answer: all ${T_TOTAL:-0} tests_to_run <t> rows ride the default page — never windowed"
else no "(C) answer: tests=\"$T_TOTAL\" but $T_ROWS <t> rows at the default cap — the ANSWER rows are being paged"; fi

# ===================================================================================================
echo "=== (D) --situ: sections [1] and [3] page, section [2] is the answer (F-10) ==="
# ===================================================================================================
run "$TMP/st" st_def --situ=core.h --no-cache
if [ -s "$TMP/st_def" ]; then ok "(D) --situ=core.h answered (it used to REFUSE --limit outright)"; else no "(D) --situ produced nothing: $( head -c 300 "$TMP/st_def.err" )"; fi
run "$TMP/st" st_all --situ=core.h --no-cache --limit=1000000
if [ -s "$TMP/st_all" ]; then ok "(D) --situ=core.h --limit=1000000 is HONORED (exit $?), not refused"
else no "(D) --situ still refuses --limit: $( head -c 300 "$TMP/st_all.err" )"; fi

python3 - "$TMP/st_def" "$TMP/st_all" "$CAP_BLAST" "$CAP_PARTNER" <<'PY'
import re, sys
d, a = ( open( p, errors="replace" ).read() for p in sys.argv[1:3] )
blastCap, partnerCap = int( sys.argv[3] ), int( sys.argv[4] )
fail = 0
def rows( text, marker, rowPat ):
    # the indented "        path  (N dependent symbols)" rows of ONE section. Matched by their own shape,
    # not by indentation: the counts_floor / script-gates disclosure lines are indented exactly like a row
    # and counting them was this gate's own first false red.
    m = re.search( re.escape( marker ) + r'.*?\n((?:        \S.*\n)*)', text )
    return [ l for l in ( m.group( 1 ).splitlines() if m else [] ) if re.search( rowPat, l ) ]

for label, marker, cap, rowPat in ( ( "[1] blast radius", "  [1] blast radius", blastCap,   r'\(\d+ dependent symbols\)$' ),
                                    ( "[3] co-change",    "  [3] co-change",    partnerCap, r'\(co-edited in \d+% of commits\)$' ) ):
    dn, an = len( rows( d, marker, rowPat ) ), len( rows( a, marker, rowPat ) )
    if an <= cap:
        print( "  FAIL  (D) crossing: %s has only %d rows uncapped — the fixture never reaches the %d cap" % ( label, an, cap ) ); fail = 1
    elif dn != cap:
        print( "  FAIL  (D) %s printed %d rows at the default cap of %d" % ( label, dn, cap ) ); fail = 1
    elif an <= dn:
        print( "  FAIL  (D) %s: --limit=1000000 gave %d rows, the bare run %d — --limit does not reach it" % ( label, an, dn ) ); fail = 1
    else:
        print( "  PASS  (D) %s pages: %d rows bare (cap %d), %d at --limit=1000000" % ( label, dn, cap, an ) )
    hdr = [ l for l in d.splitlines() if l.startswith( marker ) ]
    line = hdr[ 0 ] if hdr else ""
    if re.search( r'shown=%d total=\d+ capped=1' % dn, line ) and "; next: --situ=core.h --limit=" in line:
        print( "  PASS  (D) %s discloses shown=/total=/capped=1 and the exact next: invocation" % label )
    else:
        print( "  FAIL  (D) %s header carries no shown=/total=/capped=/next: — %s" % ( label, line[:200] ) ); fail = 1

# ANSWER: section [2] has no cap at all — no showing-note ever, and every one of its rows is served. The
# retired cap was 25, so a fixture with more than 25 reachable test files is what makes this arm real.
for text, which in ( ( d, "bare" ), ( a, "--limit=1000000" ) ):
    hdr = [ l for l in text.splitlines() if l.startswith( "  [2] tests to run" ) ]
    line = hdr[ 0 ] if hdr else ""
    total = int( re.search( r'\((\d+)\)', line ).group( 1 ) ) if re.search( r'\((\d+)\)', line ) else 0
    served = len( rows( text, "  [2] tests to run", r'^        \S' ) ) - 1   # minus the script-gates disclosure line
    if total <= 25:
        print( "  FAIL  (D) answer: only %d test rows (%s) — the fixture cannot show the retired 25-row cap is gone" % ( total, which ) ); fail = 1
    elif "showing" in line or "capped=" in line:
        print( "  FAIL  (D) answer: section [2] is capped (%s): %s" % ( which, line[:200] ) ); fail = 1
    elif served != total:
        print( "  FAIL  (D) answer: section [2] says %d tests and printed %d rows (%s)" % ( total, served, which ) ); fail = 1
    else:
        print( "  PASS  (D) answer: all %d tests_to_run rows served, no cap note (%s)" % ( total, which ) )

# RE-DERIVATION: every counted quantity in the section headers is identical with the window removed
def counts( text ):
    return ( re.findall( r'\[1\] blast radius: (\d+) symbols across (\d+) files', text )
           + re.findall( r'\[2\] tests to run \((\d+)\)', text )
           + re.findall( r'\[3\] co-change .*? \((\d+)\) window="([^"]*)" commits="(\d+)"', text ) )
if counts( d ) == counts( a ) and counts( d ):
    print( "  PASS  (D) re-derivation: every --situ section COUNT is identical bare vs --limit=1000000" )
else:
    print( "  FAIL  (D) re-derivation: a --situ count moved with the window: %r vs %r" % ( counts( d ), counts( a ) ) ); fail = 1
sys.exit( fail )
PY
[ $? = 0 ] || fail=1

# ===================================================================================================
echo "=== (E) SILENCE: a listing that FITS carries none of it, and no capped=\"0\" of this family ==="
# ===================================================================================================
run "$TMP/fit" fit_dd --doc-drift --no-cache
run "$TMP/fit" fit_fl --flags     --no-cache
for f in fit_dd fit_fl; do
    # the legends DEFINE this vocabulary in band, so they are stripped first — grepping the raw document
    # would find the legend's own words and call a byte-neutral answer a leak.
    leak="$( python3 - "$TMP/$f" <<'PYE'
import re, sys
body = re.sub( r'<!--.*?-->', '', open( sys.argv[1], errors="replace" ).read(), flags=re.S )
m = re.search( r'\s(?:shown_\w+|\w+_capped|failed_total|next)="[^"]*"', body )
print( m.group( 0 ).strip() if m else "" )
PYE
)"
    if [ -n "$leak" ]; then
        no "(E) silence: the uncut $f document carries a paging attribute it did not need: $leak"
    else
        ok "(E) silence: the uncut $f document is free of the pair — byte-neutral where nothing was cut"
    fi
done
# the round's rule 1, swept over EVERY document this gate produced: never a *_capped="0" of the new family,
# and never a shown_<noun>= that equals its own total.
python3 - "$TMP" <<'PY'
import os, re, sys
NEW = ( "failed", "weak", "reads", "r", "b", "hosts", "downstream", "untested", "build" )
bad = []
seen = 0
for name in sorted( os.listdir( sys.argv[1] ) ):
    path = os.path.join( sys.argv[1], name )
    if not os.path.isfile( path ) or name.endswith( ".err" ): continue
    text = open( path, errors="replace" ).read()
    body = re.sub( r'\A(?:\s*<!--.*?-->)+', '', text, flags=re.S )
    body = re.sub( r'<!--.*?-->', '', body, flags=re.S )     # the in-band legends DEFINE the vocabulary; they are not data
    for noun in NEW:
        for m in re.finditer( r'\s%s_capped="([^"]*)"' % noun, body ):
            seen += 1
            if m.group( 1 ) != "1": bad.append( "%s: %s_capped=\"%s\" — a disclosure that fired to say nothing was cut" % ( name, noun, m.group( 1 ) ) )
    for m in re.finditer( r'<(\w[\w-]*)((?:\s+[\w:.-]+="[^"]*")*)', body ):
        attrs = m.group( 2 )
        for noun in NEW:
            s = re.search( r'\sshown_%s="(\d+)"' % noun, attrs )
            if not s: continue
            for totalName in ( noun, noun + "_total", "n" ):
                t = re.search( r'\s%s="(\d+)"' % re.escape( totalName ), attrs )
                if t and int( s.group( 1 ) ) >= int( t.group( 1 ) ):
                    bad.append( "%s: <%s shown_%s=\"%s\" %s=\"%s\"> — shown == total, so nothing was cut" %
                                ( name, m.group( 1 ), noun, s.group( 1 ), totalName, t.group( 1 ) ) )
                if t: break
if bad:
    for b in bad[:6]: print( "  FAIL  (E) " + b )
    sys.exit( 1 )
print( "  PASS  (E) rule 1 sweep: %d *_capped= of the new family across every document, every one a fired \"1\"" % seen )
PY
[ $? = 0 ] || fail=1

# ===================================================================================================
echo "=== (F) MUTATION: the re-derivation comparison can go RED ==="
# ===================================================================================================
python3 - "$TMP/dd_def" <<'PY'
import re, sys
PAGING = re.compile( r'\s(?:shown|capped|total|has_more|next_offset|offset|limit|next|at|est_tokens)="[^"]*"'
                     r'|\sshown_\w+="[^"]*"|\s\w+_capped="[^"]*"|\s\w+_total="[^"]*"' )
body = re.sub( r'\A(?:\s*<!--.*?-->)+', '', open( sys.argv[1], errors="replace" ).read(), flags=re.S )
m = re.search( r'<doc((?:\s+[\w:.-]+="[^"]*")*)\s*/?>', body )
if not m:
    print( "  FAIL  (F) mutation: no <doc> row to mutate" ); sys.exit( 1 )
real = m.group( 1 )
# THE BUG THIS ARM MODELS: the verdict follows the emitted window. Rewrite drift= to the SHOWN row count,
# which is exactly what a `drift = shownCount - dated` emitter would print, and demand the comparison see it.
shown = re.search( r'\sshown_failed="(\d+)"', real )
if not shown:
    print( "  FAIL  (F) mutation: the default <doc> was not cut, so there is no window for a verdict to follow" ); sys.exit( 1 )
mutated = re.sub( r'\sdrift="\d+"', ' drift="%s"' % shown.group( 1 ), real )
if PAGING.sub( '', real ) == PAGING.sub( '', mutated ):
    print( "  FAIL  (F) mutation: a verdict rewritten to the window's row count is INVISIBLE to the (A) comparison" ); sys.exit( 1 )
print( "  PASS  (F) mutation: a drift= that followed the window IS caught by the (A) re-derivation comparison" )
PY
[ $? = 0 ] || fail=1

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
