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
#        which is what monotonicity could never catch — a floor is monotone. (forbudget-soft: the explicit budget is
#        a soft target now, so the H2 arms assert the soft contract instead — see below.)
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
# forbudget-soft (rule 4, owner decisions 2026-10-14) RETIRED the absolute-ceiling invariant these arms were built on.
# An explicit --token-budget on --for / --pack-task is now a SOFT target: T = N x kMinBytesPerToken x kBudgetHeadroom bytes
# charged against the ranked ROWS only (--for), or each section stopping once its share is reached (--pack-task). There is
# no byte promise, so nothing is labelled over_ceiling and nothing in the header — the verbatim task echo, route=, any
# legend clause — is ever dropped "(ceiling)" to fit. So the H2 arms no longer assert "fits ceiling x 1.15 <=> discloses
# over_ceiling"; at every (task length x budget x lens) point they assert what must hold now:
#   ST    (--for) the rows' charged bytes inside <sigs> fit T, or are only the rank 1..4 floor;
#   RP    the served rows are a rank prefix of the default answer's rows, growing with the budget (--pack-task: a growing
#         prefix in SCORE order, and each answer a disclosed pure reorder of that prefix — see "H2's RED CELL" below);
#   NX    (--for) every cut element (capped="1") carries next=;
#   NOLBL no over_ceiling= on the root and no over_ceiling ladder note;
#   HL    no "(ceiling)" drop and no "task_echo: dropped" in the header; task= verbatim; route= kept when the default has it.
# The user-text findings (M2/M3 hostile bytes, the M1 charge, the --recall disclosure, determinism) are unchanged:
# --recall --max-tokens keeps its hard ceiling and its biconditional (arm 5).
#
# H2's RED CELL, CLOSED 2026-11-21 (it was acked on integration/070-1120, owner ruling 105). THE CELL: lens --pack-task,
# task `mid`, budget 3000 against the 1600 step below — `the 9 row(s) served do not extend the 4 served at the budget below`.
# WHAT WAS SERVED (binary 5000f06af, this gate's corpus; names abbreviated, D = a docs/BUDGET_NOTES.md row):
#     score order (both reorder handles off)   render shape disclosure D:BUDGET_NOTES D D remaining ceiling headerFloor
#     --pack-task --token-budget=1600          render shape disclosure D:BUDGET_NOTES          <sigs shown="4" total="9" capped="1">
#     --pack-task --token-budget=3000          render shape disclosure remaining ceiling headerFloor D D D   <sigs docs_after_code="3">
# Both answers are exactly what the product documents. The byte ladder picks the shown set in SCORE order — 4 rows at
# 1600, all 9 at 3000, the first a prefix of the second — and code-above-docs then reorders the SHOWN set (filter.h: "the
# same rows, only reordered ... the reorder never evicts a doc row"), renumbering r= and saying so in docs_after_code=.
# At 1600 the one doc row shown is already last, so nothing moves; at 3000 three move below the code. The r= this gate
# read is the DISPLAY rank, so it compared one answer before the permutation with one after it.
# WHY IT WENT RED WHEN IT DID: this arm was written (77e225588, 2026-10-14) on the stated premise that "an explicit
# budget's answer does not [reorder]" — true then, because --pack-task handed the caller's budget to
# docsAfterCodeFitsCeiling and every budget on this grid is tighter than the default share. 34be00d0f (2026-11-19, "the
# head's lens rules are the LENS's, not the caller's budget's") deliberately passes 0 there, so an explicit budget's head
# takes the default's rules; its message lists the gates it re-ran and this one is not among them. The premise is in the
# gate, so the defect is the gate's: RP for --pack-task was asserted on a rank the product is documented to permute.
# THE FIX KEEPS THE FACT AND ADDS TWO. Per --pack-task point the gate now also serves the SCORE-ORDER TWIN (the same call
# under RIPWIRE_NO_DOCS_AFTER_CODE=1 RIPWIRE_NO_HEAD_RR=1, the product's own A/B handles for the two shown-set reorders):
#   RP   the twin's rows extend the twin's rows at the budget below      — the growing rank prefix, on the rank the ladder cuts by;
#   T1   the served rows are the twin's rows as a SET, none added or lost — the reorder is pure (new; the legend's own claim);
#   T2   a served order that differs from the twin's is DISCLOSED on <sigs> (docs_after_code= or files_first=) — new.
# So display-order prefix is no longer demanded where a disclosed reorder sits between two budgets, and that is the whole
# relaxation; --for is judged exactly as before (its soft cut is taken after the reorder, so its display order IS a
# prefix, and stays pinned). A relaxed comparison is proved by MUTATION NEGATIVE CONTROL, and the arm carries four, run
# on the cell that was red: the rank-4 row swapped for rank 5 (the old symptom, in score order), the head two rows
# transposed, one row deleted from the served answer (T1), the disclosure attribute stripped (T2) — each must go red.
# The grid is still 24 points and no point, lens or budget was dropped.
# NOT DECIDED HERE, reported for the owner: at the same explicit budget --for and --pack-task now fill the rank 1..4 floor
# differently on a question whose 4th-scored row is a doc (--for cuts after the reorder and serves `remaining`,
# --pack-task cuts before it and serves the doc heading). Each matches its own written contract; whether they should
# match each other is a product question, and this gate pins neither answer to it.

set -u
# FMT2 (ROWLINES + RANKSEQ, src/forrowlines.h): the default answer-first --for answer serves its <sigs>/<tail> rows as text lines in
# one CDATA (lossless; test/rowlinescheck.sh pins it: (L1) decodes the answer back to this element form byte for byte). This gate
# reads those rows as elements for another rule, so the line form is off here.
export RIPWIRE_NO_ROWLINES=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
# quotes the word — this gate's own corpus does, deliberately, so that mistake cannot pass unnoticed. The charge
# arm (4) reads the header region ONLY: everything up to the first "-->" (arms 3 and 7 read every header comment).
hdr(){ python3 -c "
import sys
d = open( sys.argv[1], 'rb' ).read()
i = d.find( b'-->' )
sys.stdout.buffer.write( d if i < 0 else d[ :i + 3 ] )" "$1"; }

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

# ═══ 3) H2 — THE SOFT TARGET, across task length x budget ════════════════════════════════════════════════════
# forbudget-soft (rule 4) — REPLACES the absolute ceiling biconditional (delivered > B x 2.36 x 1.15 <=> over_ceiling, and
# over_ceiling <=> est_tokens > budget_tokens; re-pinned 2026-09-05 for F2). An explicit --token-budget is a soft target
# now, so a bundle past B x 2.36 x 1.15 is legitimate (the header always ships; the floor rows always ship) and a label is
# never legitimate. Kept from the old arm: the 24-point grid (tasks mid/long x 300..3000 x both lenses) and the premise
# that the root prints a numeric est_tokens=. Per point: ST + RP + NX (--for), RP (--pack-task), NOLBL + HL (both).
srcnum(){ sed -n "s/^inline constexpr [a-z:_ ]*$1 *= *\([0-9.]*\);.*/\1/p" "$ROOT/src/serialize.h" | head -1; }
MINBPT="$( srcnum kMinBytesPerToken )";  HEADROOM="$( srcnum kBudgetHeadroom )"
case "$MINBPT$HEADROOM" in ''|*[!0-9.]*) no "H2: cannot read kMinBytesPerToken/kBudgetHeadroom from src/serialize.h ('$MINBPT' '$HEADROOM') — the ST arm has no target to judge" ;; esac
SOFT="$TMP/soft.py"
cat > "$SOFT" <<'PY_EOF'
# soft.py DOC DEFAULT_DOC TASKFILE LENS T  — prints "k=<rows served>", one "row p:l:n" per served row in rank order, then
# one line per violation; exit 1 on any
import re, sys, xml.etree.ElementTree as ET
doc, ref, taskFile, lens, T = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int( float( sys.argv[5] ) )
raw = open( doc, 'rb' ).read()
bad = []
if not raw:
    print( 'k=0' ); print( '    no document' ); sys.exit( 1 )
s = raw.decode( 'utf-8', 'replace' )
comments = ' '.join( re.findall( r'<!--(.*?)-->', s, re.S ) )
def strip( t ):
    t = re.sub( r'<!\[CDATA\[.*?\]\]>', '', t, flags = re.S )
    return re.sub( r'<!--.*?-->', '', t, flags = re.S )   # the legend quotes <sigs> and defines attributes; it is not the document's tags
body = strip( s )
root = re.search( r'<ctx\b[^>]*>', body )
if root is None:
    print( 'k=0' ); print( '    no <ctx> root' ); sys.exit( 1 )
root = root.group( 0 )
# a row's CHARGE is the ladder's (serialize.h entryCost): its printed bytes plus the zero cx=/ccx=/in= the lean spelling elides
def charge( a, printed ):
    return printed + sum( n for k, n in ( ( 'cx', 7 ), ( 'ccx', 8 ), ( 'in', 7 ) ) if not re.search( r'\b' + k + r'="', a ) )
def rowsOf( t ):
    m = re.search( r'<sigs\b([^>]*)>(.*?)</sigs>', t, re.S )
    if not m: return None, None, 0
    rows, total = [], 0
    for d in re.finditer( r'<d ([^>]*)>.*?</d>|<d ([^>]*)/>', m.group( 2 ), re.S ):
        a = d.group( 1 ) or d.group( 2 )
        g = lambda k: ( re.search( r'\b' + k + r'="([^"]*)"', a ) or [ None, '?' ] )[ 1 ]
        r = g( 'r' )
        c = charge( a, len( d.group( 0 ).encode() ) )
        total += c - len( d.group( 0 ).encode() )
        rows.append( ( int( r ) if r.isdigit() else 10**9, g( 'p' ) + ':' + g( 'l' ) + ':' + g( 'n' ) ) )
    rows.sort()
    return m.group( 1 ), rows, len( m.group( 2 ).encode() ) + total
sigAttrs, rows, charged = rowsOf( body )
refAttrs, refRows, _ = rowsOf( strip( open( ref, 'rb' ).read().decode( 'utf-8', 'replace' ) ) )
k = len( rows ) if rows is not None else 0
print( 'k=%d' % k )
for _, x in ( rows or [] ): print( 'row ' + x )
# est_tokens present and numeric (CHECKLIST 14: a missing premise is a FAIL)
if not re.search( r' est_tokens="\d+"', root ): bad.append( 'the root carries no numeric est_tokens=' )
# NOLBL
if ' over_ceiling="1"' in root:         bad.append( 'over_ceiling="1" on a soft target (est_tokens may exceed budget_tokens; no label)' )
if re.search( r'over_ceiling:', comments ): bad.append( 'an over_ceiling ladder note rides the header' )
# HL
if '(ceiling)' in comments:
    dropped = sorted( set( re.findall( r'([^\[\]]{0,40}) dropped \(ceiling\)', comments ) ) )
    bad.append( 'a header piece was dropped "(ceiling)": %s' % ( ', '.join( dropped ) or 'see header' ) )
if 'task_echo: dropped' in comments:    bad.append( 'the task echo was dropped' )
want = open( taskFile, 'rb' ).read().decode( 'utf-8' )
try:
    got = ET.fromstring( raw ).attrib.get( 'task' )
except Exception as exc:
    got = None; bad.append( 'the document does not parse as XML: %s' % ( exc, ) )
if got is not None and got != want:     bad.append( 'task= is not the verbatim task (%d chars vs %d)' % ( len( got ), len( want ) ) )
refRoot = re.search( r'<ctx\b[^>]*>', strip( open( ref, 'rb' ).read().decode( 'utf-8', 'replace' ) ) )
if refRoot and ' route=' in refRoot.group( 0 ) and ' route=' not in root: bad.append( 'route= dropped (the default answer carries it)' )
# RP
if rows is None or refRows is None:     bad.append( 'no <sigs> block (served %s, default %s) — no rows to judge' % ( rows is not None, refRows is not None ) )
else:
    if k == 0:                          bad.append( 'no row served — the rank 1..4 floor always ships' )
    if [ r for r, _ in rows ] != list( range( 1, k + 1 ) ): bad.append( 'rows are not the ranks 1..%d: r=%s' % ( k, [ r for r, _ in rows ] ) )
    # the default answer may move its doc rows below its code rows (docs_after_code=, renumbering r=). A --pack-task
    # answer under an explicit budget reorders ITS OWN shown set the same way since 34be00d0f — which is a no-op while its
    # doc rows are already last — so against a reordered default the rows are judged as a SET here, and the rank PREFIX is
    # judged across budgets by the caller: on the display rows for --for, on the score-order twin for --pack-task (twin.py)
    if refAttrs is not None and 'docs_after_code=' in refAttrs:
        extra = set( x for _, x in rows ) - set( x for _, x in refRows )
        if extra: bad.append( 'rows the default answer does not serve: %s' % sorted( extra )[ :3 ] )
    elif [ x for _, x in rows ] != [ x for _, x in refRows[ :k ] ]: bad.append( 'rows are not the default answer\'s first %d rows' % k )
    if k < min( 4, len( refRows ) ):    bad.append( 'only %d row(s): the rank 1..4 floor always ships' % k )
if lens == 'for' and rows is not None:
    # ST: the rows' charged bytes fit T, or are only the floor
    if not ( charged <= T or k <= 4 ): bad.append( 'ST: %d rows charge %d B past the %d B soft target (beyond the 4-row floor)' % ( k, charged, T ) )
    # NX: every cut section carries next= (the ranked rows, the hop rows, the file tail — the continuations --for promises)
    for m in re.finditer( r'<(sigs|hops|tail)\b([^>]*)\bcapped="1"([^>]*)>', body ):
        if ' next="' not in m.group( 2 ) + m.group( 3 ): bad.append( 'NX: <%s capped="1"> carries no next=' % m.group( 1 ) )
for line in bad: print( '    ' + line )
sys.exit( 1 if bad else 0 )
PY_EOF
# twin.py SERVED TWIN — the --pack-task reorder arms. Prints one "trow p:l:n" per TWIN row in its (score) order, then
# "reordered=0|1", then one line per violation; exit 1 on any. TWIN is the same call with both shown-set reorders off.
TWIN="$TMP/twin.py"
cat > "$TWIN" <<'PY_EOF'
import re, sys
def rowsOf( path ):
    t = open( path, 'rb' ).read().decode( 'utf-8', 'replace' )
    t = re.sub( r'<!\[CDATA\[.*?\]\]>', '', t, flags = re.S )
    t = re.sub( r'<!--.*?-->', '', t, flags = re.S )
    m = re.search( r'<sigs\b([^>]*)>(.*?)</sigs>', t, re.S )
    if not m: return None, None
    rows = []
    for d in re.finditer( r'<d ([^>]*)>.*?</d>|<d ([^>]*)/>', m.group( 2 ), re.S ):
        a = d.group( 1 ) or d.group( 2 )
        g = lambda k: ( re.search( r'\b' + k + r'="([^"]*)"', a ) or [ None, '?' ] )[ 1 ]
        rows.append( ( int( g( 'r' ) ) if g( 'r' ).isdigit() else 10**9, g( 'p' ) + ':' + g( 'l' ) + ':' + g( 'n' ) ) )
    rows.sort()
    return m.group( 1 ), [ x for _, x in rows ]
attrs, served = rowsOf( sys.argv[1] )
tAttrs, twin  = rowsOf( sys.argv[2] )
bad = []
if served is None or twin is None:
    print( 'reordered=0' ); print( '    twin: no <sigs> block (served %s, twin %s)' % ( served is not None, twin is not None ) ); sys.exit( 1 )
for x in twin: print( 'trow ' + x )
reordered = served != twin
print( 'reordered=%d' % reordered )
# the twin must BE the score order: a reorder disclosure on it means a handle stopped working and the twin proves nothing
if re.search( r'\b(docs_after_code|files_first)="', tAttrs ): bad.append( 'twin: the reorder-free twin itself discloses a reorder (<sigs%s>) — an A/B handle is not honoured' % tAttrs )
# T1: the same rows, none added, none lost, none repeated
if sorted( served ) != sorted( twin ):
    bad.append( 'T1: the served rows are not the score-order twin\'s rows as a set (%d served, %d twin; only served %s; only twin %s)' % (
        len( served ), len( twin ), sorted( set( served ) - set( twin ) )[ :2 ], sorted( set( twin ) - set( served ) )[ :2 ] ) )
# T2: a different order is a DISCLOSED one
elif reordered and not re.search( r'\b(docs_after_code|files_first)="[1-9]', attrs ):
    bad.append( 'T2: the rows are served in a different order than their score order and <sigs%s> discloses no reorder' % attrs )
for line in bad: print( '    ' + line )
sys.exit( 1 if bad else 0 )
PY_EOF
# does the row list in file $2 extend the one in file $1 — at least as long, and $1 is its head, line for line?
extends(){
    local n;  n="$( wc -l < "$1" | tr -d ' ' )"
    [ "$( wc -l < "$2" | tr -d ' ' )" -ge "$n" ] && [ "$( awk -v n="$n" 'NR <= n' "$2" )" = "$( cat "$1" )" ]
}
SOFT_POINTS=0;  SOFT_BAD=0;  SOFT_BINDS=0;  SOFT_REORDERED=0;  SOFT_TWINS=0
for TASKFILE in mid long; do
    T="$( cat "$TMP/task.$TASKFILE" )"
    for V in for pack-task; do
        "$BIN" "$CORPUS" --no-cache "--$V=$T" >"$TMP/c.def" 2>/dev/null   # the default answer: RP's reference rows
        PREVK=0;  : > "$TMP/rows.prev"
        for B in 300 600 900 1200 1600 3000; do
            "$BIN" "$CORPUS" --no-cache "--$V=$T" --token-budget=$B >"$TMP/c.out" 2>/dev/null
            TB="$( python3 -c "import sys; print(int(float(sys.argv[1])*float(sys.argv[2])*float(sys.argv[3])))" "$B" "${MINBPT:-0}" "${HEADROOM:-0}" )"
            SOFT_POINTS=$(( SOFT_POINTS + 1 ))
            OUT="$( python3 "$SOFT" "$TMP/c.out" "$TMP/c.def" "$TMP/task.$TASKFILE" "$V" "$TB" )";  RC=$?
            K="$( printf '%s\n' "$OUT" | sed -n 's/^k=//p' | head -1 )"
            # the rows RP is judged on across budgets: the DISPLAY rows for --for; for --pack-task the SCORE-ORDER twin's
            # (header, "H2's RED CELL"), with T1/T2 tying the served answer to that twin at this point
            TRC=0;  TW="";  ORDER="display"
            if [ "$V" = "pack-task" ]; then
                RIPWIRE_NO_DOCS_AFTER_CODE=1 RIPWIRE_NO_HEAD_RR=1 "$BIN" "$CORPUS" --no-cache "--$V=$T" --token-budget=$B >"$TMP/c.twin" 2>/dev/null
                TW="$( python3 "$TWIN" "$TMP/c.out" "$TMP/c.twin" )";  TRC=$?
                ORDER="score";  SOFT_TWINS=$(( SOFT_TWINS + 1 ))
                printf '%s\n' "$TW" | sed -n 's/^trow //p' > "$TMP/rows.cur"
                if printf '%s\n' "$TW" | grep -q '^reordered=1$'; then
                    SOFT_REORDERED=$(( SOFT_REORDERED + 1 ))
                    # the negative controls below run on the FIRST reordered point and the step under it
                    [ -s "$TMP/n.cur" ] || [ ! -s "$TMP/rows.prev" ] || { cp "$TMP/rows.prev" "$TMP/n.prev";  cp "$TMP/rows.cur" "$TMP/n.cur";  cp "$TMP/c.out" "$TMP/n.out";  cp "$TMP/c.twin" "$TMP/n.twin";  NEG_CELL="task=$TASKFILE budget=$B"; }
                fi
            else
                printf '%s\n' "$OUT" | sed -n 's/^row //p' > "$TMP/rows.cur"
            fi
            if [ "$RC" != 0 ] || [ "$TRC" != 0 ]; then
                SOFT_BAD=$(( SOFT_BAD + 1 ))
                echo "    --$V task=$TASKFILE budget=$B (T=$TB B):";  printf '%s\n' "$OUT" | grep -v '^k=\|^row ';  printf '%s\n' "$TW" | grep '^    '
            elif [ "${K:-0}" -lt "$PREVK" ] || ! extends "$TMP/rows.prev" "$TMP/rows.cur"; then
                SOFT_BAD=$(( SOFT_BAD + 1 ))
                echo "    --$V task=$TASKFILE budget=$B: the $K row(s) served do not extend the $PREVK served at the budget below ($ORDER order) — RP is not a growing rank prefix"
            fi
            cp "$TMP/rows.cur" "$TMP/rows.prev"
            # non-vacuity: a point whose est_tokens is past its budget (so NOLBL was tested on a blown target, not assumed)
            EST="$( perl -0pe 's#<!--.*?-->##gs' "$TMP/c.out" | grep -oE '<ctx( [^>]*)?>' | head -1 | grep -oE ' est_tokens="[0-9]+"' | tr -dc '0-9' )"
            [ -n "$EST" ] && [ "$EST" -gt "$B" ] && SOFT_BINDS=$(( SOFT_BINDS + 1 ))
            PREVK="${K:-0}"
        done
    done
done
[ "$SOFT_BAD" = "0" ] \
    && ok "H2 soft target: ST/RP/NX/NOLBL/HL hold at all $SOFT_POINTS (task length x budget x lens) points (--pack-task: RP in score order, T1/T2 at each of its $SOFT_TWINS)" \
    || no "H2 soft target: VIOLATED at $SOFT_BAD of $SOFT_POINTS points"
[ "$SOFT_BINDS" -gt 0 ] \
    && ok "H2 soft target: non-vacuity — $SOFT_BINDS point(s) deliver est_tokens past their budget (NOLBL/HL were judged on blown targets)" \
    || no "H2 soft target: VACUOUS — no point delivers past its budget, so no-label/header-kept was never tested on a blown target"
# --pack-task's RP is judged on the score-order twin, so the arm owes two proofs that it is not looser than it reads:
# that some point really IS served reordered (else T1/T2 were never exercised and the twin is the answer itself), and
# that each comparison still fails when the one fact it reads is broken (a relaxation's proof is a mutation control).
[ "$SOFT_REORDERED" -gt 0 ] \
    && ok "H2 --pack-task reorder: non-vacuity — $SOFT_REORDERED of $SOFT_TWINS point(s) are served in an order other than their score order (T1 pure-reorder and T2 disclosed were judged on a real reorder)" \
    || no "H2 --pack-task reorder: VACUOUS — 0 of $SOFT_TWINS points are served reordered, so T1/T2 judged nothing and the negative controls have no cell to run on"
if [ -s "$TMP/n.cur" ] && [ -s "$TMP/n.prev" ]; then
    NP="$( wc -l < "$TMP/n.prev" | tr -d ' ' )"
    extends "$TMP/n.prev" "$TMP/n.cur" \
        && ok "H2 (RPn) control premise: on the cell that was red (--pack-task $NEG_CELL) the score-order rows DO extend the $NP below" \
        || no "H2 (RPn) control premise: the unmutated score-order rows do not extend the step below on --pack-task $NEG_CELL — the controls below prove nothing"
    # (RPn1) the old symptom, in score order: rank NP's row gone, rank NP+1 in its place
    awk -v n="$NP" 'NR != n' "$TMP/n.cur" > "$TMP/n.m1"
    extends "$TMP/n.prev" "$TMP/n.m1" \
        && no "H2 (RPn1) negative control: with the rank-$NP row replaced by the rank after it the rows still 'extend' the step below — RP cannot go red" \
        || ok "H2 (RPn1) negative control: RP fails when the rank-$NP row is replaced by the rank after it"
    # (RPn2) the head two rows transposed
    awk 'NR == 1 { a = $0; next } NR == 2 { print; print a; next } { print }' "$TMP/n.cur" > "$TMP/n.m2"
    extends "$TMP/n.prev" "$TMP/n.m2" \
        && no "H2 (RPn2) negative control: with ranks 1 and 2 transposed the rows still 'extend' the step below — RP cannot go red" \
        || ok "H2 (RPn2) negative control: RP fails when ranks 1 and 2 are transposed"
    # (T1n) one row deleted from the SERVED answer's <sigs>
    python3 - "$TMP/n.out" "$TMP/n.m3" <<'PY_EOF'
import re, sys
s = open( sys.argv[1], 'rb' ).read().decode( 'utf-8', 'replace' )
m = re.search( r'(<sigs\b[^>]*>)(.*?)(</sigs>)(?!.*</sigs>)', s, re.S )
rows = list( re.finditer( r'<d [^>]*>.*?</d>|<d [^>]*/>', m.group( 2 ), re.S ) )
cut = rows[ -1 ]
open( sys.argv[2], 'wb' ).write( ( s[ :m.start( 2 ) + cut.start() ] + s[ m.start( 2 ) + cut.end(): ] ).encode() )
PY_EOF
    T1N="$( python3 "$TWIN" "$TMP/n.m3" "$TMP/n.twin" )"
    printf '%s\n' "$T1N" | grep -q '^    T1:' \
        && ok "H2 (T1n) negative control: T1 fails when one row is deleted from the served answer" \
        || no "H2 (T1n) negative control: one row deleted from the served answer and T1 did not fire: $( printf '%s' "$T1N" | grep -v '^trow ' | tr '\n' ' ' )"
    # (T2n) the reorder disclosure stripped from the SERVED answer's <sigs> tag (the rows stay reordered)
    perl -0pe 's#(<sigs\b[^>]*?) (?:docs_after_code|files_first)="[0-9]+"#$1#g' "$TMP/n.out" > "$TMP/n.m4"
    T2N="$( python3 "$TWIN" "$TMP/n.m4" "$TMP/n.twin" )"
    printf '%s\n' "$T2N" | grep -q '^    T2:' \
        && ok "H2 (T2n) negative control: T2 fails when the reorder is served without docs_after_code=/files_first=" \
        || no "H2 (T2n) negative control: the disclosure was stripped from a reordered answer and T2 did not fire: $( printf '%s' "$T2N" | grep -v '^trow ' | tr '\n' ' ' )"
    # and the unmutated cell passes the same reader — the controls above are red for the mutation, not for the cell
    python3 "$TWIN" "$TMP/n.out" "$TMP/n.twin" >/dev/null \
        && ok "H2 (T1/T2) on the unmutated cell: the served answer is a disclosed pure reorder of its score-order twin" \
        || no "H2 (T1/T2) on the unmutated cell: twin.py rejects the answer the controls were built from"
else
    no "H2 (RPn/T1n/T2n) negative controls DID NOT RUN: no --pack-task point is served reordered with a budget step below it, so nothing proves the score-order arms can go red"
fi

# the case named in the finding, asserted on its own so a regression names itself. forbudget-soft (rule 4) — REPLACES
# "a 900-char task at --token-budget=600 fits B x 2.36 x 1.15 or discloses over_ceiling": the soft target makes no byte
# promise, so what must hold is that the floor rows are served and the header ships whole (task= verbatim, echo kept,
# route= kept, nothing dropped "(ceiling)"), with no label.
T="$( cat "$TMP/task.long" )"
for V in for pack-task; do
    "$BIN" "$CORPUS" --no-cache "--$V=$T"                    >"$TMP/c.ldef" 2>/dev/null
    "$BIN" "$CORPUS" --no-cache "--$V=$T" --token-budget=600 >"$TMP/c.long" 2>/dev/null
    TB="$( python3 -c "import sys; print(int(600*float(sys.argv[1])*float(sys.argv[2])))" "${MINBPT:-0}" "${HEADROOM:-0}" )"
    OUT="$( python3 "$SOFT" "$TMP/c.long" "$TMP/c.ldef" "$TMP/task.long" "$V" "$TB" )";  RC=$?
    K="$( printf '%s\n' "$OUT" | sed -n 's/^k=//p' | head -1 )"
    if [ "$RC" = 0 ]; then
        ok "--$V: 900-char task at --token-budget=600 serves its $K floor row(s) with the header whole and no over_ceiling ($( wc -c < "$TMP/c.long" | tr -d ' ' ) B; no byte promise)"
    else
        no "--$V: 900-char task at --token-budget=600:";  printf '%s\n' "$OUT" | grep -v '^k=\|^row '
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
        # L1 (2026-09-19): the CLI default legend is compact; the binding test below reads the full header's cut notes
        # ("ranking: capped", "kept N of", "omitted (budget)"), which the compact dialect does not print, so it asks for them.
        "$BIN" "$CORPUS" --no-cache "--$V=shape the bundle"          --token-budget=$B --legend=full >"$TMP/p.s" 2>/dev/null
        "$BIN" "$CORPUS" --no-cache "--$V=$( cat "$TMP/task.long" )" --token-budget=$B --legend=full >"$TMP/p.l" 2>/dev/null
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
[ -s "$TMP/r.short" ] || no "zero-evidence premise (w3fixbudgetcheck.sh:574): the file the next arm judges is empty, so its verdict proves nothing"
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

# ═══ 7) the header is NEVER dropped for a soft target ═══════════════════════════════════════════════════════════
# forbudget-soft (rule 4) — REPLACES "the ceiling ladder's task_echo rung is REACHABLE" (and folds in its second half, "every
# echo-drop kept the verbatim task="). The header ladder existed to land a HARD ceiling; an explicit --token-budget is a soft
# target now, so the remedy that arm required to be reachable must now be unreachable. HL, across the same band and in the
# full dialect (the only one that echoes the task into the header comment): at every point `task_echo: dropped` is ABSENT,
# no header piece is dropped "(ceiling)", the comment echo is PRESENT, and the verbatim task= attribute is intact.
T="$( cat "$TMP/task.long" )"
ECHO_POINTS=0
ECHO_BAD=0
for B in 900 1100 1200 1400 1600 1800 2000; do
    for V in for pack-task; do
        "$BIN" "$CORPUS" --no-cache "--$V=$T" --token-budget=$B --legend=full >"$TMP/l.out" 2>/dev/null
        ECHO_POINTS=$(( ECHO_POINTS + 1 ))
        python3 - "$TMP/l.out" "$TMP/task.long" <<'PY_EOF' || { ECHO_BAD=$(( ECHO_BAD + 1 )); echo "      ^ --$V budget=$B"; }
import re, sys, xml.etree.ElementTree as ET
raw  = open( sys.argv[1], 'rb' ).read()
want = open( sys.argv[2], 'rb' ).read().decode( 'utf-8' )
if not raw:
    print( '    no document' );  sys.exit( 1 )
s    = raw.decode( 'utf-8', 'replace' )
com  = re.findall( r'<!--(.*?)-->', s, re.S )
bad  = []
if any( 'task_echo: dropped' in c for c in com ): bad.append( 'task_echo: dropped — the comment echo was dropped for a soft target' )
if any( '(ceiling)' in c for c in com ):          bad.append( 'a header piece was dropped "(ceiling)"' )
if not any( want[ :60 ] in c for c in com ):      bad.append( 'the header comment does not echo the task' )
try:
    got = ET.fromstring( raw ).attrib.get( 'task' )
except Exception as exc:
    got = None;  bad.append( 'the document does not parse as XML: %s' % ( exc, ) )
if got is not None and got != want:               bad.append( 'the verbatim task= is gone or altered' )
for line in bad: print( '    ' + line )
sys.exit( 1 if bad else 0 )
PY_EOF
    done
done
[ "$ECHO_POINTS" -gt 0 ] && [ "$ECHO_BAD" = "0" ] \
    && ok "header kept: at all $ECHO_POINTS points of the 900..2000 band (full dialect) the task echo, every header piece and the verbatim task= ship" \
    || no "header kept: $ECHO_BAD of $ECHO_POINTS point(s) dropped part of the header for a soft target"

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
