#!/usr/bin/env bash
# formaxtokenscheck.sh — issue #61: `--for --detail=N --max-tokens=N` names a ceiling it did not apply.
#
# Usage:
#   test/formaxtokenscheck.sh                                  # uses build/ripwire
#   test/formaxtokenscheck.sh asan/ripwire
#   RIPWIRE_BIN=build_base/ripwire test/formaxtokenscheck.sh    # red-first: arms A/D MUST fail here
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# DO NOT edit regression.sh beyond adding this gate's name — this is a standalone gate invoked from there.
#
# WHY THIS GATE EXISTS. Reported by YogevKr as redhat-et/ripwire#61 (2026-09-08, v0.5.0), the third of
# three honesty-class issues from the same reporter, and reproduced verbatim on 2026-09-09: on a corpus of
# 30 tiny TypeScript functions, `--for=Q --detail=30 --max-tokens=300` printed `max_tokens="300"` on the
# <ctx> root and delivered `est_tokens="2640"` — 8.8x the ceiling it named — with no over_ceiling= anywhere.
# The flag was not inert (it shapes the body count, and `<bodies capped="1">` disclosed THAT cut honestly);
# what it does not do is bound the document, because src/verbs_for.h turns it into a budget over the BODIES
# alone. Signatures, header, legend and symbol table are never charged against it. METHODOLOGY §9 #6 states
# the defect in one sentence: "a ceiling attribute names the ceiling actually applied."
#
# THE FIX IS DISCLOSURE, NOT ENFORCEMENT, and this gate is written to hold that line. §9 #2: "when a ceiling
# would cut something above the cliff, compress first, move prose into attributes second, and if it still
# does not fit, exceed the ceiling with over_ceiling="1" rather than drop the row that would have terminated
# the search." Thirty small functions totalling ~3.4K tokens, complete, ARE the terminating answer; a rung
# that hard-trimmed them to 300 tokens would make the tool worse and would still be honest. So no arm here
# asserts a byte bound. Every arm asserts the same biconditional the sibling budget verbs already hold:
#
#       est_tokens > the ceiling on this root   <=>   the root carries over_ceiling="1"
#
# A one-sided arm would be satisfied by the pre-fix binary (never label) or by a binary that labels every
# document (honest but useless), so both directions are checked, at points where each is reachable.
#
# THE FOUR ARMS, and what each one alone would miss:
#   (A) PRESENCE + CONTROL, swept.  The biconditional across a band of --max-tokens that contains BOTH
#       states. A presence-only arm passes on an unconditional attribute; a control-only arm passes on the
#       pre-fix binary. Non-vacuity is asserted: the band must contain at least one over point and at least
#       one fitting point, or the fixture has drifted and the arm proved nothing.
#   (B) SILENCE.  No --max-tokens at all => neither max_tokens= nor over_ceiling= on the root. Absent means
#       "none was asked for", never "not measured" (the §P0.1 honest-limit convention).
#   (C) BYTE ACCOUNTING.  est_tokens is re-derived from the delivered document at the two rates the emitter
#       prices in — markup at kBytesPerTokenDefault (2.50), the <bodies> section at kBytesPerTokenBody
#       (3.80) — and must match EXACTLY, at every point including the labelled ones. This is the arm that
#       catches a disclosure that is emitted but not charged: over_ceiling="1" is 17 bytes and its legend
#       clause ~50 more, and a number that prices the document without them is wrong in the one place it
#       most matters — the number that says the ceiling was blown. (src/verbs_for.h's JSON dialect was
#       fixed for exactly this shape; §H7 is the family.)
#   (D) LEGEND.  The attribute is defined by the legend of the document that carries it, against the
#       ceiling ACTUALLY on that root — max_tokens, budget_tokens, or both when both were asked for — and
#       a document inside its ceiling pays none of those bytes.
#   (E) --token-budget INTEROP.  forbudget-soft (rule 4, owner decisions 2026-10-14): an explicit --token-budget on
#       --for is a SOFT row target, never a ceiling this root labels against — so alone it carries no over_ceiling=
#       (est_tokens may exceed budget_tokens), and beside --max-tokens the label answers to max_tokens ONLY and its
#       legend says so. The served rows are a rank prefix that grows with the target, untouched by --max-tokens.
#       (Was: "the budget contract is unchanged, and with both flags set the label answers to EITHER ceiling".)
#   (F) DETERMINISM across the band, and (G) MUTATION CONTROLS: every judge above is re-run over a
#       deliberately corrupted copy of a real document and must go RED. An arm that cannot fail is not a
#       gate, and three of these four judges are cheap to write in an always-true form.
#
# THE TRAP THIS GATE STEPS AROUND (src/verbs_for.h:719, and w3fixbudgetcheck's saysOverCeiling before it):
# the legend DEFINES over_ceiling=, so `grep over_ceiling` matches the definition and reads it as the label.
# Every presence test here reads the ROOT ELEMENT'S ATTRIBUTES through a real XML parser, never the text.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "formaxtokenscheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "formaxtokenscheck: python3 is required (XML parse-back + re-derivation arms)"; exit 2; }

echo "formaxtokenscheck: BIN=$BIN"

# ── the corpus: the reporter's shape, in its own tree so the arms do not move when src/ does. Thirty tiny
#    TypeScript functions — small enough that the COMPLETE answer is cheap (which is the whole argument for
#    disclosing rather than trimming), numerous enough that --detail=30 has something for --max-tokens to
#    shape, and all matching one query so the ranking is not the variable under test. ────────────────────
CORPUS="$TMP/corpus"
mkdir -p "$CORPUS/src" || { echo "formaxtokenscheck: cannot create corpus under $TMP"; exit 2; }
python3 - "$CORPUS/src" <<'PY_EOF'
import os, sys
d = sys.argv[1]
for i in range( 1, 31 ):
    open( os.path.join( d, 'entry%02d.ts' % i ), 'w' ).write(
        '// Process one entry: trim the raw input and normalise it for lane %02d.\n'
        'export function processEntry%02d( input: string ): string {\n'
        '    const trimmed = input.trim();\n'
        '    if( trimmed.length === 0 ) {\n'
        '        return "";\n'
        '    }\n'
        '    return trimmed.toLowerCase();\n'
        '}\n' % ( i, i ) )
PY_EOF

QUERY='processEntry input trim'

# ── THE JUDGE. One script, used by every arm AND by the mutation controls, so a control provably exercises
#    the same code path the arm did. Reads the ROOT ELEMENT through a real XML parser (the :719 trap), and
#    re-derives est_tokens from the delivered bytes. Prints one diagnostic line per violation; exit 0 clean.
#
#      judge.py DOC MAX_TOKENS TOKEN_BUDGET [soft]
#        MAX_TOKENS / TOKEN_BUDGET: the value passed on the command line, or 0 for "flag not given".
#        soft: TOKEN_BUDGET names a soft target (forbudget-soft) — stated on the root, never a ground for the label.
JUDGE="$TMP/judge.py"
cat > "$JUDGE" <<'PY_EOF'
import re, sys, xml.etree.ElementTree as ET

# the two rates src/serialize.h prices in — the ONLY constants this gate mirrors, and they are named in the
# document's own legend, so a change to either is a deliberate change to a published number.
BYTES_PER_TOKEN_MARKUP = 2.50   # kBytesPerTokenDefault
BYTES_PER_TOKEN_BODY   = 3.80   # kBytesPerTokenBody

def tokens( byteCount, rate ):
    return int( byteCount / rate + 0.5 )   # tokensForEmittedBytes

path, wantMax, wantBudget = sys.argv[1], int( sys.argv[2] ), int( sys.argv[3] )
softBudget = len( sys.argv ) > 4 and sys.argv[4] == 'soft'
raw  = open( path, 'rb' ).read()
# The <shortkey> fallback ladder (forreexport.h, gate barrelshortkeycheck) is an out-of-band block whose legend says it is not in
# est_tokens (like <lit>, <decl_rows>): the accounting below prices the charged answer, so ONE trailing block that DECLARES itself
# outside est_tokens is cut before pricing. A <shortkey> with no such declaration stays in and fails (C) like any uncharged byte.
raw  = re.sub( rb'<!-- shortkey[^>]*?not in est_tokens[^>]*?-->(?:<shortkey [^>]*/>|<shortkey [^>]*>.*?</shortkey>)(?=</ctx>\s*$)', b'', raw, count = 1, flags = re.S )
bad  = []

try:
    attrs = ET.fromstring( raw ).attrib
except Exception as exc:
    print( '    document does not parse as XML: %s' % ( exc, ) );  sys.exit( 1 )

# ── the two numbers, read as ATTRIBUTES of the root and never as text anywhere in the document ───────────
if wantMax > 0:
    if attrs.get( 'max_tokens' ) != str( wantMax ):
        bad.append( 'root max_tokens=%r, expected "%d"' % ( attrs.get( 'max_tokens' ), wantMax ) )
elif 'max_tokens' in attrs:
    bad.append( 'root carries max_tokens=%r on a run that named no --max-tokens' % ( attrs['max_tokens'], ) )

if wantBudget > 0 and attrs.get( 'budget_tokens' ) != str( wantBudget ):
    bad.append( 'root budget_tokens=%r, expected "%d"' % ( attrs.get( 'budget_tokens' ), wantBudget ) )

if 'est_tokens' not in attrs:
    print( '    root carries no est_tokens= — there is no number to judge' );  sys.exit( 1 )
est = int( attrs['est_tokens'] )

# ── (A/B/E) THE BICONDITIONAL, in the unit the root prints both numbers in ───────────────────────────────
overMax    = wantMax    > 0 and est > wantMax
# forbudget-soft (rule 4): a soft target is never "over" — only max_tokens= is a ceiling on such a root
overBudget = wantBudget > 0 and est > wantBudget and not softBudget
labelled   = attrs.get( 'over_ceiling' ) == '1'
if ( overMax or overBudget ) and not labelled:
    bad.append( 'est_tokens=%d exceeds the ceiling on its own root (max_tokens=%d budget_tokens=%d) '
                'and the root is SILENT about it' % ( est, wantMax, wantBudget ) )
if labelled and not ( overMax or overBudget ):
    bad.append( 'root claims over_ceiling="1" but est_tokens=%d is inside every ceiling it names '
                '(max_tokens=%d budget_tokens=%d)' % ( est, wantMax, wantBudget ) )

# ── (C) BYTE ACCOUNTING: re-derive est_tokens from the document that was actually delivered ──────────────
# The emitter prices markup and the <bodies> payload at different rates and sums them; everything spliced
# onto the root — est_tokens' own digits, over_ceiling="1" — is inside the markup it prices, so a
# disclosure that is emitted without being charged shows up here as an exact mismatch and nowhere else.
i, j     = raw.find( b'<bodies' ), raw.find( b'</bodies>' )
bodyBytes = ( j + len( b'</bodies>' ) - i ) if ( i >= 0 and j > i ) else 0
derived   = tokens( len( raw ) - bodyBytes, BYTES_PER_TOKEN_MARKUP ) + tokens( bodyBytes, BYTES_PER_TOKEN_BODY )
if derived != est:
    bad.append( 'est_tokens=%d but the delivered document prices at %d (%d B markup + %d B bodies) — '
                'some emitted bytes are not charged' % ( est, derived, len( raw ) - bodyBytes, bodyBytes ) )

# ── (D) THE LEGEND defines the attribute, against the ceiling actually on this root ──────────────────────
# The header is <ctx ...> followed by ONE OR MORE comments, and the clause is spliced into the LAST of them
# (headerStr.rfind(" -->")), so a reader that stops at the first "-->" — w3fixbudgetcheck's hdr() does —
# looks in the wrong comment and reports a missing definition that is present. The comments are walked from
# the root instead, which also means no <bodies> CDATA that happens to quote the sentence can be mistaken
# for the legend that defines it.
legend, rest = '', raw[ re.match( rb'<ctx[^>]*>', raw ).end() : ]
while True:
    node = re.match( rb'\s*<!--(.*?)-->', rest, re.S )
    if node is None:
        break
    legend += node.group( 1 ).decode( 'utf-8', 'replace' )
    rest    = rest[ node.end(): ]
clause  = re.search( r'over_ceiling=1 says est_tokens exceeds ([a-z_ ]+)', legend )
if labelled:
    if clause is None:
        bad.append( 'the root carries over_ceiling="1" and the legend never defines it' )
    else:
        named  = set( re.findall( r'(?:budget|max)_tokens', clause.group( 1 ) ) )
        onRoot = set( k for k in ( 'budget_tokens', 'max_tokens' ) if k in attrs )
        if softBudget:
            onRoot.discard( 'budget_tokens' )   # forbudget-soft: the label must not be defined against a soft target
        if named != onRoot:
            bad.append( 'the legend defines over_ceiling against %s, but this root carries %s'
                        % ( sorted( named ) or [ 'nothing' ], sorted( onRoot ) or [ 'nothing' ] ) )
elif clause is not None:
    bad.append( 'a document inside its ceiling still pays for the over_ceiling definition clause' )

for line in bad:
    print( '    ' + line )
sys.exit( 1 if bad else 0 )
PY_EOF

# ══ (A) + (B) + (C) + (D) — the swept band ═══════════════════════════════════════════════════════════════
# The band brackets the fixture's complete answer (~4.9K tokens at --detail=30), so the low points are
# provably over and the high ones provably fit. RED (pre-fix): every over point is silent.
BAND="300 600 1000 1500 2000 3000 5000 8000 100000"
SWEPT=0;  SWEPT_BAD=0;  SAW_OVER=0;  SAW_FITS=0
for MT in $BAND; do
    "$BIN" "$CORPUS" --no-cache "--for=$QUERY" --detail=30 --max-tokens="$MT" >"$TMP/band.$MT" 2>/dev/null
    [ -s "$TMP/band.$MT" ] || { no "(A) --max-tokens=$MT produced no document at all"; continue; }
    SWEPT=$(( SWEPT + 1 ))
    python3 "$JUDGE" "$TMP/band.$MT" "$MT" 0 || { SWEPT_BAD=$(( SWEPT_BAD + 1 )); echo "      ^ at --max-tokens=$MT"; }
    EST="$( python3 -c "
import sys, xml.etree.ElementTree as ET
print( ET.parse( sys.argv[1] ).getroot().attrib.get( 'est_tokens', '0' ) )" "$TMP/band.$MT" )"
    if [ "$EST" -gt "$MT" ]; then SAW_OVER=$(( SAW_OVER + 1 )); else SAW_FITS=$(( SAW_FITS + 1 )); fi
done
[ "$SWEPT_BAD" = "0" ] \
    && ok "(A/C/D) the biconditional, byte accounting and legend hold at all $SWEPT --max-tokens points" \
    || no "(A/C/D) VIOLATED at $SWEPT_BAD of $SWEPT --max-tokens points"
# NON-VACUITY: without both states in the band, the arm above is one-sided and proves nothing.
[ "$SAW_OVER" -gt 0 ] \
    && ok "(A) non-vacuity: $SAW_OVER point(s) in the band genuinely exceed their ceiling" \
    || no "(A) VACUOUS: no point in the band exceeds its ceiling — the fixture drifted, the presence half never ran"
[ "$SAW_FITS" -gt 0 ] \
    && ok "(A) non-vacuity: $SAW_FITS point(s) in the band genuinely fit — an unconditional label would fail here" \
    || no "(A) VACUOUS: no point in the band fits — the control half never ran"

# the named reproduction from the issue, asserted on its own so a regression names itself rather than
# arriving as "one of nine band points".
"$BIN" "$CORPUS" --no-cache "--for=$QUERY" --detail=30 --max-tokens=300 >"$TMP/issue61" 2>/dev/null
python3 - "$TMP/issue61" <<'PY_EOF' \
    && ok "(A) issue #61 verbatim: --detail=30 --max-tokens=300 names the ceiling AND discloses the overshoot" \
    || no "(A) issue #61 verbatim: the root still names a ceiling it did not apply, in silence"
import sys, xml.etree.ElementTree as ET
a = ET.parse( sys.argv[1] ).getroot().attrib
est = int( a.get( 'est_tokens', '0' ) )
if a.get( 'max_tokens' ) != '300':
    print( '    max_tokens=%r — the ceiling the caller named is not on the root' % ( a.get( 'max_tokens' ), ) );  sys.exit( 1 )
if est <= 300:
    print( '    est_tokens=%d is inside 300 — the fixture no longer reproduces the issue' % est );  sys.exit( 1 )
if a.get( 'over_ceiling' ) != '1':
    print( '    est_tokens=%d against max_tokens="300" (%.1fx) and no over_ceiling= on the root' % ( est, est / 300.0 ) )
    sys.exit( 1 )
sys.exit( 0 )
PY_EOF

# ── (B) SILENCE — no ceiling asked for, no ceiling attribute, no verdict ─────────────────────────────────
"$BIN" "$CORPUS" --no-cache "--for=$QUERY" --detail=30 >"$TMP/nomax" 2>/dev/null
python3 "$JUDGE" "$TMP/nomax" 0 0 \
    && ok "(B) --detail=30 with no --max-tokens: no ceiling named, no verdict claimed" \
    || no "(B) --detail=30 with no --max-tokens still emits a ceiling attribute or a verdict"

# ══ (E) --token-budget INTEROP ═══════════════════════════════════════════════════════════════════════════
# forbudget-soft (rule 4) — REPLACES "the pre-existing budget contract is unchanged, and with both ceilings on one root the
# single label answers to either" (the JUDGE's biconditional against budget_tokens=). An explicit --token-budget is now a
# SOFT row target (owner decisions 2026-10-14): the JUDGE runs with `soft`, so at every point
#   · alone: NOLBL — no over_ceiling=, though est_tokens may exceed budget_tokens (asserted reachable below);
#   · beside --max-tokens: the label answers to max_tokens ONLY, and the legend defines it against max_tokens alone;
#   · (C) byte accounting and budget_tokens= on the root are judged exactly as before.
# Plus RP: rows(N) is a rank prefix of rows(N') for N < N' and of the default answer's rows, and --max-tokens (a body
# ceiling) never moves a row. The --max-tokens band (A) above is this arm's hard-ceiling twin.
INTEROP=0;  INTEROP_BAD=0;  SOFT_PAST=0;  BOTH_LABELLED=0
rowsOf(){ python3 -c "
import re, sys
s = open( sys.argv[1] ).read()
m = re.search( r'<sigs\b[^>]*>(.*?)</sigs>', s, re.S )
if not m: sys.exit( 3 )
rows = []
for d in re.finditer( r'<d ([^>]*)>', m.group( 1 ) ):
    a = dict( re.findall( r'(\w+)=\"([^\"]*)\"', d.group( 1 ) ) )
    r = a.get( 'r', '' )
    rows.append( ( int( r ) if r.isdigit() else 10**9, a.get( 'p', '?' ) + ':' + a.get( 'l', '?' ) + ':' + a.get( 'n', '?' ) ) )
rows.sort()
print( '\n'.join( x[1] for x in rows ) )" "$1"; }
isPrefix(){ [ -s "$1" ] && [ "$( wc -l < "$1" )" -le "$( wc -l < "$2" )" ] && [ "$( head -n "$( wc -l < "$1" )" "$2" )" = "$( cat "$1" )" ]; }
rowsOf "$TMP/nomax" > "$TMP/rows.nomax" || no "(E) the default --detail=30 answer has no <sigs> block — RP has no reference"
PREV=""
for TB in 800 2000 20000; do
    "$BIN" "$CORPUS" --no-cache "--for=$QUERY" --detail=30 --token-budget="$TB" >"$TMP/tb.$TB" 2>/dev/null
    INTEROP=$(( INTEROP + 1 ))
    python3 "$JUDGE" "$TMP/tb.$TB" 0 "$TB" soft || { INTEROP_BAD=$(( INTEROP_BAD + 1 )); echo "      ^ at --token-budget=$TB"; }
    EST="$( python3 -c "
import sys, xml.etree.ElementTree as ET
print( ET.parse( sys.argv[1] ).getroot().attrib.get( 'est_tokens', '' ) )" "$TMP/tb.$TB" 2>/dev/null )"
    case "$EST" in ''|*[!0-9]*) ;; *) [ "$EST" -gt "$TB" ] && SOFT_PAST=$(( SOFT_PAST + 1 )) ;; esac
    if rowsOf "$TMP/tb.$TB" > "$TMP/rows.$TB"; then
        isPrefix "$TMP/rows.$TB" "$TMP/rows.nomax" \
            && ok "(E) RP: rows(--token-budget=$TB) — $( wc -l < "$TMP/rows.$TB" | tr -d ' ' ) row(s) — are a rank prefix of the default answer's $( wc -l < "$TMP/rows.nomax" | tr -d ' ' )" \
            || no "(E) RP: rows(--token-budget=$TB) are not a rank prefix of the default answer's rows"
        if [ -n "$PREV" ]; then
            isPrefix "$TMP/rows.$PREV" "$TMP/rows.$TB" \
                && ok "(E) RP: rows(--token-budget=$PREV) are a prefix of rows(--token-budget=$TB) (monotone in the target)" \
                || no "(E) RP: rows(--token-budget=$PREV) are not a prefix of rows(--token-budget=$TB) — not monotone"
        fi
        PREV="$TB"
    else
        no "(E) --token-budget=$TB: no <sigs> block — no rows to judge"
    fi
    for MT in 300 20000; do
        "$BIN" "$CORPUS" --no-cache "--for=$QUERY" --detail=30 --token-budget="$TB" --max-tokens="$MT" >"$TMP/both.$TB.$MT" 2>/dev/null
        INTEROP=$(( INTEROP + 1 ))
        python3 "$JUDGE" "$TMP/both.$TB.$MT" "$MT" "$TB" soft \
            || { INTEROP_BAD=$(( INTEROP_BAD + 1 )); echo "      ^ at --token-budget=$TB --max-tokens=$MT"; }
        grep -o '<ctx [^>]*>' "$TMP/both.$TB.$MT" | head -1 | grep -q ' over_ceiling="1"' && BOTH_LABELLED=$(( BOTH_LABELLED + 1 ))
        rowsOf "$TMP/both.$TB.$MT" > "$TMP/rows.$TB.$MT" 2>/dev/null
        cmp -s "$TMP/rows.$TB.$MT" "$TMP/rows.$TB" && [ -s "$TMP/rows.$TB" ] \
            || { INTEROP_BAD=$(( INTEROP_BAD + 1 )); echo "    --token-budget=$TB --max-tokens=$MT: the rows differ from --token-budget=$TB alone — the body ceiling moved a row"; }
    done
done
[ "$INTEROP_BAD" = "0" ] \
    && ok "(E) --token-budget alone and beside --max-tokens: $INTEROP point(s), no label for the soft target, the label answering to max_tokens only, same rows either way" \
    || no "(E) VIOLATED at $INTEROP_BAD of $INTEROP --token-budget point(s)"
# NON-VACUITY for both halves: a soft target the answer really exceeds (so NOLBL was tested, not assumed), and a
# combined point really over max_tokens (so the max_tokens-only label was read, not absent).
[ "$SOFT_PAST" -gt 0 ] \
    && ok "(E) non-vacuity: $SOFT_PAST --token-budget point(s) deliver est_tokens past the soft target (the no-label half is exercised)" \
    || no "(E) VACUOUS: no --token-budget point exceeds its target — the no-label half never ran"
[ "$BOTH_LABELLED" -gt 0 ] \
    && ok "(E) non-vacuity: $BOTH_LABELLED combined point(s) carry over_ceiling=\"1\" for max_tokens" \
    || no "(E) VACUOUS: no --token-budget + --max-tokens point is labelled — the max_tokens-only legend half never ran"

# ══ (F) DETERMINISM across the band ══════════════════════════════════════════════════════════════════════
# The verdict is decided inside an est_tokens fixpoint that measures the document containing its own label.
# A fixpoint that failed to converge, or converged differently run to run, would show up here first.
DET_BAD=0
for MT in 300 3000 100000; do
    "$BIN" "$CORPUS" --no-cache "--for=$QUERY" --detail=30 --max-tokens="$MT" >"$TMP/d1" 2>/dev/null
    "$BIN" "$CORPUS" --no-cache "--for=$QUERY" --detail=30 --max-tokens="$MT" >"$TMP/d2" 2>/dev/null
    cmp -s "$TMP/d1" "$TMP/d2" || { DET_BAD=$(( DET_BAD + 1 )); echo "    non-deterministic at --max-tokens=$MT"; }
done
[ "$DET_BAD" = "0" ] \
    && ok "(F) det-gate: byte-identical run-to-run at three points of the band" \
    || no "(F) det-gate: $DET_BAD point(s) are NOT byte-identical run-to-run"

# ══ (G) MUTATION CONTROLS — every judge above, re-run over a deliberately corrupted real document ════════
# Each control edits a document this gate already collected and requires the SAME judge invocation to turn
# red. Without these, three of the four judges are satisfiable by an always-true implementation.
mutate(){                      # $1 = label, $2 = source doc, $3 = max, $4 = budget, $5 = python edit expr
    python3 - "$2" "$TMP/mut.xml" <<PY_EOF
import sys
d = open( sys.argv[1], 'rb' ).read()
$5
open( sys.argv[2], 'wb' ).write( d )
PY_EOF
    if cmp -s "$2" "$TMP/mut.xml"; then
        no "(G) $1: the mutation did not take — the copy is unchanged, so it proves nothing"
    elif python3 "$JUDGE" "$TMP/mut.xml" "$3" "$4" >/dev/null 2>&1; then
        no "(G) $1: the judge ACCEPTS a deliberately broken document — that arm is inert"
    else
        ok "(G) $1: the judge rejects it"
    fi
}
# G1 — strip the label off a document that is genuinely over: the pre-fix behaviour, manufactured.
mutate "the pre-fix silence (over_ceiling deleted from an over-ceiling root)" "$TMP/band.300" 300 0 \
       "d = d.replace( b' over_ceiling=\"1\"', b'', 1 )"
# G2 — paste the label onto a document that fits: the always-label binary, manufactured.
mutate "an unconditional label (over_ceiling pasted onto a fitting root)" "$TMP/band.100000" 100000 0 \
       "d = d.replace( b' est_tokens=', b' over_ceiling=\"1\" est_tokens=', 1 )"
# G3 — the byte-accounting arm: shift est_tokens by the ~27 tokens an uncharged disclosure would cost.
mutate "an under-reported est_tokens (the uncharged-disclosure shape)" "$TMP/band.300" 300 0 \
       "import re
m = re.search( rb' est_tokens=\"(\d+)\"', d )
d = d[ :m.start() ] + ( ' est_tokens=\"%d\"' % ( int( m.group( 1 ) ) - 27 ) ).encode() + d[ m.end(): ]"
# G4 — the legend arm: an attribute whose own document never defines it.
mutate "an undefined attribute (legend clause removed, label kept)" "$TMP/band.300" 300 0 \
       "import re
d = re.sub( rb' over_ceiling=1 says est_tokens exceeds [a-z_ ]+', b'', d, count = 1 )"
# G5 — the legend arm, other direction: the clause naming a ceiling this root does not carry.
mutate "a legend naming the wrong ceiling" "$TMP/band.300" 300 0 \
       "d = d.replace( b'over_ceiling=1 says est_tokens exceeds max_tokens', b'over_ceiling=1 says est_tokens exceeds budget_tokens', 1 )"
# G6/G7 — forbudget-soft (rule 4): the soft judge of (E), on the old behaviour manufactured — a label on a soft target the
# answer exceeds, and a legend defining the label against the soft target. A pasted attribute also moves the byte count,
# which (C) rejects on its own, so each control requires the judge's rejection to name the SOFT reason ($6), not just exit 1.
# On a binary whose real document already has the broken shape (the pre-soft base), the edit is a no-op and the real
# document is judged as is — the control then reads the shape the binary emitted, which must be rejected all the same.
softMutate(){                  # $1 label, $2 source doc, $3 max, $4 budget, $5 python edit expr, $6 expected reason
    python3 - "$2" "$TMP/mut.xml" <<PY_EOF
import sys
d = open( sys.argv[1], 'rb' ).read()
$5
open( sys.argv[2], 'wb' ).write( d )
PY_EOF
    if python3 "$JUDGE" "$TMP/mut.xml" "$3" "$4" soft > "$TMP/mut.why" 2>&1; then
        no "(G) $1: the soft judge ACCEPTS a deliberately broken document — arm (E) is inert"
    elif grep -qF -e "$6" "$TMP/mut.why"; then
        ok "(G) $1: the soft judge rejects it, for that reason"
    else
        no "(G) $1: the soft judge rejects it only for another reason ($( head -1 "$TMP/mut.why" | cut -c1-120 )) — the soft half is inert"
    fi
}
softMutate "a label on a soft target (over_ceiling pasted onto --token-budget=800 alone)" "$TMP/tb.800" 0 800 \
       "d = d.replace( b' over_ceiling=\"1\"', b'', 1 ).replace( b' est_tokens=', b' over_ceiling=\"1\" est_tokens=', 1 )" \
       'root claims over_ceiling="1" but est_tokens='
softMutate "a legend defining the label against the soft target too" "$TMP/both.800.300" 300 800 \
       "d = d.replace( b'over_ceiling=1 says est_tokens exceeds max_tokens', b'over_ceiling=1 says est_tokens exceeds budget_tokens or max_tokens', 1 )" \
       'the legend defines over_ceiling against'

if [ "$fail" = "0" ]; then echo "formaxtokenscheck: ALL PASS"; else echo "formaxtokenscheck: FAILURES"; fi
exit "$fail"
