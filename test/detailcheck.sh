#!/usr/bin/env bash
# detailcheck.sh — A4-R4 lever 3: --detail=N importance-weighted detail on --for.
# Full BODIES for the top-N ranked symbols + SIGNATURES for the rest, in ONE call (measured +63% tokens for
# the 3 relevant heads vs +355% for all-bodies — the weighted posture avoids the expensive all-bodies cost).
#
# Contract:
#   1) --detail=0 (and no --detail) is byte-identical — golden-neutral, flag-gated.
#   2) --detail=N adds a <bodies> block with at most N <b …> bodies (the top-N ranked), while the <sigs> block
#      still carries the rest as signatures-only.
#   3) composes with --max-tokens (the bodies are byte-budget-bounded) and with --adaptive.
#   4) deterministic; xmllint-clean.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/detailcheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
cd "$ROOT"
echo "detailcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
TASK="rank symbols by pagerank and serialize the map"

bodies(){ grep -o '<b t=' "$1" | wc -l | tr -d ' '; }
# H1: the budgeted --for bundle may mark the trimmed payload. §P8 vocabulary: that marker was
# payload="capped" (a string enum) and is now the tool-wide boolean capped="1" — see src/pageview.h,
# THE TRUNCATION VOCABULARY, rule 5.
sigblocks(){ grep -oE '<sigs( capped="1")?>' "$1" | wc -l | tr -d ' '; }

# ── #1: --detail=0 == no --detail (byte-identical, golden-neutral) ──────────────────────────────────────
"$BIN" src --for="$TASK" --no-cache >"$TMP/plain" 2>/dev/null
"$BIN" src --for="$TASK" --detail=0 --no-cache >"$TMP/d0" 2>/dev/null
diff -q "$TMP/plain" "$TMP/d0" >/dev/null && ok "--detail=0 byte-identical to no --detail (flag-gated)" \
    || { no "--detail=0 changed the output (must be byte-identical)"; diff "$TMP/plain" "$TMP/d0" | head -4; }

# T3 (contract update, same wave — test/forautobodycheck.sh owns the new default): plain --for is now
# terminal by default and MAY carry an enrichment section — an auto <bodies> block on a name-exact
# query, the COMPACT <hops> context on a conceptual one (this gate's TASK routes conceptual, so the
# plain/d0 pair above compares two compact bundles; 2026-08-23 sweep note). --signatures-only is the
# OPT-OUT on both shapes.
"$BIN" src --for="$TASK" --signatures-only --no-cache >"$TMP/sigonly" 2>/dev/null
grep -q '<bodies [^>]*>' "$TMP/sigonly" && no "--signatures-only --for still emits <bodies> (the opt-out must be signatures-only)" \
    || ok "--signatures-only --for is signatures-only (no <bodies> block)"

# ── #2: --detail=3 adds a <bodies> block with AT MOST 3 bodies; the <sigs> block still present ──────────
"$BIN" src --for="$TASK" --detail=3 --no-cache >"$TMP/d3" 2>/dev/null
NB=$( bodies "$TMP/d3" )
{ grep -q '<bodies [^>]*>' "$TMP/d3" && [ "$NB" -ge 1 ] && [ "$NB" -le 3 ]; } \
    && ok "--detail=3 emits a <bodies> block with $NB (<=3) full bodies (the ranked head)" \
    || no "--detail=3 body count wrong ($NB, expected 1..3)"
[ "$( sigblocks "$TMP/d3" )" -ge 1 ] && ok "--detail=3 still emits the <sigs> block (rest kept as signatures)" \
    || no "--detail=3 dropped the <sigs> block (the rest must stay signatures-only)"

# ── #3: MORE detail = MORE bodies (N=6 >= N=3), still bounded ───────────────────────────────────────────
"$BIN" src --for="$TASK" --detail=6 --no-cache >"$TMP/d6" 2>/dev/null
N6=$( bodies "$TMP/d6" )
{ [ "$N6" -ge "$NB" ] && [ "$N6" -le 6 ]; } \
    && ok "--detail=6 emits >= --detail=3 bodies ($N6 >= $NB), still <=6" \
    || no "--detail=6 body count not monotone/bounded ($N6 vs $NB)"

# ── #4: composes with --max-tokens — bodies are byte-bounded, output still valid ────────────────────────
"$BIN" src --for="$TASK" --detail=6 --max-tokens=1500 --no-cache >"$TMP/dmt" 2>/dev/null; rc=$?
BIG=$( wc -c <"$TMP/d6" ); SMALL=$( wc -c <"$TMP/dmt" )
{ [ "$rc" = 0 ] && grep -q '</ctx>' "$TMP/dmt" && [ "$SMALL" -le "$BIG" ]; } \
    && ok "--detail=6 composes with --max-tokens (bounded: ${SMALL}B <= ${BIG}B, valid close tag)" \
    || no "--detail + --max-tokens produced a bad/unbounded bundle (rc=$rc ${SMALL}B vs ${BIG}B)"

# ── #5: composes with --adaptive (no crash, valid document) ─────────────────────────────────────────────
"$BIN" src --for="$TASK" --detail=3 --adaptive --no-cache >"$TMP/dad" 2>/dev/null; rc=$?
{ [ "$rc" = 0 ] && grep -q '</ctx>' "$TMP/dad"; } \
    && ok "--detail composes with --adaptive (valid document)" \
    || no "--detail + --adaptive failed (rc=$rc)"

# ── #6: DETERMINISM — --detail run byte-identical twice ─────────────────────────────────────────────────
"$BIN" src --for="$TASK" --detail=3 --no-cache >"$TMP/x1" 2>/dev/null
"$BIN" src --for="$TASK" --detail=3 --no-cache >"$TMP/x2" 2>/dev/null
diff -q "$TMP/x1" "$TMP/x2" >/dev/null && ok "--detail deterministic (byte-identical twice)" \
    || no "--detail NON-deterministic"

# ── #7: --detail alone (no --for) is a loud parse error (guarded) ───────────────────────────────────────
"$BIN" src --detail=3 --no-cache >/dev/null 2>"$TMP/err"; rc=$?
{ [ "$rc" != 0 ] && grep -qi 'detail' "$TMP/err"; } \
    && ok "--detail without --for refuses loudly (guarded)" \
    || no "--detail without --for did not error as expected (rc=$rc)"

# ── #8: xmllint-clean ──────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    lint=1
    for F in "$TMP/d3" "$TMP/d6" "$TMP/dmt" "$TMP/dad"; do
        xmllint --noout "$F" 2>/dev/null || { echo "    malformed: $F"; lint=0; }
    done
    [ "$lint" = 1 ] && ok "--detail output well-formed XML (G4)" || no "--detail output malformed XML"
else
    printf '  SKIP  xmllint (not installed)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
