#!/bin/bash
# calleetextmonocheck — CALLEE-TEXT-MONOTONE: a correct new call edge never LOWERS its caller's lexical rank.
# The lexical ranker (src/lexical.h pass 1) adds each out-edge target's NAME to the caller's BM25 document. It used
# to add those subtokens to the document LENGTH too, so a callee name that does not match the query diluted the
# caller (ha-03: HueLight.async_turn_off fell under two rows when self.bridge.async_request_call bound). The callee
# field now adds term frequency only (a BM25F field with b = 0).
#
# Per language (Python, TypeScript, C++, Rust), one fixture written twice with the SAME caller bodies:
#   unbound: the bridge file defines a sibling name, so the caller's call has no in-tree target (no edge);
#   bound:   the bridge file defines the called name, so the call binds (edge proven by --callees).
# Corpus size and every document length other than the callee field are identical between the two.
#   (L) lowering arm: callee name carries NO query term -> caller A's score is not lower and A stays above twin B
#       (B's body is one statement longer, so A leads B when the call is unbound). Red at d71546803 (A falls under B).
#   (P) positive twin: callee name DOES carry a query term -> A's score strictly rises when the call binds (the
#       unbound bridge name zz_lamp_gadget keeps the term's document frequency equal across the pair).
# Every arm reads the exit code and requires the scored row to be present: a crash, an empty answer or a missing
# row is a FAIL, never a pass.
set -u
BIN="${1:-${RIPWIRE_BIN:-./build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
TMP="$(mktemp -d "${TMPDIR:-/tmp}/calleetextmono.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; FAIL=1; }
mkdir -p "$TMP/xdg"
QUERY="dim the lamp"

# write_fixture DIR LANG CALL DEF: caller A calls CALL; bridge defines DEF (CALL == DEF binds the edge).
write_fixture()
{
    local d="$1" lang="$2" call="$3" def="$4" i
    mkdir -p "$d"
    case "$lang" in
    py)
        printf 'from bridge import %s\n\n\ndef dim_lamp_level(amount):\n    total = amount + 1\n    %s(total)\n    return total\n\n\ndef dim_lamp_brightness(amount):\n    total = amount + 1\n    other = total + 2\n    yy_other_helper(other)\n    return total\n' "$call" "$call" > "$d/lights.py"
        printf 'def %s(value):\n    return value\n' "$def" > "$d/bridge.py"
        for i in 1 2 3 4 5 6 7 8; do printf 'def filler_step_%s(value):\n    return value * %s\n\n\n' "$i" "$i"; done > "$d/filler.py"
        ;;
    ts)
        printf "import { %s } from './bridge';\n\nexport function dim_lamp_level(amount: number): number {\n    const total = amount + 1;\n    %s(total);\n    return total;\n}\n\nexport function dim_lamp_brightness(amount: number): number {\n    const total = amount + 1;\n    const other = total + 2;\n    yy_other_helper(other);\n    return total;\n}\n" "$call" "$call" > "$d/lights.ts"
        printf 'export function %s(value: number): number {\n    return value;\n}\n' "$def" > "$d/bridge.ts"
        for i in 1 2 3 4 5 6 7 8; do printf 'export function filler_step_%s(value: number): number {\n    return value * %s;\n}\n\n' "$i" "$i"; done > "$d/filler.ts"
        ;;
    cpp)
        printf '#include "bridge.h"\n\nint dim_lamp_level(int amount)\n{\n    int total = amount + 1;\n    %s(total);\n    return total;\n}\n\nint dim_lamp_brightness(int amount)\n{\n    int total = amount + 1;\n    int other = total + 2;\n    yy_other_helper(other);\n    return total;\n}\n' "$call" > "$d/lights.cpp"
        printf '#pragma once\ninline int %s(int value)\n{\n    return value;\n}\n' "$def" > "$d/bridge.h"
        for i in 1 2 3 4 5 6 7 8; do printf 'int filler_step_%s(int value)\n{\n    return value * %s;\n}\n\n' "$i" "$i"; done > "$d/filler.cpp"
        ;;
    rs)
        mkdir -p "$d/src"
        printf 'mod bridge;\nmod filler;\nuse crate::bridge::%s;\n\npub fn dim_lamp_level(amount: i32) -> i32 {\n    let total = amount + 1;\n    %s(total);\n    total\n}\n\npub fn dim_lamp_brightness(amount: i32) -> i32 {\n    let total = amount + 1;\n    let other = total + 2;\n    yy_other_helper(other);\n    total\n}\n' "$call" "$call" > "$d/src/lib.rs"
        printf 'pub fn %s(value: i32) -> i32 {\n    value\n}\n' "$def" > "$d/src/bridge.rs"
        for i in 1 2 3 4 5 6 7 8; do printf 'pub fn filler_step_%s(value: i32) -> i32 {\n    value * %s\n}\n\n' "$i" "$i"; done > "$d/src/filler.rs"
        ;;
    esac
}

run(){ ( cd "$1" || exit 9; env -u TMPDIR XDG_CACHE_HOME="$TMP/xdg" "$BIN" "$1" --no-cache "${@:2}" ); }

# cand FILE NAME -> "rank score" of NAME's <cand> row, empty when absent
cand()
{
    tr '<' '\n' < "$1" | grep -E "^cand r=\"[0-9]+\" s=\"[^\"]*\" n=\"$2\" " | head -1 \
        | sed -E 's/^cand r="([0-9]+)" s="([^"]*)".*/\1 \2/'
}

# score_of DIR -> writes DIR.cand, returns rc of the candidates run
score_run(){ run "$1" --for="$QUERY" --format=candidates > "$1.cand" 2> "$1.err"; }

# bound_edge DIR CALLEE -> 0 when --callees=dim_lamp_level lists CALLEE as a bound target
bound_edge()
{
    run "$1" --callees=dim_lamp_level > "$1.callees" 2> "$1.callees.err" || return 2
    grep -q "n=\"$2\"" "$1.callees"
}

# fgt A B -> 0 when float A > B; fge A B -> 0 when A >= B - 1e-6 (the printed score is rounded to 6 significant digits)
fgt(){ awk -v a="$1" -v b="$2" 'BEGIN { exit !( a + 0 > b + 0 ) }'; }
fge(){ awk -v a="$1" -v b="$2" 'BEGIN { exit !( a + 0 >= b - 1e-6 * ( b < 0 ? -b : b ) ) }'; }

for lang in py ts cpp rs; do
    echo "== $lang"
    # (L) lowering arm: callee name zz_quux_frobnicate_widget carries no query term
    U="$TMP/$lang-L-unbound"; Bd="$TMP/$lang-L-bound"
    write_fixture "$U"  "$lang" zz_quux_frobnicate_widget zz_quux_frobnicate_gadget
    write_fixture "$Bd" "$lang" zz_quux_frobnicate_widget zz_quux_frobnicate_widget
    score_run "$U";  rcU=$?
    score_run "$Bd"; rcB=$?
    if [ "$rcU" -ne 0 ] || [ "$rcB" -ne 0 ]; then
        no "$lang L: candidates run failed (rc unbound=$rcU bound=$rcB)"; continue
    fi
    bound_edge "$Bd" zz_quux_frobnicate_widget; e1=$?
    bound_edge "$U"  zz_quux_frobnicate_widget; e0=$?
    if [ "$e1" -eq 0 ] && [ "$e0" -eq 1 ]; then ok "$lang L: the call binds only in the bound fixture (--callees)"
    else no "$lang L: edge precondition (bound rc=$e1 want 0, unbound rc=$e0 want 1)"; fi
    read -r rAU sAU <<< "$(cand "$U.cand"  dim_lamp_level)"
    read -r rBU sBU <<< "$(cand "$U.cand"  dim_lamp_brightness)"
    read -r rAB sAB <<< "$(cand "$Bd.cand" dim_lamp_level)"
    read -r rBB sBB <<< "$(cand "$Bd.cand" dim_lamp_brightness)"
    if [ -z "${sAU:-}" ] || [ -z "${sBU:-}" ] || [ -z "${sAB:-}" ] || [ -z "${sBB:-}" ]; then
        no "$lang L: a scored row is missing (A=$sAU/$sAB B=$sBU/$sBB)"; continue
    fi
    if [ "$rAU" -lt "$rBU" ]; then ok "$lang L: control: A ranks above twin B with the call unbound (r $rAU < $rBU)"
    else no "$lang L: control: A should lead B unbound (r A=$rAU B=$rBU)"; fi
    if fge "$sAB" "$sAU"; then ok "$lang L: binding a non-matching callee does not lower A ($sAU -> $sAB)"
    else no "$lang L: binding a non-matching callee LOWERED A ($sAU -> $sAB)"; fi
    if [ "$rAB" -lt "$rBB" ]; then ok "$lang L: A still ranks above B with the call bound (r $rAB < $rBB)"
    else no "$lang L: A fell under B when its call bound (r A=$rAB B=$rBB)"; fi

    # (P) positive twin: callee name zz_lamp_widget carries the query term "lamp"
    U="$TMP/$lang-P-unbound"; Bd="$TMP/$lang-P-bound"
    write_fixture "$U"  "$lang" zz_lamp_widget zz_lamp_gadget
    write_fixture "$Bd" "$lang" zz_lamp_widget zz_lamp_widget
    score_run "$U";  rcU=$?
    score_run "$Bd"; rcB=$?
    if [ "$rcU" -ne 0 ] || [ "$rcB" -ne 0 ]; then
        no "$lang P: candidates run failed (rc unbound=$rcU bound=$rcB)"; continue
    fi
    bound_edge "$Bd" zz_lamp_widget; e1=$?
    if [ "$e1" -eq 0 ]; then ok "$lang P: the matching call binds (--callees)"; else no "$lang P: edge precondition (rc=$e1)"; fi
    read -r rAU sAU <<< "$(cand "$U.cand"  dim_lamp_level)"
    read -r rAB sAB <<< "$(cand "$Bd.cand" dim_lamp_level)"
    if [ -z "${sAU:-}" ] || [ -z "${sAB:-}" ]; then no "$lang P: a scored row is missing (A=$sAU/$sAB)"; continue; fi
    if fgt "$sAB" "$sAU"; then ok "$lang P: binding a query-matching callee raises A ($sAU -> $sAB)"
    else no "$lang P: binding a query-matching callee did not raise A ($sAU -> $sAB)"; fi
    if [ "$rAB" -le "$rAU" ]; then ok "$lang P: A's rank does not fall (r $rAU -> $rAB)"
    else no "$lang P: A's rank fell (r $rAU -> $rAB)"; fi
done

if [ "$FAIL" -ne 0 ]; then echo "calleetextmonocheck: FAIL"; exit 1; fi
echo "calleetextmonocheck: PASS"
