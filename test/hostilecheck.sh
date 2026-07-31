#!/usr/bin/env bash
# hostilecheck.sh — hostile-content XML/UTF-8 robustness gate.
#
# ctxpack streams a minified XML map by default and a self-contained HTML file with
# --html; both are downstream consumers that must never choke on adversarial source
# content. This gate feeds ctxpack a fixture (test/hostilefix/) engineered to contain:
#   - a C++ doc-comment with raw XML metacharacters:  a < b && "quoted" & <tag>
#   - a markdown heading that looks like a script-tag breakout: </script><script>alert(1)
#   - a markdown heading mixing an emoji with CJK text (multi-byte UTF-8 stress)
#   - a Python string literal containing a raw 0x0C form-feed byte
#   - a Python comment containing a lone invalid UTF-8 byte (0xE9, no continuation byte)
#   - a Python identifier with a non-ASCII character: café_size
#
# It then runs the default map, --pack-signatures, --for=, --grep=, --lint, and --html,
# and asserts: every XML output is well-formed (xmllint --noout); every output is valid
# UTF-8 (iconv -f UTF-8 -t UTF-8); the --html output does not splice the hostile heading
# text raw into its embedded <script> block (only \u-escaped, and there is exactly one
# legitimate <script>...</script> pair); and the default map is deterministic.
#
# Usage:
#   test/hostilecheck.sh
#   CTXPACK_BIN=asan/ctxpack test/hostilecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/hostilefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v iconv   >/dev/null 2>&1 || { echo "iconv required"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "hostilecheck: BIN=$BIN  FIX=$FIX"

# ─── the source-of-truth content checks (sanity on the fixture itself) ────────
grep -q 'a < b && "quoted" & <tag>' "$FIX/hostile.cpp" \
    && ok "fixture sanity: hostile.cpp doc-comment has raw XML metacharacters" \
    || no "fixture sanity: hostile.cpp doc-comment missing expected hostile text"

grep -q '</script><script>alert(1)' "$FIX/hostile.md" \
    && ok "fixture sanity: hostile.md has the script-breakout heading" \
    || no "fixture sanity: hostile.md missing the script-breakout heading"

grep -q 'café_size' "$FIX/hostile.py" \
    && ok "fixture sanity: hostile.py has non-ASCII identifier café_size" \
    || no "fixture sanity: hostile.py missing café_size identifier"

# form-feed (0x0C) present in hostile.py
if python3 -c "
data = open('$FIX/hostile.py', 'rb').read()
raise SystemExit(0 if b'\\x0c' in data else 1)
"; then
    ok "fixture sanity: hostile.py contains a raw 0x0C form-feed byte"
else
    no "fixture sanity: hostile.py missing the form-feed byte"
fi

# lone invalid UTF-8 byte (0xE9 not followed by a continuation byte) present in hostile.py
if python3 -c "
data = open('$FIX/hostile.py', 'rb').read()
i = data.find(b'\\xe9')
ok = i != -1 and not (i + 1 < len(data) and 0x80 <= data[i+1] <= 0xBF)
raise SystemExit(0 if ok else 1)
"; then
    ok "fixture sanity: hostile.py contains a lone invalid UTF-8 byte (0xE9)"
else
    no "fixture sanity: hostile.py missing the lone invalid 0xE9 byte"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== default map: XML well-formed + valid UTF-8 ==="
# ═══════════════════════════════════════════════════════════════════════════

MAP_OUT="$TMP/map.xml"
$BIN "$FIX" >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
[ "$MAP_EXIT" -eq 0 ] && ok "default map: exits 0 on hostile fixture" || no "default map: exited $MAP_EXIT"

xmllint --noout "$MAP_OUT" 2>"$TMP/xmllint.err" \
    && ok "default map: passes xmllint --noout" \
    || no "default map: xmllint FAILED: $( cat "$TMP/xmllint.err" )"

iconv -f UTF-8 -t UTF-8 <"$MAP_OUT" >/dev/null 2>"$TMP/iconv.err" \
    && ok "default map: valid UTF-8 output" \
    || no "default map: invalid UTF-8: $( cat "$TMP/iconv.err" )"

# the hostile heading text must appear XML-escaped, never raw, in the map.
if grep -q '&lt;/script&gt;&lt;script&gt;alert(1)' "$MAP_OUT"; then
    ok "default map: script-breakout heading is XML-escaped (&lt;...&gt;)"
else
    no "default map: script-breakout heading not found XML-escaped in output"
fi
if grep -qF '</script><script>alert(1)' "$MAP_OUT"; then
    no "default map: RAW (unescaped) script-breakout text leaked into XML output"
else
    ok "default map: no raw unescaped script-breakout text in XML output"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --pack-signatures: doc-comment metacharacters escaped ==="
# ═══════════════════════════════════════════════════════════════════════════

SIG_OUT="$TMP/sig.xml"
$BIN "$FIX" --pack-signatures >"$SIG_OUT" 2>"$TMP/sig.err"
[ $? -eq 0 ] && ok "--pack-signatures: exits 0" || no "--pack-signatures: nonzero exit"

xmllint --noout "$SIG_OUT" 2>"$TMP/sig_lint.err" \
    && ok "--pack-signatures: passes xmllint --noout" \
    || no "--pack-signatures: xmllint FAILED: $( cat "$TMP/sig_lint.err" )"

iconv -f UTF-8 -t UTF-8 <"$SIG_OUT" >/dev/null 2>"$TMP/sig_iconv.err" \
    && ok "--pack-signatures: valid UTF-8 output" \
    || no "--pack-signatures: invalid UTF-8: $( cat "$TMP/sig_iconv.err" )"

# the doc-comment's raw metacharacters (< & ") must show up escaped, not raw.
if grep -q 'a &lt; b &amp;&amp; &quot;quoted&quot; &amp; &lt;tag&gt;' "$SIG_OUT"; then
    ok "--pack-signatures: doc-comment XML metacharacters correctly escaped"
else
    no "--pack-signatures: doc-comment metacharacters not correctly escaped"
fi

# café_size (non-ASCII identifier) must survive intact.
if grep -qF 'café_size' "$SIG_OUT"; then
    ok "--pack-signatures: non-ASCII identifier café_size preserved"
else
    no "--pack-signatures: café_size identifier missing/corrupted"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --for=\"quoted tag\": task lens, XML well-formed ==="
# ═══════════════════════════════════════════════════════════════════════════

FOR_OUT="$TMP/for.xml"
$BIN "$FIX" --for="quoted tag" >"$FOR_OUT" 2>"$TMP/for.err"
[ $? -eq 0 ] && ok "--for=: exits 0" || no "--for=: nonzero exit"

xmllint --noout "$FOR_OUT" 2>"$TMP/for_lint.err" \
    && ok "--for=: passes xmllint --noout" \
    || no "--for=: xmllint FAILED: $( cat "$TMP/for_lint.err" )"

iconv -f UTF-8 -t UTF-8 <"$FOR_OUT" >/dev/null 2>"$TMP/for_iconv.err" \
    && ok "--for=: valid UTF-8 output" \
    || no "--for=: invalid UTF-8: $( cat "$TMP/for_iconv.err" )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --grep=quoted: literal hit + XML well-formed ==="
# ═══════════════════════════════════════════════════════════════════════════

GREP_OUT="$TMP/grep.xml"
$BIN "$FIX" --grep=quoted >"$GREP_OUT" 2>"$TMP/grep.err"
[ $? -eq 0 ] && ok "--grep=: exits 0" || no "--grep=: nonzero exit"

xmllint --noout "$GREP_OUT" 2>"$TMP/grep_lint.err" \
    && ok "--grep=: passes xmllint --noout" \
    || no "--grep=: xmllint FAILED: $( cat "$TMP/grep_lint.err" )"

iconv -f UTF-8 -t UTF-8 <"$GREP_OUT" >/dev/null 2>"$TMP/grep_iconv.err" \
    && ok "--grep=: valid UTF-8 output" \
    || no "--grep=: invalid UTF-8: $( cat "$TMP/grep_iconv.err" )"

grep -q 'hits="1"' "$GREP_OUT" \
    && ok "--grep=quoted: found exactly 1 hit in hostile.cpp doc-comment" \
    || no "--grep=quoted: expected hits=\"1\", got: $( cat "$GREP_OUT" )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --lint: hostile fixture doesn't crash the AST checks ==="
# ═══════════════════════════════════════════════════════════════════════════

LINT_OUT="$TMP/lint.xml"
$BIN "$FIX" --lint >"$LINT_OUT" 2>"$TMP/lint.err"
[ $? -eq 0 ] && ok "--lint: exits 0" || no "--lint: nonzero exit"

xmllint --noout "$LINT_OUT" 2>"$TMP/lint_lint.err" \
    && ok "--lint: passes xmllint --noout" \
    || no "--lint: xmllint FAILED: $( cat "$TMP/lint_lint.err" )"

iconv -f UTF-8 -t UTF-8 <"$LINT_OUT" >/dev/null 2>"$TMP/lint_iconv.err" \
    && ok "--lint: valid UTF-8 output" \
    || no "--lint: invalid UTF-8: $( cat "$TMP/lint_iconv.err" )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --html=OUT.html: no script-tag breakout in embedded JSON ==="
# ═══════════════════════════════════════════════════════════════════════════

HTML_OUT="$TMP/out.html"
$BIN "$FIX" --html="$HTML_OUT" >"$TMP/html_stdout" 2>"$TMP/html.err"
[ $? -eq 0 ] && ok "--html=: exits 0" || no "--html=: nonzero exit"
[ -s "$HTML_OUT" ] && ok "--html=: output file was written and is non-empty" || no "--html=: output file missing/empty"

iconv -f UTF-8 -t UTF-8 <"$HTML_OUT" >/dev/null 2>"$TMP/html_iconv.err" \
    && ok "--html=: valid UTF-8 output" \
    || no "--html=: invalid UTF-8: $( cat "$TMP/html_iconv.err" )"

# There must be EXACTLY one literal opening <script and one literal closing </script> tag —
# the legitimate script element wrapping the graph's JS/JSON payload. If the hostile heading
# text ("</script><script>alert(1)") were spliced in raw, this count would be 2 (or more).
SCRIPT_OPEN_COUNT="$( grep -o '<script' "$HTML_OUT" | wc -l | tr -d ' ' )"
SCRIPT_CLOSE_COUNT="$( grep -o '</script>' "$HTML_OUT" | wc -l | tr -d ' ' )"
if [ "$SCRIPT_OPEN_COUNT" = "1" ] && [ "$SCRIPT_CLOSE_COUNT" = "1" ]; then
    ok "--html=: exactly one legitimate <script>...</script> pair (no raw breakout)"
else
    no "--html=: expected exactly 1 open + 1 close <script> tag, got open=$SCRIPT_OPEN_COUNT close=$SCRIPT_CLOSE_COUNT"
fi

# The raw (unescaped) breakout string must never appear anywhere in the file.
if grep -qF '</script><script>alert(1)' "$HTML_OUT"; then
    no "--html=: RAW unescaped '</script><script>alert(1)' text leaked into HTML output"
else
    ok "--html=: no raw unescaped script-breakout text anywhere in HTML output"
fi

# The hostile heading text MUST still be present, but only as a \u-escaped JSON string
# (i.e. the content was captured, just safely encoded) — extract the embedded <script>
# block and check the escaped form is what's there.
python3 - "$HTML_OUT" <<'PYEOF' >"$TMP/html_script_check"
import re, sys
html = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'<script[^>]*>(.*?)</script>', html, re.S)
if not m:
    print("NO_SCRIPT_BLOCK")
    sys.exit(0)
block = m.group(1)
has_escaped = '\\u003c/script\\u003e\\u003cscript\\u003ealert(1)' in block
has_raw = '</script><script>alert(1)' in block
if has_escaped and not has_raw:
    print("OK")
elif has_raw:
    print("RAW_LEAK")
else:
    print("MISSING_ESCAPED")
PYEOF
HTML_CHECK="$( cat "$TMP/html_script_check" )"
[ "$HTML_CHECK" = "OK" ] \
    && ok "--html=: hostile heading text present inside <script> only as \\u-escaped JSON" \
    || no "--html=: script-block content check failed: $HTML_CHECK"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== determinism: default map twice, byte-identical ==="
# ═══════════════════════════════════════════════════════════════════════════

$BIN "$FIX" >"$TMP/det_a.xml" 2>/dev/null
$BIN "$FIX" >"$TMP/det_b.xml" 2>/dev/null
diff -q "$TMP/det_a.xml" "$TMP/det_b.xml" >/dev/null \
    && ok "determinism: default map byte-identical across two runs" \
    || no "determinism: default map differs across runs"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== A3-F15: a '-'-leading positional arg is never treated as a clonable git URL ==="
# ═══════════════════════════════════════════════════════════════════════════
# isGitUrl() must reject any string starting with '-' outright (option-injection guard), so a hostile
# positional arg like "--upload-pack=touch /tmp/pwned" never reaches resolveRemoteRoot()'s popen("git
# clone ...") — it falls through to the ordinary "root path does not exist" handling instead. This check
# does NOT clone anything (no network access, no git invoked): a real clone would only be attempted for a
# TRUE git URL (https://, http://, git@, ssh://), which none of these hostile strings are.

DASH1="--upload-pack=touch /tmp/ctxpack-hostilecheck-pwned"
DASH2="-x"
DASH3="--"

for hostile in "$DASH1" "$DASH2" "$DASH3"; do
    out="$( "$BIN" "$hostile" 2>&1 1>/dev/null )"
    rc=$?
    if printf '%s' "$out" | grep -qi 'cloning\|git clone'; then
        no "hostile positional '$hostile': WAS routed into the clone path (git-clone/cloning mentioned): $out"
    else
        ok "hostile positional '$hostile': not routed into the clone path (exit $rc)"
    fi
done

[ ! -e /tmp/ctxpack-hostilecheck-pwned ] \
    && ok "hostile positional: no side-effect file created (no shell/command injection occurred)" \
    || { no "hostile positional: side-effect file WAS created — command injection!"; rm -f /tmp/ctxpack-hostilecheck-pwned; }

# static check: the clone command string in source hardens with '--' before the URL and a protocol
# allow-list, so even a same-process regression is caught without needing a live network clone.
if grep -q 'protocol.ext.allow=never' "$ROOT/src/main.cpp" && grep -q 'protocol.file.allow=user' "$ROOT/src/main.cpp" \
   && grep -qE 'clone --depth=1 -q --' "$ROOT/src/main.cpp"; then
    ok "source: git clone invocation carries protocol.ext/file allow-list + '--' before the URL"
else
    no "source: git clone invocation missing the A3-F15 hardening (protocol allow-list / '--')"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
