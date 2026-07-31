#!/usr/bin/env bash
# localitycheck.sh — the S6-C locality tie-break gate (adversarial HIGH-1 regression).
#
#   test/localitycheck.sh                       # uses build/ripwire on test/localityfix
#   RIPWIRE_BIN=asan/ripwire test/localitycheck.sh
#
# The fixture test/localityfix/loc.cpp has two UNRELATED classes Xtra and Bravo that BOTH define go().
# Class Xenon::call() does `Bravo b; b.go();`. The caller scope "Xenon" shares only a leading LETTER with
# "Xtra" — NOT a real structural prefix. The old raw-byte locality tie-break scored `Xenon`↔`Xtra` higher
# than `Xenon`↔`Bravo` and resolved the call CONFIDENTLY to the WRONG Xtra::go (ambiguous=0). The fix makes
# locality SEGMENT-aware (`/`/`::`), so the partial in-segment overlap counts as ZERO: Xtra and Bravo tie on
# path-only locality and the call stays HONESTLY ambiguous. This gate asserts:
#   * the call NEVER resolves to a lone confident pick of the unrelated Xtra::go (loc.cpp:28)
#   * it either stays split (count=2) or resolves to the correct Bravo::go (loc.cpp:29) — never a wrong one
#   * `ambiguous` > 0 on the fixture (the resolver is HONEST, not falsely certain)
#   * determinism (run twice → byte-identical) and no symbol loss / well-formed XML
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/localityfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "localitycheck: BIN=$BIN  CORPUS=$CORPUS"

# 1) determinism — same input, byte-identical output run-to-run (the tie-break must stay deterministic)
"$BIN" "$CORPUS" --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --no-cache >"$TMP/b" 2>/dev/null
diff -q "$TMP/a" "$TMP/b" >/dev/null && ok "determinism (byte-identical, $(wc -c <"$TMP/a" | tr -d ' ') B)" || no "determinism (non-deterministic output)"

# 2) the spurious-prefix call (`b.go()` in Xenon::call) must NOT be a lone confident pick of the WRONG class.
#    --callees lists resolved out-edges with file:line. Xtra::go = loc.cpp:28, Bravo::go = loc.cpp:29.
CALLEES="$( "$BIN" "$CORPUS" --callees=call --no-cache 2>/dev/null )"
NEDGE="$( printf '%s' "$CALLEES" | grep -o 'count="[0-9]*"' | grep -o '[0-9]*' )"
HAS_XTRA="$( printf '%s' "$CALLEES" | grep -c 'loc.cpp:28' )"   # Xtra::go (the WRONG class)
HAS_BRAVO="$( printf '%s' "$CALLEES" | grep -c 'loc.cpp:29' )"  # Bravo::go (the correct receiver type)

# the core regression assertion: a lone confident edge to ONLY the unrelated Xtra::go is the bug.
if [ "$NEDGE" = "1" ] && [ "$HAS_XTRA" -ge 1 ] && [ "$HAS_BRAVO" -eq 0 ]; then
    no "REGRESSION: call resolves CONFIDENTLY to the WRONG unrelated class Xtra::go (loc.cpp:28) — the HIGH-1 bug"
    printf '    %s\n' "$CALLEES"
else
    ok "no false-confident pick of the unrelated Xtra::go (count=${NEDGE:-?})"
fi

# acceptable outcomes: stay split (count=2, both go() present) OR resolve to the correct Bravo::go only.
if { [ "$NEDGE" = "2" ] && [ "$HAS_XTRA" -ge 1 ] && [ "$HAS_BRAVO" -ge 1 ]; } || { [ "$NEDGE" = "1" ] && [ "$HAS_BRAVO" -ge 1 ] && [ "$HAS_XTRA" -eq 0 ]; }; then
    ok "call is honestly ambiguous (split 2) or correctly narrowed to Bravo::go — never a wrong confident pick"
else
    no "unexpected resolution shape (count=${NEDGE:-?}, xtra=$HAS_XTRA, bravo=$HAS_BRAVO)"
    printf '    %s\n' "$CALLEES"
fi

# 3) ambiguous= header count is > 0 — the resolver is HONEST about the unresolved same-name call, not falsely
#    certain (ambiguous=0 was the bug's false-confidence signature). This count RISING is the fix working.
AMB="$( "$BIN" "$CORPUS" --no-cache 2>/dev/null | grep -o 'ambiguous=[0-9]*' | grep -o '[0-9]*' )"
[ "${AMB:-0}" -gt 0 ] && ok "ambiguous=$AMB on the fixture (>0 — honest, was falsely 0 with the byte-prefix bug)" || no "ambiguous=${AMB:-?} on the fixture (expected >0 — the resolver is falsely confident)"

# 4) no symbol loss + well-formed XML (the corrected tie-break must not corrupt the map or drop symbols).
MAP="$( "$BIN" "$CORPUS" --no-cache 2>/dev/null )"
printf '%s' "$MAP" | grep -q 'n="call"' && ok "call symbol still present (no symbol loss)" || no "call symbol vanished"
printf '%s' "$MAP" | grep -q 'n="go"'   && ok "go symbols still present (no symbol loss)"   || no "go symbols vanished"
command -v xmllint >/dev/null 2>&1 && { printf '%s' "$MAP" | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } || ok "xml well-formed (xmllint absent — skipped)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
