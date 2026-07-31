#!/usr/bin/env bash
# grepcontextcheck.sh — gate for ripgrep-style context lines on --grep/--regex
# (--grep-context=N / --grep-before=N / --grep-after=N).
#
# Asserts:
#   - --grep=NEEDLE_MID_ONCE --grep-context=2 shows exactly 2 lines before + 2 lines after the hit,
#     wrapped in <b>/<a> CDATA children inside a non-self-closing <hit>...</hit>
#   - a hit near file-start (line 1) clamps: --grep-before finds 0 before-lines, no crash, no OOB
#   - a hit near file-end clamps symmetrically: --grep-after finds 0 after-lines
#   - --grep-before=N / --grep-after=N (independently) match the halves of --grep-context=N
#   - the UTF-8 fixture (café/naïve/日本語 on the context lines) stays valid XML — no split codepoints
#   - --grep=NEEDLE (no context flag) emits NO <b>/<a> children (the context blocks stay opt-in)
#
# CONTRACT CHANGE (P5, 2026-07-27): a <hit> is no longer self-closing in any mode — it always carries
# <m><![CDATA[the matched line]]></m>, because the context blocks printed the lines AROUND the hit and
# skipped the hit's own line, so the agent never saw the text it searched for. The assertions below that
# used to pin `<hit .../>` now pin `<hit ...>` + no <b>/<a>. The matched line itself is gated in
# test/grepscancheck.sh (content verified against the file on disk).
#   - determinism: --grep-context=2 run twice is byte-identical
#   - --regex=PAT --grep-context=2 also works (context is not literal-only)
#
# Usage:
#   test/grepcontextcheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/grepcontextcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/grepcontextfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/grepcontextfix dir — fixture missing"; exit 2; }

echo "grepcontextcheck: BIN=$BIN  CORPUS=$CORPUS"

# ── (1) --grep-context=2 on the mid-file hit: exactly 2 before + 2 after ───────────────────────────

"$BIN" "$CORPUS" --no-cache --grep=NEEDLE_MID_ONCE --grep-context=2 >"$TMP/mid" 2>/dev/null

grep -q '<hit p="[^"]*ctxfix\.cpp:16" in="widget">' "$TMP/mid" \
    && ok "mid-file hit is non-self-closing <hit ...> (context present)" \
    || { no "mid-file hit missing or still self-closing"; cat "$TMP/mid"; }

# exactly 2 before-lines: the café comment line then "int y = x + 1;", newline-joined inside <b>
# (grep can't span embedded newlines without -P -z, so use perl -0777 slurp mode here)
perl -0777 -ne 'exit( /<b><!\[CDATA\[    \/\/ café line above.*naïve.*日本語.*\n    int y = x \+ 1;.*café line directly before the hit\]\]><\/b>/s ? 0 : 1 )' "$TMP/mid" \
    && ok "before-context is exactly the 2 lines immediately preceding the hit (UTF-8 intact)" \
    || { no "before-context wrong content"; cat "$TMP/mid"; }

# exactly 2 after-lines: "int z = y + 1;" (日本語) then "return z;"
perl -0777 -ne 'exit( /<a><!\[CDATA\[    int z = y \+ 1;.*日本語 line directly after the hit\n    return z;\]\]><\/a>/s ? 0 : 1 )' "$TMP/mid" \
    && ok "after-context is exactly the 2 lines immediately following the hit (UTF-8 intact)" \
    || { no "after-context wrong content"; cat "$TMP/mid"; }

xmllint --noout "$TMP/mid" 2>/dev/null \
    && ok "UTF-8 context output is well-formed XML (no split codepoints)" \
    || no "UTF-8 context output is malformed XML"

# ── (2) clamp at file start: --grep-before near line 1 gives 0 before-lines ────────────────────────

"$BIN" "$CORPUS" --no-cache --grep=NEEDLE_TOP --grep-before=5 >"$TMP/top" 2>/dev/null
e_top=$?
[ "$e_top" -lt 128 ] \
    && ok "hit on line 1 with --grep-before=5 does not crash (exit $e_top)" \
    || no "hit on line 1 with --grep-before=5 crashed or signaled (exit $e_top)"

# line 1 has no lines before it AND --grep-after wasn't requested ⇒ before=after=empty ⇒ the hit carries
# its matched line and nothing else (same degrade-to-no-context shape as the no-flag path) — 0
# before-lines, no <b> emitted, no OOB.
grep -q '<hit p="[^"]*ctxfix\.cpp:1" in="widget"><m>' "$TMP/top" && ! grep -q '<b>' "$TMP/top" \
    && ok "clamp at file start: 0 before-lines, no <b> emitted, no OOB" \
    || { no "clamp at file start failed"; cat "$TMP/top"; }

xmllint --noout "$TMP/top" 2>/dev/null \
    && ok "file-start clamp output is well-formed XML" \
    || no "file-start clamp output is malformed XML"

# ── (3) clamp at file end: geometry.h's last line (from the primary fixture) has 0 after-lines ────

GEOM="$ROOT/test/fixture"
"$BIN" "$GEOM" --no-cache --grep=perimeter --grep-after=5 >"$TMP/end" 2>/dev/null
# geometry.h's hit is on its last line (line 13 of a 13-line file) and only --grep-after was requested
# (no --grep-before) ⇒ before=after=empty ⇒ the hit carries only its <m> matched line — 0 after-lines, no OOB.
# (other hits in this run legitimately DO carry <a> blocks — assert on THIS hit's own children only:
#  it must close right after its <m>, with no <a> of its own.)
perl -0777 -ne 'exit( /<hit p="[^"]*geometry\.h:13" in="perimeter"><m><!\[CDATA\[.*?\]\]><\/m><\/hit>/s ? 0 : 1 )' "$TMP/end" \
    && ok "clamp at file end: 0 after-lines on the last-line hit, no OOB" \
    || { no "clamp at file end failed"; cat "$TMP/end"; }

xmllint --noout "$TMP/end" 2>/dev/null \
    && ok "file-end clamp output is well-formed XML" \
    || no "file-end clamp output is malformed XML"

# ── (3b) trailing-newline-at-EOF regression: --grep-after reaching the file's TRUE last line must not
#         emit a phantom blank line (a file ending in '\n' has one extra empty "line" in a naive byte-
#         offset split that nothing ever matches on — the after-context must stop at the real last line,
#         not print an extra blank line for it). ctxfix.cpp's last line is `}` (line 19), reached by
#         --grep-after=3 from the line-16 hit.
"$BIN" "$CORPUS" --no-cache --grep=NEEDLE_MID_ONCE --grep-after=3 >"$TMP/eof" 2>/dev/null
grep -q '<a><!\[CDATA\[    int z = y + 1;.*$' "$TMP/eof" >/dev/null   # sanity: still finds the after-block
perl -0777 -ne 'exit( /<a><!\[CDATA\[    int z = y \+ 1;.*\n    return z;\n\}\]\]><\/a>/s ? 0 : 1 )' "$TMP/eof" \
    && ok "--grep-after reaching the true last line stops there — no phantom trailing blank line" \
    || { no "--grep-after at EOF emitted a phantom blank line or wrong content"; cat "$TMP/eof"; }

# ── (4) --grep-before / --grep-after independently match the halves of --grep-context ─────────────

"$BIN" "$CORPUS" --no-cache --grep=NEEDLE_MID_ONCE --grep-before=2 >"$TMP/before_only" 2>/dev/null
"$BIN" "$CORPUS" --no-cache --grep=NEEDLE_MID_ONCE --grep-after=2  >"$TMP/after_only"  2>/dev/null

grep -q '<b>' "$TMP/before_only" && ! grep -q '<a>' "$TMP/before_only" \
    && ok "--grep-before=2 alone emits only <b>, no <a>" \
    || no "--grep-before=2 alone emitted the wrong children"

grep -q '<a>' "$TMP/after_only" && ! grep -q '<b>' "$TMP/after_only" \
    && ok "--grep-after=2 alone emits only <a>, no <b>" \
    || no "--grep-after=2 alone emitted the wrong children"

# the <b> block from --grep-before=2 must equal the <b> block from --grep-context=2
b_before_only="$( grep -o '<b>.*</b>' "$TMP/before_only" )"
b_context="$(     grep -o '<b>.*</b>' "$TMP/mid" )"
[ "$b_before_only" = "$b_context" ] \
    && ok "--grep-before=2 before-block matches --grep-context=2's before-block" \
    || no "--grep-before=2 / --grep-context=2 before-blocks differ"

a_after_only="$( grep -o '<a>.*</a>' "$TMP/after_only" )"
a_context="$(    grep -o '<a>.*</a>' "$TMP/mid" )"
[ "$a_after_only" = "$a_context" ] \
    && ok "--grep-after=2 after-block matches --grep-context=2's after-block" \
    || no "--grep-after=2 / --grep-context=2 after-blocks differ"

# ── (5) --grep without a context flag emits the matched line and NOTHING else (context stays opt-in) ──

"$BIN" "$CORPUS" --no-cache --grep=NEEDLE_MID_ONCE >"$TMP/nocontext" 2>/dev/null

grep -q '<hit p="[^"]*ctxfix\.cpp:16" in="widget"><m><!\[CDATA\[    int hitline = NEEDLE_MID_ONCE;\]\]></m></hit>' "$TMP/nocontext" \
    && ok "--grep with no context flag emits exactly <hit ...><m>matched line</m></hit>" \
    || { no "--grep with no context flag changed shape"; cat "$TMP/nocontext"; }

! grep -q '<b>\|<a>' "$TMP/nocontext" \
    && ok "--grep with no context flag emits no <b>/<a> children anywhere" \
    || no "--grep with no context flag unexpectedly emitted context children"

xmllint --noout "$TMP/nocontext" 2>/dev/null \
    && ok "no-context output is well-formed XML" \
    || no "no-context output is malformed XML"

# ── (6) determinism: --grep-context=2 run twice is byte-identical ──────────────────────────────────

"$BIN" "$CORPUS" --no-cache --grep=NEEDLE_MID_ONCE --grep-context=2 >"$TMP/det1" 2>/dev/null
"$BIN" "$CORPUS" --no-cache --grep=NEEDLE_MID_ONCE --grep-context=2 >"$TMP/det2" 2>/dev/null

diff -q "$TMP/det1" "$TMP/det2" >/dev/null \
    && ok "determinism: byte-identical --grep-context=2 output across runs" \
    || no "determinism: non-identical context output between runs"

# ── (7) --regex + --grep-context also works (context isn't literal-only) ───────────────────────────

"$BIN" "$CORPUS" --no-cache --regex='NEEDLE_MID_[A-Z]+' --grep-context=1 >"$TMP/rx" 2>/dev/null

grep -q '<hit p="[^"]*ctxfix\.cpp:16" in="widget">' "$TMP/rx" \
    && ok "--regex + --grep-context=1 finds the hit with context" \
    || { no "--regex + --grep-context=1 failed"; cat "$TMP/rx"; }

xmllint --noout "$TMP/rx" 2>/dev/null \
    && ok "--regex + --grep-context output is well-formed XML" \
    || no "--regex + --grep-context output is malformed XML"

# ── (8) special characters under context still don't crash ─────────────────────────────────────────

"$BIN" "$CORPUS" --no-cache --grep='((' --grep-context=2 >"$TMP/special" 2>/dev/null
e_sp=$?
[ "$e_sp" -lt 128 ] \
    && ok "--grep='((' --grep-context=2 does not crash (exit $e_sp)" \
    || no "--grep='((' --grep-context=2 crashed or signaled (exit $e_sp)"

# ── (9) G4 on the REAL corpus: a context line ENDING in a multi-byte codepoint must survive ───────
# §G5 repro. grepLineRangeText's trailing UTF-8 back-off used to strip the em-dash's continuation bytes
# unconditionally and stop on the LEAD byte, so a context line whose last character is "—" (very common
# in this codebase's comments) was emitted as a lone 0xE2 inside CDATA — `xmllint --noout` then died with
# "Input is not proper UTF-8". The fixture cannot catch this (its multi-byte chars are mid-line); only
# the real tree has comment lines that END on a codepoint, so this arm runs against $ROOT.
"$BIN" "$ROOT" --no-cache --regex='fnv\w+' --grep-context=2 >"$TMP/utf8regex" 2>/dev/null
xmllint --noout "$TMP/utf8regex" 2>/dev/null \
    && ok "--regex='fnv\\w+' --grep-context=2 on the real corpus is well-formed (no split codepoint)" \
    || no "--regex='fnv\\w+' --grep-context=2 on the real corpus is malformed XML — context cut mid-UTF-8"

"$BIN" "$ROOT" --no-cache --grep=MUST --grep-context=2 >"$TMP/utf8lit" 2>/dev/null
xmllint --noout "$TMP/utf8lit" 2>/dev/null \
    && ok "--grep=MUST --grep-context=2 on the real corpus is well-formed (no split codepoint)" \
    || no "--grep=MUST --grep-context=2 on the real corpus is malformed XML — context cut mid-UTF-8"

# the em-dash must be PRESERVED, not scrubbed to '?': the back-off fix keeps the whole codepoint, so a
# gate that only checked xmllint could be satisfied by a lossy scrub. Pin the content too.
grep -q 'The multiply MUST wrap — that is the algorithm —' "$TMP/utf8regex" \
    && ok "a context line ending in an em-dash keeps the full codepoint (not scrubbed to '?')" \
    || no "the em-dash-terminated context line lost its trailing codepoint"

# ── Summary ───────────────────────────────────────────────────────────────────────────────────────

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
