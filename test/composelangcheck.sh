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
# The SECOND bug this gate was recorded RED against (2026-08-31, base 3ce9944) is the rest of that same
# adjacency hole, in the SAME language. buildGraph deduped composeEdges on (ownerSym, fieldName) with
# std::unique — which only removes ADJACENT equals — while sorting them by (ownerSym, typeSym,
# fieldName). The dedup key was not a prefix of the sort key, so a type NAME with K same-language
# class/struct definitions put K copies of every field of that type in the ranked bundle, byte-identical,
# separated by the other fields. Measured on ripwire's own tree at that base: `ripwire . --around=
# darkflags.h:Gate` emitted `defSite` and `alsoSite` THREE times each (three `struct Site` definitions:
# darkflags.h, crossref.h, infra/profileScope.h) — 1522 bytes where 1272 carry the same facts; and a
# --for bundle over the same area shipped 20 <compose> rows where 12 are distinct, spending 524 bytes of
# its ~7.5KB payload budget on repeats that displaced two real ranked signatures. Pure waste against G4,
# and misleading — K identical rows read as K distinct use sites. A field has exactly ONE declared type;
# the extra candidates are resolver ambiguity about WHICH definition the name binds to, which
# byte-identical rows cannot express anyway. Section 4 pins one row per FIELD; the invariant arm pins it
# generically (no byte-identical duplicate row in a <compose> block).
#
# Usage:
#   test/composelangcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/composelangcheck.sh
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/composelangfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# The single <compose>…</compose> block of a map (--around / --for emit at most one), and the rows in it
# that appear more than once BYTE-IDENTICALLY. Scoped to the block on purpose: `<field ` is a row shape
# other surfaces print too (--layout's struct rows), and the invariant here is about ONE compose block.
compose_block(){ grep -o '<compose>.*</compose>' "$1" 2>/dev/null | head -1; }
dupe_rows(){ compose_block "$1" | tr '<' '\n' | sed -n 's|^field \(.*\)/>$|<field \1/>|p' | sort | uniq -d; }

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
echo "=== 4. same-language multi-definition: ONE row per field, not one per candidate definition ==="
# ═══════════════════════════════════════════════════════════════════════════
# `Thing` is defined twice in C++ (widget.cpp and theta.cpp) — both lang-compatible with the owner, so
# both survive the section-1 guard. The declared type of a field is singular, so each of Widget's two
# Thing members must still produce exactly one <compose> row.
THING_COUNT="$( grep -o 'name="m_thing"' "$TMP/widget.xml" | wc -l | tr -d ' ' )"
[ "$THING_COUNT" -eq 1 ] && ok "m_thing emitted exactly once (count=$THING_COUNT) — the second C++ Thing is the same declared type, not a second member" \
                          || no "m_thing emitted $THING_COUNT times — one row per candidate DEFINITION (dedup key is not a prefix of the sort key)"

OTHER_COUNT="$( grep -o 'name="m_other"' "$TMP/widget.xml" | wc -l | tr -d ' ' )"
[ "$OTHER_COUNT" -eq 1 ] && ok "m_other emitted exactly once (count=$OTHER_COUNT)" \
                          || no "m_other emitted $OTHER_COUNT times — same duplication, second field"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 5. INVARIANT: no byte-identical duplicate row inside one <compose> block ==="
# ═══════════════════════════════════════════════════════════════════════════
# The generic form of section 4, so a future duplication path that is neither cross-language nor
# multi-definition is still caught. Duplicated rows are pure token waste (G4) and they MISLEAD: a reader
# seeing a field N times may reasonably infer N distinct use sites, which is not what the row means.
for probe in "$TMP/widget.xml" "$TMP/cppfoo.xml"
do
    DUPES="$( dupe_rows "$probe" )"
    [ -z "$DUPES" ] && ok "no duplicate <compose> row in $( basename "$probe" )" \
                    || no "duplicate <compose> rows in $( basename "$probe" ):
$( echo "$DUPES" | sed 's/^/          /' )"
done

# The same invariant on ripwire's OWN tree, where the bug was found: `struct Site` has three C++
# definitions (darkflags.h, crossref.h, infra/profileScope.h) and darkflags.h's `Gate` has two Site
# members. This arm is deliberately assertion-only — if Gate ever loses those members it goes quiet
# rather than red, and section 4's hermetic fixture stays the load-bearing proof.
"$BIN" "$ROOT" --around=darkflags.h:Gate >"$TMP/selfgate.xml" 2>/dev/null
SELF_DUPES="$( dupe_rows "$TMP/selfgate.xml" )"
[ -z "$SELF_DUPES" ] && ok "no duplicate <compose> row in ripwire's own --around=darkflags.h:Gate" \
                     || no "duplicate <compose> rows in ripwire's own --around=darkflags.h:Gate:
$( echo "$SELF_DUPES" | sed 's/^/          /' )"

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

# the section-5 invariant is a "must be EMPTY" assertion, so it passes on any output it cannot read.
# Hand it a block that IS duplicated and confirm it reports exactly that row.
printf '%s' '<r><compose><field name="a" type="T" owner="O" rel="uses"/><field name="b" type="T" owner="O" rel="uses"/><field name="a" type="T" owner="O" rel="uses"/></compose></r>' >"$TMP/synthetic.xml"
MUT3="$( dupe_rows "$TMP/synthetic.xml" )"
[ "$MUT3" = '<field name="a" type="T" owner="O" rel="uses"/>' ] \
    && ok "mutation self-test (dupe_rows finds a planted duplicate row, and only it)" \
    || no "mutation self-test broke — dupe_rows returned [$MUT3] on a block with one planted duplicate"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
