#!/usr/bin/env bash
# w3fixbudgetcheck.sh — gate for the W3FIX budget/echo seam: the four findings the wave-3 verifier raised
# about what a task-shaped verb does with the user's OWN TEXT, in the header and in the budget.
#
# Usage:
#   test/w3fixbudgetcheck.sh                                  # uses build/ripwire
#   test/w3fixbudgetcheck.sh asan/ripwire
#   RIPWIRE_BIN=build_base/ripwire test/w3fixbudgetcheck.sh    # red-first: every family below MUST fail here
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# DO NOT edit regression.sh — this is a standalone gate invoked from there.
#
# WHY THIS GATE EXISTS. Three sibling gates each covered a piece of this seam and each stopped at the piece it
# was written for: taskechocheck proved the §B1.7 attribute exists and round-trips a `--`-bearing query;
# tokenbudgetcheck proved --token-budget is MONOTONE (a bigger budget never delivers less); bundleidcheck
# proved the ceiling holds on ONE fixture with a THREE-WORD task. None of them ever passed a hostile BYTE or a
# LONG task, which is where all four findings lived. The arms here are organised by finding.
#
#   H2 — --for's header floor (fixed legend + the task echoed twice) can exceed the ceiling --help promises it
#        "trims to fit", and it shipped the overrun silently: 5.3x at a 900-char task. An absolute-ceiling arm,
#        which is what monotonicity could never catch — a floor is monotone.
#   M1 — --pack-task charged the verbatim task= attribute and not the comment's echo of the same text, so a
#        fixed 1024-byte reserve was bounding user-length bytes; and its "route_attr: dropped (ceiling)" note
#        claimed a remedy that had not been measured. Same class at --recall --max-tokens, where the byte
#        accounting was already right and the DISCLOSURE was missing.
#   M2 — a \n in the task emitted a LITERAL newline inside the root attribute (G4: no \n outside CDATA), and
#        XML attribute-value normalization rewrites \t/\n/\r to a space on parse-back, so the attribute whose
#        entire purpose is verbatim fidelity handed back a different string than the user typed.
#   M3 — the comment echo was dash-scrubbed and nothing else, so a C0 byte or an invalid UTF-8 sequence in the
#        task made xmllint reject the whole document.
#
# THE ONE INVARIANT the ceiling arms assert (and the reason they can be absolute at all): a bundle is
# conformant at or under ceiling x 1.15 — the single-entry overshoot the design allows, because the ranking
# section emits its first entry WHOLE (src/serialize.h kCeilingFirstEntryTolerance; the same 1.15
# bundleidcheck.sh and partitioncheck.sh already commit to). Past that bar the lens has provably failed to trim
# to fit, and must SAY SO. So the assertion is a biconditional, not a bound:
#
#       delivered > ceiling * 1.15   <=>   the document discloses over_ceiling
#
# A one-sided bound would be satisfiable by a lens that never trims and never admits it (the pre-fix state) or
# by one that labels everything over_ceiling (honest but useless). Both directions are checked.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "w3fixbudgetcheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3  >/dev/null 2>&1 || { echo "w3fixbudgetcheck: python3 is required (XML parse-back + JSON arms)"; exit 2; }
command -v xmllint  >/dev/null 2>&1 || { echo "w3fixbudgetcheck: xmllint is required (G4 arm)"; exit 2; }

echo "w3fixbudgetcheck: BIN=$BIN"

# ── the corpus. Its own tree, so the arms do not move when src/ does. Two files with real call edges, enough
#    symbols that the ranking section has something to trim, and a doc so --recall has a body to budget. ─────
CORPUS="$TMP/corpus"
mkdir -p "$CORPUS/src" "$CORPUS/docs" || { echo "w3fixbudgetcheck: cannot create corpus under $TMP"; exit 2; }
cat > "$CORPUS/src/budget.py" <<'PY_EOF'
def ceilingBytes( tokenTarget, bytesPerToken ):
    """The hard byte ceiling a token target implies, at the densest measured rate."""
    return int( tokenTarget * bytesPerToken )

def headerFloorBytes( legendBytes, taskBytes ):
    """The header cannot shrink below its fixed legend plus the caller's own echoed task."""
    return legendBytes + taskBytes + taskBytes

def remainingAfterHeader( budgetBytes, legendBytes, taskBytes ):
    """What the payload sections may spend once the header has been charged exactly."""
    floor = headerFloorBytes( legendBytes, taskBytes )
    return budgetBytes - floor if budgetBytes > floor else 1

def shapeBundle( budgetTokens, legendBytes, taskBytes ):
    """Shape a bundle to a token budget, reporting whether the floor busted the ceiling."""
    ceiling   = ceilingBytes( budgetTokens, 2.36 )
    remaining = remainingAfterHeader( ceiling, legendBytes, taskBytes )
    return { 'ceiling': ceiling, 'remaining': remaining, 'over': remaining == 1 }
PY_EOF
cat > "$CORPUS/src/report.py" <<'PY_EOF'
from budget import shapeBundle, ceilingBytes

def renderBudgetReport( budgetTokens, legendBytes, taskBytes ):
    """Render the truncation ledger a shaped bundle discloses in its header."""
    shape = shapeBundle( budgetTokens, legendBytes, taskBytes )
    tail  = ' | busted' if shape[ 'over' ] else ''
    return 'budget=%d bytes%s' % ( shape[ 'ceiling' ], tail )

def disclosureSentence( isBusted ):
    """The one sentence a lens owes a caller whose budget it could not honour."""
    return 'the header floor exceeds this budget' if isBusted else ''
PY_EOF
cat > "$CORPUS/docs/BUDGET_NOTES.md" <<'MD_EOF'
# Budget notes

The header floor is the fixed legend plus the caller's own task, echoed once verbatim in the root
attribute and once scrubbed into the header comment. No payload trim can shrink either copy, so past
some task length the floor alone busts the stated ceiling and the only honest move left is to say so.

## Ceiling tolerance

The ranking section emits its first entry whole, so a small overshoot is permitted by design. A bundle at
or under the ceiling times that tolerance is conformant and says nothing.
MD_EOF

# ── the hostile task bytes, built in python so the shell never has to carry a raw NUL-adjacent byte. Each is
#    written to a file and read back with $(cat) so the exact bytes reach argv. ───────────────────────────────
python3 - "$TMP" <<'PY_EOF'
import os, sys
d = sys.argv[1]
cases = {
    'nl':   b'anchor\nthe budget ceiling',
    'tab':  b'anchor\tthe budget ceiling',
    'cr':   b'anchor\rthe budget ceiling',
    'c0':   b'anchor\x01the budget ceiling',
    'badu8':b'anchor\xffthe budget ceiling',
    'mixed':b'anchor--the\n\x01budget\tceiling\xff',
}
for name, raw in cases.items():
    open( os.path.join( d, 'task.' + name ), 'wb' ).write( raw )
# the 900-char task H2 was measured with: long enough that the doubled echo alone busts a tight ceiling
open( os.path.join( d, 'task.long' ), 'wb' ).write(
    ( b'budget accounting for the ranked lens header attributes ' * 20 )[ :900 ] )
# 300+ chars: the length bundleidcheck's fixture arm never reached
open( os.path.join( d, 'task.mid' ), 'wb' ).write(
    ( b'shape the bundle under one budget and disclose every cut ' * 8 )[ :320 ] )
PY_EOF

HOSTILE="nl tab cr c0 badu8 mixed"

# The disclosure lives in the header COMMENT. Grepping the whole document for it would also match a body that
# quotes the word — this gate's own corpus does, deliberately, so that mistake cannot pass unnoticed. Every
# ceiling arm below reads the header region ONLY: everything up to the first "-->".
hdr(){ python3 -c "
import sys
d = open( sys.argv[1], 'rb' ).read()
i = d.find( b'-->' )
sys.stdout.buffer.write( d if i < 0 else d[ :i + 3 ] )" "$1"; }
saysOverCeiling(){ hdr "$1" | grep -q 'over_ceiling'; }

# ═══ 1) M2 + M3 — G4 AND xmllint under hostile task bytes, every verb that echoes user text ═══════════════════
# RED (build_base): xmllint FAILS on {--for,--pack-task} x {c0,badu8}; the newline arms emit a literal \n
# outside CDATA on --for/--pack-task/--exemplar/--grep/--whereis. Both halves of that are asserted here.
NEWLINE_VERBS="--for --pack-task --exemplar --grep --whereis"
for V in $NEWLINE_VERBS; do
    for H in $HOSTILE; do
        T="$( cat "$TMP/task.$H" )"
        "$BIN" "$CORPUS" --no-cache "$V=$T" >"$TMP/h.out" 2>/dev/null
        RC=$?
        # a refusal is a legitimate answer for a selector-shaped verb; only OUTPUT is judged
        if [ ! -s "$TMP/h.out" ]; then
            ok "$V($H): no document emitted (rc=$RC) — nothing to malform"
            continue
        fi
        if xmllint --noout "$TMP/h.out" 2>/dev/null; then
            ok "$V($H): xmllint clean"
        else
            no "$V($H): xmllint REJECTS the document — a task byte reached a place XML cannot carry it"
        fi
        # G4: no newline outside CDATA. CDATA sections are stripped first so a body's own newlines never count.
        python3 - "$TMP/h.out" <<'PY_EOF' \
            && ok "$V($H): G4 — zero newlines outside CDATA" \
            || no "$V($H): G4 BREACH — a raw newline escaped into markup"
import re, sys
d = open( sys.argv[1], 'rb' ).read()
stripped = re.sub( rb'<!\[CDATA\[.*?\]\]>', b'', d, flags = re.S )
sys.exit( 1 if b'\n' in stripped else 0 )
PY_EOF
    done
done

# ═══ 2) M2 — the VERBATIM round-trip through a real XML parser, and JSON parity ═══════════════════════════════
# The point is not "does it lint" but "does a parser hand back the bytes the user typed". \t \n \r must survive
# attribute-value normalization exactly (character references do; literal control chars are rewritten to a
# space, which is the RED behaviour). C0 outside \t\n\r has no XML encoding at all, so XML scrubs it to a space
# and only the JSON dialect can be verbatim there — asserted as such, so the limit is pinned rather than hidden.
for V in for pack-task; do
    for H in nl tab cr; do
        T="$( cat "$TMP/task.$H" )"
        "$BIN" "$CORPUS" --no-cache "--$V=$T"          >"$TMP/rt.xml"  2>/dev/null
        "$BIN" "$CORPUS" --no-cache "--$V=$T" --json   >"$TMP/rt.json" 2>/dev/null
        python3 - "$TMP/task.$H" "$TMP/rt.xml" "$TMP/rt.json" "$H" <<'PY_EOF' \
            && ok "--$V($H): task= round-trips VERBATIM through an XML parser, and matches the JSON dialect" \
            || no "--$V($H): the parsed task= is NOT the string that was passed in (or the dialects disagree)"
import json, sys, xml.etree.ElementTree as ET
raw  = open( sys.argv[1], 'rb' ).read().decode( 'utf-8' )
attr = ET.parse( sys.argv[2] ).getroot().attrib.get( 'task' )
key  = json.load( open( sys.argv[3], encoding = 'utf-8' ) ).get( 'task' )
if key != raw:
    print( '    json task key differs: %r != %r' % ( key, raw ) );  sys.exit( 1 )
if attr != raw:
    print( '    xml task attr differs: %r != %r' % ( attr, raw ) );  sys.exit( 1 )
sys.exit( 0 )
PY_EOF
    done
done

# the LIMIT of "verbatim", pinned so it cannot quietly widen or narrow. \t \n \r are the only control chars XML
# 1.0 permits at all; the rest of C0 has no encoding in this format, not even a character reference, so the XML
# dialect MUST scrub it. Invalid UTF-8 is scrubbed by BOTH dialects (XML to '?', JSON to U+FFFD) — neither can
# emit a byte sequence its own encoding rejects. The arm asserts the substitution is exactly that and nothing
# more: the legal whitespace either side of the illegal byte must survive untouched.
T="$( cat "$TMP/task.mixed" )"
"$BIN" "$CORPUS" --no-cache "--for=$T"        >"$TMP/lim.xml"  2>/dev/null
"$BIN" "$CORPUS" --no-cache "--for=$T" --json >"$TMP/lim.json" 2>/dev/null
python3 - "$TMP/lim.xml" "$TMP/lim.json" <<'PY_EOF' \
    && ok "--for: the ONE documented scrub — illegal C0 -> ' ' (XML), invalid UTF-8 -> '?'/U+FFFD; \\t \\n survive" \
    || no "--for: the scrub of an XML-illegal byte took legal whitespace with it (or left the illegal byte in)"
import json, sys, xml.etree.ElementTree as ET
attr = ET.parse( sys.argv[1] ).getroot().attrib.get( 'task' )
key  = json.load( open( sys.argv[2], encoding = 'utf-8' ) ).get( 'task' )
# input was b'anchor--the\n\x01budget\tceiling\xff'
if attr != 'anchor--the\n budget\tceiling?':
    print( '    xml attr: %r' % ( attr, ) );  sys.exit( 1 )
if key != 'anchor--the\n\x01budget\tceiling�':
    print( '    json key: %r' % ( key, ) );  sys.exit( 1 )
sys.exit( 0 )
PY_EOF

# ═══ 3) H2 + M1 — THE ABSOLUTE CEILING BICONDITIONAL, across task length x budget ════════════════════════════
# tokenbudgetcheck asserts MONOTONICITY, which a floor satisfies trivially (5.3x over at every budget is
# perfectly monotone). This is the absolute arm: for every (task length, budget) point, the delivered document
# either fits ceiling*1.15 or says over_ceiling — never neither, never both.
CEILING_ARM_POINTS=0
CEILING_ARM_BAD=0
for TASKFILE in mid long; do
    T="$( cat "$TMP/task.$TASKFILE" )"
    for B in 300 600 900 1200 1600 3000; do
        for V in for pack-task; do
            "$BIN" "$CORPUS" --no-cache "--$V=$T" --token-budget=$B >"$TMP/c.out" 2>/dev/null
            BYTES="$( wc -c < "$TMP/c.out" | tr -d ' ' )"
            # the bar, in shell, from the same two constants the code uses (2.36 B/tok x 1.15 tolerance)
            ALLOW="$( python3 -c "print(int($B*2.36*1.15))" )"
            OVER=0;  saysOverCeiling "$TMP/c.out" && OVER=1
            CEILING_ARM_POINTS=$(( CEILING_ARM_POINTS + 1 ))
            if [ "$BYTES" -gt "$ALLOW" ] && [ "$OVER" = "0" ]; then
                CEILING_ARM_BAD=$(( CEILING_ARM_BAD + 1 ))
                echo "    --$V task=$TASKFILE budget=$B: $BYTES B > allowance $ALLOW B and SILENT about it"
            elif [ "$BYTES" -le "$ALLOW" ] && [ "$OVER" = "1" ]; then
                CEILING_ARM_BAD=$(( CEILING_ARM_BAD + 1 ))
                echo "    --$V task=$TASKFILE budget=$B: $BYTES B fits allowance $ALLOW B yet claims over_ceiling"
            fi
        done
    done
done
[ "$CEILING_ARM_BAD" = "0" ] \
    && ok "ceiling biconditional holds at all $CEILING_ARM_POINTS (task length x budget x lens) points" \
    || no "ceiling biconditional VIOLATED at $CEILING_ARM_BAD of $CEILING_ARM_POINTS points"

# the RED case named in the finding, asserted on its own so a regression names itself: a 900-char task at a
# tight budget must not be silently 2x+ over.
T="$( cat "$TMP/task.long" )"
for V in for pack-task; do
    "$BIN" "$CORPUS" --no-cache "--$V=$T" --token-budget=600 >"$TMP/c.long" 2>/dev/null
    BYTES="$( wc -c < "$TMP/c.long" | tr -d ' ' )"
    ALLOW="$( python3 -c "print(int(600*2.36*1.15))" )"
    if [ "$BYTES" -le "$ALLOW" ]; then
        ok "--$V: 900-char task at --token-budget=600 fits the allowance ($BYTES <= $ALLOW B)"
    elif saysOverCeiling "$TMP/c.long"; then
        ok "--$V: 900-char task at --token-budget=600 is $BYTES B over $ALLOW B and DISCLOSES over_ceiling"
    else
        no "--$V: 900-char task at --token-budget=600 delivers $BYTES B past the $ALLOW B allowance in SILENCE"
    fi
done

# ═══ 4) M1 — the comment echo is CHARGED, observed where the budget actually BINDS ════════════════════════════
# The consequence of charging user-length header bytes is that a longer header buys a SMALLER payload. It is
# only observable where the budget binds: at a generous budget nothing is being trimmed, so a longer task just
# adds its own header bytes with nothing to repay from, and (a different query ranking different symbols) the
# payload can legitimately grow. An earlier draft of this arm measured at --token-budget=3000 and "failed" the
# fixed binary for exactly that reason — the premise, not the code, was wrong. So: only budgets at which the
# SHORT task is already capped count, and the payload (bytes after the header comment) is what is compared.
#
# --pack-task only, deliberately. It is M1's subject: it charged the attribute and not the echo. --for was
# MEASURED to charge its whole header exactly (a +1800 B header buys a -1765 B sigs trim at --token-budget=4000),
# so there is no undercharge there to detect, and its ceiling behaviour is what arm 3 covers.
for V in pack-task; do
    SEEN=0
    BAD=0
    for B in 1200 1600 2000; do
        "$BIN" "$CORPUS" --no-cache "--$V=shape the bundle"          --token-budget=$B >"$TMP/p.s" 2>/dev/null
        "$BIN" "$CORPUS" --no-cache "--$V=$( cat "$TMP/task.long" )" --token-budget=$B >"$TMP/p.l" 2>/dev/null
        # BINDING = the short task's own header already discloses a cut. Without that, this budget proves
        # nothing: an uncapped bundle has no payload to repay the header's growth from.
        hdr "$TMP/p.s" | grep -qE 'ranking: capped|kept [0-9]+ of|omitted \(budget\)' || continue
        PS=$(( $( wc -c < "$TMP/p.s" | tr -d ' ' ) - $( hdr "$TMP/p.s" | wc -c | tr -d ' ' ) ))
        PL=$(( $( wc -c < "$TMP/p.l" | tr -d ' ' ) - $( hdr "$TMP/p.l" | wc -c | tr -d ' ' ) ))
        SEEN=$(( SEEN + 1 ))
        [ "$PL" -le "$PS" ] || { BAD=$(( BAD + 1 )); echo "    --$V budget=$B: payload GREW with the task ($PS -> $PL B)"; }
    done
    if [ "$SEEN" = "0" ]; then
        no "--$V: no binding budget found in 1200..2000 — the charge arm proved nothing (fixture drifted)"
    elif [ "$BAD" = "0" ]; then
        ok "--$V: at all $SEEN binding budget(s), a 900-char task buys a SMALLER payload — the echo is charged"
    else
        no "--$V: at $BAD of $SEEN binding budget(s) a longer header bought MORE payload — bytes riding free"
    fi
done

# ═══ 5) M1 — --recall discloses over_ceiling against the --max-tokens budget it was shaped against ════════════
# RED: a 1500-char task at --max-tokens=200 delivers 4.2x the byte budget with no field saying so. The budget
# arithmetic (kRecallHeaderReserveBytes + task.size()) was already right; the DISCLOSURE was the gap.
python3 - "$TMP" <<'PY_EOF'
import os, sys
open( os.path.join( sys.argv[1], 'task.recall' ), 'wb' ).write(
    ( b'recall the budget notes about the header floor and the ceiling tolerance ' * 30 )[ :1500 ] )
PY_EOF
RT="$( cat "$TMP/task.recall" )"
for MT in 200 600 4000; do
    "$BIN" "$CORPUS" --no-cache --recall="$RT" --max-tokens=$MT >"$TMP/r.out" 2>/dev/null
    BYTES="$( wc -c < "$TMP/r.out" | tr -d ' ' )"
    MAXB="$( python3 -c "print(int($MT*2.36*0.90))" )"
    OVER=0;  head -1 "$TMP/r.out" | grep -q 'over_ceiling=1' && OVER=1
    if [ "$BYTES" -gt "$MAXB" ] && [ "$OVER" = "0" ]; then
        no "--recall(1500-char task) --max-tokens=$MT: $BYTES B past its $MAXB B budget with no over_ceiling="
    elif [ "$BYTES" -le "$MAXB" ] && [ "$OVER" = "1" ]; then
        no "--recall(1500-char task) --max-tokens=$MT: fits $MAXB B yet claims over_ceiling=1"
    else
        ok "--recall(1500-char task) --max-tokens=$MT: $BYTES B vs $MAXB B budget, over_ceiling=$OVER (consistent)"
    fi
done
# and the silence half: a SHORT task within budget must not carry the field at all (absent = measured-and-fine,
# the §P0.1 honest-limit convention — a field that is always present cannot mean anything)
"$BIN" "$CORPUS" --no-cache --recall="header floor" --max-tokens=4000 >"$TMP/r.short" 2>/dev/null
head -1 "$TMP/r.short" | grep -q 'over_ceiling' \
    && no "--recall: a short task inside its budget still emits over_ceiling — the field is decoration" \
    || ok "--recall: over_ceiling ABSENT on a short task inside its budget (silence means measured-and-fine)"

# ═══ 6) determinism under every hostile byte and every ceiling rung ═══════════════════════════════════════════
# The ladder picks a header shape by MEASURING candidates; a measurement that reads uninitialised or
# map-ordered state would show up here and nowhere else in the suite.
DET_BAD=0
for H in $HOSTILE long mid; do
    T="$( cat "$TMP/task.$H" )"
    for ARGS in "--for=$T" "--pack-task=$T" "--for=$T --token-budget=600" "--pack-task=$T --token-budget=600" "--pack-task=$T --token-budget=1200"; do
        # shellcheck disable=SC2086
        "$BIN" "$CORPUS" --no-cache $ARGS >"$TMP/d1" 2>/dev/null
        # shellcheck disable=SC2086
        "$BIN" "$CORPUS" --no-cache $ARGS >"$TMP/d2" 2>/dev/null
        cmp -s "$TMP/d1" "$TMP/d2" || { DET_BAD=$(( DET_BAD + 1 )); echo "    non-deterministic: $ARGS"; }
    done
done
[ "$DET_BAD" = "0" ] \
    && ok "det-gate: byte-identical run-to-run across every hostile byte x ceiling rung" \
    || no "det-gate: $DET_BAD argument set(s) are NOT byte-identical run-to-run"

# ═══ 7) the ladder's rungs are REACHABLE and correctly ordered ════════════════════════════════════════════════
# A remedy nothing ever selects is dead code that reads as a feature. Sweep a band of budgets and require that
# the cheap rung (drop the DUPLICATE comment echo, keeping the verbatim task= attribute) is actually taken
# somewhere — and that whenever it is, the verbatim attribute is still present. That ordering is the whole
# point: reclaim the duplicate before dropping unique information.
T="$( cat "$TMP/task.long" )"
ECHO_RUNG_SEEN=0
ECHO_RUNG_BAD=0
for B in 900 1100 1200 1400 1600 1800 2000; do
    for V in for pack-task; do
        "$BIN" "$CORPUS" --no-cache "--$V=$T" --token-budget=$B >"$TMP/l.out" 2>/dev/null
        hdr "$TMP/l.out" | grep -q 'task_echo: dropped' || continue
        ECHO_RUNG_SEEN=$(( ECHO_RUNG_SEEN + 1 ))
        # the verbatim copy must survive the drop of its scrubbed twin
        python3 - "$TMP/l.out" "$TMP/task.long" <<'PY_EOF' || {
import sys, xml.etree.ElementTree as ET
want = open( sys.argv[2], 'rb' ).read().decode( 'utf-8' )
got  = ET.parse( sys.argv[1] ).getroot().attrib.get( 'task' )
sys.exit( 0 if got == want else 1 )
PY_EOF
            ECHO_RUNG_BAD=$(( ECHO_RUNG_BAD + 1 ))
            echo "    --$V budget=$B: dropped the comment echo but the verbatim task= is gone or altered"
        }
    done
done
[ "$ECHO_RUNG_SEEN" -gt 0 ] \
    && ok "ceiling ladder: the task_echo rung is REACHABLE ($ECHO_RUNG_SEEN point(s) in the 900..2000 band)" \
    || no "ceiling ladder: the task_echo rung was never selected at any budget — an unreachable remedy"
[ "$ECHO_RUNG_BAD" = "0" ] \
    && ok "ceiling ladder: every echo-drop kept the VERBATIM task= attribute intact" \
    || no "ceiling ladder: $ECHO_RUNG_BAD echo-drop(s) also lost the verbatim task= — wrong bytes dropped"

# ═══ 8) the MCP SIBLING — the same hostile bytes through the live server ══════════════════════════════════════
# M3's scrub had to be applied at SIX echo sites, two of which are MCP-only (mcpverbs.h `for` and `exemplar`).
# A CLI-only gate would have left those two to be fixed by inspection and verified by hope. The task text there
# is agent-controlled, which is if anything the more hostile source, so the same encodings go through a real
# tools/call over stdin — the shape a client actually speaks.
python3 - "$BIN" "$CORPUS" <<'PY_EOF' \
    && ok "MCP for/exemplar/pack_task: every hostile encoding returns xmllint-clean, G4-clean XML" \
    || no "MCP for/exemplar/pack_task: a hostile task byte reached the reply — the CLI twin was fixed and this was not"
import json, re, subprocess, sys
BIN, CORPUS = sys.argv[1], sys.argv[2]
hostile = { 'nl': 'a\nb', 'tab': 'a\tb', 'c0': 'a' + chr( 1 ) + 'b', 'badu8': 'a\udcffb',
            'mixed': 'anchor--the\n' + chr( 1 ) + 'budget\tceiling' }
reqs = [ { "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {} } ]
rid, keys = 2, []
for name, task in hostile.items():
    for verb, arg in ( ( 'for', 'task' ), ( 'exemplar', 'kind_or_task' ), ( 'pack_task', 'task' ) ):
        reqs.append( { "jsonrpc": "2.0", "id": rid, "method": "tools/call",
                       "params": { "name": verb, "arguments": { arg: task } } } )
        keys.append( ( rid, verb, name ) );  rid += 1

blob = ''.join( json.dumps( r ) + '\n' for r in reqs ).encode( 'utf-8', 'surrogateescape' )
proc = subprocess.run( [ BIN, '--mcp', CORPUS ], input = blob, capture_output = True )
byId = {}
for line in proc.stdout.decode( 'utf-8', 'replace' ).splitlines():
    line = line.strip()
    if not line.startswith( '{' ): continue
    try:    reply = json.loads( line )
    except Exception: continue
    if 'id' in reply: byId[ reply['id'] ] = reply

bad, checked = 0, 0
for ( key, verb, name ) in keys:
    reply = byId.get( key )
    if reply is None:
        print( '    no reply for %s(%s) — the server died on a hostile byte' % ( verb, name ) );  bad += 1;  continue
    try:    body = reply['result']['content'][0]['text']
    except Exception: continue          # a refusal carries no document to malform
    if not body.lstrip().startswith( '<' ): continue
    checked += 1
    lint = subprocess.run( [ 'xmllint', '--noout', '-' ], input = body.encode( 'utf-8', 'surrogateescape' ),
                           capture_output = True )
    outside = '\n' in re.sub( r'<!\[CDATA\[.*?\]\]>', '', body, flags = re.S )
    if lint.returncode or outside:
        print( '    %s(%s): xmllint_rc=%d newline_outside_cdata=%s' % ( verb, name, lint.returncode, outside ) )
        bad += 1
if checked == 0:
    print( '    no MCP verb returned a document — the arm proved nothing' );  sys.exit( 1 )
sys.exit( 1 if bad else 0 )
PY_EOF

if [ "$fail" = "0" ]; then echo "w3fixbudgetcheck: ALL PASS"; else echo "w3fixbudgetcheck: FAILURES"; fi
exit "$fail"
