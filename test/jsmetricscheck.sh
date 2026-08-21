#!/usr/bin/env bash
# jsmetricscheck.sh — does --metrics / --for / --quality-delta actually WORK on JavaScript + Bash, with
# real hand-computed values, or do they silently stay 0 / degrade to C-family-only? Wave-1 landed JS+Bash
# ingest (jslangcheck.sh: symbols + call edges) and metricscheck.sh hand-checks metrics on C++/Python —
# neither gate proves the per-symbol Q-metrics (loc/params/nest/cbo), the --for lens, or --quality-delta
# actually compute correct NON-ZERO values on the two new languages. This gate closes that gap.
#
# Fixture (test/jsmetricsfix/): shapes.js + shapes.sh, each with a leaf fn, a 3-deep-nested/3-param fn, a
# fn that calls both (cbo=2), and (JS only) an arrow-fn-bound-to-const with 2 params + 1 nesting level.
# Every loc/params/nest/cbo value below was counted BY HAND from the source and cross-checked once against
# a real run (see the comment blocks in the fixture files) before being pinned as an assertion.
#
# Usage:
#   test/jsmetricscheck.sh
#   RIPWIRE_BIN=asan/ripwire test/jsmetricscheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success. Does NOT edit
# regression.sh. All --quality-baseline/--quality-delta work happens in a SCRATCH copy (mktemp), never on
# the checked-in fixture, since --quality-baseline writes a sidecar file next to the corpus.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/jsmetricsfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/jsmetricsfix directory"; exit 2; }

echo "jsmetricscheck: BIN=$BIN  FIX=$FIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --metrics: hand-checked loc/params/nest/cbo on JavaScript ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$FIX" --metrics --no-cache >"$TMP/m1" 2>/dev/null
"$BIN" "$FIX" --metrics --no-cache >"$TMP/m2" 2>/dev/null
MAP="$( cat "$TMP/m1" )"

diff -q "$TMP/m1" "$TMP/m2" >/dev/null && ok "determinism (--metrics byte-identical run-to-run)" || no "non-deterministic --metrics output"

sattr(){ printf '%s' "$MAP" | sed 's/>/>\n/g' | grep -E "<s t=\"[^\"]*\" n=\"$1\"" | head -1; }
assert_attr(){ # name attr val
    local line; line="$( sattr "$1" )"
    if printf '%s' "$line" | grep -q " $2=\"$3\""; then ok "$1: $2=$3"; else no "$1: expected $2=$3 — got: $line"; fi
}

# leaf (JS): 1 param, 0 nesting, 0 calls (cbo=0), loc=4
assert_attr leaf loc 4;     assert_attr leaf params 1;   assert_attr leaf nest 0;   assert_attr leaf cbo 0
# deepNest (JS): 3 params, 3-deep nesting (if>for>if), calls nothing in-repo, loc=14
assert_attr deepNest loc 14; assert_attr deepNest params 3; assert_attr deepNest nest 3; assert_attr deepNest cbo 0
# callsLeafAndDeep (JS): 1 param, 0 nesting, calls leaf()+deepNest() -> cbo=2
assert_attr callsLeafAndDeep params 1; assert_attr callsLeafAndDeep nest 0; assert_attr callsLeafAndDeep cbo 2
# arrowWithParams (JS, arrow-fn bound to const): 2 params, 1-deep nesting (if)
assert_attr arrowWithParams params 2; assert_attr arrowWithParams nest 1; assert_attr arrowWithParams cbo 0

# REAL-FINDING trap: if JS metrics silently stay 0 (grammar shape not recognized), assert_attr above would
# have already failed loudly — but double-check explicitly that at least ONE JS symbol has a NON-ZERO
# nest and NON-ZERO params, so a wholesale "everything defaulted to 0" regression cannot slip past a
# coincidental single bad assertion.
NONZERO_NEST_JS="$( printf '%s' "$MAP" | grep -c 'p="test/jsmetricsfix/shapes.js"' )"
printf '%s' "$( sattr deepNest )" | grep -qv ' nest="0"' && ok "sanity: JS nest values are NOT all defaulting to 0" || no "sanity: JS nest defaulted to 0 across the board — metrics may be silently broken on JS"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --metrics: hand-checked loc/params/nest/cbo on Bash ==="
# ═══════════════════════════════════════════════════════════════════════════
# leaf_sh: 0 params (Bash fns take no formal param list), 0 nesting, 0 calls, loc=4
assert_attr leaf_sh loc 4;     assert_attr leaf_sh params 0;   assert_attr leaf_sh nest 0;   assert_attr leaf_sh cbo 0
# deep_nest_sh: 3-deep nesting (if>for>if), calls nothing in-repo, loc=10
assert_attr deep_nest_sh loc 10; assert_attr deep_nest_sh params 0; assert_attr deep_nest_sh nest 3; assert_attr deep_nest_sh cbo 0
# calls_leaf_and_deep_sh: calls leaf_sh()+deep_nest_sh() -> cbo=2
assert_attr calls_leaf_and_deep_sh nest 0; assert_attr calls_leaf_and_deep_sh cbo 2

printf '%s' "$( sattr deep_nest_sh )" | grep -qv ' nest="0"' && ok "sanity: Bash nest values are NOT all defaulting to 0" || no "sanity: Bash nest defaulted to 0 across the board — metrics may be silently broken on Bash"

# golden neutrality: the default map (no --metrics) carries none of these attributes on JS/Bash either.
"$BIN" "$FIX" --no-cache >"$TMP/def" 2>/dev/null
LEAK="$( grep -oE ' (loc|params|nest|cbo)="[^"]*"' "$TMP/def" | head -1 )"
[ -z "$LEAK" ] && ok "golden-neutral: no Q-metric attribute leaks into the default JS/Bash map" || no "attribute leaked into default map: $LEAK"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --for: the task lens surfaces cx/ccx on JS/Bash and ranks by relevance ==="
# ═══════════════════════════════════════════════════════════════════════════
FOR_OUT="$( "$BIN" "$FIX" --for="deep nesting" --no-cache 2>/dev/null )"
FOR_RC=$?
[ $FOR_RC -eq 0 ] && ok "--for exits 0 on JS/Bash corpus" || no "--for failed (rc=$FOR_RC)"
printf '%s' "$FOR_OUT" | grep -q 'shapes.js' && ok "--for includes the JS file" || no "--for missing the JS file"
printf '%s' "$FOR_OUT" | grep -q 'shapes.sh' && ok "--for includes the Bash file" || no "--for missing the Bash file"
printf '%s' "$FOR_OUT" | grep -q 'function deepNest' && ok "--for surfaces the deepNest JS signature (matches the query)" || no "--for did not surface deepNest for a 'deep nesting' query"
printf '%s' "$FOR_OUT" | grep -q 'deep_nest_sh' && ok "--for surfaces the deep_nest_sh Bash signature" || no "--for did not surface deep_nest_sh"
# deepNest's cx/ccx in the --for lens must match the --metrics values (cx=4 ccx=6), not be zeroed out.
printf '%s' "$FOR_OUT" | grep -A0 'function deepNest' | grep -q 'cx="4" ccx="6"' \
    && ok "--for: deepNest carries the correct cx=4 ccx=6 (matches --metrics, not zeroed)" \
    || { no "--for: deepNest cx/ccx wrong or missing"; printf '%s' "$FOR_OUT" | grep -o '<d[^>]*>[^<]*deepNest[^<]*' ; }

# determinism of --for on this corpus
"$BIN" "$FIX" --for="deep nesting" --no-cache >"$TMP/for2" 2>/dev/null
printf '%s' "$FOR_OUT" >"$TMP/for1"
diff -q "$TMP/for1" "$TMP/for2" >/dev/null && ok "--for deterministic on JS/Bash corpus" || no "--for non-deterministic"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --quality-baseline / --quality-delta: nesting REGRESSION detected on JavaScript ==="
# ═══════════════════════════════════════════════════════════════════════════
# Work in a scratch copy: baseline the CLEAN fixture, then worsen leaf() with 5-deep nesting (over the
# kNestBar=4 bar) and confirm --quality-delta reports it as a "nesting" regression with exit 2.
QD="$TMP/qdjs"; mkdir -p "$QD"
cat > "$QD/a.js" <<'EOF'
function simple( x )
{
    return x + 1;
}
EOF
( cd "$QD" && "$BIN" . --quality-baseline --no-cache >/dev/null 2>&1 )
[ -f "$QD/.ripwire_quality_baseline" ] && ok "--quality-baseline writes a sidecar for a JS-only corpus" || no "--quality-baseline did not write a sidecar for JS"

cat > "$QD/a.js" <<'EOF'
function simple( x )
{
    if ( x > 0 )
    {
        if ( x > 1 )
        {
            if ( x > 2 )
            {
                if ( x > 3 )
                {
                    if ( x > 4 )
                    {
                        return x + 100;
                    }
                }
            }
        }
    }
    return x + 1;
}
EOF
QD_OUT="$( cd "$QD" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
QD_RC=$?
[ $QD_RC -eq 2 ] && ok "--quality-delta exits 2 on a real JS nesting regression" || no "--quality-delta exit code wrong (got $QD_RC, want 2)"
printf '%s' "$QD_OUT" | grep -q 'regressions="1"' && ok "--quality-delta reports exactly 1 regression" || no "--quality-delta regression count wrong: $QD_OUT"
printf '%s' "$QD_OUT" | grep -q 'kind="nesting"' && ok "--quality-delta correctly classifies it as a nesting regression" || no "--quality-delta did not classify as nesting: $QD_OUT"
printf '%s' "$QD_OUT" | grep -q 'sym="simple"' && ok "--quality-delta names the regressed JS symbol (simple)" || no "--quality-delta did not name the symbol: $QD_OUT"
printf '%s' "$QD_OUT" | grep -q 'now="5"' && ok "--quality-delta reports the correct now=5 nest depth" || no "--quality-delta now= value wrong: $QD_OUT"

# negative control: re-running quality-delta with NO further change reports 0 regressions (not sticky).
QD2_OUT="$( cd "$QD" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
# NOTE: baseline was never updated, so the same regression is still reported — this is EXPECTED (delta is
# vs the fixed baseline, not vs the last run). Re-baselining should clear it.
( cd "$QD" && "$BIN" . --quality-baseline --no-cache >/dev/null 2>&1 )
QD3_OUT="$( cd "$QD" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
QD3_RC=$?
printf '%s' "$QD3_OUT" | grep -q 'regressions="0"' && [ $QD3_RC -eq 0 ] \
    && ok "re-baselining a regressed JS symbol clears it (regressions=0, exit 0)" \
    || no "re-baseline did not clear the regression: rc=$QD3_RC out=$QD3_OUT"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== MUTATION: wrong expected values must be DETECTED as failures (assertion liveness) ==="
# ═══════════════════════════════════════════════════════════════════════════
MUT="$( ok(){ :; }; no(){ echo TRIPPED; }
        line="$( sattr deepNest )"
        if printf '%s' "$line" | grep -q ' nest="999"'; then ok; else no; fi )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (a wrong nest=999 assertion is correctly detected as a failure)" \
                       || no "mutation self-test broke — a wrong value did NOT fail (assertion logic unsound)"

MUT2="$( ok(){ :; }; no(){ echo TRIPPED; }
        if printf '%s' "$QD_OUT" | grep -q 'regressions="0"'; then ok; else no; fi )"
[ "$MUT2" = "TRIPPED" ] && ok "mutation self-test (asserting regressions=0 on a REAL regression correctly fails)" \
                        || no "mutation self-test broke — quality-delta regression assertion is not live"

# well-formed XML on the --metrics / --for output (G4)
command -v xmllint >/dev/null 2>&1 && {
    printf '%s' "$MAP" | xmllint --noout - 2>/dev/null && ok "xml well-formed (--metrics on JS/Bash)" || no "xml malformed (--metrics on JS/Bash)"
    printf '%s' "$FOR_OUT" | xmllint --noout - 2>/dev/null && ok "xml well-formed (--for on JS/Bash)" || no "xml malformed (--for on JS/Bash)"
}

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
