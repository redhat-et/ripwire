#!/usr/bin/env bash
# cachelintcheck.sh — gate for the cache-friendliness lint pack (src/cachelint.h, built into --lint).
# Asserts, on test/cachefix/:
#   1. determinism — --lint run twice is byte-identical
#   2. the tally header carries every cache-* rule (a rule whose query stopped compiling against the
#      grammar dies SILENTLY as count=0 — the exact-line asserts below are what catch that, and the
#      tally check catches a rule dropped from the pack's name table)
#   3. RECALL — every cache-* rule fires in unfriendly.cpp at its exact pinned line(s)
#   4. PRECISION — friendly.cpp (the same jobs done cache-consciously) produces ZERO cache-* findings
#   5. the three in-loop rules stay LOOP-FENCED: alloc/chase/gather shapes OUTSIDE any loop must not
#      fire (unfriendly.cpp's file-scope vector<Node*> etc. never appear under an in-loop rule)
#   6. xmllint-clean output
# Does NOT edit test/regression.sh (the orchestrator wires it).
#
#   RIPWIRE_BIN=build/ripwire bash test/cachelintcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/cachelintcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/cachefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]    || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/cachefix dir — fixture missing"; exit 2; }

echo "cachelintcheck: BIN=$BIN  CORPUS=$CORPUS"

# 1. determinism
"$BIN" "$CORPUS" --lint --no-cache >"$TMP/out1" 2>/dev/null
"$BIN" "$CORPUS" --lint --no-cache >"$TMP/out2" 2>/dev/null
diff -q "$TMP/out1" "$TMP/out2" >/dev/null && ok "deterministic (byte-identical run-to-run)" \
    || { no "non-deterministic output"; diff "$TMP/out1" "$TMP/out2" | head -8; }
OUT="$TMP/out1"

# 2. every pack rule present in the tally header
for rule in cache-node-container cache-vector-of-raw-ptr cache-vector-of-indirect \
            cache-heap-alloc-in-loop cache-pointer-chase-loop cache-gather-subscript \
            cache-shared-ptr-by-value cache-manual-prefetch; do
    grep -q "rule name=\"$rule\"" "$OUT" && ok "tally row present: $rule" || no "tally row MISSING: $rule"
done

# 3. RECALL — rule id → the exact unfriendly.cpp line(s) it must fire on, space-joined in emit order.
lns(){ grep -oE "rule=\"$1\" [^>]*p=\"[^\"]*unfriendly.cpp:[0-9]+" "$OUT" | grep -oE 'unfriendly.cpp:[0-9]+' | grep -oE '[0-9]+$' | paste -sd' ' - ; }
want(){ # want <rule-id> <expected-lines>
    got="$( lns "$1" )"
    [ "$got" = "$2" ] && ok "$1 fires at exactly: $2" || no "$1 expected lines '$2', got '${got:-none}'"
}
want cache-node-container      "13 14"
want cache-vector-of-raw-ptr   "17 21"
want cache-vector-of-indirect  "18 19 61"
want cache-heap-alloc-in-loop  "25 26 64"
want cache-pointer-chase-loop  "38 80"
want cache-gather-subscript    "47"
want cache-shared-ptr-by-value "51 70"
want cache-manual-prefetch     "79"

# 4. PRECISION — the friendly rewrites must be silent
FRIENDLY_CNT="$( grep -oE 'rule="cache-[a-z-]*" [^>]*p="[^"]*/friendly.cpp' "$OUT" | wc -l | tr -d ' ' )"
[ "$FRIENDLY_CNT" = "0" ] && ok "friendly.cpp is clean (0 cache-* findings)" \
    || { no "friendly.cpp has $FRIENDLY_CNT cache-* findings (precision regression)"; grep -oE 'rule="cache-[^"]*" [^>]*p="[^"]*/friendly.cpp:[0-9]+' "$OUT" | head -8; }

# 5. the loop fence holds — no in-loop rule fires on a line outside every loop (unfriendly.cpp's
# file-scope declarations sit on lines 13-21; an alloc/chase/gather row there means the fence broke)
FENCE_BREACH="$( lns cache-heap-alloc-in-loop; lns cache-pointer-chase-loop; lns cache-gather-subscript )"
case " $FENCE_BREACH " in
    *" 13 "*|*" 14 "*|*" 17 "*|*" 18 "*|*" 19 "*|*" 21 "*) no "an in-loop rule fired at file scope (fence breach): $FENCE_BREACH" ;;
    *) ok "loop fence holds (no in-loop rule at file scope)" ;;
esac

# 6. xmllint-clean
"$BIN" "$CORPUS" --lint --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null \
    && ok "xmllint clean" || no "xmllint reported malformed XML"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
