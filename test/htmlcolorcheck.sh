#!/usr/bin/env bash
# htmlcolorcheck.sh — gate for --color-by=MODE on the --html export (lang|community|cx|churn|tested).
#
# Usage:
#   test/htmlcolorcheck.sh                          # uses build/ripwire on test/fixture
#   RIPWIRE_BIN=asan/ripwire test/htmlcolorcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

echo "htmlcolorcheck: BIN=$BIN  CORPUS=$CORPUS"

# 1) baseline payload: --html with no --color-by still carries the color-by machinery, defaulted to lang.
"$BIN" "$CORPUS" --html --no-cache >"$TMP/out.html" 2>/dev/null
count="$( grep -c '"id"' "$TMP/out.html" 2>/dev/null || echo 0 )"
[ "$count" -ge 3 ]                             && ok "NODES array has >= 3 entries (found $count)"        || no "NODES array has < 3 entries (found $count)"
grep -q '"cx":'                "$TMP/out.html" && ok "output contains \"cx\": per-node field"              || no "output missing \"cx\": per-node field"
grep -q '"ts":'                "$TMP/out.html" && ok "output contains \"ts\": per-node field"              || no "output missing \"ts\": per-node field"
grep -q 'const FCHURN'         "$TMP/out.html" && ok "output contains const FCHURN"                        || no "output missing const FCHURN"
grep -q 'const CHURN_OK'       "$TMP/out.html" && ok "output contains const CHURN_OK"                      || no "output missing const CHURN_OK"
grep -q 'id="colorMode"'       "$TMP/out.html" && ok "output contains <select id=\"colorMode\">"           || no "output missing <select id=\"colorMode\">"
grep -q 'value="lang"'         "$TMP/out.html" && ok "colorMode select has value=\"lang\" option"          || no "colorMode select missing value=\"lang\" option"
grep -q 'value="community"'    "$TMP/out.html" && ok "colorMode select has value=\"community\" option"     || no "colorMode select missing value=\"community\" option"
grep -q 'value="cx"'           "$TMP/out.html" && ok "colorMode select has value=\"cx\" option"            || no "colorMode select missing value=\"cx\" option"
grep -q 'value="churn"'        "$TMP/out.html" && ok "colorMode select has value=\"churn\" option"         || no "colorMode select missing value=\"churn\" option"
grep -q 'value="tested"'       "$TMP/out.html" && ok "colorMode select has value=\"tested\" option"        || no "colorMode select missing value=\"tested\" option"
grep -q 'renderLegend'         "$TMP/out.html" && ok "output contains renderLegend function"               || no "output missing renderLegend function"
grep -q 'const COLOR_MODE = "lang"' "$TMP/out.html" && ok "default COLOR_MODE is \"lang\" when --color-by omitted" || no "default COLOR_MODE is not \"lang\" when --color-by omitted"

# 2) explicit mode: --color-by=cx bakes COLOR_MODE = "cx" into the page.
"$BIN" "$CORPUS" --html --color-by=cx --no-cache >"$TMP/cx.html" 2>/dev/null
grep -q 'const COLOR_MODE = "cx"' "$TMP/cx.html" && ok "--color-by=cx: COLOR_MODE = \"cx\" baked in" || no "--color-by=cx: COLOR_MODE = \"cx\" not baked in"

# 3) determinism: two runs of --html --color-by=community produce byte-identical output.
"$BIN" "$CORPUS" --html --color-by=community --no-cache >"$TMP/comm_a.html" 2>/dev/null
"$BIN" "$CORPUS" --html --color-by=community --no-cache >"$TMP/comm_b.html" 2>/dev/null
diff -q "$TMP/comm_a.html" "$TMP/comm_b.html" >/dev/null && ok "determinism: byte-identical run-to-run" || no "determinism: non-identical output"

# 4) refusals

# 4a) --color-by without --html must refuse, naming --html in stderr.
"$BIN" "$CORPUS" --color-by=community --no-cache >"$TMP/4a.out" 2>"$TMP/4a.err"
rc=$?
if [ "$rc" -ne 0 ] && grep -q -- '--html' "$TMP/4a.err"; then
    ok "--color-by without --html refuses (rc=$rc) and names --html"
else
    no "--color-by without --html did not refuse-and-name --html (rc=$rc)"
    sed 's/^/    /' "$TMP/4a.err"
fi

# 4b) --color-by=bogus must refuse, naming the bad value and the allowed set.
"$BIN" "$CORPUS" --color-by=bogus --html --no-cache >"$TMP/4b.out" 2>"$TMP/4b.err"
rc=$?
if [ "$rc" -ne 0 ] && grep -q 'unknown value' "$TMP/4b.err" && grep -q 'lang|community|cx|churn|tested' "$TMP/4b.err"; then
    ok "--color-by=bogus refuses (rc=$rc), names \"unknown value\" and the allowed set"
else
    no "--color-by=bogus did not refuse-and-explain correctly (rc=$rc)"
    sed 's/^/    /' "$TMP/4b.err"
fi

# 4c) --color-by= (empty value) must refuse.
"$BIN" "$CORPUS" --color-by= --html --no-cache >"$TMP/4c.out" 2>"$TMP/4c.err"
rc=$?
[ "$rc" -ne 0 ] && ok "--color-by= (empty value) refuses (rc=$rc)" || no "--color-by= (empty value) did not refuse (rc=$rc)"

# 5) no external script src= or link href= (self-contained, no CDN) on the colored output.
"$BIN" "$CORPUS" --html --color-by=community --no-cache >"$TMP/colored.html" 2>/dev/null
if grep -qE '<script[^>]+src=' "$TMP/colored.html" 2>/dev/null; then
    no "self-contained: external <script src= found"
else
    ok "self-contained: no external <script src=>"
fi
if grep -qE '<link[^>]+href=' "$TMP/colored.html" 2>/dev/null; then
    no "self-contained: external <link href= found"
else
    ok "self-contained: no external <link href=>"
fi

# 6) zero external http(s):// resource references anywhere in the document (CSP-safe, no CDN) —
#    the only http(s) text allowed is inside an xmlns attribute (none expected in HTML, but the check
#    is written generically so a future xmlns doesn't false-positive).
if grep -oE 'https?://[^"'"'"' <>]+' "$TMP/colored.html" 2>/dev/null | grep -vq 'xmlns'; then
    no "self-contained: found http(s):// reference outside xmlns"
else
    ok "self-contained: no http(s):// resource references beyond xmlns"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
