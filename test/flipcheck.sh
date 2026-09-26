#!/usr/bin/env bash
# flipcheck.sh — the gate for `--flags --flip=NAME`, the ONE-GATE BLAST RADIUS (src/flipimpact.h).
#
#   test/flipcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/flipcheck.sh
#
# --flags answers "what is dark here" and hands back a LIST. --flip answers the only question that list
# leads to: if I turn THIS one on, what becomes live, which symbols hold it, what do they reach, and which
# tests cover it. The four things a naive implementation gets wrong, each pinned below:
#
#   1) a plain #if gate         — regions -> the defs inside them (test/flagsfix FIXTURE_DARK_FEATURE)
#   2) an ALIAS MASTER          — its radius is its CHILDREN's, rolled up (test/flagsaliasfix ALIASFIX_ALL);
#      and the same chain the other way: flipping a CHILD lights only that child, and names its parent
#   3) a VALUE-STYLE gate       — `constexpr bool k = F != 0` + `if constexpr( k )` guards a C++ BRANCH, not
#      an #if region, so --flags honestly reports regions="0" and a flip verb that follows only #if regions
#      reports "nothing lights up" for exactly the family an owner most wants to flip
#      (test/flagsfix FIXTURE_VALUE_ALL) — plus the SHADOW rule that keeps that lane from cross-wiring on a
#      same-named local constant in an unrelated file (valueShadow.cpp)
#   4) the refusals             — --flip without --flags, a bare --flip, an unknown gate name; each must
#      refuse LOUDLY with exit 1, never emit an empty-looking success
#
# Plus the kind-specific semantics (cmake override / env runtime), and a synthetic src+test corpus for the
# tests / untested lane, which the committed fixtures cannot pin because everything under test/ is a test
# path by isTestPath (same reason test/testgatecheck.sh builds its own corpus).
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/flagsfix"
ALIASFIX="$ROOT/test/flagsaliasfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "flipcheck: BIN=$BIN"

# flip CORPUS GATE [extra flags…] -> the report on stdout
flip(){ local c="$1" g="$2"; shift 2; "$BIN" "$c" --flags --flip="$g" --no-cache "$@" 2>/dev/null; }
# attr XML ELEM ATTR -> the attribute value on the FIRST element of that name ("" if absent)
attr(){ printf '%s' "$1" | tr '<' '\n' | grep -m1 "^$2 " | sed -n "s/.* $3=\"\([^\"]*\)\".*/\1/p"; }
want(){ # want LABEL GOT EXPECTED
    if [ "$2" = "$3" ]; then ok "$1 ($3)"; else no "$1: got '$2', want '$3'"; fi; }

# ── 1) determinism — two runs byte-identical (§1) ────────────────────────────────────────────────
flip "$FIX" FIXTURE_VALUE_ALL >"$TMP/a"
flip "$FIX" FIXTURE_VALUE_ALL >"$TMP/b"
if cmp -s "$TMP/a" "$TMP/b"; then ok "determinism (byte-identical)"; else no "--flip is non-deterministic"; fi

# ── 2) a plain #if gate: regions -> the defs those regions hold ───────────────────────────────────────
F="$( flip "$FIX" FIXTURE_DARK_FEATURE )"
want "plain #if: kind"        "$( attr "$F" flip kind )"     "compile"
want "plain #if: dark"        "$( attr "$F" flip dark )"     "1"
want "plain #if: regions"     "$( attr "$F" flip regions )"  "2"
want "plain #if: family is just itself" "$( attr "$F" flip family )" "1"
want "plain #if: hosts"       "$( attr "$F" flip hosts )"    "2"
[ "$( attr "$F" flip loc )" -gt 0 ] 2>/dev/null \
    && ok "plain #if: sizes the guarded code (loc=$( attr "$F" flip loc ))" || no "plain #if: loc is 0"
# the hosts are the two functions that live INSIDE the guarded regions, not the live one beside them
if printf '%s' "$F" | grep -q 'sym="darkOnly"'; then ok "plain #if: darkOnly is a host"; else no "plain #if: darkOnly missing from hosts"; fi
if printf '%s' "$F" | grep -q 'sym="nestedDark"'; then ok "plain #if: nestedDark is a host"; else no "plain #if: nestedDark missing from hosts"; fi
printf '%s' "$F" | grep -q 'sym="liveEntry"'  && no "plain #if: liveEntry (outside every region) reported as a host" \
                                              || ok "plain #if: unguarded code is NOT a host"

# ── 3) alias chains, BOTH directions ──────────────────────────────────────────────────────────────────
M="$( flip "$ALIASFIX" ALIASFIX_ALL )"
want "alias master: family rolls up master+children" "$( attr "$M" flip family )"  "3"
want "alias master: radius is its CHILDREN's regions" "$( attr "$M" flip regions )" "2"
want "alias master: hosts"                            "$( attr "$M" flip hosts )"   "2"
printf '%s' "$M" | grep -q 'member name="ALIASFIX_WALLS" via="alias"' \
    && ok "alias master: WALLS listed as a family member" || no "alias master: WALLS member row missing"
printf '%s' "$M" | grep -q 'member name="ALIASFIX_TURNS" via="alias"' \
    && ok "alias master: TURNS listed as a family member" || no "alias master: TURNS member row missing"
printf '%s' "$M" | grep -q 'sym="wallsFeature"' && printf '%s' "$M" | grep -q 'sym="turnsFeature"' \
    && ok "alias master: lights BOTH children's guarded functions" || no "alias master: a child's function is missing"

C="$( flip "$ALIASFIX" ALIASFIX_WALLS )"
want "alias child: family is just itself"  "$( attr "$C" flip family )"  "1"
want "alias child: regions"                "$( attr "$C" flip regions )" "1"
want "alias child: hosts"                  "$( attr "$C" flip hosts )"   "1"
printf '%s' "$C" | grep -q 'parent name="ALIASFIX_ALL" siblings="1"' \
    && ok "alias child: names its parent + the 1 sibling the parent's flip would add" \
    || { no "alias child: parent row wrong"; printf '%s' "$C" | tr '<' '\n' | grep '^parent'; }
printf '%s' "$C" | grep -q 'sym="turnsFeature"' && no "alias child: lit its SIBLING's code too" \
                                                || ok "alias child: does NOT light the sibling's code"

# ── 4) the VALUE-STYLE gate — the case --flags honestly reports as regions="0" ─────────────────────────
V="$( flip "$FIX" FIXTURE_VALUE_ALL )"
want "value gate: regions (no #if exists — this is the point)" "$( attr "$V" flip regions )"  "0"
want "value gate: family"                                      "$( attr "$V" flip family )"   "3"
want "value gate: constexpr bool bindings found"               "$( attr "$V" flip bindings )" "2"
want "value gate: if-constexpr branch sites found"             "$( attr "$V" flip branches )" "2"
want "value gate: hosts"                                       "$( attr "$V" flip hosts )"    "1"
printf '%s' "$V" | grep -q 'b p="valueUse.cpp" l="12" gate="FIXTURE_VALUE_WAVE" via="kWave" sym="valueEntry"' \
    && ok "value gate: a branch row names its gate, its binding AND its host symbol" \
    || { no "value gate: branch row wrong"; printf '%s' "$V" | tr '<' '\n' | grep '^b p='; }
printf '%s' "$V" | grep -q 'sym="turnHelper"' && printf '%s' "$V" | grep -q 'sym="waveHelper"' \
    && ok "value gate: downstream names what the newly-live branches CALL" || no "value gate: downstream missing the helpers"
# the SHADOW rule: valueShadow.cpp has its own `constexpr int kTurns` and must NOT be credited to the gate
want "value gate: shadowed local constant not counted" \
     "$( printf '%s' "$V" | tr '<' '\n' | grep -m1 '^bind name="kTurns"' | sed -n 's/.* uses="\([0-9]*\)".*/\1/p' )" "1"
printf '%s' "$V" | grep -q 'valueShadow.cpp' && no "value gate: the shadowing file leaked into the radius" \
                                             || ok "value gate: the shadowing file is excluded entirely"
# and the child of a value master lights only itself
VC="$( flip "$FIX" FIXTURE_VALUE_WAVE )"
want "value child: family is just itself" "$( attr "$VC" flip family )"   "1"
want "value child: branches"              "$( attr "$VC" flip branches )" "1"
printf '%s' "$VC" | grep -q 'parent name="FIXTURE_VALUE_ALL" siblings="1"' \
    && ok "value child: names its parent (a child with NO preprocessor reader is still reachable)" \
    || no "value child: parent row missing — the unread-gate keep is broken"

# ── 5) kind semantics: cmake override wins + build rows; env is runtime ───────────────────────────────
O="$( flip "$FIX" FIXTURE_OVERRIDE )"
want "cmake override: the CMake default wins the headline" "$( attr "$O" flip kind )"    "cmake"
want "cmake override: not dark (the build already passes it)" "$( attr "$O" flip dark )" "0"
printf '%s' "$O" | grep -q '<already-lit ' \
    && ok "cmake override: says the winning default ALREADY builds this code" || no "cmake override: already-lit note missing"
printf '%s' "$O" | grep -q '<also kind="compile" default="0" p="override.h"' \
    && ok "cmake override: the contradicting header row is still shown" || no "cmake override: <also> row missing"
printf '%s' "$O" | grep -q '<c p="CMakeLists.txt"' \
    && ok "cmake override: CMake read sites listed as unfollowed build reach" || no "cmake override: <build> rows missing"

E="$( flip "$FIX" FIXTURE_ENV_SWITCH )"
want "env gate: kind"                 "$( attr "$E" flip kind )"    "env"
want "env gate: flagged as RUNTIME"   "$( attr "$E" flip runtime )" "1"
printf '%s' "$E" | grep -q 'via="getenv" sym="envGate"' \
    && ok "env gate: the host is the symbol that CONSULTS the variable" || no "env gate: getenv host wrong"

# ── 6) the refusals — each loud, each exit 1, none an empty-looking success ───────────────────────────
"$BIN" "$FIX" --flip=FIXTURE_DARK_FEATURE --no-cache >"$TMP/o" 2>"$TMP/e"; rc=$?
[ $rc -eq 1 ] && [ ! -s "$TMP/o" ] && grep -q -- "--flags" "$TMP/e" \
    && ok "refusal: --flip without --flags (exit 1, names the companion, no stdout)" \
    || no "refusal: --flip alone rc=$rc out=$( wc -c <"$TMP/o" ) err=$( head -1 "$TMP/e" )"

"$BIN" "$FIX" --flags --flip --no-cache >"$TMP/o" 2>"$TMP/e"; rc=$?
[ $rc -eq 1 ] && [ ! -s "$TMP/o" ] && grep -q "needs a gate name" "$TMP/e" \
    && ok "refusal: bare --flip (exit 1, asks for a gate name, no stdout)" \
    || no "refusal: bare --flip rc=$rc err=$( head -1 "$TMP/e" )"

"$BIN" "$FIX" --flags --flip=FIXTURE_DARK --no-cache >"$TMP/o" 2>"$TMP/e"; rc=$?
[ $rc -eq 1 ] && [ ! -s "$TMP/o" ] && grep -q "FIXTURE_DARK_FEATURE" "$TMP/e" \
    && ok "refusal: unknown gate (exit 1, names the near-miss, no stdout)" \
    || no "refusal: near-miss rc=$rc err=$( head -1 "$TMP/e" )"

"$BIN" "$FIX" --flags --flip=ZZZ_NOT_A_GATE --no-cache >"$TMP/o" 2>"$TMP/e"; rc=$?
[ $rc -eq 1 ] && [ ! -s "$TMP/o" ] && grep -q "no gate named" "$TMP/e" \
    && ok "refusal: unknown gate with no near-miss still refuses (exit 1)" \
    || no "refusal: unmatchable name rc=$rc err=$( head -1 "$TMP/e" )"

# multi-root: the gate harvest reads on-disk paths, which a merged workspace relabels, so it would find zero
# gates and report the real gate as "unknown". Refuse instead of answering wrong.
"$BIN" "$FIX" "$ALIASFIX" --flags --flip=ALIASFIX_ALL --no-cache >"$TMP/o" 2>"$TMP/e"; rc=$?
[ $rc -eq 1 ] && [ ! -s "$TMP/o" ] && grep -q "single-root only" "$TMP/e" \
    && ok "refusal: multi-root (exit 1, names the reason, never a bogus unknown-gate)" \
    || no "refusal: multi-root rc=$rc err=$( head -1 "$TMP/e" )"

# ── 7) tests / untested — needs a corpus with a real src+test split (see the header note) ─────────────
SYN="$TMP/syn"; mkdir -p "$SYN/src" "$SYN/tests"
cat >"$SYN/src/gates.h" <<'EOF'
#pragma once
#ifndef SYNFIX_FEATURE
#define SYNFIX_FEATURE 0
#endif
EOF
cat >"$SYN/src/covered.cpp" <<'EOF'
#include "gates.h"
#if SYNFIX_FEATURE
int coveredDark()
{
    return 1;
}
#endif
EOF
cat >"$SYN/src/uncovered.cpp" <<'EOF'
#include "gates.h"
#if SYNFIX_FEATURE
int uncoveredDark()
{
    return 2;
}
#endif
EOF
cat >"$SYN/tests/test_cov.cpp" <<'EOF'
int coveredDark();
int runCoveredCase()
{
    return coveredDark();
}
EOF
S="$( flip "$SYN" SYNFIX_FEATURE )"
want "coverage: both guarded defs are hosts" "$( attr "$S" flip hosts )" "2"
# M21(b) re-pin (capture-audit 2026-09-04, lane L8): --flags --flip's <t> rows joined the tests_to_run row
# family and now carry run="…" or run_unknown="1" like every sibling (test/testrowruncheck.sh is the family
# gate). Pinned to the NEW contract — the path AND a disclosure — not loosened to a prefix match.
printf '%s' "$S" | grep -qE '<t p="tests/test_cov\.cpp"( run="[^"]*"| run_unknown="1")/>' \
    && ok "coverage: the covering test file is named, with its run recipe or run_unknown disclosure" \
    || { no "coverage: tests_to_run wrong"; printf '%s' "$S" | tr '<' '\n' | grep '^t p='; }
want "coverage: exactly one host no test reaches" "$( attr "$S" flip untested )" "1"
printf '%s' "$S" | tr '<' '\n' | grep -q '^u sym="uncoveredDark"' \
    && ok "coverage: uncoveredDark is the untested one" || { no "coverage: untested row wrong"; printf '%s' "$S" | tr '<' '\n' | grep '^u '; }
printf '%s' "$S" | grep -q 'sym="coveredDark" p="src/covered.cpp" l="3" ccx="0" tested="1"' \
    && ok "coverage: coveredDark carries tested=1" || { no "coverage: tested= column wrong"; printf '%s' "$S" | tr '<' '\n' | grep '^h '; }

# ── 8) --detail lifts the per-list row caps ───────────────────────────────────────────────────────────
N_CAPPED="$(  flip "$FIX" FIXTURE_VALUE_ALL            | tr '<' '\n' | grep -c '^b p=' )"
N_DETAIL="$(  flip "$FIX" FIXTURE_VALUE_ALL --detail=1 | tr '<' '\n' | grep -c '^b p=' )"
[ "$N_CAPPED" = "$N_DETAIL" ] && ok "--detail is accepted alongside --flags/--flip" \
                              || no "--detail changed the small-fixture row count ($N_CAPPED vs $N_DETAIL)"
"$BIN" "$FIX" --flags --flip=FIXTURE_VALUE_ALL --detail=1 --no-cache >/dev/null 2>"$TMP/e"
if [ ! -s "$TMP/e" ]; then ok "--detail=N with --flags no longer refuses"; else no "--detail refused: $( head -1 "$TMP/e" )"; fi

# ── 9) G4 — well-formed, minified XML on every kind ───────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmlfail=0
    for g in FIXTURE_DARK_FEATURE FIXTURE_VALUE_ALL FIXTURE_OVERRIDE FIXTURE_ENV_SWITCH; do
        flip "$FIX" "$g" >"$TMP/x" || true
        xmllint --noout "$TMP/x" 2>/dev/null || { xmlfail=1; echo "      (malformed for $g)"; }
        [ "$( grep -c '' "$TMP/x" )" -le 1 ] || { xmlfail=1; echo "      (newlines outside CDATA for $g)"; }
    done
    if [ $xmlfail -eq 0 ]; then ok "XML well-formed + minified for every gate kind"; else no "XML/G4 violation"; fi
else
    ok "xmllint unavailable — well-formedness skipped"
fi
# no `--` inside an XML comment (G4: xmllint accepts it in some modes, the spec does not)
flip "$FIX" FIXTURE_DARK_FEATURE | sed -n 's/.*<!--\(.*\)-->.*/\1/p' | grep -q -- '--' \
    && no "an XML comment contains '--'" || ok "no '--' inside the XML comment"

# ── 10) --flags itself is UNCHANGED by all of the above (the behaviour --flip extends) ────────────────
if bash "$ROOT/test/flagscheck.sh" >/dev/null 2>&1; then ok "test/flagscheck.sh still passes (--flags unchanged)"
else no "test/flagscheck.sh broke — --flip must not change --flags output"; fi

# ── the binding cap is disclosed, in every build flavour ──────────────────────────────────────────────────────────
# The value lane keeps at most kMaxBindings (32) constexpr bindings of one gate. With 40, bindings="32" and the 32
# branch sites reached through them used to read as totals — the legend says the verdict counts are taken over the
# FULL sets — with only a one-argument DISCLOSE (nothing in Release). The scan's sink now puts <capped what="bindings"
# at="32"/> in the report, and a clause defining capped= rides with it.
BC="$TMP/bindcap"; mkdir -p "$BC"
python3 - "$BC/a.cpp" <<'PYEOF'
import sys
s = "#ifndef FEATURE_X\n#define FEATURE_X 0\n#endif\n" + "".join( "constexpr bool kB%d = FEATURE_X;\n" % i for i in range( 40 ) )
s += "int run( int v )\n{\n" + "".join( "    if constexpr ( kB%d ) { v += %d; }\n" % ( i, i ) for i in range( 40 ) ) + "    return v;\n}\n"
open( sys.argv[1], "w" ).write( s )
PYEOF
flip "$BC" FEATURE_X >"$BC/out.xml"
grep -q '<flip [^>]* bindings="32"' "$BC/out.xml" \
    && ok "binding cap (guard): 40 bindings are cut to the 32 the scan keeps" \
    || no "binding cap (guard): the fixture did not reach the cap — the arm is void: $( grep -o '<flip [^>]*>' "$BC/out.xml" | head -c 200 )"
grep -q '<capped what="bindings" at="32"/>' "$BC/out.xml" \
    && ok "binding cap: the report says bindings= is a floor — <capped what=\"bindings\" at=\"32\"/>" \
    || no "binding cap: bindings=\"32\" reads as the total with no cap row"
grep -q 'capped what= at=: ' "$BC/out.xml" \
    && ok "binding cap: capped what= at= is defined in the same document" || no "binding cap: the capped row rides with no definition"
command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$BC/out.xml" 2>/dev/null \
    && ok "binding cap: the report is well-formed" || no "binding cap: the report fails xmllint"; }

# ── the alias-chain DEPTH cap is disclosed too, and only when the chain really runs past it ─────────────────────────
# aliasDescendants descends kMaxChainDepth (8) alias links. Only the fan-out cap (kMaxFamily) set familyCapped, so a
# chain of ten gates flipped at its root lit nine and dropped the tenth with no <capped> row (CodeRabbit on #295).
# Control: a chain of exactly nine gates — the walk reaches its end in eight links, so nothing may be claimed capped.
chain(){ # chain DIR N -> N gates DEEPFIX_L0..L(N-1), each aliasing the previous, the last one guarding a function
    mkdir -p "$1"; { printf '#ifndef DEEPFIX_L0\n#define DEEPFIX_L0 0\n#endif\n'
      i=1; while [ $i -lt "$2" ]; do printf '#ifndef DEEPFIX_L%d\n#define DEEPFIX_L%d DEEPFIX_L%d\n#endif\n' $i $i $(( i - 1 )); i=$(( i + 1 )); done
      printf '#if DEEPFIX_L%d\nint deepFeature() { return 1; }\n#endif\n' $(( $2 - 1 )); } >"$1/chain.h"; }
chain "$TMP/chain9" 9; chain "$TMP/chain10" 10
D9="$( flip "$TMP/chain9" DEEPFIX_L0 )"; D10="$( flip "$TMP/chain10" DEEPFIX_L0 )"
want "depth control: a nine-gate chain is walked to its end (family)" "$( attr "$D9" flip family )" "9"
printf '%s' "$D9" | grep -q '<capped what="depth"' \
    && no "depth control: a chain the walk finished claims a depth cut" || ok "depth control: no <capped what=\"depth\"> on a chain the walk finished"
want "depth: a ten-gate chain stops at the cap (family)" "$( attr "$D10" flip family )" "9"
printf '%s' "$D10" | grep -q '<capped what="depth" at="8"/>' \
    && ok "depth: the cut is disclosed (<capped what=\"depth\" at=\"8\"/>)" \
    || no "depth: a ten-gate chain lost its tenth gate with no <capped what=\"depth\"> row: $( printf '%s' "$D10" | tr '<' '\n' | grep -m1 '^flip ' )"
printf '%s' "$D10" | grep -q 'what=depth' \
    && ok "depth: the capped clause defining what=depth rides with the row" || no "depth: <capped what=\"depth\"> emitted with no clause defining it"

# ── 2026-09-25: a next= over 120 B used to be dropped SILENTLY (base), then this lane's
# first draft replaced a complete, runnable invocation with next_dropped="1" instead — a working follow-up
# lost either way for no reason but its own length. The ruling: nextAttrXml carries NO length ceiling, so
# flipNextInvocation's full "--flags --flip=NAME --limit=N" is now always emitted, and it must actually
# paste and run. RED on origin/main's binary: this fixture's gate name alone pushes the invocation past
# 120 B, and the pre-fix binary emits no next= at all.
LONGGATE="FIXTURE_ANSWERSNEXT064_A_VERY_LONG_MACRO_GATE_NAME_THAT_PUSHES_THE_NEXT_INVOCATION_PAST_ONE_HUNDRED_TWENTY_BYTES_XYZ"
LG="$TMP/longgate"; mkdir -p "$LG"
{ printf '#pragma once\n#ifndef %s\n#define %s 0\n#endif\n#if %s\n' "$LONGGATE" "$LONGGATE" "$LONGGATE"
  i=0; while [ $i -lt 30 ]; do printf 'int hostFn%d() { return %d; }\n' $i $i; i=$(( i + 1 )); done
  printf '#endif\n'; } >"$LG/gate.h"
NEXTLONG="$( flip "$LG" "$LONGGATE" )"
[ "$( attr "$NEXTLONG" flip hosts )" = "30" ] && [ "$( attr "$NEXTLONG" hosts hosts_capped )" = "1" ] \
    && ok "E2 guard: the 30-host fixture really cuts hosts at 25 (hosts_capped=\"1\") — the arms below can fail" \
    || no "E2 guard: fixture did not cut (hosts=$( attr "$NEXTLONG" flip hosts ) hosts_capped=$( attr "$NEXTLONG" hosts hosts_capped )) — the next= arms below are vacuous"
NEXTLONGVAL="$( attr "$NEXTLONG" flip next )"
if [ -z "$NEXTLONGVAL" ]; then
    no "E2: no next= on the cut, over-120-byte flip report (want the full --flags --flip=$LONGGATE --limit=…)"
else
    if [ "${#NEXTLONGVAL}" -gt 120 ]; then ok "E2: the over-120-byte next= is emitted in full (${#NEXTLONGVAL} B), never dropped"
    else no "E2: fixture next= is only ${#NEXTLONGVAL} B (<=120) — not a real test of the no-ceiling rule"; fi
    python3 -c 'import shlex, sys; print( "\0".join( shlex.split( sys.argv[1] ) ), end = "" )' "$NEXTLONGVAL" > "$TMP/e2argv.bin"
    E2RC="$( ( cd "$LG" && xargs -0 "$BIN" . --no-cache < "$TMP/e2argv.bin" >"$TMP/e2.out" 2>"$TMP/e2.err" ); echo $? )"
    if [ "$E2RC" = 0 ]; then
        E2RERUN="$( cat "$TMP/e2.out" )"
        [ "$( attr "$E2RERUN" hosts hosts_capped )" != "1" ] \
            && ok "E2: the pasted next= re-runs and its own --limit= now shows every host uncapped" \
            || no "E2: the pasted next=\"$NEXTLONGVAL\" re-ran but hosts are STILL capped: $( printf '%s' "$E2RERUN" | grep -o '<hosts[^>]*>' )"
    else
        no "E2: the pasted next=\"$NEXTLONGVAL\" exits $E2RC instead of running: $( head -c 160 "$TMP/e2.err" | tr '\n' ' ' )"
    fi
fi
# control: a short gate name that still cuts DOES carry a real, runnable next=
SHORTLONG="$( flip "$FIX" FIXTURE_DARK_FEATURE --limit=1 )"
SN="$( attr "$SHORTLONG" flip next )"
if [ -n "$SN" ]; then
    [ "${#SN}" -le 120 ] && ok "E2 control: a short-name cut flip's next= is ${#SN} B (<=120), and present" \
                         || no "E2 control: a short-name cut flip's next= is ${#SN} B (>120)"
else
    no "E2 control: FIXTURE_DARK_FEATURE --limit=1 carries no next= at all — the control case is vacuous"
fi

[ $fail -eq 0 ] && echo "flipcheck: ALL PASS" || echo "flipcheck: FAILURES"
exit $fail
