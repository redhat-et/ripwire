#!/usr/bin/env bash
# selfcontainedcheck.sh — the executable must not consult the source checkout for tags queries.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
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
cp "$ROOT/test/elixirfix/math.ex" "$TMP/isolated/corpus/"
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

if python3 - "$TMP/a.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
syms = {s.get('n'): s for s in ET.parse(sys.argv[1]).iter('s')}
assert {'Sample.Math', 'square', 'twice', 'secret', 'answer'} <= set(syms)
assert 'square' in {c.get('n') for c in syms['twice'].iter('c')}
assert 'secret' in {c.get('n') for c in syms['answer'].iter('c')}
PY
then
    ok "isolated binary extracts Elixir definitions and call edges"
else
    no "isolated binary did not extract Elixir definitions and call edges"
fi

# Execute the generated C++ interface, rather than trusting a source-text count. When
# testing an installed binary, configure the source tree in scratch space to obtain its query model.
generatedDir="$( dirname "$BIN" )/generated"
if [ ! -f "$generatedDir/embedded_queries.h" ]; then
    if cmake -S "$ROOT" -B "$TMP/query-model" -DFETCHCONTENT_FULLY_DISCONNECTED=ON >"$TMP/configure.log" 2>&1; then
        generatedDir="$TMP/query-model/generated"
    else
        no "could not configure the embedded-query model"
        cat "$TMP/configure.log"
    fi
fi
cat > "$TMP/query-model.cpp" <<'CPP'
#include "embedded_queries.h"
#include <cstdio>

/// Emit each embedded query's name and exact bytes through the public generated lookup interface.
int main()
{
    for( const auto& query : rw::embedded_queries::kEmbeddedQueries )
    {
        const auto source = rw::embedded_queries::queryFor( query.sub );
        if( source != query.source ) return 1;
        std::printf( "%.*s\t", int( query.sub.size() ), query.sub.data() );
        for( unsigned char byte : source ) std::printf( "%02x", unsigned( byte ) );
        std::putchar( '\n' );
    }
}
CPP
if "${CXX:-c++}" -std=c++17 -I"$generatedDir" "$TMP/query-model.cpp" -o "$TMP/query-model-bin" \
    && "$TMP/query-model-bin" > "$TMP/queries.tsv" \
    && python3 - "$ROOT/queries" "$TMP/queries.tsv" <<'PYQUERIES'
import pathlib, sys
expected = {p.parent.name: p.read_bytes() for p in pathlib.Path(sys.argv[1]).glob('*/tags.scm')}
rows = [line.split('\t') for line in pathlib.Path(sys.argv[2]).read_text().splitlines()]
actual = {name: bytes.fromhex(source) for name, source in rows}
assert len(actual) == len(rows), 'duplicate embedded query names'
assert expected and actual == expected, f'query set or contents differ: missing={expected.keys()-actual.keys()}, extra={actual.keys()-expected.keys()}'
PYQUERIES
then
    ok "generated lookup serves every committed query with identical contents and no extras"
else
    no "complete embedded-query inventory or contents differ from committed queries"
fi

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
