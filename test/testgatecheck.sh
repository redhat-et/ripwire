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
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # BOTH seams: positional and RIPWIRE_BIN
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
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
# basenames of the emitted <t p="..."/> test rows, sorted
tset(){ printf '%s' "$1" | grep -oE '<t p="[^"]*"' | grep -oE '[^/"]*"$' | sed 's/"$//' | sort | tr '\n' ','; }
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
    [ "$xok" = 1 ] && ok "(f) xml well-formed (all variants)" || no "(f) xml malformed"
else
    printf '  SKIP  (f) xml well-formed (no xmllint)\n'
fi


# ── (g) §B12.5 — untested= IS THREE DIFFERENT UNITS, and each legend now says which ──────────────────────
# `untested=` counts cross-directory call EDGES in --seams, impacted SYMBOLS here, and gate-lit HOSTS in
# --flip. Every one of those legends was locally honest, which is exactly how a reader who compares two of
# the numbers is misled — the R13 shape lifted one level. Swept over the WHOLE emitting family from source,
# not from a remembered list: whatever spells untested= must carry the clause.
UNIT_FAM="$( grep -rlF 'untested=\"' "$ROOT/src" 2>/dev/null | sed 's|.*/||' | sort | tr '\n' ' ' )"
probe_unit(){ "$BIN" "$ROOT" $1 2>/dev/null | grep -oE '<!--.*?-->' | head -1; }
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

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
