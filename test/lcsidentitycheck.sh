#!/usr/bin/env bash
# lcsidentitycheck.sh — gate for QD-LCS (src/clones.h cloneLcsLen, the Type-3 clone pass's LCS).
#
# The Type-3 pass keeps a pair when 2·LCS/(|a|+|b|) ≥ kType3MinSimilarity. QD-LCS lets the LCS stop as soon as the
# length cannot reach type3LcsNeed (the early exit). An exit may only drop pairs the threshold drops anyway, and a kept
# pair must get its exact length. This gate proves it twice:
#
#   (F)  fuzz: test/lcsfuzz_harness.cpp, compiled against src/clones.h, checks the LCS on deterministic random token
#        streams (word edges, edited copies on both sides of the threshold, bodies up to the cap) against an independent
#        textbook DP. Premise: it compares pairs, some stop early and some reach need; a vacuous run FAILS.
#   (B)  binary: RIPWIRE_LCS_VERIFY=1 re-runs every LCS the pass ran with the plain DP and prints
#        `lcs-verify pairs= early_exits= mismatches=`. On a fixture with one kept near-clone and one pair the exit drops,
#        mismatches must be 0, and pairs and early_exits must not be (a pass that compared nothing FAILS). The answer is
#        byte-identical with and without the variable, and names the kept pair.
#   (R)  optional, real trees: LCS_REPOS="dir1 dir2" runs (B)'s check over --clones on each (the lane measured envoy,
#        cockroach and vscode this way).
#
# Usage:  bash test/lcsidentitycheck.sh            (BIN=build/ripwire; CXX=c++)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
CXX="${CXX:-c++}"
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "lcsidentitycheck: BIN=$BIN CXX=$CXX"

# ── (F) the fuzz harness ─────────────────────────────────────────────────────────────────────────────────────────────
if ! "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra -I"$ROOT/src/infra" -I"$ROOT/third_party" -I"$ROOT/src" \
        "$ROOT/test/lcsfuzz_harness.cpp" "$ROOT/src/infra/diagnostics.cpp" -o "$WORK/lcsfuzz" 2> "$WORK/cc.log"; then
    no "(F) the fuzz harness failed to compile"; sed 's/^/    /' "$WORK/cc.log"
else
    "$WORK/lcsfuzz" > "$WORK/fuzz.txt"; frc=$?
    sed 's/^/    /' "$WORK/fuzz.txt" | tail -5
    if [ "$frc" = 0 ] && grep -q '^LCSFUZZ .* failures=0$' "$WORK/fuzz.txt"; then
        ok "(F) fuzz: $( grep '^LCSFUZZ' "$WORK/fuzz.txt" | cut -d' ' -f2- )"
    else
        no "(F) fuzz harness rc=$frc"
    fi
fi

# verify_line <dir> <tag> [args...]: run the binary with RIPWIRE_LCS_VERIFY=1 and check its lcs-verify line
verify_line(){
    local dir="$1" tag="$2"; shift 2
    ( cd "$dir" && RIPWIRE_LCS_VERIFY=1 "$BIN" . "$@" > "$WORK/$tag.v.out" 2> "$WORK/$tag.v.err" ); local rc=$?
    local line; line="$( grep '^ripwire: lcs-verify ' "$WORK/$tag.v.err" | tail -1 )"
    local pairs exits mism
    pairs="$( printf '%s' "$line" | sed -n 's/.* pairs=\([0-9]*\).*/\1/p' )"
    exits="$( printf '%s' "$line" | sed -n 's/.* early_exits=\([0-9]*\).*/\1/p' )"
    mism="$( printf '%s' "$line" | sed -n 's/.* mismatches=\([0-9]*\).*/\1/p' )"
    if [ "$rc" != 0 ] || [ -z "$line" ]; then no "($tag) rc=$rc, no lcs-verify line"; return; fi
    if [ "${pairs:-0}" -gt 0 ] && [ "${exits:-0}" -gt 0 ] && [ "$mism" = 0 ]; then
        ok "($tag) pairs=$pairs early_exits=$exits mismatches=0"
    else
        no "($tag) pairs=$pairs early_exits=$exits mismatches=$mism (need pairs>0, early_exits>0, mismatches=0)"
    fi
}

# ── (B) the binary on a fixture: alpha/gamma are a kept near-clone (one inserted statement); alpha/beta and beta/gamma
#    share a 10-statement head and then differ, so they reach the LCS (k-gram Jaccard ≥ 0.40) and stop early ──────────
FX="$WORK/fx"; mkdir -p "$FX"
head_stmts='    x = y + 1;
    m = ( n << 3 ) | 7;
    goto done;
    for ( i = 0 ; i < n ; i++ ) { s += i; }
    val %= 13;
    return_val = f ( g , h );
    ptr -> field = other . field;
    if ( a ) { b(); }
    switch ( k ) { case 1 : z = 2; break; }
    cnt ^= mask;'
tail_a='    if ( a ) { b(); }
    arr [ i ] = arr [ i - 1 ] * 2;
    m = ( n << 3 ) | 7;
    ptr -> field = other . field;
    str = "x";
    x = y + 1;
    return_val = f ( g , h );
    p = q ? r : t;
    do { u--; } while ( u > 0 );
    val %= 13;'
tail_b='    while ( c < 3 ) { c++; }
    m = ( n << 3 ) | 7;
    val %= 13;
    if ( a ) { b(); }
    p = q ? r : t;
    flag = ! flag && ready;
    x = y + 1;
    for ( i = 0 ; i < n ; i++ ) { s += i; }
    ptr -> field = other . field;
    cnt ^= mask;'
{
    printf 'int alpha(int *v) {\n%s\n%s\n    done: return 0;\n}\n\n' "$head_stmts" "$tail_a"
    printf 'int beta(int *v) {\n%s\n%s\n    done: return 1;\n}\n\n' "$head_stmts" "$tail_b"
    printf 'int gamma(int *v) {\n%s\n    total += 1;\n%s\n    done: return 0;\n}\n' "$head_stmts" "$tail_a"
} > "$FX/m.c"
verify_line "$FX" B --clones --no-cache
( cd "$FX" && "$BIN" . --clones --no-cache > "$WORK/B.p.out" 2> "$WORK/B.p.err" ); prc=$?
grep -v '^ripwire: lcs-verify ' "$WORK/B.v.err" > "$WORK/B.v.err2"
if [ "$prc" = 0 ] && cmp -s "$WORK/B.p.out" "$WORK/B.v.out" && cmp -s "$WORK/B.p.err" "$WORK/B.v.err2"; then
    ok "(B) the answer is byte-identical with and without RIPWIRE_LCS_VERIFY (stdout, stderr, rc)"
else
    no "(B) RIPWIRE_LCS_VERIFY changed the answer (rc=$prc)"
fi
if grep -q '<group type="3"[^>]*><f n="alpha"[^>]*/><f n="gamma"' "$WORK/B.p.out" && ! grep -q '<f n="beta"' "$WORK/B.p.out"; then
    ok "(B) the near-clone alpha/gamma is kept and the pairs with beta are dropped"
else
    no "(B) expected the one Type-3 pair alpha/gamma"; sed 's/^/    /' "$WORK/B.p.out" | tail -c 600
fi

# ── (R) optional real trees ─────────────────────────────────────────────────────────────────────────────────────────
for repo in ${LCS_REPOS:-}; do
    verify_line "$repo" "R:$( basename "$repo" )" --clones --no-cache
done

if [ "$fail" = 0 ]; then echo "lcsidentitycheck: PASS"; exit 0; fi
echo "lcsidentitycheck: FAIL"; exit 1
