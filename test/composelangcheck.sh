#!/usr/bin/env bash
# composelangcheck.sh — S5-E HAS-A compose edges must apply the SAME language gate (langCompatible)
# as every other candidate-admission site in buildGraph.
#
# The bug this gate was recorded RED against (2026-08-20, base adb0831): compose CAPTURE is C++-only
# (ingest.cpp captureFields), but compose RESOLUTION was language-blind — byName.find( typeName )
# admitted a Python `class Foo` as the target of a C++ member `Foo m_foo;`. Two user-visible symptoms
# on the mixed-language fixture test/composelangfix:
#   * the cross-language candidate gets a LOWER symbol id (alpha.py sorts before widget.cpp), so it
#     sorts first AND defeats the adjacency dedup on (ownerSym, fieldName) — `m_foo` appeared TWICE
#     in <compose>, once bound to the Python Foo and once to the C++ Foo;
#   * a member whose type has NO lang-compatible definition anywhere (`Bar* m_bar;`, Python-only Bar)
#     grew a compose edge to the Python class.
# Both leak into --around / --for (serialize.h packCompose) and into the CBO composed-type half of
# --metrics. The C<->C++ bridge control (m_gadget -> gadget.c) pins that the fix is langCompatible,
# NOT a bare lang==Cpp equality test.
#
# Usage:
#   test/composelangcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/composelangcheck.sh
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/composelangfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/composelangfix directory"; exit 2; }

echo "composelangcheck: BIN=$BIN  FIX=$FIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 1. --around=Widget: compose edges admit only lang-compatible targets ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$FIX" --around=Widget --no-cache >"$TMP/widget.xml" 2>/dev/null
rc=$?; [ $rc -eq 0 ] && ok "--around=Widget exits 0" || no "--around=Widget failed (rc=$rc)"

FOO_COUNT="$( grep -o 'name="m_foo"' "$TMP/widget.xml" | wc -l | tr -d ' ' )"
[ "$FOO_COUNT" -eq 1 ] && ok "m_foo emitted exactly once (count=$FOO_COUNT) — cross-language Foo candidate rejected" \
                        || no "m_foo emitted $FOO_COUNT times — the Python Foo was admitted alongside the C++ Foo (lang-blind resolution)"

grep -q 'name="m_bar"' "$TMP/widget.xml" \
    && no "m_bar has a compose edge — its only definition of Bar is the PYTHON class in alpha.py" \
    || ok "m_bar has no compose edge (Bar has no lang-compatible definition)"

grep -q 'name="m_gadget"' "$TMP/widget.xml" \
    && ok "m_gadget compose edge kept — C<->C++ bridge (gadget.c) still resolves (guard is langCompatible, not lang==Cpp)" \
    || no "m_gadget compose edge LOST — the lang guard broke the C<->C++ bridge (over-tight fix?)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 2. binding direction: the edge belongs to the C++ Foo, not the Python Foo ==="
# ═══════════════════════════════════════════════════════════════════════════
# packCompose emits an edge when EITHER endpoint is in the --around neighborhood, so which class's
# --around view carries the <compose> block reveals which definition the edge actually bound to.
"$BIN" "$FIX" --around=alpha.py:Foo  --no-cache >"$TMP/pyfoo.xml"  2>/dev/null
"$BIN" "$FIX" --around=widget.cpp:Foo --no-cache >"$TMP/cppfoo.xml" 2>/dev/null

grep -q '<compose>' "$TMP/pyfoo.xml" \
    && no "--around=alpha.py:Foo shows a <compose> block — the HAS-A edge bound to the PYTHON Foo" \
    || ok "--around=alpha.py:Foo shows no <compose> block (Python Foo owns no edge endpoint)"

grep -q 'name="m_foo"' "$TMP/cppfoo.xml" \
    && ok "--around=widget.cpp:Foo shows the m_foo edge — bound to the C++ definition" \
    || no "--around=widget.cpp:Foo missing the m_foo edge — the legitimate same-language binding was lost"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 3. hygiene: determinism + well-formedness of the compose-bearing map ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$FIX" --around=Widget --no-cache >"$TMP/widget2.xml" 2>/dev/null
diff -q "$TMP/widget.xml" "$TMP/widget2.xml" >/dev/null \
    && ok "--around=Widget deterministic (byte-identical rerun)" || no "--around=Widget non-deterministic"
command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$TMP/widget.xml" 2>/dev/null \
    && ok "--around=Widget output well-formed XML" || no "--around=Widget output malformed XML"; }

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== MUTATION: prove the count/presence assertions are load-bearing, not vacuous ==="
# ═══════════════════════════════════════════════════════════════════════════
MUT="$( ok(){ :; }; no(){ echo TRIPPED; }
        # asserting m_foo appears ZERO times must fail (the legitimate C++ edge exists)
        if [ "$FOO_COUNT" -eq 0 ]; then ok; else no; fi )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (asserting m_foo count==0 correctly fails)" \
                       || no "mutation self-test broke — the m_foo count assertion is not live"

MUT2="$( ok(){ :; }; no(){ echo TRIPPED; }
        if grep -q 'name="m_missing"' "$TMP/widget.xml"; then ok; else no; fi )"
[ "$MUT2" = "TRIPPED" ] && ok "mutation self-test (asserting a nonexistent field correctly fails)" \
                        || no "mutation self-test broke — the field-presence grep is not live"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
