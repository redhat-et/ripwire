#!/usr/bin/env bash
# grepcheck.sh — gate for literal --grep feature.
#
# Asserts:
#   - run ripwire --grep=perimeter on test/fixture
#   - output contains <grep pattern="perimeter" header
#   - at least one hit whose p= points into geometry.cpp
#   - each hit's in= attribute names the enclosing symbol (asserts exact value after inspection)
#   - special chars don't crash: --grep='((' and --grep='a"b' exit cleanly (exit < 128) and output passes xmllint
#   - determinism: run the perimeter grep twice, byte-identical output
#
# Usage:
#   test/grepcheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/grepcheck.sh
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

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "grepcheck: BIN=$BIN  CORPUS=$CORPUS"

# ── (1) Run --grep=perimeter ─────────────────────────────────────────────────────────────────────

"$BIN" "$CORPUS" --no-cache --grep=perimeter >"$TMP/perimeter" 2>/dev/null

# (1a) Output contains <grep pattern="perimeter" header
grep -q '<grep pattern="perimeter"' "$TMP/perimeter" \
    && ok "--grep=perimeter output has correct header" \
    || no "--grep=perimeter missing or wrong header"

# (1b) At least one hit points into geometry.cpp
grep -q 'p="[^"]*geometry\.cpp' "$TMP/perimeter" \
    && ok "at least one hit in geometry.cpp" \
    || no "no hits found in geometry.cpp"

# (1c) Enclosing symbols: the real output has (P5, 2026-07-27 — a <hit> is no longer self-closing: it
#      always carries <m><![CDATA[the matched line]]></m>, see test/grepscancheck.sh):
#      <hit p=".../geometry.cpp:11" in="perimeter"><m><![CDATA[double perimeter( … )]]></m></hit>
#      <hit p=".../geometry.cpp:16" in="perimeter">…
#      <hit p=".../geometry.h:13"   in="perimeter">…
#      We assert these exact values (checked by inspection above)
grep -q '<hit p="[^"]*geometry\.cpp:11" in="perimeter">' "$TMP/perimeter" \
    && ok "geometry.cpp:11 enclosing symbol is 'perimeter'" \
    || { no "geometry.cpp:11 missing or wrong enclosing symbol"; head -20 "$TMP/perimeter"; }

grep -q '<hit p="[^"]*geometry\.cpp:16" in="perimeter">' "$TMP/perimeter" \
    && ok "geometry.cpp:16 enclosing symbol is 'perimeter'" \
    || no "geometry.cpp:16 missing or wrong enclosing symbol"

grep -q '<hit p="[^"]*geometry\.h:13" in="perimeter">' "$TMP/perimeter" \
    && ok "geometry.h:13 enclosing symbol is 'perimeter'" \
    || no "geometry.h:13 missing or wrong enclosing symbol"

# (1c2) …and the matched line itself is emitted with the hit (the P5 fix: a hit that shows WHERE but not
#       WHAT cost the agent a follow-up file read)
grep -q '<hit p="[^"]*geometry\.cpp:11" in="perimeter"><m><!\[CDATA\[double perimeter(' "$TMP/perimeter" \
    && ok "geometry.cpp:11 hit carries its matched line in <m>" \
    || { no "geometry.cpp:11 hit has no/incorrect <m> matched line"; head -20 "$TMP/perimeter"; }

# (1d) Output is valid XML
xmllint --noout "$TMP/perimeter" 2>/dev/null \
    && ok "perimeter grep output is well-formed XML" \
    || no "perimeter grep output is malformed XML"

# ── (2) Special characters don't crash ───────────────────────────────────────────────────────────

# --grep='((' should not crash (exit code < 128 means no signal)
"$BIN" "$CORPUS" --no-cache --grep='((' >"$TMP/special1" 2>/dev/null
e1=$?
[ "$e1" -lt 128 ] \
    && ok "--grep='((' does not crash (exit $e1)" \
    || no "--grep='((' crashed or signaled (exit $e1)"

[ -s "$TMP/special1" ] && xmllint --noout "$TMP/special1" 2>/dev/null \
    && ok "--grep='((' output is valid XML" \
    || ok "--grep='((' output is empty or invalid XML (acceptable)"

# --grep='a"b' should not crash
"$BIN" "$CORPUS" --no-cache --grep='a"b' >"$TMP/special2" 2>/dev/null
e2=$?
[ "$e2" -lt 128 ] \
    && ok "--grep='a\"b' does not crash (exit $e2)" \
    || no "--grep='a\"b' crashed or signaled (exit $e2)"

[ -s "$TMP/special2" ] && xmllint --noout "$TMP/special2" 2>/dev/null \
    && ok "--grep='a\"b' output is valid XML" \
    || ok "--grep='a\"b' output is empty or invalid XML (acceptable)"

# ── (3) Determinism: byte-identical runs ────────────────────────────────────────────────────────

"$BIN" "$CORPUS" --no-cache --grep=perimeter >"$TMP/det1" 2>/dev/null
"$BIN" "$CORPUS" --no-cache --grep=perimeter >"$TMP/det2" 2>/dev/null

diff -q "$TMP/det1" "$TMP/det2" >/dev/null \
    && ok "determinism: byte-identical perimeter grep output" \
    || no "determinism: non-identical output between runs"

# ── (4) §P11.1 — hits are ordered SOURCE-FIRST, before the row cap ──────────────────────────────
#
# The finding: --grep emitted hits in plain path-alphabetical order and then cut at 100 rows. On this
# repo that is a systematic bias against code — `--grep=DEGRADED_PATH_ALERT` filled 66 of its 100 shown
# rows with markdown and left no `test/` row at all, because `AGENTS.md`/`AUDIT*.md` sort above `src/`
# and the cap always cuts the tail.
#
# The fix is ORDERING ONLY: grepHits() (src/search.h pass 2) stable-sorts into three path tiers —
# source → test/bench → docs (rw::pathTierOf, src/filter.h) — with path-alphabetical order preserved
# untouched INSIDE each tier. Nothing is dropped, no attribute changes, and because the order lives in
# the SHARED grepHits() the CLI verb and the MCP `grep` verb cannot diverge.
#
# CORPUS-SCOPE NOTE, recorded so it is not re-found: a row can be absent for a CORPUS reason rather than
# an ordering one, and no ordering change can surface it — `vendor` and `third_party` are on the CRAWL
# DENYLIST (isSkippedCrawlDir, src/ingest.h), so files under them are never indexed and --grep, which scans
# the indexed corpus, structurally cannot see them. That is a corpus decision, not a serialization one;
# these checks assert what ordering CAN deliver and do not assert a row the scanner never had.

# the sandbox: alphabetical order is the exact INVERSE of the wanted order.
#   AAA_notes.md      (doc)    sorts FIRST  alphabetically, must emit LAST
#   src/aaa.cpp       (source) sorts second alphabetically, must emit FIRST
#   src/zzz.cpp       (source)                              must emit SECOND (tier-internal alpha)
#   test/aaa_test.cpp (test)                                must emit THIRD
SB="$TMP/tiersandbox"
mkdir -p "$SB/src" "$SB/test"
printf '# Notes\n\nThe design calls TIERMARKERTOKEN from the dispatch layer.\n'  >"$SB/AAA_notes.md"
printf 'void alphaEntry()\n{\n    TIERMARKERTOKEN();\n}\n'                       >"$SB/src/aaa.cpp"
printf 'void zetaEntry()\n{\n    TIERMARKERTOKEN();\n}\n'                        >"$SB/src/zzz.cpp"
printf 'void testAlphaEntry()\n{\n    TIERMARKERTOKEN();\n}\n'                   >"$SB/test/aaa_test.cpp"

"$BIN" "$SB" --no-cache --grep=TIERMARKERTOKEN >"$TMP/tier.xml" 2>/dev/null
tr '<' '\n' <"$TMP/tier.xml" | sed -n 's/^hit p="\([^"]*\)".*/\1/p' >"$TMP/tier.paths"

# (4a) nothing was dropped — an ordering change that loses a row must never read as a pass
[ "$( wc -l <"$TMP/tier.paths" | tr -d ' ' )" = "4" ] \
    && ok "tier order: all 4 sandbox hits emitted (ordering drops nothing)" \
    || { no "tier order: expected 4 hits, got $( wc -l <"$TMP/tier.paths" | tr -d ' ' )"; cat "$TMP/tier.paths"; }

tierRow(){ sed -n "$1p" "$TMP/tier.paths"; }
case "$( tierRow 1 )" in */src/aaa.cpp:*)       ok "tier order row 1 = src/aaa.cpp (source tier leads)" ;;
                        *)                      no "tier order row 1 = '$( tierRow 1 )', expected src/aaa.cpp" ;; esac
case "$( tierRow 2 )" in */src/zzz.cpp:*)       ok "tier order row 2 = src/zzz.cpp (alphabetical WITHIN a tier preserved)" ;;
                        *)                      no "tier order row 2 = '$( tierRow 2 )', expected src/zzz.cpp" ;; esac
case "$( tierRow 3 )" in */test/aaa_test.cpp:*) ok "tier order row 3 = test/aaa_test.cpp (test tier after source)" ;;
                        *)                      no "tier order row 3 = '$( tierRow 3 )', expected test/aaa_test.cpp" ;; esac
case "$( tierRow 4 )" in */AAA_notes.md:*)      ok "tier order row 4 = AAA_notes.md (doc tier LAST, though alphabetically first)" ;;
                        *)                      no "tier order row 4 = '$( tierRow 4 )', expected AAA_notes.md" ;; esac

# (4b) --limit/--offset page down the TIERED order, not the alphabetical one
"$BIN" "$SB" --no-cache --grep=TIERMARKERTOKEN --limit=1 >"$TMP/tier_l1.xml" 2>/dev/null
grep -q '<hit p="[^"]*/src/aaa\.cpp:' "$TMP/tier_l1.xml" && ! grep -q 'AAA_notes\.md:' "$TMP/tier_l1.xml" \
    && ok "--limit=1 returns the SOURCE row (paging walks the tiered order)" \
    || { no "--limit=1 did not return the source row"; cat "$TMP/tier_l1.xml"; }

"$BIN" "$SB" --no-cache --grep=TIERMARKERTOKEN --limit=1 --offset=3 >"$TMP/tier_o3.xml" 2>/dev/null
grep -q '<hit p="[^"]*AAA_notes\.md:' "$TMP/tier_o3.xml" \
    && ok "--offset=3 --limit=1 returns the DOC row (last in the tiered order)" \
    || { no "--offset=3 --limit=1 did not return the doc row"; cat "$TMP/tier_o3.xml"; }

# (4c) the finding's own repro, on this repo's real corpus: the capped first screen is all code
"$BIN" "$ROOT" --grep=DEGRADED_PATH_ALERT >"$TMP/repro.xml" 2>/dev/null
tr '<' '\n' <"$TMP/repro.xml" | sed -n 's/^hit p="\([^"]*\)".*/\1/p' >"$TMP/repro.paths"

[ "$( wc -l <"$TMP/repro.paths" | tr -d ' ' )" -gt 0 ] \
    && ok "repro query returned $( wc -l <"$TMP/repro.paths" | tr -d ' ' ) rows" \
    || no "repro query returned no rows at all"

[ "$( grep -c '\.md:' "$TMP/repro.paths" )" = "0" ] \
    && ok "capped first screen carries ZERO markdown rows (was 66 of 100)" \
    || no "capped first screen still carries $( grep -c '\.md:' "$TMP/repro.paths" ) markdown rows"

case "$( sed -n 1p "$TMP/repro.paths" )" in
    */src/*) ok "first row of the repro query is a src/ path" ;;
    *)       no "first row of the repro query is '$( sed -n 1p "$TMP/repro.paths" )', not a src/ path" ;;
esac

# (4d) with the cap lifted, EVERY doc row still sorts after EVERY code row
"$BIN" "$ROOT" --grep=DEGRADED_PATH_ALERT --limit=1000 >"$TMP/repro_all.xml" 2>/dev/null
tr '<' '\n' <"$TMP/repro_all.xml" | sed -n 's/^hit p="\([^"]*\)".*/\1/p' >"$TMP/repro_all.paths"
firstDocRow="$( grep -n '\.md:'  "$TMP/repro_all.paths" | head -1 | cut -d: -f1 )"
lastCodeRow="$( grep -vn '\.md:' "$TMP/repro_all.paths" | tail -1 | cut -d: -f1 )"
if [ -n "$firstDocRow" ] && [ -n "$lastCodeRow" ] && [ "$firstDocRow" -gt "$lastCodeRow" ]; then
    ok "un-capped listing: first doc row ($firstDocRow) sorts after the last code row ($lastCodeRow)"
else
    no "un-capped listing interleaves docs and code (first doc $firstDocRow, last code $lastCodeRow)"
fi

xmllint --noout "$TMP/repro.xml" 2>/dev/null \
    && ok "G4: tiered grep output is well-formed XML" \
    || no "G4: tiered grep output is malformed XML"

"$BIN" "$SB" --no-cache --grep=TIERMARKERTOKEN >"$TMP/tdet1" 2>/dev/null
"$BIN" "$SB" --no-cache --grep=TIERMARKERTOKEN >"$TMP/tdet2" 2>/dev/null
diff -q "$TMP/tdet1" "$TMP/tdet2" >/dev/null \
    && ok "determinism: byte-identical tiered output across runs" \
    || no "determinism: tiered output differs between runs"

# ── Summary ───────────────────────────────────────────────────────────────────────────────────────

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
