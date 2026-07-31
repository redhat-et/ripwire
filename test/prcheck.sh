#!/usr/bin/env bash
# prcheck.sh — RANKING-CORE gate: a hand-derivable PageRank oracle. Zero prior coverage before this gate
# on the actual numeric correctness of the PageRank power-iteration itself (src/graph.h rankGraph* /
# src/main.cpp default rank path) — querycheck.sh/rankbycheck.sh exercise ranking as a black box (order,
# dispatch) but nothing pins hand-derived VALUES.
#
# Fixture test/prfix/star.cpp: three symmetric callers (caller_x/y/z) each call ONE hub() and nothing
# else calls anything. By symmetry the three callers must have EQUAL rank; hub gathers all three callers'
# rank so it must be the clear top; the star topology has no other edges to muddy the derivation.
#
# House rule: float scores are NEVER asserted bit-exact except where the fixture's OWN symmetry makes two
# printed values identical by construction (the tie) — never against an absolute expected value. The
# hub-vs-caller comparison is a coarse ratio via k= parsing (awk), never string equality.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/prcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/prfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/prfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "prcheck: BIN=$BIN  CORPUS=test/prfix"

OUT="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --rank-by=pagerank --no-cache 2>/dev/null )"
[ -n "$OUT" ] || { echo "empty output from ripwire — cannot proceed"; exit 1; }

# names in EMISSION order (rank desc, id asc — see src/serialize.h) — this IS the rank order.
names_in_order(){ printf '%s' "$1" | grep -oE '<s [^>]*n="[^"]*"' | grep -oE 'n="[^"]*"' | sed 's/n="//;s/"//'; }
k_of(){ printf '%s' "$1" | grep -oE '<s [^>]*n="'"$2"'"[^>]*k="[0-9.]+"' | head -1 | grep -oE 'k="[0-9.]+"' | sed 's/k="//;s/"//'; }

# ── #1: order — hub first, then the three callers (any order among the tied three) ─────────────────────
ORDER="$( names_in_order "$OUT" )"
first="$( printf '%s\n' "$ORDER" | head -1 )"
count="$( printf '%s\n' "$ORDER" | wc -l | tr -d ' ' )"
rest="$( printf '%s\n' "$ORDER" | tail -n +2 | sort | tr '\n' ',' )"
[ "$first" = "hub" ] && ok "rank order: hub() emitted first" || no "rank order: expected hub() first, got: $first"
{ [ "$count" = 4 ] && [ "$rest" = "caller_x,caller_y,caller_z," ]; } \
    && ok "rank order: all 4 symbols present, hub followed by exactly {caller_x,caller_y,caller_z}" \
    || no "rank order: expected hub + {caller_x,caller_y,caller_z}, got count=$count rest=$rest"

# ── #2: the three callers TIE — equal k= to 4 decimals AS PRINTED (symmetric fixture; printed equality is
#    fine here per the house rule, since this is a genuine sort/membership-style symmetry, not a float
#    computation being pinned to an absolute value) ──────────────────────────────────────────────────────
kx="$( k_of "$OUT" caller_x )"; ky="$( k_of "$OUT" caller_y )"; kz="$( k_of "$OUT" caller_z )"
{ [ -n "$kx" ] && [ "$kx" = "$ky" ] && [ "$ky" = "$kz" ]; } \
    && ok "symmetry: caller_x/y/z all tie at k=$kx (equal rank by construction)" \
    || no "symmetry broken: caller_x=$kx caller_y=$ky caller_z=$kz should be equal"

# ── #3: hub's k is at least 2x a caller's k — numeric comparison via awk, NEVER string-equality on hub's
#    absolute value. (Observed ratio is ~3.5x; 2x is a generous, robust tolerance-factor floor.) ─────────
khub="$( k_of "$OUT" hub )"
if [ -n "$khub" ] && [ -n "$kx" ]; then
    awk -v h="$khub" -v c="$kx" 'BEGIN{ exit !(h >= c * 2.0) }' \
        && ok "hub k=$khub is >= 2x a caller's k=$kx (ratio=$( awk -v h="$khub" -v c="$kx" 'BEGIN{ printf "%.2f", h/c }' ))" \
        || no "hub k=$khub is NOT >= 2x caller k=$kx"
else
    no "could not parse hub/caller k= values (hub='$khub' caller='$kx')"
fi

# ── determinism ──────────────────────────────────────────────────────────────────────────────────────
OUT_B="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --rank-by=pagerank --no-cache 2>/dev/null )"
[ "$OUT" = "$OUT_B" ] && ok "determinism: byte-identical run-to-run" || no "non-deterministic pagerank output"

# ── xml well-formed ──────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT" | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
