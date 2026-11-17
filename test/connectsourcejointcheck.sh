#!/usr/bin/env bash
# connectsourcejointcheck.sh — CONNECT-SOURCE-JOINT (a): --connect never names a TEST function as the joint of two SOURCE
# terminals (CLI --connect, the <graph_verb> block inside --for, the MCP `connect` verb — one core, three surfaces).
#
# THE DEFECT THIS PINS. connectSubgraph's undirected BFS walks every node, so when the only thing calling both terminals is a
# test (terraform's TestContext2Apply_nullableVariables calls Context.Plan and Context.Apply), the answer printed the test
# as <s n=…> — "the common caller" — with no hedge: confident-wrong. Worse, the §2.4a tie-break prefers the join that connects
# FEWER things, and a test usually connects few, so a test could beat a real source joint at the same distance.
#
# THE RULE. When no terminal is test code (filter.h pathDefInTests: a test symbol, or a test/fixture/bench path), a test-class
# node is never an intermediary of the search. When that leaves terminals apart that a test joins, the root says so:
# source_joint="none" with test_joint=/test_joint_p= naming the test (test-only evidence, not a source caller).
#
# Arms:
#   P  premise: in the test-only fixture the test really calls both terminals (--callers on each names it); FAIL on zero
#   A  test-only joint: CLI --connect prints no <s> for the test, and discloses source_joint="none" + test_joint=      (RED on main)
#   B  the same through --for's <graph_verb> block                                                                     (RED on main)
#   C  the same through the MCP connect verb                                                                            (RED on main)
#   D  positive control: a real source joint still prints as <s>, no source_joint=
#   E  a source joint that connects MORE than the test (the old tie-break's loser) now wins over the test               (RED on main)
#   F  test terminal: when a terminal IS test code, a test joint stays allowed (and no source_joint=)
#   G  legend: source_joint= / test_joint= / test_joint_p= are defined in both dialects when present; absent otherwise
#   I  the evidence names a test that joins terminals the source search left APART: with planIt/applyIt joined through
#      source and a shorter test path beside it, and cIt/dIt joined only by a second test, test_joint= is the cIt/dIt
#      test, not the lower-id planIt/applyIt one (CodeRabbit #625)
#   J  the test_joint= reading in both dialects does not claim a direction: the test is a node the undirected search
#      joins them THROUGH (A -> helper <- B is not "a test that calls them together"; CodeRabbit #625)
#   K  the evidence is per LEG: one unrestricted group holds planIt/applyIt (source-joined, with a shorter abTest beside
#      them) and cIt (joined to applyIt only through bcTest); test_joint= is bcTest, the test on the leg that crosses
#      source components, not the lower-id abTest on a source-joined leg (CodeRabbit #636)
#   L  a many-definition terminal is chosen on the source-only view: one::runIt joins planIt in 2 hops through a test,
#      two::runIt in 4 hops through source; the answer joins planIt to two::runIt through source, with no test_joint=
#      (CodeRabbit #636)
#   N  two qualifying tests: test_joint= is the first by content (path, line, name), unchanged by renaming an unrelated
#      file (CodeRabbit #625 4546683506; green on main too: NodeId order already follows path, line, name)
#   H  determinism (3 runs) + xmllint
#   M  mutations: each assertion sees its own regression
#
# Usage: test/connectsourcejointcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "connectsourcejointcheck: BIN=$BIN"

brief(){ printf '%s' "$1" | sed 's/^.*<connect /<connect /' | head -c 600; }
steinerOf(){ printf '%s' "$1" | grep -o '<s n="[^"]*"' | sed 's/<s n="//;s/"//' | sort | tr '\n' ' ' | sed 's/ $//'; }

# ── corpora ──────────────────────────────────────────────────────────────────────────────────────────────
mksrc(){ mkdir -p "$1/src" "$1/test"; printf 'void planIt() {}\nvoid applyIt() {}\n' > "$1/src/core.cpp"; }
TONLY="$TMP/testonly";  mksrc "$TONLY"
printf 'void planIt(); void applyIt();\nvoid testBoth() { planIt(); applyIt(); }\n' > "$TONLY/test/core_test.cpp"

SJ="$TMP/srcjoint";     mksrc "$SJ"
printf 'void planIt(); void applyIt();\nvoid driver() { planIt(); applyIt(); }\n' > "$SJ/src/driver.cpp"

# the source joint connects 7 things, the test 2: the §2.4a tie-break (fewer connects) handed the join to the test
TIE="$TMP/tiebeat";     mksrc "$TIE"
printf 'void planIt(); void applyIt();\nvoid testBoth() { planIt(); applyIt(); }\n' > "$TIE/test/core_test.cpp"
{
    printf 'void x1() {}\nvoid x2() {}\nvoid x3() {}\nvoid x4() {}\nvoid x5() {}\nvoid planIt(); void applyIt();\n'
    printf 'void driver() { planIt(); applyIt(); x1(); x2(); x3(); x4(); x5(); }\n'
} > "$TIE/src/driver.cpp"

# planIt/applyIt are joined through source (driver -> planIt, driver -> mid -> applyIt) and by a SHORTER test path (abTest);
# cIt/dIt only by a second test (cdTest), declared after abTest so it has the higher id
XC="$TMP/crosscomp";    mksrc "$XC"
printf 'void cIt() {}\nvoid dIt() {}\n' >> "$XC/src/core.cpp"
printf 'void planIt(); void applyIt();\nvoid mid() { applyIt(); }\nvoid driver() { planIt(); mid(); }\n' > "$XC/src/driver.cpp"
printf 'void planIt(); void applyIt(); void cIt(); void dIt();\nvoid abTest() { planIt(); applyIt(); }\nvoid cdTest() { cIt(); dIt(); }\n' > "$XC/test/core_test.cpp"

# one unrestricted group: planIt/applyIt joined through source and by a shorter abTest; cIt reaches applyIt only through bcTest,
# declared after abTest so it has the higher id
XL="$TMP/crossleg";     mksrc "$XL"
printf 'void cIt() {}\n' >> "$XL/src/core.cpp"
printf 'void planIt(); void applyIt();\nvoid mid() { applyIt(); }\nvoid driver() { planIt(); mid(); }\n' > "$XL/src/driver.cpp"
printf 'void planIt(); void applyIt(); void cIt();\nvoid abTest() { planIt(); applyIt(); }\nvoid bcTest() { applyIt(); cIt(); }\n' > "$XL/test/core_test.cpp"

# runIt has two definitions: one::runIt joins planIt only through a test (2 hops), two::runIt through source (4 hops)
MD="$TMP/manydefs";     mksrc "$MD"
printf 'namespace one { void runIt() {} }\nnamespace two { void runIt() {} }\n' > "$MD/src/run.cpp"
printf 'void planIt();\nnamespace two { void runIt(); }\nvoid m2() { two::runIt(); }\nvoid m1() { m2(); }\nvoid d1() { planIt(); m1(); }\n' > "$MD/src/driver.cpp"
printf 'void planIt();\nnamespace one { void runIt(); }\nvoid pTest() { planIt(); one::runIt(); }\n' > "$MD/test/run_test.cpp"

TT="$TMP/testterm";     mksrc "$TT"
printf 'void helperT() {}\nvoid applyIt();\nvoid testDriver() { helperT(); applyIt(); }\n' > "$TT/test/helper_test.cpp"

# ── P) premise: the test-only joint exists (the test calls both terminals) ───────────────────────────────
premise=0
for t in planIt applyIt; do
    cl="$( "$BIN" "$TONLY" --no-cache --callers="$t" 2>/dev/null )" || no "premise: --callers=$t exited $?"
    printf '%s' "$cl" | grep -q 'testBoth' && premise=$(( premise + 1 ))
done
if [ "$premise" -eq 2 ]; then
    ok "(P) premise: testBoth calls both terminals (seen by --callers on each: $premise/2)"
else
    no "(P) premise: testBoth is not a caller of both terminals ($premise/2) — the negative arms below would be vacuous"
fi
premTie=0
for t in planIt applyIt; do
    cl="$( "$BIN" "$TIE" --no-cache --callers="$t" 2>/dev/null )" || no "premise: --callers=$t exited $?"
    printf '%s' "$cl" | grep -q 'testBoth' && premTie=$(( premTie + 1 ))
done
if [ "$premTie" -eq 2 ]; then
    ok "(P) premise: tie fixture's testBoth calls both terminals ($premTie/2)"
else
    no "(P) premise: tie fixture's testBoth calls $premTie/2 terminals"
fi

# ── A) CLI --connect, test-only joint ──────────────────────────────────────────────────────────────────
checkTestOnly(){   # $1 label, $2 document
    if printf '%s' "$2" | grep -q '<s n="testBoth"'; then
        no "($1) the test function is printed as the joint of two source terminals: $( brief "$2" )"
    else
        ok "($1) no <s> row names the test function testBoth"
    fi
    if printf '%s' "$2" | grep -q '<connect [^>]*source_joint="none"'; then ok "($1) the root says source_joint=\"none\""; else no "($1) no source_joint=\"none\" on the root: $( brief "$2" )"; fi
    if printf '%s' "$2" | grep -q '<connect [^>]*test_joint="testBoth" test_joint_p="test/core_test.cpp:2"'; then ok "($1) the test is named as test-only evidence (test_joint= test_joint_p=)"; else no "($1) test_joint=/test_joint_p= missing: $( brief "$2" )"; fi
    if printf '%s' "$2" | grep -q '<unconnected radius='; then ok "($1) the terminals are reported <unconnected> (no source joint within radius)"; else no "($1) no <unconnected> row: $( brief "$2" )"; fi
}
A_FULL="$( "$BIN" "$TONLY" --no-cache --connect=planIt,applyIt --legend=full 2>/dev/null )" || no "A_FULL: ripwire exited $?"
A_DEF="$( "$BIN" "$TONLY" --no-cache --connect=planIt,applyIt 2>/dev/null )" || no "A_DEF: ripwire exited $?"
checkTestOnly "A" "$A_FULL"

# ── B) --for's <graph_verb> block ────────────────────────────────────────────────────────────────────────
B_DOC="$( "$BIN" "$TONLY" --no-cache --for='common caller of planIt and applyIt' 2>/dev/null )" || no "B_DOC: ripwire exited $?"
B_GV="$( printf '%s' "$B_DOC" | grep -o '<graph_verb .*</graph_verb>' )"
if printf '%s' "$B_GV" | grep -q 'verb="--connect='; then
    ok "(B) premise: --for ran the --connect graph verb"
    checkTestOnly "B" "$B_GV"
else
    no "(B) premise: --for printed no --connect <graph_verb> block: $( printf '%s' "$B_DOC" | tail -c 400 )"
fi

# ── C) MCP connect verb ──────────────────────────────────────────────────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
    CMSG='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"connect","arguments":{"path":"'"$TONLY"'","symbols":["planIt","applyIt"]}}}'
    C_RAW="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$CMSG" | "$BIN" --mcp 2>/dev/null )" || no "(C) ripwire --mcp exited $?"
    C_DOC="$( printf '%s\n' "$C_RAW" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + json.dumps(r["error"]) if "error" in r else r["result"]["content"][0]["text"])
' )"
    case "$C_DOC" in
        __ERROR__*) no "(C) MCP connect returned an error: ${C_DOC#__ERROR__:}";;
        *) checkTestOnly "C" "$C_DOC";;
    esac
else
    ok "(C) python3 absent — MCP arm skipped"
fi

# ── D) positive control: a real source joint is still the joint ─────────────────────────────────────────
D_DOC="$( "$BIN" "$SJ" --no-cache --connect=planIt,applyIt 2>/dev/null )" || no "D_DOC: ripwire exited $?"
if [ "$( steinerOf "$D_DOC" )" = "driver" ]; then ok "(D) a source joint (driver) still prints as <s>"; else no "(D) expected <s n=\"driver\">: $( brief "$D_DOC" )"; fi
if printf '%s' "$D_DOC" | grep -q 'source_joint='; then no "(D) source_joint= printed beside a real source joint"; else ok "(D) no source_joint= when a source joint exists"; fi

# ── E) a source joint the old tie-break lost to a test ───────────────────────────────────────────────────
E_DOC="$( "$BIN" "$TIE" --no-cache --connect=planIt,applyIt 2>/dev/null )" || no "E_DOC: ripwire exited $?"
if [ "$( steinerOf "$E_DOC" )" = "driver" ]; then
    ok "(E) the source joint driver (connects 7) wins over the test testBoth (connects 2)"
else
    no "(E) expected the source joint driver, got '$( steinerOf "$E_DOC" )': $( brief "$E_DOC" )"
fi
if printf '%s' "$E_DOC" | grep -q 'source_joint='; then no "(E) source_joint= printed though a source joint exists"; else ok "(E) no source_joint= (a source joint was found)"; fi

# ── F) a test terminal keeps its test joint ──────────────────────────────────────────────────────────────
F_DOC="$( "$BIN" "$TT" --no-cache --connect=helperT,applyIt 2>/dev/null )" || no "F_DOC: ripwire exited $?"
if [ "$( steinerOf "$F_DOC" )" = "testDriver" ]; then
    ok "(F) with a test terminal, the test joint testDriver is still printed"
else
    no "(F) expected <s n=\"testDriver\"> for a test terminal: $( brief "$F_DOC" )"
fi
if printf '%s' "$F_DOC" | grep -q 'source_joint='; then no "(F) source_joint= printed for a test terminal"; else ok "(F) no source_joint= for a test terminal"; fi

# ── I) the evidence joins what the source search left apart ─────────────────────────────────────────────
I_DOC="$( "$BIN" "$XC" --no-cache --connect=planIt,applyIt,cIt,dIt 2>/dev/null )" || no "I_DOC: ripwire exited $?"
iPrem=0
printf '%s' "$I_DOC" | grep -q '<g terminals="2"><t n="planIt"' && iPrem=$(( iPrem + 1 ))
[ "$( printf '%s' "$I_DOC" | grep -o '<unconnected radius=' | wc -l | tr -d ' ' )" = 2 ] && iPrem=$(( iPrem + 1 ))
if [ "$iPrem" -eq 2 ]; then
    ok "(I) premise: planIt/applyIt joined through source, cIt and dIt <unconnected> ($iPrem/2)"
else
    no "(I) premise: expected one source group of planIt/applyIt and two <unconnected> rows ($iPrem/2): $( brief "$I_DOC" )"
fi
if printf '%s' "$I_DOC" | grep -q '<connect [^>]*test_joint="cdTest" test_joint_p="test/core_test.cpp:3"'; then
    ok "(I) test_joint= names cdTest, the test that joins the <unconnected> cIt/dIt"
else
    no "(I) test_joint= is not cdTest (evidence unrelated to the <unconnected> terminals?): $( brief "$I_DOC" )"
fi

# ── K) the evidence is the test on a leg that crosses source components ─────────────────────────────────
K_DOC="$( "$BIN" "$XL" --no-cache --connect=planIt,applyIt,cIt 2>/dev/null )" || no "K_DOC: ripwire exited $?"
if printf '%s' "$K_DOC" | grep -q '<g terminals="2"><t n="planIt"' && printf '%s' "$K_DOC" | grep -q '<unconnected radius='; then
    ok "(K) premise: planIt/applyIt joined through source, cIt <unconnected>"
else
    no "(K) premise: expected a source group of planIt/applyIt and cIt <unconnected>: $( brief "$K_DOC" )"
fi
if printf '%s' "$K_DOC" | grep -q '<connect [^>]*test_joint="bcTest" test_joint_p="test/core_test.cpp:3"'; then
    ok "(K) test_joint= names bcTest, the test on the leg to the <unconnected> cIt"
else
    no "(K) test_joint= is not bcTest (a test from a source-joined leg?): $( brief "$K_DOC" )"
fi

# ── L) a many-definition terminal is chosen on the source-only view ───────────────────────────────────────
L_DOC="$( "$BIN" "$MD" --no-cache --connect=planIt,runIt 2>/dev/null )" || no "L_DOC: ripwire exited $?"
lPrem=0
MD_CALLERS="$( "$BIN" "$MD" --no-cache --callers=planIt 2>/dev/null )" || no "(L) premise: --callers=planIt exited $?"
for t in d1 pTest; do printf '%s' "$MD_CALLERS" | grep -q "$t" && lPrem=$(( lPrem + 1 )); done
if [ "$lPrem" -eq 2 ]; then ok "(L) premise: planIt is called by d1 (source) and pTest (test)"; else no "(L) premise: planIt callers lack d1/pTest ($lPrem/2)"; fi
if printf '%s' "$L_DOC" | grep -q '<g terminals="2">' && ! printf '%s' "$L_DOC" | grep -q 'test_joint='; then
    ok "(L) planIt and runIt joined through source, no test_joint="
else
    no "(L) runIt was chosen on the unrestricted view (test-joined definition): $( brief "$L_DOC" )"
fi

# ── N) of two qualifying tests, test_joint= is the first by content (path, line, name), stable under a rename ──────────
# CONNECT-TESTJOINT-CONTENT-KEY (CodeRabbit #625 4546683506): the tie-break keys on graph.h symbolContentKey, NodeId only on
# a full tie. Measured 2026-11-14: NodeId order already follows (sorted path, line, name), so no fixture separates the two
# keys today and this arm is green on main too; it pins the contract so a future id reorder cannot move the named test.
TJ="$TMP/twotests";     mksrc "$TJ"
printf 'void unrelatedIt() {}\n' > "$TJ/src/zz_unrelated.cpp"
printf 'void planIt(); void applyIt();\nvoid mTest() { planIt(); applyIt(); }\n' > "$TJ/test/m_test.cpp"
printf 'void planIt(); void applyIt();\nvoid kTest() { planIt(); applyIt(); }\n' > "$TJ/test/k_test.cpp"
tjOf(){ printf '%s' "$1" | grep -o '<connect [^>]*test_joint="[^"]*" test_joint_p="[^"]*"' | sed 's/.*test_joint=/test_joint=/'; }
N_DOC="$( "$BIN" "$TJ" --no-cache --connect=planIt,applyIt 2>/dev/null )" || no "(N) before the rename: ripwire exited $?"
N_BEFORE="$( tjOf "$N_DOC" )"
mv "$TJ/src/zz_unrelated.cpp" "$TJ/src/aa_unrelated.cpp"
N_DOC="$( "$BIN" "$TJ" --no-cache --connect=planIt,applyIt 2>/dev/null )" || no "(N) after the rename: ripwire exited $?"
N_AFTER="$( tjOf "$N_DOC" )"
rm "$TJ/test/k_test.cpp"
N_DOC="$( "$BIN" "$TJ" --no-cache --connect=planIt,applyIt 2>/dev/null )" || no "(N) mTest alone: ripwire exited $?"
N_ONE="$( tjOf "$N_DOC" )"
if [ "$N_ONE" = 'test_joint="mTest" test_joint_p="test/m_test.cpp:2"' ]; then
    ok "(N) premise: mTest alone qualifies too (the pair is a real tie between two tests)"
else
    no "(N) premise: with kTest removed, expected mTest as test_joint, got [$N_ONE]"
fi
if [ "$N_BEFORE" = 'test_joint="kTest" test_joint_p="test/k_test.cpp:2"' ] && [ "$N_AFTER" = "$N_BEFORE" ]; then
    ok "(N) the first test by content (test/k_test.cpp) is named, before and after renaming an unrelated file"
else
    no "(N) expected kTest (test/k_test.cpp:2) before and after the rename, got [$N_BEFORE] then [$N_AFTER]"
fi

# ── G) legend ────────────────────────────────────────────────────────────────────────────────────────────
for lbl in full default; do
    [ "$lbl" = full ] && doc="$A_FULL" || doc="$A_DEF"
    leg="$( printf '%s' "$doc" | sed 's/<connect .*//' )"
    for a in 'source_joint=' 'test_joint=' 'test_joint_p='; do
        if printf '%s' "$leg" | grep -qF "$a"; then ok "(G) $lbl legend defines $a"; else no "(G) $lbl legend lacks $a"; fi
    done
done
# J) the reading names an undirected join, never a caller of both
for lbl in full default; do
    [ "$lbl" = full ] && doc="$A_FULL" || doc="$A_DEF"
    clause="$( printf '%s' "$doc" | sed 's/<connect .*//' | grep -oE 'test_joint=/test_joint_p=[^;]*' | head -1 )"
    case "$clause" in
        '') no "(J) $lbl legend: no test_joint=/test_joint_p= reading to judge";;
        *'call them together'*|*'calls them together'*) no "(J) $lbl legend claims the test calls both: $clause";;
        *through*) ok "(J) $lbl legend reads the test as a node the search joins them through";;
        *) no "(J) $lbl legend: the test_joint reading does not say the join runs through the test: $clause";;
    esac
done
if printf '%s' "$D_DOC" | sed 's/<connect .*//' | grep -qF 'source_joint='; then no "(G) the source_joint= clause rides an answer that does not carry it"; else ok "(G) the clause is present-only (absent with a source joint)"; fi

# ── H) determinism + well-formedness ─────────────────────────────────────────────────────────────────────
"$BIN" "$TONLY" --no-cache --connect=planIt,applyIt >"$TMP/d1" 2>&1 || no "(H) run 1: ripwire exited $?"
"$BIN" "$TONLY" --no-cache --connect=planIt,applyIt >"$TMP/d2" 2>&1 || no "(H) run 2: ripwire exited $?"
"$BIN" "$TONLY" --no-cache --connect=planIt,applyIt >"$TMP/d3" 2>&1 || no "(H) run 3: ripwire exited $?"
if cmp -s "$TMP/d1" "$TMP/d2" && cmp -s "$TMP/d2" "$TMP/d3"; then ok "(H) 3 runs byte-identical"; else no "(H) non-deterministic"; fi
if command -v xmllint >/dev/null 2>&1; then
    xmlBad=0
    for d in "$A_FULL" "$A_DEF" "$D_DOC" "$E_DOC" "$F_DOC"; do
        if ! printf '%s' "$d" | xmllint --noout - 2>/dev/null; then xmlBad=$(( xmlBad + 1 )); no "(H) malformed xml: $( brief "$d" )"; fi
    done
    if [ "$xmlBad" -eq 0 ]; then ok "(H) xmllint pass over the five answers"; fi
fi

# ── M) mutations ─────────────────────────────────────────────────────────────────────────────────────────
MUT="$( printf '%s' "$A_FULL" | sed 's/<unconnected/<s n="testBoth" t="fn"\/><unconnected/' )"
if printf '%s' "$MUT" | grep -q '<s n="testBoth"'; then ok "(M) mutation (test joint printed) trips (A)"; else no "(M) mutation not seen by (A)"; fi
MUT="$( printf '%s' "$A_FULL" | sed 's/ source_joint="none"//g' )"
if printf '%s' "$MUT" | grep -q '<connect [^>]*source_joint="none"'; then no "(M) mutation (disclosure dropped) passes (A)"; else ok "(M) mutation (disclosure dropped) trips (A)"; fi
MUT="$( printf '%s' "$E_DOC" | sed 's/<s n="driver"/<s n="testBoth"/' )"
if [ "$( steinerOf "$MUT" )" = "driver" ]; then no "(M) mutation (test wins tie) passes (E)"; else ok "(M) mutation (test wins tie) trips (E)"; fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "SOME FAILED"; fi
exit "$fail"
