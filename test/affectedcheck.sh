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
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
# F3 (terminality round A, 2026-09-05) — the SUBSTRING-COLLISION half of the fixture. The file reading is a
# path PATTERN (filePathContains), so `geo.cpp` matches BOTH src/geo.cpp and test/check_geo.cpp. Named so the
# collision is unavoidable, and so no OTHER arm's pattern can reach these two files.
printf 'double deg2rad(double d) { return d; }\ndouble haversine(double a) { return deg2rad(a); }\n' > "$R/src/geo.cpp"
printf 'void spec_hav() { haversine(1); }\nvoid spec_deg() { deg2rad(2); }\n'                        > "$R/test/check_geo.cpp"
# H2H-Graft F1 (2026-09-07) — the EVIDENCE-ORDER half of the fixture. Rows used to be path-sorted, so on a
# corpus with 127 reaching tests the one test named after the changed file sat at row ~60 (rocksdb
# db/write_batch.cc -> db/write_batch_test.cc), and a sibling test the graph never reaches at all
# (cache/tiered_secondary_cache.cc -> cache/tiered_secondary_cache_test.cc, which builds the object through a
# factory) was absent. Named so that PATH order is the REVERSE of evidence order: test_afar.cpp sorts before
# test_zdirect.cpp, yet reaches deep() only through via() (hops=2) where test_zdirect calls it directly (hops=1);
# deep_test.cpp is the stem partner of src/deep.cpp and calls nothing in it.
printf 'int deep() { return 3; }\n'                                > "$R/src/deep.cpp"
printf 'int via() { return deep(); }\n'                            > "$R/src/via.cpp"
printf 'void zd() { deep(); }\n'                                   > "$R/test/test_zdirect.cpp"
printf 'void af() { via(); }\n'                                    > "$R/test/test_afar.cpp"
printf 'void unrelated_helper() { }\n'                             > "$R/test/deep_test.cpp"

run(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" "$@" --no-cache 2>/dev/null; }
runec(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" "$@" --no-cache >/dev/null 2>"$TMP/err.txt"; }
# The basenames of the emitted test rows, sorted — through test/testrowpaths.py, THE shared reader, like
# tord() below. This helper was the LAST private reader left in the file the shared reader's own docstring
# names among the six it converted (review of #214), so that claim was false while it stood. It split EVERY
# row's p= on ',' — including a single <test> row's — and a path containing ',' is never grouped (testmap.h
# refuses to, so that p= is one path, not a list), which turned such a row into two names that name nothing.
# The shared reader splits only a QUALIFIED group row and decodes entities, so the two helpers in this file
# can no longer disagree about what a row is.
tset(){ printf '%s' "$1" | python3 "$ROOT/test/testrowpaths.py" paths xml | sed 's|.*/||' | LC_ALL=C sort | tr '\n' ','; }
cnt(){  printf '%s' "$1" | grep -oE 'tests="[0-9]+"' | head -1 | grep -oE '[0-9]+'; }

# ── 1) change core.cpp → exactly the two tests that reach its symbols ────────────────────────────────
# L1 (2026-09-19): the CLI default legend is compact; $A and $COLL feed arms that read the FULL legend's prose, so they ask for it.
A="$( run --affected=src/core.cpp --legend=full )"
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

# ── F3) a pattern that also matches a TEST file must not swallow the answer ──────────────────────────
# The file reading is a substring PATTERN, so one item can match several files. When one of them is a TEST
# file, its own symbols used to enter the seed set — and transitiveCallers returns "reached, minus the
# seeds", so the very tests that reach the change were subtracted out of their own answer. `--affected=geo.py`
# reported seeds="6" tests="0" reached="0" on a corpus where `--affected=./geo.py` reported reached="1"
# (lane-L8 2026-09-04, found-not-fixed #1): a confidently wrong ZERO, in the verb whose entire job is telling
# an agent which tests to run. A test file cannot "reach" a change it is part of; it is in the answer because
# the argument MATCHED it, which is a different fact and is labelled as one.
CTRL="$( run --affected=src/geo.cpp )"       # unambiguous: matches src/geo.cpp only
COLL="$( run --affected=geo.cpp --legend=full )"           # matches src/geo.cpp AND test/check_geo.cpp
ONLYT="$( run --affected=check_geo.cpp )"    # matches the TEST file alone
attr(){ printf '%s' "$2" | grep -oE "$1=\"[0-9]+\"" | head -1 | grep -oE '[0-9]+'; }

[ "$( cnt "$CTRL" )" = 1 ] && [ "$( tset "$CTRL" )" = "check_geo.cpp," ] \
    && ok "(F3 control) --affected=src/geo.cpp: tests=1 {check_geo.cpp}, reached=$( attr reached "$CTRL" )" \
    || no "(F3 control) --affected=src/geo.cpp wrong (tests=$( cnt "$CTRL" ) set=$( tset "$CTRL" )) — the fixture itself is broken"

{ [ "$( cnt "$COLL" )" = "$( cnt "$CTRL" )" ] && [ "$( tset "$COLL" )" = "$( tset "$CTRL" )" ] && [ "$( attr reached "$COLL" )" = "$( attr reached "$CTRL" )" ]; } \
    && ok "(F3) --affected=geo.cpp answers the same tests/reached as the unambiguous spelling (the test-file match no longer absorbs the seeds)" \
    || no "(F3) --affected=geo.cpp disagrees with --affected=src/geo.cpp: tests=$( cnt "$COLL" )/$( cnt "$CTRL" ) reached=$( attr reached "$COLL" )/$( attr reached "$CTRL" ) set=$( tset "$COLL" )/$( tset "$CTRL" )"

{ [ -n "$( attr seeds "$COLL" )" ] && [ "$( attr seeds "$COLL" )" -gt "$( attr seeds "$CTRL" )" ]; } \
    && ok "(F3 non-vacuity) the collision spelling really does match more files (seeds=$( attr seeds "$COLL" ) vs $( attr seeds "$CTRL" ))" \
    || no "(F3 non-vacuity) seeds= did not grow under the colliding pattern (=$( attr seeds "$COLL" )) — the arm above proves nothing"

[ "$( attr seed_test_files "$COLL" )" = "1" ] \
    && ok "(F3 disclosure) the root says seed_test_files=\"1\" — the argument matched a test file" \
    || no "(F3 disclosure) root carries no honest seed_test_files= (got '$( attr seed_test_files "$COLL" )')"
[ "$( attr seed_test_files "$CTRL" )" = "0" ] \
    && ok "(F3 disclosure) the unambiguous spelling says seed_test_files=\"0\" (a zero that means none matched)" \
    || no "(F3 disclosure) seed_test_files= is not 0 on a pattern that matches no test file (got '$( attr seed_test_files "$CTRL" )')"

printf '%s' "$COLL" | grep -q '<test p="[^"]*check_geo\.cpp" seed_kind="test"' \
    && ok "(F3 row) the matched test file's row carries seed_kind=\"test\" — it is here because it CHANGED, not because it reaches the change" \
    || no "(F3 row) the matched test file's row has no seed_kind=\"test\" label"
printf '%s' "$CTRL" | grep -q '<test [^>]*seed_kind=' \
    && no "(F3 row) a row that was only REACHED wrongly carries seed_kind=" \
    || ok "(F3 row) a merely-reached test row carries no seed_kind= (the label means matched-as-a-seed)"

{ [ "$( cnt "$ONLYT" )" = 1 ] && [ "$( attr reached "$ONLYT" )" = "0" ]; } \
    && ok "(F3 test-only) a pattern matching ONLY a test file answers tests=1 (run it — it changed), reached=0" \
    || no "(F3 test-only) --affected=check_geo.cpp answered tests=$( cnt "$ONLYT" ) reached=$( attr reached "$ONLYT" ) — a changed test that must be run reported as no tests"

# the honesty rule this whole arm exists for: tests="0" while a test file absorbed the seeds is the silent zero.
{ [ "$( cnt "$COLL" )" = "0" ] && [ "$( attr seed_test_files "$COLL" )" != "0" ]; } \
    && no "(F3 silent zero) tests=\"0\" on an argument that matched a test file — exactly the confidently-wrong zero this arm gates" \
    || ok "(F3 silent zero) no tests=\"0\" answer while seed_test_files= is non-zero"

for a in seed_test_files seed_kind; do
    printf '%s' "$COLL" | sed 's/-->.*//' | grep -q "$a=" \
        && ok "(F3 legend) the first-screen legend defines $a=" \
        || no "(F3 legend) $a= is emitted but undefined in the legend a reader meets first"
done

# ── 7) H2H-Graft F1: rows in EVIDENCE order, stem partner first, hops= disclosed ──────────────────────
# Ordered basenames (NOT sorted — the order IS the claim).
# E1: the files named, in EMITTED order (a <g> row contributes its members in place) — through the shared
# reader, so this gate and the eight others that ask the same question cannot disagree about what a row is.
tord(){ printf '%s' "$1" | python3 "$ROOT/test/testrowpaths.py" paths xml | sed 's|.*/||' | tr '\n' ','; }
D="$( run --affected=src/deep.cpp )"
[ "$( tord "$D" )" = "deep_test.cpp,test_zdirect.cpp,test_afar.cpp," ] && [ "$( cnt "$D" )" = 3 ] \
    && ok "(7a) --affected=src/deep.cpp: partner first, then hops asc — deep_test, test_zdirect(1), test_afar(2); tests=3" \
    || no "(7a) evidence order wrong (tests=$( cnt "$D" ) order=$( tord "$D" ))"
printf '%s' "$D" | grep -q '<test p="test/deep_test.cpp" partner="1"' \
    && ok "(7b) the stem partner row carries partner=\"1\"" || no "(7b) deep_test.cpp row lacks partner=\"1\""
printf '%s' "$D" | grep -qE '<test p="test/deep_test.cpp" partner="1"[^>]*hops=' \
    && no "(7c) a partner the graph never reaches must carry NO hops= (a zero would be a fake edge)" \
    || ok "(7c) unreached partner carries no hops="
printf '%s' "$D" | grep -q '<test p="test/test_zdirect.cpp" hops="1"' && printf '%s' "$D" | grep -q '<test p="test/test_afar.cpp" hops="2"' \
    && ok "(7d) hops= is the caller-walk depth: zdirect 1, afar 2" || no "(7d) hops= values wrong"
printf '%s' "$D" | grep -q '<affected [^>]*order="evidence"' && printf '%s' "$D" | grep -q '<affected [^>]*partners="1"' \
    && ok "(7e) root says order=\"evidence\" partners=\"1\"" || no "(7e) root lacks order=/partners="
# negative: no stem partner exists for core.cpp, so no row may claim one
printf '%s' "$A" | grep -q 'partner="1"' && no "(7f) core.cpp has no *_test partner yet a row claims partner=\"1\"" \
    || ok "(7f) partner= never fires without a stem match"
# E1 (2026-09-12): with no derivable runner the direct test rides a <g hops="1" n= p="…"/> group row when a
# sibling shares its evidence, and a single <test p= hops="1"> row otherwise — hops="1" is asserted either way.
printf '%s' "$A" | grep -qE '<test p="test/test_leaf\.cpp" hops="1"|<g hops="1" n="[0-9]+" p="([^"]*,)?test/test_leaf\.cpp(,[^"]*)?"' \
    && ok "(7g) core.cpp's direct test row carries hops=\"1\"" \
    || no "(7g) core.cpp rows lack hops="

# ── 7h) the RUN-FIRST head (comparison table hono-20 / textual-20) ─────────────────────────────────────
# A tests-to-run answer listed 80-249 files by evidence, and nothing marked which rows carry the most direct evidence:
# textual's snapshot test sat inside an undifferentiated tier of 157. run_first=N marks the head of the evidence order
# — every changed/partner/hops=1 row, or when none exists the rows at the smallest hops= — as a RUN ORDER, never a skip
# list (the walk is name-based; the rest can still exercise the change), and the rest stays listed (no drop).
# RED on main 953818d6: no run_first= anywhere. (7p) pins the "not a skip list" reading in the legend that carries it.
printf 'int farleaf() { return 9; }\n'                            > "$R/src/farleaf.cpp"
printf 'int farbridge() { return farleaf(); }\nint farbridge2() { return farbridge(); }\n' > "$R/src/farbridge.cpp"
printf 'void nf_one() { farbridge(); }\n'                         > "$R/test/test_nfone.cpp"
printf 'void nf_two() { farbridge2(); }\n'                        > "$R/test/test_nftwo.cpp"
D="$( run --affected=src/deep.cpp )"
printf '%s' "$D" | grep -q '<affected [^>]*run_first="2"' \
    && ok "(7h) --affected=src/deep.cpp: run_first=\"2\" — the partner and the hops=1 row, ahead of hops=2" \
    || no "(7h) expected run_first=\"2\" on the --affected root, got: $( printf '%s' "$D" | grep -o '<affected [^>]*>' )"
FAR="$( run --affected=src/farleaf.cpp )"
if printf '%s' "$FAR" | grep -q '<affected [^>]*run_first="1"' && [ "$( tord "$FAR" )" = "test_nfone.cpp,test_nftwo.cpp," ]; then
    ok "(7i) no partner or hops=1 row: the nearest hop tier (test_nfone, hops=2) is the run-first tier, hops=3 still listed"
else
    no "(7i) expected run_first=\"1\" over test_nfone,test_nftwo; got $( printf '%s' "$FAR" | grep -o '<affected [^>]*>' ) order=$( tord "$FAR" )"
fi
printf '%s' "$( run --affected=src/via.cpp )" | grep -q 'run_first=' \
    && no "(7j) a list that is ALL run-first carries run_first= (it splits nothing)" \
    || ok "(7j) a list whose every row is run-first carries no run_first= (it splits nothing)"
printf '%s' "$D" | sed 's/-->.*//' | grep -q 'run_first=N' \
    && ok "(7k) the legend defines run_first= in the answer that carries it" \
    || no "(7k) run_first= emitted without its legend clause"
printf '%s' "$D" | sed 's/-->.*//' | grep -q 'not a skip list' \
    && ok "(7p) the run_first= reading says it is a run order, not a skip list" \
    || no "(7p) the run_first= legend lost 'not a skip list' — the head would read as the whole obligation"
TG="$( run --test-gate=src/deep.cpp )"
printf '%s' "$TG" | grep -q '<test-gate [^>]*run_first="2"' \
    && ok "(7l) --test-gate=src/deep.cpp carries the same run_first=\"2\"" \
    || no "(7l) --test-gate root lacks run_first=\"2\": $( printf '%s' "$TG" | grep -o '<test-gate [^>]*>' )"
printf '%s' "$TG" | sed 's/-->.*//' | grep -q 'run_first=N' \
    && ok "(7m) the --test-gate legend defines run_first=" || no "(7m) --test-gate emits run_first= undefined"
run --test-gate=src/deep.cpp --json | grep -q '"run_first":2' \
    && ok "(7n) --test-gate --json carries \"run_first\":2" || no "(7n) --test-gate --json lacks run_first"
AF_MCP="$( printf '%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"affected","arguments":{"path":"'"$R"'","files":"src/deep.cpp"}}}' \
    | perl -e 'alarm 30; exec @ARGV' "$BIN" "$R" --mcp --no-cache 2>/dev/null | tail -1 )"
printf '%s' "$AF_MCP" | grep -q 'run_first=\\"2\\"' \
    && ok "(7o) the MCP affected twin carries run_first=\"2\" (one renderer)" \
    || { no "(7o) the MCP affected twin lacks run_first"; printf '%s\n' "$AF_MCP" | cut -c1-300; }
rm -f "$R/src/farleaf.cpp" "$R/src/farbridge.cpp" "$R/test/test_nfone.cpp" "$R/test/test_nftwo.cpp"

# ── 8) issue #60: a call with no enclosing NAMED function is still a call ─────────────────────────────
# @YogevKr's reproduction, verbatim in shape: a node:test arrow callback calls the changed function, and
# the test file's name does not share the source file's stem, so the filename-partner fallback cannot fire.
# The CONTROL is the same assertion moved into a named function — the contrast that isolated the defect.
# Before ingest_model.h mintModuleScopeOwners the callback arm read tests="0" and the named arm tests="1";
# both must now read 1, and they must agree, because the two source shapes mean the same thing.
echo "=== (8) #60: an arrow-callback call and a named-function call give the SAME tests ==="
T60="$TMP/issue60"; mkdir -p "$T60/arrow/src" "$T60/arrow/test" "$T60/named/src" "$T60/named/test"
for v in arrow named; do
    printf 'export function bounded(text: string): string {\n  return text.replace(/x/g, "");\n}\n' > "$T60/$v/src/bounded.ts"
done
printf 'import test from "node:test";\nimport assert from "node:assert/strict";\nimport { bounded } from "../src/bounded.ts";\ntest("bounded removes x", () => { assert.equal(bounded("x value"), " value"); });\n' > "$T60/arrow/test/behavior.test.ts"
printf 'import test from "node:test";\nimport assert from "node:assert/strict";\nimport { bounded } from "../src/bounded.ts";\nfunction checkBounded() { assert.equal(bounded("x value"), " value"); }\ntest("bounded removes x", checkBounded);\n' > "$T60/named/test/behavior.test.ts"
AR="$( "$BIN" "$T60/arrow" --no-cache --affected=src/bounded.ts 2>/dev/null )"
NA="$( "$BIN" "$T60/named" --no-cache --affected=src/bounded.ts 2>/dev/null )"
arrowTests="$( attr tests "$AR" )"; namedTests="$( attr tests "$NA" )"
[ "$namedTests" = 1 ] && ok "(8) the named-function control still reports tests=\"1\"" \
    || no "(8) the named-function control reports tests=\"${namedTests:-absent}\" — the contrast proves nothing"
[ "$arrowTests" = 1 ] && ok "(8) the arrow-callback arm reports tests=\"1\" (the pre-#60 binary reports 0)" \
    || no "(8) the arrow-callback arm reports tests=\"${arrowTests:-absent}\", expected 1"
[ "$arrowTests" = "$namedTests" ] && ok "(8) both source shapes give the SAME tests= ($arrowTests)" \
    || no "(8) arrow=$arrowTests named=$namedTests — the two shapes still disagree"
printf '%s' "$AR" | grep -q 'p="test/behavior\.test\.ts"' \
    && ok "(8) the arrow arm NAMES test/behavior.test.ts, whose stem never matches bounded.ts" \
    || no "(8) the arrow arm reports a count but not the file: $AR"
# --test-gate must FAIL (exit 4) while that test is not in the run set — the verb an agent acts on.
"$BIN" "$T60/arrow" --no-cache --test-gate=src/bounded.ts >"$TMP/tg60.xml" 2>/dev/null
tgrc=$?
[ "$tgrc" = 4 ] && ok "(8) --test-gate exits 4 on the arrow arm: the test to run is named, not silently zero" \
    || no "(8) --test-gate exited $tgrc on the arrow arm, expected 4"
grep -q 'behavior\.test\.ts' "$TMP/tg60.xml" \
    && ok "(8) --test-gate names test/behavior.test.ts as the test to run" \
    || no "(8) --test-gate exits non-zero but never names the test: $( head -c 400 "$TMP/tg60.xml" )"

# ── 8b) issue #60, @alex-michaud's arm: the same root cause in ORDINARY PRODUCTION code ───────────────
# No test file, no test framework: a module top-level call is framework registration / DI wiring / route
# setup, and --callers and --impact both used to be one short. The named-function call in the same file is
# the control: it was always counted, and it must still be.
echo "=== (8b) #60: a module top-level call is a caller ==="
P60="$TMP/issue60prod/src"; mkdir -p "$P60"
printf 'export function setPhase(phase: string): void {\n  console.log(phase)\n}\n' > "$P60/lifecycle.ts"
printf "import { setPhase } from './lifecycle'\n\nexport function boot(): void {\n  setPhase('booting')\n}\n\nsetPhase('starting')\n" > "$P60/index.ts"
CA="$( "$BIN" "$TMP/issue60prod" --no-cache --callers=setPhase 2>/dev/null )"
IM="$( "$BIN" "$TMP/issue60prod" --no-cache --impact=setPhase 2>/dev/null )"
[ "$( attr count "$CA" )" = 2 ] && ok "(8b) --callers=setPhase count=\"2\" (the pre-#60 binary reports 1)" \
    || no "(8b) --callers=setPhase count=\"$( attr count "$CA" )\", expected 2"
[ "$( attr reaches "$IM" )" = 2 ] && ok "(8b) --impact=setPhase reaches=\"2\" (the pre-#60 binary reports 1)" \
    || no "(8b) --impact=setPhase reaches=\"$( attr reaches "$IM" )\", expected 2"
printf '%s' "$CA" | grep -q '<s t="fn" n="boot" p="src/index.ts:3" sites_at="src/index.ts:4"/>' \
    && ok "(8b) the named-function caller row is unchanged — no existing edge moved" \
    || no "(8b) the boot row changed shape: $CA"
printf '%s' "$CA" | grep -q '<s t="modscope" n="&lt;file-scope&gt;" p="src/index.ts:1" sites_at="src/index.ts:7"/>' \
    && ok "(8b) the module-scope caller is a LABELLED t=\"modscope\" row, not a fabricated function" \
    || no "(8b) --callers=setPhase has no modscope row: $CA"
# HONESTY, IN EVERY POSTURE. The default CLI legend is compact and the clause is a present-only term
# (compactlegend.h, keyed on the t= VALUE); --legend=full takes the conditional clause in graphlegend.h.
# Both must define the kind, and the two must be asserted separately — a reader holds one or the other.
printf '%s' "$CA" | grep -q '(t=modscope)' \
    && ok "(8b) the compact callers legend defines t=\"modscope\" in the document that emits it" \
    || no "(8b) --callers emits t=\"modscope\" and its compact legend never defines it"
printf '%s' "$IM" | grep -q '(t=modscope)' \
    && ok "(8b) the compact impact legend defines t=\"modscope\" too" \
    || no "(8b) --impact emits t=\"modscope\" and its compact legend never defines it"
for v in callers impact; do
    F="$( "$BIN" "$TMP/issue60prod" --no-cache --$v=setPhase --legend=full 2>/dev/null )"
    printf '%s' "$F" | grep -q 'modscope" is a row for a file' \
        && ok "(8b) --$v --legend=full defines t=\"modscope\" as well" \
        || no "(8b) --$v --legend=full emits t=\"modscope\" with no definition"
done
# …and the clause costs 0 bytes where no such row exists (the "0 bytes when inert" placement rule).
NM="$( "$BIN" "$T60/named" --no-cache --callers=bounded 2>/dev/null )"
printf '%s' "$NM" | grep -q 'modscope' \
    && no "(8b) a callers answer with no modscope row still pays for the clause" \
    || ok "(8b) no modscope row ⇒ no clause: the definition costs 0 bytes when inert"
# BLAST RADIUS: an unrelated symbol's counts must not move. lonely() in the ORIGINAL corpus is reached by
# no test and called by nobody; leaf() is called from one named function and one test.
LON="$( "$BIN" "$R" --no-cache --callers=lonely 2>/dev/null )"
[ "$( attr count "$LON" )" = 0 ] && ok "(8b) control: --callers=lonely is still count=\"0\" — no count moved that should not" \
    || no "(8b) control: --callers=lonely is now count=\"$( attr count "$LON" )\""
MIDC="$( "$BIN" "$R" --no-cache --callers=leaf 2>/dev/null )"
[ "$( attr count "$MIDC" )" = 2 ] && ok "(8b) control: --callers=leaf still count=\"2\" (mid + test_leaf)" \
    || no "(8b) control: --callers=leaf is now count=\"$( attr count "$MIDC" )\", expected 2"

# ── 8c) #60 honesty: the kind is defined in every POSTURE and SURFACE that shows it ────────────────────
# The first round defined t="modscope" only on the default <s> rows of --callers/--impact. The kind reaches
# a reader through a dozen spellings — a columnar <kind> array item, <h n=>, <edge caller=>, <u sym=>,
# <c n=> — and "a definition where the reader meets it" is the whole contract. The compact dialect now keys
# the reading on the NAME (compactlegend.h kModScopeEscapedName), which every surface escapes identically;
# the full dialect takes graphlegend.h modScopeLegend( bool ) at each verb, on that verb's own row set.
echo "=== (8c) #60: t=\"modscope\" defined in every posture that shows it ==="
sawmod(){ printf '%s' "$2" | grep -q '&lt;file-scope&gt;'; }                       # does this document SHOW one?
defmod(){ printf '%s' "$2" | grep -qE 't=modscope|modscope" is a row'; }           # …and define it?
for POSTURE in default compact full columnar; do
    case "$POSTURE" in
        default)  EXTRA="" ;;
        compact)  EXTRA="--legend=compact" ;;
        full)     EXTRA="--legend=full" ;;
        columnar) EXTRA="--format=columnar" ;;
    esac
    for V in "--callers=setPhase" "--impact=setPhase"; do
        O="$( "$BIN" "$TMP/issue60prod" --no-cache $V $EXTRA 2>/dev/null )"
        if sawmod "$V" "$O"; then
            defmod "$V" "$O" && ok "(8c) $V $POSTURE: row shown AND kind defined" \
                || no "(8c) $V $POSTURE: shows <file-scope> with NO definition anywhere in the document"
        else
            no "(8c) $V $POSTURE: no <file-scope> row at all — the posture arm proves nothing"
        fi
    done
done
# the surfaces beyond <s> rows: a graph-query row, a safe-delete caller row, a callees selector
for PAIR in "--graph-query=all()|full" "--graph-query=all()|compact" "--safe-delete=setPhase|full" "--safe-delete=setPhase|compact"; do
    V="${PAIR%|*}"; L="${PAIR#*|}"
    O="$( "$BIN" "$TMP/issue60prod" --no-cache "$V" --legend=$L 2>/dev/null )"
    if sawmod "$V" "$O"; then
        defmod "$V" "$O" && ok "(8c) $V --legend=$L: row shown AND kind defined" \
            || no "(8c) $V --legend=$L: shows <file-scope> with NO definition"
    else
        no "(8c) $V --legend=$L: no <file-scope> row — the arm proves nothing"
    fi
done
# …and 0 bytes on a corpus with NO file-scope call at all, in every one of those postures (the placement
# rule). The control corpus has to be built for it: every other fixture in this gate holds a top-level shell
# command or a node:test call, which is exactly the shape that mints an owner.
NOMS="$TMP/noms/src"; mkdir -p "$NOMS"
printf 'int leafy() { return 1; }\nint stalk() { return leafy(); }\n' > "$NOMS/tree.cpp"
for L in compact full; do
    for V in "--callers=leafy" "--graph-query=all()"; do
        O="$( "$BIN" "$TMP/noms" --no-cache "$V" --legend=$L 2>/dev/null )"
        printf '%s' "$O" | grep -q 'modscope' \
            && no "(8c) $V --legend=$L pays for the clause with no modscope row in the document" \
            || ok "(8c) $V --legend=$L: no row ⇒ no clause (0 bytes when inert)"
    done
done

# ── 8e) #60 MED-3 residual: --for and the full dialect on the verbs the first sweep missed ────────────
# The name-keyed compact rule covers everything that goes through compactLegendText. Two families do not:
# --for builds its own two legend strips (verbs_for.h, present-only bits), and the full dialect is per-verb.
echo "=== (8e) #60: --for, and --legend=full on the verbs that were bare ==="
for L in compact full; do
    O="$( "$BIN" "$TMP/issue60prod" --no-cache --for='module scope of a file' --legend=$L 2>/dev/null )"
    if printf '%s' "$O" | grep -q '&lt;file-scope&gt;'; then
        printf '%s' "$O" | grep -q 'modscope' \
            && ok "(8e) --for --legend=$L: row shown AND kind defined" \
            || no "(8e) --for --legend=$L: shows <file-scope> with NO definition (the entry verb, bare)"
    else
        no "(8e) --for --legend=$L: no <file-scope> row — the arm proves nothing"
    fi
done
for V in "--edit-check=setPhase" "--tree" "--path=<file-scope>,setPhase" "--connect=<file-scope>,setPhase" "--pack-task=<file-scope> setPhase"; do
    O="$( "$BIN" "$TMP/issue60prod" --no-cache "$V" --legend=full 2>/dev/null )"
    if printf '%s' "$O" | grep -q '&lt;file-scope&gt;'; then
        printf '%s' "$O" | grep -q 'modscope' \
            && ok "(8e) $V --legend=full: row shown AND kind defined" \
            || no "(8e) $V --legend=full: shows <file-scope> with NO definition"
    else
        no "(8e) $V --legend=full: no <file-scope> row — the arm proves nothing"
    fi
done
# inert again, in both --for dialects: the clause is a present-only bit, not a constant
for L in compact full; do
    "$BIN" "$TMP/noms" --no-cache --for='a leafy stalk' --legend=$L 2>/dev/null | grep -q 'modscope' \
        && no "(8e) --for --legend=$L pays for the clause on a corpus with no owner" \
        || ok "(8e) --for --legend=$L: no owner ⇒ no clause (0 bytes when inert)"
done

# ── 8f) #60 LOW-2: --for's clause rides on the ROW SET, not on the corpus ─────────────────────────────
# The first cut of this bit tested the whole symbol table, so a corpus holding ONE top-level call paid the
# clause on every --for answer — ~154 B compact / ~250 B full on the most-used verb, in front of the rows.
# It now reads the head of the rank-ordered surface the <d> and <hops> rows are drawn from, so it rides
# when an owner can actually be in the answer and costs nothing when it cannot. The corpus below has an
# owner (index.ts's top-level call) AND a query that ranks nowhere near it: that combination is the arm.
echo "=== (8f) #60: --for pays for the clause only when an owner row can be in the answer ==="
for L in compact full; do
    OWNED="$( "$BIN" "$TMP/issue60prod" --no-cache --for='module scope of a file' --legend=$L 2>/dev/null )"
    printf '%s' "$OWNED" | grep -q 'modscope\|MODULE SCOPE' \
        && ok "(8f) --for --legend=$L on a query that reaches the owner: the clause is present" \
        || no "(8f) --for --legend=$L: an owner row is reachable and the clause is missing"
done
# THE NEGATIVE HALF NEEDS A REAL CORPUS: on a two-file fixture every symbol ranks, so an owner is always in
# the head and the corpus-wide bug would hide. This repository has owners (704 shell files hold top-level
# calls) and enough symbols that a technical query's ranked head reaches none of them — which is exactly
# the shape that paid ~154 B on every answer before this fix.
for L in compact full; do
    for Q in "rank the graph with pagerank" "crawl the directory tree" "emit xml attributes"; do
        AWAY="$( "$BIN" "$ROOT" --no-cache --for="$Q" --legend=$L 2>/dev/null )"
        if printf '%s' "$AWAY" | grep -q '&lt;file-scope&gt;'; then
            printf '%s' "$AWAY" | grep -q 'modscope\|MODULE SCOPE' \
                && ok "(8f) --for --legend=$L '$Q': shows an owner row and defines it" \
                || no "(8f) --for --legend=$L '$Q': shows an owner row with no definition"
        else
            printf '%s' "$AWAY" | grep -q 'modscope\|MODULE SCOPE' \
                && no "(8f) --for --legend=$L '$Q': NO owner row in the answer, yet the clause still rides — the bit is corpus-wide again" \
                || ok "(8f) --for --legend=$L '$Q': no owner row ⇒ no clause, on a corpus that HAS owners"
        fi
    done
done

# ── 8d) #60 MED-2: the legend says the owner has no body, and --expand agrees ──────────────────────────
# Every clause naming this kind says "no body to expand". --expand used to answer either the WHOLE FILE
# (the whole-file serving always undercuts an empty bundle) or shown="0" capped="1" — a cap over a body
# that does not exist, and "a false _capped is a wrong answer". Both now answer bodyless, capped="0", with
# the count named and defined.
echo "=== (8d) #60: --expand on a module-scope owner is bodyless, not capped, not the file ==="
EX="$( "$BIN" "$TMP/issue60prod" --no-cache --expand='<file-scope>' 2>/dev/null )"
printf '%s' "$EX" | grep -q 'capped="0"' && printf '%s' "$EX" | grep -q 'bodyless="1"' \
    && ok '(8d) --expand=<file-scope> answers capped="0" bodyless="1"' \
    || no "(8d) --expand=<file-scope>: $( printf '%s' "$EX" | grep -oE '<bodies [^>]*>' )"
printf '%s' "$EX" | grep -q 'mode="whole-file"' \
    && no "(8d) --expand=<file-scope> served the WHOLE FILE — the legend says it has no body" \
    || ok "(8d) --expand=<file-scope> did not fall back to serving the file"
printf '%s' "$EX" | grep -q 'bodyless=N' \
    && ok "(8d) bodyless= is defined in the document that emits it" \
    || no "(8d) --expand emits bodyless= and never defines it"
EXN="$( "$BIN" "$T60/named" --no-cache --expand=bounded 2>/dev/null )"
printf '%s' "$EXN" | grep -q 'bodyless=' \
    && no "(8d) an ordinary body's answer carries bodyless= (absent-at-zero broken)" \
    || ok "(8d) control: an ordinary --expand carries no bodyless= and no clause"

# ── 9) IX-5 (hono-20) — the CLASS-NEW backstop: tests that construct a class owning a reached method ──────────
# hono's trie-router/router.test.ts only does `new TrieRouter()` and drives it through an interface-typed helper, so the
# caller walk from src/utils/url.ts never reached it. The backstop lists such tests in a SEPARATE hedged group
# <g via="class-new"> (never in tests=), one <new p= l= class=> row each. Near misses pinned: an unrelated class stays out,
# an already-proven test stays a proven row only, a class built only in non-test code adds nothing, a wide class caps
# with total=/shown=/next=. Construction per language is data: `new T(` (TS), `T(` (Python), `T::new` (Rust row).
echo "=== (9) IX-5: the class-new backstop ==="
CN="$TMP/classnew"; mkdir -p "$CN/src" "$CN/test" "$CN/py/pkg" "$CN/py/tests" "$CN/rs/src" "$CN/rs/tests"
printf 'export function leaf(p: string): string { return p }\n'                                > "$CN/src/url.ts"
printf 'export interface IRouter { add(p: string): void }\n'                                   > "$CN/src/iface.ts"
printf "import { leaf } from './url'\nimport type { IRouter } from './iface'\nexport class TrieRouter implements IRouter {\n  add(p: string) { leaf(p) }\n}\nexport class LinearRouter implements IRouter {\n  add(p: string) { return p }\n}\nexport class Unrelated {\n  ping() { return 1 }\n}\nexport class Other {\n  go(p: string) { leaf(p) }\n}\nexport class Wide {\n  run(p: string) { leaf(p) }\n}\n" > "$CN/src/router.ts"
printf "import { Other } from './router'\nexport function makeOther() { return new Other() }\n"   > "$CN/src/app.ts"
printf "import type { IRouter } from '../src/iface'\nexport function runTest(mk: () => IRouter) { const r = mk(); r.add('/x') }\n" > "$CN/test/runner.ts"
printf "import { TrieRouter } from '../src/router'\nimport { runTest } from './runner'\ndescribe('trie', () => {\n  runTest(() => new TrieRouter())\n})\n" > "$CN/test/router.test.ts"
printf "import { Unrelated } from '../src/router'\ndescribe('u', () => { new Unrelated().ping() })\n"  > "$CN/test/unrelated.test.ts"
printf "import { leaf } from '../src/url'\nimport { TrieRouter } from '../src/router'\ndescribe('d', () => { leaf('a'); new TrieRouter() })\n" > "$CN/test/direct.test.ts"
printf "import { makeOther } from '../src/app'\ndescribe('o', () => { makeOther() })\n"              > "$CN/test/other.test.ts"
for i in 01 02 03 04 05 06 07 08 09 10; do
    printf "import { Wide } from '../src/router'\ndescribe('w%s', () => { const w = new Wide(); void w })\n" "$i" > "$CN/test/wide$i.test.ts"
done
printf 'def leaf(p):\n    return p\n'                                                          > "$CN/py/pkg/util.py"
printf 'from pkg.util import leaf\n\nclass Svc:\n    def run(self, p):\n        return leaf(p)\n' > "$CN/py/pkg/svc.py"
printf 'from pkg.svc import Svc\n\ndef test_svc():\n    obj = Svc()\n    getattr(obj, "r" + "un")(1)\n' > "$CN/py/tests/test_svc.py"
printf 'pub fn leaf(p: u32) -> u32 { p }\n'                                                    > "$CN/rs/src/util.rs"
printf 'mod util;\nuse crate::util::leaf;\npub struct Eng { v: u32 }\nimpl Eng {\n    pub fn new() -> Eng { Eng { v: 0 } }\n    pub fn run(&self) -> u32 { leaf(self.v) }\n}\n' > "$CN/rs/src/lib.rs"
printf 'use crate::Eng;\n#[test]\nfn builds() {\n    let _e = Eng::new();\n}\n'                 > "$CN/rs/tests/eng_test.rs"
cn(){ ( cd "$CN" || exit 1; "$BIN" "$CN" --affected="$1" --no-cache 2>/dev/null ); }
CNT="$( cn src/url.ts )"
CNG="$( printf '%s' "$CNT" | grep -oE '<g via="class-new"[^>]*>.*</g>' )"
printf '%s' "$CNG" | grep -q '<new p="test/router.test.ts" l="4" class="TrieRouter"/>' \
    && ok '(9a) TS: router.test.ts constructs TrieRouter (owns the reached add) and rides <g via="class-new"> with l= and class=' \
    || no "(9a) TS: no class-new row for test/router.test.ts: $( printf '%s' "$CNT" | sed 's/^.*-->//' )"
printf '%s' "$CNT" | grep -q 'tests="1"' && printf '%s' "$CNT" | grep -q '<test p="test/direct.test.ts" hops="1"' \
    && ok '(9b) the group is never counted: tests="1" (the one proven row), the backstop rows outside it' \
    || no "(9b) tests= moved or the proven row is gone: $( printf '%s' "$CNT" | grep -oE '<affected [^>]*>' )"
printf '%s' "$CNT" | grep -q 'unrelated.test.ts' \
    && no '(9c) a test constructing an UNRELATED class (owns no reached method) was listed' \
    || ok '(9c) near miss: unrelated.test.ts (constructs Unrelated, which owns no reached method) stays out'
printf '%s' "$CNG" | grep -q 'direct.test.ts' \
    && no '(9d) an already-proven test was duplicated into the class-new group' \
    || ok '(9d) near miss: direct.test.ts (proven, and constructs TrieRouter) stays a proven row only'
printf '%s' "$CNG" | grep -qE 'class="Other"|other.test.ts' \
    && no '(9e) a class constructed only in non-test code (Other, via src/app.ts) added a row' \
    || ok '(9e) near miss: Other, built only in src/app.ts, adds nothing (one hop from the class, test callers only)'
printf '%s' "$CNG" | grep -q '<g via="class-new" total="11" shown="8" capped="1" next="--callers=src/router.ts:Wide">' \
    && [ "$( printf '%s' "$CNG" | grep -o '<new ' | wc -l | tr -d ' ' )" = 8 ] \
    && ok '(9f) a wide class caps: total="11" shown="8" capped="1" (8 <new> rows) with next="--callers=src/router.ts:Wide"' \
    || no "(9f) cap/count/next= wrong: $( printf '%s' "$CNG" | grep -oE '<g via="class-new"[^>]*>' )"
printf '%s' "$CNT" | grep -q 'via=class-new total= shown= capped= next=>: tests not listed above that construct a class owning a reached method' \
    && ok '(9g) the legend defines the group exactly when it renders' \
    || no '(9g) the class-new group renders with no legend clause'
CNP="$( cn py/pkg/util.py )"
printf '%s' "$CNP" | grep -q 'tests="0"' && printf '%s' "$CNP" | grep -q '<g via="class-new" total="1" shown="1"><new p="py/tests/test_svc.py" l="4" class="Svc"/></g>' \
    && ok '(9h) Python: test_svc.py builds Svc() (owns the reached run), tests="0" unchanged' \
    || no "(9h) Python: $( printf '%s' "$CNP" | sed 's/^.*-->//' )"
CNR="$( cn rs/src/util.rs )"
printf '%s' "$CNR" | grep -q '<g via="class-new" total="1" shown="1"><new p="rs/tests/eng_test.rs" l="4" class="Eng"/></g>' \
    && ok '(9i) Rust: eng_test.rs calls Eng::new (the langfacts constructorMethod row) — a class-new row for Eng' \
    || no "(9i) Rust: $( printf '%s' "$CNR" | sed 's/^.*-->//' )"
# (9i2) Rust: a file that constructs ANOTHER type first (`Other::new()`, line 5) then the reached class (`Eng::new()`, line 6): both calls
# are named `new`, so only the call's written qualifier tells them apart — the row's l= must be the Eng line, never Other's.
RS2="$TMP/classnew-rs2"; mkdir -p "$RS2/src" "$RS2/tests"
printf 'pub fn leaf(p: u32) -> u32 { p }\n'                                                    > "$RS2/src/util.rs"
printf 'mod util;\nuse crate::util::leaf;\npub struct Eng { v: u32 }\nimpl Eng {\n    pub fn new() -> Eng { Eng { v: 0 } }\n    pub fn run(&self) -> u32 { leaf(self.v) }\n}\npub struct Other { v: u32 }\nimpl Other {\n    pub fn new() -> Other { Other { v: 0 } }\n}\n' > "$RS2/src/lib.rs"
printf 'use crate::{Eng, Other};\n#[test]\nfn builds() {\n    let _x = 1;\n    let _o = Other::new();\n    let _e = Eng::new();\n}\n' > "$RS2/tests/t.rs"
CNR2="$( cd "$RS2" || exit 1; "$BIN" "$RS2" --affected=src/util.rs --no-cache 2>/dev/null )"
printf '%s' "$CNR2" | grep -q '<g via="class-new" total="1" shown="1"><new p="tests/t.rs" l="6" class="Eng"/></g>' \
    && ok '(9i2) Rust: Other::new() (line 5) then Eng::new() (line 6) in one test fn — the row names the Eng construction, l="6"' \
    || no "(9i2) Rust: a row's l= names another type's construction: $( printf '%s' "$CNR2" | sed 's/^.*-->//' )"
# (9n) CR #434 (4364224370): the next= of a capped Rust group whose first cut row built the class through its constructor METHOD names that
# method by its canonical id (src/lib.rs::Eng::new), not `Eng.new` (every same-named class's `new`); the continuation resolves to ONE def.
RS4="$TMP/classnew-rs4"; mkdir -p "$RS4/src" "$RS4/tests"
printf 'pub fn leaf(p: u32) -> u32 { p }\n'                                                    > "$RS4/src/util.rs"
printf 'mod util;\nuse crate::util::leaf;\npub struct Eng { v: u32 }\nimpl Eng {\n    pub fn new() -> Eng { Eng { v: 0 } }\n    pub fn run(&self) -> u32 { leaf(self.v) }\n}\n' > "$RS4/src/lib.rs"
for n in 1 2 3 4 5 6 7 8 9; do printf 'use crate::Eng;\n#[test]\nfn builds%s() {\n    let _e = Eng::new();\n}\n' "$n" > "$RS4/tests/t$n.rs"; done
CNR4="$( cd "$RS4" || exit 1; "$BIN" "$RS4" --affected=src/util.rs --no-cache 2>/dev/null )"
printf '%s' "$CNR4" | grep -q '<g via="class-new" total="9" shown="8" capped="1" next="--callers=src/lib.rs::Eng::new">' \
    && ok '(9n) Rust ctor row cut: next="--callers=src/lib.rs::Eng::new" (the constructor by canonical id)' \
    || no "(9n) Rust ctor row cut: next= is not the canonical id of Eng::new: $( printf '%s' "$CNR4" | sed 's/^.*-->//' | grep -o '<g via="class-new"[^>]*>' )"
CNR4N="$( cd "$RS4" || exit 1; "$BIN" "$RS4" --callers=src/lib.rs::Eng::new --no-cache 2>/dev/null )"
printf '%s' "$CNR4N" | grep -q 'defs="1"' \
    && ok '(9n) the continuation resolves to one definition (defs="1")' \
    || no "(9n) the continuation does not resolve to one def: $( printf '%s' "$CNR4N" | sed 's/^.*-->//' | cut -c1-200 )"
# (9i3) TS `new A.Eng()` (line 4) then `new B.Eng()` (line 5) — two classes named Eng, the edge is B.Eng's. TS/JS take l= only from a construction
# that RESOLVES to the reached class (B is `import * as B` of its file, B.Eng its export), so the row reads l="5", never l="4". Python twin (the
# name test + spelling hedge): `ext.Eng()` (external module, line 5) then the imported `Eng()` (line 6) — no l=, never l="5".
TS3="$TMP/classnew-ts3"; mkdir -p "$TS3/src" "$TS3/test"
printf 'export class Eng { other() { return 1; } }\n'                                                 > "$TS3/src/a.ts"
printf 'import { leaf } from "./util";\nexport class Eng { run(p: number) { return leaf(p); } }\n'    > "$TS3/src/b.ts"
printf 'export function leaf(p: number) { return p; }\n'                                              > "$TS3/src/util.ts"
printf 'import * as A from "../src/a";\nimport * as B from "../src/b";\ntest("x", () => {\n  const x = new A.Eng();\n  const y = new B.Eng();\n});\n' > "$TS3/test/x.test.ts"
CNT3="$( cd "$TS3" || exit 1; "$BIN" "$TS3" --affected=src/util.ts --no-cache 2>/dev/null )"
printf '%s' "$CNT3" | grep -q '<g via="class-new" total="1" shown="1"><new p="test/x.test.ts" l="5" class="Eng"/></g>' \
    && ok '(9i3) TS: new A.Eng() (line 4) then new B.Eng() (line 5) — only B.Eng resolves to the reached class (namespace export), so l="5" (never l="4")' \
    || no "(9i3) TS: a row's l= names another class's construction: $( printf '%s' "$CNT3" | sed 's/^.*-->//' )"
PY3="$TMP/classnew-py3"; mkdir -p "$PY3/pkg" "$PY3/tests"
printf 'def leaf(p):\n    return p\n'                                                                > "$PY3/pkg/util.py"
printf 'from pkg.util import leaf\n\nclass Eng:\n    def run(self, p):\n        return leaf(p)\n'      > "$PY3/pkg/b.py"
printf 'from pkg.b import Eng\nimport ext\n\ndef test_x():\n    x = ext.Eng()\n    y = Eng()\n'        > "$PY3/tests/test_x.py"
CNY3="$( cd "$PY3" || exit 1; "$BIN" "$PY3" --affected=pkg/util.py --no-cache 2>/dev/null )"
printf '%s' "$CNY3" | grep -q '<g via="class-new" total="1" shown="1"><new p="tests/test_x.py" class="Eng"/></g>' \
    && ok '(9i3) Python: ext.Eng() (line 5) then Eng() (line 6) — two different qualifiers pass the name test, so the row has no l= (never l="5")' \
    || no "(9i3) Python: a row's l= names the external namesake's construction: $( printf '%s' "$CNY3" | sed 's/^.*-->//' )"
# (9i4) TS ALIASED import of the reached class: `import { Eng as E }` / `import E from "../src/b"` + a bare `new Eng()` of a namesake (line 4) then
# `new E()` (line 5, the reached B.Eng). Only `new E()` resolves to the reached class (the named import / the module's default export), so the
# row reads l="5", never l="4". Controls: an unrelated default import (`React`) keeps l=.
TS4="$TMP/classnew-ts4"; mkdir -p "$TS4/src" "$TS4/test"
printf 'export class Eng { other() { return 1; } }\n'                                                 > "$TS4/src/a.ts"
printf 'import { leaf } from "./util";\nexport class Eng { run(p: number) { return leaf(p); } }\n'    > "$TS4/src/b.ts"
printf 'export function leaf(p: number) { return p; }\n'                                              > "$TS4/src/util.ts"
printf 'import { Eng } from "../src/a";\nimport { Eng as E } from "../src/b";\ntest("x", () => {\n  const x = new Eng();\n  const y = new E();\n});\n' > "$TS4/test/x.test.ts"
CNT4="$( cd "$TS4" || exit 1; "$BIN" "$TS4" --affected=src/util.ts --no-cache 2>/dev/null )"
printf '%s' "$CNT4" | grep -q '<g via="class-new" total="1" shown="1"><new p="test/x.test.ts" l="5" class="Eng"/></g>' \
    && ok '(9i4) TS: import { Eng as E } of the reached class + a bare new Eng() of a namesake (line 4) — l="5" from new E() (never l="4")' \
    || no "(9i4) TS: an aliased import leaves the namesake's line: $( printf '%s' "$CNT4" | sed 's/^.*-->//' )"
TS5="$TMP/classnew-ts5"; mkdir -p "$TS5/src" "$TS5/test"
printf 'export default class Eng { other() { return 1; } }\n'                                                 > "$TS5/src/a.ts"
printf 'import { leaf } from "./util";\nexport default class Eng { run(p: number) { return leaf(p); } }\n' > "$TS5/src/b.ts"
printf 'export function leaf(p: number) { return p; }\n'                                              > "$TS5/src/util.ts"
printf 'import Eng from "../src/a";\nimport E from "../src/b";\ntest("x", () => {\n  const x = new Eng();\n  const y = new E();\n});\n' > "$TS5/test/x.test.ts"
CNT5="$( cd "$TS5" || exit 1; "$BIN" "$TS5" --affected=src/util.ts --no-cache 2>/dev/null )"
printf '%s' "$CNT5" | grep -q '<g via="class-new" total="1" shown="1"><new p="test/x.test.ts" l="5" class="Eng"/></g>' \
    && ok '(9i4) TS: default import E of the reached class + a bare new Eng() of a namesake (line 4) — l="5" from new E() (never l="4")' \
    || no "(9i4) TS: a default import leaves the namesake's line: $( printf '%s' "$CNT5" | sed 's/^.*-->//' )"
TS6="$TMP/classnew-ts6"; mkdir -p "$TS6/src" "$TS6/test"
cp "$TS4/src/b.ts" "$TS4/src/util.ts" "$TS6/src/"
printf 'import React from "react";\nimport { Eng } from "../src/b";\ntest("x", () => {\n  const x = new Eng();\n});\n' > "$TS6/test/x.test.ts"
CNT6="$( cd "$TS6" || exit 1; "$BIN" "$TS6" --affected=src/util.ts --no-cache 2>/dev/null )"
printf '%s' "$CNT6" | grep -q '<g via="class-new" total="1" shown="1"><new p="test/x.test.ts" l="4" class="Eng"/></g>' \
    && ok '(9i4) TS control: an unrelated default import (React) + the reached Eng built by its own name keeps l="4"' \
    || no "(9i4) TS control: an unrelated default import dropped the line: $( printf '%s' "$CNT6" | sed 's/^.*-->//' )"
# (9i4b) The class is renamed on the EXPORT side (`class Eng {} export { Eng as Engine }`): `Eng` is bound to ../src/a (a namesake), `Engine` to
# ../src/b's export Engine = the reached class. Only `new Engine()` (line 5) resolves to it, so l="5", never the namesake's line 4.
TS7="$TMP/classnew-ts7"; mkdir -p "$TS7/src" "$TS7/test"
cp "$TS4/src/a.ts" "$TS4/src/util.ts" "$TS7/src/"
printf 'import { leaf } from "./util";\nclass Eng { run(p: number) { return leaf(p); } }\nexport { Eng as Engine };\n' > "$TS7/src/b.ts"
printf 'import { Eng } from "../src/a";\nimport { Engine } from "../src/b";\ntest("x", () => {\n  const x = new Eng();\n  const y = new Engine();\n});\n' > "$TS7/test/x.test.ts"
CNT7="$( cd "$TS7" || exit 1; "$BIN" "$TS7" --affected=src/util.ts --no-cache 2>/dev/null )"
printf '%s' "$CNT7" | grep -q '<g via="class-new" total="1" shown="1"><new p="test/x.test.ts" l="5" class="Eng"/></g>' \
    && ok '(9i4b) TS: export { Eng as Engine } + a test binding Eng to a namesake file and building it first (line 4) — l="5" from new Engine() (never l="4")' \
    || no "(9i4b) TS: an export-side rename leaves the namesake's line: $( printf '%s' "$CNT7" | sed 's/^.*-->//' )"
# Recall arms for the same rule: the bare name is bound to the class's OWN file, so the row keeps its line however the test file aliases other things.
#   stem: a default import of another file (lib/b) whose stem equals the class file's (src/b); stem2: two default imports of same-stem files (the
#   bare one is src/eng); agree-react: unrelated default/namespace imports and the NAMESAKE aliased (`Eng as Other`).
TS8="$TMP/classnew-ts8"; mkdir -p "$TS8/src" "$TS8/lib" "$TS8/test"
cp "$TS4/src/b.ts" "$TS4/src/util.ts" "$TS8/src/"
printf 'export default class Other { }\n'                                                             > "$TS8/lib/b.ts"
printf 'import Thing from "../lib/b";\nimport { Eng } from "../src/b";\ntest("x", () => {\n  const t = new Thing();\n  const x = new Eng();\n});\n' > "$TS8/test/x.test.ts"
CNT8="$( cd "$TS8" || exit 1; "$BIN" "$TS8" --affected=src/util.ts --no-cache 2>/dev/null )"
printf '%s' "$CNT8" | grep -q '<g via="class-new" total="1" shown="1"><new p="test/x.test.ts" l="5" class="Eng"/></g>' \
    && ok '(9i4b) TS recall: a default import of a same-stem file elsewhere (lib/b) does not hedge — Eng is bound to src/b, l="5" kept' \
    || no "(9i4b) TS recall: a same-stem default import dropped the line: $( printf '%s' "$CNT8" | sed 's/^.*-->//' )"
TS9="$TMP/classnew-ts9"; mkdir -p "$TS9/src" "$TS9/lib" "$TS9/test"
cp "$TS5/src/util.ts" "$TS9/src/"
printf 'export default class Eng { other() { return 1; } }\n'                                          > "$TS9/lib/eng.ts"
printf 'import { leaf } from "./util";\nexport default class Eng { run(p: number) { return leaf(p); } }\n' > "$TS9/src/eng.ts"
printf 'import Eng from "../src/eng";\nimport L from "../lib/eng";\ntest("x", () => {\n  const x = new Eng();\n  const y = new L();\n});\n' > "$TS9/test/x.test.ts"
CNT9="$( cd "$TS9" || exit 1; "$BIN" "$TS9" --affected=src/util.ts --no-cache 2>/dev/null )"
printf '%s' "$CNT9" | grep -q '<g via="class-new" total="1" shown="1"><new p="test/x.test.ts" l="4" class="Eng"/></g>' \
    && ok '(9i4b) TS recall: Eng default-imported from src/eng (the class file) beside a same-stem lib/eng import — l="4" kept' \
    || no "(9i4b) TS recall: a same-stem default import dropped the line: $( printf '%s' "$CNT9" | sed 's/^.*-->//' )"
TS10="$TMP/classnew-ts10"; mkdir -p "$TS10/src" "$TS10/test"
cp "$TS4/src/a.ts" "$TS4/src/b.ts" "$TS4/src/util.ts" "$TS10/src/"
printf 'import React from "react";\nimport * as path from "path";\nimport { Eng } from "../src/b";\nimport { Eng as Other } from "../src/a";\ntest("x", () => {\n  const x = new Eng();\n});\n' > "$TS10/test/x.test.ts"
CNT10="$( cd "$TS10" || exit 1; "$BIN" "$TS10" --affected=src/util.ts --no-cache 2>/dev/null )"
printf '%s' "$CNT10" | grep -q '<g via="class-new" total="1" shown="1"><new p="test/x.test.ts" l="6" class="Eng"/></g>' \
    && ok '(9i4b) TS recall: Eng bound to src/b while the namesake is aliased (Eng as Other) and unrelated imports sit around it — l="6" kept' \
    || no "(9i4b) TS recall: an aliased namesake dropped the line: $( printf '%s' "$CNT10" | sed 's/^.*-->//' )"
# Barrel FLOOR (hono's `import { RegExpRouter } from "../reg-exp-router"`): the name is bound to src/eng/index.ts, which only RE-EXPORTS the class
# (`export { Eng } from "./router"`). The import resolver records no re-export (ingest_jsimports.h), so the construction resolves to nothing and the
# row keeps no l= (exact or none; the row itself stays).
TS11="$TMP/classnew-ts11"; mkdir -p "$TS11/src/eng" "$TS11/test"
cp "$TS4/src/a.ts" "$TS4/src/util.ts" "$TS11/src/"
printf 'import { leaf } from "../util";\nexport class Eng { run(p: number) { return leaf(p); } }\n' > "$TS11/src/eng/router.ts"
printf 'export { Eng } from "./router";\n'                                                          > "$TS11/src/eng/index.ts"
printf 'import { Eng } from "../src/eng";\ntest("x", () => {\n  const x = new Eng();\n});\n'     > "$TS11/test/x.test.ts"
CNT11="$( cd "$TS11" || exit 1; "$BIN" "$TS11" --affected=src/util.ts --no-cache 2>/dev/null )"
printf '%s' "$CNT11" | grep -q '<g via="class-new" total="1" shown="1"><new p="test/x.test.ts" class="Eng"/></g>' \
    && ok '(9i4b) TS floor: Eng imported through a barrel (src/eng/index.ts re-exporting ./router) keeps the row, no l= (the resolver records no re-export)' \
    || no "(9i4b) TS floor: a barrel import row is missing or claims a line: $( printf '%s' "$CNT11" | sed 's/^.*-->//' )"
# (9i5) THE RESOLVED-EDGE RULE: a TS/JS row's l= is the earliest construction whose callee RESOLVES to the reached class (Eng in src/eng), never one
# that merely carries its name or comes from its module. ren: `import { Foo as Eng }` + `import { Eng as Real }` — new Eng() (line 4) builds Foo,
# new Real() (line 5) builds Eng → l="5". dflt: `import Eng` of `export default class Foo` → l="5" from new Real(). js: the .js twin of ren.
# expren: `export { Foo as Eng, Eng as Engine }` in the class file → l="5" from new Engine(). bar1/bar2: a barrel `export { Foo as Eng } from` /
# `export * ... export { Bar as Eng } from "./bar"` — nothing resolves through a re-export, so no l= (never the renamed class's line 3).
# Recall/controls: only (a lone `import { Foo as Eng }` + new Eng()) — no row; req (`const { Eng } = require( class file )`) → l="3";
# shadow (an arrow parameter Eng hides the import inside the test callback, line 3; the real new Eng() is line 4) → l="4".
cn9i5(){ ( cd "$TMP/classnew-9i5/$1" || exit 1; "$BIN" "$TMP/classnew-9i5/$1" --affected="src/util.$2" --no-cache 2>/dev/null ) | grep -oE '<g via="class-new"[^>]*>.*</g>'; }
mk9i5(){ mkdir -p "$TMP/classnew-9i5/$1/src" "$TMP/classnew-9i5/$1/test"; printf '%b' "$4" > "$TMP/classnew-9i5/$1/src/eng.$2"; printf '%b' "$5" > "$TMP/classnew-9i5/$1/test/x.test.$2"
         printf 'export function leaf(p%s) { return p; }\n' "$3" > "$TMP/classnew-9i5/$1/src/util.$2"; }
ENG2='import { leaf } from "./util";\nexport class Eng { run(p: number) { return leaf(p); } }\nexport class Foo { other() { return 1; } }\n'
RENT='import { Foo as Eng } from "../src/eng";\nimport { Eng as Real } from "../src/eng";\ntest("x", () => {\n  const x = new Eng();\n  const y = new Real();\n});\n'
mk9i5 ren ts ': number' "$ENG2" "$RENT"
mk9i5 dflt ts ': number' 'import { leaf } from "./util";\nexport class Eng { run(p: number) { return leaf(p); } }\nexport default class Foo { other() { return 1; } }\n' \
      'import Eng from "../src/eng";\nimport { Eng as Real } from "../src/eng";\ntest("x", () => {\n  const x = new Eng();\n  const y = new Real();\n});\n'
mk9i5 js js '' 'import { leaf } from "./util";\nexport class Eng { run(p) { return leaf(p); } }\nexport class Foo { other() { return 1; } }\n' "$RENT"
mk9i5 expren ts ': number' 'import { leaf } from "./util";\nclass Eng { run(p: number) { return leaf(p); } }\nclass Foo { other() { return 1; } }\nexport { Foo as Eng, Eng as Engine };\n' \
      'import { Eng } from "../src/eng";\nimport { Engine } from "../src/eng";\ntest("x", () => {\n  const x = new Eng();\n  const y = new Engine();\n});\n'
BART='import { Eng, Engine } from "../src";\ntest("x", () => {\n  const x = new Eng();\n  const y = new Engine();\n});\n'
mk9i5 bar1 ts ': number' "$ENG2" "$BART"
printf 'export { Foo as Eng } from "./eng";\nexport { Eng as Engine } from "./eng";\n' > "$TMP/classnew-9i5/bar1/src/index.ts"
mk9i5 bar2 ts ': number' 'import { leaf } from "./util";\nexport class Eng { run(p: number) { return leaf(p); } }\n' "$BART"
printf 'export class Bar { other() { return 1; } }\n' > "$TMP/classnew-9i5/bar2/src/bar.ts"
printf 'export * from "./eng";\nexport { Bar as Eng } from "./bar";\nexport { Eng as Engine } from "./eng";\n' > "$TMP/classnew-9i5/bar2/src/index.ts"
mk9i5 only ts ': number' "$ENG2" 'import { Foo as Eng } from "../src/eng";\ntest("x", () => {\n  const x = new Eng();\n});\n'
mk9i5 req ts ': number' "$ENG2" 'const { Eng } = require("../src/eng");\ntest("x", () => {\n  const x = new Eng();\n});\n'
mk9i5 shadow ts ': number' "$ENG2" 'import { Eng, Foo } from "../src/eng";\ntest("x", () => {\n  [Foo].map((Eng: any) => new Eng());\n  const y = new Eng();\n});\n'
for c in 'ren ts l="5" ' 'dflt ts l="5" ' 'js js l="5" ' 'expren ts l="5" ' 'bar1 ts -' 'bar2 ts -' 'req ts l="3" ' 'shadow ts l="4" '; do
    d=${c%% *}; rest=${c#* }; e=${rest%% *}; want=${rest#* }; [ "$want" = - ] && want=
    got="$( cn9i5 "$d" "$e" )"
    [ "$got" = "<g via=\"class-new\" total=\"1\" shown=\"1\"><new p=\"test/x.test.$e\" ${want}class=\"Eng\"/></g>" ] \
        && ok "(9i5) $d: the row's l= is the construction resolved to the reached class (${want:-no l=})" \
        || no "(9i5) $d: expected ${want:-no l=}, got: ${got:-<no group>}"
done
[ -z "$( cn9i5 only ts )" ] \
    && ok '(9i5) only: import { Foo as Eng } + new Eng() builds Foo — no class-new row' \
    || no "(9i5) only: a row for a Foo construction: $( cn9i5 only ts )"
# (9l) "nearest class first": two classes at DIFFERENT hops whose test-path order is the reverse of their rank order. Far (hop 2, via
# the module function mid) is built by the alphabetically-first test, Near (hop 1) by the later one: the rows must list Near first.
MB="$TMP/classnew-rank"; mkdir -p "$MB/pkg" "$MB/tests"
printf 'def leaf(p):\n    return p\n'                                                       > "$MB/pkg/util.py"
printf 'from pkg.util import leaf\n\ndef mid(p):\n    return leaf(p)\n\nclass Far:\n    def go(self, p):\n        return mid(p)\n\nclass Near:\n    def run(self, p):\n        return leaf(p)\n' > "$MB/pkg/svc.py"
printf 'from pkg.svc import Far\n\ndef test_far():\n    obj = Far()\n    getattr(obj, "g" + "o")(1)\n'  > "$MB/tests/test_a.py"
printf 'from pkg.svc import Near\n\ndef test_near():\n    obj = Near()\n    getattr(obj, "r" + "un")(1)\n' > "$MB/tests/test_z.py"
CNM="$( cd "$MB" || exit 1; "$BIN" "$MB" --affected=pkg/util.py --no-cache 2>/dev/null )"
printf '%s' "$CNM" | grep -q '<g via="class-new" total="2" shown="2"><new p="tests/test_z.py" l="4" class="Near"/><new p="tests/test_a.py" l="4" class="Far"/></g>' \
    && ok '(9l) rank order: Near (hop 1, tests/test_z.py) is listed before Far (hop 2, tests/test_a.py) although the path order is the reverse' \
    || no "(9l) rank order: the nearest class is not first: $( printf '%s' "$CNM" | sed 's/^.*-->//' )"
( cd "$CN" || exit 1; "$BIN" "$CN" --affected=src/url.ts --legend=full --no-cache 2>/dev/null ) | grep -q '<g via="class-new" total= shown= capped= next=>: tests not listed above that construct a class owning a reached method' \
    && ok '(9k) the full legend carries the same clause (testmap.h kClassNewLegend) when the group renders' \
    || no '(9k) --legend=full renders the class-new group with no clause'
# (9m) CR #434 (4364224360): the group is a FLOOR (Go T{}, C++ T x;, Ruby T.new are never read), and both legends say so
( cd "$CN" || exit 1; "$BIN" "$CN" --affected=src/url.ts --legend=full --no-cache 2>/dev/null ) | grep -q 'nearest class first; a floor (Go T{}, C++ T x;, Ruby T.new are not read)' \
    && ok '(9m) the full legend names the class-new group a floor (Go T{}, C++ T x;, Ruby T.new unread)' \
    || no '(9m) --legend=full: the class-new clause does not say the group is a floor'
( cd "$CN" || exit 1; "$BIN" "$CN" --affected=src/url.ts --legend=compact --no-cache 2>/dev/null ) | grep -q 'nearest class first; a floor (Go T{}, C++ T x;, Ruby T.new are not read)' \
    && ok '(9m) the compact legend carries the floor clause too (compact shortens the dictionary, never a meaning)' \
    || no '(9m) --legend=compact: the class-new clause does not say the group is a floor'
printf '%s' "$A" | grep -q 'class-new' \
    && no '(9j) an answer with no class-new row carries the group or its clause (absent-when-empty broken)' \
    || ok '(9j) control: --affected=src/core.cpp (no class reached) has no group and no clause'

# ── 6) xml well-formed ───────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$A" | xmllint --noout - 2>/dev/null; then ok "--affected xml well-formed"; else no "--affected xml malformed"; fi
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
