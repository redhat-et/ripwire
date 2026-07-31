#!/usr/bin/env bash
# adaptivecutshapecheck.sh — A4-F4 unit-style gate, run BEFORE any relevance-cliff cut work: reproduces the
# exact deterministic score-vector shape the audit used (head cliff ~35% relative drop at rank 8 + a much
# larger ~98% relative drop far out in the tail, beyond hardCeil=40) and asserts adaptiveCut(...,
# scanFullDistribution=true) actually CUTS ON THE HEAD CLIFF instead of being inert (kept 40/40).
#
# Before the fix: tracking only the single GLOBAL-max relative drop meant the big-but-unreachable tail drop
# (beyond hardCeil) always won over the real, in-cap head cliff, so the cut candidate (bestCutKept=60ish)
# failed the `< hardCeil` guard and the function fell back to "keep the whole ceiling" — 40/40, inert on
# exactly the sharp queries adaptive-cut exists for.
#
# This is a standalone .cpp (lexical.h is header-only) compiled directly with clang++ — no CMake wiring
# needed, and a synthetic score vector is the precise, deterministic way to pin this exact shape (a
# real-corpus repro is not guaranteed to keep landing on the identical rank/pct numbers as source drifts).
#
# Usage: bash test/adaptivecutshapecheck.sh
# Exits non-zero on any failure. Does NOT touch regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
SRC="$ROOT/test/adaptivecutshapefix/adaptive_cut_shape_test.cpp"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "adaptivecutshapecheck: SRC=$SRC"

CXX="${CXX:-clang++}"
"$CXX" -std=c++23 -I "$ROOT/src" -I "$ROOT/src/infra" -I "$ROOT/third_party" "$SRC" "$ROOT/src/infra/fastmath.cpp" -o "$TMP/t" 2>"$TMP/build.err"
if [ -x "$TMP/t" ]; then
    ok "gate binary built"
else
    no "build failed"; cat "$TMP/build.err"; echo "FAILURES ABOVE"; exit 1
fi

OUT="$( "$TMP/t" )"
printf '%s\n' "$OUT"

FULL_KEPT="$(  printf '%s\n' "$OUT" | grep '^full:'   | grep -oE 'kept=[0-9]+'       | cut -d= -f2 )"
FULL_HIT="$(   printf '%s\n' "$OUT" | grep '^full:'   | grep -oE 'hitCeiling=[0-9]+' | cut -d= -f2 )"
FULL_DROP="$(  printf '%s\n' "$OUT" | grep '^full:'   | grep -oE 'dropPct=[0-9]+'    | cut -d= -f2 )"
CAP_KEPT="$(   printf '%s\n' "$OUT" | grep '^capped:' | grep -oE 'kept=[0-9]+'       | cut -d= -f2 )"

# the FIX: scanFullDistribution=true must cut at the head cliff (kept in [5,10], NOT the ceiling 40) —
# this is the exact regression the finding describes ("keeps 40/40" was the bug).
{ [ -n "$FULL_KEPT" ] && [ "$FULL_KEPT" -ge 5 ] && [ "$FULL_KEPT" -le 10 ]; } \
    && ok "A4-F4: scanFullDistribution=true cuts at the head cliff (kept=$FULL_KEPT, not 40/40)" \
    || no "A4-F4: NOT fixed — scanFullDistribution=true kept=$FULL_KEPT (want a small head-cliff cut, e.g. ~7)"
[ "$FULL_HIT" = "0" ] && ok "A4-F4: hitCeiling=false (a real cut was made, not a ceiling cap)" \
    || no "A4-F4: hitCeiling=$FULL_HIT (expected false — a cut should have fired)"
{ [ -n "$FULL_DROP" ] && [ "$FULL_DROP" -ge 25 ] && [ "$FULL_DROP" -le 45 ]; } \
    && ok "A4-F4: reported dropPct=$FULL_DROP is the in-cap ~35% head cliff, not the beyond-cap ~98% tail drop" \
    || no "A4-F4: dropPct=$FULL_DROP does not match the expected ~35% head-cliff magnitude"

# sanity: the capped (scanFullDistribution=false) scan already found this same head cliff before the fix —
# proves the test shape itself is sound and the fix doesn't change the ALREADY-CORRECT capped-mode behavior.
[ "$CAP_KEPT" = "$FULL_KEPT" ] \
    && ok "sanity: capped-mode (unaffected by this fix) agrees with full-mode on the same head cliff" \
    || no "sanity FAILED: capped=$CAP_KEPT vs full=$FULL_KEPT — the fixture shape may not isolate the bug as intended"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
