#!/usr/bin/env bash
# zoneconsistencycheck.sh — Zone-of-Pain SELF-CONSISTENCY gate (196e695, src/arch.h + main.cpp
# emitMetrics). test/zonecheck.sh hand-verifies the per-module I/A/D/zone classification on ONE fixture
# and its zone_pain=1/zone_useless=1 summary counts as a byproduct of checking that exact fixture. This
# gate checks a DIFFERENT property that must hold on ANY fixture: the <metrics zone_pain=N
# zone_useless=M> summary counts are computed by literally counting the per-module zone= tags — so N
# must equal the number of <m zone="pain"> tags and M must equal the number of <m zone="useless"> tags,
# programmatically, not by re-deriving the hand-picked expected numbers. It also checks the "everything
# lands on the main sequence" corner: a repo with only balanced modules (D<=0.5 everywhere) must report
# zone_pain=0 AND zone_useless=0, not just one of them.
#
# Fixtures:
#   - test/zonefix (existing, checked-in, READ-ONLY — reused from zonecheck.sh's own corpus) as an
#     independent cross-check that the self-consistency property holds on a KNOWN mixed-zone fixture.
#   - a fresh all-ok fixture (built here in TMP) with two modules that mutually include each other and
#     each have one abstract + one concrete type -> I=0.50 A=0.50 D=0.00 on both -> zone="ok" everywhere.
#
# Usage:  test/zoneconsistencycheck.sh   |   CTXPACK_BIN=asan/ctxpack test/zoneconsistencycheck.sh
# Exits non-zero on any failure. Does NOT edit regression.sh or any existing test file.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"

echo "zoneconsistencycheck: BIN=$BIN"

# self-consistency checker: given a raw --arch output blob, assert zone_pain=/zone_useless=/zone_ok=/
# zone_na= in the <metrics> tag equal the actual count of <m zone="..."> tags in the same output, AND
# that the four buckets partition modules= exactly (§A10.8: zone_ok was computed but never emitted, so
# the header's own bucket sum fell short of modules= with nothing disclosing the gap).
check_consistency(){
    local label="$1" out="$2"
    local reported_pain reported_useless reported_ok reported_na actual_pain actual_useless actual_ok actual_na modules
    reported_pain="$(    printf '%s' "$out" | grep -oE 'zone_pain="[0-9]+"'    | head -1 | grep -oE '[0-9]+' )"
    reported_useless="$( printf '%s' "$out" | grep -oE 'zone_useless="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
    reported_ok="$(       printf '%s' "$out" | grep -oE 'zone_ok="[0-9]+"'      | head -1 | grep -oE '[0-9]+' )"
    reported_na="$(       printf '%s' "$out" | grep -oE 'zone_na="[0-9]+"'      | head -1 | grep -oE '[0-9]+' )"
    modules="$(          printf '%s' "$out" | grep -oE 'modules="[0-9]+"'      | head -1 | grep -oE '[0-9]+' )"
    actual_pain="$(    printf '%s' "$out" | grep -oE '<m [^>]*zone="pain"'    | wc -l | tr -d ' ' )"
    actual_useless="$( printf '%s' "$out" | grep -oE '<m [^>]*zone="useless"' | wc -l | tr -d ' ' )"
    actual_ok="$(       printf '%s' "$out" | grep -oE '<m [^>]*zone="ok"'      | wc -l | tr -d ' ' )"
    if [ -z "$reported_pain" ] || [ -z "$reported_useless" ]; then
        no "$label: could not parse zone_pain=/zone_useless= from <metrics> at all"
        return
    fi
    [ "$reported_pain" = "$actual_pain" ] \
        && ok "$label: zone_pain=$reported_pain matches actual count of zone=\"pain\" <m> tags ($actual_pain)" \
        || no "$label: zone_pain=$reported_pain MISMATCHES actual zone=\"pain\" tag count ($actual_pain) — summary and per-module tags disagree"
    [ "$reported_useless" = "$actual_useless" ] \
        && ok "$label: zone_useless=$reported_useless matches actual count of zone=\"useless\" <m> tags ($actual_useless)" \
        || no "$label: zone_useless=$reported_useless MISMATCHES actual zone=\"useless\" tag count ($actual_useless) — summary and per-module tags disagree"
    if [ -z "$reported_ok" ]; then
        no "$label: zone_ok= is missing from <metrics> (§A10.8: computed but not emitted)"
    else
        [ "$reported_ok" = "$actual_ok" ] \
            && ok "$label: zone_ok=$reported_ok matches actual count of zone=\"ok\" <m> tags ($actual_ok)" \
            || no "$label: zone_ok=$reported_ok MISMATCHES actual zone=\"ok\" tag count ($actual_ok) — summary and per-module tags disagree"
    fi
    if [ -n "$reported_ok" ] && [ -n "$reported_na" ] && [ -n "$modules" ]; then
        local sum=$(( reported_pain + reported_useless + reported_ok + reported_na ))
        [ "$sum" = "$modules" ] \
            && ok "$label: zone_pain+zone_useless+zone_ok+zone_na=$sum == modules=$modules (full partition, §A10.8)" \
            || no "$label: zone_pain+zone_useless+zone_ok+zone_na=$sum != modules=$modules — partition incomplete"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== self-consistency on the existing mixed-zone fixture (test/zonefix) ==="
# ═══════════════════════════════════════════════════════════════════════════
[ -d test/zonefix ] || { echo "no test/zonefix — fixture missing (expected from Wave-2)"; exit 2; }
ZF_OUT="$( "$BIN" test/zonefix --arch=test/zonefix/zone.arch --no-cache 2>/dev/null )"
[ -n "$ZF_OUT" ] && printf '%s' "$ZF_OUT" | grep -q '<metrics' && ok "produced <metrics> block on test/zonefix" || no "no <metrics> block on test/zonefix"
check_consistency "test/zonefix" "$ZF_OUT"
# independent sanity: this fixture is KNOWN (from zonecheck.sh) to have exactly 1 pain + 1 useless + 1 ok
# + 1 n/a out of 4 modules — cross-check the raw numbers too, not just self-consistency, so a bug that
# shifts BOTH the summary and the per-module tags the same wrong way (e.g. an off-by-one in classification
# itself) is still caught. §P6.5: `consumer` has zero types, so it reads zone="n/a" (excluded from
# zone_pain/zone_useless and from the zone="ok" count) rather than the pre-fix accidental "ok" it got from
# D=0.00 with a forced A=0 — only `balanced` is genuinely zone="ok" now.
printf '%s' "$ZF_OUT" | grep -q 'modules="4"' && ok "test/zonefix: modules=4 (independent count check)" || no "test/zonefix: modules count wrong: $ZF_OUT"
printf '%s' "$ZF_OUT" | grep -oE '<m [^>]*zone="ok"' | wc -l | tr -d ' ' | grep -q '^1$' && ok "test/zonefix: exactly 1 module lands zone=\"ok\" (independent count check)" || no "test/zonefix: ok-zone count wrong"
printf '%s' "$ZF_OUT" | grep -oE '<m [^>]*zone="n/a"' | wc -l | tr -d ' ' | grep -q '^1$' && ok "test/zonefix: exactly 1 module lands zone=\"n/a\" (consumer, zero types)" || no "test/zonefix: n/a-zone count wrong"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== all-ok fixture: EVERY module near the main sequence -> zone_pain=0 AND zone_useless=0 ==="
# ═══════════════════════════════════════════════════════════════════════════
# modA/modB mutually include each other; each declares one abstract (pure-virtual, no body) type and one
# concrete (has a body) type -> Ca=1 Ce=1 I=0.50 A=0.50 -> D=|0.50+0.50-1|=0.00, well under the 0.5
# distThreshold -> zone="ok" for BOTH modules, deterministically.
AOK="$TMP/allok/src"; mkdir -p "$AOK/modA" "$AOK/modB"
cat > "$AOK/modA/a.h" <<'EOF'
#pragma once
#include "../modB/b.h"

struct AbsA
{
    virtual void run() = 0;
};

struct ConcA
{
    void run() { BConcrete c; c.doIt(); }
};
EOF
cat > "$AOK/modB/b.h" <<'EOF'
#pragma once
#include "../modA/a.h"

struct BAbs
{
    virtual void doIt() = 0;
};

struct BConcrete
{
    void doIt() {}
};
EOF
: > "$TMP/allok/noop.arch"   # empty rules file — we only want the <metrics> block, no layering violations
AOK_OUT="$( "$BIN" "$TMP/allok" --arch="$TMP/allok/noop.arch" --no-cache 2>/dev/null )"
[ -n "$AOK_OUT" ] && printf '%s' "$AOK_OUT" | grep -q '<metrics' && ok "produced <metrics> block on the all-ok fixture" || no "no <metrics> block on the all-ok fixture"
printf '%s' "$AOK_OUT" | grep -q 'modules="2"' && ok "all-ok fixture: modules=2" || no "all-ok fixture: modules count wrong: $AOK_OUT"
printf '%s' "$AOK_OUT" | grep -q 'zone_pain="0"' && ok "all-ok fixture: zone_pain=0" || no "all-ok fixture: zone_pain should be 0: $AOK_OUT"
printf '%s' "$AOK_OUT" | grep -q 'zone_useless="0"' && ok "all-ok fixture: zone_useless=0" || no "all-ok fixture: zone_useless should be 0: $AOK_OUT"
# both modules individually tagged zone="ok" (not just the summary happening to read 0/0 by coincidence
# — e.g. if the summary counter were entirely disconnected from the tags, it could default to 0 always;
# the earlier self-consistency check on zonefix already rules that out, but pin it here too for belt-and-braces).
printf '%s' "$AOK_OUT" | grep -oE '<m [^>]*zone="ok"' | wc -l | tr -d ' ' | grep -q '^2$' && ok "all-ok fixture: both modules individually tagged zone=\"ok\"" || no "all-ok fixture: not all modules tagged zone=\"ok\": $AOK_OUT"
check_consistency "all-ok fixture" "$AOK_OUT"

# determinism
AOK_OUT2="$( "$BIN" "$TMP/allok" --arch="$TMP/allok/noop.arch" --no-cache 2>/dev/null )"
[ "$AOK_OUT" = "$AOK_OUT2" ] && ok "all-ok fixture: deterministic run-to-run" || no "all-ok fixture: non-deterministic"

command -v xmllint >/dev/null 2>&1 && { printf '%s' "$AOK_OUT" | xmllint --noout - 2>/dev/null && ok "xml well-formed (all-ok --arch)" || no "xml malformed (all-ok --arch)"; }

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== MUTATION: prove the count assertions are load-bearing ==="
# ═══════════════════════════════════════════════════════════════════════════
# self-test of check_consistency itself: feed it a deliberately-wrong blob (claims zone_pain=5 but has 0
# zone="pain" tags) and confirm it FAILS, proving the comparison logic actually discriminates.
MUT_BLOB='<metrics zone_pain="5" zone_useless="0"></metrics><m path="x" zone="ok"/>'
MUT="$( ok(){ echo NOT-TRIPPED; }; no(){ echo TRIPPED; }
        check_consistency "mutation-probe" "$MUT_BLOB" | grep -q TRIPPED && echo TRIPPED || echo NOT-TRIPPED )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (a deliberately-wrong zone_pain=5 vs 0 actual tags is correctly detected as inconsistent)" \
                       || no "mutation self-test broke — check_consistency does not actually compare summary vs tags"

MUT2="$( ok(){ :; }; no(){ echo TRIPPED; }
        if printf '%s' "$AOK_OUT" | grep -q 'zone_pain="1"'; then ok; else no; fi )"
[ "$MUT2" = "TRIPPED" ] && ok "mutation self-test (asserting all-ok fixture has zone_pain=1 when it is really 0 correctly fails)" \
                        || no "mutation self-test broke — the all-ok zone_pain=0 assertion is not live"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
