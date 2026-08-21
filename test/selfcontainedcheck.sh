#!/usr/bin/env bash
# selfcontainedcheck.sh — the executable must not consult the source checkout for tags queries.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { printf 'no ripwire binary at %s\n' "$BIN"; exit 2; }

if strings "$BIN" | grep -Fq "$ROOT/queries"; then
    no "binary contains the source-tree query path"
else
    ok "binary contains no source-tree query path"
fi

if rg -n 'RIPWIRE_QUERY_DIR' "$ROOT/CMakeLists.txt" "$ROOT/src" >/dev/null; then
    no "build/source still defines RIPWIRE_QUERY_DIR"
else
    ok "no RIPWIRE_QUERY_DIR build seam remains"
fi

mkdir -p "$TMP/isolated/corpus"
cp "$BIN" "$TMP/isolated/ripwire"
cp "$ROOT/test/fixture/geometry.cpp" "$ROOT/test/fixture/geometry.h" "$TMP/isolated/corpus/"

( cd / && "$TMP/isolated/ripwire" "$TMP/isolated/corpus" --no-cache >"$TMP/a.xml" 2>"$TMP/a.err" )
rc=$?
( cd / && "$TMP/isolated/ripwire" "$TMP/isolated/corpus" --no-cache >"$TMP/b.xml" 2>"$TMP/b.err" )

if [ "$rc" = 0 ] && grep -q ' n="distance"' "$TMP/a.xml" && ! grep -q 'tags.scm' "$TMP/a.err"; then
    ok "isolated copied binary parses a representative corpus"
else
    no "isolated copied binary did not parse cleanly"
fi

if diff -q "$TMP/a.xml" "$TMP/b.xml" >/dev/null; then
    ok "isolated output is byte-deterministic"
else
    no "isolated output is not deterministic"
fi

if command -v xmllint >/dev/null 2>&1 && xmllint --noout "$TMP/a.xml" 2>/dev/null; then
    ok "isolated output is well-formed XML"
else
    no "isolated output is not well-formed XML or xmllint is unavailable"
fi

queryCount="$( find "$ROOT/queries" -mindepth 2 -maxdepth 2 -name tags.scm | wc -l | tr -d ' ' )"
generatedHeader="$( dirname "$BIN" )/generated/embedded_queries.h"
if [ "$queryCount" = 18 ] && [ -f "$generatedHeader" ] \
    && grep -q 'kEmbeddedQueryCount = 18' "$generatedHeader"; then
    ok "generated table accounts for all 18 committed query sources"
else
    no "generated table does not prove coverage of all 18 query sources"
fi

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
