#!/usr/bin/env bash
# withprofilecheck.sh — gate for --with-profile=FILE, the --lint × #PROF_TSV heat join (the SYZYGY
# advice-mode pairing: static finding shape × measured PMU weight). Asserts, on test/cachefix/ with a
# hand-written #PROF_TSV fixture:
#   1. determinism — the joined run twice is byte-identical
#   2. JOIN — the pointer-chase finding at unfriendly.cpp:38 (inside pointerChase, which opens at L31)
#      gains heat_* from the site at L33, with the fixture's exact values; the root carries heat_joined="1"
#   3. FENCE — a site OUTSIDE every finding's enclosing symbol (file head, L5) annotates NOTHING
#   4. heat_joined="0" is honest, not an error (sites only in friendly.cpp → 0 joins, exit 0)
#   5. refusals: --with-profile alone (no --lint) exits 1; a missing file exits 1; a file with no
#      #PROF_TSV sentinel pair exits 1 — "joined nothing" and "read the wrong file" never look alike
#   6. the heat legend appears ONLY when the flag is armed; bare --lint output carries no heat_*
#   7. xmllint-clean
# Does NOT edit test/regression.sh (the orchestrator wires it).
#
#   RIPWIRE_BIN=build/ripwire bash test/withprofilecheck.sh

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

echo "withprofilecheck: BIN=$BIN  CORPUS=$CORPUS"

# The hand-written profile: one site INSIDE pointerChase (L33 — findings at/after it join), one at
# file scope (L5 — inside no symbol, must join nothing). Format = profileScope.h::print_tsv verbatim.
printf '#PROF_TSV_BEGIN\tone row per scope, aggregated across threads; counters are RAW integers\n' >  "$TMP/prof.txt"
printf 'scope\tfile\tline\tcalls\ttotal_ms\tl1d_mpki\n'                                             >> "$TMP/prof.txt"
printf 'chase walk\tunfriendly.cpp\t33\t12\t48.500\t7.250\n'                                        >> "$TMP/prof.txt"
printf 'file head\tunfriendly.cpp\t5\t1\t1.000\t0.100\n'                                            >> "$TMP/prof.txt"
printf '#PROF_TSV_END\n'                                                                            >> "$TMP/prof.txt"

# 1. determinism
"$BIN" "$CORPUS" --lint --with-profile="$TMP/prof.txt" --no-cache > "$TMP/out1" 2>/dev/null
"$BIN" "$CORPUS" --lint --with-profile="$TMP/prof.txt" --no-cache > "$TMP/out2" 2>/dev/null
diff -q "$TMP/out1" "$TMP/out2" >/dev/null && ok "deterministic (byte-identical run-to-run)" \
    || { no "non-deterministic output"; diff "$TMP/out1" "$TMP/out2" | head -6; }
OUT="$TMP/out1"

# 2. the join — exact row, exact values, root counter
grep -q 'rule="cache-pointer-chase-loop" p="[^"]*unfriendly.cpp:38" in="pointerChase" heat_scope="chase walk" heat_calls="12" heat_total_ms="48.500" heat_l1d_mpki="7.250"' "$OUT" \
    && ok "join: L38 chase finding carries the L33 site's measured values" || no "join row missing or wrong values"
grep -q 'heat_joined="1"' "$OUT" && ok 'root heat_joined="1"' || no 'root heat_joined="1" missing'

# 3. the fence — exactly ONE annotated finding in total (the L5 file-head site joined nothing)
HEATS="$( grep -o 'heat_scope="' "$OUT" | wc -l | tr -d ' ' )"
[ "$HEATS" = "1" ] && ok "fence: exactly 1 annotated finding (file-head site joined nothing)" \
    || no "fence: expected 1 heat_scope, got $HEATS"

# 4. zero joins is honest
printf '#PROF_TSV_BEGIN\thdr\nscope\tfile\tline\tcalls\ttotal_ms\nx\tfriendly.cpp\t2\t1\t1.000\n#PROF_TSV_END\n' > "$TMP/prof0.txt"
"$BIN" "$CORPUS" --lint --with-profile="$TMP/prof0.txt" --no-cache > "$TMP/out0" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && grep -q 'heat_joined="0"' "$TMP/out0" && ok 'zero joins → exit 0 + heat_joined="0"' \
    || no "zero-join case: rc=$rc or heat_joined=0 missing"

# 5. refusals
"$BIN" "$CORPUS" --with-profile="$TMP/prof.txt" --no-cache >/dev/null 2>"$TMP/e1"; rc=$?
[ "$rc" -eq 1 ] && grep -q 'modifies --lint' "$TMP/e1" && ok "flag alone refuses (exit 1, names --lint)" || no "flag-alone: rc=$rc"
"$BIN" "$CORPUS" --lint --with-profile="$TMP/absent.txt" --no-cache >/dev/null 2>"$TMP/e2"; rc=$?
[ "$rc" -eq 1 ] && ok "missing file refuses (exit 1)" || no "missing file: rc=$rc"
printf 'not a profile at all\n' > "$TMP/junk.txt"
"$BIN" "$CORPUS" --lint --with-profile="$TMP/junk.txt" --no-cache >/dev/null 2>"$TMP/e3"; rc=$?
[ "$rc" -eq 1 ] && grep -q 'PROF_TSV' "$TMP/e3" && ok "sentinel-less file refuses (exit 1, names the block)" || no "junk file: rc=$rc"

# 6. the heat legend is armed-only
grep -q 'with-profile: heat_\*' "$OUT" && ok "heat legend present when armed" || no "heat legend missing when armed"
"$BIN" "$CORPUS" --lint --no-cache > "$TMP/plain" 2>/dev/null
grep -q 'heat_' "$TMP/plain" && no "bare --lint leaked heat_* content" || ok "bare --lint carries no heat_* (legend and attrs)"

# 7. xmllint
xmllint --noout "$OUT" 2>/dev/null && ok "xmllint clean" || no "xmllint reported malformed XML"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
