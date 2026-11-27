#!/usr/bin/env bash
# verbscopecheck.sh — the per-verb and per-request PROFILE_SCOPEs exist, are placed where they claim
# to be, and cost the default binary nothing (lane/large-repo-perf, 2026-11-27).
#
# WHY. `main.cpp`'s "query + emit (the verb, after the graph)" scope carried a comment saying "the
# verbs' own scopes nest inside it". For the --for family that was aspirational: `runForLens`,
# `runForVerbRoute` and `runPackTask` had no scopes, so the scope nested nothing and a warm
# llvm-project --for read 2,920 ms in ONE unlabelled bucket -- the largest per-query term in the
# profile. Worse, the MCP server has its own dispatch and never enters `dispatchMainBody`, so the
# path agents actually use had no per-call timer at all, which is how a per-query cost came to be
# read off a one-invocation cold row.
#
# A profiler's placement cannot be checked by reading its numbers -- any placement produces
# plausible numbers. So this gate checks the two things that can actually be wrong:
#
#   (A) PLACEMENT, in the source. Each named dispatch seam is governed by a PROFILE_SCOPE_DESCRIBE.
#       Arm B is the control that keeps A from being vacuous: a seam deliberately left
#       uninstrumented must be REPORTED uninstrumented by the same matcher. Without B, a matcher
#       that says "instrumented" for every line on earth would pass A.
#   (C) ZERO COST WHEN OFF, in the binary. The default build must emit no scope text and no
#       #PROF_TSV block on any stream. This is the contract that lets the markers exist at all.
#   (D) BEHAVIOUR, when a profile build is available: the scopes must actually fire, with calls>=1.
#       Skipped with a reason when there is no profile tree, in the pmccheck.sh manner -- the arm
#       the machine can express is asserted, and the skip says which arm was not.
#
# Usage:  bash test/verbscopecheck.sh [path/to/ripwire]
#         RIPWIRE_BIN=… RIPWIRE_PROF_BIN=build_prof/ripwire bash test/verbscopecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
PROF_BIN="${RIPWIRE_PROF_BIN:-$ROOT/build_prof/ripwire}"

echo "verbscopecheck: BIN=$BIN $( "$BIN" --version 2>/dev/null | head -1 )"

fail=0
note() { echo "  FAIL  $*"; fail=1; }
ok()   { echo "  ok    $*"; }

[ -x "$BIN" ] || { echo "  FAIL  no binary at $BIN"; exit 2; }

# ── the matcher: is CALL inside FILE governed by a PROFILE_SCOPE_DESCRIBE? ───────────────────────────
# "Governed" = a PROFILE_SCOPE_DESCRIBE appears above the call, after the last line that CLOSES a
# block at or below the call's indentation. Deliberately simple and shared by arms A and B, so the
# control in B tests the same code path that A relies on.
governed() {
    awk -v call="$2" '
        index($0, "PROFILE_SCOPE_DESCRIBE(") { scope = NR; next }
        index($0, call) && !index($0, "//") { print (scope > 0 && NR - scope <= 6) ? "yes" : "no"; found = 1; exit }
        /^    \}/ { scope = 0 }
        END { if (!found) print "absent" }
    ' "$1"
}

# ── Arm A: the seams that must be instrumented ──────────────────────────────────────────────────────
for pair in \
    "src/main.cpp|runForVerbRoute( dsp )" \
    "src/main.cpp|runForLens( dsp )" \
    "src/main.cpp|runPackTask( dsp )" \
    "src/main.cpp|runDefaultMap( dsp )"
do
    f="${pair%%|*}"; call="${pair##*|}"
    case "$( governed "$ROOT/$f" "$call" )" in
        yes)    ok "arm A: $call is governed by a PROFILE_SCOPE in $f" ;;
        no)     note "arm A: $call is NOT governed by a PROFILE_SCOPE in $f — its cost falls into the enclosing bucket" ;;
        absent) note "arm A: $call not found in $f — this gate's seam list is stale, which is a gate bug, not a pass" ;;
    esac
done

# -A20, not -A4: the scope sits under a comment block explaining why the per-call unit needs its own
# timer, and a window tight enough to exclude a comment would make this arm fail on a correct tree.
if grep -A20 'inline McpDispatchResult dispatchMcpLine' "$ROOT/src/mcp.h" | grep -q 'PROFILE_SCOPE_DESCRIBE('; then
    ok "arm A: dispatchMcpLine carries the per-request scope (the agent path's per-call unit)"
else
    note "arm A: dispatchMcpLine has no PROFILE_SCOPE — an MCP session then has no per-call timer, and a per-query cost can only be guessed from a per-index row"
fi

# ── Arm B: the control. An uninstrumented seam must read as uninstrumented ───────────────────────────
# runTargetedViews is deliberately NOT instrumented (main.cpp says four seams on purpose, not fifty).
case "$( governed "$ROOT/src/main.cpp" "runTargetedViews( dsp )" )" in
    no)     ok "arm B: the matcher reports the deliberately-uninstrumented runTargetedViews as uninstrumented (arm A is not vacuous)" ;;
    yes)    note "arm B: the matcher calls runTargetedViews governed, but nothing instruments it — the matcher says yes to anything, so arm A proved nothing" ;;
    absent) note "arm B: runTargetedViews not found — pick another uninstrumented seam for the control" ;;
esac

# ── Arm C: zero cost when off, in the shipped default build ─────────────────────────────────────────
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
"$BIN" "$ROOT/test/largescalefix" --top-k=1 > "$WORK/out.xml" 2> "$WORK/out.err"
leak=0
for pat in '#PROF_TSV' 'mcp: handle one request' 'verb/for:' 'hottest scopes'; do
    if grep -qF "$pat" "$WORK/out.xml" "$WORK/out.err" 2>/dev/null; then
        note "arm C: the DEFAULT build emitted profiler text ($pat) — PROFILE_SCOPE is not compiling out"
        leak=1
    fi
done
[ "$leak" -eq 0 ] && ok "arm C: the default build emits no profiler text on stdout or stderr"

# ── Arm D: the scopes actually fire, when a profile build exists ─────────────────────────────────────
if [ ! -x "$PROF_BIN" ]; then
    echo "  SKIP  arm D (do the scopes fire?): no profile build at $PROF_BIN — configure one with"
    echo "        cmake -S . -B build_prof -DRIPWIRE_PROFILE=ON && cmake --build build_prof -j"
    echo "        Arms A-C asserted; the behavioural arm is the one this machine did not express."
else
    XDG_CACHE_HOME="$WORK/c" TMPDIR="$WORK/t" "$PROF_BIN" "$ROOT/test/largescalefix" \
        --for="resolve a symbol reference" > /dev/null 2> "$WORK/prof.err"
    for scope in 'main: query + emit' 'verb/for: runForLens'; do
        line="$( awk -F'\t' -v s="$scope" '
            /^#PROF_TSV_BEGIN/ { f = 1; next } /^#PROF_TSV_END/ { f = 0 }
            f && index($1, s) == 1 { print $4; exit }' "$WORK/prof.err" )"
        if [ -n "$line" ] && [ "$line" -ge 1 ] 2>/dev/null; then
            ok "arm D: '$scope' fired, calls=$line"
        else
            note "arm D: '$scope' did not appear in the #PROF_TSV block with calls>=1 (got '${line:-nothing}')"
        fi
    done
fi

if [ "$fail" -ne 0 ]; then
    echo "verbscopecheck: FAIL"
    exit 1
fi
echo "verbscopecheck: PASS"
