#!/usr/bin/env bash
# rustanccheck.sh — gate for the RUST QUALIFIED-CALL ANCESTOR-CLOSURE MEMO (perf round 2026-09-09, the
# loop-hoist sweep). `graph.h::keepRustQualifiedCandidates` decides whether a candidate for a `Qual::name()`
# call is admissible by asking whether the candidate's enclosing scope reaches `Qual` through the CHA-lite
# base-name graph. It used to answer that with a fresh transitive BFS PER CANDIDATE PER REFERENCE —
# `std::vector<std::string> ancestors`, a full std::string COPY per queue element, an O(n²) `std::find`
# dedup, capped at 4,096 — the same shape, in the function next door, that the CHA-lite cone memo fixed the
# same day. Measured warm on rust-lang/rust-analyzer (2,303 files): 7,539 active calls, 23.9 ms, which was
# 47% of the whole resolve loop and 17% of the warm run (bench/PROFILE.md has the phase table). The fix
# computes each scope's capped base closure ONCE, over interned ids, and answers by binary search.
#
# WHAT THIS GATE PINS — a memo's one real failure mode is a HIT THAT RETURNS THE WRONG ANSWER, so every arm
# is a lookup, never a timing:
#   (a) the closure is TRANSITIVE. Alphaz reaches Zonkbase only through Zonktop -> Zonkmid (three hops), so a
#       one-hop test, or a walk that stops at the first frontier, drops Alphaz — arm 1.
#   (b) the closure is keyed on the CANDIDATE SCOPE, and a hit served after the memo has GROWN is still the
#       requester's own answer: zonk_first fills the Alphaz/Betaz/Gammaz closures against Zonkbase,
#       zonk_between then asks against Otherbase (a different qualifier, answer Gammaz only), and zonk_again
#       asks for Zonkbase again — it must be {Alphaz, Betaz} and never Gammaz. A cached index that goes stale
#       when the closure table reallocates, a key collision, or "return the most recently filled closure" all
#       present exactly as arm 3 reads.
#   (c) the guard still REFUSES: Gammaz's closure reaches Otherbase and nothing else, so it must never
#       survive a Zonkbase-qualified call (arms 1 and 3) and must be the only survivor of an Otherbase one
#       (arm 2). A memo that returned "reaches everything" would show up here first.
# Plus determinism and XML well-formedness.
#
# RED-first proof (2026-09-09): against the PRE-memo binary every arm passes — the expected values are the
# per-candidate walk's own answers, read off it before the memo existed. Then, against the memo build, two
# mutations were applied one at a time and each was observed RED:
#   * `ancestors_.back()` instead of `ancestors_[ ancIndex_[ root ] ]` (serve the LAST-FILLED closure on a
#     hit) -> arm 2 keeps all three impls and arm 3 collapses to nothing;
#   * replacing the transitive walk with a one-hop frontier -> arms 1 and 3 lose Alphaz, whose only path to
#     Zonkbase is Alphaz -> Zonktop -> Zonkmid -> Zonkbase.
# Green again after each revert.
#
#   test/rustanccheck.sh                       # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/rustanccheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/rustancfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/rustancfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "rustanccheck: BIN=$BIN  CORPUS=test/rustancfix"

# def lines derived from the source, so the gate survives a fixture edit instead of pinning stale numbers
ALPHA_LINE="$( grep -n '^impl Zonktop   for Alphaz'  "$FIX/src/lib.rs" | cut -d: -f1 )"
BETA_LINE="$(  grep -n '^impl Zonkbase  for Betaz'   "$FIX/src/lib.rs" | cut -d: -f1 )"
GAMMA_LINE="$( grep -n '^impl Otherbase for Gammaz'  "$FIX/src/lib.rs" | cut -d: -f1 )"
for v in ALPHA_LINE BETA_LINE GAMMA_LINE; do
    eval "n=\$$v"
    case "$n" in ''|*[!0-9]*) echo "  FAIL  fixture probe: $v did not resolve to a line number"; fail=1;; esac
done

callees(){ "$BIN" "$FIX" --callees="$1" --no-cache 2>/dev/null; }
lines(){   callees "$1" | tr '>' '\n' | grep -oE 'lib\.rs:[0-9]+' | grep -oE '[0-9]+$' | sort -un | tr '\n' ' ' | sed 's/ $//'; }
count(){   callees "$1" | grep -oE ' count="[0-9]+"' | head -1 | grep -oE '[0-9]+'; }

# ── 1) the FIRST ask: Zonkbase keeps Alphaz (3 hops) and Betaz (1 hop), drops Gammaz ────────────────────
G="$( lines zonk_first )"
if [ "$( count zonk_first )" = 2 ] && [ "$G" = "$ALPHA_LINE $BETA_LINE" ]; then
    ok "zonk_first: Zonkbase:: keeps Alphaz (lib.rs:$ALPHA_LINE, three hops) + Betaz (lib.rs:$BETA_LINE), drops Gammaz"
else no "zonk_first: expected exactly {$ALPHA_LINE $BETA_LINE} — got count=$( count zonk_first ) lines={$G}"; fi

# ── 2) a DIFFERENT qualifier in between: Otherbase keeps Gammaz alone (the memo grows) ──────────────────
G="$( lines zonk_between )"
if [ "$( count zonk_between )" = 1 ] && [ "$G" = "$GAMMA_LINE" ]; then
    ok "zonk_between: Otherbase:: keeps Gammaz alone (lib.rs:$GAMMA_LINE) — a different key fills the memo"
else no "zonk_between: expected exactly {$GAMMA_LINE} — got count=$( count zonk_between ) lines={$G}"; fi

# ── 3) the memo HIT after growth: Zonkbase again, still Alphaz+Betaz, never Gammaz ──────────────────────
G="$( lines zonk_again )"
if [ "$( count zonk_again )" = 2 ] && [ "$G" = "$ALPHA_LINE $BETA_LINE" ]; then
    ok "zonk_again (hit after the memo grew): Zonkbase:: is its OWN answer again, never Gammaz's lib.rs:$GAMMA_LINE"
else no "zonk_again: a hit returned the wrong closure — expected {$ALPHA_LINE $BETA_LINE}, got count=$( count zonk_again ) lines={$G}"; fi

# ── 4) determinism + well-formedness ───────────────────────────────────────────────────────────────────
A="$( "$BIN" "$FIX" --no-cache --top-k=100000 2>/dev/null )"; B="$( "$BIN" "$FIX" --no-cache --top-k=100000 2>/dev/null )"
[ "$A" = "$B" ] && ok "determinism: the default map is byte-identical run-to-run" || no "non-deterministic default map"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$A" | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
