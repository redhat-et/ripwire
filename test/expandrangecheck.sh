#!/usr/bin/env bash
# expandrangecheck.sh — gate for --expand=SYM:START-END (octocode partial-fetch, RESEARCH_agentQuality2026
# §2f): slice a symbol's body to 1-based lines START..END, relative to the symbol's own first line, instead
# of emitting the whole def. --expand=SYM (no range) MUST stay byte-identical to the pre-existing whole-body
# path.
#
# Usage:
#   test/expandrangecheck.sh                          # uses build/ripwire on test/expandrangefix
#   RIPWIRE_BIN=asan/ripwire test/expandrangecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# DO NOT edit regression.sh — this is a standalone gate invoked from there.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/expandrangefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/expandrangefix directory"; exit 2; }

echo "expandrangecheck: BIN=$BIN  CORPUS=$CORPUS"

# bigFunction (test/expandrangefix/rangedemo.cpp) is 11 lines, 1-based relative to its own signature line:
#   1  int bigFunction( int a, int b )
#   2  {
#   3      int line2 = a + b;
#   4      int line3 = a - b;
#   5      int line4 = a * b;
#   6      int line5 = helperOne( a );
#   7      // café — UTF-8 comment on line6 (é is a 2-byte codepoint straddling nothing here,
#   8      int line7 = b - a;
#   9      int line8 = line2 + line3 + line4 + line5 + line7;
#   10     return line8;
#   11 }

# 1) --expand=bigFunction (NO range) — the pre-existing whole-body path. Must NOT carry a lines= marker
#    and must contain the entire def, signature through closing brace.
"$BIN" "$CORPUS" --expand=bigFunction --no-cache >"$TMP/whole.xml" 2>/dev/null
rc=$?
[ $rc -eq 0 ] && ok "--expand=bigFunction (no range) exits 0" || no "--expand=bigFunction failed (rc=$rc)"
grep -q 'lines="' "$TMP/whole.xml" && no "whole-body output carries a lines= marker (should be absent)" || ok "whole-body output has NO lines= marker"
grep -q 'int bigFunction( int a, int b )' "$TMP/whole.xml" && ok "whole body includes the signature line" || no "whole body missing the signature line"
grep -q 'return line8;' "$TMP/whole.xml" && ok "whole body includes the last statement" || no "whole body missing the last statement"

# 2) determinism of the whole-body (no-range) path — two runs byte-identical.
"$BIN" "$CORPUS" --expand=bigFunction --no-cache >"$TMP/whole2.xml" 2>/dev/null
diff -q "$TMP/whole.xml" "$TMP/whole2.xml" >/dev/null && ok "whole-body path deterministic (byte-identical)" || no "whole-body path non-deterministic"

# 3) --expand=bigFunction:3-5 — exact slice: lines2/3/4 declarations only, nothing else.
"$BIN" "$CORPUS" --expand=bigFunction:3-5 --no-cache >"$TMP/slice.xml" 2>/dev/null
rc=$?
[ $rc -eq 0 ] && ok "--expand=bigFunction:3-5 exits 0" || no "--expand=bigFunction:3-5 failed (rc=$rc)"
grep -q 'lines="3-5/11"' "$TMP/slice.xml" && ok "slice marker lines=\"3-5/11\" present" || no "slice marker missing/wrong (want lines=\"3-5/11\")"
grep -q 'int line2 = a + b;' "$TMP/slice.xml" && ok "slice contains line2 (in range)" || no "slice missing line2"
grep -q 'int line3 = a - b;' "$TMP/slice.xml" && ok "slice contains line3 (in range)" || no "slice missing line3"
grep -q 'int line4 = a \* b;' "$TMP/slice.xml" && ok "slice contains line4 (in range)" || no "slice missing line4"
grep -q 'int bigFunction( int a, int b )' "$TMP/slice.xml" && no "slice leaked the signature line (out of range)" || ok "slice correctly excludes the signature line"
grep -q 'return line8;' "$TMP/slice.xml" && no "slice leaked the return statement (out of range)" || ok "slice correctly excludes the return statement"
grep -q 'int line5' "$TMP/slice.xml" && no "slice leaked line5 (out of range)" || ok "slice correctly excludes line5"

# 4) determinism of a ranged slice — fixed range on a fixed symbol → byte-identical run to run.
"$BIN" "$CORPUS" --expand=bigFunction:3-5 --no-cache >"$TMP/slice2.xml" 2>/dev/null
diff -q "$TMP/slice.xml" "$TMP/slice2.xml" >/dev/null && ok "ranged slice deterministic (byte-identical)" || no "ranged slice non-deterministic"

# 5) out-of-range clamps (never OOB): 9-999 clamps to 9-11 (the def's actual last line), not a crash.
"$BIN" "$CORPUS" --expand=bigFunction:9-999 --no-cache >"$TMP/clamp.xml" 2>/dev/null
rc=$?
[ $rc -eq 0 ] && ok "out-of-range END exits 0 (no crash)" || no "out-of-range END crashed/failed (rc=$rc)"
grep -q 'lines="9-11/11"' "$TMP/clamp.xml" && ok "out-of-range END clamps to lines=\"9-11/11\"" || no "out-of-range END did not clamp correctly"
grep -q '}' "$TMP/clamp.xml" && ok "clamped slice includes the closing brace (last real line)" || no "clamped slice missing the closing brace"

# 5b) START clamps too: START far beyond the def's span still yields a valid (last-line) slice.
"$BIN" "$CORPUS" --expand=bigFunction:500-999 --no-cache >"$TMP/clamp2.xml" 2>/dev/null
rc=$?
[ $rc -eq 0 ] && ok "out-of-range START exits 0 (no crash)" || no "out-of-range START crashed/failed (rc=$rc)"
grep -q 'lines="11-11/11"' "$TMP/clamp2.xml" && ok "out-of-range START clamps to the last line (lines=\"11-11/11\")" || no "out-of-range START did not clamp correctly"

# 6) reversed range (START>END) degrades cleanly to the swapped, correct slice — never a crash, never
#    an inverted/empty emission.
"$BIN" "$CORPUS" --expand=bigFunction:5-3 --no-cache >"$TMP/rev.xml" 2>/dev/null
rc=$?
[ $rc -eq 0 ] && ok "reversed range (5-3) exits 0 (no crash)" || no "reversed range crashed/failed (rc=$rc)"
grep -q 'lines="3-5/11"' "$TMP/rev.xml" && ok "reversed range (5-3) swaps to lines=\"3-5/11\"" || no "reversed range did not swap correctly"
diff -q "$TMP/rev.xml" "$TMP/slice.xml" >/dev/null && ok "reversed range (5-3) == forward range (3-5) output" || no "reversed range output differs from the equivalent forward range"

# 7) malformed range degrades to the WHOLE body, with a clear stderr note — never a crash.
#    REPINNED (§P8 seam 1, 2026-07-28): the disambiguator is now "the tail after the LAST ':' is a range
#    attempt IFF it starts with a DIGIT" — no identifier in any grammar we parse does, so `NAME:abc` is a
#    FILE:NAME SELECTOR now (see test/selectorchaincheck.sh), not a botched range. That reading is the whole
#    point of the seam: a pasted `p=` locator is exactly `path:name`-shaped. The degrade path itself is
#    UNCHANGED and still gated here — it just needs a digit-leading malformed tail to reach it.
"$BIN" "$CORPUS" --expand=bigFunction:5x-7 --no-cache >"$TMP/mal.xml" 2>"$TMP/mal.err"
rc=$?
[ $rc -eq 0 ] && ok "malformed range (5x-7) exits 0 (degrades, no crash)" || no "malformed range (5x-7) crashed/failed (rc=$rc)"
grep -q 'lines="' "$TMP/mal.xml" && no "malformed range still emitted a lines= marker (should degrade to whole-body)" || ok "malformed range correctly degrades to whole-body (no lines= marker)"
grep -q 'int bigFunction( int a, int b )' "$TMP/mal.xml" && ok "malformed range: whole body present (signature line included)" || no "malformed range: whole body missing after degrade"
grep -qi 'malformed range' "$TMP/mal.err" && ok "malformed range prints a clear stderr note" || no "malformed range: no stderr note"

# 7a) …and the OTHER reading of the same token shape now works: a non-digit tail is a file:name selector.
"$BIN" "$CORPUS" --top-k=0 --expand=rangedemo.cpp:bigFunction --no-cache >"$TMP/sel.xml" 2>"$TMP/sel.err"
rc=$?
{ [ $rc -eq 0 ] && grep -q 'n="bigFunction"' "$TMP/sel.xml" && ! grep -qi 'malformed range' "$TMP/sel.err"; } \
  && ok "file:name selector (big.cpp:bigFunction) resolves, no bogus malformed-range note" \
  || no "file:name selector regressed (rc=$rc, err=$( cat "$TMP/sel.err" ))"

# 7b) malformed range (START=0, 1-based so 0 is invalid) also degrades cleanly.
"$BIN" "$CORPUS" --expand=bigFunction:0-5 --no-cache >"$TMP/mal0.xml" 2>"$TMP/mal0.err"
rc=$?
[ $rc -eq 0 ] && ok "malformed range (0-5) exits 0 (degrades, no crash)" || no "malformed range (0-5) crashed/failed (rc=$rc)"
grep -q 'lines="' "$TMP/mal0.xml" && no "malformed range (0-5) still emitted a lines= marker" || ok "malformed range (0-5) degrades to whole-body"

# 7c) malformed range (missing dash) also degrades cleanly.
"$BIN" "$CORPUS" --expand=bigFunction:5 --no-cache >"$TMP/mal5.xml" 2>"$TMP/mal5.err"
rc=$?
[ $rc -eq 0 ] && ok "malformed range (5, no dash) exits 0 (degrades, no crash)" || no "malformed range (5, no dash) crashed/failed (rc=$rc)"
grep -q 'lines="' "$TMP/mal5.xml" && no "malformed range (5, no dash) still emitted a lines= marker" || ok "malformed range (5, no dash) degrades to whole-body"

# 8) UTF-8 safety: a 1-line slice landing exactly on the café (UTF-8) comment line must stay valid UTF-8
#    (no split codepoint) and must pass xmllint.
"$BIN" "$CORPUS" --expand=bigFunction:7-7 --no-cache >"$TMP/utf8.xml" 2>/dev/null
rc=$?
[ $rc -eq 0 ] && ok "UTF-8 line slice (7-7) exits 0" || no "UTF-8 line slice (7-7) failed (rc=$rc)"
grep -q 'lines="7-7/11"' "$TMP/utf8.xml" && ok "UTF-8 line slice marker lines=\"7-7/11\" present" || no "UTF-8 line slice marker missing/wrong"
grep -q 'café' "$TMP/utf8.xml" && ok "UTF-8 codepoint (café) survived the slice intact" || no "UTF-8 codepoint corrupted or missing from the slice"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/utf8.xml" 2>"$TMP/utf8.lint" && ok "UTF-8 slice output is well-formed XML (xmllint)" || { no "UTF-8 slice output failed xmllint"; cat "$TMP/utf8.lint"; }
    python3 -c "import sys; open('$TMP/utf8.xml','rb').read().decode('utf-8')" 2>"$TMP/utf8.dec" && ok "UTF-8 slice output decodes as valid UTF-8" || { no "UTF-8 slice output is NOT valid UTF-8"; cat "$TMP/utf8.dec"; }
else
    printf '  SKIP  xmllint not installed\n'
fi

# 9) mutation test: corrupt the clamp so the slice bound is off-by-one — the marker MUST change,
#    proving the check above is actually sensitive to the emitted range (not a vacuous grep).
if grep -q 'lines="3-5/11"' "$TMP/slice.xml" && ! grep -q 'lines="3-6/11"' "$TMP/slice.xml"; then
    ok "mutation-sensitive: lines=\"3-5/11\" present AND the off-by-one lines=\"3-6/11\" is absent"
else
    no "mutation-sensitivity check failed (range marker not precise)"
fi

# 10) full whole-body/slice composition sanity: --expand with a MIX of a bare name and a ranged name in
#     one invocation — the bare one stays whole, the ranged one slices. (Uses helperOne + bigFunction:3-5.)
"$BIN" "$CORPUS" --expand=helperOne,bigFunction:3-5 --no-cache >"$TMP/mix.xml" 2>/dev/null
rc=$?
[ $rc -eq 0 ] && ok "mixed --expand=helperOne,bigFunction:3-5 exits 0" || no "mixed --expand failed (rc=$rc)"
grep -q 'n="helperOne"' "$TMP/mix.xml" && ! grep -A2 'n="helperOne"' "$TMP/mix.xml" | grep -q 'lines="' \
    && ok "mixed request: helperOne (no range) stays whole-body" || no "mixed request: helperOne unexpectedly carries a lines= marker"
grep -q 'lines="3-5/11"' "$TMP/mix.xml" && ok "mixed request: bigFunction still slices to 3-5/11" || no "mixed request: bigFunction slice missing/wrong"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
