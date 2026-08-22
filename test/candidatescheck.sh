#!/usr/bin/env bash
# candidatescheck.sh — A4-R6 / R6: --format=candidates, a FLAT machine-readable top-K export for EXTERNAL
# rerankers. One <cand r= s= n= id= k= p= l=><sig>…</sig></cand> row per --for/--query result — identity +
# score + signature only, NO lens/quality extras, NO doc bodies. The research doc's division-of-labor thesis:
# stay deterministic + offline, hand a reranker exactly what it needs.
#
# Contract:
#   1) row count == --top-k (or == available symbols when fewer); count= attr matches.
#   2) every row carries r/ s/ n/ id/ k/ p/ l attributes + a <sig> child.
#   3) NO lens extras (churn=/amp=/clone=/tested=/<doc>) leak into a row.
#   4) works on BOTH --for and --query; composes with --top-k; byte-deterministic; xmllint-clean.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/candidatescheck.sh
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
echo "candidatescheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

rows(){ grep -o '<cand ' "$1" | wc -l | tr -d ' '; }
countattr(){ grep -oE '<candidates count="[0-9]*"' "$1" | grep -oE '[0-9]+' | head -1; }

# ── #1: --query --format=candidates: row count == --top-k, count= matches ──────────────────────────────
for K in 3 5 10; do
    "$BIN" src --query="escape xml serialize" --format=candidates --top-k=$K --no-cache >"$TMP/q$K" 2>/dev/null
    R=$( rows "$TMP/q$K" ); C=$( countattr "$TMP/q$K" )
    { [ "$R" = "$K" ] && [ "$C" = "$K" ]; } \
        && ok "--query candidates --top-k=$K -> $R rows, count=\"$C\" (both == $K)" \
        || no "--query candidates --top-k=$K wrong row/count ($R rows, count=$C)"
done

# ── #2: every row carries r/s/n/id/k/p/l + a <sig> ─────────────────────────────────────────────────────
F="$TMP/q5"
missing=0
for A in 'r="' 's="' ' n="' ' id="' ' k="' ' p="' ' l="'; do
    exp=$( rows "$F" )
    got=$( grep -oF "$A" "$F" | wc -l | tr -d ' ' )
    [ "$got" -ge "$exp" ] || { echo "    attr $A present on $got/$exp rows"; missing=1; }
done
SIGS=$( grep -o '<sig>' "$F" | wc -l | tr -d ' ' )
{ [ "$missing" = 0 ] && [ "$SIGS" = "$( rows "$F" )" ]; } \
    && ok "every <cand> row carries r/s/n/id/k/p/l + a <sig> child" \
    || no "some <cand> rows are missing a required field (attrs or <sig>)"

# ── #3: NO lens/quality extras leak into candidates (the whole point — nothing to strip) ────────────────
if grep -qE 'churn=|amp=|clone=|tested=|<doc>|<sigs>|cx=' "$F"; then
    no "candidates leaked lens/quality extras (churn/amp/clone/tested/doc/cx) — must be identity+score+sig only"
else
    ok "candidates carry NO lens extras (no churn/amp/clone/tested/doc/cx)"
fi

# ── #4: --for --format=candidates works and is capped by --top-k ────────────────────────────────────────
"$BIN" src --for="rank symbols by pagerank" --format=candidates --top-k=7 --no-cache >"$TMP/f7" 2>/dev/null
R7=$( rows "$TMP/f7" )
[ "$R7" = 7 ] && ok "--for candidates --top-k=7 -> 7 rows" || no "--for candidates --top-k=7 -> $R7 rows (expected 7)"

# ── #5: ranks are 1..K in order (r="1" first, ascending) ───────────────────────────────────────────────
FIRST=$( grep -oE '<cand r="[0-9]+"' "$TMP/f7" | head -1 | grep -oE '[0-9]+' )
LAST=$(  grep -oE '<cand r="[0-9]+"' "$TMP/f7" | tail -1 | grep -oE '[0-9]+' )
{ [ "$FIRST" = 1 ] && [ "$LAST" = 7 ]; } \
    && ok "ranks are 1..K in emission order (r=$FIRST .. $LAST)" \
    || no "rank numbering wrong (first=$FIRST last=$LAST, expected 1..7)"

# ── #6: byte-determinism ───────────────────────────────────────────────────────────────────────────────
"$BIN" src --query="escape xml serialize" --format=candidates --top-k=10 --no-cache >"$TMP/det1" 2>/dev/null
"$BIN" src --query="escape xml serialize" --format=candidates --top-k=10 --no-cache >"$TMP/det2" 2>/dev/null
diff -q "$TMP/det1" "$TMP/det2" >/dev/null && ok "candidates byte-deterministic (identical twice)" \
    || no "candidates NON-deterministic"

# ── #7: --format=candidates without --for/--query refuses loudly ───────────────────────────────────────
"$BIN" src --format=candidates --no-cache >/dev/null 2>"$TMP/err"; rc=$?
{ [ "$rc" != 0 ] && grep -qi 'candidates' "$TMP/err"; } \
    && ok "--format=candidates without --for/--query refuses loudly (guarded)" \
    || no "--format=candidates on the plain map did not error as expected (rc=$rc)"

# ── #8: xmllint-clean ──────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    lint=1
    for FF in "$TMP/q10" "$TMP/f7" "$TMP/det1"; do
        xmllint --noout "$FF" 2>/dev/null || { echo "    malformed: $FF"; lint=0; }
    done
    [ "$lint" = 1 ] && ok "candidates output well-formed XML (G4)" || no "candidates output malformed XML"
else
    printf '  SKIP  xmllint (not installed)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
