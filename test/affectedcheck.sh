#!/usr/bin/env bash
# affectedcheck.sh — gate for --affected=F1,F2 (ZERO prior coverage). Contract (from --help): "test files
# that transitively reach the changed files (run these)". This is the "which tests do I run for this diff"
# verb — a false negative (missing a test that DOES cover the change) is the dangerous failure mode, so the
# gate pins an EXACT set, not just non-emptiness.
#
# Synthetic corpus (no git history needed — --affected takes the changed set as an argument):
#   src/core.cpp   :  leaf()  ; mid()->leaf()
#   src/other.cpp  :  lonely()               (touched by no test)
#   test/test_mid.cpp   :  test_mid()->mid()   (transitively reaches leaf and mid)
#   test/test_leaf.cpp  :  test_leaf()->leaf() (reaches leaf directly, NOT mid)
#
# Hand-computed expectations:
#   --affected=src/core.cpp           → tests reaching core.cpp's symbols = {test_mid, test_leaf}  (count 2)
#   --affected=src/other.cpp          → lonely() reached by no test = {}                            (count 0)
#   --affected=src/core.cpp changing where ONLY mid is the entry: both tests transitively reach core.cpp
#     (test_leaf reaches leaf() which lives in core.cpp; test_mid reaches mid()) → still 2.
#   Layer detection: a file under test/ must be recognised as a test (that's how --affected knows what a
#   "test file" IS) — if test-file detection breaks, count collapses to 0 and this gate catches it.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/affectedcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "affectedcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src" "$R/test"
printf 'int leaf() { return 1; }\nint mid()  { return leaf(); }\n'  > "$R/src/core.cpp"
printf 'int lonely() { return 0; }\n'                               > "$R/src/other.cpp"
printf 'void test_mid()  { mid();  }\n'                             > "$R/test/test_mid.cpp"
printf 'void test_leaf() { leaf(); }\n'                             > "$R/test/test_leaf.cpp"
# §P9 N5 fixture: two test/*.sh "gates" that invoke a compiled binary as a subprocess (never a graph call
# edge into src/core.cpp/other.cpp) — --affected's reachability walk cannot see these; they exist so the
# script_gates_unmodelled= disclosure has something real to count.
printf '#!/usr/bin/env bash\necho ok\n'                              > "$R/test/gate_one.sh"
printf '#!/usr/bin/env bash\necho ok\n'                              > "$R/test/gate_two.sh"
# §P11.2a — the SYMBOL half of the fixture. Deliberately named so that NO symbol name below is a substring
# of ANY path in this corpus: file interpretation wins by design (§7 below pins that), so a symbol whose
# name happens to appear in a path could never exercise the symbol branch at all.
printf 'int frobnicate() { return 7; }\nint quux() { return frobnicate(); }\n' > "$R/src/widget.cpp"
printf 'void test_one() { frobnicate(); }\n'                        > "$R/test/test_a.cpp"
printf 'void test_two() { quux(); }\n'                              > "$R/test/test_b.cpp"

run(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" "$@" --no-cache 2>/dev/null; }
runec(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" "$@" --no-cache >/dev/null 2>"$TMP/err.txt"; }
# extract the basenames of the emitted <test p="..."/> entries, sorted
tset(){ printf '%s' "$1" | grep -oE '<test p="[^"]*"' | grep -oE '[^/"]*"$' | sed 's/"$//' | sort | tr '\n' ','; }
cnt(){  printf '%s' "$1" | grep -oE 'tests="[0-9]+"' | head -1 | grep -oE '[0-9]+'; }

# ── 1) change core.cpp → exactly the two tests that reach its symbols ────────────────────────────────
A="$( run --affected=src/core.cpp )"
{ [ "$( cnt "$A" )" = 2 ] && [ "$( tset "$A" )" = "test_leaf.cpp,test_mid.cpp," ]; } \
    && ok "--affected=src/core.cpp: exactly {test_leaf.cpp,test_mid.cpp}, tests=2" \
    || no "--affected=src/core.cpp wrong (tests=$( cnt "$A" ) set=$( tset "$A" ))"

# ── 2) change other.cpp (lonely, reached by no test) → empty set, no crash ────────────────────────────
O="$( run --affected=src/other.cpp )"
run --affected=src/other.cpp >/dev/null 2>&1; OEC=$?
{ [ "$( cnt "$O" )" = 0 ] && [ "$OEC" = 0 ]; } \
    && ok "--affected=src/other.cpp: tests=0 (lonely() reached by no test), exit 0" \
    || no "--affected=src/other.cpp wrong (tests=$( cnt "$O" ) exit=$OEC)"

# ── 3) the two results DIFFER — proves --affected genuinely walks reachability per-file, not a constant ─
[ "$( tset "$A" )" != "$( tset "$O" )" ] \
    && ok "--affected discriminates by changed file (core→2 tests, other→0) — not a constant answer" \
    || no "--affected returned the same set for core.cpp and other.cpp — reachability not per-file"

# ── 4) multi-file changed set: src/core.cpp,src/other.cpp → union is still the 2 core tests ───────────
M="$( run --affected=src/core.cpp,src/other.cpp )"
[ "$( tset "$M" )" = "test_leaf.cpp,test_mid.cpp," ] \
    && ok "--affected multi-file (core,other): union = {test_leaf,test_mid}" \
    || no "--affected multi-file wrong set=$( tset "$M" )"

# ── 4b) §P8 seam 2: a pasted `path:line` locator means the same thing as the bare path ────────────────
# --hotspots/--clones/--grep/--lint/--quality-delta all emit `path:line` as their PRIMARY locator, so that
# is the spelling an agent holds when it wants "which tests cover this row?". Both the :N and :N-M shapes
# strip; a path that carries no locator is untouched (checks 1-4 above are the byte-identity witness).
L1="$( run --affected=src/core.cpp:2 )"
L2="$( run --affected=src/core.cpp:1-2 )"
{ [ "$( tset "$L1" )" = "$( tset "$A" )" ] && [ "$( tset "$L2" )" = "$( tset "$A" )" ]; } \
    && ok "--affected=src/core.cpp:2 and :1-2 ≡ --affected=src/core.cpp (locator stripped)" \
    || no "--affected path:line not stripped (:2=$( tset "$L1" ) :1-2=$( tset "$L2" ))"
# …and a NON-locator colon tail is still passed through verbatim (it must not silently become core.cpp)
LX="$( run --affected=src/core.cpp:abc )"
[ "$( cnt "$LX" )" = "" ] || [ "$( cnt "$LX" )" = 0 ] \
    && ok "--affected=src/core.cpp:abc is NOT treated as a locator (no silent strip)" \
    || no "--affected stripped a non-numeric tail (tests=$( cnt "$LX" ))"

# ── 7) §P11.2a: --affected=SYMBOL — "which tests cover symbol X?" (the change-PLANNING question) ─────
# --affected took FILES only, so the question an agent actually has ("I am about to change this function")
# had to be widened to the whole file first, over-reporting the tests. The seed set is now the symbol's
# def(s); everything downstream (transitiveCallers → isTestPath) is the SAME traversal.
#
# The subset law is the gate: a symbol lives IN a file, so the tests reaching the symbol can never exceed
# the tests reaching its file. quux() is covered only by test_b; widget.cpp as a whole by both.
W="$(  run --affected=src/widget.cpp )"
Q="$(  run --affected=quux )"
FR="$( run --affected=frobnicate )"
{ [ "$( cnt "$W" )" = 2 ] && [ "$( tset "$W" )" = "test_a.cpp,test_b.cpp," ]; } \
    && ok "--affected=src/widget.cpp (file): {test_a,test_b}" \
    || no "--affected=src/widget.cpp wrong (tests=$( cnt "$W" ) set=$( tset "$W" ))"
{ [ "$( cnt "$Q" )" = 1 ] && [ "$( tset "$Q" )" = "test_b.cpp," ]; } \
    && ok "--affected=quux (SYMBOL): exactly {test_b.cpp} — a proper non-empty subset of its file's set" \
    || no "--affected=quux wrong (tests=$( cnt "$Q" ) set=$( tset "$Q" ))"
{ [ "$( cnt "$FR" )" = 2 ] && [ "$( tset "$FR" )" = "test_a.cpp,test_b.cpp," ]; } \
    && ok "--affected=frobnicate (SYMBOL): both tests (test_b reaches it through quux) — transitive, not 1-hop" \
    || no "--affected=frobnicate wrong (tests=$( cnt "$FR" ) set=$( tset "$FR" ))"
# seeded_by= must SAY which reading it used — the two readings answer different questions and the counts
# differ, so an undisclosed pick is exactly the §P0 fabricated-confidence shape.
case "$W" in *'seeded_by="file"'*)   ok "--affected file arg discloses seeded_by=\"file\"" ;;
             *) no "--affected=src/widget.cpp does not disclose seeded_by=\"file\": $W" ;; esac
case "$Q" in *'seeded_by="symbol"'*) ok "--affected symbol arg discloses seeded_by=\"symbol\"" ;;
             *) no "--affected=quux does not disclose seeded_by=\"symbol\": $Q" ;; esac

# file:name disambiguates, exactly as it does on --callers/--impact/--around
QF="$( run --affected=src/widget.cpp:quux )"
[ "$( tset "$QF" )" = "test_b.cpp," ] \
    && ok "--affected=src/widget.cpp:quux (file:name) ≡ --affected=quux" \
    || no "--affected file:name form wrong (set=$( tset "$QF" ))"

# ── 7b) the disambiguation rule is FILE-FIRST — pre-§P11 semantics must not move ──────────────────────
# `widget` is a substring of ./src/widget.cpp, so it stays a FILE pattern (it always was one). This is the
# byte-compatibility half of the rule: every argument shape that worked before means the same thing now.
WS="$( run --affected=widget )"
[ "$( tset "$WS" )" = "$( tset "$W" )" ] \
    && ok "--affected=widget still reads as a PATH pattern (file-first rule; old semantics unchanged)" \
    || no "--affected=widget changed meaning (set=$( tset "$WS" ) vs file set $( tset "$W" ))"

# ── 7c) an argument that is NEITHER refuses, naming BOTH readings ─────────────────────────────────────
# The §P0 rule: a lookup that resolves under no interpretation is a refusal, never a confident zero. And
# because two interpretations were tried, the message must name both — otherwise the caller cannot tell a
# path typo from a symbol typo.
runec --affected=zzznotathing; XEC=$?
E="$( cat "$TMP/err.txt" )"
[ "$XEC" = 1 ] && ok "--affected=zzznotathing exits 1 (refusal, not a tests=0)" \
               || no "--affected=zzznotathing exit=$XEC (want 1)"
case "$E" in *file*) FE=1 ;; *) FE=0 ;; esac
case "$E" in *symbol*) SE=1 ;; *) SE=0 ;; esac
{ [ "$FE" = 1 ] && [ "$SE" = 1 ]; } \
    && ok "--affected refusal names BOTH readings (file and symbol): $E" \
    || no "--affected refusal does not name both readings: $E"

# ── 7d) the subset law on the REAL repo (§P11.2a's own worked gate) ──────────────────────────────────
# The synthetic corpus above proves the traversal; this proves it against a corpus with 250+ test files
# and a real C++ call graph, which is the only place a resolver regression (wrong def picked, header/impl
# split lost) would show. connectSubgraph lives in src/graph.h and is exercised by exactly one harness.
# NOTE the qualified spelling: bare `connectSubgraph` is a substring of, so the
# file-first rule reads it as a PATH — that is the rule working, and the reason file:NAME exists.
rrun(){ perl -e 'alarm 60; exec @ARGV' "$BIN" "$ROOT" "$@" 2>/dev/null; }
RF="$( rrun --affected=src/graph.h )"
RS="$( rrun --affected=src/graph.h:connectSubgraph )"
RFS="$( tset "$RF" )"; RSS="$( tset "$RS" )"
subset=1
for t in $( printf '%s' "$RSS" | tr ',' ' ' ); do case ",$RFS" in *",$t,"*) ;; *) subset=0 ;; esac; done
{ [ -n "$RSS" ] && [ "$subset" = 1 ] && [ "$RSS" != "$RFS" ]; } \
    && ok "repo: --affected=src/graph.h:connectSubgraph → non-empty PROPER subset of --affected=src/graph.h ($RSS ⊂ $RFS)" \
    || no "repo subset law broken (symbol set='$RSS' file set='$RFS')"

# ── 5) determinism ───────────────────────────────────────────────────────────────────────────────────
[ "$( run --affected=src/core.cpp )" = "$( run --affected=src/core.cpp )" ] \
    && ok "--affected deterministic (byte-identical run-to-run)" || no "--affected non-deterministic"

# ── 5b) §P9 N5: script_gates_unmodelled= discloses the test/*.sh gates this verb's graph walk can't see ──
# The fixture's two test/*.sh files invoke a compiled binary as a subprocess — never a graph call edge —
# so they can NEVER appear in tests=/reached= no matter what changed. The disclosure count is independent
# of the changed set (it's a corpus-wide fact, not scoped to this query), so it must be the same on both
# core.cpp's and other.cpp's runs even though their tests=/reached= differ.
sgu(){ printf '%s' "$1" | grep -oE 'script_gates_unmodelled="[0-9]+"' | head -1 | grep -oE '[0-9]+'; }
[ "$( sgu "$A" )" = "2" ] \
    && ok "--affected=src/core.cpp: script_gates_unmodelled=\"2\" (the fixture's gate_one.sh/gate_two.sh)" \
    || no "--affected=src/core.cpp: script_gates_unmodelled wrong/missing (got '$( sgu "$A" )')"
[ "$( sgu "$O" )" = "2" ] \
    && ok "--affected=src/other.cpp: script_gates_unmodelled=\"2\" (corpus-wide, not scoped to the changed set)" \
    || no "--affected=src/other.cpp: script_gates_unmodelled differs from core.cpp's run (got '$( sgu "$O" )')"
printf '%s' "$A" | grep -q 'script_gates_unmodelled=' \
    && [ "$( printf '%s' "$A" | grep -c '<test p="gate_one\.sh"/>' )" = "0" ] \
    && [ "$( printf '%s' "$A" | grep -c '<test p="gate_two\.sh"/>' )" = "0" ] \
    && ok "--affected: the .sh gates never appear as <test> rows (invisible to the graph walk, as documented)" \
    || no "--affected: a .sh gate wrongly appeared as a <test> row, or the disclosure attr is missing"

# §A10.7: the legend must match what the CODE does — scriptGatesUnmodelledCount() is a PATH count (every
# test/*.sh file), it never opens a file to check whether it actually invokes the binary. The prior wording
# ("invoke the compiled binary as a subprocess") overclaimed that; the fixed text says "a path count; not
# every one invokes the binary" instead.
printf '%s' "$A" | grep -q 'a path count; not every one invokes the binary' \
    && ok "script_gates_unmodelled= legend matches the code (path count, not content-checked) (§A10.7)" \
    || no "script_gates_unmodelled= legend still overclaims content inspection the code does not do"

# ── 6) xml well-formed ───────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$A" | xmllint --noout - 2>/dev/null && ok "--affected xml well-formed" || no "--affected xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
