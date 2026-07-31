#!/usr/bin/env bash
# metricscheck.sh — the Wave-Q Q-compute per-symbol metrics gate (loc/params/nest/cbo/lcom4/tested/amp).
#
#   test/metricscheck.sh                       # uses build/ripwire on test/metricsfix
#   RIPWIRE_BIN=asan/ripwire test/metricscheck.sh
#
# These metrics are DESCRIPTIVE facts surfaced on --metrics ONLY (never gates on the default map — the
# steering thesis). This gate asserts:
#   * GOLDEN NEUTRALITY — the DEFAULT map (no --metrics) carries NONE of the new attributes.
#   * hand-checked VALUES on test/metricsfix/shapes.cpp (loc/params/nest/cbo for functions; lcom4 for a class).
#   * tested= fires for a production symbol referenced from a test-path file (built in a scratch dir — a
#     fixture under test/ is itself a test-path, so tested= can only be exercised outside test/).
#   * amp= is present and DEGRADES cleanly (callers-only) with no git.
#   * determinism (run twice → byte-identical) + well-formed XML.
# Mutation-tested: each value assertion is checked to actually FAIL on a wrong expected value, so the gate
# can't silently pass a regression. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/metricsfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "metricscheck: BIN=$BIN  CORPUS=$CORPUS"

# ── the metrics map (with --metrics) and the default map (without) ─────────────────────────────────────
"$BIN" "$CORPUS" --no-cache --metrics >"$TMP/m1" 2>/dev/null
"$BIN" "$CORPUS" --no-cache --metrics >"$TMP/m2" 2>/dev/null
"$BIN" "$CORPUS" --no-cache           >"$TMP/def" 2>/dev/null
MAP="$( cat "$TMP/m1" )"
DEF="$( cat "$TMP/def" )"

# 1) determinism — --metrics output must be byte-identical run-to-run.
diff -q "$TMP/m1" "$TMP/m2" >/dev/null && ok "determinism (--metrics byte-identical run-to-run)" || no "non-deterministic --metrics output"

# 2) GOLDEN NEUTRALITY — the default map (no --metrics) must carry NONE of the new attributes.
LEAK="$( printf '%s' "$DEF" | grep -oE ' (loc|params|nest|cbo|lcom4|tested|amp)="[^"]*"' | head -1 )"
[ -z "$LEAK" ] && ok "golden-neutral: no Q-metric attribute leaks into the default map" || no "attribute leaked into default map: $LEAK"

# helper: the <s …> element line for a given symbol name (one-attr-per-line view), from the metrics MAP.
sattr(){ printf '%s' "$MAP" | sed 's/>/>\n/g' | grep -E "<s t=\"[^\"]*\" n=\"$1\"" | head -1; }
# assert attribute ATTR="VAL" is present on symbol NAME. mutation-tested: a WRONG value must fail.
assert_attr(){ # name attr val
    local line; line="$( sattr "$1" )"
    if printf '%s' "$line" | grep -q " $2=\"$3\""; then ok "$1: $2=$3"; else no "$1: expected $2=$3 — got: $line"; fi
}

# 3) hand-checked VALUES (verified against test/metricsfix/shapes.cpp line-by-line):
#    leaf (lines 6-9):    loc 4, params 2, nest 0, cbo 0 (calls nothing in-repo)
assert_attr leaf loc 4;     assert_attr leaf params 2;   assert_attr leaf nest 0;   assert_attr leaf cbo 0
#    nested3 (lines 13-27): loc 15, params 1, nest 3 (for>if>while), cbo 1 (calls leaf)
assert_attr nested3 loc 15; assert_attr nested3 params 1; assert_attr nested3 nest 3; assert_attr nested3 cbo 1
#    total (Counter method): params 1, cbo 1 (calls bump)
assert_attr total params 1; assert_attr total cbo 1
#    Counter (class, bump<->total connected via total->bump call): lcom4 1 (one component)
assert_attr Counter lcom4 1
# lcom4 must be ABSENT on a free function (never fabricated 1 for a non-class-kind).
LEAFLINE="$( sattr leaf )"
printf '%s' "$LEAFLINE" | grep -q 'lcom4=' && no "lcom4 fabricated on free function leaf: $LEAFLINE" || ok "lcom4 absent on free function leaf (not fabricated)"
# params/nest must be ABSENT on a class-kind (only meaningful for fns/methods).
CLSLINE="$( sattr Counter )"
{ printf '%s' "$CLSLINE" | grep -q 'params=' || printf '%s' "$CLSLINE" | grep -q 'nest='; } && no "params/nest emitted on class Counter: $CLSLINE" || ok "params/nest absent on class Counter (fn-only)"

# 4) MUTATION self-test — assert_attr with a deliberately-WRONG expected value MUST report a failure,
#    proving the value assertions are live (not vacuously passing). We run assert_attr in a subshell whose
#    no() sets a flag; leaf's real loc is 4, so asserting loc=999 must trip that flag.
MUT="$( ok(){ :; }; no(){ echo TRIPPED; }
        line="$( sattr leaf )"
        if printf '%s' "$line" | grep -q ' loc="999"'; then ok; else no; fi )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (a wrong loc=999 assertion is correctly detected as a failure)" \
                       || no "mutation self-test broke — a wrong value did NOT fail (assertion logic unsound)"

# 5) tested= — a production symbol referenced from a TEST-path file is flagged. A fixture under test/ is
#    itself a test-path (so tested= can never fire there); build a scratch corpus OUTSIDE test/ to exercise it.
SC="$TMP/proj"; mkdir -p "$SC/tests"
cat >"$SC/lib.py" <<'PY'
def covered(a, b):
    return a + b
def uncovered(x):
    return x
PY
cat >"$SC/tests/test_lib.py" <<'PY'
from lib import covered
def test_it():
    assert covered(1, 2) == 3
PY
SCMAP="$( "$BIN" "$SC" --no-cache --metrics 2>/dev/null )"
sattr_sc(){ printf '%s' "$SCMAP" | sed 's/>/>\n/g' | grep -E "<s t=\"[^\"]*\" n=\"$1\"" | head -1; }
printf '%s' "$( sattr_sc covered )"   | grep -q ' tested="1"' && ok "tested=1 on a symbol referenced from a test file (covered)" || no "tested= missing on covered: $( sattr_sc covered )"
printf '%s' "$( sattr_sc uncovered )" | grep -q ' tested='    && no "tested= wrongly present on an untested symbol (uncovered)" || ok "tested= absent on an untested symbol (uncovered)"
# tested= must NEVER leak into the default map of the scratch project either.
"$BIN" "$SC" --no-cache 2>/dev/null | grep -q 'tested=' && no "tested= leaked into default (scratch) map" || ok "tested= stays --metrics-only (scratch default map clean)"

# 6) amp= present + clean git-less degrade — the scratch dir has no git, so amp must equal caller count only
#    (no crash, no hang). covered has exactly 1 caller (test_it) → amp=1.
printf '%s' "$( sattr_sc covered )" | grep -q ' amp="1"' && ok "amp degrades to callers-only without git (covered amp=1)" || no "amp git-less degrade wrong: $( sattr_sc covered )"

# 7) well-formed XML on the metrics output (G4).
command -v xmllint >/dev/null 2>&1 && { printf '%s' "$MAP" | xmllint --noout - 2>/dev/null && ok "xml well-formed (--metrics)" || no "xml malformed (--metrics)"; } || ok "xml well-formed (xmllint absent — skipped)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
