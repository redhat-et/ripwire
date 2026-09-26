#!/usr/bin/env bash
# testgatecheck.sh — gate for --test-gate[=F1,F2] (A4-R2, the TDAD-parity regression contract). Contract
# (from --help): names the tests to run for a change + the UNTESTED blast radius, and the EXIT CODE is the
# gate (exit 4 when either obligation is non-empty, exit 0 when neither). Mirrors --quality-delta's
# convergence-loop shape; motivated by TDAD (arXiv 2603.17973): a queryable call-graph+test map cut
# agent-caused regressions -70% (6.08%->1.82%).
#
# KEY SEMANTIC (documented here so the test's own shape is honest): this gate NAMES obligations, it cannot
# OBSERVE a test run. So "run the covering test, does the gate go green?" is the WRONG mental model — re-running
# the same command yields the same exit 4, because the obligation (this test MUST be run) still EXISTS. The
# agent loop is: gate → run the named tests → rely on the now-green tests. The exit contract is about the
# EXISTENCE of test obligations / untested reach, never their satisfaction. Scenario (b) below pins exactly this.
#
# Synthetic corpus (no git history needed — --test-gate takes the changed set as an argument, like --situ=FILES):
#   src/covered.cpp    :  covered()                              (has a covering test)
#   test/test_covered.cpp : test_covered() -> covered()          (transitively reaches covered)
#   src/uncovered.cpp  :  uncovered()                            (NO test reaches it or its users)
#   src/user.cpp       :  user() -> uncovered()                  (non-test symbol in uncovered()'s blast radius)
#
# Hand-computed expectations:
#   --test-gate=src/covered.cpp   → tests={test_covered.cpp}, untested={} → exit 4 (there is a test to run)
#   --test-gate=src/uncovered.cpp → tests={}, untested={user} → exit 4 (a non-test impacted symbol no test covers)
#   --test-gate=<no such file>    → REFUSED, exit 1 (2026-08-24: this used to be changed=0 at exit 0 — a
#                                   silent zero on an unparseable input, the non-negotiable-#3 breach the
#                                   def-over-decl lane found via --test-gate=da61bac..HEAD; the full refusal
#                                   surface is testgaterefusecheck.sh's)
#   bare --test-gate, CLEAN git tree → changed=0, exit 0 (the one honest zero: git ran, found no change)
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/testgatecheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # BOTH seams: positional and RIPWIRE_BIN
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "testgatecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src" "$R/test"
printf 'int covered() { return 1; }\n'                       > "$R/src/covered.cpp"
printf 'void test_covered() { covered(); }\n'                > "$R/test/test_covered.cpp"
printf 'int uncovered() { return 2; }\n'                     > "$R/src/uncovered.cpp"
printf 'int user() { return uncovered(); }\n'                > "$R/src/user.cpp"

# run + capture exit code separately (the gate's exit IS the contract)
run(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" "$@" --no-cache 2>/dev/null; }
rc(){  perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" "$@" --no-cache >/dev/null 2>&1; echo $?; }
attr(){ printf '%s' "$1" | grep -oE "$2=\"[0-9]+\"" | head -1 | grep -oE '[0-9]+'; }
# Basenames of the emitted test rows, sorted — through test/testrowpaths.py, THE shared reader.
# The census the review of #214 ran over test/ found this the last private reader in the tests_to_run family
# that could still go QUIET: it matched `<t p=` singles only, so every <g … n= p="a,b,c" run_unknown="1"/>
# group row (testmap.h's E1 shape, emitted whenever two runner-less tests share their evidence) was skipped
# without a word. Measured on a two-runner-less-test fixture: this helper returned the EMPTY set where the
# shared reader returned both paths. Only the one-test fixture below kept the arms honest, which is a
# property of the fixture and not of the reader.
tset(){ printf '%s' "$1" | python3 "$ROOT/test/testrowpaths.py" paths xml | sed 's|.*/||' | sort | tr '\n' ','; }
# names of the emitted <u sym="..."/> untested rows, sorted
uset(){ printf '%s' "$1" | grep -oE '<u sym="[^"]*"' | sed -E 's/<u sym="([^"]*)"/\1/' | sort | tr '\n' ','; }

# ── (a) change with an existing covering test → exit 4 listing exactly that test file ─────────────────
A="$( run --test-gate=src/covered.cpp )"; AEC="$( rc --test-gate=src/covered.cpp )"
{ [ "$AEC" = 4 ] && [ "$( attr "$A" tests )" = 1 ] && [ "$( tset "$A" )" = "test_covered.cpp," ] && [ "$( attr "$A" untested )" = 0 ]; } \
    && ok "(a) covered change: tests={test_covered.cpp}, untested=0, exit 4" \
    || no "(a) covered wrong (exit=$AEC tests=$( attr "$A" tests ) set=$( tset "$A" ) untested=$( attr "$A" untested ))"

# ── (b) the gate names, it cannot observe runs: re-running is byte-identical and STILL exit 4 ─────────
#      ("after 'running' the covering test" = the same command again; the obligation still EXISTS → exit 4)
B="$( run --test-gate=src/covered.cpp )"; BEC="$( rc --test-gate=src/covered.cpp )"
{ [ "$B" = "$A" ] && [ "$BEC" = 4 ]; } \
    && ok "(b) gate names (cannot observe a run): re-run byte-identical, still exit 4" \
    || no "(b) re-run drifted (identical=$( [ "$B" = "$A" ] && echo y || echo n ) exit=$BEC) — gate must not pretend to see runs"

# ── (c) change reaching symbols no test covers → untested non-empty, exit 4 with them printed ─────────
C="$( run --test-gate=src/uncovered.cpp )"; CEC="$( rc --test-gate=src/uncovered.cpp )"
{ [ "$CEC" = 4 ] && [ "$( attr "$C" tests )" = 0 ] && [ "$( attr "$C" untested )" -ge 1 ] && printf '%s' "$( uset "$C" )" | grep -q 'user'; } \
    && ok "(c) uncovered change: tests=0, untested>=1 (includes user), exit 4, offenders printed" \
    || no "(c) uncovered wrong (exit=$CEC tests=$( attr "$C" tests ) untested=$( attr "$C" untested ) uset=$( uset "$C" ))"

# ── (c') the (a) and (c) obligations DIFFER — proves the gate distinguishes tests-to-run from untested reach
{ [ -n "$( tset "$A" )" ] && [ -z "$( tset "$C" )" ] && [ -z "$( uset "$A" )" ] && [ -n "$( uset "$C" )" ]; } \
    && ok "(c') distinguishes obligations: covered→a test, uncovered→an untested symbol (not a constant)" \
    || no "(c') the two changes produced indistinguishable obligations"

# ── (d) an unparseable FILES token → REFUSED (exit 1, nothing on stdout) ─────────────────────────────
# The pre-2026-08-24 contract here — changed="0" at exit 0 — was the defect: "none found" spelled where
# "cannot parse" was true. Wording/probe arms live in testgaterefusecheck.sh; this pins the flip itself.
D="$( run --test-gate=zz_no_such_file_xyz.zzz )"; DEC="$( rc --test-gate=zz_no_such_file_xyz.zzz )"
{ [ "$DEC" = 1 ] && [ -z "$D" ]; } \
    && ok "(d) a no-such-file token REFUSES: exit 1, no report body (never a silent changed=\"0\")" \
    || no "(d) no-such-file not refused (exit=$DEC, stdout ${#D} bytes) — the silent-zero defect is back"

# ── (d2) the one HONEST zero: a clean git tree under the bare form → changed="0", exit 0 ─────────────
# "No change = no obligations" needs a vehicle that can still truthfully produce it: git ran and reported
# zero changed files. (The synthetic corpus above stays git-less on purpose; this arm builds its own repo.)
if command -v git >/dev/null 2>&1; then
    G="$TMP/gitrepo"; mkdir -p "$G/src"
    printf 'int lone() { return 3; }\n' > "$G/src/lone.cpp"
    git -C "$G" init -q . && git -C "$G" -c user.email=t@t -c user.name=t add src/lone.cpp \
        && git -C "$G" -c user.email=t@t -c user.name=t commit -qm base
    D2="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$G" --test-gate --no-cache 2>/dev/null )"
    D2EC="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$G" --test-gate --no-cache >/dev/null 2>&1; echo $? )"
    { [ "$D2EC" = 0 ] && [ "$( attr "$D2" changed )" = 0 ] && [ "$( attr "$D2" tests )" = 0 ] && [ "$( attr "$D2" untested )" = 0 ]; } \
        && ok '(d2) clean tree: <test-gate changed="0" tests="0" untested="0">, exit 0 (the honest zero)' \
        || no "(d2) clean-tree wrong (exit=$D2EC changed=$( attr "$D2" changed ) tests=$( attr "$D2" tests ) untested=$( attr "$D2" untested ))"
else
    printf '  SKIP  (d2) clean-tree honest zero (no git)\n'; D2=""
fi

# ── (e) determinism (two runs byte-identical) ────────────────────────────────────────────────────────
[ "$( run --test-gate=src/covered.cpp,src/uncovered.cpp )" = "$( run --test-gate=src/covered.cpp,src/uncovered.cpp )" ] \
    && ok "(e) deterministic (byte-identical run-to-run)" || no "(e) non-deterministic"

# ── (f) xml well-formed (every emitted variant) ──────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xok=1
    # "$D" left this list when arm (d) became a refusal (empty stdout is not a document); "$D2" may be
    # empty only when git is absent, in which case there is nothing to lint.
    for X in "$A" "$C" "$D2" "$( run --test-gate=src/covered.cpp,src/uncovered.cpp )"; do
        [ -n "$X" ] || continue
        printf '%s' "$X" | xmllint --noout - 2>/dev/null || xok=0
    done
    if [ "$xok" = 1 ]; then ok "(f) xml well-formed (all variants)"; else no "(f) xml malformed"; fi
else
    printf '  SKIP  (f) xml well-formed (no xmllint)\n'
fi


# ── (g) §B12.5 — untested= IS THREE DIFFERENT UNITS, and each legend now says which ──────────────────────
# `untested=` counts cross-directory call EDGES in --seams, impacted SYMBOLS here, and gate-lit HOSTS in
# --flip. Every one of those legends was locally honest, which is exactly how a reader who compares two of
# the numbers is misled — the R13 shape lifted one level. Swept over the WHOLE emitting family from source,
# not from a remembered list: whatever spells untested= must carry the clause.
UNIT_FAM="$( grep -rlF 'untested=\"' "$ROOT/src" 2>/dev/null | sed 's|.*/||' | sort | tr '\n' ' ' )"
# L1 (2026-09-19): the CLI default legend is compact; (g) reads the FULL legend's UNIT: prose, so probe_unit asks for it.
probe_unit(){ "$BIN" "$ROOT" $1 --legend=full 2>/dev/null | grep -oE '<!--.*?-->' | head -1; }
u_ok=1
for spec in "--seams:EDGES" "--test-gate=src/editcheck.h:SYMBOLS" "--flags --flip=RIPWIRE_ASAN:HOSTS"; do
    _v="${spec%:*}"; _unit="${spec##*:}"
    _leg="$( probe_unit "$_v" )"
    if [ -z "$_leg" ]; then
        no "(g) '$_v' emitted no legend to check"; u_ok=0; continue
    fi
    printf '%s' "$_leg" | grep -q "UNIT: untested= here counts .*$_unit" \
        && ok "(g) '$_v' names its own untested= unit ($_unit)" \
        || { no "(g) '$_v' does not name its untested= unit"; u_ok=0; }
    # and it must name the OTHER TWO, or a reader still has no way to know the numbers differ.
    _others=0
    for w in EDGES SYMBOLS HOSTS; do [ "$w" = "$_unit" ] && continue
        printf '%s' "$_leg" | grep -qiE "$( [ $w = EDGES ] && echo 'call EDGES' || { [ $w = SYMBOLS ] && echo 'impacted SYMBOLS' || echo 'defs a gate lights'; } )" && _others=$(( _others + 1 ))
    done
    [ "$_others" = 2 ] && ok "(g) '$_v' names the other two verbs' units too (the collision is the finding)" \
                       || { no "(g) '$_v' names $_others of the 2 sibling units"; u_ok=0; }
done
[ "$u_ok" = 1 ] && ok "(g) the untested= family ($UNIT_FAM) all disclose their unit" \
                || no "(g) at least one untested= emitter is silent about its unit"

# ── (h) H2H-Graft F1 (2026-09-07): a <t> row says WHY it is an obligation ────────────────────────────
# hops= is the caller-walk depth at which the test reaches the change (1 = it calls a changed symbol
# directly); a test file that is ITSELF in the change set is an obligation on its own evidence — you edited
# it, run it — and its row says changed="1" (Graft's blast verb calls this state "changed"; the graph-reached
# rows are its "stale": tests that reach the area and the diff did not touch). Before this, a changed test
# file was silently ABSENT from tests_to_run: its symbols were skipped as "the change, not its radius".
H="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" --test-gate=src/covered.cpp --no-cache 2>/dev/null )"
printf '%s' "$H" | grep -qE '<t p="test/test_covered.cpp"[^>]* hops="1"' \
    && ok "(h1) --test-gate=src/covered.cpp: the covering test's row carries hops=\"1\"" \
    || no "(h1) test_covered.cpp row lacks hops=\"1\""
perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" --test-gate=src/covered.cpp,test/test_covered.cpp --no-cache >"$TMP/h2.txt" 2>/dev/null; hrc=$?
grep -q '<t p="test/test_covered.cpp"[^>]*changed="1"' "$TMP/h2.txt" \
    && ok "(h2) a test file IN the change set is a tests_to_run row with changed=\"1\"" \
    || no "(h2) changed test file absent from tests_to_run, or lacks changed=\"1\""
[ "$hrc" = 4 ] && ok "(h3) that run still exits 4 (an obligation exists: run the test you edited)" \
               || no "(h3) exit $hrc, expected 4"
perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" --test-gate=src/covered.cpp,test/test_covered.cpp --no-cache --json 2>/dev/null \
    | grep -q '"p":"test/test_covered.cpp"[^}]*"changed":true' \
    && ok "(h4) the JSON twin carries \"changed\":true on the same row" || no "(h4) JSON twin lacks \"changed\":true"

# ── (i)-(m) #323/#324: TS/JS runner derivation + the <file-scope> untested exclusion ────────────────────
# Fixtures (committed, no git needed — same "changed set as an argument" shape the header comment describes):
#   test/testgatevitestfix/    package.json{devDependencies:vitest, scripts.test:"vitest run"} + src/lib.ts
#                              + src/lib.test.ts  -> run="npx vitest run src/lib.test.ts"
#   test/testgatejestfix/      package.json{devDependencies:jest, scripts.test:"jest"}          -> run="npx jest src/lib.test.ts"
#   test/testgatenodetestfix/  package.json{scripts.test:"node --test"}, .js sources             -> run="node --test src/lib.test.js"
#   test/testgatenorunnerfix/  package.json{devDependencies:mocha, scripts.test:"mocha"} — NONE of the three
#                              named runners: stays run_unknown="1", never a guessed default
#   test/testgatefilescopefix/ the issue's own repro: lib.ts (vitest-covered) + main.ts calling add() at
#                              module scope, reached by no test -> the untested list must NOT contain
#                              <file-scope>, and the run= derivation applies at the same time (#323+#324
#                              together, since #324's own repro is built on the #323 corpus)
runjs(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$ROOT/test/$1" --test-gate="$2" --no-cache 2>/dev/null; }
rcjs(){  perl -e 'alarm 15; exec @ARGV' "$BIN" "$ROOT/test/$1" --test-gate="$2" --no-cache >/dev/null 2>&1; echo $?; }

I="$( runjs testgatevitestfix src/lib.ts )"; IEC="$( rcjs testgatevitestfix src/lib.ts )"
{ [ "$IEC" = 4 ] && printf '%s' "$I" | grep -qF 'run="npx vitest run src/lib.test.ts"'; } \
    && ok '(i) vitest: devDependencies+scripts.test evidence -> run="npx vitest run src/lib.test.ts"' \
    || no "(i) vitest runner not derived (exit=$IEC): $I"

J="$( runjs testgatejestfix src/lib.ts )"; JEC="$( rcjs testgatejestfix src/lib.ts )"
{ [ "$JEC" = 4 ] && printf '%s' "$J" | grep -qF 'run="npx jest src/lib.test.ts"'; } \
    && ok '(j) jest: devDependencies+scripts.test evidence -> run="npx jest src/lib.test.ts"' \
    || no "(j) jest runner not derived (exit=$JEC): $J"

K="$( runjs testgatenodetestfix src/lib.js )"; KEC="$( rcjs testgatenodetestfix src/lib.js )"
{ [ "$KEC" = 4 ] && printf '%s' "$K" | grep -qF 'run="node --test src/lib.test.js"'; } \
    && ok '(k) node:test: scripts.test="node --test" evidence -> run="node --test src/lib.test.js"' \
    || no "(k) node --test runner not derived (exit=$KEC): $K"

# (l) a package.json IS present but names none of the three runners (mocha) — must stay the honest unknown,
#     never guess mocha's CLI shape and never fall back to a default. The obligation still gates (exit 4):
#     an undecidable runner is not the same claim as "no obligation exists".
L="$( runjs testgatenorunnerfix src/lib.ts )"; LEC="$( rcjs testgatenorunnerfix src/lib.ts )"
{ [ "$LEC" = 4 ] && printf '%s' "$L" | grep -q 'run_unknown="1"' && ! printf '%s' "$L" | grep -q ' run="'; } \
    && ok "(l) mocha-only evidence: no guessed runner, stays run_unknown=\"1\" (still gates, exit 4)" \
    || no "(l) no-runner case wrong (exit=$LEC): $L"

# (m) #324: the issue's own combined repro — the module-scope caller in main.ts must never appear as an
#     untested obligation (it can never be tested), while the real vitest coverage of lib.ts still derives.
#     rv-test-gate-tsjs F3: the excluded owner is COUNTED, not silently dropped — untested_modscope="1".
M="$( runjs testgatefilescopefix src/lib.ts )"; MEC="$( rcjs testgatefilescopefix src/lib.ts )"
# F3's own untested_modscope= legend clause names "<file-scope>" in PROSE now (defining what the count is),
# so the no-file-scope-row check is scoped to an actual <u sym=...> ROW, never a bare substring search over
# the whole document (which would now false-positive on the legend's own defining sentence).
{ [ "$MEC" = 4 ] && ! printf '%s' "$M" | grep -qF '<u sym="&lt;file-scope&gt;"' && [ "$( attr "$M" untested )" = 0 ] \
      && [ "$( attr "$M" untested_modscope )" = 1 ] \
      && printf '%s' "$M" | grep -qF 'run="npx vitest run src/lib.test.ts"'; } \
    && ok '(m) #324: <file-scope> excluded from untested (untested=0, untested_modscope=1), vitest run= still derived' \
    || no "(m) file-scope case wrong (exit=$MEC untested=$( attr "$M" untested ) untested_modscope=$( attr "$M" untested_modscope )): $M"

# (n) xml well-formed for the new fixtures too
if command -v xmllint >/dev/null 2>&1; then
    jsxok=1
    for X in "$I" "$J" "$K" "$L" "$M"; do
        [ -n "$X" ] || continue
        printf '%s' "$X" | xmllint --noout - 2>/dev/null || jsxok=0
    done
    if [ "$jsxok" = 1 ]; then ok "(n) xml well-formed (TS/JS runner + file-scope fixtures)"; else no "(n) xml malformed"; fi
else
    printf '  SKIP  (n) xml well-formed, TS/JS fixtures (no xmllint)\n'
fi

# ── (o)-(u) rv-test-gate-tsjs fix round — F1 (lost shell-driver fallback), F2 (wrong runner), F3 (silent
# pass, the fsonly half), F4 (false fail on non-test JS), F5 (marker package.json stops the walk) ──────────
# Fixtures reused from the review's own $ORCH/tmp/rv-test-gate/fx/ (per the coordinator's instruction),
# committed here as test/testgateNNNfix/ in this repo's existing naming convention.

# (o1) F1: a TS/JS test file with NO package.json, but a test/*.sh DRIVER whose own text names it — the
#      driver's evidence must not be discarded now that TS/JS has its own (empty, here) evidence path.
O1="$( runjs testgateshdriverfix src/lib.ts )"; O1EC="$( rcjs testgateshdriverfix src/lib.ts )"
{ [ "$O1EC" = 4 ] && printf '%s' "$O1" | grep -qF 'run="bash test/run_ts.sh"'; } \
    && ok "(o1) F1: no package.json, a shell driver names the test file -> run=\"bash test/run_ts.sh\"" \
    || no "(o1) F1 shell-driver fallback lost (exit=$O1EC): $O1"

# (o2) F1: same driver, but a package.json now exists and names mocha (none of the three) — package.json
#      evidence is inconclusive for TS/JS itself, and the SAME shell-driver fallback must still fire.
O2="$( runjs testgateshdrivermochafix src/lib.ts )"; O2EC="$( rcjs testgateshdrivermochafix src/lib.ts )"
{ [ "$O2EC" = 4 ] && printf '%s' "$O2" | grep -qF 'run="bash test/run_ts.sh"'; } \
    && ok "(o2) F1: mocha package.json (inconclusive) + shell driver -> run=\"bash test/run_ts.sh\"" \
    || no "(o2) F1 fallback lost with an inconclusive manifest present (exit=$O2EC): $O2"

# (o3) F1 on --affected: TestRunnerIndex is the ONE shared class, so the fix must reach every surface built
#      on it, not just --test-gate's own report.
O3="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$ROOT/test/testgateshdriverfix" --affected=src/lib.ts --no-cache --legend=compact 2>/dev/null )"
printf '%s' "$O3" | grep -qF 'run="bash test/run_ts.sh"' \
    && ok "(o3) F1 on --affected: run=\"bash test/run_ts.sh\" (TestRunnerIndex is shared)" \
    || no "(o3) F1 --affected did not carry the driver fallback: $O3"

# (o4) F1 on the MCP affected tool — same shared class, the MCP surface too.
if command -v python3 >/dev/null 2>&1; then
    O4="$( python3 - "$BIN" "$ROOT/test/testgateshdriverfix" <<'PY'
import json, subprocess, sys
BIN, corpus = sys.argv[1], sys.argv[2]
req = "\n".join([
    json.dumps( { "jsonrpc": "2.0", "id": 1, "method": "initialize" } ),
    json.dumps( { "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                  "params": { "name": "affected", "arguments": { "path": corpus, "files": "src/lib.ts" } } } ),
] ) + "\n"
out = subprocess.run( [ BIN, "--mcp" ], input = req, capture_output = True, text = True, timeout = 15 ).stdout
lines = [ l for l in out.splitlines() if l.strip() ]
if not lines:
    print( "__NO_OUTPUT__" ); sys.exit( 0 )
r = json.loads( lines[ -1 ] )
print( r.get( "result", {} ).get( "content", [ {} ] )[ 0 ].get( "text", "__NO_TEXT__:" + str( r ) ) )
PY
)"
    printf '%s' "$O4" | grep -qF 'run="bash test/run_ts.sh"' \
        && ok "(o4) F1 on the MCP affected tool: run=\"bash test/run_ts.sh\"" \
        || no "(o4) F1 MCP affected did not carry the driver fallback: $O4"
else
    printf '  SKIP  (o4) F1 MCP affected check (no python3)\n'
fi

# (p1) F2: scripts.test is AUTHORITATIVE — mocha's own script, with vitest ALSO a devDependency, must never
#      derive vitest (a stray dependency is not permission to override what CI actually runs).
P1="$( runjs testgatemochavitestdepfix src/lib.ts )"; P1EC="$( rcjs testgatemochavitestdepfix src/lib.ts )"
{ [ "$P1EC" = 4 ] && printf '%s' "$P1" | grep -q 'run_unknown="1"' && ! printf '%s' "$P1" | grep -q 'run="npx vitest'; } \
    && ok "(p1) F2: mocha scripts.test + vitest devDependency -> run_unknown=\"1\" (scripts.test wins)" \
    || no "(p1) F2 dependency wrongly overrode scripts.test (exit=$P1EC): $P1"

# (p2) F2: "jest" as a SUBSTRING of an unrelated path token (jest-report-cleaner.js) must not match as a
#      shell WORD; the script names neither vitest/jest/node --test -> run_unknown, never a guessed jest.
P2="$( runjs testgatejestsubstringfix src/lib.ts )"; P2EC="$( rcjs testgatejestsubstringfix src/lib.ts )"
{ [ "$P2EC" = 4 ] && printf '%s' "$P2" | grep -q 'run_unknown="1"' && ! printf '%s' "$P2" | grep -q 'run="npx jest'; } \
    && ok "(p2) F2: 'jest' inside jest-report-cleaner.js is a substring, not a word -> run_unknown=\"1\"" \
    || no "(p2) F2 substring match derived a runner it should not have (exit=$P2EC): $P2"

# (p3) F2 / non-object scripts: scripts is an ARRAY, not an object — must not crash, and reads as "no
#      scripts.test" (absent), so a real jest devDependency is the only evidence and correctly wins. NOT a
#      red/green differentiator for this fixture specifically — topLevelObjectBody already refused a
#      non-object scripts value before this round (both binaries agree), so this arm is coverage proving
#      that "absent" reading is deliberate, not merely never having been exercised.
P3="$( runjs testgatescriptsarrayfix src/lib.ts )"; P3EC="$( rcjs testgatescriptsarrayfix src/lib.ts )"
{ [ "$P3EC" = 4 ] && printf '%s' "$P3" | grep -qF 'run="npx jest src/lib.test.ts"'; } \
    && ok "(p3) F2: non-object scripts (array) does not crash, falls to the real jest dependency" \
    || no "(p3) F2 non-object scripts mishandled (exit=$P3EC): $P3"

# (q) F3: fx/fsonly — a module-scope-only change (no test file anywhere) must disclose untested_modscope="1"
#     rather than a bare, unexplained untested="0" that reads as "nothing to do".
Q="$( runjs testgatefsonlyfix src/lib.ts )"; QEC="$( rcjs testgatefsonlyfix src/lib.ts )"
{ [ "$( attr "$Q" untested )" = 0 ] && [ "$( attr "$Q" untested_modscope )" = 1 ] && [ "$( attr "$Q" impacted )" = 1 ]; } \
    && ok "(q) F3: fsonly discloses untested_modscope=\"1\" (impacted=1, untested=0, exit=$QEC unchanged)" \
    || no "(q) F3 fsonly disclosure wrong (exit=$QEC untested=$( attr "$Q" untested ) untested_modscope=$( attr "$Q" untested_modscope ) impacted=$( attr "$Q" impacted )): $Q"

# (r1) F4: a test-DIRECTORY helper/setup file (isTestPath true, but no .test./.spec. name) must NOT be
#      spelled as a vitest target — vitest's own include-glob would never collect it either.
R1="$( runjs testgatehelperfix test/util.ts )"; R1EC="$( rcjs testgatehelperfix test/util.ts )"
{ [ "$R1EC" = 4 ] && printf '%s' "$R1" | grep -qF '<t p="test/util.ts" changed="1" run_unknown="1"/>' \
      && printf '%s' "$R1" | grep -qF '<t p="test/setup.ts"' && ! printf '%s' "$R1" | grep -qE '<t p="test/setup\.ts"[^>]*run="npx' \
      && printf '%s' "$R1" | grep -qF 'run="npx vitest run test/util.test.ts"'; } \
    && ok "(r1) F4: helper/setup TS files stay run_unknown; the real util.test.ts still derives" \
    || no "(r1) F4 helper/setup wrongly spelled runnable (exit=$R1EC): $R1"

# (r2) F4: a .d.ts declaration file must never be spelled as a vitest/jest target, regardless of evidence.
R2="$( runjs testgatedtsfix test/lib.d.ts )"; R2EC="$( rcjs testgatedtsfix test/lib.d.ts )"
{ [ "$R2EC" = 4 ] && printf '%s' "$R2" | grep -qF '<t p="test/lib.d.ts" changed="1" run_unknown="1"/>'; } \
    && ok "(r2) F4: .d.ts never spelled as a test target -> run_unknown=\"1\"" \
    || no "(r2) F4 .d.ts wrongly spelled runnable (exit=$R2EC): $R2"

# (s) F5: the NEAREST package.json is a bare module-type marker ({"type":"commonjs"}, no scripts/deps) —
#     the walk must keep climbing to the root manifest's real vitest evidence, not stop and report unknown.
S="$( runjs testgatetypemarkerfix src/lib.ts )"; SEC="$( rcjs testgatetypemarkerfix src/lib.ts )"
{ [ "$SEC" = 4 ] && printf '%s' "$S" | grep -qF 'run="npx vitest run src/lib.test.ts"'; } \
    && ok "(s) F5: a non-deciding marker package.json is skipped; the root manifest is used" \
    || no "(s) F5 walk stopped at the marker manifest (exit=$SEC): $S"

# (u1) rv-test-gate-tsjs G1 (regression from the F5 fix): a NESTED package with its own authoritative
#      scripts.test (mocha, unrecognized) must NOT be overridden by an unrelated root manifest's jest —
#      the walk stops at the FIRST manifest with a real scripts.test, recognized or not (F2's rule, one
#      level up a monorepo). Before this fix the walk kept climbing past the "None" mocha manifest and
#      reached the root's jest, deriving a command that finds no matching tests.
U1="$( runjs testgatemonomochafix packages/a/src/lib.ts )"; U1EC="$( rcjs testgatemonomochafix packages/a/src/lib.ts )"
{ [ "$U1EC" = 4 ] && printf '%s' "$U1" | grep -q 'run_unknown="1"' && ! printf '%s' "$U1" | grep -q 'run="npx jest'; } \
    && ok "(u1) G1: a nested authoritative mocha script is not overridden by the root's jest -> run_unknown=\"1\"" \
    || no "(u1) G1 nested authoritative script overridden (exit=$U1EC): $U1"

# (u2) F5's own positive control, one level up a monorepo: a nested package.json that is a TRUE marker
#      (no scripts.test, no vitest/jest dependency — just an unrelated "lodash" dependency and a "type"
#      field) must still let the walk climb to the root's real vitest evidence. Distinguishes (u1)'s
#      "authoritative-but-unrecognized STOPS the walk" from F5's own "decides-nothing CONTINUES it".
U2="$( runjs testgatemonomarkerfix packages/a/src/lib.ts )"; U2EC="$( rcjs testgatemonomarkerfix packages/a/src/lib.ts )"
{ [ "$U2EC" = 4 ] && printf '%s' "$U2" | grep -qF 'run="npx vitest run packages/a/src/lib.test.ts"'; } \
    && ok "(u2) F5 control: a true marker (no script, unrelated dependency) still lets the walk reach the root" \
    || no "(u2) F5 control broken by the G1 fix (exit=$U2EC): $U2"

# (v) G2 (delta review, fixed as a real defect): jest's DEFAULT layout — a test file under a bare
#     __tests__/ directory, no .test./.spec. in its own name — used to be invisible to --test-gate
#     entirely (isTestPath did not recognize the directory, so the file's module scope read as an
#     untestable owner and a COVERED change exited 0 with nothing to run: a false pass). __tests__/ is
#     now a recognized test-path directory segment; the file is a <t> row with its own derived runner.
V="$( runjs testgatejesttestsdirfix src/lib.js )"; VEC="$( rcjs testgatejesttestsdirfix src/lib.js )"
{ [ "$VEC" = 4 ] && printf '%s' "$V" | grep -qF '<t p="src/__tests__/lib.js" hops="1" run="npx jest src/__tests__/lib.js"/>' \
      && [ "$( attr "$V" untested )" = 0 ] && [ "$( attr "$V" untested_modscope )" = 0 ]; } \
    && ok "(v) G2: a bare __tests__/ jest test file is a <t> row, not an untestable owner (exit 4, run=\"npx jest ...\")" \
    || no "(v) G2 __tests__/ still invisible (exit=$VEC untested=$( attr "$V" untested ) untested_modscope=$( attr "$V" untested_modscope )): $V"

# (w) G3: scripts.test delegating through `npm run <script>` to another entry in the same manifest is a
#     STATED FLOOR, not a guess — pinned so it stays exactly this (never silently starts guessing from the
#     dependency, and never crashes trying to follow the indirection) until a real fix follows it.
W="$( runjs testgatenpmrunfix src/lib.ts )"; WEC="$( rcjs testgatenpmrunfix src/lib.ts )"
{ [ "$WEC" = 4 ] && printf '%s' "$W" | grep -q 'run_unknown="1"' && ! printf '%s' "$W" | grep -q 'run="npx vitest'; } \
    && ok "(w) G3: npm run <script> indirection stays the honest run_unknown=\"1\" floor" \
    || no "(w) G3 indirection handling changed unexpectedly (exit=$WEC): $W"

# ── (x1)-(x5) #60 (train 20): the test file's OWN node:test import/require, consulted ONLY when
#     package.json evidence (above) decides nothing for it — closes the issue's last gap, where a bare
#     node:test repro with NO package.json at all stayed run_unknown="1" forever. Fixtures:
#       test/testgatenodetestimportfix/         the issue's own exact repro (src/bounded.ts + test/behavior.test.ts,
#                                                `import test from "node:test"`, no package.json anywhere)
#       test/testgatenodetestimportjsfix/        the .js variant of the same import shape
#       test/testgatenodetestimportrequirefix/   `const test = require("node:test")` (CommonJS)
#       test/testgatenodetestimportnegfix/       "node:test" appears only in a comment and a string — never
#                                                 a real import/require — must NOT derive a runner (parsed,
#                                                 not a substring scan)
#       test/testgatenodetestimportprecedencefix/ package.json scripts.test="vitest run" AND the test file
#                                                 also imports node:test — the explicit manifest evidence
#                                                 must still win

# (x1) the exact #60 repro: no package.json, a .ts test file importing node:test -> derived, and — since
#      nothing here can prove the target Node is >= 23.6 — the conservative, flagged form.
X1="$( runjs testgatenodetestimportfix src/bounded.ts )"; X1EC="$( rcjs testgatenodetestimportfix src/bounded.ts )"
{ [ "$X1EC" = 4 ] && printf '%s' "$X1" | grep -qF 'run="node --experimental-strip-types --test test/behavior.test.ts"'; } \
    && ok '(x1) #60: exact repro (no package.json, import test from "node:test") -> node --experimental-strip-types --test' \
    || no "(x1) #60 repro not derived (exit=$X1EC): $X1"

# (x2) .js variant: no type-stripping question at all, so the bare form.
X2="$( runjs testgatenodetestimportjsfix src/bounded.js )"; X2EC="$( rcjs testgatenodetestimportjsfix src/bounded.js )"
{ [ "$X2EC" = 4 ] && printf '%s' "$X2" | grep -qF 'run="node --test test/behavior.test.js"'; } \
    && ok '(x2) #60: .js variant, import test from "node:test" -> node --test' \
    || no "(x2) #60 .js variant not derived (exit=$X2EC): $X2"

# (x3) require("node:test") — the CommonJS shape.
X3="$( runjs testgatenodetestimportrequirefix src/bounded.js )"; X3EC="$( rcjs testgatenodetestimportrequirefix src/bounded.js )"
{ [ "$X3EC" = 4 ] && printf '%s' "$X3" | grep -qF 'run="node --test test/behavior.test.js"'; } \
    && ok '(x3) #60: require("node:test") -> node --test' \
    || no "(x3) #60 require() variant not derived (exit=$X3EC): $X3"

# (x4) negative control: "node:test" in a comment and a string, no real import/require — must stay the
#      honest unknown (the obligation still gates, exit 4; only the runner is undecided).
X4="$( runjs testgatenodetestimportnegfix src/bounded.js )"; X4EC="$( rcjs testgatenodetestimportnegfix src/bounded.js )"
{ [ "$X4EC" = 4 ] && printf '%s' "$X4" | grep -q 'run_unknown="1"' && ! printf '%s' "$X4" | grep -q 'run="node --test'; } \
    && ok '(x4) #60: "node:test" only in a comment/string -> run_unknown="1" (parsed, not a substring scan)' \
    || no "(x4) #60 negative control wrongly derived a runner (exit=$X4EC): $X4"

# (x5) precedence: an explicit package.json scripts.test still wins over the test file's own node:test
#      import — vitest is named authoritatively, so it is the answer even though the same file imports
#      node:test too (train 18's F2 rule, restated at this new evidence layer).
X5="$( runjs testgatenodetestimportprecedencefix src/lib.ts )"; X5EC="$( rcjs testgatenodetestimportprecedencefix src/lib.ts )"
{ [ "$X5EC" = 4 ] && printf '%s' "$X5" | grep -qF 'run="npx vitest run src/lib.test.ts"' && ! printf '%s' "$X5" | grep -q 'run="node --test'; } \
    && ok '(x5) #60: package.json scripts.test="vitest run" still wins over a node:test import in the same file' \
    || no "(x5) #60 precedence broken, node:test import overrode scripts.test (exit=$X5EC): $X5"

# (x6) xml well-formed for the #60 fixtures
if command -v xmllint >/dev/null 2>&1; then
    x6ok=1
    for X in "$X1" "$X2" "$X3" "$X4" "$X5"; do
        [ -n "$X" ] || continue
        printf '%s' "$X" | xmllint --noout - 2>/dev/null || x6ok=0
    done
    if [ "$x6ok" = 1 ]; then ok "(x6) xml well-formed (#60 node:test import-evidence fixtures)"; else no "(x6) xml malformed"; fi
else
    printf '  SKIP  (x6) xml well-formed, #60 fixtures (no xmllint)\n'
fi

# ── (y1)-(y5) rv-nodetest-runner-60 fix round: a run= that fails is worse than an honest run_unknown="1"
#     (the owner's own re-sign rule). Each of these was WRONGLY derived by the first cut of #60's fix —
#     RED-FIRST arms: each one reproduces the reviewer's finding against the pre-fix binary and pins the
#     honest run_unknown="1" going forward. Fixtures:
#       test/testgatenodetesttsxfix/                 F1: a .tsx test file — Node's type stripping does not
#                                                     cover .tsx at all (ERR_UNKNOWN_FILE_EXTENSION)
#       test/testgatenodetestjsxfix/                 F1: a .jsx test file — plain node cannot load .jsx,
#                                                     with or without any flag
#       test/testgatenodetestnoextfix/                F2: a .ts test file whose own relative import has NO
#                                                     extension — Node's resolver under type stripping never
#                                                     probes for one
#       test/testgatenodetestengineslowfix/           F3: engines.node=">=18" (below the 22.6 floor the flag
#                                                     itself needs) even though the import is fully resolvable
#       test/testgatenodetestenginescompoundfix/      F3: engines.node=">=24 || ^20" — the LOWEST admitted
#                                                     alternative (^20) is what decides it, not the highest

# (y1) F1: .tsx can never be spelled, whatever the import evidence says.
Y1="$( runjs testgatenodetesttsxfix src/bounded.ts )"; Y1EC="$( rcjs testgatenodetesttsxfix src/bounded.ts )"
{ [ "$Y1EC" = 4 ] && printf '%s' "$Y1" | grep -q 'run_unknown="1"' && ! printf '%s' "$Y1" | grep -q 'run="node'; } \
    && ok '(y1) F1: .tsx test file stays run_unknown="1" (Node cannot type-strip .tsx)' \
    || no "(y1) F1 .tsx wrongly derived a runner (exit=$Y1EC): $Y1"

# (y2) F1: .jsx can never be spelled either — plain node cannot load it at all.
Y2="$( runjs testgatenodetestjsxfix src/bounded.js )"; Y2EC="$( rcjs testgatenodetestjsxfix src/bounded.js )"
{ [ "$Y2EC" = 4 ] && printf '%s' "$Y2" | grep -q 'run_unknown="1"' && ! printf '%s' "$Y2" | grep -q 'run="node'; } \
    && ok '(y2) F1: .jsx test file stays run_unknown="1" (node cannot load .jsx)' \
    || no "(y2) F1 .jsx wrongly derived a runner (exit=$Y2EC): $Y2"

# (y3) F2: an extensionless relative import in a .ts test file — Node's resolver never probes for one.
Y3="$( runjs testgatenodetestnoextfix src/bounded.ts )"; Y3EC="$( rcjs testgatenodetestnoextfix src/bounded.ts )"
{ [ "$Y3EC" = 4 ] && printf '%s' "$Y3" | grep -q 'run_unknown="1"' && ! printf '%s' "$Y3" | grep -q 'run="node'; } \
    && ok '(y3) F2: extensionless relative import stays run_unknown="1" (no probing under type stripping)' \
    || no "(y3) F2 extensionless import wrongly derived a runner (exit=$Y3EC): $Y3"

# (y4) F3: engines.node=">=18" admits a Node where --experimental-strip-types itself is a fatal bad option.
Y4="$( runjs testgatenodetestengineslowfix src/bounded.ts )"; Y4EC="$( rcjs testgatenodetestengineslowfix src/bounded.ts )"
{ [ "$Y4EC" = 4 ] && printf '%s' "$Y4" | grep -q 'run_unknown="1"' && ! printf '%s' "$Y4" | grep -q 'run="node'; } \
    && ok '(y4) F3: engines.node=">=18" stays run_unknown="1" (below the flag'"'"'s own 22.6 floor)' \
    || no "(y4) F3 low engines floor wrongly derived a runner (exit=$Y4EC): $Y4"

# (y5) F3: a compound engines.node range — the LOWEST admitted alternative decides it, not the highest.
Y5="$( runjs testgatenodetestenginescompoundfix src/bounded.ts )"; Y5EC="$( rcjs testgatenodetestenginescompoundfix src/bounded.ts )"
{ [ "$Y5EC" = 4 ] && printf '%s' "$Y5" | grep -q 'run_unknown="1"' && ! printf '%s' "$Y5" | grep -q 'run="node'; } \
    && ok '(y5) F3: engines.node=">=24 || ^20" stays run_unknown="1" (the ^20 alternative decides it)' \
    || no "(y5) F3 compound engines range wrongly derived a runner (exit=$Y5EC): $Y5"

# (y6) xml well-formed for the fix-round F1-F3 fixtures
if command -v xmllint >/dev/null 2>&1; then
    y6ok=1
    for X in "$Y1" "$Y2" "$Y3" "$Y4" "$Y5"; do
        [ -n "$X" ] || continue
        printf '%s' "$X" | xmllint --noout - 2>/dev/null || y6ok=0
    done
    if [ "$y6ok" = 1 ]; then ok "(y6) xml well-formed (rv-nodetest-runner-60 F1-F3 fixtures)"; else no "(y6) xml malformed"; fi
else
    printf '  SKIP  (y6) xml well-formed, F1-F3 fixtures (no xmllint)\n'
fi

# (t) xml well-formed for the fix-round fixtures
if command -v xmllint >/dev/null 2>&1; then
    tok=1
    for X in "$O1" "$O2" "$P1" "$P2" "$P3" "$Q" "$R1" "$R2" "$S" "$U1" "$U2" "$V" "$W"; do
        [ -n "$X" ] || continue
        printf '%s' "$X" | xmllint --noout - 2>/dev/null || tok=0
    done
    if [ "$tok" = 1 ]; then ok "(t) xml well-formed (fix-round fixtures)"; else no "(t) xml malformed"; fi
else
    printf '  SKIP  (t) xml well-formed, fix-round fixtures (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
