#!/usr/bin/env bash
# compresscheck.sh — gate for P2-B: --compress body output stripping.
#
# Usage:
#   test/compresscheck.sh                          # uses build/ripwire on test/compressfix
#   RIPWIRE_BIN=asan/ripwire test/compresscheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# DO NOT edit regression.sh — this is a standalone gate invoked from there.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/compressfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/compressfix directory"; exit 2; }

echo "compresscheck: BIN=$BIN  CORPUS=$CORPUS"

# Run --expand on computeArea WITH --compress, capture the body output.
"$BIN" "$CORPUS" --expand=computeArea --compress --no-cache >"$TMP/compressed.xml" 2>/dev/null
rc=$?
if [ $rc -eq 0 ]; then ok "--expand --compress exits 0"; else no "--expand --compress failed (rc=$rc)"; fi

# Run the SAME expand WITHOUT --compress to have a baseline for comparison.
"$BIN" "$CORPUS" --expand=computeArea --no-cache >"$TMP/uncompressed.xml" 2>/dev/null

# 1) The function body is still present (the function name appears in the <b> element).
if grep -q 'computeArea' "$TMP/compressed.xml"; then ok "function still present (computeArea)"; else no "function missing from compressed output"; fi

# 2) Block comments ARE present in the uncompressed output.
if grep -q 'block comment inside function' "$TMP/uncompressed.xml"; then ok "block comment present WITHOUT --compress (baseline OK)"; else no "block comment missing from uncompressed baseline (fixture or expand broken)"; fi

# 3) Block comments are GONE after --compress.
grep -q 'block comment inside function' "$TMP/compressed.xml" && no "block comment still present WITH --compress (should be stripped)" || ok "block comment stripped by --compress"

# 4) Line comments are GONE after --compress.
grep -q 'line comment inside function' "$TMP/compressed.xml" && no "line comment still present WITH --compress (should be stripped)" || ok "line comment stripped by --compress"

# 5) The string literal "http://example.com // not a comment inside a string" is PRESERVED.
#    We grep for the URL host part which would be cut by a naive // stripper.
if grep -q 'http://example.com' "$TMP/compressed.xml"; then ok "string literal URL preserved (http://example.com survived)"; else no "string literal URL was corrupted by --compress"; fi

# 6) The string "/* not a comment */" content is PRESERVED.
if grep -q 'not a comment' "$TMP/compressed.xml"; then ok "string literal block-comment lookalike preserved"; else no "string literal '/* not a comment */' was corrupted by --compress"; fi

# 7) The compressed output is smaller than the uncompressed output (compression actually does something).
sz_c="$( wc -c <"$TMP/compressed.xml" | tr -d ' ' )"
sz_u="$( wc -c <"$TMP/uncompressed.xml" | tr -d ' ' )"
if [ "$sz_c" -lt "$sz_u" ]; then ok "compressed output is smaller ($sz_c B < $sz_u B)"; else no "compressed output is not smaller ($sz_c B >= $sz_u B)"; fi

# 8) --compress is deterministic: two runs must be byte-identical.
"$BIN" "$CORPUS" --expand=computeArea --compress --no-cache >"$TMP/c2.xml" 2>/dev/null
if diff -q "$TMP/compressed.xml" "$TMP/c2.xml" >/dev/null; then ok "--compress deterministic (byte-identical)"; else no "--compress nondeterministic"; fi

# 9) Without --compress, comments survive (confirms the flag is the differentiator, not some other stripping).
if grep -q 'line comment inside function' "$TMP/uncompressed.xml"; then ok "without --compress, comments are present (flag is the differentiator)"; else no "without --compress, comments already absent (flag has no effect?)"; fi

# 10) --outline also works with --compress.
"$BIN" "$CORPUS" --outline=computeArea --compress --no-cache >"$TMP/outline_c.xml" 2>/dev/null
rc_ol=$?
if [ $rc_ol -eq 0 ]; then ok "--outline --compress exits 0"; else no "--outline --compress failed (rc=$rc_ol)"; fi
if grep -q 'computeArea' "$TMP/outline_c.xml"; then ok "--outline --compress: function present"; else no "--outline --compress: function missing"; fi

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
