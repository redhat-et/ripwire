#!/usr/bin/env bash
# lintcheck.sh — S6-A gate: assert each new lint rule fires on test/lintfix/, and that
# output is deterministic (run twice, diff). Does NOT edit test/regression.sh.
#
#   CTXPACK_BIN=build/ctxpack bash test/lintcheck.sh
#   CTXPACK_BIN=asan/ctxpack  bash test/lintcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/lintfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/lintfix dir — fixture missing"; exit 2; }

echo "lintcheck: BIN=$BIN  CORPUS=$CORPUS"

# Run --lint twice; output must be byte-identical (determinism contract).
"$BIN" "$CORPUS" --lint --no-cache >"$TMP/out1" 2>/dev/null
"$BIN" "$CORPUS" --lint --no-cache >"$TMP/out2" 2>/dev/null
diff -q "$TMP/out1" "$TMP/out2" >/dev/null && ok "deterministic (byte-identical run-to-run)" \
    || { no "non-deterministic output"; diff "$TMP/out1" "$TMP/out2" | head -8; }

OUT="$TMP/out1"

# 1. typedef-over-using — C-style typedef struct in C++ (modernisation signal)
grep -q 'typedef-over-using' "$OUT" && ok "typedef-over-using fires" \
    || no "typedef-over-using NOT found in lint output"

# 2. magic-number — numeric literal outside const/constexpr init
grep -q 'magic-number' "$OUT" && ok "magic-number fires" \
    || no "magic-number NOT found in lint output"

# 3. empty-catch — catch block with no body (swallowed exception)
grep -q 'empty-catch' "$OUT" && ok "empty-catch fires" \
    || no "empty-catch NOT found in lint output"

# 4. self-assignment — x = x (always a bug)
grep -q 'self-assign' "$OUT" && ok "self-assign fires" \
    || no "self-assign NOT found in lint output"

# 5. inconsistent-return — bare return in a non-void function that also has value returns
grep -q 'inconsistent-return' "$OUT" && ok "inconsistent-return fires" \
    || no "inconsistent-return NOT found in lint output"

# 6. deep-nesting — nesting depth > 4
grep -q 'deep-nesting' "$OUT" && ok "deep-nesting fires" \
    || no "deep-nesting NOT found in lint output"

# 7. large-function — body > 80 lines
grep -q 'large-function' "$OUT" && ok "large-function fires" \
    || no "large-function NOT found in lint output"

# Overall: no crash (binary must exit 0 on --lint)
"$BIN" "$CORPUS" --lint --no-cache >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "--lint exits 0 (no crash)" || no "--lint crashed (exit $rc)"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
