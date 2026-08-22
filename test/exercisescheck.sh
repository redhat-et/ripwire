#!/usr/bin/env bash
# exercisescheck.sh — gate for --exercises=TESTFILE.
#
# THE GAP: the test<->code map ran one way only. --affected/--situ/--test-gate answer "which tests reach
# this code"; NOTHING answered the inverse, "what does this test exercise?" — which is the FIRST question
# when a test fails and you have its name and nothing else. It is one BFS over edges the tool already has
# (graph.h forwardReach, the dual of the transitiveCallers --affected uses).
#
# PURELY NEW VERB, so there is no pre-existing behavior to prove red against: on the pre-change binary
# every arm below fails at the flag itself. What the gate therefore has to earn is that the answer is a
# MEASUREMENT rather than a plausible list — hence the hand-computed exact sets, the "not the seeds
# themselves / not the sibling test's code" negative arms, and the two refusals.
#
# Synthetic corpus (hand-computed expectations):
#   src/core.cpp        : leaf() ; mid() -> leaf()
#   src/other.cpp       : lonely()                       (no test calls it)
#   test/test_mid.cpp   : test_mid() -> mid()            exercises {mid, leaf} — transitive, not 1-hop
#   test/test_leaf.cpp  : test_leaf() -> leaf()          exercises {leaf} only
#   test/helper_x.cpp   : helper() -> lonely()           a SECOND test file, so a whole-dir pattern differs
#
# Usage:  bash test/exercisescheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/exercisescheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "exercisescheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src" "$R/test"
printf 'int leaf() { return 1; }\nint mid()  { return leaf(); }\n'  > "$R/src/core.cpp"
printf 'int lonely() { return 0; }\n'                               > "$R/src/other.cpp"
printf 'void test_mid()  { mid();  }\n'                             > "$R/test/test_mid.cpp"
printf 'void test_leaf() { leaf(); }\n'                             > "$R/test/test_leaf.cpp"
printf 'void helper()    { lonely(); }\n'                           > "$R/test/helper_x.cpp"

run(){   perl -e 'alarm 20; exec @ARGV' "$BIN" "$R" "$@" --no-cache 2>/dev/null; }
runec(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$R" "$@" --no-cache >/dev/null 2>"$TMP/err.txt"; }
# the emitted symbol names, sorted+joined — the set this test exercises
sset(){ printf '%s' "$1" | grep -oE '<s [^>]*n="[^"]*"' | grep -oE 'n="[^"]*"$' | sed 's/n="//;s/"//' | sort | tr '\n' ','; }
attr(){ printf '%s' "$2" | grep -oE " $1=\"[^\"]*\"" | head -1 | sed "s/ $1=\"//;s/\"//"; }

# ── 1) the forward answer is exact, transitive, and excludes the test's OWN code ──────────────────────
M="$( run --exercises=test/test_mid.cpp )"
[ "$( sset "$M" )" = "leaf,mid," ] \
    && ok "--exercises=test/test_mid.cpp: exactly {leaf,mid} — transitive (leaf via mid), test_mid itself excluded" \
    || no "--exercises=test/test_mid.cpp wrong set=$( sset "$M" )"

# ── 2) it DISCRIMINATES per test file — test_leaf reaches leaf only ───────────────────────────────────
L="$( run --exercises=test/test_leaf.cpp )"
[ "$( sset "$L" )" = "leaf," ] \
    && ok "--exercises=test/test_leaf.cpp: exactly {leaf} — not a constant answer" \
    || no "--exercises=test/test_leaf.cpp wrong set=$( sset "$L" )"
[ "$( sset "$M" )" != "$( sset "$L" )" ] \
    && ok "--exercises discriminates between two test files in the same directory" \
    || no "--exercises returned the same set for test_mid and test_leaf"

# ── 3) a NON-TEST file refuses, naming the rule AND the alternative verb ──────────────────────────────
# Decided (documented in --help): refuse, do not answer generically. The verb's entire content is the
# test/non-test PARTITION — it SUBTRACTS test code from the answer. On a non-test file that subtraction is
# meaningless, and "everything this file transitively calls" is a different question with its own verbs.
runec --exercises=src/core.cpp; XEC=$?
E="$( cat "$TMP/err.txt" )"
[ "$XEC" = 1 ] && ok "--exercises=src/core.cpp (non-test) exits 1" || no "--exercises non-test exit=$XEC (want 1)"
case "$E" in *test*) TE=1 ;; *) TE=0 ;; esac
case "$E" in *--callees*|*--impact*) AE=1 ;; *) AE=0 ;; esac
{ [ "$TE" = 1 ] && [ "$AE" = 1 ]; } \
    && ok "--exercises non-test refusal names the test-path rule AND an alternative verb: $E" \
    || no "--exercises non-test refusal incomplete: $E"

# ── 4) an argument matching NO indexed path refuses (never a confident empty report) ──────────────────
runec --exercises=zzznotafile; XEC2=$?
E2="$( cat "$TMP/err.txt" )"
[ "$XEC2" = 1 ] \
    && ok "--exercises=zzznotafile exits 1 (refusal, not reaches=0): $E2" \
    || no "--exercises unknown path exit=$XEC2 (want 1)"

# ── 4b) a bare --exercises (no value) refuses loudly instead of falling through to the map ────────────
runec --exercises; XEC3=$?
E3="$( cat "$TMP/err.txt" )"
{ [ "$XEC3" = 1 ] && [ -n "$E3" ]; } \
    && ok "bare --exercises refuses loudly (exit 1): $E3" \
    || no "bare --exercises exit=$XEC3 err='$E3' (want exit 1 + a message)"

# ── 5) --limit is HONORED and disclosed in pageview.h's ONE vocabulary (§P8) ──────────────────────────
P="$( run --exercises=test/test_mid.cpp --limit=1 )"
rows="$( printf '%s' "$P" | grep -o '<s ' | wc -l | tr -d ' ' )"
{ [ "$rows" = 1 ] && [ "$( attr shown "$P" )" = 1 ] && [ "$( attr capped "$P" )" = 1 ] \
  && [ "$( attr total "$P" )" = 2 ] && [ "$( attr has_more "$P" )" = 1 ] && [ "$( attr next_offset "$P" )" = 1 ]; } \
    && ok "--exercises --limit=1: 1 row, shown/capped/total/has_more/next_offset all present and right" \
    || no "--exercises paging wrong (rows=$rows shown=$( attr shown "$P" ) capped=$( attr capped "$P" ) total=$( attr total "$P" ) has_more=$( attr has_more "$P" ) next_offset=$( attr next_offset "$P" ))"
P2="$( run --exercises=test/test_mid.cpp --limit=1 --offset=1 )"
{ [ "$( attr has_more "$P2" )" = 0 ] && [ "$( sset "$P" )$( sset "$P2" )" = "leaf,mid," ]; } \
    && ok "--exercises page 2 is the exact continuation (no row dropped or repeated across the seam)" \
    || no "--exercises offset seam wrong (page1=$( sset "$P" ) page2=$( sset "$P2" ) has_more=$( attr has_more "$P2" ))"

# ── 6) the un-paginated shape discloses its own cap honestly (capped=0 when complete) ─────────────────
[ "$( attr capped "$M" )" = 0 ] \
    && ok "--exercises un-paginated: capped=\"0\" (the listing is complete, said out loud)" \
    || no "--exercises un-paginated capped=$( attr capped "$M" ) (want 0)"

# ── 7) determinism + G4 ──────────────────────────────────────────────────────────────────────────────
[ "$( run --exercises=test/test_mid.cpp )" = "$( run --exercises=test/test_mid.cpp )" ] \
    && ok "--exercises deterministic (byte-identical run-to-run)" || no "--exercises non-deterministic"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$M" | xmllint --noout - 2>/dev/null && ok "--exercises xml well-formed" || no "--exercises xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── 8) the REAL repo: a harness names the src/ symbols it drives ─────────────────────────────────────
# The synthetic corpus proves the traversal; this proves it survives a 250-test-file C++ corpus, where a
# resolver regression (header/impl split, overload set) would actually show.
RR="$( perl -e 'alarm 90; exec @ARGV' "$BIN" "$ROOT" --exercises=test/connectcore_harness.cpp --limit=200 2>/dev/null )"
case "$RR" in *'n="connectSubgraph"'*) ok "repo: --exercises=test/connectcore_harness.cpp names connectSubgraph" ;;
              *) no "repo: --exercises=test/connectcore_harness.cpp does not name connectSubgraph" ;; esac
case "$RR" in *'p="./test/'*) no "repo: --exercises emitted a TEST-path row — the non-test filter is broken" ;;
              *) ok "repo: --exercises emits no test-path rows (the partition holds on a real corpus)" ;; esac

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
