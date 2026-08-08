#!/usr/bin/env bash
# outlinecheck.sh — gate for --outline=A,B (the L3 rung of the detail ladder). Before this gate --outline
# had SMOKE-only coverage (xmlwellformed / compresscheck touch it but assert nothing about the skeleton).
# --outline is a CONTROL-FLOW skeleton: it keeps the function signature and the control-flow scaffold
# (if/for/while/switch headers) but ELIDES straight-line statement bodies (replaced with a `...` marker).
# The contract that matters — and the bug class this gate exists to catch — is exactly that elision:
#   (1) control-flow HEADERS are preserved verbatim   — an agent reads the shape without the noise
#   (2) inner straight-line statements are DROPPED     — the whole point (fewer tokens than --expand)
#   (3) a body-less function comes through whole        — nothing to elide, don't mangle it
#   (4) output is smaller than the raw source of the same symbol (--expand) — the token win is real
#
# Self-contained synthetic fixture with a KNOWN control-flow shape:
#   classify(n):  if(n<0){ return SENTINEL_NEG; }  for(...){ if(i==3){ return i; } }  while(n>100){ n = SENTINEL_HALVE; }  return n;
#   plain():      return 42;                       (no control flow — passes through whole)
# The two SENTINEL_* tokens are unique strings that live ONLY inside elided blocks, so their ABSENCE from
# the skeleton is a precise witness that block bodies were dropped (not just "output looks shorter").
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/outlinecheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "outlinecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R"
cat >"$R/cf.cpp" <<'EOF'
int classify( int n )
{
    if( n < 0 )
    {
        return SENTINEL_NEG;
    }
    for( int i = 0; i < n; ++i )
    {
        if( i == 3 ) { return i; }
    }
    while( n > 100 )
    {
        n = SENTINEL_HALVE;
    }
    return n;
}
int plain() { return 42; }
EOF
# make the sentinels compile-irrelevant (this fixture is never compiled; ripwire only parses text)

run(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" "$@" --no-cache 2>/dev/null; }
OUT="$( run --outline=classify )"

# ── 1) control-flow HEADERS preserved (the skeleton keeps the shape) ─────────────────────────────────
{ printf '%s' "$OUT" | grep -q 'if( n < 0 )' \
    && printf '%s' "$OUT" | grep -q 'for( int i = 0; i < n; ++i )' \
    && printf '%s' "$OUT" | grep -q 'while( n > 100 )'; } \
    && ok "--outline preserves control-flow headers (if / for / while)" \
    || no "--outline dropped a control-flow header — got: $( printf '%s' "$OUT" | tr -d '\n' | head -c 300 )"

# ── 2) the signature line is preserved ───────────────────────────────────────────────────────────────
printf '%s' "$OUT" | grep -q 'int classify( int n )' \
    && ok "--outline preserves the function signature" \
    || no "--outline dropped the signature"

# ── 3) inner block bodies ELIDED — the two sentinel tokens live only inside elided blocks and must vanish
{ ! printf '%s' "$OUT" | grep -q 'SENTINEL_NEG' && ! printf '%s' "$OUT" | grep -q 'SENTINEL_HALVE'; } \
    && ok "--outline ELIDES straight-line block bodies (SENTINEL_NEG / SENTINEL_HALVE both dropped)" \
    || no "--outline did NOT elide block bodies — a sentinel survived (SENTINEL_NEG=$( printf '%s' "$OUT" | grep -c SENTINEL_NEG ) SENTINEL_HALVE=$( printf '%s' "$OUT" | grep -c SENTINEL_HALVE ))"

# ── 4) an elision MARKER is present (the `...` placeholder proves elision, not truncation) ────────────
printf '%s' "$OUT" | grep -qF '...' \
    && ok "--outline emits a '...' elision marker where a block body was dropped" \
    || no "--outline has no '...' elision marker"

# ── 5) a body-less function passes through WHOLE (nothing to elide) ──────────────────────────────────
PLAIN="$( run --outline=plain )"
printf '%s' "$PLAIN" | grep -q 'int plain() { return 42; }' \
    && ok "--outline=plain: body-less function reproduced whole (nothing elided)" \
    || no "--outline mangled a body-less function — got: $( printf '%s' "$PLAIN" | grep -oE '<o[^<]*<!\[CDATA\[[^]]*' | head -c 200 )"

# ── 6) the token win is REAL: outline of classify < its full body (--expand) ─────────────────────────
# M6 (density audit 2026-08-08): compared at --top-k=0 (payload vs payload). A bare --expand now
# auto-serves the CHEAPEST complete answer (test/expandmodecheck.sh) — on this small fixture that is the
# whole FILE, which made the old bare-vs-bare comparison measure the serving mode, not the elision. The
# claim this arm exists for is "the skeleton is smaller than the full body", and the lean forms compare
# exactly that.
OLEN="$( run --outline=classify --top-k=0 | wc -c | tr -d ' ' )"
ELEN="$( run --expand=classify  --top-k=0 | wc -c | tr -d ' ' )"
{ [ "$OLEN" -gt 0 ] && [ "$ELEN" -gt 0 ] && [ "$OLEN" -lt "$ELEN" ]; } \
    && ok "--outline smaller than --expand for classify ($OLEN < $ELEN bytes, both at --top-k=0) — the elision saves tokens" \
    || no "--outline not smaller than --expand (outline=$OLEN expand=$ELEN, both at --top-k=0)"

# ── 7) determinism + xml well-formed ────────────────────────────────────────────────────────────────
[ "$( run --outline=classify )" = "$( run --outline=classify )" ] \
    && ok "--outline deterministic (byte-identical run-to-run)" || no "--outline non-deterministic"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT" | xmllint --noout - 2>/dev/null && ok "--outline xml well-formed" || no "--outline xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
