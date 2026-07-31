#!/usr/bin/env bash
# deadcheck.sh — the S5-A --dead-code detection gate.
#
#   test/deadcheck.sh                       # uses build/ripwire on test/deadfix
#   RIPWIRE_BIN=asan/ripwire test/deadcheck.sh
#
# The fixture test/deadfix/ contains:
#   (a) orphan()      — internal static definition, NEVER called in the tree → MUST appear in --dead-code
#   (b) worker()      — defined in deadfix.cpp, called by driver()       → must NOT appear
#   (c) exportedApi() — defined in deadfix.h (a header)                  → must NOT appear (exported exclusion)
#
# Additionally:
#   - Determinism: run twice, byte-identical output.
#   - Well-formed XML (if xmllint is available).
#   - Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/deadfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "deadcheck: BIN=$BIN  CORPUS=$CORPUS"

# 1) determinism — same input, byte-identical output run-to-run
"$BIN" "$CORPUS" --dead-code --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --dead-code --no-cache >"$TMP/b" 2>/dev/null
diff -q "$TMP/a" "$TMP/b" >/dev/null \
    && ok "determinism (byte-identical, $(wc -c <"$TMP/a" | tr -d ' ') B)" \
    || no "determinism (non-deterministic output)"

DEAD="$( cat "$TMP/a" )"

# 2) orphan() MUST appear in --dead-code (in-degree == 0, defined in .cpp)
printf '%s' "$DEAD" | grep -q 'n="orphan"' \
    && ok "orphan() appears in --dead-code (unreachable, in-degree=0)" \
    || { no "orphan() missing from --dead-code output"; printf '    %s\n' "$DEAD"; }

# 3) worker() must NOT appear — it is called by driver()
printf '%s' "$DEAD" | grep -q 'n="worker"' \
    && { no "worker() wrongly appears in --dead-code (it is called by driver)"; printf '    %s\n' "$DEAD"; } \
    || ok "worker() absent from --dead-code (has a caller — correct)"

# 4) exportedApi() must NOT appear — it is defined in a .h header (export exclusion)
printf '%s' "$DEAD" | grep -q 'n="exportedApi"' \
    && { no "exportedApi() wrongly appears in --dead-code (header-defined, must be excluded)"; printf '    %s\n' "$DEAD"; } \
    || ok "exportedApi() absent from --dead-code (header-defined — exported exclusion correct)"

# 5) driver() must NOT appear — zero callers alone is not enough evidence for an external-linkage entry point.
printf '%s' "$DEAD" | grep -q 'n="driver"' \
    && { no "driver() wrongly appears in high-confidence --dead-code (external linkage)"; printf '    %s\n' "$DEAD"; } \
    || ok "driver() absent from --dead-code (external-linkage entry point — correct)"

# 6) well-formed XML
command -v xmllint >/dev/null 2>&1 \
    && { printf '%s' "$DEAD" | xmllint --noout - 2>/dev/null \
         && ok "xml well-formed" || no "xml malformed"; } \
    || ok "xml well-formed (xmllint absent — skipped)"

# 7) count sanity — must have at least 1 candidate (orphan)
COUNT="$( printf '%s' "$DEAD" | grep -o 'count="[0-9]*"' | grep -o '[0-9]*' )"
[ -n "$COUNT" ] && [ "$COUNT" -ge 1 ] \
    && ok "dead-code count >= 1 (found $COUNT candidate(s))" \
    || no "dead-code count is zero or missing (expected at least orphan)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
