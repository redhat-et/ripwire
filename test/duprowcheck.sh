#!/usr/bin/env bash
# duprowcheck.sh — gate for §P6.3 (dup-row half): the default map must not emit two rows for one
# canonical id. const/non-const overloads (src/infra/svector.h's buf()/buf() const, begin()/begin() const,
# end()/end() const) canonicalize to the SAME id="...svector::buf" — canonicalId() is path::scope::name,
# it has no notion of signature or const-qualification — so before the fix the map printed the identical
# <s t="method" n="buf" id="...svector::buf" k="..."> row twice, byte-for-byte, telling a reader nothing
# extra. Fixture: test/duprowfix/box.h reproduces the identical shape (a const/non-const accessor pair,
# each called once from a third method so the resolver links the call to both candidates).
#
# Usage:  bash test/duprowcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/duprowcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/duprowfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/duprowfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "duprowcheck: BIN=$BIN  CORPUS=test/duprowfix"

OUT="$( "$BIN" test/duprowfix --no-cache 2>/dev/null )"
[ -n "$OUT" ] || { echo "no output — binary or fixture broken"; exit 2; }

# ── 1) exactly one row carries id="...Box::data" — the const/non-const pair is collapsed ──────────────
n_rows="$( printf '%s' "$OUT" | grep -o 'id="box.h::Box::data"' | wc -l | tr -d ' ' )"
[ "$n_rows" = 1 ] \
    && ok "the Box::data overload pair collapses to exactly one <s> row (was 2, byte-identical, pre-fix)" \
    || no "expected exactly 1 row for id=\"...Box::data\", got $n_rows"

# ── 2) the surviving row discloses the multiplicity via overloads="2" ──────────────────────────────────
printf '%s' "$OUT" | grep -q 'id="box.h::Box::data"[^>]*overloads="2"' \
    && ok "the collapsed row carries overloads=\"2\" (the id is the same, so 2 rows carried zero extra info)" \
    || no "collapsed row is missing overloads=\"2\": $( printf '%s' "$OUT" | grep -o '<s[^>]*Box::data[^>]*>' )"

# ── 3) a symbol with NO overload sibling (Box::touch, Box::Box) never carries overloads= ───────────────
printf '%s' "$OUT" | grep -o '<s[^>]*n="touch"[^>]*>' | grep -q 'overloads=' \
    && no "Box::touch (no overload sibling) unexpectedly carries overloads=" \
    || ok "a non-overloaded symbol (Box::touch) carries no overloads= (zero token cost for the common case)"

# ── 4) call edges into the collapsed identity are unaffected — touch() still shows its call(s) ─────────
printf '%s' "$OUT" | grep -o '<s[^>]*n="touch"[^>]*>[^<]*<c[^/]*/>' | grep -q 'n="data"' \
    && ok "call edges into the collapsed id are still emitted (touch() -> data())" \
    || no "call edge into the collapsed id went missing"

# ── 5) xml well-formed (G4) ─────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT" | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── 6) determinism — two runs byte-identical ────────────────────────────────────────────────────────────
OUT2="$( "$BIN" test/duprowfix --no-cache 2>/dev/null )"
[ "$OUT" = "$OUT2" ] && ok "deterministic (byte-identical run-to-run)" || no "non-deterministic output"

# ── 8) §A8.7: the v1 legend closes the shown=/overloads= arithmetic — the ONE clause a reader needs to
# know rows + Σ(overloads-1) == shown, which was previously true but undocumented.
printf '%s' "$OUT" | grep -oE '<!-- ripwire v1[^>]*-->' | grep -q 'overloads=' \
    && ok "§A8.7: the v1 legend documents overloads=" \
    || no "§A8.7: the v1 legend has no overloads= clause"

# ── 9) §A8.7: the arithmetic itself, on THIS fixture (one collapsed row, overloads=\"2\") — rows +
# Σ(overloads-1) == shown=. Box::data collapses 2 defs into 1 row (contributes +1); every other row
# carries no overloads= (absent ⇒ weight 1, contributes 0).
ROWS="$( printf '%s' "$OUT" | grep -o '<s ' | wc -l | tr -d ' ' )"
SHOWN="$( printf '%s' "$OUT" | grep -oE '<!-- files=[^>]*-->' | grep -oE 'shown=[0-9]+' | grep -oE '[0-9]+$' )"
OVERLOAD_EXTRA=0
for ov in $( printf '%s' "$OUT" | grep -oE 'overloads="[0-9]+"' | grep -oE '"[0-9]+"' | tr -d '"' ); do
    OVERLOAD_EXTRA=$(( OVERLOAD_EXTRA + ov - 1 ))
done
{ [ -n "$ROWS" ] && [ -n "$SHOWN" ] && [ "$(( ROWS + OVERLOAD_EXTRA ))" = "$SHOWN" ]; } \
    && ok "§A8.7: rows=$ROWS + Σ(overloads-1)=$OVERLOAD_EXTRA == shown=$SHOWN" \
    || no "§A8.7: arithmetic broken (rows=$ROWS overload_extra=$OVERLOAD_EXTRA shown=$SHOWN)"

# ── 7) golden-neutral — the default map on test/fixture (no overload collisions there) is unaffected ──
if [ -f "$ROOT/test/golden.xml" ]; then
    "$BIN" test/fixture --no-cache 2>/dev/null | diff -q - "$ROOT/test/golden.xml" >/dev/null \
        && ok "golden-neutral: test/fixture default map byte-identical to test/golden.xml" \
        || no "default map drifted on the golden fixture (no overload collision expected there)"
else
    ok "golden.xml absent — skipped"
fi

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit $fail
