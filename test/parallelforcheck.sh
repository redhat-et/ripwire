#!/usr/bin/env bash
# parallelforcheck.sh — warmsnap::parallelFor's granularity contract, and the one claim the fix
# behind it cannot make by argument: that the worker count cannot change an answer.
#
# THE DEFECT THIS GATE EXISTS FOR. parallelFor picks workers from the ITEM COUNT —
# min( hardware_concurrency, ceil( n / itemsPerWorker ) ), serial at one worker. The default
# itemsPerWorker of 2048 suits a caller whose item is cheap and silently serialises one whose item
# is coarse. readRefRows passes the CHUNK count: measured, llvm-project has 1,449 reference chunks,
# ceil( 1449 / 2048 ) == 1, and ~5.94 M reference rows decode on one core of eighteen — in a format
# whose own comment says chunks decode in parallel. Effective threads measured 1.00 on both envoy and
# llvm-project (per-chunk thread time over parallel-region wall; a ratio, so contention can only
# depress it and 1.00 can only mean one worker).
#
# Arms A and B live in test/parallelforcheck_harness.cpp — thread-id COUNTS, not timings, because the
# house forbids perf-budget gates and a timing arm on a shared runner is a flake.
#
# Arm C is here, because it needs the product binary. The fix makes the worker count variable, so the
# risk it introduces is that an answer starts depending on it. That is the claim that is cheap to
# argue and expensive to be wrong about, so it is measured: two runs at different worker counts must
# write byte-identical maps. RIPWIRE_PARALLEL_WORKERS exists for this arm and for nothing else — it
# is a TEST SEAM, not a tuning knob, exactly as RIPWIRE_PARSE_THREADS is for
# test/snapdeterminismcheck.sh. Arm C and the seam justify each other: without the seam the claim
# cannot be demonstrated, and without the claim the seam has no reason to exist.
#
# Arm D proves the seam is inert when unset — measured, not read off the source.
#
# Usage:  bash test/parallelforcheck.sh [path/to/ripwire]
#         CXX=clang++ RIPWIRE_BIN=… bash test/parallelforcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
CXX="${CXX:-c++}"
HARNESS="$ROOT/test/parallelforcheck_harness.cpp"

echo "parallelforcheck: BIN=$BIN $( "$BIN" --version 2>/dev/null | head -1 )"

fail=0
note() { echo "  FAIL  $*"; fail=1; }
ok()   { echo "  ok    $*"; }

[ -x "$BIN" ] || { echo "  FAIL  no binary at $BIN"; exit 2; }
[ -f "$HARNESS" ] || { echo "  FAIL  $HARNESS is missing"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT

# ── arms A + B: compile and run the harness ─────────────────────────────────────────────────────────
# A compile failure is a RED, not an error: the harness calls the three-argument parallelFor, so on a
# tree without it there is nothing to test and the gate must say so rather than skip.
. "$ROOT/scripts/cxxstd.sh" 2>/dev/null || true
CXXSTD="$( ripwire_cxx_std_flag "$CXX" 2>/dev/null || echo -std=c++23 )"
# diagnostics.cpp is NOT optional: VALIDATE's failure path calls ::Diagnostics::ConsoleLog::
# handleValidateFailed, which lives out of line there — the same reason CMakeLists.txt lists it for
# every verify_* target. Without it the harness fails to LINK, which would read as "the itemsPerWorker
# argument is missing" and send a reader to the wrong file.
if ! "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra -pthread \
        -I"$ROOT/src" -I"$ROOT/src/infra" -I"$ROOT/third_party" \
        "$HARNESS" "$ROOT/src/infra/diagnostics.cpp" -o "$WORK/harness" 2> "$WORK/cc.log"; then
    if grep -q "no matching function\|too many arguments" "$WORK/cc.log"; then
        note "arms A+B: parallelFor has no itemsPerWorker argument on this tree"
    else
        note "arms A+B: the harness did not build (see below) — note this is NOT necessarily a missing argument"
    fi
    sed 's/^/        /' "$WORK/cc.log" | head -12
else
    # The harness carries its own assertions, so its EXIT STATUS is the arm -- not its stdout. Run it
    # unpiped into a file and branch on the status with `if`: a pipeline's status is the last stage's,
    # so `harness | sed` reports sed's success and loses every assertion the harness made.
    # ${PIPESTATUS[0]} would read correctly here but test/gateexitcheck.sh arm H1 does not credit it
    # (its accepted forms are if / || / && .. || / rc=$? compared / set -e / pipefail), and a status
    # test a reader cannot see is the same hazard as one that is not there.
    if "$WORK/harness" > "$WORK/harness.out" 2>&1; then
        sed 's/^/  /' "$WORK/harness.out"
    else
        sed 's/^/  /' "$WORK/harness.out"
        note "arms A+B: the harness ran but its own assertions FAILED (exit status above zero)"
    fi
fi

# ── arm C: the worker count cannot change an answer ─────────────────────────────────────────────────
# One corpus, two worker counts, byte-identical maps. The fixture is small; what matters is that the
# reference and bind chunk decodes run at both 1 worker and many, and they do at any size.
CORPUS="$ROOT/src"
mkdir -p "$WORK/c1" "$WORK/t1" "$WORK/cN" "$WORK/tN"
RIPWIRE_SNAPSHOT_STATS=1 XDG_CACHE_HOME="$WORK/c1" TMPDIR="$WORK/t1" RIPWIRE_PARALLEL_WORKERS=1 \
    "$BIN" "$CORPUS" --top-k=40 > "$WORK/w1.xml" 2> "$WORK/w1.err"
RIPWIRE_SNAPSHOT_STATS=1 XDG_CACHE_HOME="$WORK/cN" TMPDIR="$WORK/tN" RIPWIRE_PARALLEL_WORKERS=16 \
    "$BIN" "$CORPUS" --top-k=40 > "$WORK/wN.xml" 2> "$WORK/wN.err"

# THE PRECONDITION, checked before the comparison is believed. An arm that compares two runs which
# used the SAME worker count passes while proving nothing — and that is not hypothetical: on the tree
# before the seam existed, this arm read green because the variable was simply ignored. So the two
# runs must be SEEN to differ in `parallel_workers=` first.
got1="$( grep -o 'parallel_workers=[0-9]*' "$WORK/w1.err" | head -1 )"
gotN="$( grep -o 'parallel_workers=[0-9]*' "$WORK/wN.err" | head -1 )"
if [ ! -s "$WORK/w1.xml" ] || [ ! -s "$WORK/wN.xml" ]; then
    note "arm C: one of the two runs produced no map"
    head -3 "$WORK/w1.err" "$WORK/wN.err" | sed 's/^/        /'
elif grep -q "ignoring RIPWIRE_PARALLEL_WORKERS" "$WORK/w1.err" "$WORK/wN.err" 2>/dev/null; then
    note "arm C: the binary REFUSED RIPWIRE_PARALLEL_WORKERS, so both runs used the same worker count and this arm would compare a run with itself"
elif [ -z "$got1" ] || [ -z "$gotN" ]; then
    note "arm C: no parallel_workers= in snapshot-stats (got '${got1:-nothing}' / '${gotN:-nothing}') — the worker count is not observable, so this arm cannot show the two runs differed and must not be trusted"
elif [ "$got1" = "$gotN" ]; then
    note "arm C: both runs report $got1 — the seam did not take effect, so comparing their maps proves nothing"
elif [ "$got1" != "parallel_workers=1" ]; then
    note "arm C: the 1-worker run reports $got1, not parallel_workers=1 — the seam is not honoured"
elif cmp -s "$WORK/w1.xml" "$WORK/wN.xml"; then
    ok "arm C: $got1 and $gotN write byte-identical maps ($( wc -c < "$WORK/wN.xml" | tr -d ' ' ) B)"
else
    note "arm C: the map DIFFERS between 1 worker and 16 — an answer depends on the worker count"
    cmp "$WORK/w1.xml" "$WORK/wN.xml" | head -2 | sed 's/^/        /'
fi

# ── arm C control: the comparison can fail ──────────────────────────────────────────────────────────
# Arm C compares two runs of one binary, so a cmp that could never differ would pass it in silence.
# Feeding it two deliberately different maps must be SEEN to differ.
XDG_CACHE_HOME="$WORK/cN" TMPDIR="$WORK/tN" "$BIN" "$CORPUS" --top-k=41 > "$WORK/wX.xml" 2>/dev/null
if cmp -s "$WORK/wN.xml" "$WORK/wX.xml"; then
    note "arm C control: --top-k=40 and --top-k=41 compared EQUAL, so arm C's cmp cannot distinguish two maps and proved nothing"
else
    ok "arm C control: two deliberately different maps ARE seen to differ (arm C's cmp is not vacuous)"
fi

# ── arm D: the seam is inert when unset ─────────────────────────────────────────────────────────────
# Measured, not read. An UNSET run must match a run at the box's own worker count, and must not be
# folded into the cache key — a seam that re-keys the snapshot is not zero cost, it is a cache miss.
RIPWIRE_SNAPSHOT_STATS=1 RIPWIRE_CACHE_STATS=1 XDG_CACHE_HOME="$WORK/cN" TMPDIR="$WORK/tN" \
    "$BIN" "$CORPUS" --top-k=40 > "$WORK/wU.xml" 2> "$WORK/wU.err"
if ! cmp -s "$WORK/wN.xml" "$WORK/wU.xml"; then
    note "arm D: an UNSET run differs from one at 16 workers — the seam is not inert"
elif grep -qE "reparsed=[1-9]" "$WORK/wU.err" 2>/dev/null; then
    note "arm D: the UNSET run re-parsed after a run with the variable set — the seam is folded into the cache key, so setting it costs a full re-index"
else
    ok "arm D: unset matches 16 workers byte for byte, and set/unset share one cache (the seam is a pure observer)"
fi

# ── arm D control: the re-index detector can fire ───────────────────────────────────────────────────
# Arm D concludes "no re-index" from a grep finding nothing, and a grep that could never match would
# pass it in silence. A deliberately COLD run must be seen to match the same pattern.
mkdir -p "$WORK/cold_c" "$WORK/cold_t"
RIPWIRE_CACHE_STATS=1 XDG_CACHE_HOME="$WORK/cold_c" TMPDIR="$WORK/cold_t" \
    "$BIN" "$CORPUS" --top-k=40 > /dev/null 2> "$WORK/cold.err"
if grep -qE "reparsed=[1-9]" "$WORK/cold.err" 2>/dev/null; then
    ok "arm D control: a cold run IS seen to report reparsed=[1-9] (arm D's detector is not vacuous)"
else
    note "arm D control: a cold run did not match reparsed=[1-9] ($( grep -o 'reparsed=[0-9]*' "$WORK/cold.err" | head -1 )) — arm D's detector cannot fire, so its green proved nothing"
fi

if [ "$fail" -ne 0 ]; then
    echo "parallelforcheck: FAIL"
    exit 1
fi
echo "parallelforcheck: PASS"
