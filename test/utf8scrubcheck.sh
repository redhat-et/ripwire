#!/usr/bin/env bash
# utf8scrubcheck.sh — A4-F20 gate: invalid UTF-8 in source bytes must be scrubbed at every emission seam so
# the XML map (G4 xmllint) and the cc.json export ("always valid JSON") never break on a stray Latin-1 byte.
#
# Before the fix, xmlSafeByte scrubbed only C0 controls; a lone 0xE9 (Latin-1 'é') in a doc-comment or a
# CDATA body flowed verbatim to stdout and made xmllint reject the WHOLE document. ccjson.h's ccJsonEscape
# likewise passed bytes >=0x20 raw, contradicting its "always valid JSON" docstring.
#
# Three layers of coverage:
#   (A) CLI/fixture — test/utf8scrubfix/latin1.cpp carries a raw 0xE9 in a doc-comment (→ escapeXml text
#       path) AND inside a string literal in the body (→ packSource/packBodies CDATA copy loops). We run
#       --pack-signatures, --pack-top-n and --expand and assert every output is xmllint-clean, valid UTF-8,
#       and carries NO raw 0xE9 byte (scrubbed to '?').
#   (B) unit — a tiny TU includes ccjson.h + serialize.h + jsonesc.h and drives ccJsonEscape / escapeXml /
#       utf8SeqLen / jsonesc::escapeHtml directly with invalid + valid byte sequences (the ccJsonEscape
#       path is not CLI-reachable on macOS, whose filesystem forbids invalid-UTF-8 filenames, so it is
#       exercised at the function level).
#   (C) CLI/fixture, --html — AUDIT4 follow-up: htmlexport.h's jsonEscape (jsonesc::escapeHtml) used to
#       pass invalid UTF-8 through raw (the same gap class A4-F20 named for ccjson); now validated. Same
#       latin1.cpp fixture through `--html`, asserting valid UTF-8 output, no raw 0xE9 byte, and an
#       xmllint --html-parseable page.
#
# Usage:  test/utf8scrubcheck.sh   [ CTXPACK_BIN=path/to/ctxpack ]
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/utf8scrubfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v iconv   >/dev/null 2>&1 || { echo "iconv required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }
echo "utf8scrubcheck: BIN=$BIN  FIX=$FIX"

# ── fixture sanity: the raw invalid bytes are actually there ─────────────────────────────────────────
if python3 -c "import sys; d=open('$FIX/latin1.cpp','rb').read(); sys.exit(0 if d.count(b'\xe9')>=2 else 1)"; then
    ok "fixture sanity: latin1.cpp carries raw invalid 0xE9 bytes (doc-comment + body)"
else
    no "fixture sanity: latin1.cpp missing the raw 0xE9 bytes"
fi

# ── (A) CLI seams: each emission verb must be xmllint-clean + valid UTF-8 + no raw 0xE9 ──────────────
for verb in "--pack-signatures" "--pack-top-n=1" "--expand=set_cafe_size"; do
    OUT="$TMP/out.xml"
    "$BIN" "$FIX" $verb --no-cache >"$OUT" 2>/dev/null

    xmllint --noout "$OUT" 2>"$TMP/lint.err" \
        && ok "$verb: passes xmllint --noout (invalid UTF-8 scrubbed)" \
        || no "$verb: xmllint FAILED: $( cat "$TMP/lint.err" )"

    iconv -f UTF-8 -t UTF-8 <"$OUT" >/dev/null 2>"$TMP/iconv.err" \
        && ok "$verb: output is valid UTF-8" \
        || no "$verb: invalid UTF-8 in output: $( cat "$TMP/iconv.err" )"

    if python3 -c "import sys; sys.exit(0 if b'\xe9' in open('$OUT','rb').read() else 1)"; then
        no "$verb: raw 0xE9 byte leaked into the output (not scrubbed)"
    else
        ok "$verb: no raw 0xE9 byte in output (scrubbed to '?')"
    fi
done

# the default map must remain well-formed too (the fixture has no doc-comment/CDATA there, but check anyway)
"$BIN" "$FIX" --no-cache >"$TMP/map.xml" 2>/dev/null
xmllint --noout "$TMP/map.xml" 2>/dev/null && ok "default map on the Latin-1 fixture: xmllint-clean" || no "default map: xmllint FAILED"

# ── (C) --html on the Latin-1 fixture: valid UTF-8 output + no raw 0xE9 + parseable HTML page ────────
HTMLOUT="$TMP/out.html"
"$BIN" "$FIX" --html --no-cache >"$HTMLOUT" 2>/dev/null

[ -s "$HTMLOUT" ] && ok "--html: produced non-empty output on the Latin-1 fixture" \
                   || no "--html: empty/missing output on the Latin-1 fixture"

iconv -f UTF-8 -t UTF-8 <"$HTMLOUT" >/dev/null 2>"$TMP/iconv_html.err" \
    && ok "--html: output is valid UTF-8" \
    || no "--html: invalid UTF-8 in output: $( cat "$TMP/iconv_html.err" )"

if python3 -c "import sys; sys.exit(0 if b'\xe9' in open('$HTMLOUT','rb').read() else 1)"; then
    no "--html: raw 0xE9 byte leaked into the output (not scrubbed)"
else
    ok "--html: no raw 0xE9 byte in output (scrubbed)"
fi

xmllint --html --noout "$HTMLOUT" 2>"$TMP/htmllint.err" \
    && ok "--html: xmllint --html --noout parses the page cleanly" \
    || { grep -qi 'error' "$TMP/htmllint.err" \
           && no "--html: xmllint --html FAILED: $( cat "$TMP/htmllint.err" )" \
           || ok "--html: xmllint --html --noout parses the page (warnings only)"; }

# ── (B) unit: ccJsonEscape / escapeXml / utf8SeqLen / jsonesc::escapeHtml on invalid + valid bytes ────
CXX="${CXX:-c++}"
command -v "$CXX" >/dev/null 2>&1 || CXX=g++
if command -v "$CXX" >/dev/null 2>&1; then
    UTU="$TMP/ccu.cpp"
    cat > "$UTU" <<'EOF'
#include "ccjson.h"
#include "serialize.h"
#include "jsonesc.h"
#include <cassert>
#include <cstdio>
#include <string>
#include <string_view>
using namespace ctx;
int main()
{
    // ccJsonEscape: a lone 0xE9 (invalid UTF-8) becomes the replacement char �; valid stays valid JSON.
    std::string j; ccJsonEscape( std::string_view( "caf\xe9x", 5 ), j );
    assert( j == "caf\\ufffdx" );
    // a VALID multi-byte sequence (é = C3 A9) passes through raw (byte-identical to pre-fix behaviour).
    std::string j2; ccJsonEscape( std::string_view( "caf\xc3\xa9", 5 ), j2 );
    assert( j2 == "caf\xc3\xa9" );
    // escapeXml: invalid -> '?', XML metachars still escaped, valid multi-byte preserved.
    std::vector<char> o; auto v = escapeXml( std::string_view( "a\xe9<b\xc3\xa9", 6 ), o );
    assert( std::string( v ) == "a?&lt;b\xc3\xa9" );
    // utf8SeqLen classifier: lone continuation-less lead = 0; valid 2-byte = 2; surrogate = 0; 4-byte OK.
    assert( utf8SeqLen( "\xe9", 0, 1 ) == 0 );
    assert( utf8SeqLen( "\xc3\xa9", 0, 2 ) == 2 );
    assert( utf8SeqLen( "\xed\xa0\x80", 0, 3 ) == 0 );
    assert( utf8SeqLen( "\xf0\x9f\x98\x80", 0, 4 ) == 4 );
    // jsonesc::escapeHtml (AUDIT4 follow-up): NOW validates UTF-8 — a lone 0xE9 scrubs to raw U+FFFD
    // bytes (escapeMcp's replacement posture, not ccjson's textual � — see jsonesc.h rationale).
    // Valid multi-byte + the <>& hardening this escaper has always had are both preserved.
    std::string h = jsonesc::escapeHtml( std::string_view( "caf\xe9<x>&" ) );
    assert( h == "caf\xEF\xBF\xBD\\u003cx\\u003e\\u0026" );
    std::string h2 = jsonesc::escapeHtml( std::string_view( "caf\xc3\xa9" ) );
    assert( h2 == "caf\xc3\xa9" );
    std::puts( "UNIT_OK" );
    return 0;
}
EOF
    if "$CXX" -std=c++23 -I "$ROOT/src" -I "$ROOT/src/infra" -I "$ROOT/third_party" "$UTU" -o "$TMP/ccu" 2>"$TMP/ccu.err"; then
        if "$TMP/ccu" >"$TMP/ccu.out" 2>&1 && grep -q UNIT_OK "$TMP/ccu.out"; then
            ok "unit: ccJsonEscape/escapeXml/utf8SeqLen/jsonesc::escapeHtml scrub invalid UTF-8, preserve valid"
        else
            no "unit: assertion failed: $( cat "$TMP/ccu.out" )"
        fi
    else
        no "unit: compile failed: $( tail -5 "$TMP/ccu.err" )"
    fi
else
    echo "  SKIP  unit: no C++ compiler found (\$CXX)"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
