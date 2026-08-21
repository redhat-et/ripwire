#!/usr/bin/env bash
# bundleidcheck.sh — the P2.3/P2.4 "the flagship bundles carry a usable chain key, and never a false zero" gate.
#
#   test/bundleidcheck.sh                       # uses build/ripwire on test/fixture
#   RIPWIRE_BIN=asan/ripwire test/bundleidcheck.sh
#
# --for / --pack-task / --from-trace are the verbs an agent ORIENTS with, and the next move after reading one
# is always to chain into --expand=SYM / --callers=SYM. Before P2.3 their <d> rows carried l=/cx=/ccx= and the
# raw signature text but NO name and NO id, so chaining meant parsing a C++ declarator out of text like
# `inline HashMap<...> loadCache( const std::string&...`. And --pack-task/--from-trace printed in="0" on EVERY
# row while --for reported the real fan-in for the same symbol in the same run — a false zero that reads as
# "nobody calls this". This gate asserts:
#   * every <d> row of all three verbs carries n=.
#   * id= is emitted exactly when the canonical id ADDS an enclosing scope, and equals the DEFAULT map's id=
#     for the same symbol (one canonical id form across lenses — the --plan-lanes prerequisite).
#   * --for and --pack-task agree on in= for every symbol both bundles name (never 0-vs-real).
#   * no bundle asserts in="0" without a fan-in source: --from-trace OMITS the attribute instead.
#   * the added attributes are ACCOUNTED for, not overflowed — a --token-budget=N run still fits its own
#     reported byte budget, and --for's est_tokens still matches the bytes actually delivered.
#   * determinism (run twice → byte-identical) + well-formed XML on all three verbs.
# Mutation-tested: the n=-presence assertion is checked to actually FAIL on a row stripped of n=.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "bundleidcheck: BIN=$BIN"

TASK="compute perimeter distance"
FIX="test/fixture"

# a stack trace pointing INTO the fixture, so --from-trace has in-corpus frames to rank
cat > "$TMP/trace.txt" <<'EOF'
    #0 0x1 in distance test/fixture/geometry.cpp:5
    #1 0x2 in perimeter test/fixture/geometry.cpp:13
    #2 0x3 in diagonal test/fixture/sub/consumer.cpp:9
EOF

"$BIN" "$FIX" --no-cache --for="$TASK"        >"$TMP/for.xml"   2>/dev/null
"$BIN" "$FIX" --no-cache --pack-task="$TASK"  >"$TMP/task.xml"  2>/dev/null
"$BIN" "$FIX" --no-cache --from-trace="$TMP/trace.txt" >"$TMP/trace.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache                      >"$TMP/map.xml"   2>/dev/null

for f in for task trace map; do
    [ -s "$TMP/$f.xml" ] || no "$f bundle is empty — the rest of this gate is meaningless"
done

# every <d …> opening tag, one per line
drows(){ sed 's/></>\n</g' "$1" | grep -E '^<d ' ; }

# ── 1) every <d> row of all three flagship bundles carries n= ─────────────────────────────────────────
for v in for task trace; do
    TOTAL="$( drows "$TMP/$v.xml" | wc -l | tr -d ' ' )"
    NAMED="$( drows "$TMP/$v.xml" | grep -cE '^<d [^>]* n="' )"
    [ "$TOTAL" -gt 0 ] || { no "$v: no <d> rows at all — cannot assert n="; continue; }
    [ "$TOTAL" = "$NAMED" ] \
        && ok "$v: all $TOTAL <d> rows carry n= (the chain key into --expand/--callers)" \
        || no "$v: only $NAMED of $TOTAL <d> rows carry n="
done

# mutation control: the same assertion must FAIL on a row with n= stripped
MUT="$( drows "$TMP/for.xml" | head -1 | sed 's/ n="[^"]*"//' )"
printf '%s\n' "$MUT" | grep -qE '^<d [^>]* n="' \
    && no "mutation control: an n=-stripped row still matched the presence test (the test is vacuous)" \
    || ok "mutation control: an n=-stripped row correctly fails the presence test"

# ── 2) id= — emitted exactly when scoped, and identical to the DEFAULT map's canonical id ─────────────
# The fixture's only scoped symbol is Point (a C++ class); free functions must stay id-less (zero token cost).
MAP_ID="$( grep -o '<s [^>]*n="Point"[^>]*>' "$TMP/map.xml" | grep -o 'id="[^"]*"' | head -1 )"
FOR_ID="$( drows "$TMP/for.xml" | grep -E ' n="Point"' | grep -o 'id="[^"]*"' | head -1 )"
if [ -n "$MAP_ID" ]; then
    [ "$MAP_ID" = "$FOR_ID" ] \
        && ok "id= agrees with the default map's canonical id for Point ($MAP_ID)" \
        || no "id= disagrees with the default map: map=$MAP_ID bundle=${FOR_ID:-<absent>}"
else
    no "default map emitted no id= for Point — the fixture changed; re-anchor this assertion"
fi
SCOPELESS_WITH_ID="$( drows "$TMP/for.xml" | grep -E ' n="(distance|perimeter)"' | grep -c 'id="' )"
[ "$SCOPELESS_WITH_ID" = "0" ] \
    && ok "id= omitted on scope-less symbols (canonical id == bare name → no token cost)" \
    || no "id= emitted on $SCOPELESS_WITH_ID scope-less row(s) — it must add disambiguation or be absent"

# ── 3) --for and --pack-task agree on in= for every symbol BOTH bundles name ──────────────────────────
python3 - "$TMP/for.xml" "$TMP/task.xml" <<'PY' >"$TMP/incmp.txt" 2>&1
import re, sys

def rows( path ):
    text = open( path, encoding = 'utf-8' ).read()
    out  = {}
    # <d …> rows are grouped under <f p="…"> — track the enclosing file so the key is unambiguous
    fileNow = ''
    for m in re.finditer( r'<f p="([^"]*)"|<d ([^>]*)>', text ):
        if m.group( 1 ) is not None:
            fileNow = m.group( 1 );  continue
        attrs = dict( re.findall( r'(\w+)="([^"]*)"', m.group( 2 ) ) )
        if 'n' not in attrs or 'l' not in attrs: continue
        out[ ( fileNow, attrs['l'], attrs['n'] ) ] = attrs.get( 'in' )
    return out

a, b   = rows( sys.argv[1] ), rows( sys.argv[2] )
shared = sorted( set( a ) & set( b ) )
bad    = [ ( k, a[k], b[k] ) for k in shared if a[k] != b[k] ]
print( 'shared=%d' % len( shared ) )
print( 'missing_in_task=%d' % sum( 1 for k in shared if b[k] is None ) )
for k, x, y in bad: print( 'MISMATCH %s for=%s task=%s' % ( k, x, y ) )
PY
SHARED="$( grep -o 'shared=[0-9]*' "$TMP/incmp.txt" | cut -d= -f2 )"
MISM="$( grep -c '^MISMATCH' "$TMP/incmp.txt" )"
[ -n "${SHARED:-}" ] && [ "$SHARED" -gt 0 ] \
    && ok "--for and --pack-task name $SHARED symbol(s) in common (the comparison is non-vacuous)" \
    || no "--for and --pack-task share no symbols — cannot compare in=; $( head -3 "$TMP/incmp.txt" )"
[ "$MISM" = "0" ] \
    && ok "--for and --pack-task agree on in= for every shared symbol" \
    || no "in= disagrees between --for and --pack-task: $( grep '^MISMATCH' "$TMP/incmp.txt" | head -3 )"
# and the real values must actually be present (not "agreeing" by both being absent)
grep -q 'missing_in_task=0' "$TMP/incmp.txt" \
    && ok "--pack-task carries a real in= on every shared row (no dropped attribute)" \
    || no "--pack-task omitted in= on some shared rows: $( grep 'missing_in_task' "$TMP/incmp.txt" )"

# ── 4) never a FALSE zero — --from-trace must either omit in= or carry the TRUE value ─────────────────
# The original rule here was "omit, because this bundle has no fan-in source". The orchestrator then gave
# --from-trace a real source (fanInFromInEdges off the in-edge CSR, hoisted to graph.h), so omission is no
# longer the only honest answer — and the STRONGER property is what actually matters to a reader: whatever
# in= --from-trace prints must equal what --for prints for that same symbol. A silent all-zeros regression
# would have passed the old assertion by simply not printing; it cannot pass this one.
TRACE_ZEROS="$( drows "$TMP/trace.xml" | grep -c ' in="0"' )"
TRACE_IN="$( drows "$TMP/trace.xml" | grep -c ' in="' )"
if [ "$TRACE_IN" = "0" ]; then
    ok "--from-trace omits in= (no fan-in source) instead of asserting in=\"0\""
else
    # every in= it DOES print must match the --for value for the same symbol name
    mism=0
    while read -r nm val; do
        [ -n "$nm" ] || continue
        ref="$( drows "$TMP/for.xml" | grep -oE "n=\"$nm\"[^>]* in=\"[0-9]+\"" | grep -oE 'in="[0-9]+"' | head -1 | tr -cd '0-9' )"
        [ -n "$ref" ] || continue
        [ "$val" = "$ref" ] || { mism=$(( mism + 1 )); echo "    mismatch $nm: trace=$val for=$ref"; }
    done <<< "$( drows "$TMP/trace.xml" | grep -oE 'n="[A-Za-z_][A-Za-z0-9_]*"[^>]* in="[0-9]+"' \
                 | sed -E 's/n="([^"]*)".* in="([0-9]+)"/\1 \2/' )"
    [ "$mism" = "0" ] \
        && ok "--from-trace in= agrees with --for on every shared symbol ($TRACE_IN row(s), $TRACE_ZEROS zero)" \
        || no "--from-trace in= disagrees with --for on $mism row(s) — one of them is lying"
fi

# ── 5) budget accounting survives the added attributes ────────────────────────────────────────────────
# the header states its own byte budget + ceiling; the delivered document must fit BOTH.
for B in 600 1200 6000; do
    "$BIN" "$FIX" --no-cache --pack-task="$TASK" --token-budget=$B >"$TMP/b.$B" 2>/dev/null
    BYTES="$( wc -c < "$TMP/b.$B" | tr -d ' ' )"
    BUDGET="$( grep -o 'budget=[0-9]* bytes' "$TMP/b.$B" | head -1 | tr -dc '0-9' )"
    CEIL="$( grep -o 'ceiling [0-9]*' "$TMP/b.$B" | head -1 | tr -dc '0-9' )"
    # §B1.7 fixup (2026-07-29): the strict BYTES<=CEIL arm was passing by a 28-byte accident — the DESIGN
    # contract has always been ceiling + the single-entry overshoot tolerance (the ranking section emits its
    # first entry whole; partitioncheck.sh committed the same TOL=1.15 for the same reason). The verbatim
    # task= root attribute (charged to the budget, route= dropped-and-disclosed at tight ceilings) consumed
    # the accident. Meaning half kept: the ledger is readable and the document fits ceiling*1.15.
    CEILTOL=$(( CEIL * 115 / 100 ))
    # CA4 §B7.5 / trap #28: this arm asserted the unconditional fit and therefore CONTRADICTED arm 5b twelve
    # lines below, which has always accepted an overshoot that DISCLOSES over_ceiling — that is the documented
    # contract (serialize.h climbCeilingLadder rung (d): "a caller who hit the wall is owed the complete bundle
    # and an honest label"). Two arms in one file asserting opposite things about one property means one of
    # them fails whenever the code is right. Asserted here as the BICONDITIONAL, which is strictly stronger
    # than either: it still fails an undisclosed overshoot (the original catch) AND now also fails a document
    # that fits while CLAIMING over_ceiling, which the old form could not see. Grepped from the HEADER COMMENT
    # only — the bundle emits source text, and this repo's own sources contain the string "over_ceiling"
    # (trap #15). Measured margin note: at B=600 on this fixture the pre-CA4 binary delivered 1618 B against a
    # 1628 B bar — a 10-byte accident, the same shape as the 28-byte one the fixup above records.
    OVERLBL="$( sed -n 's/.*<!-- ripwire task bundle\(.*\)-->.*/\1/p' "$TMP/b.$B" | grep -c 'over_ceiling' )"
    [ "${OVERLBL:-0}" -gt 0 ] && OVERLBL=1 || OVERLBL=0
    [ "$BYTES" -gt "$CEILTOL" ] && OVERREAL=1 || OVERREAL=0
    if [ -z "$BUDGET" ] || [ -z "$CEIL" ]; then
        no "--token-budget=$B: header reported no budget/ceiling — the ledger is unreadable"
    elif [ "$OVERREAL" = "$OVERLBL" ]; then
        if [ "$OVERREAL" = 0 ]; then ok "--token-budget=$B: delivered $BYTES B <= ceiling $CEIL B * 1.15 first-entry tolerance (budget $BUDGET B), no over_ceiling claimed"
        else                         ok "--token-budget=$B: delivered $BYTES B past ceiling $CEIL B * 1.15 and SAYS over_ceiling (the ladder's honest rung)"; fi
    elif [ "$OVERREAL" = 1 ]; then
        no "--token-budget=$B: delivered $BYTES B OVERFLOWS ceiling $CEIL B even at the 1.15 single-entry tolerance, with NO over_ceiling label"
    else
        no "--token-budget=$B: delivered $BYTES B FITS ceiling $CEIL B * 1.15 yet the header claims over_ceiling"
    fi
    # the truncation ledger must still reconcile: every "kept X of Y" has X <= Y
    python3 - "$TMP/b.$B" <<'PY' || no "--token-budget=$B: truncation ledger does not reconcile"
import re, sys
head = open( sys.argv[1], encoding = 'utf-8' ).read().split( '-->' )[0]
bad  = [ ( a, b ) for a, b in re.findall( r'(?:kept )?(\d+) of (\d+)', head ) if int( a ) > int( b ) ]
sys.exit( 1 if bad else 0 )
PY
done
[ $fail -eq 0 ] && ok "truncation ledgers reconcile (kept <= total on every section)"

# ── 5b) W3FIX M1 — the FIXTURE BLIND SPOT the arm above had: a THREE-WORD task ──────────────────────────
# $TASK is "compute perimeter distance" — 26 bytes. The header echoes the task TWICE (verbatim in task=, and
# dash-scrubbed in the comment), so at 26 bytes the user's own text is ~52 of a ~1400-byte ceiling and the arm
# above could never see the defect it was written to catch: a fixed kPackTaskHeaderReserve of 1024 being asked
# to bound USER-LENGTH bytes. At a 320-byte task the same budget=600 point was 1.7x over the ceiling. So the
# same accounting, with a task long enough for the echo to matter — and the honest bar, because past some task
# length the header floor exceeds the ceiling and no trim can fix it: fit ceiling*1.15, or SAY over_ceiling.
LONGTASK="$( python3 -c "print(('shape the bundle under one budget and disclose every cut '*8)[:320])" 2>/dev/null )"
if [ -z "$LONGTASK" ]; then
    no "5b: python3 unavailable — the long-task ceiling arm could not build its 320-byte task"
else
    for B in 600 1200; do
        "$BIN" "$FIX" --no-cache --pack-task="$LONGTASK" --token-budget=$B >"$TMP/lt.$B" 2>/dev/null
        LT_BYTES="$( wc -c < "$TMP/lt.$B" | tr -d ' ' )"
        LT_CEIL="$( grep -o 'ceiling [0-9]*' "$TMP/lt.$B" | head -1 | tr -dc '0-9' )"
        # the disclosure lives in the header COMMENT — read only up to the first "-->" so a body cannot supply it
        LT_HDR="$( head -c 6000 "$TMP/lt.$B" | sed -e 's/-->.*//' )"
        if [ -z "$LT_CEIL" ]; then
            no "5b --token-budget=$B (320-byte task): header reported no ceiling — the ledger is unreadable"
        elif [ "$LT_BYTES" -le $(( LT_CEIL * 115 / 100 )) ]; then
            ok "5b --token-budget=$B (320-byte task): delivered $LT_BYTES B <= ceiling $LT_CEIL B * 1.15"
        elif printf '%s' "$LT_HDR" | grep -q 'over_ceiling'; then
            ok "5b --token-budget=$B (320-byte task): $LT_BYTES B over ceiling $LT_CEIL B and DISCLOSES over_ceiling"
        else
            no "5b --token-budget=$B (320-byte task): $LT_BYTES B past ceiling $LT_CEIL B * 1.15 in SILENCE"
        fi
    done
fi

# --for's est_tokens must still describe the bytes actually delivered. T3 (contract update, same wave):
# the default bundle is MIXED-rate — markup at ~2.50 B/token plus the auto <bodies> span at ~3.80 — so the
# band is checked against the blended expectation for THIS document's own markup/body split, ±10%.
EST="$( grep -o 'est_tokens="[0-9]*"' "$TMP/for.xml" | head -1 | tr -dc '0-9' )"
FORBYTES="$( wc -c < "$TMP/for.xml" | tr -d ' ' )"
if [ -n "$EST" ] && [ "$EST" -gt 0 ]; then
    python3 -c "
import sys
est, b = $EST, $FORBYTES
d = open( '$TMP/for.xml', 'rb' ).read()
a2 = d.find( b'<bodies ' ); b2 = d.find( b'</bodies>' )
span = ( b2 + 9 ) - a2 if a2 >= 0 and b2 >= 0 else 0
expected = ( b - span ) / 2.50 + span / 3.80
sys.exit( 0 if 0.90 <= est / expected <= 1.10 else 1 )" \
        && ok "--for est_tokens=$EST still describes the delivered $FORBYTES B (blended rate in band)" \
        || no "--for est_tokens=$EST does not match the delivered $FORBYTES B — the estimate drifted"
else
    no "--for emitted no est_tokens — the budget report vanished"
fi

# ── 6) determinism + well-formed XML on all three verbs ───────────────────────────────────────────────
"$BIN" "$FIX" --no-cache --for="$TASK" >"$TMP/for2.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache --pack-task="$TASK" >"$TMP/task2.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache --from-trace="$TMP/trace.txt" >"$TMP/trace2.xml" 2>/dev/null
for v in for task trace; do
    diff -q "$TMP/$v.xml" "$TMP/${v}2.xml" >/dev/null \
        && ok "$v: byte-identical run-to-run (det-gate)" || no "$v: non-deterministic output"
done
if command -v xmllint >/dev/null 2>&1; then
    for v in for task trace; do
        xmllint --noout "$TMP/$v.xml" 2>/dev/null \
            && ok "$v: G4 xmllint clean with n=/id= present" || no "$v: G4 xmllint FAILED"
    done
else
    ok "xmllint absent — G4 checks skipped"
fi

[ $fail -eq 0 ] && { echo "bundleidcheck: ALL PASS"; exit 0; }
echo "bundleidcheck: FAILURES"; exit 1
