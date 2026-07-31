#!/usr/bin/env bash
# columnarcommacheck.sh — A4-F15 gate: columnar.h's ',' field separator must not mis-zip a parallel-array
# row when the emitted VALUE itself contains a literal comma (a markdown SECTION name like
# "results, discussion"; a canonical id embedding a comma-bearing path).
#
# The real end-to-end CLI path to land a comma in a `name`/`in` field needs a markdown section symbol that
# the flat-list verbs (--callers/--callees/--uses/--impact) don't naturally surface (Sections never call
# and doc-mention references are excluded from --uses). So this gate drives emitColumnarSymbolRows /
# emitColumnarUseSites DIRECTLY with a synthetic IngestResult via a small standalone .cpp (compiled here
# with plain clang++ — columnar.h is header-only, no CMake wiring needed), which is a more precise and
# deterministic reproduction of exactly the code path the finding is about.
#
# Checks:
#   (1) build succeeds
#   (2) the <name> array in the symbol-rows output has EXACTLY 3 naive-comma-split fields for 3 rows
#       (proves the comma inside "results, discussion" was escaped, not treated as a 4th field separator)
#   (3) the <in_id> array in the use-sites output has EXACTLY 2 naive-comma-split fields for 2 rows
#   (4) the comma-bearing value round-trips: "results&#44; discussion" appears verbatim (the escape marker)
#       and the RAW un-escaped comma does NOT appear as a bare ',' inside either array
#   (5) output is well-formed XML (xmllint)
#
# Usage: bash test/columnarcommacheck.sh
# Exits non-zero on any failure; DOES NOT touch regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
SRC="$ROOT/test/columnarcommafix/columnar_comma_test.cpp"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "columnarcommacheck: SRC=$SRC"

CXX="${CXX:-clang++}"
"$CXX" -std=c++23 -I "$ROOT/src" -I "$ROOT/src/infra" -I "$ROOT/third_party" "$SRC" -o "$TMP/t" 2>"$TMP/build.err"
if [ -x "$TMP/t" ]; then
    ok "standalone gate binary built"
else
    no "build failed"; cat "$TMP/build.err"; echo "FAILURES ABOVE"; exit 1
fi

"$TMP/t" "$TMP/out.txt"
rc=$?
[ $rc -eq 0 ] && ok "gate binary exits 0" || { no "gate binary exited $rc"; exit 1; }

SYM_LINE="$( sed -n '/^SYMROWS_BEGIN$/,/^SYMROWS_END$/p' "$TMP/out.txt" | sed -n 2p )"
USE_LINE="$( sed -n '/^USESROWS_BEGIN$/,/^USESROWS_END$/p' "$TMP/out.txt" | sed -n 2p )"

# §P8 (2026-07-28) — REPINNED: the --uses columnar column `in` became `in_id`. The XML attribute it
# mirrors carried a canonical ID under the spelling that means an enclosing NAME in grep/lint and a
# fan-in COUNT in for/pack-task; the id meaning had zero consumers, so it was the one that moved. The
# comma-escaping contract this gate exists for is unchanged — only the column's name is.
# extract the <name>...</name> and <in_id>...</in_id> array bodies
NAME_ARR="$( printf '%s' "$SYM_LINE" | grep -oE '<name>[^<]*</name>' | sed -E 's/<name>(.*)<\/name>/\1/' )"
IN_ARR="$(   printf '%s' "$USE_LINE" | grep -oE '<in_id>[^<]*</in_id>' | sed -E 's/<in_id>(.*)<\/in_id>/\1/' )"

[ -n "$NAME_ARR" ] && ok "extracted <name> array: $NAME_ARR" || no "could not extract <name> array"
[ -n "$IN_ARR" ]   && ok "extracted <in_id> array: $IN_ARR"     || no "could not extract <in_id> array"

# (2)/(3) field count via naive ',' split must equal the row count (3 and 2), NOT more.
NAME_FIELDS="$( awk -F',' '{print NF}' <<<"$NAME_ARR" )"
IN_FIELDS="$(   awk -F',' '{print NF}' <<<"$IN_ARR" )"
[ "$NAME_FIELDS" -eq 3 ] && ok "name array: naive comma-split field count == row count (3)" \
    || no "name array MIS-ZIPPED: naive comma-split gives $NAME_FIELDS fields, want 3 (comma leaked as a separator)"
[ "$IN_FIELDS" -eq 2 ] && ok "in array: naive comma-split field count == row count (2)" \
    || no "in array MIS-ZIPPED: naive comma-split gives $IN_FIELDS fields, want 2 (comma leaked as a separator)"

# (4) the comma-bearing value must round-trip via the escape marker, and no bare comma inside the value.
printf '%s' "$NAME_ARR" | grep -q 'results&#44; discussion' \
    && ok "name array carries the escaped value 'results&#44; discussion'" \
    || no "name array missing the expected escaped value (got: $NAME_ARR)"
printf '%s' "$IN_ARR" | grep -q 'results&#44; discussion' \
    && ok "in array carries the escaped value 'results&#44; discussion'" \
    || no "in array missing the expected escaped value (got: $IN_ARR)"

# (5) well-formed XML
if command -v xmllint >/dev/null 2>&1; then
    { printf '%s\n' "$SYM_LINE"; } | xmllint --noout - 2>/dev/null \
        && ok "symbol-rows output is well-formed XML" || no "symbol-rows output malformed XML"
    { printf '%s\n' "$USE_LINE"; } | xmllint --noout - 2>/dev/null \
        && ok "use-sites output is well-formed XML" || no "use-sites output malformed XML"
else
    printf '  SKIP  xmllint (not installed)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
