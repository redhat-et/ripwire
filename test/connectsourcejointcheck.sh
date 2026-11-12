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
ok(){ printf '  PASS  %s\n' "$*"; }
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

TT="$TMP/testterm";     mksrc "$TT"
printf 'void helperT() {}\nvoid applyIt();\nvoid testDriver() { helperT(); applyIt(); }\n' > "$TT/test/helper_test.cpp"

# ── P) premise: the test-only joint exists (the test calls both terminals) ───────────────────────────────
premise=0
for t in planIt applyIt; do
    "$BIN" "$TONLY" --no-cache --callers="$t" 2>/dev/null | grep -q 'testBoth' && premise=$(( premise + 1 ))
done
[ "$premise" -eq 2 ] && ok "(P) premise: testBoth calls both terminals (seen by --callers on each: $premise/2)" \
                     || no "(P) premise: testBoth is not a caller of both terminals ($premise/2) — the negative arms below would be vacuous"
premTie=0
for t in planIt applyIt; do
    "$BIN" "$TIE" --no-cache --callers="$t" 2>/dev/null | grep -q 'testBoth' && premTie=$(( premTie + 1 ))
done
[ "$premTie" -eq 2 ] && ok "(P) premise: tie fixture's testBoth calls both terminals ($premTie/2)" \
                     || no "(P) premise: tie fixture's testBoth calls $premTie/2 terminals"

# ── A) CLI --connect, test-only joint ──────────────────────────────────────────────────────────────────
checkTestOnly(){   # $1 label, $2 document
    if printf '%s' "$2" | grep -q '<s n="testBoth"'; then
        no "($1) the test function is printed as the joint of two source terminals: $( brief "$2" )"
    else
        ok "($1) no <s> row names the test function testBoth"
    fi
    printf '%s' "$2" | grep -q '<connect [^>]*source_joint="none"' \
        && ok "($1) the root says source_joint=\"none\"" || no "($1) no source_joint=\"none\" on the root: $( brief "$2" )"
    printf '%s' "$2" | grep -q '<connect [^>]*test_joint="testBoth" test_joint_p="test/core_test.cpp:2"' \
        && ok "($1) the test is named as test-only evidence (test_joint= test_joint_p=)" || no "($1) test_joint=/test_joint_p= missing: $( brief "$2" )"
    printf '%s' "$2" | grep -q '<unconnected radius=' \
        && ok "($1) the terminals are reported <unconnected> (no source joint within radius)" || no "($1) no <unconnected> row: $( brief "$2" )"
}
A_FULL="$( "$BIN" "$TONLY" --no-cache --connect=planIt,applyIt --legend=full 2>/dev/null )"
A_DEF="$( "$BIN" "$TONLY" --no-cache --connect=planIt,applyIt 2>/dev/null )"
checkTestOnly "A" "$A_FULL"

# ── B) --for's <graph_verb> block ────────────────────────────────────────────────────────────────────────
B_DOC="$( "$BIN" "$TONLY" --no-cache --for='common caller of planIt and applyIt' 2>/dev/null )"
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
    C_DOC="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$CMSG" | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
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
D_DOC="$( "$BIN" "$SJ" --no-cache --connect=planIt,applyIt 2>/dev/null )"
[ "$( steinerOf "$D_DOC" )" = "driver" ] && ok "(D) a source joint (driver) still prints as <s>" || no "(D) expected <s n=\"driver\">: $( brief "$D_DOC" )"
printf '%s' "$D_DOC" | grep -q 'source_joint=' && no "(D) source_joint= printed beside a real source joint" || ok "(D) no source_joint= when a source joint exists"

# ── E) a source joint the old tie-break lost to a test ───────────────────────────────────────────────────
E_DOC="$( "$BIN" "$TIE" --no-cache --connect=planIt,applyIt 2>/dev/null )"
[ "$( steinerOf "$E_DOC" )" = "driver" ] && ok "(E) the source joint driver (connects 7) wins over the test testBoth (connects 2)" \
                                         || no "(E) expected the source joint driver, got '$( steinerOf "$E_DOC" )': $( brief "$E_DOC" )"
printf '%s' "$E_DOC" | grep -q 'source_joint=' && no "(E) source_joint= printed though a source joint exists" || ok "(E) no source_joint= (a source joint was found)"

# ── F) a test terminal keeps its test joint ──────────────────────────────────────────────────────────────
F_DOC="$( "$BIN" "$TT" --no-cache --connect=helperT,applyIt 2>/dev/null )"
[ "$( steinerOf "$F_DOC" )" = "testDriver" ] && ok "(F) with a test terminal, the test joint testDriver is still printed" \
                                              || no "(F) expected <s n=\"testDriver\"> for a test terminal: $( brief "$F_DOC" )"
printf '%s' "$F_DOC" | grep -q 'source_joint=' && no "(F) source_joint= printed for a test terminal" || ok "(F) no source_joint= for a test terminal"

# ── G) legend ────────────────────────────────────────────────────────────────────────────────────────────
for lbl in full default; do
    [ "$lbl" = full ] && doc="$A_FULL" || doc="$A_DEF"
    leg="$( printf '%s' "$doc" | sed 's/<connect .*//' )"
    for a in 'source_joint=' 'test_joint=' 'test_joint_p='; do
        printf '%s' "$leg" | grep -qF "$a" && ok "(G) $lbl legend defines $a" || no "(G) $lbl legend lacks $a"
    done
done
printf '%s' "$D_DOC" | sed 's/<connect .*//' | grep -qF 'source_joint=' \
    && no "(G) the source_joint= clause rides an answer that does not carry it" || ok "(G) the clause is present-only (absent with a source joint)"

# ── H) determinism + well-formedness ─────────────────────────────────────────────────────────────────────
"$BIN" "$TONLY" --no-cache --connect=planIt,applyIt >"$TMP/d1" 2>&1
"$BIN" "$TONLY" --no-cache --connect=planIt,applyIt >"$TMP/d2" 2>&1
"$BIN" "$TONLY" --no-cache --connect=planIt,applyIt >"$TMP/d3" 2>&1
cmp -s "$TMP/d1" "$TMP/d2" && cmp -s "$TMP/d2" "$TMP/d3" && ok "(H) 3 runs byte-identical" || no "(H) non-deterministic"
if command -v xmllint >/dev/null 2>&1; then
    for d in "$A_FULL" "$A_DEF" "$D_DOC" "$E_DOC" "$F_DOC"; do
        printf '%s' "$d" | xmllint --noout - 2>/dev/null || { no "(H) malformed xml: $( brief "$d" )"; }
    done
    ok "(H) xmllint pass over the five answers"
fi

# ── M) mutations ─────────────────────────────────────────────────────────────────────────────────────────
MUT="$( printf '%s' "$A_FULL" | sed 's/<unconnected/<s n="testBoth" t="fn"\/><unconnected/' )"
printf '%s' "$MUT" | grep -q '<s n="testBoth"' && ok "(M) mutation (test joint printed) trips (A)" || no "(M) mutation not seen by (A)"
MUT="$( printf '%s' "$A_FULL" | sed 's/ source_joint="none"//' )"
printf '%s' "$MUT" | grep -q '<connect [^>]*source_joint="none"' && no "(M) mutation (disclosure dropped) passes (A)" || ok "(M) mutation (disclosure dropped) trips (A)"
MUT="$( printf '%s' "$E_DOC" | sed 's/<s n="driver"/<s n="testBoth"/' )"
[ "$( steinerOf "$MUT" )" = "driver" ] && no "(M) mutation (test wins tie) passes (E)" || ok "(M) mutation (test wins tie) trips (E)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
