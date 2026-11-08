#!/usr/bin/env bash
# forsoftbudgetcheck.sh — the --for lens stops when its answer is complete; an explicit --token-budget on the
# answer-shaping lenses is a SOFT TARGET (owner decisions 2026-10-14). Written RED-FIRST, before the code; round 2
# (early gates review R1-R9) added the stop-at-target, continuation, legend-set, guard-bound and twin arms.
#
# WHAT CHANGES, and the contract every arm below pins:
#
#   DEFAULT --for (no budget). The ranked head the lens selected (<sigs total=>: the relevance floor intersected with
#   kForLensDefaultTopN or --pack-top-n) IS the answer. kForPayloadBudgetBytes stops being a ceiling and becomes a
#   stair-step TARGET: the trim ladder's shrink steps (A..E: shorter signatures, doc excerpts) still run against it,
#   but its row-drop step (F) runs only past a RUNAWAY GUARD (kForRunawayGuardBytes, far above a typical answer). So:
#     (D1) a default answer serves every row of its head: shown == total, and total == kForLensDefaultTopN here;
#     (D2) those rows, in rank order, are the rows an uncapped call serves;
#     (D3) rows served past the target are disclosed — <sigs past_target="K"> and a legend clause defining it —
#          and the legend calls budget_bytes= a TARGET on that answer; no over_ceiling= (a target cannot be "over");
#     (D3H) the compact route's <hops> serves its whole row set (decision D-3): shown + noedge == total, not capped;
#     (D4) hitting the runaway guard is the only default-regime row cut: over_ceiling="1" on the root, the <sigs>
#          cut carries next=, the legend names the guard (its value read from that legend), and the block is
#          within the guard yet close to it (a lower bound: the guard is not the old 7.5 KB step in disguise);
#     (D4b) over a --pack-top-n sweep: over_ceiling="1" exactly when the uncut head passes the guard;
#     (D5) the MCP `for` twin serves its whole head too: the CLI default's rows, as a set;
#     (D6) negative: a complete answer under the target carries no past-target / guard disclosure;
#     (NX4) every cut element of a default answer (capped="1", or shown < total beyond noedge=) carries next= (D-4).
#
#   EXPLICIT --token-budget=N / MCP budget_tokens on --for, --pack-task, MCP explore. T = N x kMinBytesPerToken x
#   kBudgetHeadroom (the existing conversion) is charged against the <sigs> ROWS only, never the header or a
#   disclosure. Rows are added in rank order while they fit T; the rank 1..4 floor always ships; there is no byte
#   promise, so nothing is labelled over a ceiling and nothing in the header is dropped to fit:
#     (ST)  stop at target, in the default and --signatures-only modes: the rows' bytes fit T (or are only the
#           floor), and when rows were left out the next row of the complete answer would cross T less the trailing
#           sections' bytes (round C: sections are reserved first, rows fill the rest; fill is maximal);
#     (E1)  no over_ceiling= at a tight target; the floor rows ship; the <sigs> cut carries next=;
#     (E2)  no legend clause is dropped: at every N the legend's clauses include the wide answer's (present-only
#           clauses aside), the root keeps task= and route=, the full dialect keeps its task echo; and a 900-char
#           task at N=300 keeps task= verbatim with no task_echo drop;
#     (E3)  the served rows are a rank PREFIX that grows with N, and a prefix of the default answer's rows;
#     (E4)  the compact and full dialects serve the same rows at every target (rows are charged, not headers);
#     (E5)  stop when complete: a target wider than the answer serves exactly the default answer's rows;
#     (NX1) the cut's next= RUNS and serves the whole head, the cut's rows its prefix (NX2: the guard cut's; NX3:
#           the MCP next_budget_tokens= re-call);
#     (E6)  MCP `for` at a tight budget_tokens: no over_ceiling=, next_budget_tokens= names the continuation;
#     (PT1) --pack-top-n sets the head, the target fills it: a wide target serves exactly --pack-top-n rows;
#     (P1)  --pack-task at a tight target: no over_ceiling=, no "(ceiling)" drop, task= verbatim;
#     (P2)  --pack-task --token-budget=6000 serves the default --pack-task's sections (6000 is the default value);
#     (P3)  MCP explore at a tight budget_tokens: no over_ceiling=.
#
#   UNCHANGED (twins, must hold on base and head): the exit-3 CI-gate personality of --token-budget on the default
#   map (G1), --query (G2) and --recall (G3): over budget -> exit 3, the artifact withheld.
#
# Usage:  bash test/forsoftbudgetcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forsoftbudgetcheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # gitenvhermeticcheck (D): no ambient GIT_* reaches the RP10 fixture repos
unset RIPWIRE_NO_HEAD_RR          # lane hrr: the reorder is ON here unless a twin below sets it (cli_so / mcp_so)
export RIPWIRE_TESTLIB="$ROOT/test/lib"   # softbudget.py: the soft-target readers, shared helpers (CHECKLIST 32)
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
cd "$ROOT"
echo "forsoftbudgetcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUS="src"                                    # short relative root (CHECKLIST 22): header bytes shift with the root path
Q="rank symbols by pagerank"                    # conceptual: a flat 40-row head whose default answer the 7.5 KB ladder cut
QH="parse command line flags"                   # conceptual: the compact route's <hops> was cut by its 1,000 B allowance on base
CF="--cache=$TMP/c_for"; CP="--cache=$TMP/c_pack"; CM="--cache=$TMP/c_map"; CD="--cache=$TMP/c_docs"   # one cache per verb class

# constants, read from source (a binary that predates the guard has none: the arms that need it FAIL, never skip)
srcnum(){ sed -n "s/^inline constexpr [a-z:_ ]*$1 *= *\([0-9.]*\);.*/\1/p" src/serialize.h | head -1; }
GUARD_SRC="$( srcnum kForRunawayGuardBytes )"
TOPN="$( srcnum kForLensDefaultTopN )"
MINBPT="$( srcnum kMinBytesPerToken )"; HEADROOM="$( srcnum kBudgetHeadroom )"
tbytes(){ python3 -c "import sys; print(int(float(sys.argv[1]) * float(sys.argv[2]) * float(sys.argv[3])))" "$1" "$MINBPT" "$HEADROOM"; }

# ── helpers ──────────────────────────────────────────────────────────────────────────────────────────────
cat > "$TMP/rows.py" <<'PY'
# the served <sigs> rows as "p:l:n", in RANK order (r=), one per line; exit 3 when there is no <sigs> block
import re, sys
s = sys.stdin.read()
m = re.search( r'<sigs\b[^>]*>(.*?)</sigs>', s, re.S )
if not m: sys.exit( 3 )
rows = []
for d in re.finditer( r'<d ([^>]*)>', m.group( 1 ) ):
    a = d.group( 1 )
    g = lambda k: ( re.search( r'\b' + k + r'="([^"]*)"', a ) or [ None, "?" ] )[ 1 ]
    r = g( "r" )
    rows.append( ( int( r ) if r.isdigit() else 10**9, g( "p" ) + ":" + g( "l" ) + ":" + g( "n" ) ) )
rows.sort()
print( "\n".join( x[ 1 ] for x in rows ) )
PY
cat > "$TMP/rowbytes.py" <<'PY'
# rowbytes.py FILE: "<rows-bytes> <row-count>" then one line per row "<bytes> p:l:n" in rank order. rows-bytes = the bytes
# inside the <sigs> element (between its open tag and </sigs>): what a soft target is charged against. exit 3: no <sigs>.
import re, sys
s = open( sys.argv[ 1 ] ).read()
m = re.search( r'<sigs\b[^>]*>(.*?)</sigs>', s, re.S )
if not m: sys.exit( 3 )
inner = m.group( 1 )
rows = []
for d in re.finditer( r'<d ([^>]*)>.*?</d>|<d ([^>]*)/>', inner, re.S ):
    a = d.group( 1 ) or d.group( 2 )
    g = lambda k: ( re.search( r'\b' + k + r'="([^"]*)"', a ) or [ None, "?" ] )[ 1 ]
    r = g( "r" )
    rows.append( ( int( r ) if r.isdigit() else 10**9, len( d.group( 0 ).encode() ), g( "p" ) + ":" + g( "l" ) + ":" + g( "n" ) ) )
rows.sort()
print( len( inner.encode() ), len( rows ) )
for r in rows: print( r[ 1 ], r[ 2 ] )
PY
cat > "$TMP/attr.py" <<'PY'
# attr.py ELEMENT NAME: the value of NAME on the first <ELEMENT ...> open tag ("" when absent; exit 3 when no such tag)
import re, sys
el, name = sys.argv[ 1 ], sys.argv[ 2 ]
s = sys.stdin.read()
m = re.search( r'<' + el + r'\b([^>]*)>', s )
if not m: sys.exit( 3 )
v = re.search( r'\b' + name + r'="([^"]*)"', m.group( 1 ) )
print( v.group( 1 ) if v else "" )
PY
cat > "$TMP/prefix.py" <<'PY'
# prefix.py A B: exit 0 when the lines of file A are a prefix of the lines of file B
import sys
a = open( sys.argv[ 1 ] ).read().split( "\n" ); b = open( sys.argv[ 2 ] ).read().split( "\n" )
a = [ x for x in a if x ]; b = [ x for x in b if x ]
sys.exit( 0 if a == b[ :len( a ) ] else 1 )
PY
# head round-robin (lane hrr, train 31; PROCESS rule 4, orchestrator ruling FIX1 §4(a)): the routed no-budget answer reorders
# its first 8 rows (files_first=), so an ORDER-prefix arm below runs UNCHANGED as a RIPWIRE_NO_HEAD_RR=1 twin, and its "h" arm
# asserts what still holds with the reorder ON: the rows are a SET prefix (score ranks 1..K) — the continuation resumes with
# no gap and no repeat (the forrankordercheck (10h) precedent).
cat > "$TMP/legend.py" <<'PY'
# legend.py NARROW WIDE: the legend clauses (header comments before <sigs>, split at brackets / '; ' / '. ', digits
# normalised) of WIDE that NARROW lacks, one per line — present-only clauses (each rides only with its own attribute)
# excluded. Empty output = no clause was dropped. exit 3 when either file has no header comment.
import re, sys
# Present-only = rides only with its own attribute or section on THIS answer (fewer rows can legitimately not carry it): the
# cut/target readings, e= (rows carry it only where endLinesFitCeiling says), sc=, the lego/compose stub (only when a
# section collapsed), the shrunk-not-dropped reading.
PRESENT_ONLY = re.compile( r'dropped_positive|docs_dropped|capped=[#1] with shown|sigs next|next_offset|next_budget|past_target|'
                           r'budget_bytes|BYTE target|over_ceiling|runaway|docs_after_code|relevance floor|this budget left out|'
                           r'e= on a d row|d e= its last line|extent is not known|line of the definition|the name.s line|'
                           r'sc=scope|cut, recoverable|bodies shown|hops shown=#|collapse to a counted stub|'
                           # RE-PIN 2026-11-08 (main red after #572 + #573/#577): the lego COUNT clause (kForLegoCountLegend,
                           # count-floor) is present-only by design — verbs_for.h splices it only when the served <lego>
                           # carries an implementors_ attribute, and the lego is narrowed to the rendered rows' files. Measured:
                           # #572's Symbol::rankFlags pulls model.h rows into this query's wide head, where MEM-REF-SHRINK's
                           # RefColdFields renders implementors="2" implementors_shown="1"; at N<=3000 those rows are past
                           # the cut, the lego narrows away and the clause is rightly absent. Its two segments, below.
                           r'implementors_shown=K only K impl rows|implementors_floor=# an extends clause|'
                           # the <c> row readings ride only with a row that carries them: a spent target's hops cut marker
                           # leaves none (via="name" since forbudget-soft, attrib-multidef's prov="split" since train 28)
                           r'on a <c> row|c prov=split|another arm|NOT mean the edge is false|NOT a claim the edge is false', re.I )
def clauses( path ):
    s = open( path ).read()
    head = s.split( '<sigs', 1 )[ 0 ]
    com = re.findall( r'<!--(.*?)-->', head, re.S )
    if not com: sys.exit( 3 )
    out = set()
    for c in com:
        # " est_tokens= prices…" is spliced after the last clause with a bare space (pre-existing): a clause boundary too.
        # So are the two present-only <c> row readings (FE-B's via="name", attrib-multidef's prov="split"), which open with a
        # bare space after whatever clause precedes them: without the boundary the clause before one reads as missing
        # wherever the one between them (e= on a d row) is absent (train 28: the split reading rides this corpus)
        for seg in re.split( r'\s*(?:\[|\]|;\s|\.\s|\s—\s|\s(?=est_tokens= prices)|\s(?=via="name" on a <c> row)|\s(?=prov="split" on a <c> row))\s*', c ):
            seg = re.sub( r'\d+', '#', re.sub( r'\s+', ' ', seg ) ).strip( ' .:;' )
            if len( seg ) >= 12: out.add( seg )
    return out
n, w = clauses( sys.argv[ 1 ] ), clauses( sys.argv[ 2 ] )
for c in sorted( w - n ):
    if not PRESENT_ONLY.search( c ): print( c )
PY
cat > "$TMP/cuts.py" <<'PY'
# cuts.py: every element of the answer that discloses a CUT — capped="1", or shown < total beyond what noedge= explains —
# and carries no continuation (next= / next_budget_tokens=), one per line. Empty = every cut is recoverable.
import re, sys
s = sys.stdin.read()
for m in re.finditer( r'<([a-z]+)\b([^>]*)>', s ):
    el, a = m.group( 1 ), m.group( 2 )
    g = lambda k: ( re.search( r'\b' + k + r'="([^"]*)"', a ) or [ None, "" ] )[ 1 ]
    num = lambda k: int( g( k ) ) if g( k ).isdigit() else None
    shown, total, noedge = num( "shown" ), num( "total" ), num( "noedge" ) or 0
    cut = g( "capped" ) == "1" or ( shown is not None and total is not None and shown + noedge < total )
    if el in ( "ctx", "files" ) or not cut: continue
    if g( "next" ) or g( "next_budget_tokens" ): continue
    print( el, a.strip()[ :160 ] )
PY
cat > "$TMP/mcptext.py" <<'PY'
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: d = json.loads( line )
    except Exception: continue
    c = d.get( "result", {} ).get( "content" )
    if c: print( c[ 0 ].get( "text", "" ) )
PY
cli_for(){ "$BIN" "$CORPUS" --for="$Q" "$@" "$CF" 2>/dev/null; }
cli_so(){ RIPWIRE_NO_HEAD_RR=1 cli_for "$@"; }   # the rule-4 twin of cli_for: the score-order answer (lane hrr)
mcp_call(){ # mcp_call TOOL TASK EXTRA-JSON
    printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":{"path":"%s","task":"%s"%s}}}\n' \
           "$1" "$CORPUS" "$2" "${3:-}" | "$BIN" --mcp 2>/dev/null | python3 "$TMP/mcptext.py"; }
mcp_so(){ RIPWIRE_NO_HEAD_RR=1 mcp_call "$@"; }   # the rule-4 twin of mcp_call (lane hrr)
attr(){ python3 "$TMP/attr.py" "$1" "$2" < "$3"; }
setp(){ python3 "$RIPWIRE_TESTLIB/softbudget.py" setprefix "$1" "$2" "$3"; }   # setp A ON OFF: A is a SET prefix (score ranks 1..K); ON == OFF as sets
rows(){ python3 "$TMP/rows.py" < "$1" > "$2"; }
isnum(){ case "${1:-}" in ''|*[!0-9]*) return 1;; esac; return 0; }
lines(){ local c; c="$( grep -c . "$1" 2>/dev/null )"; echo "${c:-0}"; }
# run a pasteable next= (XML-escaped argv fragment) against the same corpus; stdout to $2
run_next(){
    python3 - "$1" > "$TMP/next.argv" <<'PY' || return 1
import sys, shlex, html
print( "\0".join( shlex.split( html.unescape( sys.argv[ 1 ] ) ) ), end="" )
PY
    local -a a=()
    while IFS= read -r -d '' x; do a+=( "$x" ); done < <( cat "$TMP/next.argv"; printf '\0' )
    [ "${#a[@]}" -gt 0 ] || return 1
    "$BIN" "$CORPUS" "${a[@]}" "$CF" > "$2" 2>/dev/null
}
run_next_so(){ RIPWIRE_NO_HEAD_RR=1 run_next "$@"; }

if ! isnum "$TOPN" || [ -z "$MINBPT" ] || [ -z "$HEADROOM" ]; then
    no "premise: kForLensDefaultTopN / kMinBytesPerToken / kBudgetHeadroom not found in src/serialize.h"
    echo "FAILURES ABOVE"; exit 1
fi

# ── the default answer (premise for D1..D3, ST, E3, E5) ──────────────────────────────────────────────────
cli_for > "$TMP/def.xml"; rc=$?
if [ "$rc" -ne 0 ] || ! rows "$TMP/def.xml" "$TMP/def.rows"; then
    no "premise: default --for on $CORPUS did not run (rc=$rc) or served no <sigs> — every arm below would measure nothing"
    echo "FAILURES ABOVE"; exit 1
fi
# lane hrr (rule 4): the score-order twin of the default answer, the reference of every order-prefix twin below
cli_so > "$TMP/def_so.xml"
if ! rows "$TMP/def_so.xml" "$TMP/def_so.rows"; then no "premise: the RIPWIRE_NO_HEAD_RR=1 default served no <sigs> — the twins below measure nothing"; fi
DS="$( attr sigs shown "$TMP/def.xml" )"; DT="$( attr sigs total "$TMP/def.xml" )"
DN="$( lines "$TMP/def.rows" )"
# R5: the head size is pinned to the lens's own cap — a change that shrinks the head cannot pass D1 by shrinking total=
if isnum "$DT" && [ "$DT" -eq "$TOPN" ]; then
    ok "premise: the default head is kForLensDefaultTopN wide: total=$DT"
else
    no "premise: the default head total='$DT' != kForLensDefaultTopN=$TOPN — the head was narrowed, so 'complete' is relative to a smaller answer"
fi

# (D1) the whole head ships
if isnum "$DT" && [ "$DN" -eq "$DT" ] && { [ -z "$DS" ] || [ "$DS" = "$DT" ]; }; then
    ok "(D1) default answer serves its whole head: $DN rows of total=$DT"
else
    no "(D1) default answer served $DN rows (shown='$DS') of total='$DT' — rows of the ranked head were dropped below the runaway guard"
fi

# (D2) the default rows ARE the uncapped rows, in rank order — rule-4 twin (lane hrr): unchanged, under RIPWIRE_NO_HEAD_RR=1
cli_so --signatures-only --token-budget=1000000 > "$TMP/unc_so.xml"
if rows "$TMP/unc_so.xml" "$TMP/unc_so.rows" && cmp -s "$TMP/def_so.rows" "$TMP/unc_so.rows"; then
    ok "(D2) [RIPWIRE_NO_HEAD_RR=1 twin] default rows == uncapped rows ($( lines "$TMP/unc_so.rows" ) rows, rank order)"
else
    no "(D2) [RIPWIRE_NO_HEAD_RR=1 twin] default rows ($( lines "$TMP/def_so.rows" )) differ from the uncapped call's rows ($( lines "$TMP/unc_so.rows" ))"
fi
# (D2h) reorder ON: the default serves the uncapped call's rows as a set (the reorder adds and drops none)
cli_for --signatures-only --token-budget=1000000 > "$TMP/unc.xml"
if rows "$TMP/unc.xml" "$TMP/unc.rows" && [ "$( lines "$TMP/unc.rows" )" -eq "$DN" ] && setp "$TMP/def.rows" "$TMP/unc.rows" "$TMP/def_so.rows"; then
    ok "(D2h) head round-robin on: default rows == uncapped rows as a set ($DN rows)"
else
    no "(D2h) head round-robin on: default rows ($DN) are not the uncapped call's rows ($( lines "$TMP/unc.rows" )) as a set"
fi

# (D3) past-target disclosure on that answer
PT="$( attr sigs past_target "$TMP/def.xml" )"; OC="$( attr ctx over_ceiling "$TMP/def.xml" )"
sed 's/<sigs.*//' "$TMP/def.xml" > "$TMP/def.head"
if isnum "$PT" && [ "$PT" -gt 0 ] && [ "$PT" -le $(( DN - 4 )) ]; then
    ok "(D3) <sigs past_target=\"$PT\"> names the rows served past the default target (<= shown-4: the floor is never past it)"
else
    no "(D3) <sigs> carries no past_target=K with 0 < K <= shown-4 (got '$PT', shown=$DN) although the answer passes the 7.5 KB target"
fi
if grep -q 'past_target=' "$TMP/def.head"; then ok "(D3) the header legend defines past_target="
else no "(D3) no legend clause defines past_target= ahead of <sigs>"; fi
if grep -q 'default BYTE ceiling this ranked payload' "$TMP/def.head"; then
    no "(D3) the legend still calls budget_bytes= a ceiling on an answer that passed it by design"
elif grep -q 'budget_bytes= is the default BYTE target' "$TMP/def.head"; then
    ok "(D3) the legend calls budget_bytes= a TARGET on a past-target answer"
else
    no "(D3) the legend neither calls budget_bytes= a target nor a ceiling — its clause is missing on an answer that carries budget_bytes="
fi
if [ -z "$OC" ]; then ok "(D3) no over_ceiling= on a default answer under the guard"
else no "(D3) over_ceiling='$OC' on a default answer that is under the runaway guard (a target cannot be 'over')"; fi

# (NX4) every cut element of the default answer carries a continuation (rule 5; D-4: the <tail>)
python3 "$TMP/cuts.py" < "$TMP/def.xml" > "$TMP/def.cuts"
if [ "$( lines "$TMP/def.cuts" )" -eq 0 ]; then ok "(NX4) every cut element of the default answer carries next="
else no "(NX4) cut elements without a continuation: $( tr '\n' '|' < "$TMP/def.cuts" | cut -c1-300 )"; fi

# (D3H) D-3: the compact route's <hops> serves its whole row set on the default answer
"$BIN" "$CORPUS" --for="$QH" "$CF" > "$TMP/hops.xml" 2>/dev/null; hrc=$?
HS="$( attr hops shown "$TMP/hops.xml" )"; HT="$( attr hops total "$TMP/hops.xml" )"; HE="$( attr hops noedge "$TMP/hops.xml" )"; HC="$( attr hops capped "$TMP/hops.xml" )"
HE="${HE:-0}"
if [ "$hrc" -ne 0 ] || ! isnum "$HS" || ! isnum "$HT"; then
    no "(D3H) premise: --for='$QH' did not run (rc=$hrc) or served no <hops shown= total=> (route changed?)"
elif [ $(( HS + HE )) -eq "$HT" ] && [ "$HC" != "1" ]; then
    ok "(D3H) <hops> complete: shown=$HS + noedge=$HE == total=$HT, not capped"
else
    no "(D3H) <hops> cut: shown=$HS noedge=$HE total=$HT capped='$HC' — the default answer must serve every hop row"
fi
python3 "$TMP/cuts.py" < "$TMP/hops.xml" > "$TMP/hops.cuts"
if [ "$hrc" -eq 0 ] && [ "$( lines "$TMP/hops.cuts" )" -eq 0 ]; then ok "(NX4) every cut element of the '$QH' answer carries next="
else no "(NX4) '$QH': cut elements without a continuation: $( tr '\n' '|' < "$TMP/hops.cuts" | cut -c1-300 )"; fi

# (D4) the runaway guard: a 400-row head runs into it
cli_for --pack-top-n=400 > "$TMP/guard.xml"
GOC="$( attr ctx over_ceiling "$TMP/guard.xml" )"; GNX="$( attr sigs next "$TMP/guard.xml" )"; GCAP="$( attr sigs capped "$TMP/guard.xml" )"
GS="$( attr sigs shown "$TMP/guard.xml" )"; GT="$( attr sigs total "$TMP/guard.xml" )"
if [ "$GOC" = "1" ] && [ "$GCAP" = "1" ] && [ -n "$GNX" ]; then
    ok "(D4) --pack-top-n=400: the guard cut is disclosed (over_ceiling=1, <sigs capped=1 next=…>)"
else
    no "(D4) --pack-top-n=400: expected over_ceiling=1 + <sigs capped=1 next=…>; got over_ceiling='$GOC' capped='$GCAP' next='${GNX:0:40}'"
fi
sed 's/<sigs.*//' "$TMP/guard.xml" > "$TMP/guard.head"
# S3: the guard's value is read from the legend of the answer that hit it, and must agree with the source's one owner
GUARD="$( sed -n 's/.*runaway guard of \([0-9][0-9]*\) B.*/\1/p' "$TMP/guard.head" | head -1 )"
if isnum "$GUARD" && [ "$GUARD" = "$GUARD_SRC" ]; then ok "(D4) the legend names the runaway guard ($GUARD B, == kForRunawayGuardBytes)"
else no "(D4) the legend names no runaway guard value ('$GUARD') or it differs from src/serialize.h kForRunawayGuardBytes ('$GUARD_SRC')"; fi
SIGB="$( python3 -c 'import re,sys; m=re.search(r"<sigs\b.*?</sigs>", sys.stdin.read(), re.S); print(len(m.group(0).encode()) if m else "")' < "$TMP/guard.xml" )"
if ! isnum "$GUARD"; then
    no "(D4) no guard value to bound the <sigs> block against"
elif ! isnum "$SIGB"; then
    no "(D4) no <sigs> block on the guard answer"
elif [ "$SIGB" -le "$GUARD" ] && [ "$SIGB" -gt $(( GUARD - 6000 )) ]; then
    ok "(D4) <sigs> block $SIGB B within the guard $GUARD B and close to it (> guard - 6000: header + one row)"
else
    no "(D4) <sigs> block $SIGB B is not in (guard-6000, guard] = ($(( GUARD - 6000 )), $GUARD] — the cut is not at the guard"
fi
# (NX2) the guard cut's next= runs and serves the whole 400-candidate head, the cut's rows its prefix — rule-4 twin (lane
# hrr): this arm unchanged under RIPWIRE_NO_HEAD_RR=1; (NX2h) below asserts the set prefix with the reorder on
cli_so --pack-top-n=400 > "$TMP/guard_so.xml"
GNXS="$( attr sigs next "$TMP/guard_so.xml" )"; GTS="$( attr sigs total "$TMP/guard_so.xml" )"
rows "$TMP/guard_so.xml" "$TMP/guard_so.rows"
if [ -n "$GNXS" ] && run_next_so "$GNXS" "$TMP/guard_next_so.xml" && rows "$TMP/guard_next_so.xml" "$TMP/guard_next_so.rows"; then
    GXNS="$( lines "$TMP/guard_next_so.rows" )"
    if isnum "$GTS" && [ "$GXNS" -eq "$GTS" ] && python3 "$TMP/prefix.py" "$TMP/guard_so.rows" "$TMP/guard_next_so.rows"; then
        ok "(NX2) [RIPWIRE_NO_HEAD_RR=1 twin] the guard cut's next= serves all $GXNS rows of total=$GTS; the cut's $( lines "$TMP/guard_so.rows" ) rows are its prefix"
    else
        no "(NX2) [RIPWIRE_NO_HEAD_RR=1 twin] the guard cut's next= served $GXNS rows (total=$GTS) or the cut's rows are not its prefix"
    fi
else
    no "(NX2) [RIPWIRE_NO_HEAD_RR=1 twin] the guard cut's next= ('${GNXS:0:60}') is absent or did not run"
fi
rows "$TMP/guard.xml" "$TMP/guard.rows"
if [ -n "$GNX" ] && run_next "$GNX" "$TMP/guard_next.xml" && rows "$TMP/guard_next.xml" "$TMP/guard_next.rows"; then
    GXN="$( lines "$TMP/guard_next.rows" )"
    if isnum "$GT" && [ "$GXN" -eq "$GT" ] && [ -s "$TMP/guard_next_so.rows" ] && setp "$TMP/guard.rows" "$TMP/guard_next.rows" "$TMP/guard_next_so.rows"; then
        ok "(NX2h) head round-robin on: the guard cut's next= serves all $GXN rows of total=$GT; the cut's $( lines "$TMP/guard.rows" ) rows are its SET prefix"
    else
        no "(NX2h) head round-robin on: the guard cut's next= served $GXN rows (total=$GT) or the cut's rows are not its set prefix (score ranks 1..K)"
    fi
else
    no "(NX2h) the guard cut's next= ('${GNX:0:60}') is absent or did not run"
fi

# (D4b) the guard biconditional over a --pack-top-n sweep: over_ceiling="1" <=> the uncut head passes the guard
for n in 40 100 200 400; do
    cli_for --pack-top-n="$n" > "$TMP/pt_$n.xml"
    cli_for --pack-top-n="$n" --signatures-only --token-budget=1000000 > "$TMP/pt_${n}_unc.xml"
    o="$( attr ctx over_ceiling "$TMP/pt_$n.xml" )"; s="$( attr sigs shown "$TMP/pt_$n.xml" )"; t="$( attr sigs total "$TMP/pt_$n.xml" )"
    rows "$TMP/pt_$n.xml" "$TMP/pt_$n.rows"; sn="$( lines "$TMP/pt_$n.rows" )"
    # the uncut quantity the guard measures: this answer's bytes up to <sigs> + the uncut block
    q="$( python3 - "$TMP/pt_$n.xml" "$TMP/pt_${n}_unc.xml" <<'PY'
import re, sys
a = open( sys.argv[ 1 ] ).read(); u = open( sys.argv[ 2 ] ).read()
m = re.search( r'<sigs\b.*?</sigs>', u, re.S )
print( len( a.split( '<sigs', 1 )[ 0 ].encode() ) + len( m.group( 0 ).encode() ) if m and '<sigs' in a else "" )
PY
)"
    if ! isnum "$q" || ! isnum "$GUARD"; then no "(D4b) --pack-top-n=$n: no guard value or no measurable uncut head"; continue; fi
    if [ "$q" -gt "$GUARD" ]; then
        if [ "$o" = "1" ] && isnum "$t" && [ "$sn" -lt "$t" ]; then ok "(D4b) n=$n: uncut head $q B > guard -> over_ceiling=1, $sn of $t rows"
        else no "(D4b) n=$n: uncut head $q B > guard $GUARD but over_ceiling='$o' rows=$sn total='$t'"; fi
    else
        if [ -z "$o" ] && isnum "$t" && [ "$sn" -eq "$t" ]; then ok "(D4b) n=$n: uncut head $q B <= guard -> complete ($sn of $t), no over_ceiling"
        else no "(D4b) n=$n: uncut head $q B <= guard $GUARD but over_ceiling='$o' rows=$sn total='$t'"; fi
    fi
done

# (D5) the MCP twin serves its whole head: the CLI default's rows (as a set; the dialects order nothing differently, but
#      the set is the contract mcpforparitycheck already pins)
mcp_call for "$Q" "" > "$TMP/mcp_def.xml"
MS="$( attr sigs shown "$TMP/mcp_def.xml" )"; MT="$( attr sigs total "$TMP/mcp_def.xml" )"
rows "$TMP/mcp_def.xml" "$TMP/mcp_def.rows"; MN="$( lines "$TMP/mcp_def.rows" )"
if isnum "$MT" && [ "$MT" = "$DT" ] && [ "$MN" = "$MT" ] && { [ -z "$MS" ] || [ "$MS" = "$MN" ]; } \
   && cmp -s <( sort "$TMP/mcp_def.rows" ) <( sort "$TMP/def.rows" ); then
    ok "(D5) MCP for serves its whole head: $MN rows == the CLI default's rows (total=$MT)"
else
    no "(D5) MCP for served $MN rows (shown='$MS') of total='$MT'; CLI default $DN of $DT — must be the same whole head"
fi

# (D6) negative: an answer that is complete under the target carries no past-target or guard disclosure
#      (a name-exact query: one anchor row set, well under 7.5 KB; on such answers the change is byte-identical)
"$BIN" "$CORPUS" --for="trimSigLadder" --signatures-only "$CF" > "$TMP/narrow.xml" 2>/dev/null; nrc=$?
NPT="$( attr sigs past_target "$TMP/narrow.xml" )"; NOC="$( attr ctx over_ceiling "$TMP/narrow.xml" )"
NB="$( wc -c < "$TMP/narrow.xml" | tr -d ' ' )"
if [ "$nrc" -ne 0 ] || ! isnum "$NB" || [ "$NB" -eq 0 ]; then no "(D6) the narrow name-exact answer did not run"
elif [ "$NB" -ge 7500 ]; then no "(D6) premise: the narrow answer ($NB B) is not under the 7.5 KB target — pick a narrower query"
elif [ -z "$NPT" ] && [ -z "$NOC" ] && ! grep -qi 'runaway\|past_target' "$TMP/narrow.xml"; then ok "(D6) a $NB B complete answer carries no past_target=/over_ceiling=/guard clause"
else no "(D6) a $NB B complete answer carries past_target='$NPT' over_ceiling='$NOC' or a guard/past-target clause"; fi

# ── explicit targets ─────────────────────────────────────────────────────────────────────────────────────
cli_for --token-budget=20000 > "$TMP/wide.xml"                                      # the default dialect (compact)
cli_for --token-budget=20000 --legend=full > "$TMP/wide_full.xml"
cli_for --token-budget=20000 --legend=compact > "$TMP/wide_compact.xml"
rows "$TMP/wide.xml" "$TMP/wide.rows"
"$BIN" "$CORPUS" --for="$Q" --signatures-only "$CF" > "$TMP/so_def.xml" 2>/dev/null
SWEEP=( 300 1000 2000 3000 6000 )
prev=""
for n in "${SWEEP[@]}"; do
    T="$( tbytes "$n" )"
    for lg in full compact; do
        cli_for --token-budget="$n" --legend="$lg" > "$TMP/t_${n}_$lg.xml"; trc=$?
        if [ "$trc" -ne 0 ] || ! rows "$TMP/t_${n}_$lg.xml" "$TMP/t_${n}_$lg.rows"; then
            no "(E) N=$n $lg: the call failed (rc=$trc) or served no <sigs> block — no arm below can read it"
            : > "$TMP/t_${n}_$lg.rows"; continue
        fi
        # (E2) the header is never shaped: no "(ceiling)" drop, and the wide answer's clauses all ride (S4: read only
        #      off a call that ran and produced its rows, above)
        wf="$TMP/wide_$lg.xml"
        python3 "$TMP/legend.py" "$TMP/t_${n}_$lg.xml" "$wf" > "$TMP/t_${n}_$lg.lost"; lrc=$?
        if grep -q 'dropped (ceiling)' "$TMP/t_${n}_$lg.xml"; then
            no "(E2) N=$n $lg: legend clauses dropped '(ceiling)' — the header must not be shaped by a soft target"
        elif [ "$lrc" -ne 0 ]; then
            no "(E2) N=$n $lg: no header comment to compare"
        elif [ "$( lines "$TMP/t_${n}_$lg.lost" )" -gt 0 ]; then
            no "(E2) N=$n $lg: clauses of the wide answer missing: $( head -3 "$TMP/t_${n}_$lg.lost" | tr '\n' '|' | cut -c1-240 )"
        else
            ok "(E2) N=$n $lg: every clause of the wide answer rides (no clause dropped)"
        fi
        if [ "$( attr ctx task "$TMP/t_${n}_$lg.xml" )" = "$Q" ] && [ -n "$( attr ctx route "$TMP/t_${n}_$lg.xml" )" ]; then
            ok "(E2) N=$n $lg: the root keeps task= verbatim and route="
        else
            no "(E2) N=$n $lg: the root lost task= or route= at this target"
        fi
    done
    f="$TMP/t_${n}_full.xml"
    if [ -s "$TMP/t_${n}_full.rows" ] && grep -qF "lens for \"$Q\"" "$f"; then ok "(E2) N=$n full: the legend echoes the task"
    else no "(E2) N=$n full: the task echo is gone from the legend (or the call failed)"; fi
    TOC="$( attr ctx over_ceiling "$f" )"; TN="$( lines "$TMP/t_${n}_full.rows" )"
    # (E1) at the tight end of the sweep
    if [ "$n" -le 1000 ]; then
        TNX="$( attr sigs next "$f" )"
        if [ -z "$TOC" ] && [ "$TN" -ge 4 ] && [ -n "$TNX" ]; then
            ok "(E1) N=$n: no over_ceiling=, $TN floor rows, the cut carries next="
        else
            no "(E1) N=$n: over_ceiling='$TOC', rows=$TN (floor 4), sigs next='${TNX:0:40}' — a soft target is never 'over' and always names its continuation"
        fi
    fi
    # (E3) rank prefix: of the default rows, and of the next wider target. Rule-4 twin (lane hrr): the default-prefix arm runs
    #      unchanged under RIPWIRE_NO_HEAD_RR=1; (E3h) asserts the set prefix with the reorder on
    cli_so --token-budget="$n" --legend=full > "$TMP/t_${n}_so.xml"; rows "$TMP/t_${n}_so.xml" "$TMP/t_${n}_so.rows" || : > "$TMP/t_${n}_so.rows"
    if [ -s "$TMP/t_${n}_so.rows" ] && python3 "$TMP/prefix.py" "$TMP/t_${n}_so.rows" "$TMP/def_so.rows"; then ok "(E3) [RIPWIRE_NO_HEAD_RR=1 twin] N=$n: rows ($( lines "$TMP/t_${n}_so.rows" )) are a rank prefix of the default rows"
    else no "(E3) [RIPWIRE_NO_HEAD_RR=1 twin] N=$n: rows ($( lines "$TMP/t_${n}_so.rows" )) are not a rank prefix of the default rows ($( lines "$TMP/def_so.rows" ))"; fi
    if setp "$TMP/t_${n}_full.rows" "$TMP/def.rows" "$TMP/def_so.rows"; then ok "(E3h) head round-robin on, N=$n: rows ($TN) are a SET prefix of the default rows (score ranks 1..$TN)"
    else no "(E3h) head round-robin on, N=$n: rows ($TN) are not a set prefix of the default rows ($DN) — the continuation would gap or repeat"; fi
    if [ -n "$prev" ]; then
        if python3 "$TMP/prefix.py" "$TMP/t_${prev}_full.rows" "$TMP/t_${n}_full.rows"; then ok "(E3) rows(N=$prev) is a prefix of rows(N=$n)"
        else no "(E3) rows(N=$prev) is not a prefix of rows(N=$n) — not monotone"; fi
    fi
    # (E4) dialects agree on rows
    if cmp -s "$TMP/t_${n}_full.rows" "$TMP/t_${n}_compact.rows"; then ok "(E4) N=$n: compact rows == full rows ($TN)"
    else no "(E4) N=$n: compact rows ($( lines "$TMP/t_${n}_compact.rows" )) != full rows ($TN)"; fi
    # (ST) stop at target, default and --signatures-only modes: rows fit T (or are the floor); a cut is maximal
    "$BIN" "$CORPUS" --for="$Q" --signatures-only --token-budget="$n" "$CF" > "$TMP/so_$n.xml" 2>/dev/null
    for mode in def so; do
        if [ "$mode" = def ]; then a="$f"; ref="$TMP/def.xml"; else a="$TMP/so_$n.xml"; ref="$TMP/so_def.xml"; fi
        st="$( python3 - "$a" "$ref" "$T" <<'PY'
import subprocess, sys, re
# a row's CHARGE is the ladder's (serialize.h entryCost): its printed bytes plus the zero cx=/ccx=/in= the lean spelling elides
# (SigEntry::elidedBytes — charged so the kept rows are the ones kept before the elision)
def charge( a, printed ):
    return printed + sum( n for k, n in ( ( 'cx', 7 ), ( 'ccx', 8 ), ( 'in', 7 ) ) if not re.search( r'\b' + k + r'="', a ) )
def rb( p ):
    s = open( p ).read()
    m = re.search( r'<sigs\b[^>]*>(.*?)</sigs>', s, re.S )
    if not m: return None
    inner = m.group( 1 ); rows = []; elided = 0
    for d in re.finditer( r'<d ([^>]*)>.*?</d>|<d ([^>]*)/>', inner, re.S ):
        a = d.group( 1 ) or d.group( 2 )
        r = re.search( r'\br="(\d+)"', a )
        printed = len( d.group( 0 ).encode() ); c = charge( a, printed ); elided += c - printed
        rows.append( ( int( r.group( 1 ) ) if r else 10**9, c ) )
    rows.sort()
    return len( inner.encode() ) + elided, rows
a, ref, T = rb( sys.argv[ 1 ] ), rb( sys.argv[ 2 ] ), int( sys.argv[ 3 ] )
# round C (owner decision 2026-10-14: RESERVE SECTIONS FIRST): the trailing sections (and the <hdr> rows) are served first
# and the rows past the target cut fill what they leave of T — the maximality bound is T less the bytes of those sections (U, read
# off the answer: everything after </sigs> but </ctx>, plus the <hdr> rows before it)
import os as _os0, sys as _sys0; _sys0.path.insert( 0, _os0.environ[ "RIPWIRE_TESTLIB" ] ); from softbudget import strip_appended
ans = strip_appended( open( sys.argv[ 1 ] ).read() )   # K-LEGEND: the <syms> block / held stub is not reserved from T
U = ( len( ans.split( '</sigs>', 1 )[ 1 ].encode() ) - len( '</ctx>' ) if '</sigs>' in ans else 0 )
U += sum( len( h.encode() ) for h in re.findall( r'<hdr [^>]*/>', ans.split( '<sigs', 1 )[ 0 ] ) )
# the tail size: test/lib/softbudget.py, shared by the five soft-target readers (the FIX1 R1 tail floor)
import os as _os, sys as _sys; _sys.path.insert( 0, _os.environ[ "RIPWIRE_TESTLIB" ] ); from softbudget import tail_size
U += max( 0, tail_size( open( sys.argv[ 2 ] ).read() ) - tail_size( ans ) )
if a is None or ref is None: print( "ERR no <sigs>" ); sys.exit( 0 )
ab, ar = a; rr = ref[ 1 ]
k = len( ar )
fits = ab <= T or k <= 4
if k >= len( rr ): print( "OK fits=%d rows=%d/%d charged=%d T=%d complete" % ( fits, k, len( rr ), ab, T ) ); sys.exit( 0 )
nxt = rr[ k ][ 1 ]
maximal = ab + nxt > T - U - 160
# FIX2 C1 (rule 4): the upper-bound twin of maximality (test/lib/softbudget.py upper_bound): rows past the floor stop where T less
# the other sections and the tail reserve runs out; RED on a binary that ignores the tail reserve
from softbudget import upper_bound
upper, udet = upper_bound( ans, open( sys.argv[ 2 ] ).read(), T, k, len( rr ), U )
print( "%s fits=%d maximal=%d upper=%d rows=%d/%d charged=%d next=%d T=%d U=%d%s" % ( "OK" if fits and maximal and upper else "BAD", fits, maximal, upper,
       k, len( rr ), ab, nxt, T, U, "" if upper else " -- " + udet ) )
PY
)"
        case "$st" in
            OK*)  ok "(ST) N=$n $mode: $st" ;;
            *)    no "(ST) N=$n $mode: $st — the rows must fit the target and stop only where the next row would cross it, never past T less the sections and the tail reserve" ;;
        esac
    done
    prev="$n"
done

# (E2b) a 900-char task at a tight target: the task stays verbatim and its echo is never dropped
Q900="$Q $( printf 'with the symbol graph and the teleport vector over the whole index %.0s' $( seq 1 14 ) )"
Q900="${Q900:0:900}"; Q900="${Q900% }"
"$BIN" "$CORPUS" --for="$Q900" --token-budget=300 --legend=full "$CF" > "$TMP/q900.xml" 2>/dev/null; qrc=$?   # the full dialect echoes the task
if [ "$qrc" -ne 0 ]; then no "(E2b) the 900-char task call failed (rc=$qrc)"
elif [ "$( attr ctx task "$TMP/q900.xml" )" = "$Q900" ] && ! grep -q 'task_echo' "$TMP/q900.xml" && grep -qF "lens for \"$Q900\"" "$TMP/q900.xml"; then
    ok "(E2b) a ${#Q900}-char task at N=300: task= verbatim, the echo kept, no task_echo drop"
else
    no "(E2b) a ${#Q900}-char task at N=300: task= changed, or the legend echo dropped ('task_echo' in the answer: $( grep -c task_echo "$TMP/q900.xml" ))"
fi
# …and --pack-task, whose ladder took the echo rung at 2000 on base (the rung w3fixbudgetcheck (7) pinned as reachable)
"$BIN" "$CORPUS" --pack-task="$Q900" --token-budget=2000 --legend=full "$CP" > "$TMP/q900p.xml" 2>/dev/null; qrc=$?
if [ "$qrc" -ne 0 ]; then no "(E2b) the 900-char --pack-task call failed (rc=$qrc)"
elif [ "$( attr ctx task "$TMP/q900p.xml" )" = "$Q900" ] && ! grep -q 'task_echo' "$TMP/q900p.xml"; then
    ok "(E2b) a ${#Q900}-char --pack-task at N=2000: task= verbatim, no task_echo drop"
else
    no "(E2b) a ${#Q900}-char --pack-task at N=2000: task= changed or the echo was dropped (a soft target never sheds the header)"
fi

# (NX1) the tight cut's next= runs and serves the whole head; the cut's rows are its prefix — rule-4 twin (lane hrr): unchanged
# under RIPWIRE_NO_HEAD_RR=1; (NX1h) asserts the set prefix with the reorder on
NXS="$( attr sigs next "$TMP/t_300_so.xml" )"
if [ -n "$NXS" ] && run_next_so "$NXS" "$TMP/nx_so.xml" && rows "$TMP/nx_so.xml" "$TMP/nx_so.rows"; then
    if cmp -s "$TMP/nx_so.rows" "$TMP/def_so.rows" && python3 "$TMP/prefix.py" "$TMP/t_300_so.rows" "$TMP/nx_so.rows"; then
        ok "(NX1) [RIPWIRE_NO_HEAD_RR=1 twin] N=300's next= serves the whole head ($( lines "$TMP/nx_so.rows" ) rows == the default's); the cut is its prefix"
    else
        no "(NX1) [RIPWIRE_NO_HEAD_RR=1 twin] N=300's next= served $( lines "$TMP/nx_so.rows" ) rows, not the default's in order (or the cut is not its prefix)"
    fi
else
    no "(NX1) [RIPWIRE_NO_HEAD_RR=1 twin] N=300's sigs next= ('${NXS:0:60}') is absent or did not run"
fi
NX="$( attr sigs next "$TMP/t_300_full.xml" )"
if [ -n "$NX" ] && run_next "$NX" "$TMP/nx.xml" && rows "$TMP/nx.xml" "$TMP/nx.rows"; then
    if [ "$( lines "$TMP/nx.rows" )" -eq "$DN" ] && setp "$TMP/nx.rows" "$TMP/def.rows" "$TMP/def_so.rows" && setp "$TMP/t_300_full.rows" "$TMP/nx.rows" "$TMP/def_so.rows"; then
        ok "(NX1h) head round-robin on: N=300's next= serves the whole head as a set ($DN rows); the cut is its SET prefix"
    else
        no "(NX1h) head round-robin on: N=300's next= served $( lines "$TMP/nx.rows" ) rows, not the default's $DN as a set (or the cut is not its set prefix)"
    fi
else
    no "(NX1h) N=300's sigs next= ('${NX:0:60}') is absent or did not run"
fi

# (E5) stop when complete: a wide target serves exactly the default answer's rows — rule-4 twin (lane hrr): unchanged under
# RIPWIRE_NO_HEAD_RR=1; (E5h) asserts the same rows as a set with the reorder on
cli_so --token-budget=20000 > "$TMP/wide_so.xml"; rows "$TMP/wide_so.xml" "$TMP/wide_so.rows"
if cmp -s "$TMP/wide_so.rows" "$TMP/def_so.rows" && [ "$( lines "$TMP/def_so.rows" )" = "$DT" ]; then
    ok "(E5) [RIPWIRE_NO_HEAD_RR=1 twin] --token-budget=20000 serves exactly the default (complete) rows: $DT"
else
    no "(E5) [RIPWIRE_NO_HEAD_RR=1 twin] --token-budget=20000 served $( lines "$TMP/wide_so.rows" ) rows; the default served $( lines "$TMP/def_so.rows" ) of total=$DT — a target wider than the answer must serve the complete head"
fi
if [ "$( lines "$TMP/wide.rows" )" = "$DN" ] && [ "$DN" = "$DT" ] && setp "$TMP/wide.rows" "$TMP/def.rows" "$TMP/def_so.rows"; then
    ok "(E5h) head round-robin on: --token-budget=20000 serves the default (complete) rows as a set: $DN"
else
    no "(E5h) head round-robin on: --token-budget=20000 served $( lines "$TMP/wide.rows" ) rows; the default served $DN of total=$DT — not the complete head as a set"
fi

# (PT1) --pack-top-n sets the head; the target fills it (rule-4 table #4). An uncut block prints no total= (its rows are it).
cli_for --pack-top-n=10 --token-budget=20000 > "$TMP/ptn10.xml"; rows "$TMP/ptn10.xml" "$TMP/ptn10.rows"
P10T="$( attr sigs total "$TMP/ptn10.xml" )"
# rule-4 twin (lane hrr): this arm unchanged under RIPWIRE_NO_HEAD_RR=1; (PT1h) the set prefix with the reorder on
cli_so --pack-top-n=10 --token-budget=20000 > "$TMP/ptn10_so.xml"; rows "$TMP/ptn10_so.xml" "$TMP/ptn10_so.rows"
P10TS="$( attr sigs total "$TMP/ptn10_so.xml" )"
if { [ "$P10TS" = "10" ] || [ -z "$P10TS" ]; } && [ "$( lines "$TMP/ptn10_so.rows" )" -eq 10 ] && python3 "$TMP/prefix.py" "$TMP/ptn10_so.rows" "$TMP/def_so.rows"; then
    ok "(PT1) [RIPWIRE_NO_HEAD_RR=1 twin] --pack-top-n=10 --token-budget=20000: exactly the 10-row head, a prefix of the default rows"
else
    no "(PT1) [RIPWIRE_NO_HEAD_RR=1 twin] --pack-top-n=10 --token-budget=20000: total='$P10TS' rows=$( lines "$TMP/ptn10_so.rows" ) — a wide target must serve exactly the --pack-top-n head"
fi
if { [ "$P10T" = "10" ] || [ -z "$P10T" ]; } && [ "$( lines "$TMP/ptn10.rows" )" -eq 10 ] && setp "$TMP/ptn10.rows" "$TMP/def.rows" "$TMP/def_so.rows"; then
    ok "(PT1h) head round-robin on: --pack-top-n=10 --token-budget=20000: exactly the 10-row head, a SET prefix of the default rows"
else
    no "(PT1h) head round-robin on: --pack-top-n=10 --token-budget=20000: total='$P10T' rows=$( lines "$TMP/ptn10.rows" ) — want the 10-row head, a set prefix of the default rows"
fi

# (E6) MCP for at a tight budget_tokens; (NX3) its continuation re-call serves the whole head
mcp_call for "$Q" ',"budget_tokens":300' > "$TMP/mcp_300.xml"
M3OC="$( attr ctx over_ceiling "$TMP/mcp_300.xml" )"; M3NB="$( attr sigs next_budget_tokens "$TMP/mcp_300.xml" )"
if [ -z "$M3OC" ] && isnum "$M3NB"; then ok "(E6) MCP for budget_tokens=300: no over_ceiling=, next_budget_tokens=$M3NB"
else no "(E6) MCP for budget_tokens=300: over_ceiling='$M3OC' next_budget_tokens='$M3NB'"; fi
rows "$TMP/mcp_300.xml" "$TMP/mcp_300.rows"
# rule-4 twin (lane hrr): (NX3) runs unchanged under RIPWIRE_NO_HEAD_RR=1; (NX3h) the set prefix with the reorder on
mcp_so for "$Q" "" > "$TMP/mcp_def_so.xml"; rows "$TMP/mcp_def_so.xml" "$TMP/mcp_def_so.rows"
mcp_so for "$Q" ',"budget_tokens":300' > "$TMP/mcp_300_so.xml"; rows "$TMP/mcp_300_so.xml" "$TMP/mcp_300_so.rows"
M3NBS="$( attr sigs next_budget_tokens "$TMP/mcp_300_so.xml" )"
if isnum "$M3NBS"; then
    mcp_so for "$Q" ",\"budget_tokens\":$M3NBS" > "$TMP/mcp_nx_so.xml"; rows "$TMP/mcp_nx_so.xml" "$TMP/mcp_nx_so.rows"
    if cmp -s "$TMP/mcp_nx_so.rows" "$TMP/mcp_def_so.rows" && python3 "$TMP/prefix.py" "$TMP/mcp_300_so.rows" "$TMP/mcp_nx_so.rows"; then
        ok "(NX3) [RIPWIRE_NO_HEAD_RR=1 twin] MCP re-call at next_budget_tokens=$M3NBS serves the whole head ($( lines "$TMP/mcp_nx_so.rows" ) rows); the cut is its prefix"
    else
        no "(NX3) [RIPWIRE_NO_HEAD_RR=1 twin] MCP re-call at next_budget_tokens=$M3NBS served $( lines "$TMP/mcp_nx_so.rows" ) rows; the MCP default serves $( lines "$TMP/mcp_def_so.rows" )"
    fi
else
    no "(NX3) [RIPWIRE_NO_HEAD_RR=1 twin] no next_budget_tokens= to re-call with"
fi
if isnum "$M3NB"; then
    mcp_call for "$Q" ",\"budget_tokens\":$M3NB" > "$TMP/mcp_nx.xml"; rows "$TMP/mcp_nx.xml" "$TMP/mcp_nx.rows"
    if [ "$( lines "$TMP/mcp_nx.rows" )" -eq "$MN" ] && setp "$TMP/mcp_nx.rows" "$TMP/mcp_def.rows" "$TMP/mcp_def_so.rows" \
       && setp "$TMP/mcp_300.rows" "$TMP/mcp_nx.rows" "$TMP/mcp_def_so.rows"; then
        ok "(NX3h) head round-robin on: MCP re-call at next_budget_tokens=$M3NB serves the whole head as a set ($MN rows); the cut is its SET prefix"
    else
        no "(NX3h) head round-robin on: MCP re-call at next_budget_tokens=$M3NB served $( lines "$TMP/mcp_nx.rows" ) rows; the MCP default serves $MN (or the cut is not its set prefix)"
    fi
else
    no "(NX3h) no next_budget_tokens= to re-call with"
fi

# (P1) --pack-task at a tight target
"$BIN" "$CORPUS" --pack-task="$Q" --token-budget=300 "$CP" > "$TMP/pt.xml" 2>/dev/null; prc=$?
PTOC="$( attr ctx over_ceiling "$TMP/pt.xml" 2>/dev/null )"; pa=$?
if [ "$prc" -ne 0 ] || [ "$pa" -ne 0 ]; then no "(P1) --pack-task --token-budget=300 did not run (rc=$prc) or has no <ctx> root"
elif [ -z "$PTOC" ] && ! grep -q '(ceiling)\|header floor' "$TMP/pt.xml" && [ "$( attr ctx task "$TMP/pt.xml" )" = "$Q" ]; then
    ok "(P1) --pack-task --token-budget=300: no over_ceiling=, no '(ceiling)' drop, task= verbatim (soft target)"
else
    no "(P1) --pack-task --token-budget=300: over_ceiling='$PTOC', '(ceiling)'/'header floor' notes: $( grep -o '(ceiling)\|header floor' "$TMP/pt.xml" | wc -l | tr -d ' ' ) — a soft target is never 'over' and never sheds the header"
fi

# (P2) R9: the explicit default value serves the default's sections — the quota cascade is the one shaping rule both run
"$BIN" "$CORPUS" --pack-task="$Q" "$CP" > "$TMP/pt_def.xml" 2>/dev/null; p2a=$?
"$BIN" "$CORPUS" --pack-task="$Q" --token-budget=6000 "$CP" > "$TMP/pt_6000.xml" 2>/dev/null; p2b=$?
if [ "$p2a" -ne 0 ] || [ "$p2b" -ne 0 ] || ! grep -q '<sigs' "$TMP/pt_def.xml"; then
    no "(P2) --pack-task default / --token-budget=6000 did not run (rc=$p2a/$p2b) or served no sections"
elif cmp -s <( sed -n '/<sigs/,$p' "$TMP/pt_def.xml" | sed '1s/^.*<sigs/<sigs/' ) <( sed -n '/<sigs/,$p' "$TMP/pt_6000.xml" | sed '1s/^.*<sigs/<sigs/' ); then
    ok "(P2) --pack-task --token-budget=6000 serves the default --pack-task's sections byte for byte"
else
    no "(P2) --pack-task --token-budget=6000 serves different sections than the default (6000 is the default's own value)"
fi

# (P3) S7: the MCP explore twin of P1
mcp_call explore "$Q" ',"budget_tokens":300' > "$TMP/mcp_explore.xml"
EOC="$( attr ctx over_ceiling "$TMP/mcp_explore.xml" 2>/dev/null )"; ea=$?
if [ "$ea" -ne 0 ]; then no "(P3) MCP explore budget_tokens=300 produced no <ctx> root"
elif [ -z "$EOC" ]; then ok "(P3) MCP explore budget_tokens=300: no over_ceiling= (soft target)"
else no "(P3) MCP explore budget_tokens=300: over_ceiling='$EOC'"; fi

# ── ROUND C (owner decisions 2026-10-14) ─────────────────────────────────────────────────────────────────────
# FOLD C: the default answer's <tail> carries the file page's first rows (`--for=TASK --limit=160`, FOR-TAIL-WIDE: four
# pages): after the rank rows (the positive-score files outside the shown sigs rows; sym= too since tail-sym, train 30), the
# page's first 160 rows not already listed, each with sym= on the old walk's first 40 rows and path-only past them; total= every positive-score file (the page's total=); a cut tail's next= is the page from its first unprinted page row.
# RESERVE SECTIONS FIRST: under an explicit --token-budget the trailing sections (<hops>, <lego>, <compose>, the tail) keep at
# least the share the retired hard ceiling gave them, and the rows past its cut fill what they leave of T (ST above reads T - U).
cat > "$TMP/tail.py" <<'PY'
# tail.py FILE MODE [PAGE]: the <tail> of an answer — "rank" (paths of the rank rows), "page" (p<TAB>sym of the page rows),
# "ranksym" (p<TAB>sym of the rank rows), "all" (p<TAB>sym), "attrs" (total shown capped next). exit 3: no <tail>.
# tail-sym (train 30): rank rows carry sym= too, so the split is structural against PAGE (the same task at --limit=40):
# rank rows = the SHORTEST prefix after which the rows are exactly PAGE's rows not in it, in page order (a capped tail: a
# prefix of them); no such prefix → "SPLIT-FAIL" (and the arm comparing it fails).
import re, sys, html
s = open( sys.argv[ 1 ] ).read()
m = re.search( r'<tail\b([^>]*)>(.*?)</tail>', s, re.S )
if not m: sys.exit( 3 )
a = dict( re.findall( r'(\w+)="([^"]*)"', m.group( 1 ) ) )
rows = [ ( html.unescape( p ), html.unescape( y ), bool( h ) ) for p, h, y in re.findall( r'<t p="([^"]*)"( sym="([^"]*)")?/>', m.group( 2 ) ) ]
mode = sys.argv[ 2 ]
if mode == "attrs": print( a.get( "total", "" ), a.get( "shown", "" ), a.get( "capped", "" ), html.unescape( a.get( "next", "" ) ) )
k = 0
if mode in ( "rank", "page", "ranksym" ):
    page = [ html.unescape( q ) for q in re.findall( r'<f p="([^"]*)"', open( sys.argv[ 3 ] ).read() ) ]
    paths = [ p for p, _y, _h in rows ]
    k = -1
    for j in range( len( paths ) + 1 ):
        seen = set( paths[ :j ] ); rem = [ q for q in page if q not in seen ]
        if paths[ j: ] == ( rem[ :len( paths ) - j ] if a.get( "capped" ) == "1" else rem ):
            k = j; break
    if k < 0: print( "SPLIT-FAIL" ); sys.exit( 0 )
for i, ( p, y, h ) in enumerate( rows ):
    if mode == "rank" and i < k: print( p )
    if mode == "ranksym" and i < k: print( p + "\t" + y )
    if mode == "page" and i >= k: print( p + "\t" + y )
    if mode == "all": print( p + "\t" + y )
PY
cat > "$TMP/page.py" <<'PY'
# page.py RANKFILE < page: the page's rows (p<TAB>sym) not among RANKFILE's paths, in page order; "total=N" first
import re, sys, html
s = sys.stdin.read(); rank = set( open( sys.argv[ 1 ] ).read().split( "\n" ) )
m = re.search( r'<files\b[^>]*\btotal="([0-9]+)"', s ); print( "total=" + ( m.group( 1 ) if m else "" ) )
for p, y in re.findall( r'<f p="([^"]*)"[^>]*? sym="([^"]*)"', s ):
    if html.unescape( p ) not in rank: print( html.unescape( p ) + "\t" + html.unescape( y ) )
PY
# (C1) the default answer's tail: rank rows outside the shown head, then page 0 of the file page, sym= equal
if python3 "$TMP/tail.py" "$TMP/def.xml" attrs > "$TMP/c1.attrs"; then
    read -r C1T C1S C1C C1N < "$TMP/c1.attrs"
    "$BIN" "$CORPUS" --for="$Q" --limit=160 "$CF" 2>/dev/null > "$TMP/c1.pagexml"
    python3 "$TMP/tail.py" "$TMP/def.xml" rank "$TMP/c1.pagexml" > "$TMP/c1.rank"; python3 "$TMP/tail.py" "$TMP/def.xml" page "$TMP/c1.pagexml" > "$TMP/c1.page"
    python3 "$TMP/page.py" "$TMP/c1.rank" < "$TMP/c1.pagexml" > "$TMP/c1.want"
    C1PT="$( head -1 "$TMP/c1.want" | sed 's/total=//' )"; sed -i.bak '1d' "$TMP/c1.want"
    C1DUP="$( python3 - "$TMP/def.xml" "$TMP/c1.rank" <<'PY'
import re, sys
head = set( re.findall( r'<d [^>]*?\bp="([^"]*)"', open( sys.argv[ 1 ] ).read() ) )
print( sum( 1 for p in open( sys.argv[ 2 ] ).read().split( "\n" ) if p in head ) )
PY
)"
    # FOR-TAIL-WIDE: a tail page row is the page's row (same path, same order); its sym= is the page's own or absent (path-only past the old
    # 40-row walk, pinned by fortailwidecheck arm 3); the first row always names its sym=
    C1PV="$( python3 - "$TMP/c1.page" "$TMP/c1.want" <<'PY'
import sys
t = [ l.rstrip( "\n" ).split( "\t" ) for l in open( sys.argv[ 1 ] ) if l.strip( "\n" ) ]
w = [ l.rstrip( "\n" ).split( "\t" ) for l in open( sys.argv[ 2 ] ) if l.strip( "\n" ) ]
ok = len( t ) == len( w ) and len( t ) > 0 and all( a[ 0 ] == b[ 0 ] and ( len( a ) < 2 or not a[ 1 ] or a[ 1 ] == b[ 1 ] ) for a, b in zip( t, w ) ) and len( t[ 0 ] ) > 1 and t[ 0 ][ 1 ]
print( "OK" if ok else "BAD" )
PY
)"
    if [ -s "$TMP/c1.page" ] && [ "$C1PV" = OK ] && [ "$C1T" = "$C1PT" ] && [ "$C1DUP" = 0 ] && [ "$( lines "$TMP/c1.rank" )" -le 24 ] \
       && ! grep -q SPLIT-FAIL "$TMP/c1.rank"; then
        ok "(C1) default tail: $( lines "$TMP/c1.rank" ) rank rows outside the head, then the page's first 160 rows not listed ($( lines "$TMP/c1.page" ), sym= equal or absent); total=$C1T == the page's"
    else
        no "(C1) default tail: page rows $( lines "$TMP/c1.page" ) vs the page's $( lines "$TMP/c1.want" ), total=$C1T vs page $C1PT, $C1DUP rank row(s) in the head"
    fi
    # (C1t) tail-sym (train 30): every rank row names sym=, the file page's own sym= for that file (a pointer, reused); a
    #       rank-row file can sit past page row 40, so the names are read off the WHOLE page (--limit=total=)
    "$BIN" "$CORPUS" --for="$Q" --limit="$C1T" "$CF" 2>/dev/null > "$TMP/c1.pageall"
    C1TS="$( python3 "$TMP/tail.py" "$TMP/def.xml" ranksym "$TMP/c1.pagexml" | python3 -c '
import html, re, sys
want = { html.unescape( p ): html.unescape( y ) for p, y in re.findall( r"<f p=\"([^\"]*)\"[^>]*? sym=\"([^\"]*)\"", open( sys.argv[ 1 ] ).read() ) }
rows = [ l.rstrip( "\n" ).split( "\t" ) for l in sys.stdin if "\t" in l ]
print( len( rows ), sum( 1 for p, y in rows if not y or want.get( p ) != y ) )' "$TMP/c1.pageall" )"
    # an explicit PASS shape ("N 0", N >= 1): an empty or malformed reading (the reader crashed) fails, never passes
    case "$C1TS" in
        [1-9]*" 0") ok "(C1t) tail-sym: all $( printf '%s' "$C1TS" | cut -d' ' -f1 ) rank rows carry the file page's sym= for their file" ;;
        *)          no "(C1t) tail-sym: rank rows / rows whose sym= is missing or differs from the page's = '$C1TS'" ;;
    esac
    # (C2) a capped tail's next= is the page from its first unprinted page row, and it runs (rc 0, a <files> page at that offset)
    if [ "$C1C" = 1 ] && [ "$C1S" -lt "$C1T" ]; then
        C2OFF="$( printf '%s' "$C1N" | sed -nE "s/^--for='.*' --limit=40( --offset=([0-9]+))?\$/\2/p" )"
        if printf '%s' "$C1N" | grep -qE "^--for='$Q' --limit=40( --offset=[0-9]+)?\$" && run_next "$C1N" "$TMP/c2.xml" \
           && grep -qE "^<files [^>]* offset=\"${C2OFF:-0}\"" "$TMP/c2.xml" && [ "${C2OFF:-0}" -ge "$( lines "$TMP/c1.page" )" ]; then
            ok "(C2) the capped tail's next= ('${C1N:0:70}…') runs and serves the page from offset ${C2OFF:-0} (past every page row it printed)"
        else
            no "(C2) the capped tail's next= ('$C1N') is not the file page from its first unprinted row, or did not run"
        fi
    else
        no "(C2) premise: the default tail is not capped (total=$C1T shown=$C1S) — re-anchor on a capped tail"
    fi
    # (C3) the size is disclosed: est_tokens= on the root prices the whole answer, tail included (markup rate 2.5 B/token)
    C3E="$( attr ctx est_tokens "$TMP/def.xml" )"; C3B="$( wc -c < "$TMP/def.xml" | tr -d ' ' )"
    # body-fold (train 31): the fold's bodies are source text, priced at the body rate (forbodyfoldcheck (F6)); the markup-rate
    # floor reads the answer without the <fold> element
    C3B=$(( C3B - $( python3 -c 'import re,sys; m=re.search(r"<fold .*?</fold>", open(sys.argv[1]).read(), re.S); print(len(m.group(0).encode()) if m else 0)' "$TMP/def.xml" ) ))
    if isnum "$C3E" && [ "$(( C3E * 25 ))" -ge "$(( C3B * 10 * 97 / 100 ))" ]; then ok "(C3) est_tokens=$C3E prices the $C3B-byte answer, its tail included"
    else no "(C3) est_tokens='$C3E' does not price the $C3B-byte answer (the tail rides unpriced)"; fi
else
    no "(C1) the default answer carries no <tail>"
fi
# (C4) the JSON twin: the same tail rows (files + sym index-aligned), total=, next present exactly when cut
cli_for --json > "$TMP/def.json"
C4="$( python3 - "$TMP/def.json" "$TMP/def.xml" <<'PY'
import json, re, sys, html
t = json.load( open( sys.argv[ 1 ] ) ).get( "tail", {} ); x = open( sys.argv[ 2 ] ).read()
xa = dict( re.findall( r'(\w+)="([^"]*)"', re.search( r'<tail\b([^>]*)>', x ).group( 1 ) ) )
xr = [ ( html.unescape( p ), html.unescape( y ) ) for p, _, y in re.findall( r'<t p="([^"]*)"( sym="([^"]*)")?/>', x ) ]
ok = list( zip( t.get( "files", [] ), t.get( "sym", [] ) ) ) == xr and str( t.get( "total" ) ) == xa.get( "total" ) \
     and ( "next" in t ) == ( xa.get( "capped" ) == "1" ) and ( t.get( "next" ) or "" ) == html.unescape( xa.get( "next", "" ) )
print( "OK" if ok else "BAD json rows=%d xml rows=%d total %s/%s" % ( len( t.get( "files", [] ) ), len( xr ), t.get( "total" ), xa.get( "total" ) ) )
PY
)"
if [ "$C4" = OK ]; then ok "(C4) --json tail == the XML tail (files + sym, total=, next)"
else no "(C4) --json tail differs from the XML tail: $C4"; fi
# (C5) the MCP twin serves the same tail rows as the CLI default
mcp_call for "$Q" > "$TMP/mcp_def_tail.xml"
if python3 "$TMP/tail.py" "$TMP/mcp_def_tail.xml" all > "$TMP/c5.mcp" && python3 "$TMP/tail.py" "$TMP/def.xml" all > "$TMP/c5.cli" \
   && [ -s "$TMP/c5.cli" ] && cmp -s "$TMP/c5.mcp" "$TMP/c5.cli"; then ok "(C5) MCP for serves the CLI default's tail rows ($( lines "$TMP/c5.cli" ), sym= included)"
else no "(C5) MCP for's tail rows differ from the CLI default's ($( lines "$TMP/c5.mcp" ) vs $( lines "$TMP/c5.cli" ))"; fi
# (C6) under every explicit target of the sweep the tail is present, and a cut tail names a next= that runs
for n in "${SWEEP[@]}"; do
    f="$TMP/t_${n}_full.xml"
    if ! python3 "$TMP/tail.py" "$f" attrs > "$TMP/c6.attrs"; then no "(C6) N=$n: no <tail>"; continue; fi
    read -r T6 S6 C6 N6 < "$TMP/c6.attrs"
    if [ "$C6" = 1 ]; then
        if [ -n "$N6" ] && run_next "$N6" "$TMP/c6.xml" && grep -q '^<files ' "$TMP/c6.xml"; then ok "(C6) N=$n: the cut tail ($S6 of $T6) names a next= that runs"
        else no "(C6) N=$n: the cut tail ($S6 of $T6) names no runnable next= ('$N6')"; fi
    else ok "(C6) N=$n: the tail is complete ($S6 of $T6)"; fi
done
# (RF1) RESERVE SECTIONS FIRST, pinned against the retired hard ceiling (d4325a8c) on frozen in-repo fixtures: each trailing
# section keeps at least the rows that ceiling served it at the same N. Round B's soft target (sections took what the rows
# left of T) served 0 rows in every case below (RED on 13297e3a); lower bounds, never equalities.
cat > "$TMP/sec.py" <<'PY'
# sec.py SECTION < answer: the section's rows (lego: iface+impl+m; tail: t; hops: h+c)
import re, sys
tags = { "lego": ( "iface", "impl", "m" ), "tail": ( "t", ), "hops": ( "h", "c" ) }[ sys.argv[ 1 ] ]
s = sys.stdin.read(); m0 = re.search( r'<%s\b[^>]*>' % sys.argv[ 1 ], s )
if not m0: print( 0 ); sys.exit( 0 )
el = m0.group( 0 ) if m0.group( 0 ).endswith( "/>" ) else s[ m0.start(): s.find( "</%s>" % sys.argv[ 1 ], m0.end() ) ]
print( sum( len( re.findall( r'<%s[ >/]' % t, el ) ) for t in tags ) )
PY
QNODE="where is the node interface implemented"; QHAND="how does the handler process a request and call the service"
for spec in "legotransitivefix|$QNODE|600|lego|9" "legotransitivefix|$QNODE|1000|lego|9" "forcompletefix|$QNODE|1500|tail|11" \
            "forcompletefix|$QNODE|3000|tail|1" "forcompletefix|$QHAND|3000|tail|1"; do
    IFS='|' read -r fx q n sec want <<< "$spec"
    "$BIN" "test/$fx" --no-cache --for="$q" --token-budget="$n" > "$TMP/rf.xml" 2>/dev/null; rrc=$?
    got="$( python3 "$TMP/sec.py" "$sec" < "$TMP/rf.xml" )"
    if [ "$rrc" -eq 0 ] && isnum "$got" && [ "$got" -ge "$want" ]; then ok "(RF1) $fx '$q' N=$n: <$sec> keeps $got rows >= the retired ceiling's $want"
    else no "(RF1) $fx '$q' N=$n: <$sec> serves '$got' rows < the retired ceiling's $want (rc=$rrc) — a section lost its share to the rows"; fi
done

# (RF2) FIX1 R2 (review rv-forbudget-soft): the --json tail is a trailing section too — at an explicit N it keeps at least the
# bytes the retired hard ceiling (d4325a8c) gave it. Lower bounds measured on frozen in-repo fixtures; 974dd5b1 served 470/412/434
# and 514/438 B there (RED), the tail funded from what the refilled rows left.
for spec in "receiverevidencefix|$QNODE|1000|527" "receiverevidencefix|$QNODE|2000|582" "receiverevidencefix|$QNODE|3000|622" \
            "falseedgefix|$QHAND|2000|544" "falseedgefix|$QHAND|3000|526"; do
    IFS='|' read -r fx q n want <<< "$spec"
    got="$( "$BIN" "test/$fx" --no-cache --for="$q" --token-budget="$n" --json 2>/dev/null \
            | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(json.dumps(d["tail"],separators=(",",":"))))' 2>/dev/null )"
    if isnum "$got" && [ "$got" -ge "$want" ]; then ok "(RF2) $fx '$q' N=$n --json: the tail keeps $got B >= the retired ceiling's $want B"
    else no "(RF2) $fx '$q' N=$n --json: the tail serves '$got' B < the retired ceiling's $want B — a trailing section lost its share"; fi
done
# (RP10) FIX1 R1: rows are a rank prefix and MONOTONE in N at a step of 10, at three root path lengths (the header's root= moves
# which N the cut steps at; 974dd5b1 dropped a row at 1490 with a 28-char root: the tail's reserve stepped with the cut). The
# fornotesbudgetcheck corpus shape (72 noted symbols), swept 1400..1600, default and --json dialects.
RPD="$( mktemp -d /tmp/rwrp.XXXXXX )" || RPD="$TMP/rp"
mkdir -p "$RPD/a/c" "$RPD/medium_root_path_component/c" "$TMP/a_long_root_path_component_for_the_rp10_sweep/c"
for root in "$RPD/a/c" "$RPD/medium_root_path_component/c" "$TMP/a_long_root_path_component_for_the_rp10_sweep/c"; do
    mkdir -p "$root/src"
    python3 - "$root" <<'PY'
import os, sys
for i in range( 12 ):
    with open( os.path.join( sys.argv[ 1 ], "src", "mod%d.py" % i ), "w" ) as f:
        for j in range( 6 ):
            f.write( "def widgetRoutine%d_%d( alpha, beta ):\n    \"\"\"Route the widget pipeline stage %d.%d through the dispatcher.\"\"\"\n    return alpha + beta\n\n\n" % ( i, j, i, j ) )
PY
    ( cd "$root" && git init -q -b main . && git add -A && git -c user.email=gate@example.invalid -c user.name=gate commit -qm corpus ) >/dev/null 2>&1
    for i in 0 1 2 3 4 5 6 7 8 9 10 11; do for j in 0 1 2 3 4 5; do
        "$BIN" "$root" --note-add="widgetRoutine${i}_${j}: this routine is load-bearing for the widget dispatcher and must not be reordered without rechecking the stage table downstream" >/dev/null 2>&1
    done; done
    rp10="$( python3 - "$BIN" "$root" <<'PY'
import json, re, subprocess, sys
B, root = sys.argv[ 1 ], sys.argv[ 2 ]; q = "widget dispatcher pipeline stage"
def rows( s, js ):
    if js:
        return [ "%s:%s:%s" % ( e.get( "p" ), e.get( "l" ), e.get( "n" ) ) for e in sorted( json.loads( s ).get( "sigs", [] ), key=lambda e: e.get( "r", 10**9 ) ) ]
    m = re.search( r"<sigs\b[^>]*>(.*?)</sigs>", s, re.S ); out = []
    for x in re.finditer( r"<d ([^>]*)>", m.group( 1 ) if m else "" ):
        g = lambda k: ( re.search( r"\b" + k + r'="([^"]*)"', x.group( 1 ) ) or [ None, "?" ] )[ 1 ]
        out.append( ( int( g( "r" ) ) if g( "r" ).isdigit() else 10**9, g( "p" ) + ":" + g( "l" ) + ":" + g( "n" ) ) )
    return [ b for a, b in sorted( out ) ]
# rule-4 twin (lane hrr): the order-prefix sweep runs unchanged under RIPWIRE_NO_HEAD_RR=1 (twin); with the reorder on, the
# rows are a SET prefix of the default (score ranks 1..K, read off the twin default) and stay monotone in N (seth)
import os
sys.path.insert( 0, os.environ[ "RIPWIRE_TESTLIB" ] ); from softbudget import set_prefix
def run( argv, off ):
    env = dict( os.environ ); env.pop( "RIPWIRE_NO_HEAD_RR", None )
    if off: env[ "RIPWIRE_NO_HEAD_RR" ] = "1"
    return subprocess.run( argv, capture_output=True, env=env ).stdout.decode()
out = []
for mode in ( "twin", "seth" ):
    bad = []
    for js in ( False, True ):
        extra = [ "--json" ] if js else []
        ref = rows( run( [ B, root, "--for=" + q ] + extra, True ), js ); prev = None
        on = rows( run( [ B, root, "--for=" + q ] + extra, False ), js )
        for n in range( 1400, 1601, 10 ):
            r = rows( run( [ B, root, "--for=" + q, "--token-budget=%d" % n ] + extra, mode == "twin" ), js )
            if mode == "twin": pre = r == ref[ :len( r ) ]
            else: pre = set_prefix( r, on, ref )
            if not r or not pre or ( prev is not None and prev != r[ :len( prev ) ] ):
                bad.append( "%s@%d:%s->%d" % ( "json" if js else "xml", n, len( prev ) if prev else "-", len( r ) ) )
            prev = r
    out.append( mode + "=" + ( "OK" if not bad else "BAD " + " ".join( bad[ :4 ] ) ) )
print( ";".join( out ) )
PY
)"
    case "$rp10" in
        twin=OK*) ok "(RP10) [RIPWIRE_NO_HEAD_RR=1 twin] root of ${#root} chars: rows are a rank prefix, monotone in N, 1400..1600 step 10, default and --json" ;;
        *)  no "(RP10) [RIPWIRE_NO_HEAD_RR=1 twin] root of ${#root} chars: ${rp10%%;*} — the rows past the cut fell as N grew (or are not a rank prefix)" ;;
    esac
    case "$rp10" in
        *";seth=OK") ok "(RP10h) head round-robin on, root of ${#root} chars: rows are a SET prefix of the default, monotone in N, 1400..1600 step 10, default and --json" ;;
        *)  no "(RP10h) head round-robin on, root of ${#root} chars: ${rp10#*;} — the rows past the cut fell as N grew (or are not a set prefix)" ;;
    esac
done
rm -rf "$RPD"

# ── (SB-strip) strip_appended removes only the real trailing <syms> block, never body bytes a CDATA quote of its legend would span
if sbs="$( python3 -I "$RIPWIRE_TESTLIB/softbudget.py" strip-selftest 2>&1 )"; then ok "(SB-strip) strip_appended leaves a quoted '<!-- syms:' body alone: block, held stub, block before <graph>, no-block twin"
else no "(SB-strip) strip_appended swallowed or missed bytes: $sbs"; fi

# ── twins: the CI-gate personality of --token-budget is unchanged on the map, --query and --recall ───────
"$BIN" "$CORPUS" --token-budget=100 "$CM" > "$TMP/map.out" 2>/dev/null; grc=$?
GW="$( attr r withheld "$TMP/map.out" 2>/dev/null )"
if [ "$grc" -eq 3 ] && [ "$GW" = "1" ] && ! grep -q '<d ' "$TMP/map.out"; then ok "(G1) map --token-budget=100: exit 3, the map withheld whole (withheld=1, no rows)"
else no "(G1) map --token-budget=100: rc=$grc withheld='$GW', stdout $( wc -c < "$TMP/map.out" ) B — the gate personality must not move"; fi
"$BIN" "$CORPUS" --query="rank symbols" --token-budget=50 "$CM" > "$TMP/query.out" 2>/dev/null; qrc=$?
QW="$( attr r withheld "$TMP/query.out" 2>/dev/null )"
if [ "$qrc" -eq 3 ] && [ "$QW" = "1" ] && ! grep -q '<d ' "$TMP/query.out"; then ok "(G2) --query --token-budget=50: exit 3, withheld=1, no rows"
else no "(G2) --query --token-budget=50: rc=$qrc withheld='$QW' — the gate personality must not move"; fi
"$BIN" docs --recall=budget --token-budget=100 "$CD" > "$TMP/recall.out" 2>/dev/null; rrc=$?
if [ "$rrc" -eq 3 ] && grep -q 'shown=0' "$TMP/recall.out" && grep -q 'withheld_est_tokens=' "$TMP/recall.out"; then
    ok "(G3) --recall --token-budget=100: exit 3, shown=0, the withheld price disclosed"
else
    no "(G3) --recall --token-budget=100: rc=$rrc — the gate personality must not move"
fi

if [ "$fail" -ne 0 ]; then echo "FAILURES ABOVE"; exit 1; fi
echo "forsoftbudgetcheck: all arms pass"
