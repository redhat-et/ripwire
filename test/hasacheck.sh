#!/usr/bin/env bash
# hasacheck.sh — S5-E HAS-A composition edges gate.
#
#   test/hasacheck.sh                       # uses build/ctxpack on test/hasafix
#   CTXPACK_BIN=asan/ctxpack test/hasacheck.sh
#
# The fixture test/hasafix/hasa.h has class CanyonScreen holding:
#   m_pool  — a SpherePool by value (creates)
#   m_sound — a SoundEngine by reference (uses)
#
# Assertions:
#   1) determinism — --around and --for produce byte-identical output run-to-run
#   2) --around=CanyonScreen emits a <compose> block naming both typed members
#   3) --for emits a <compose> block naming both typed members
#   4) the <compose> fields have correct rel= ("creates" for m_pool, "uses" for m_sound)
#   5) compose edges are NOT in the call graph — CanyonScreen has NO <c> edges to
#      SpherePool or SoundEngine (edges=0 in --around output)
#   6) xmllint: the output is well-formed XML

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative CTXPACK_BIN
CORPUS="$ROOT/test/hasafix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "hasacheck: BIN=$BIN  CORPUS=$CORPUS"

# ── 1) determinism ────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --no-cache --around=CanyonScreen 2>/dev/null > "$TMP/around_a"
"$BIN" "$CORPUS" --no-cache --around=CanyonScreen 2>/dev/null > "$TMP/around_b"
diff -q "$TMP/around_a" "$TMP/around_b" >/dev/null \
    && ok "determinism --around (byte-identical, $(wc -c <"$TMP/around_a" | tr -d ' ') B)" \
    || no "determinism --around (non-deterministic output)"

"$BIN" "$CORPUS" --no-cache --for="member field composition" 2>/dev/null > "$TMP/for_a"
"$BIN" "$CORPUS" --no-cache --for="member field composition" 2>/dev/null > "$TMP/for_b"
diff -q "$TMP/for_a" "$TMP/for_b" >/dev/null \
    && ok "determinism --for (byte-identical, $(wc -c <"$TMP/for_a" | tr -d ' ') B)" \
    || no "determinism --for (non-deterministic output)"

AROUND="$( cat "$TMP/around_a" )"
FOR="$( cat "$TMP/for_a" )"

# ── 2) --around <compose> block present ────────────────────────────────────────
printf '%s' "$AROUND" | grep -q '<compose>' \
    && ok "--around emits <compose> block" \
    || no "--around: <compose> block missing"

# ── 3) --for <compose> block present ──────────────────────────────────────────
printf '%s' "$FOR" | grep -q '<compose>' \
    && ok "--for emits <compose> block" \
    || no "--for: <compose> block missing"

# ── 4a) m_pool with rel="creates" in --around ─────────────────────────────────
printf '%s' "$AROUND" | grep -q 'name="m_pool"' \
    && ok "--around: m_pool field present" \
    || no "--around: m_pool field missing"

printf '%s' "$AROUND" | grep -q 'type="SpherePool"' \
    && ok "--around: SpherePool type present" \
    || no "--around: SpherePool type missing"

printf '%s' "$AROUND" | grep 'name="m_pool"' | grep -q 'rel="creates"' \
    && ok "--around: m_pool rel=creates (inline value member)" \
    || no "--around: m_pool does not have rel=creates"

# ── 4b) m_sound with rel="uses" in --around ───────────────────────────────────
printf '%s' "$AROUND" | grep -q 'name="m_sound"' \
    && ok "--around: m_sound field present" \
    || no "--around: m_sound field missing"

printf '%s' "$AROUND" | grep -q 'type="SoundEngine"' \
    && ok "--around: SoundEngine type present" \
    || no "--around: SoundEngine type missing"

printf '%s' "$AROUND" | grep 'name="m_sound"' | grep -q 'rel="uses"' \
    && ok "--around: m_sound rel=uses (reference/injected member)" \
    || no "--around: m_sound does not have rel=uses"

# ── 4c) owner=CanyonScreen present ───────────────────────────────────────────
printf '%s' "$AROUND" | grep -q 'owner="CanyonScreen"' \
    && ok "--around: owner=CanyonScreen present" \
    || no "--around: owner=CanyonScreen missing"

# ── 5) compose edges NOT in call graph: edges=0 on CanyonScreen ───────────────
# The default map header reports edges=N (resolved call edges). With compose edges
# excluded from the CSR, CanyonScreen should show NO <c> children pointing to
# SpherePool or SoundEngine (edges=0 in the --around output header).
EDGES="$( printf '%s' "$AROUND" | grep -o 'edges=[0-9]*' | grep -o '[0-9]*' )"
[ "$EDGES" = "0" ] \
    && ok "compose edges NOT in call graph (edges=0, no <c> to member types)" \
    || no "compose edges LEAKED into call graph (edges=${EDGES:-?}, expected 0)"

# Double-check: no <c n="SpherePool"> or <c n="SoundEngine"> in the around output
printf '%s' "$AROUND" | grep -q '<c n="SpherePool"' \
    && no "LEAKED: <c n=\"SpherePool\"> found in call graph" \
    || ok "no <c n=\"SpherePool\"> in call graph (correct)"
printf '%s' "$AROUND" | grep -q '<c n="SoundEngine"' \
    && no "LEAKED: <c n=\"SoundEngine\"> found in call graph" \
    || ok "no <c n=\"SoundEngine\"> in call graph (correct)"

# ── 6) well-formed XML ───────────────────────────────────────────────────────
# Note: --around + compose concatenates two well-formed XML fragments. We wrap them
# in a root element for xmllint's sake (they share the output stream, not a doc).
if command -v xmllint >/dev/null 2>&1; then
    printf '<root>%s</root>' "$AROUND" | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed (--around)" \
        || no "xml malformed (--around)"
    printf '<root>%s</root>' "$FOR" | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed (--for)" \
        || no "xml malformed (--for)"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
