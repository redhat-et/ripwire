#!/usr/bin/env bash
# chacheck.sh — gate for B2.1 CHA-lite (class-hierarchy devirtualization) + B2.2 arity filtering, the two
# SOUND call-graph precision prunes applied to a still-ambiguous receiver-typed / argument-counted call
# BEFORE the locality tie-break (graph.h::buildGraph). Both only ever DROP a candidate the true target is
# provably not among, and both DEGRADE (leave the tier untouched) rather than empty it.
#
# The chafix corpus:
#   cha.cpp   — Animal (bodied speak), Dog+Cat implementors (neither overrides speak), Robot (UNRELATED,
#               its own speak). g() calls `Dog d; d.speak()` → CHA-lite narrows to the Dog cone {Dog,Animal},
#               dropping Robot::speak → resolves to Animal::speak ALONE. h() calls the same through an
#               untyped `auto` local (no var→type binding) → receiver type unknown → CHA can't fire → stays ambiguous.
#   arity.cpp — emit(int) / emit(int,int,int) / emit(const char*,...). caller() does emit(1,2,3): B2.2 drops
#               the arity-1 overload (fixed arity 1 != 3), keeps the arity-3 overload, and KEEPS the variadic
#               overload (variadic is never a fixed arity → never provably wrong).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/chacheck.sh   (or asan/ripwire)
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/chafix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/chafix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "chacheck: BIN=$BIN  CORPUS=test/chafix"

# derive the def line numbers from the sources so the gate survives fixture edits.
ROBOT_LINE="$(  grep -n 'void speak() { power'   "$FIX/cha.cpp"   | cut -d: -f1 )"   # Robot::speak (unrelated)
ANIMAL_LINE="$( grep -n 'void Animal::speak()'   "$FIX/cha.cpp"   | cut -d: -f1 )"   # Animal::speak (inherited def)
EMIT1_LINE="$(  grep -n 'void emit( int a ) {'   "$FIX/arity.cpp" | cut -d: -f1 )"   # emit(int) — arity 1
EMIT3_LINE="$(  grep -n 'void emit( int a, int b, int c )' "$FIX/arity.cpp" | cut -d: -f1 )"   # arity 3
EMITV_LINE="$(  grep -n 'void emit( const char\* fmt'      "$FIX/arity.cpp" | cut -d: -f1 )"   # variadic

# distinct speak/emit target lines a caller resolves to (via --callees). R-E (2026-08-17 harvest:
# root-relative paths for ALL verbs) — p= is now relative to $FIX itself, so "chafix/" (or "cha/") never
# appears in the path at all; match the bare "<name>.cpp:<line>" shape directly.
targets(){ "$BIN" "$FIX" --callees="$1" --no-cache 2>/dev/null | tr '>' '\n' | grep -oE '[a-z]+\.cpp:[0-9]+' | grep -oE '[0-9]+$' | sort -un; }

# ── 1) CHA positive: g() resolves d.speak() to EXACTLY the Animal (inherited) def — Robot::speak excluded. ──
gT="$( targets g )"
gN="$( printf '%s\n' "$gT" | grep -c . )"
if [ "$gN" = "1" ] && printf '%s\n' "$gT" | grep -qx "$ANIMAL_LINE" && ! printf '%s\n' "$gT" | grep -qx "$ROBOT_LINE"; then
    ok "CHA-lite positive: g() → Animal::speak ONLY (Robot::speak excluded, $gN target)"
else
    no "CHA-lite positive: g() targets = [$(echo $gT)] (want ONLY line $ANIMAL_LINE=Animal; NOT $ROBOT_LINE=Robot)"
fi

# ── 2) CHA control: h() (receiver is an untyped local → unknown type) stays AMBIGUOUS — BOTH speak defs survive. ──
hT="$( targets h )"
hN="$( printf '%s\n' "$hT" | grep -c . )"
if [ "$hN" = "2" ] && printf '%s\n' "$hT" | grep -qx "$ANIMAL_LINE" && printf '%s\n' "$hT" | grep -qx "$ROBOT_LINE"; then
    ok "CHA-lite control: h() stays AMBIGUOUS (both Animal::speak + Robot::speak — unknown receiver keeps current behavior)"
else
    no "CHA-lite control: h() targets = [$(echo $hT)] (want BOTH $ANIMAL_LINE + $ROBOT_LINE — CHA must NOT fire on an untyped receiver)"
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

# ── 6) #446: C++ base-clause types read as @reference.base captures (the capture IS the language gate).
# The fixture covers direct, qualified, template (CRTP family) and multiple-inheritance bases;
# a nameless struct with a base stays edgeless (the capture only matches a named class/struct),
# and a specialization's base is walked once (captureSpecializationHeader's own path).
FIX446="$ROOT/test/chafix446"
"$BIN" "$FIX446" --no-cache --lego=TBase 2>/dev/null >"$TMP/lego_tbase"
# edge-specific: each impl names TBase (the global one) among its bases
for impl in Tmpl QualTmpl Multi2 DepT In; do
    if grep -q "n=\"$impl\"" "$TMP/lego_tbase"; then ok "C++ base capture: $impl -> TBase"; \
    else no "C++ base capture: $impl lost its TBase edge"; fi
done
# Crtpd implements Crtp, not TBase — check against the right base
"$BIN" "$FIX446" --no-cache --lego=Crtp 2>/dev/null >"$TMP/lego_crtp"
if grep -q "n=\"Crtpd\"" "$TMP/lego_crtp"; then ok "C++ base capture: Crtpd -> Crtp (CRTP)"; \
    else no "C++ base capture: Crtpd lost its Crtp edge"; fi
# Base's direct implementors are exactly Dog, Cat and Multi2 (Multi arrives transitively via Dog).
# anon_var's nameless struct also derives from Base: an edge from it would add a direct row here.
"$BIN" "$FIX446" --no-cache --lego=Base 2>/dev/null >"$TMP/lego_base"
DIRECT446=$( grep -o '<impl n="[^"]*" p="[^"]*"/>' "$TMP/lego_base" | sed 's/^<impl n="\([^"]*\)".*/\1/' | sort | tr '\n' ' ' )
[ "$DIRECT446" = "Cat Dog Multi2 " ] && ok "C++ base capture: Base's direct implementors are exactly Cat Dog Multi2" \
    || no "C++ base capture: Base's direct implementors are [$DIRECT446], want [Cat Dog Multi2 ]"
# nameless struct (line 21): no extends site at all, and no anon_var row
"$BIN" "$FIX446" --no-cache --uses=Base 2>/dev/null >"$TMP/uses_base"
ANON446=$( grep -o 'role="extends" p="cppbase446.cpp:21"' "$TMP/uses_base" | wc -l | tr -d ' ' )
if [ "$ANON446" = 0 ] && ! grep -q 'anon_var' "$TMP/lego_base"; then ok "C++ base capture: nameless struct has no edge"; \
    else no "C++ base capture: nameless struct wrongly edged (extends sites at :21 = $ANON446)"; fi
# specialization (line 23): exactly one extends site — captureSpecializationHeader's own walk, not doubled by the capture
SPEC446=$( grep -o 'role="extends" p="cppbase446.cpp:23"' "$TMP/uses_base" | wc -l | tr -d ' ' )
[ "$SPEC446" = 1 ] && ok "C++ base capture: specialization's base read exactly once" \
    || no "C++ base capture: specialization produced $SPEC446 extends sites (want exactly 1)"
# determinism
"$BIN" "$FIX446" --no-cache >"$TMP/base446_map" 2>/dev/null
"$BIN" "$FIX446" --no-cache >"$TMP/base446_map2" 2>/dev/null
[ -s "$TMP/base446_map" ] && diff -q "$TMP/base446_map" "$TMP/base446_map2" >/dev/null && ok "C++ base capture: deterministic fixture map" \
    || no "C++ base capture: empty or non-deterministic fixture map"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
