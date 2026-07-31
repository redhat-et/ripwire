#!/usr/bin/env bash
# chacheck.sh — gate for B2.1 CHA-lite (class-hierarchy devirtualization) + B2.2 arity filtering, the two
# SOUND call-graph precision prunes applied to a still-ambiguous receiver-typed / argument-counted call
# BEFORE the locality tie-break (graph.h::buildGraph). Both only ever DROP a candidate the true target is
# provably not among, and both DEGRADE (leave the tier untouched) rather than empty it.
#
# The chafix corpus:
#   cha.cpp   — Animal (bodied speak), Dog+Cat implementors (neither overrides speak), Robot (UNRELATED,
#               its own speak). g() calls `Dog d; d.speak()` → CHA-lite narrows to the Dog cone {Dog,Animal},
#               dropping Robot::speak → resolves to Animal::speak ALONE. h() calls the same through a
#               PARAMETER (no var→type binding) → receiver type unknown → CHA can't fire → stays ambiguous.
#   arity.cpp — emit(int) / emit(int,int,int) / emit(const char*,...). caller() does emit(1,2,3): B2.2 drops
#               the arity-1 overload (fixed arity 1 != 3), keeps the arity-3 overload, and KEEPS the variadic
#               overload (variadic is never a fixed arity → never provably wrong).
#
# Usage:  CTXPACK_BIN=build/ctxpack bash test/chacheck.sh   (or asan/ctxpack)
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
FIX="$ROOT/test/chafix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/chafix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "chacheck: BIN=$BIN  CORPUS=test/chafix"

# derive the def line numbers from the sources so the gate survives fixture edits.
ROBOT_LINE="$(  grep -n 'void speak() { power'   "$FIX/cha.cpp"   | cut -d: -f1 )"   # Robot::speak (unrelated)
ANIMAL_LINE="$( grep -n 'void Animal::speak()'   "$FIX/cha.cpp"   | cut -d: -f1 )"   # Animal::speak (inherited def)
EMIT1_LINE="$(  grep -n 'void emit( int a ) {'   "$FIX/arity.cpp" | cut -d: -f1 )"   # emit(int) — arity 1
EMIT3_LINE="$(  grep -n 'void emit( int a, int b, int c )' "$FIX/arity.cpp" | cut -d: -f1 )"   # arity 3
EMITV_LINE="$(  grep -n 'void emit( const char\* fmt'      "$FIX/arity.cpp" | cut -d: -f1 )"   # variadic

# distinct speak/emit target lines a caller resolves to (via --callees).
targets(){ "$BIN" "$FIX" --callees="$1" --no-cache 2>/dev/null | tr '>' '\n' | grep -oE 'cha(fix)?/[a-z]+\.cpp:[0-9]+' | grep -oE '[0-9]+$' | sort -un; }

# ── 1) CHA positive: g() resolves d.speak() to EXACTLY the Animal (inherited) def — Robot::speak excluded. ──
gT="$( targets g )"
gN="$( printf '%s\n' "$gT" | grep -c . )"
if [ "$gN" = "1" ] && printf '%s\n' "$gT" | grep -qx "$ANIMAL_LINE" && ! printf '%s\n' "$gT" | grep -qx "$ROBOT_LINE"; then
    ok "CHA-lite positive: g() → Animal::speak ONLY (Robot::speak excluded, $gN target)"
else
    no "CHA-lite positive: g() targets = [$(echo $gT)] (want ONLY line $ANIMAL_LINE=Animal; NOT $ROBOT_LINE=Robot)"
fi

# ── 2) CHA control: h() (receiver is a parameter → unknown type) stays AMBIGUOUS — BOTH speak defs survive. ──
hT="$( targets h )"
hN="$( printf '%s\n' "$hT" | grep -c . )"
if [ "$hN" = "2" ] && printf '%s\n' "$hT" | grep -qx "$ANIMAL_LINE" && printf '%s\n' "$hT" | grep -qx "$ROBOT_LINE"; then
    ok "CHA-lite control: h() stays AMBIGUOUS (both Animal::speak + Robot::speak — unknown receiver keeps current behavior)"
else
    no "CHA-lite control: h() targets = [$(echo $hT)] (want BOTH $ANIMAL_LINE + $ROBOT_LINE — CHA must NOT fire on a param receiver)"
fi

# ── 3) amb honesty: g is resolved (no amb marker), h stays flagged (amb=). ──
if "$BIN" "$FIX" --no-cache --top-k=100000 2>/dev/null | grep -oE 'n="g"[^>]*' | grep -q 'amb='; then
    no "g() still carries amb= (CHA-lite did not resolve it)"; else ok "g() carries NO amb= (resolved by CHA-lite)"; fi
if "$BIN" "$FIX" --no-cache --top-k=100000 2>/dev/null | grep -oE 'n="h"[^>]*' | grep -q 'amb='; then
    ok "h() carries amb= (honest ambiguity preserved on the unknown-receiver control)"
else no "h() lost its amb= (the control should stay ambiguous)"; fi

# ── 4) arity: caller() emit(1,2,3) EXCLUDES the arity-1 overload, KEEPS arity-3 AND the variadic overload. ──
cT="$( targets caller )"
cN="$( printf '%s\n' "$cT" | grep -c . )"
if printf '%s\n' "$cT" | grep -qx "$EMIT1_LINE"; then
    no "arity: caller() still resolves to emit(int) at line $EMIT1_LINE (arity-1 NOT excluded on a 3-arg call)"
else
    ok "arity: emit(int) (arity 1) EXCLUDED from the 3-arg call site"
fi
if printf '%s\n' "$cT" | grep -qx "$EMIT3_LINE"; then ok "arity: emit(int,int,int) (arity 3) KEPT (matches the 3-arg call)"; \
    else no "arity: emit(int,int,int) at line $EMIT3_LINE was dropped (a true target removed — FALSE NEGATIVE)"; fi
if printf '%s\n' "$cT" | grep -qx "$EMITV_LINE"; then ok "arity: emit(const char*,...) (variadic) KEPT (variadic is never provably-wrong)"; \
    else no "arity: variadic emit at line $EMITV_LINE was dropped (variadic MUST NOT be arity-filtered — FALSE NEGATIVE)"; fi

# ── 5) determinism — the two prunes must be byte-stable run-to-run. ──
"$BIN" "$FIX" --no-cache >"$TMP/m1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/m2" 2>/dev/null
diff -q "$TMP/m1" "$TMP/m2" >/dev/null && ok "deterministic (chafix map byte-identical across two runs)" \
    || { no "non-deterministic chafix map"; diff "$TMP/m1" "$TMP/m2" | head -6; }

# ── 6) cache transparency — the arityExact / argCount facts survive the incremental cache: warm == cold. ──
rm -f "$TMP/cc"
"$BIN" "$FIX" --cache="$TMP/cc" >/dev/null 2>&1
"$BIN" "$FIX" --cache="$TMP/cc" >"$TMP/warm" 2>/dev/null
"$BIN" "$FIX" --no-cache        >"$TMP/cold" 2>/dev/null
diff -q "$TMP/warm" "$TMP/cold" >/dev/null && ok "cache-transparent (arity/CHA facts round-trip: warm == cold)" \
    || { no "cache changes output (warm != cold)"; diff "$TMP/cold" "$TMP/warm" | head -6; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
