#!/usr/bin/env bash
# textpoolcheck.sh — MEM-REF-SHRINK step 2: src/infra/internedtext.h's shared text pool (Reference / RawRef names as 4 B ids).
# Compiles test/textpool_harness.cpp (header-only: no ripwire objects) twice and runs it:
#   [g1]   the G1 sanitizer set with -fno-sanitize-recover=all: arms A-D (canonical ids under 8 threads, the empty id, text order,
#          edits) on a binary where UB or a bad slot index aborts;
#   [tsan] ThreadSanitizer, arm A's 8 interning threads: a missing shard lock or an unpublished segment pointer is a reported race.
#          SKIP (not FAIL) when the toolchain cannot build or start a TSan binary; the g1 pass still runs.
# Usage: test/textpoolcheck.sh [BIN]   (BIN unused: the harness needs no ripwire binary). Exits non-zero on any FAIL.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/scripts/asanprobe.sh"
CXX="$( ripwire_asan_pick_cxx "${CXX:-}" )"
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
HARNESS="$ROOT/test/textpool_harness.cpp"
WORK="$( mktemp -d )"; trap 'gate_bounded_reap; rm -rf "$WORK"' EXIT; gate_bounded_arm
echo "textpoolcheck: CXX=$CXX"
fail=0

build_run()
{
    local LABEL="$1"; shift
    if ! "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra "$@" -I"$ROOT/src" -I"$ROOT/third_party" "$HARNESS" -o "$WORK/h_$LABEL" -pthread 2> "$WORK/cc_$LABEL.log"; then
        return 3
    fi
    "$WORK/h_$LABEL" > "$WORK/out_$LABEL.log" 2>&1
}

if ripwire_asan_probe "$CXX" "$WORK"; then
    SAN="-fsanitize=address,undefined,integer,float-divide-by-zero,float-cast-overflow"
    printf 'int main(){return 0;}\n' > "$WORK/probe.cpp"
    "$CXX" $SAN -fsyntax-only "$WORK/probe.cpp" 2>/dev/null || SAN="-fsanitize=address,undefined"
    build_run g1 $SAN -fno-sanitize-recover=all; rc=$?
else
    echo "  NOTE  [g1] $RIPWIRE_ASAN_PROBE_WHY: running the plain build instead"
    build_run g1; rc=$?
fi
if [ "$rc" -eq 3 ]; then echo "  FAIL  [g1] harness failed to compile"; sed 's/^/    /' "$WORK/cc_g1.log"; exit 2; fi
if [ "$rc" -ne 0 ] || ! grep -q "textpool: ALL PASS" "$WORK/out_g1.log"; then
    echo "  FAIL  [g1] rc=$rc"; grep -v '^  PASS' "$WORK/out_g1.log" | head -20 | sed 's/^/    /'; fail=1
else
    echo "  PASS  [g1] $( grep -c '^  PASS' "$WORK/out_g1.log" ) harness arms green"
fi

printf 'int main(){return 0;}\n' > "$WORK/tprobe.cpp"
if "$CXX" -fsanitize=thread "$WORK/tprobe.cpp" -o "$WORK/tprobe" 2>/dev/null && "$WORK/tprobe" 2>/dev/null; then
    TSAN_OPTIONS="halt_on_error=1" build_run tsan -fsanitize=thread; rc=$?
    if [ "$rc" -ne 0 ] || grep -q "WARNING: ThreadSanitizer" "$WORK/out_tsan.log" || ! grep -q "textpool: ALL PASS" "$WORK/out_tsan.log"; then
        echo "  FAIL  [tsan] rc=$rc"; grep -A 12 "ThreadSanitizer\|FAIL" "$WORK/out_tsan.log" | head -30 | sed 's/^/    /'; fail=1
    else
        echo "  PASS  [tsan] arm A's 8 interning threads race-free"
    fi
else
    echo "  SKIP  [tsan] this toolchain cannot build or start a ThreadSanitizer binary"
fi

[ "$fail" -eq 0 ] && echo "textpoolcheck: PASS" || echo "textpoolcheck: FAIL"
exit "$fail"
