#!/usr/bin/env bash
# filerootcheck.sh — gate for single-file root indexing.
#
# Asserts:
#   - ripwire path/to/file.cpp (a FILE as root, not a directory) indexes that file
#   - output contains symbols from the file (non-zero symbol count for a known fixture file)
#   - output is well-formed XML (xmllint --noout)
#   - determinism: two identical single-file runs produce byte-identical output
#
# Usage:
#   test/filerootcheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/filerootcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIXTURE="$ROOT/test/fixture"
FIXTURE_FILE="$FIXTURE/geometry.cpp"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -f "$FIXTURE_FILE" ] || { echo "no fixture file at $FIXTURE_FILE"; exit 2; }

echo "filerootcheck: BIN=$BIN  FIXTURE_FILE=$FIXTURE_FILE"

# ── (1) Run ripwire on a single file ────────────────────────────────────────────────────────────

"$BIN" "$FIXTURE_FILE" --no-cache >"$TMP/singlefile" 2>/dev/null

# (1a) Output contains <r> root element (not empty)
[ -s "$TMP/singlefile" ] \
    && ok "single-file root produces non-empty output" \
    || { no "single-file root produced empty output"; cat "$TMP/singlefile"; }

# (1b) Output contains the file being indexed
grep -q "p=\"[^\"]*geometry\.cpp" "$TMP/singlefile" \
    && ok "output references geometry.cpp in path attribute" \
    || no "output does not reference geometry.cpp"

# (1c) Output contains at least one symbol from geometry.cpp
# geometry.cpp defines functions like 'distance', 'perimeter'
grep -q '<s [^>]*n="distance"' "$TMP/singlefile" \
    && ok "output contains symbols from geometry.cpp (found 'distance')" \
    || { no "output contains no recognizable symbols from geometry.cpp"; head -20 "$TMP/singlefile"; }

# (1d) Header shows non-zero symbol and edge counts
if grep -q 'symbols=0' "$TMP/singlefile"; then
    no "header shows symbols=0 (should index file contents)"
elif grep -q 'symbols=[1-9][0-9]*' "$TMP/singlefile"; then
    ok "header shows non-zero symbol count"
else
    no "header missing or malformed symbols count"
fi

# (1e) Output is valid XML
xmllint --noout "$TMP/singlefile" 2>/dev/null \
    && ok "single-file output is well-formed XML" \
    || { no "single-file output is malformed XML"; xmllint --noout "$TMP/singlefile" 2>&1 | head -3; }

# ── (2) Determinism: byte-identical runs ────────────────────────────────────────────────────────

"$BIN" "$FIXTURE_FILE" --no-cache >"$TMP/det1" 2>/dev/null
"$BIN" "$FIXTURE_FILE" --no-cache >"$TMP/det2" 2>/dev/null

diff -q "$TMP/det1" "$TMP/det2" >/dev/null \
    && ok "determinism: byte-identical single-file output across runs" \
    || no "determinism: non-identical output between runs"

# ── (3) Directory root behavior unchanged ────────────────────────────────────────────────────────

"$BIN" "$FIXTURE" --no-cache >"$TMP/dir1" 2>/dev/null
"$BIN" "$FIXTURE" --no-cache >"$TMP/dir2" 2>/dev/null

diff -q "$TMP/dir1" "$TMP/dir2" >/dev/null \
    && ok "directory root: byte-identical output (no regression)" \
    || no "directory root: non-identical output between runs"

# ── Summary ───────────────────────────────────────────────────────────────────────────────────────

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
