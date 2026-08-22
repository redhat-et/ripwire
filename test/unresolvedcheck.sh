#!/usr/bin/env bash
# unresolvedcheck.sh — honesty lever #2 gate: the `unresolved=N` completeness gauge.
#
# THE contract this locks (see memory project_honesty_hardening.md, lever #2): a call whose
# in-repo defs are ALL language-filtered — a same-name def exists in ANOTHER language — must be
# COUNTED into the header `unresolved=N` gauge (a plausibly-internal edge the tool MISSED),
# while a call to a name with NO in-repo def at all (a genuine stdlib/third-party external)
# must NOT be counted. Over-counting the external case would itself be a silent-WRONG gauge —
# the exact bug this lever exists to kill — so the gate asserts BOTH directions.
#
# Fixture (test/unresolvedfix/):
#   lib.cpp — int render() { 42 }        // C++ def of `render`
#             int cppMain() { render() } // same-language call → resolves cleanly (NOT unresolved)
#   app.py  — def run():                 // Python caller
#               render()                 // cross-language: `render` is in-repo (C++) but its def
#                                        //   is lang-filtered for a Python call → COUNTED
#               totally_external_fn()    // no in-repo def anywhere (site A) → NOT counted
#               helper()                 // same-language Python call → resolves cleanly
#             def helper(): 1
#
# FINDINGS from running `ripwire test/unresolvedfix` and reading the raw header BEFORE asserting:
#   - header shows `unresolved=1` — exactly the one cross-language `render()` call from Python.
#     `totally_external_fn` (genuine external) and both same-language calls are NOT counted.
#   - edges=2: cppMain -> render (C++) and run -> helper (Python) both resolve — the lever does
#     NOT disturb normal same-language resolution.
#   - determinism: two runs byte-identical.
#   - MUTATION A: delete the `render()` call from app.py (leave the genuine external) → the ONLY
#     remaining unresolved-style call is `totally_external_fn` → `unresolved=0`. Proves the
#     external case is NOT counted.
#   - MUTATION B: rename the C++ def `render` -> `renderX` (so the name is no longer in-repo) →
#     the Python `render()` call becomes a genuine external (site A) → `unresolved=0`. Proves the
#     count is gated on "name IS defined in-repo" — non-tautological.
#
# Usage:
#   test/unresolvedcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/unresolvedcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/unresolvedfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# extract the header gauge value: gauge_of <file> <name> → prints the integer (empty if absent).
# Require ≥1 DIGIT after '=' (grep -oE ...=[0-9]+) so the legend text `hdr:unresolved=call-name-…`
# (which has no digit) is NOT matched — only the header stats token `unresolved=<N>`.
gauge_of(){ grep -oE "$2=[0-9]+" "$1" | head -1 | cut -d= -f2; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "unresolvedcheck: BIN=$BIN  FIX=$FIX"

MAP_OUT="$TMP/map.xml"
$BIN "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
[ "$MAP_EXIT" -eq 0 ] && ok "default map: exits 0 on the polyglot fixture" || no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"

command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$MAP_OUT" && ok "default map: passes xmllint --noout (G4)" || no "default map: xmllint failed"; }
[ -s "$TMP/map.err" ] && no "default map: unexpected stderr (degrade?): $( cat "$TMP/map.err" )" || ok "default map: clean stderr (no degrade)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== the gauge is present in the header, next to ambiguous= ==="
# ═══════════════════════════════════════════════════════════════════════════
grep -qE 'ambiguous=[0-9]+ unresolved=[0-9]+' "$MAP_OUT" \
    && ok "header: unresolved= emitted immediately after ambiguous= (stats line)" \
    || no "header: unresolved= not found next to ambiguous=: $( head -c 400 "$MAP_OUT" )"

# legend documents the new gauge
grep -q 'unresolved=' "$MAP_OUT" && ok "header: unresolved= gauge present" || no "header: unresolved= gauge MISSING"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== the cross-language miss IS counted; the genuine external is NOT ==="
# ═══════════════════════════════════════════════════════════════════════════
UNRES="$( gauge_of "$MAP_OUT" unresolved )"
AMB="$( gauge_of "$MAP_OUT" ambiguous )"
echo "  unresolved=$UNRES  ambiguous=$AMB"
[ "$UNRES" = "1" ] \
    && ok "unresolved=1: the Python->C++ render() cross-language miss is counted" \
    || no "unresolved=$UNRES: expected exactly 1 (the render() cross-language miss)"
# the genuine external totally_external_fn must NOT have inflated the count (it would make it >1)
[ "$UNRES" = "1" ] \
    && ok "genuine external totally_external_fn() NOT counted (count stays 1, not 2)" \
    || no "genuine external appears to be counted (unresolved=$UNRES > 1)"

# normal same-language resolution is UNDISTURBED: both real edges present
grep -q 'n="cppMain"[^>]*>.*<c n="render"' "$MAP_OUT" \
    && ok "same-language C++ edge cppMain -> render still resolves (lever does not break resolution)" \
    || no "same-language edge cppMain -> render MISSING"
grep -q 'n="run"[^>]*>.*<c n="helper"' "$MAP_OUT" \
    && ok "same-language Python edge run -> helper still resolves" \
    || no "same-language edge run -> helper MISSING"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== MUTATION A: drop the cross-language call, keep the genuine external → gauge falls to 0 ==="
# ═══════════════════════════════════════════════════════════════════════════
MUTA="$TMP/muta"; mkdir -p "$MUTA"; cp "$FIX/lib.cpp" "$MUTA/lib.cpp"
sed 's/^    render().*$/    pass/' "$FIX/app.py" >"$MUTA/app.py"
$BIN "$MUTA" --no-cache >"$TMP/muta.xml" 2>/dev/null
UNRES_A="$( gauge_of "$TMP/muta.xml" unresolved )"
[ "$UNRES_A" = "0" ] \
    && ok "MUTATION A: unresolved=0 — the lone genuine external is NOT counted (non-tautological)" \
    || no "MUTATION A: unresolved=$UNRES_A — expected 0 (genuine external must not count)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== MUTATION B: rename the C++ def so the name leaves the repo → the call becomes external → 0 ==="
# ═══════════════════════════════════════════════════════════════════════════
MUTB="$TMP/mutb"; mkdir -p "$MUTB"; cp "$FIX/app.py" "$MUTB/app.py"
sed 's/int render()/int renderX()/; s/return render();/return renderX();/' "$FIX/lib.cpp" >"$MUTB/lib.cpp"
$BIN "$MUTB" --no-cache >"$TMP/mutb.xml" 2>/dev/null
UNRES_B="$( gauge_of "$TMP/mutb.xml" unresolved )"
[ "$UNRES_B" = "0" ] \
    && ok "MUTATION B: unresolved=0 — a name with no in-repo def is a genuine external, not a miss" \
    || no "MUTATION B: unresolved=$UNRES_B — expected 0 (count must be gated on in-repo def)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== determinism: default map twice, byte-identical (det-gate) ==="
# ═══════════════════════════════════════════════════════════════════════════
$BIN "$FIX" --no-cache >"$TMP/det_a.xml" 2>/dev/null
$BIN "$FIX" --no-cache >"$TMP/det_b.xml" 2>/dev/null
diff -q "$TMP/det_a.xml" "$TMP/det_b.xml" >/dev/null \
    && ok "determinism: default map byte-identical across two runs" \
    || no "determinism: default map differs across runs"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
