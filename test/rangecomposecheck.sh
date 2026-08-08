#!/usr/bin/env bash
# rangecomposecheck.sh — does --expand=SYM:START-END COMPOSE correctly with --compress and with a
# non-C++ language, and does --outline behave sanely when handed a range-suffix it does not support?
# expandrangecheck.sh proves the range mechanics in isolation on ONE C++ fixture; this gate proves the
# CROSS-CUTTING interactions Wave-1's own gate explicitly does not touch:
#   1. --expand=SYM:START-END + --compress together (does the slice survive comment-stripping, and does
#      compress operate on the SLICE, not silently fall back to the whole body?)
#   2. a ranged slice on a JavaScript AND a Bash symbol (not just the C++ rangedemo.cpp fixture)
#   3. a ranged slice whose window includes / excludes a call site — the <calls> sidecar must reflect the
#      symbol's real callees regardless of the slice window (never filtered by the range)
#   4. --outline=SYM:START-END — outline does not document range support; this pins the ACTUAL behavior
#      (degrade, not crash) so a future accidental behavior change is caught either way
#
# Uses test/jsmetricsfix (shapes.js / shapes.sh, hand-authored for jsmetricscheck.sh — reused here since
# it already has hand-verified line numbers) and test/expandrangefix (the Wave-1 C++ fixture) read-only.
#
# Usage:
#   test/rangecomposecheck.sh
#   RIPWIRE_BIN=asan/ripwire test/rangecomposecheck.sh
#
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
JSFIX="$ROOT/test/jsmetricsfix"
CPPFIX="$ROOT/test/expandrangefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$JSFIX" ]  || { echo "no test/jsmetricsfix directory (expected from jsmetricscheck.sh)"; exit 2; }
[ -d "$CPPFIX" ] || { echo "no test/expandrangefix directory"; exit 2; }

echo "rangecomposecheck: BIN=$BIN  JSFIX=$JSFIX  CPPFIX=$CPPFIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 1. --expand=SYM:START-END + --compress compose (slice survives comment-strip) ==="
# ═══════════════════════════════════════════════════════════════════════════
# rangedemo.cpp bigFunction body line 7 is a `// café` comment; slicing 6-8 (line5/comment/line7) then
# compressing must (a) still carry the lines="6-8/11" marker (range not lost), (b) strip the comment line,
# (c) be SHORTER than the uncompressed slice, (d) NOT silently widen back to the whole body.
"$BIN" "$CPPFIX" --expand=bigFunction:6-8 --no-cache            >"$TMP/slice_plain.xml" 2>/dev/null
"$BIN" "$CPPFIX" --expand=bigFunction:6-8 --compress --no-cache >"$TMP/slice_compress.xml" 2>/dev/null
rc1=$?; [ $rc1 -eq 0 ] && ok "--expand:range + --compress exits 0" || no "--expand:range + --compress failed (rc=$rc1)"

grep -q 'lines="6-8/11"' "$TMP/slice_compress.xml" && ok "compressed slice KEEPS the lines=\"6-8/11\" range marker" || no "compressed slice lost/changed the range marker"
grep -q 'café' "$TMP/slice_plain.xml" && ok "uncompressed slice contains the comment (café)" || no "uncompressed slice missing the expected comment line"
grep -q 'café' "$TMP/slice_compress.xml" && no "compressed slice STILL contains the stripped comment (compress did not apply to the slice)" || ok "compressed slice correctly strips the comment"
grep -q 'int line5' "$TMP/slice_compress.xml" && ok "compressed slice still contains real code (line5)" || no "compressed slice lost real code, not just the comment"
grep -q 'int line7' "$TMP/slice_compress.xml" && ok "compressed slice still contains real code (line7)" || no "compressed slice lost line7"

# whole file sizes stand in for the <b>...</b> body-block size: everything else in the map (the <r> symbol
# table, comments) is byte-identical across these three invocations (same corpus, same flags otherwise), so
# the file-size delta is attributable entirely to the body slice/compression. (grep -o cannot span the
# embedded newline inside a multi-line CDATA slice, so we measure the whole file instead of tag-extracting.)
SZ_PLAIN="$( wc -c <"$TMP/slice_plain.xml" | tr -d ' ' )"
SZ_COMPRESS="$( wc -c <"$TMP/slice_compress.xml" | tr -d ' ' )"
[ "$SZ_COMPRESS" -lt "$SZ_PLAIN" ] && ok "compressed slice is smaller than the plain slice ($SZ_COMPRESS < $SZ_PLAIN bytes)" \
                                    || no "compressed slice not smaller (compress=$SZ_COMPRESS plain=$SZ_PLAIN) — compress may not be applying to ranged bodies"

# never silently widens: the whole-body BUNDLE is strictly larger than either sliced variant.
# M6 note (2026-08-08): a bare --expand now auto-serves the cheapest complete answer and on this tiny
# fixture that is the whole FILE (724 B < the ~1.2 KB bundle) — smaller than a sliced BUNDLE that still
# carries the ranked map, so comparing across serving modes stopped measuring widening and started
# measuring the mode choice. The control pins --top-k=200 (the default k, made explicit) so it is the
# EXACT bundle shape the ranged run serves (ranges keep the legacy bundle — expandmodecheck (3b)); the
# widen-detection power is unchanged: a slice that silently widened to the whole body would be >= this.
"$BIN" "$CPPFIX" --expand=bigFunction --top-k=200 --no-cache >"$TMP/whole.xml" 2>/dev/null
SZ_WHOLE="$( wc -c <"$TMP/whole.xml" | tr -d ' ' )"
[ "$SZ_COMPRESS" -lt "$SZ_WHOLE" ] && ok "compressed slice ($SZ_COMPRESS B) is smaller than the whole body ($SZ_WHOLE B) — range did not silently widen" \
                                    || no "compressed slice is NOT smaller than the whole body — range may have silently widened to whole-body"

# determinism of the composed (range + compress) output
"$BIN" "$CPPFIX" --expand=bigFunction:6-8 --compress --no-cache >"$TMP/slice_compress2.xml" 2>/dev/null
diff -q "$TMP/slice_compress.xml" "$TMP/slice_compress2.xml" >/dev/null \
    && ok "range+compress composition deterministic (byte-identical)" || no "range+compress composition non-deterministic"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 2. ranged --expand on JavaScript AND Bash symbols ==="
# ═══════════════════════════════════════════════════════════════════════════
# deepNest (JS) body: 1=signature 2={ 3=if(a>0) 4={ 5=for(...) ... 14=}. Slice 3-5 = if/brace/for lines only.
"$BIN" "$JSFIX" --expand=deepNest:3-5 --no-cache >"$TMP/js_slice.xml" 2>/dev/null
rc=$?; [ $rc -eq 0 ] && ok "JS ranged --expand=deepNest:3-5 exits 0" || no "JS ranged expand failed (rc=$rc)"
grep -q 'lines="3-5/14"' "$TMP/js_slice.xml" && ok "JS slice marker lines=\"3-5/14\" present" || no "JS slice marker missing/wrong"
grep -q 'if ( a > 0 )' "$TMP/js_slice.xml" && ok "JS slice contains the expected if-line" || no "JS slice missing the if-line"
grep -q 'for ( let i = 0' "$TMP/js_slice.xml" && ok "JS slice contains the expected for-line" || no "JS slice missing the for-line"
grep -q 'function deepNest' "$TMP/js_slice.xml" && no "JS slice leaked the signature line (out of range)" || ok "JS slice correctly excludes the signature line"

# deep_nest_sh (Bash) body: 1={ 2=if 3=for 4=if 5=echo 6=fi 7=done 8=fi 9=} — wait, actual body starts at
# the opening brace on its own line per bash function_definition capture (verified earlier); slice 2-4.
"$BIN" "$JSFIX" --expand=deep_nest_sh:2-4 --no-cache >"$TMP/sh_slice.xml" 2>/dev/null
rc=$?; [ $rc -eq 0 ] && ok "Bash ranged --expand=deep_nest_sh:2-4 exits 0" || no "Bash ranged expand failed (rc=$rc)"
grep -q 'lines="2-4/10"' "$TMP/sh_slice.xml" && ok "Bash slice marker lines=\"2-4/10\" present" || no "Bash slice marker missing/wrong"
grep -q 'if \[ "\$1" -gt 0 \]' "$TMP/sh_slice.xml" && ok "Bash slice contains the expected if-line" || no "Bash slice missing the if-line"
grep -q 'for i in' "$TMP/sh_slice.xml" && ok "Bash slice contains the expected for-line" || no "Bash slice missing the for-line"
grep -q 'deep_nest_sh()' "$TMP/sh_slice.xml" && no "Bash slice leaked the signature line (out of range)" || ok "Bash slice correctly excludes the signature line"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 3. <calls> sidecar reflects real callees regardless of the slice window ==="
# ═══════════════════════════════════════════════════════════════════════════
# callsLeafAndDeep body: 1=sig 2={ 3=leaf(x); 4=return deepNest(...); 5=}. Slice 3-4 INCLUDES both call
# sites; the <calls> sidecar must list leaf+deepNest either way (it's driven by the symbol's real call
# edges, not the visible window) — but as a stronger check, slice 1-1 (signature only, EXCLUDES both call
# sites) must STILL list both calls in <calls>, proving the sidecar isn't re-derived from the visible text.
"$BIN" "$JSFIX" --expand=callsLeafAndDeep:1-1 --no-cache >"$TMP/narrow_slice.xml" 2>/dev/null
grep -q 'lines="1-1/5"' "$TMP/narrow_slice.xml" && ok "narrow 1-line slice marker correct" || no "narrow slice marker wrong"
grep -q '<c n="leaf"' "$TMP/narrow_slice.xml" && ok "1-line slice EXCLUDING the call sites still lists <c n=\"leaf\"> in <calls>" || no "<calls> sidecar missing leaf when window excludes it"
grep -q '<c n="deepNest"' "$TMP/narrow_slice.xml" && ok "1-line slice EXCLUDING the call sites still lists <c n=\"deepNest\"> in <calls>" || no "<calls> sidecar missing deepNest when window excludes it"
grep -q 'leaf( x )' "$TMP/narrow_slice.xml" && no "1-line slice leaked line 3 (leaf call site) — window not respected" || ok "1-line slice body correctly excludes the call-site lines"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 4. --outline=SYM:START-END (range suffix, unsupported by outline) degrades cleanly ==="
# ═══════════════════════════════════════════════════════════════════════════
# --outline has no range form (a control-flow skeleton is a whole-symbol shape) but SYM:START-END is the
# muscle memory --expand teaches. This block used to pin the ACCIDENT: the literal name "bigFunction:3-5"
# missed, so nothing was emitted and the exit was 0 — indistinguishable from a real typo, and once --outline
# started refusing typos (exit 1 + empty stdout) that accident became a REFUSAL of a name that was fine.
# The contract now: strip the range, outline the whole symbol, and SAY SO on stderr. Never silent either way.
"$BIN" "$CPPFIX" --outline=bigFunction:3-5 --no-cache >"$TMP/outline_range.xml" 2>"$TMP/outline_range.err"
rc=$?
[ $rc -eq 0 ] && ok "--outline=SYM:START-END exits 0 (no crash on an unsupported suffix)" || no "--outline=SYM:START-END crashed/failed (rc=$rc)"
grep -q '<outline>' "$TMP/outline_range.xml" && ok "--outline=SYM:START-END outlines the WHOLE symbol (range stripped, name honoured)" || no "--outline=SYM:START-END emitted no outline — a valid name was refused for its suffix"
grep -q 'no line-range form' "$TMP/outline_range.err" && ok "--outline=SYM:START-END explains the strip on stderr (not a silent reinterpretation)" || no "--outline=SYM:START-END dropped the range SILENTLY — the reader cannot tell they got the whole symbol"
grep -q 'did you mean' "$TMP/outline_range.err" && no "--outline=SYM:START-END still reports a valid name as a typo (did-you-mean)" || ok "--outline=SYM:START-END no longer misreports a valid name as a typo"
command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$TMP/outline_range.xml" 2>/dev/null && ok "--outline=SYM:START-END output still well-formed XML" || no "--outline=SYM:START-END produced malformed XML"; }

# the PLAIN --outline=bigFunction (no range) still works normally as the control.
"$BIN" "$CPPFIX" --outline=bigFunction --no-cache >"$TMP/outline_plain.xml" 2>/dev/null
grep -q '<outline>' "$TMP/outline_plain.xml" && ok "control: plain --outline=bigFunction (no range) DOES emit an <outline> block" || no "control: plain --outline broken"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== MUTATION: prove the size/marker comparisons are load-bearing, not vacuous ==="
# ═══════════════════════════════════════════════════════════════════════════
MUT="$( ok(){ :; }; no(){ echo TRIPPED; }
        # asserting the compressed slice is LARGER than the plain slice must fail (it is actually smaller)
        if [ "$SZ_COMPRESS" -gt "$SZ_PLAIN" ]; then ok; else no; fi )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (asserting compressed>plain size correctly fails)" \
                       || no "mutation self-test broke — size comparison assertion is not live"

MUT2="$( ok(){ :; }; no(){ echo TRIPPED; }
        if grep -q 'lines="9-9/14"' "$TMP/js_slice.xml"; then ok; else no; fi )"
[ "$MUT2" = "TRIPPED" ] && ok "mutation self-test (asserting a wrong lines= marker on the JS slice correctly fails)" \
                        || no "mutation self-test broke — JS slice marker assertion is not live"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
