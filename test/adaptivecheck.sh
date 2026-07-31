#!/usr/bin/env bash
# adaptivecheck.sh — PHASE 3 gate (RESEARCH_outputEconomy §2 / lever 2): the --adaptive relevance-cliff cut.
#
# --for/--query sort by lens score then DISCARD it, so the "cliff" (a sharp query's few relevant hits vs a
# long low-score tail) is unobservable — a fixed top-40 is too generous for sharp queries and meaningless for
# broad ones (BM25 saturates, no knee). --adaptive cuts at the largest RELATIVE score gap (Adaptive-k), floor
# 5, ceiling = the existing top-k, and prints the cut in the header. Without it, output is byte-identical.
#
# Usage:  bash test/adaptivecheck.sh [BIN]   |   CTXPACK_BIN=asan/ctxpack bash test/adaptivecheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# trap #20, BOTH seams. regression.sh drives gates through CTXPACK_BIN (`test/regression.sh:183`), which this
# file already honoured, so the SUITE was never running the wrong binary — the missing seam is the positional
# one, which is how a lane or a verifier points a gate at asan/ or at a base binary BY HAND. Without it
# `bash test/adaptivecheck.sh asan/ctxpack` silently re-ran build/ and reported PASS for the wrong binary.
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
cd "$ROOT"
echo "adaptivecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# how many <d> signature blocks does a --for lens emit? (minified XML is one line → count OCCURRENCES, not lines)
dcount(){ "$BIN" "$@" --no-cache 2>/dev/null | grep -o '<d ' | wc -l | tr -d ' '; }

# ── (a) plain --for (no --adaptive) is byte-identical run-to-run AND unaffected by the flag's presence in
#    the code (golden neutrality). We compare a --for run to itself (determinism) and assert the adaptive
#    header note is ABSENT without the flag. ─────────────────────────────────────────────────────────────
Q="serialize the ranked map"
"$BIN" src --for="$Q" --no-cache >"$TMP/plain1" 2>/dev/null
"$BIN" src --for="$Q" --no-cache >"$TMP/plain2" 2>/dev/null
{ diff -q "$TMP/plain1" "$TMP/plain2" >/dev/null && ! grep -q 'adaptive:' "$TMP/plain1"; } \
    && ok "plain --for: deterministic + no 'adaptive:' note (golden-neutral without the flag)" \
    || no "plain --for: non-deterministic or leaked an adaptive note without the flag"

# ── (b) a SHARP query keeps FAR FEWER than a BROAD common-word query. Sharp = a rare compound identifier
#    (few real matches, sharp head-cliff → cut to the floor); broad = "file" (BM25 saturates → ceiling). ──
#    --no-route pins the subtoken+body ranker so this exercises adaptive's cut, not the router's pick.
SHARP=$( dcount src --for="estimateExpandBodyTokens" --no-route --adaptive )
BROAD=$( dcount src --for="file" --no-route --adaptive )
{ [ -n "$SHARP" ] && [ -n "$BROAD" ] && [ "$SHARP" -lt "$BROAD" ] 2>/dev/null; } \
    && ok "sharp query kept far fewer than broad ($SHARP < $BROAD)" \
    || no "sharp query did NOT keep fewer than broad ($SHARP vs $BROAD) — the cliff cut isn't discriminating"

# ── (b2) PHASE 3: --adaptive must BITE ON --for under DEFAULT routing (the flagship path). Before this phase
#    --adaptive was effectively inert on --for (kept 40/40): the cliff scan ran on the already-capped top-k,
#    found no gap, and returned the ceiling on exactly the sharp queries the mode exists for.
#
#    CORPUS DRIFT (2026-07-31) — why this arm no longer compares two live queries on src/. The form it
#    replaces ran `dcount src --for="known item retrieval eval" --adaptive` against `--for="file" --adaptive`
#    and demanded the first keep >=10 fewer. BOTH halves were shaped by the corpus rather than by the cut:
#      * <sigs> is BYTE-BUDGETED (payload="capped"), so the <d> count is min(kept, what the byte budget
#        left) — NOT kept. Measured at the time it went red: both queries reported `adaptive: kept 40 of 40
#        - no relevance cliff`, i.e. NO CUT ON EITHER, while the counts read 32 and 29 purely because their
#        signatures are different lengths. Adding --adaptive moved the arm's measured number by ZERO
#        (32 vs 32, 29 vs 29): it had stopped observing the cut at all, and its verdict was being decided by
#        signature verbosity. It could equally have passed with the mode fully inert — trap #20.
#      * the "sharp" phrase was sharp on the src/ of the day. src/ grew ~16 files this round, its head for
#        that phrase went flat, and a query hand-picked for one snapshot stopped having a cliff.
#    So this arm now runs on a corpus the GATE OWNS and measures the header's own `kept K of N` — the number
#    the cut actually produces — plus the emitted set, which proves the announced cut was HONOURED and not
#    merely printed. Deterministic, and immune to anything that lands in src/. (The unit-level shape of
#    adaptiveCut() itself is pinned separately, on a synthetic score vector, by adaptivecutshapecheck.sh;
#    this arm is the INTEGRATION half — that the --for path wires that cut in and spends it.)
#
#    The fixture is built to make the two cases PROPERTIES, not accidents:
#      76 tail files      — one symbol each, mentioning "widget" and "telemetry" exactly once →
#                           >ceiling positive hits for both queries, and a flat score head for "widget".
#      6 head files       — "zorbulator telemetry" saturated in doc + body → a head that scores far above
#                           the tail, so the largest relative gap sits at rank 6, well inside the ceiling.
FIX="$TMP/cliffcorpus"
mkdir -p "$FIX"
python3 - "$FIX" <<'PYX'
import sys, os
d = sys.argv[1]
for i in range( 70 ):
    open( os.path.join( d, 'tail%02d.cpp' % i ), 'w' ).write(
        '// widget handler number %d for the widget pipeline\n'
        'void widgetHandler%02d( int widget )\n'
        '{\n'
        '    int telemetry = widget + %d;\n'
        '    (void)telemetry;\n'
        '}\n' % ( i, i, i ) )
for i in range( 6 ):
    open( os.path.join( d, 'head%02d.cpp' % i ), 'w' ).write(
        '// zorbulator telemetry: the zorbulator telemetry zorbulator telemetry pump, zorbulator telemetry.\n'
        'void zorbTelemetryPump%02d( int widget )\n'
        '{\n'
        '    int zorbulator = widget; int telemetry = zorbulator;\n'
        '    zorbulator = telemetry + zorbulator + telemetry; (void)zorbulator;\n'
        '}\n' % ( i, ) )
PYX
#    the fixture's own premise, asserted rather than assumed (a gate whose corpus silently failed to
#    materialise would "pass" every assertion below against an empty tree)
FIXN=$( ls "$FIX" | wc -l | tr -d ' ' )
[ "$FIXN" = 76 ] \
    && ok "PHASE3 premise: the gate-owned cliff corpus built ($FIXN files)" \
    || no "PHASE3 premise: the cliff corpus is $FIXN files, expected 76 — every assertion below is void"

hdrcut(){ "$BIN" "$@" --no-cache 2>/dev/null | grep -oE 'adaptive: kept [0-9]+ of [0-9]+[^]]*' | head -1; }
routeof(){ "$BIN" "$@" --no-cache 2>/dev/null | grep -oE 'routed: [^]]*' | head -1; }
SHARPQ="zorbulator telemetry pump"
BROADQ="widget"

#    both queries must take the SAME (default-routed, subtoken+body) path — a router change that sent one of
#    them name-exact would quietly change what this arm tests instead of failing it
{ routeof "$FIX" --for="$SHARPQ" --adaptive | grep -q 'subtoken+body' \
    && routeof "$FIX" --for="$BROADQ" --adaptive | grep -q 'subtoken+body'; } \
    && ok "PHASE3: both fixture queries take the default subtoken+body route (the flagship --for path)" \
    || no "PHASE3: a fixture query did not route subtoken+body — this arm is no longer testing the --for path it names"

#    SHARP: the header must report a CLIFF-driven cut (not the 'only N symbols matched' clamp, which the
#    pre-PHASE3 binary also produced), materially below the ceiling, at a material drop.
HS=$( hdrcut "$FIX" --for="$SHARPQ" --adaptive )
KS=$( printf '%s' "$HS" | sed -n 's/^adaptive: kept \([0-9]*\) of \([0-9]*\).*/\1/p' )
NS=$( printf '%s' "$HS" | sed -n 's/^adaptive: kept \([0-9]*\) of \([0-9]*\).*/\2/p' )
DS=$( printf '%s' "$HS" | sed -n 's/.*cliff at rank [0-9]*, \([0-9]*\)% drop.*/\1/p' )
{ [ -n "$KS" ] && [ -n "$NS" ] && [ -n "$DS" ] && [ "$KS" -lt "$NS" ] && [ $(( KS * 2 )) -le "$NS" ] \
    && [ "$DS" -ge 20 ]; } 2>/dev/null \
    && ok "PHASE3: --adaptive BITES on --for (default routing) — cliff-driven cut to $KS of $NS at a $DS% drop ['$HS']" \
    || no "PHASE3: --adaptive did not bite on --for — header said '$HS' (needs a cliff-driven kept << ceiling)"

#    and the cut is SPENT, not just announced: the emitted head is exactly the kept count, and strictly
#    smaller than the same query without --adaptive.
DS_AD=$( dcount "$FIX" --for="$SHARPQ" --adaptive )
DS_PL=$( dcount "$FIX" --for="$SHARPQ" )
{ [ -n "$KS" ] && [ "$DS_AD" = "$KS" ] && [ "$DS_AD" -lt "$DS_PL" ]; } 2>/dev/null \
    && ok "PHASE3: the announced cut is HONOURED — $DS_AD <d> emitted == kept $KS, against $DS_PL without --adaptive" \
    || no "PHASE3: the announced cut is not honoured — $DS_AD <d> emitted vs kept '$KS' (plain $DS_PL)"

#    BROAD: a flat distribution has no knee, so the honest answer is the ceiling — and the mode must then be
#    INERT (same emitted set as without it), which is the other half of "materially" and the half a
#    recalibrated-to-whatever-it-does arm would have dropped.
HB=$( hdrcut "$FIX" --for="$BROADQ" --adaptive )
KB=$( printf '%s' "$HB" | sed -n 's/^adaptive: kept \([0-9]*\) of \([0-9]*\).*/\1/p' )
NB=$( printf '%s' "$HB" | sed -n 's/^adaptive: kept \([0-9]*\) of \([0-9]*\).*/\2/p' )
DB_AD=$( dcount "$FIX" --for="$BROADQ" --adaptive )
DB_PL=$( dcount "$FIX" --for="$BROADQ" )
{ [ -n "$KB" ] && [ "$KB" = "$NB" ] && printf '%s' "$HB" | grep -q 'no relevance cliff' \
    && [ "$DB_AD" = "$DB_PL" ]; } 2>/dev/null \
    && ok "PHASE3: a flat query keeps the ceiling and the mode is inert on it — kept $KB of $NB, $DB_AD <d> either way" \
    || no "PHASE3: the flat query was cut or mislabelled — header '$HB', $DB_AD <d> with --adaptive vs $DB_PL without"

# ── (c) the header STATES the cut (kept K of N, and either a cliff rank+drop or a 'no cliff' note) ───────
HDR_SHARP=$( "$BIN" src --for="estimateExpandBodyTokens" --adaptive --no-cache 2>/dev/null | grep -oE 'adaptive: kept [0-9]+ of [0-9]+[^]]*' | head -1 )
HDR_BROAD=$( "$BIN" src --for="file" --adaptive --no-cache 2>/dev/null | grep -oE 'adaptive: kept [0-9]+ of [0-9]+[^]]*' | head -1 )
{ echo "$HDR_SHARP" | grep -qE 'kept [0-9]+ of [0-9]+ - (sharp cliff|cliff|only [0-9]+ symbols)' \
    && echo "$HDR_BROAD" | grep -qE 'kept [0-9]+ of [0-9]+ - no relevance cliff'; } \
    && ok "header states the cut (sharp: '$HDR_SHARP' | broad: '$HDR_BROAD')" \
    || no "header does not clearly state the cut (sharp='$HDR_SHARP' broad='$HDR_BROAD')"

# ── (d) DETERMINISM — an --adaptive run is byte-identical twice (the cut is a pure fn of the score) ─────
"$BIN" src --for="$Q" --adaptive --no-cache >"$TMP/ad1" 2>/dev/null
"$BIN" src --for="$Q" --adaptive --no-cache >"$TMP/ad2" 2>/dev/null
diff -q "$TMP/ad1" "$TMP/ad2" >/dev/null \
    && ok "--adaptive deterministic: two runs byte-identical" \
    || no "--adaptive NON-deterministic: two runs differ"

# ── (e) the FLOOR is respected on an ultra-sharp query — never cut below 5, even with a rank-1 cliff ────
FLOOR=$( dcount src --for="estimateExpandBodyTokens" --no-route --adaptive )
{ [ -n "$FLOOR" ] && [ "$FLOOR" -ge 5 ] 2>/dev/null; } \
    && ok "floor respected: ultra-sharp query keeps >= 5 ($FLOOR)" \
    || no "floor violated: ultra-sharp query kept < 5 ($FLOOR)"

# ── (f) the CEILING is respected — --adaptive never keeps MORE than the plain top-k (40 by default).
#    Both sides pin --no-route so the comparison is like-for-like on the same pre-routing ranker (routing
#    choice and any opt-in rank modifiers are payload/rank effects, not ceiling effects, and must not
#    contaminate this assertion). ─────────────────────────────────────────────────────────────────────
CEIL=$( dcount src --for="file" --no-route --adaptive )
PLAIN=$( dcount src --for="file" --no-route )
{ [ -n "$CEIL" ] && [ -n "$PLAIN" ] && [ "$CEIL" -le "$PLAIN" ] 2>/dev/null; } \
    && ok "ceiling respected: adaptive broad ($CEIL) <= plain top-k ($PLAIN)" \
    || no "ceiling violated: adaptive kept more than plain ($CEIL > $PLAIN)"

# ── (g) --adaptive composes with --query and stays well-formed XML (leading cut comment before <r>) ────
if command -v xmllint >/dev/null 2>&1; then
    "$BIN" src --query="estimateExpandBodyTokens" --adaptive --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed under --query --adaptive" || no "xml malformed under --query --adaptive"
    "$BIN" src --for="$Q" --adaptive --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed under --for --adaptive" || no "xml malformed under --for --adaptive"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── (h) --adaptive alone (no --for/--query) is a clean loud error, not a silent no-op ──────────────────
"$BIN" src --adaptive --no-cache >/dev/null 2>"$TMP/err"
{ [ "$?" -ne 0 ] && grep -q 'adaptive modifies' "$TMP/err"; } \
    && ok "--adaptive alone: clean error (refuses to silently do nothing)" \
    || no "--adaptive alone: did not error clearly ($(cat "$TMP/err" 2>/dev/null))"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
