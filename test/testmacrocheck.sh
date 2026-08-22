#!/usr/bin/env bash
# testmacrocheck.sh — macro-defined test bodies must be symbols, so their call sites are edges.
#
# ── THE DEFECT THIS PINS (LB-E, r10 gitnexus harvest 2026-08-20) ─────────────────────────────────────
# A doctest/Catch2 test body is a MACRO INVOCATION followed by a block:
#
#   TEST_CASE( "double PageRank numeric, dangling, and top-K contracts" )
#   {
#       rw::pageRankDouble( … );   // ×5 in this repo's own doctest pagerank harness
#   }
#
# tree-sitter-cpp cannot expand the macro, so this parses as TWO SIBLING nodes — an
# (expression_statement (call_expression …) (MISSING ";")) and a bare (compound_statement …) — and
# neither is a definition. No symbol spans the body, so every call inside it attributes to NOTHING:
# measured on this repo, `--callers=pageRankDouble` reported count="1" while `--grep` found all five
# sites. UNFLAGGED — and --test-gate, --affected and the tested= lens all rest on exactly those
# missing test→subject edges.
#
# (The harness file's PATH is deliberately not spelled anywhere in this script: the run= hint index
# treats a test/*.sh that names a harness file as its runner, and this gate does not run it.)
#
# ── THE RULE ─────────────────────────────────────────────────────────────────────────────────────────
# A KNOWN test-macro invocation (kTestBlockMacroNames in ingest.cpp: doctest/Catch2 TEST_CASE,
# TEST_CASE_FIXTURE, TEST_CASE_METHOD, SCENARIO, TEST_SUITE) whose expression_statement carries the
# error-recovery MISSING ";" and whose next named sibling is a compound_statement becomes a t="fn"
# symbol: named by its title string literal (VERBATIM — no finalSegment split on '.'), spanning from
# the macro identifier to the block's closing brace, testScope=1 (it IS a test by in-file convention,
# wherever the file lives). Calls inside then attribute by the ordinary innermost-span scan.
# PRECISION OVER RECALL: an unknown macro name, or a real `call( "x" );` statement (real semicolon —
# no MISSING node) followed by an unrelated block, must mint NOTHING. TEST_CASE_TEMPLATE /
# SCENARIO_TEMPLATE are a DOCUMENTED GAP: their block is swallowed into the argument list by error
# recovery (no sibling compound_statement), so they stay invisible — recall widening, not a bug here.
#
# ── ARMS ─────────────────────────────────────────────────────────────────────────────────────────────
#   0. PRESENCE   — subjects and every asserted-on symbol extract (green-while-inert guard).
#   1. SYMBOLS    — each TEST_CASE/TEST_SUITE title is a t="fn" symbol, incl. inside a namespace.
#   2. CALLERS    — --callers=rankStep sees all four test-case callers (count + each title).
#   3. IMPACT     — --impact=rankStep reaches the test bodies it was blind to.
#   4. TESTED=    — the subject carries tested="1"; in-file (src/) macro tests seed it too.
#   5. AFFECTED   — --affected on the subject's file names the doctest file as a test to run.
#   6. NAME       — a dotted title survives verbatim (finalSegment must not split it).
#   7. NEGATIVE   — unknown macro name / real-semicolon call+block mint no symbol; the enclosing
#                   function keeps its own edges.
#   8. IGNORE-TESTS — a macro test in src/ vanishes under --ignore-tests; production code survives.
#   9. HYGIENE    — determinism (two cold runs byte-identical), well-formed XML, warm == cold (the
#                   extraction change rides kParserVer, so a stale blob must not survive).
#
# Usage:
#   bash test/testmacrocheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/testmacrocheck.sh
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
echo "testmacrocheck: BIN=$BIN  TMP=$TMP"

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────
# The doctest file mirrors the repo's own pagerank verify harness: one title, several call sites
# nested in plain blocks/branches, all of which must attribute to the ONE test-case symbol.
FIX="$TMP/fix"; mkdir -p "$FIX/src" "$FIX/test"

cat > "$FIX/src/rankcore.cpp" <<'EOF'
namespace rw
{

int rankStep( int value )
{
    return value + 1;
}

int neverTested( int value )
{
    return value - 1;
}

}
EOF

cat > "$FIX/test/verify_rank.cpp" <<'EOF'
namespace rw
{
int rankStep( int value );
}

TEST_CASE( "rank step convergence and mass contracts" )
{
    const int first = rw::rankStep( 1 );
    if( first > 0 )
    {
        rw::rankStep( 2 );
    }
    {
        rw::rankStep( 3 );
    }
}

TEST_CASE( "rank.step determinism" )
{
    rw::rankStep( 4 );
}

namespace app
{

TEST_CASE( "namespaced rank case" )
{
    rw::rankStep( 5 );
}

}

TEST_SUITE( "rank suite" )
{

TEST_CASE( "suite inner case" )
{
    rw::rankStep( 6 );
}

}
EOF

# In-file convention: a macro test INSIDE a production src/ file — no path signal at all, so anything
# this gate observes being treated as a test here is attributable to the extraction bit and nothing else.
cat > "$FIX/src/inline_widget.cpp" <<'EOF'
int widgetCompute( int value )
{
    return value * 2;
}

TEST_CASE( "widget compute doubles" )
{
    widgetCompute( 2 );
}
EOF

# Negative controls, in their own corpus: the same sibling shape must NOT trigger on (a) a real
# statement + unrelated block (the semicolon is REAL, not MISSING) and (b) an unknown macro name.
NEG="$TMP/neg"; mkdir -p "$NEG/src"
cat > "$NEG/src/negshape.cpp" <<'EOF'
void logCall( const char* message );
int helperFn( int value );

void realFn()
{
    logCall( "startup" );
    {
        helperFn( 3 );
    }
}

WIDGET_DEF( "not a test" )
{
    helperFn( 4 );
}
EOF

# ── the maps ─────────────────────────────────────────────────────────────────────────────────────────
MAP="$TMP/map.xml";  "$BIN" "$FIX" --no-cache > "$MAP" 2>/dev/null
NMAP="$TMP/neg.xml"; "$BIN" "$NEG" --no-cache > "$NMAP" 2>/dev/null

hasrow(){   # $1=name → the map has a symbol row with exactly this n=
    tr '<' '\n' < "$MAP" | grep -q "n=\"$1\""
}

# ── arm 0: PRESENCE ──────────────────────────────────────────────────────────────────────────────────
bad=""
for s in rankStep neverTested widgetCompute; do
    hasrow "$s" || bad="$bad $s"
done
tr '<' '\n' < "$NMAP" | grep -q 'n="realFn"'    || bad="$bad realFn"
tr '<' '\n' < "$NMAP" | grep -q 'n="helperFn"'  || bad="$bad helperFn"
if [ -z "$bad" ]; then ok "arm0 presence: every subject the arms below rest on extracts"
else no "arm0 presence: missing subject symbols:$bad"; fi

# ── arm 1: SYMBOLS — the titles are t="fn" rows ──────────────────────────────────────────────────────
bad=""
for t in "rank step convergence and mass contracts" "namespaced rank case" "suite inner case" "widget compute doubles" "rank suite"; do
    tr '<' '\n' < "$MAP" | grep "n=\"$t\"" | head -1 | grep -q '^s t="fn"' || bad="$bad|$t"
done
if [ -z "$bad" ]; then ok "arm1 symbols: every test-macro title is a t=\"fn\" symbol (incl. namespaced + suite-nested)"
else no "arm1 symbols: titles missing or not t=\"fn\":$bad"; fi

# ── arm 2: CALLERS — the recovered edges ─────────────────────────────────────────────────────────────
CAL="$( "$BIN" "$FIX" --callers=rankStep 2>/dev/null )"
bad=""
for t in "rank step convergence and mass contracts" "rank.step determinism" "namespaced rank case" "suite inner case"; do
    printf '%s' "$CAL" | grep -q "n=\"$t\"" || bad="$bad|$t"
done
if [ -z "$bad" ]; then ok "arm2 callers: all four test-case callers of rankStep are visible"
else no "arm2 callers: --callers=rankStep is still blind to:$bad"; fi
if printf '%s' "$CAL" | grep -q 'count="4"'; then ok "arm2 callers: count=\"4\" — the distinct-caller count agrees"
else no "arm2 callers: expected count=\"4\" distinct callers, got: $( printf '%s' "$CAL" | grep -o 'count="[0-9]*"' | head -1 )"; fi

# ── arm 3: IMPACT — the transitive lens sees the same edges ──────────────────────────────────────────
IMP="$( "$BIN" "$FIX" --impact=rankStep 2>/dev/null )"
if printf '%s' "$IMP" | grep -q 'rank step convergence and mass contracts'; then
    ok "arm3 impact: --impact=rankStep reaches the test body"
else no "arm3 impact: --impact=rankStep still omits the test body"; fi

# ── arm 4: TESTED= — the coverage lens rests on the recovered edges ──────────────────────────────────
MET="$TMP/metrics.xml"
"$BIN" "$FIX" --metrics > "$MET" 2>/dev/null
testedrow(){   # $1=symbol name → prints its <s …> row
    tr '<' '\n' < "$MET" | grep "n=\"$1\"" | head -1
}
bad=""
for s in rankStep widgetCompute; do
    printf '%s' "$( testedrow "$s" )" | grep -q 'tested="1"' || bad="$bad $s"
done
if [ -z "$bad" ]; then ok "arm4 tested=: subjects reached only from macro test bodies carry tested=\"1\""
else no "arm4 tested=: subjects reached only from macro test bodies lack tested=\"1\":$bad"; fi
if printf '%s' "$( testedrow "neverTested" )" | grep -q 'tested="1"'; then
    no "arm4 tested=: an uncalled symbol (neverTested) was marked tested=\"1\" (over-trigger)"
else ok "arm4 tested=: the uncalled control stays untested"; fi

# ── arm 5: AFFECTED — tests-to-run sees the doctest file ─────────────────────────────────────────────
AFF="$( "$BIN" "$FIX" --affected=src/rankcore.cpp 2>/dev/null )"
if printf '%s' "$AFF" | tr '<' '\n' | grep -q '^test p="[^"]*test/verify_rank\.cpp"'; then
    ok "arm5 affected: the doctest file is named as a test to run for the subject's file"
else no "arm5 affected: --affected=src/rankcore.cpp does not name test/verify_rank.cpp"; fi

# ── arm 6: NAME fidelity — a dotted title is NOT an identifier to split ──────────────────────────────
if hasrow "rank.step determinism"; then ok "arm6 name: the dotted title survives verbatim"
else no "arm6 name: the dotted title was mangled (finalSegment split it?)"; fi

# ── arm 7: NEGATIVE — no over-trigger, and the enclosing fn keeps its edges ──────────────────────────
bad=""
tr '<' '\n' < "$NMAP" | grep -q 'n="startup"'    && bad="$bad startup"
tr '<' '\n' < "$NMAP" | grep -q 'n="not a test"' && bad="$bad not-a-test"
if [ -z "$bad" ]; then ok "arm7 negative: a real call+block and an unknown macro mint no symbol"
else no "arm7 negative: phantom symbols minted:$bad"; fi
if "$BIN" "$NEG" --callers=helperFn 2>/dev/null | grep -q 'n="realFn"'; then
    ok "arm7 negative: realFn keeps its helperFn edge"
else no "arm7 negative: realFn lost its helperFn edge"; fi

# ── arm 8: IGNORE-TESTS — the in-file bit reaches the filter ─────────────────────────────────────────
IGN="$TMP/ign.xml"
"$BIN" "$FIX" --ignore-tests > "$IGN" 2>/dev/null
if tr '<' '\n' < "$IGN" | grep -q 'n="widget compute doubles"'; then
    no "arm8 ignore-tests: an in-file (src/) macro test survived --ignore-tests"
else ok "arm8 ignore-tests: the in-file macro test is dropped"; fi
if tr '<' '\n' < "$IGN" | grep -q 'n="widgetCompute"'; then
    ok "arm8 ignore-tests: production code in the same file survives"
else no "arm8 ignore-tests: production code (widgetCompute) was dropped alongside the test"; fi

# ── arm 9: HYGIENE ───────────────────────────────────────────────────────────────────────────────────
rm -rf "$FIX/.ripwire_cache" 2>/dev/null
"$BIN" "$FIX" --no-cache > "$TMP/cold1.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache > "$TMP/cold2.xml" 2>/dev/null
if diff -q "$TMP/cold1.xml" "$TMP/cold2.xml" >/dev/null 2>&1; then ok "arm9 determinism: two cold runs byte-identical"
else no "arm9 determinism: two cold runs differ"; fi
if xmllint --noout "$MAP" 2>/dev/null; then ok "arm9 well-formed: the map parses (titles with spaces/dots escape cleanly)"
else no "arm9 well-formed: the map is not well-formed XML"; fi
# warm == cold: a blob written by a pre-feature binary must be invalidated by the kParserVer bump. The
# second run below reads the cache the first one wrote.
"$BIN" "$FIX" > "$TMP/warm1.xml" 2>/dev/null
"$BIN" "$FIX" > "$TMP/warm2.xml" 2>/dev/null
if diff -q "$TMP/warm1.xml" "$TMP/warm2.xml" >/dev/null 2>&1; then ok "arm9 warm==cold: cached extraction agrees with the fresh parse"
else no "arm9 warm==cold: a warm run disagrees with the cold run (cache key missed the extraction change)"; fi

echo
[ "$fail" -eq 0 ] && echo "testmacrocheck: ALL PASS" || echo "testmacrocheck: FAILURES"
exit "$fail"
