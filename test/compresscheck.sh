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

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/compressfix directory"; exit 2; }

echo "compresscheck: BIN=$BIN  CORPUS=$CORPUS"

# Run --expand on computeArea WITH --compress, capture the body output.
"$BIN" "$CORPUS" --expand=computeArea --compress --no-cache >"$TMP/compressed.xml" 2>/dev/null
rc=$?
[ $rc -eq 0 ] && ok "--expand --compress exits 0" || no "--expand --compress failed (rc=$rc)"

# Run the SAME expand WITHOUT --compress to have a baseline for comparison.
"$BIN" "$CORPUS" --expand=computeArea --no-cache >"$TMP/uncompressed.xml" 2>/dev/null

# 1) The function body is still present (the function name appears in the <b> element).
grep -q 'computeArea' "$TMP/compressed.xml" && ok "function still present (computeArea)" || no "function missing from compressed output"

# 2) Block comments ARE present in the uncompressed output.
grep -q 'block comment inside function' "$TMP/uncompressed.xml" && ok "block comment present WITHOUT --compress (baseline OK)" || no "block comment missing from uncompressed baseline (fixture or expand broken)"

# 3) Block comments are GONE after --compress.
grep -q 'block comment inside function' "$TMP/compressed.xml" && no "block comment still present WITH --compress (should be stripped)" || ok "block comment stripped by --compress"

# 4) Line comments are GONE after --compress.
grep -q 'line comment inside function' "$TMP/compressed.xml" && no "line comment still present WITH --compress (should be stripped)" || ok "line comment stripped by --compress"

# 5) The string literal "http://example.com // not a comment inside a string" is PRESERVED.
#    We grep for the URL host part which would be cut by a naive // stripper.
grep -q 'http://example.com' "$TMP/compressed.xml" && ok "string literal URL preserved (http://example.com survived)" || no "string literal URL was corrupted by --compress"

# 6) The string "/* not a comment */" content is PRESERVED.
grep -q 'not a comment' "$TMP/compressed.xml" && ok "string literal block-comment lookalike preserved" || no "string literal '/* not a comment */' was corrupted by --compress"

# 7) The compressed output is smaller than the uncompressed output (compression actually does something).
sz_c="$( wc -c <"$TMP/compressed.xml" | tr -d ' ' )"
sz_u="$( wc -c <"$TMP/uncompressed.xml" | tr -d ' ' )"
[ "$sz_c" -lt "$sz_u" ] && ok "compressed output is smaller ($sz_c B < $sz_u B)" || no "compressed output is not smaller ($sz_c B >= $sz_u B)"

# 8) --compress is deterministic: two runs must be byte-identical.
"$BIN" "$CORPUS" --expand=computeArea --compress --no-cache >"$TMP/c2.xml" 2>/dev/null
diff -q "$TMP/compressed.xml" "$TMP/c2.xml" >/dev/null && ok "--compress deterministic (byte-identical)" || no "--compress nondeterministic"

# 9) Without --compress, comments survive (confirms the flag is the differentiator, not some other stripping).
grep -q 'line comment inside function' "$TMP/uncompressed.xml" && ok "without --compress, comments are present (flag is the differentiator)" || no "without --compress, comments already absent (flag has no effect?)"

# 10) --outline also works with --compress.
"$BIN" "$CORPUS" --outline=computeArea --compress --no-cache >"$TMP/outline_c.xml" 2>/dev/null
rc_ol=$?
[ $rc_ol -eq 0 ] && ok "--outline --compress exits 0" || no "--outline --compress failed (rc=$rc_ol)"
grep -q 'computeArea' "$TMP/outline_c.xml" && ok "--outline --compress: function present" || no "--outline --compress: function missing"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
