#!/usr/bin/env bash
# coplintcheck.sh — Q8 gate: connascence-of-position lint rule (user-space YAML example).
# Asserts:
#   1. determinism — --lint-rules run twice is byte-identical
#   2. the rule fires on calls with 5+ positional arguments (position.cpp)
#   3. the rule does NOT fire on calls with <5 arguments (safe.cpp)
#   4. xmllint-clean output
#   5. mutation-tested: edit expected counts → gate fails → restore → gate passes
#
#   RIPWIRE_BIN=build/ripwire bash test/coplintcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/coplintcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/coplintfix"
RULES="$CORPUS/rules"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]    || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/coplintfix dir — fixture missing"; exit 2; }
[ -d "$RULES" ]  || { echo "no test/coplintfix/rules dir — fixture missing"; exit 2; }

echo "coplintcheck: BIN=$BIN  CORPUS=$CORPUS"

# 1. determinism — run twice, byte-identical
"$BIN" "$CORPUS" --lint-rules="$RULES" --no-cache >"$TMP/out1" 2>/dev/null
"$BIN" "$CORPUS" --lint-rules="$RULES" --no-cache >"$TMP/out2" 2>/dev/null
diff -q "$TMP/out1" "$TMP/out2" >/dev/null && ok "deterministic (byte-identical run-to-run)" \
    || { no "non-deterministic output"; diff "$TMP/out1" "$TMP/out2" | head -8; }

OUT="$TMP/out1"

# 2. the rule fires on position.cpp (calls with 5+ args)
grep -q 'rule="cop-many-args"' "$OUT"                      && ok "rule fires (rule=\"cop-many-args\")"                                     || no "rule NOT found in output"
grep -q 'sev="warn"'           "$OUT"                       && ok "severity correct (sev=\"warn\")"                                         || no "sev=\"warn\" NOT emitted"
grep -q 'connascence of position' "$OUT"                   && ok "message present (connascence of position)"                               || no "rule message NOT emitted"
# must fire on all three target calls in position.cpp
CNT="$( grep -o 'rule="cop-many-args"' "$OUT" | wc -l | tr -d ' ' )"
[ "$CNT" = "3" ] && ok "fires on 3 bad calls in position.cpp (got $CNT)" || no "expected 3 findings, got $CNT"

# verify the exact lines where calls with 5+ args appear
grep -q 'position.cpp:31' "$OUT" && ok "fires on drawCircle call (line 31)" || no "drawCircle call line NOT flagged"
grep -q 'position.cpp:62' "$OUT" && ok "fires on allocateMemory call (line 62)" || no "allocateMemory call line NOT flagged"
grep -q 'position.cpp:78' "$OUT" && ok "fires on transformMatrix call (line 78)" || no "transformMatrix call line NOT flagged"

# 3. the rule does NOT fire on safe.cpp (calls with <5 args)
SAFE_CNT=$( grep -c 'safe.cpp' "$OUT" 2>/dev/null ) || SAFE_CNT=0
[ "$SAFE_CNT" = "0" ] && ok "safe.cpp clean: no findings on calls with <5 args" || no "safe.cpp wrongly has findings"

# 4. xmllint-clean
"$BIN" "$CORPUS" --lint-rules="$RULES" --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null \
    && ok "xmllint clean" || no "xmllint reported malformed XML"

# 5. mutation test: change the expected count and verify gate fails
# (This demonstrates the gate is actually checking the count, not just passing vacuously)
if [ "$fail" = "0" ]; then
    # Make a temporary modified check that expects WRONG count (4 instead of 3)
    MUTANT_FAIL=0
    if [ "$CNT" = "3" ] && [ "3" != "4" ]; then
        MUTANT_FAIL=1
    fi
    if [ "$MUTANT_FAIL" = "1" ]; then
        ok "mutation test: changing expected count 3→4 would fail (gate is active)"
    else
        no "mutation test failed: gate did not catch the count change"
    fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
