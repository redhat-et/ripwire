#!/usr/bin/env bash
# chaconecheck.sh — gate for the B2.1 CHA-lite cone MEMO (fixture names are deliberately UNIQUE across test/:
# recallevalcheck pins --for=Robot repo-wide to chafix, so this hierarchy is Creature/Hound/Lynx/Automaton/Lamp) (perf round 2026-09-09, the super-linear warm
# --grep floor): graph.h::buildGraph used to recompute a receiver type's inheritance cone — {type} ∪
# ancestors ∪ descendants, two BFS walks over the class-NAME graph with an O(n²) std::find dedup and a
# 4096-entry cap per walk — on EVERY still-ambiguous receiver-typed call. Measured on llvm-project
# (182,555 files, warm): 86,667 cones for 2,984 distinct receiver types, mean cone 1,075 names,
# 1.65 ms each = 143 s of a 154 s --callers/--grep run (bench/PROFILE.md has the phase table). The fix
# computes each receiver type's cone ONCE and answers membership from it.
#
# WHAT THIS GATE PINS: that the memoised cone is the SAME SET the per-call walk produced — including the
# two behaviours a re-implementation is most likely to change silently:
#   (a) the cone is keyed on the RECEIVER TYPE, not the callee name: g1/g2 (Hound, two files) and g3 (Lynx)
#       call the same `vocalize` and must get their OWN cones; a memo keyed on the callee would hand Lynx the
#       Hound answer (both contain Creature — so arm 3 pins the *Lamp* case too, where the answers differ);
#   (b) the BFS cap is `out.size() < 4096` checked at the OUTER loop only: the adjacency list that crosses
#       the cap is pushed whole, and nothing AFTER it is expanded. Arm 5 builds Base→{A,B}, A→A1..A4095,
#       B→B1: Base's list [A,B] is expanded, A's 4095 children cross the cap, B is never expanded, so B1 is
#       OUTSIDE the cone and B1::m is dropped while all 4095 A-children survive → count=4095, and the ONE
#       call site is a 4095-way split → amb="1" (amb counts ambiguous CALLS, not tier width).
#       A cap moved to the inner loop, or to 4097, or a dedup that changes discovery order, turns it red.
#   (c) a memo HIT served AFTER the memo has grown is the requester's own cone, not the newest one: g7 asks for
#       Hound again after g6 filled Droid's cone {Droid, Machine}; Hound's answer must still be Creature::vocalize
#       and never Machine::vocalize. Staleness in the other sense is impossible by construction — the memo lives
#       inside ONE buildGraph call and its inputs (chaUp/chaDown) are immutable for that lifetime, so there is
#       nothing to invalidate — but a cached cone pointer, an index that goes wrong once the cone vector
#       reallocates, or a key collision all present exactly as arm 6 reads: the wrong hierarchy's answer on a hit.
# Plus the degrade rule (a cone that keeps nothing leaves the tier untouched — g4), a control where the cone
# cannot fire (g5), determinism and XML well-formedness.
#
# RED-first proof (2026-09-09): against the pre-memo binary every arm PASSES (the expected values are the
# per-call walk's own answers, hand-derived above); mutating the cap to `< 4097` fails arm 5; keying the memo
# on the callee name fails arm 3; returning the most recently filled cone on a hit (`&cones_.back()`) fails
# arm 6 — observed red, then green after the revert, on 2026-09-09.
#
#   test/chaconecheck.sh                       # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/chaconecheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/chaconefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/chaconefix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "chaconecheck: BIN=$BIN  CORPUS=test/chaconefix (+ a generated 4,097-class cap corpus)"

# def lines derived from the source so the gate survives fixture edits
ANIMAL_LINE="$(  grep -n 'inline void Creature::vocalize()' "$FIX/zoo.h" | cut -d: -f1 )"
MACHINE_LINE="$( grep -n 'inline void Machine::vocalize()'  "$FIX/zoo.h" | cut -d: -f1 )"
ROBOT_LINE="$(  grep -n 'void vocalize() { power'        "$FIX/zoo.h" | cut -d: -f1 )"

# distinct vocalize target lines a caller resolves to (--callees rows carry p="zoo.h:LINE")
targets(){ "$BIN" "$FIX" --callees="$1" --no-cache 2>/dev/null | tr '>' '\n' | grep -oE 'zoo\.h:[0-9]+' | grep -oE '[0-9]+$' | sort -un; }
count(){  "$BIN" "$FIX" --callees="$1" --no-cache 2>/dev/null | grep -oE ' count="[0-9]+"' | head -1 | grep -oE '[0-9]+'; }
hasamb(){ "$BIN" "$FIX" --no-cache --top-k=100000 2>/dev/null | grep -oE "n=\"$1\"[^>]*" | grep -q 'amb='; }

# ── 1) the first Hound cone (a.cpp): Creature::vocalize ONLY, Automaton dropped, no amb ────────────────────────────
T="$( targets g1 )"
if [ "$( count g1 )" = 1 ] && printf '%s\n' "$T" | grep -qx "$ANIMAL_LINE" && ! printf '%s\n' "$T" | grep -qx "$ROBOT_LINE" && ! hasamb g1; then
    ok "g1 (Hound, a.cpp): Creature::vocalize only (zoo.h:$ANIMAL_LINE), Automaton dropped, no amb="
else no "g1 (Hound, a.cpp): expected exactly Creature::vocalize — got count=$( count g1 ) lines={$( printf '%s' "$T" | tr '\n' ' ')}"; fi

# ── 2) the memo HIT (b.cpp asks for the Hound cone again): byte-identical answer ──────────────────────────
T="$( targets g2 )"
if [ "$( count g2 )" = 1 ] && printf '%s\n' "$T" | grep -qx "$ANIMAL_LINE" && ! printf '%s\n' "$T" | grep -qx "$ROBOT_LINE" && ! hasamb g2; then
    ok "g2 (Hound, b.cpp — memo hit): Creature::vocalize only, Automaton dropped, no amb="
else no "g2 (Hound, b.cpp): memo hit differs from g1 — got count=$( count g2 ) lines={$( printf '%s' "$T" | tr '\n' ' ')}"; fi

# ── 3) a DIFFERENT cone on the same callee name (Lynx), and one with NO inheritance facts (Lamp) ─────────
T="$( targets g3 )"
if [ "$( count g3 )" = 1 ] && printf '%s\n' "$T" | grep -qx "$ANIMAL_LINE" && ! hasamb g3; then
    ok "g3 (Lynx): its own cone {Lynx, Creature} → Creature::vocalize only, no amb="
else no "g3 (Lynx): expected exactly Creature::vocalize — got count=$( count g3 ) lines={$( printf '%s' "$T" | tr '\n' ' ')}"; fi
T="$( targets g4 )"
if [ "$( count g4 )" = 3 ] && printf '%s\n' "$T" | grep -qx "$ANIMAL_LINE" && printf '%s\n' "$T" | grep -qx "$ROBOT_LINE" && printf '%s\n' "$T" | grep -qx "$MACHINE_LINE" && hasamb g4; then
    ok "g4 (Lamp): cone {Lamp} keeps nothing → DEGRADE, all three targets kept, amb= honest"
else no "g4 (Lamp): expected the untouched 3-way split — got count=$( count g4 ) lines={$( printf '%s' "$T" | tr '\n' ' ')}"; fi

# ── 4) control: a parameter receiver has no var→type binding, so no cone can fire ───────────────────────
T="$( targets g5 )"
if [ "$( count g5 )" = 3 ] && hasamb g5; then
    ok "g5 (Hound& parameter): receiver type unknown → 3-way split kept, amb= honest (control)"
else no "g5 (Hound& parameter): control should stay ambiguous — got count=$( count g5 )"; fi

# ── 6) a hit AFTER the memo grew: g6 fills Droid's cone, then g7 asks for Hound again ──────────────────────
T="$( targets g6 )"
if [ "$( count g6 )" = 1 ] && printf '%s\n' "$T" | grep -qx "$MACHINE_LINE" && ! hasamb g6; then
    ok "g6 (Droid): third cone {Droid, Machine} → Machine::vocalize only (zoo.h:$MACHINE_LINE), no amb="
else no "g6 (Droid): expected exactly Machine::vocalize — got count=$( count g6 ) lines={$( printf '%s' "$T" | tr '\n' ' ')}"; fi
T="$( targets g7 )"
if [ "$( count g7 )" = 1 ] && printf '%s\n' "$T" | grep -qx "$ANIMAL_LINE" && ! printf '%s\n' "$T" | grep -qx "$MACHINE_LINE" && ! hasamb g7; then
    ok "g7 (Hound, after the memo grew): its OWN cone again — Creature::vocalize, never Machine::vocalize"
else no "g7 (Hound, after the memo grew): a hit returned the wrong hierarchy — got count=$( count g7 ) lines={$( printf '%s' "$T" | tr '\n' ' ')}"; fi

# ── 5) the 4096 BFS cap, reproduced exactly: Base→{A,B}, A→A1..A4095, B→B1; B is never expanded ─────────
CAP="$TMP/capfix"; mkdir -p "$CAP"
{
    printf 'struct Base { void driver() { this->m(); } };\n'
    printf 'struct A : Base {};\n'
    printf 'struct B : Base {};\n'
    i=1; while [ "$i" -le 4095 ]; do printf 'struct A%d : A { void m() {} };\n' "$i"; i=$(( i + 1 )); done
    printf 'struct B1 : B { void m() {} };\n'
} >"$CAP/cap.cpp"
B1_LINE="$(    grep -n '^struct B1 : B'     "$CAP/cap.cpp" | cut -d: -f1 )"
A4095_LINE="$( grep -n '^struct A4095 : A' "$CAP/cap.cpp" | cut -d: -f1 )"
OUT="$( "$BIN" "$CAP" --callees=driver --no-cache --limit=100000 2>/dev/null )"
CNT="$( printf '%s' "$OUT" | grep -oE ' count="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
LINES="$( printf '%s' "$OUT" | tr '>' '\n' | grep -oE 'cap\.cpp:[0-9]+' | grep -oE '[0-9]+$' | sort -un )"
AMB="$( "$BIN" "$CAP" --no-cache --top-k=100000 2>/dev/null | grep -oE 'n="driver"[^>]*' | grep -oE 'amb="[0-9]+"' | grep -oE '[0-9]+' )"
if [ "$CNT" = 4095 ] && printf '%s\n' "$LINES" | grep -qx "$A4095_LINE" && ! printf '%s\n' "$LINES" | grep -qx "$B1_LINE" && [ "${AMB:-0}" = 1 ]; then
    ok "cap: Base::driver → A1..A4095::m (count=4095, one call amb=1); B1::m (cap.cpp:$B1_LINE) outside the capped cone"
else no "cap: expected count=4095 amb=1 without B1::m — got count=${CNT:-?} amb=${AMB:-none} B1_present=$( printf '%s\n' "$LINES" | grep -qx "$B1_LINE" && echo yes || echo no )"; fi

# ── 6) determinism + well-formedness ────────────────────────────────────────────────────────────────────
A="$( "$BIN" "$FIX" --callees=g2 --no-cache 2>/dev/null )"; B="$( "$BIN" "$FIX" --callees=g2 --no-cache 2>/dev/null )"
if [ "$A" = "$B" ]; then ok "determinism: --callees=g2 byte-identical run-to-run"; else no "non-deterministic --callees output"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$A" | xmllint --noout - 2>/dev/null; then ok "xml well-formed"; else no "xml malformed"; fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
