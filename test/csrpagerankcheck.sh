#!/usr/bin/env bash
# csrpagerankcheck.sh — gate for CSR structure / verification and the PageRank kernel.
#
# Drives the CMake targets `ripwire_test_csr` (test/verify_csr.cpp) and `ripwire_test_pagerank`
# (test/verify_pagerank.cpp), enforcing the CSR property contract and numeric convergence.
#
# FOUR ARMS:
#   0  PRESENCE: both targets appear in CMakeLists.txt and both sources exist on disk.
#   1  CMAKE, FULL G1 SANITIZERS: -DRIPWIRE_TESTS=ON -DRIPWIRE_ASAN=ON -DFETCHCONTENT_FULLY_DISCONNECTED=ON.
#      Runs ripwire_test_csr and ripwire_test_pagerank under ASan, UBSan, and LSan.
#      Asserts exit 0, 0 failures, and case / assertion tallies >= floors.
#   2  DIRECT $CXX, -DNDEBUG -O2: compiles verify_pagerank.cpp directly with -fno-fast-math,
#      running K12, K13, K14 to prove the truncation and non-convergence return values survive NDEBUG.
#   3  MUTATION TESTING: CAN GO RED:
#      M1: deletes ++iterationCount; in converged loop (src/pagerank.cpp) -> K1, K3, K12 fail.
#      M2: drops config.alpha * danglingMass + (src/pagerank.cpp) -> K3, K6 fail.
#      M3: removes || values[edgeIndex] < T( 0 ) from src/infra/csrverify.h -> C5j fails.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"

. "$ROOT/scripts/cxxstd.sh"
. "$ROOT/scripts/asanprobe.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
WORK="$( mktemp -d )"; trap 'gate_bounded_reap; rm -rf "$WORK"' EXIT; gate_bounded_arm
ARCH="$( uname -m )"
fail=0

MIN_CSR_CASES=15
MIN_CSR_ASSERTS=40
MIN_PR_CASES=25
MIN_PR_ASSERTS=80

echo "csrpagerankcheck: CXX=$CXX arch=$ARCH targets=ripwire_test_csr,ripwire_test_pagerank"

# ── Arm 0: Presence ──────────────────────────────────────────────────────────────────────────────
if ! grep -q "add_executable(ripwire_test_csr" "$ROOT/CMakeLists.txt" || \
   ! grep -q "add_executable(ripwire_test_pagerank" "$ROOT/CMakeLists.txt"; then
    echo "  FAIL  targets ripwire_test_csr / ripwire_test_pagerank missing from CMakeLists.txt"
    fail=1
fi
if [ ! -f "$ROOT/test/verify_csr.cpp" ] || [ ! -f "$ROOT/test/verify_pagerank.cpp" ]; then
    echo "  FAIL  test source files test/verify_csr.cpp / test/verify_pagerank.cpp missing on disk"
    fail=1
fi
if [ "$fail" -ne 0 ]; then
    exit 2
fi
echo "  PASS  arm 0: target definitions and source files present"

# ── Arm 1: CMake target, under G1 sanitizers ─────────────────────────────────────────────────────
read_counts()   # $1 = log; sets CASES, CASES_PASS, ASSERTS, ASSERTS_FAIL
{
    CASES="$(        sed -n 's/^\[doctest\] test cases: *\([0-9][0-9]*\) .*/\1/p'                "$1" | tail -1 )"
    CASES_PASS="$(   sed -n 's/^\[doctest\] test cases: *[0-9][0-9]* | *\([0-9][0-9]*\) passed.*/\1/p' "$1" | tail -1 )"
    ASSERTS="$(      sed -n 's/^\[doctest\] assertions: *\([0-9][0-9]*\) .*/\1/p'                "$1" | tail -1 )"
    ASSERTS_FAIL="$( sed -n 's/.*| *\([0-9][0-9]*\) failed |$/\1/p'                            "$1" | tail -1 )"
    : "${CASES:=0}" "${CASES_PASS:=0}" "${ASSERTS:=0}" "${ASSERTS_FAIL:=0}"
}

if ! ripwire_asan_probe "$CXX" "$WORK"; then
    echo "csrpagerankcheck: SKIP arm 1 — $RIPWIRE_ASAN_PROBE_WHY"
else
    if ! cmake -S "$ROOT" -B "$WORK/cmb" -DRIPWIRE_TESTS=ON -DRIPWIRE_ASAN=ON \
            -DFETCHCONTENT_FULLY_DISCONNECTED=ON > "$WORK/cfg.log" 2>&1; then
        echo "  FAIL  cmake configure (-DRIPWIRE_TESTS=ON -DRIPWIRE_ASAN=ON) failed"
        tail -20 "$WORK/cfg.log" | sed 's/^/    /'
        fail=1
    elif ! cmake --build "$WORK/cmb" --target ripwire_test_csr ripwire_test_pagerank -j 2 > "$WORK/build.log" 2>&1; then
        echo "  FAIL  targets failed to build under G1 sanitizers"
        tail -30 "$WORK/build.log" | sed 's/^/    /'
        fail=1
    else
        if [ "$( uname -s )" = "Darwin" ]; then
            ASAN_OPTS="detect_leaks=0:halt_on_error=1:abort_on_error=1"
        else
            ASAN_OPTS="detect_leaks=1:halt_on_error=1:abort_on_error=1"
        fi
        
        # Run ripwire_test_csr
        ASAN_OPTIONS="$ASAN_OPTS" UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
            LSAN_OPTIONS="suppressions=$ROOT/lsan_suppressions.txt" RIPWIRE_ROOT="$ROOT" \
            "$WORK/cmb/ripwire_test_csr" > "$WORK/out_csr.log" 2>&1
        rc_csr=$?
        read_counts "$WORK/out_csr.log"
        if [ "$rc_csr" -ne 0 ] || [ "${ASSERTS_FAIL:-1}" != "0" ]; then
            echo "  FAIL  ripwire_test_csr failed under sanitizers (exit $rc_csr, $ASSERTS_FAIL failed):"
            grep -B 2 -A 6 'ERROR\|FAILED' "$WORK/out_csr.log" | sed 's/^/    /' | head -40
            fail=1
        elif [ "$ASSERTS" -lt "$MIN_CSR_ASSERTS" ] || [ "$CASES" -lt "$MIN_CSR_CASES" ]; then
            echo "  FAIL  ripwire_test_csr ran $CASES cases / $ASSERTS assertions; below floor $MIN_CSR_CASES / $MIN_CSR_ASSERTS"
            fail=1
        else
            printf '  PASS  ripwire_test_csr: %s test cases / %s assertions green under G1 sanitizers\n' "$CASES" "$ASSERTS"
        fi

        # Run ripwire_test_pagerank
        ASAN_OPTIONS="$ASAN_OPTS" UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
            LSAN_OPTIONS="suppressions=$ROOT/lsan_suppressions.txt" RIPWIRE_ROOT="$ROOT" \
            "$WORK/cmb/ripwire_test_pagerank" > "$WORK/out_pr.log" 2>&1
        rc_pr=$?
        read_counts "$WORK/out_pr.log"
        if [ "$rc_pr" -ne 0 ] || [ "${ASSERTS_FAIL:-1}" != "0" ]; then
            echo "  FAIL  ripwire_test_pagerank failed under sanitizers (exit $rc_pr, $ASSERTS_FAIL failed):"
            grep -B 2 -A 6 'ERROR\|FAILED' "$WORK/out_pr.log" | sed 's/^/    /' | head -40
            fail=1
        elif [ "$ASSERTS" -lt "$MIN_PR_ASSERTS" ] || [ "$CASES" -lt "$MIN_PR_CASES" ]; then
            echo "  FAIL  ripwire_test_pagerank ran $CASES cases / $ASSERTS assertions; below floor $MIN_PR_CASES / $MIN_PR_ASSERTS"
            fail=1
        else
            printf '  PASS  ripwire_test_pagerank: %s test cases / %s assertions green under G1 sanitizers\n' "$CASES" "$ASSERTS"
        fi
    fi
fi

# ── Arm 2: Direct $CXX -DNDEBUG -O2 (Truncation survives release build) ───────────────────────────
if ! "$CXX" $CXXSTD -DNDEBUG -O2 -fno-fast-math \
        -I"$ROOT/src/infra" -I"$ROOT/third_party" -I"$ROOT/src" -I"$ROOT/third_party/deps/doctest" \
        "$ROOT/test/verify_pagerank.cpp" "$ROOT/src/pagerank.cpp" "$ROOT/src/infra/diagnostics.cpp" \
        -o "$WORK/pr_ndebug" > "$WORK/build_ndebug.log" 2>&1; then
    echo "  FAIL  failed to compile verify_pagerank under -DNDEBUG -O2"
    tail -20 "$WORK/build_ndebug.log" | sed 's/^/    /'
    fail=1
else
    "$WORK/pr_ndebug" -tc="*K12*,*K13*,*K14*" > "$WORK/out_ndebug.log" 2>&1
    rc_ndebug=$?
    read_counts "$WORK/out_ndebug.log"
    if [ "$rc_ndebug" -ne 0 ] || [ "${ASSERTS_FAIL:-1}" != "0" ] || [ "$CASES" -lt 3 ]; then
        echo "  FAIL  K12, K13, K14 failed under -DNDEBUG (exit $rc_ndebug, $ASSERTS_FAIL failed):"
        grep -B 2 -A 6 'ERROR\|FAILED' "$WORK/out_ndebug.log" | sed 's/^/    /' | head -30
        fail=1
    else
        printf '  PASS  arm 2: K12, K13, K14 (%s cases / %s assertions) green under -DNDEBUG -O2\n' "$CASES" "$ASSERTS"
    fi
fi

# ── Arm 3: Mutation testing (Can go red) ──────────────────────────────────────────────────────────
# M1: delete ++iterationCount; in converged branch (src/pagerank.cpp)
cp -R "$ROOT/src" "$WORK/mut_m1"
sed -i.bak '/\+\+iterationCount;/d' "$WORK/mut_m1/pagerank.cpp"
if cmp -s "$ROOT/src/pagerank.cpp" "$WORK/mut_m1/pagerank.cpp"; then
    echo "  FAIL  arm 3: mutation M1 did not take (source unmodified)"
    fail=1
elif ! "$CXX" $CXXSTD -I"$WORK/mut_m1/infra" -I"$ROOT/third_party" -I"$WORK/mut_m1" -I"$ROOT/third_party/deps/doctest" \
        "$ROOT/test/verify_pagerank.cpp" "$WORK/mut_m1/pagerank.cpp" "$WORK/mut_m1/infra/diagnostics.cpp" \
        -o "$WORK/pr_m1" > "$WORK/bld_m1.log" 2>&1; then
    echo "  FAIL  arm 3: failed to compile M1 mutant"
    fail=1
else
    "$WORK/pr_m1" -tc="*K1:*,*K3:*,*K12:*" > "$WORK/out_m1.log" 2>&1 || true
    read_counts "$WORK/out_m1.log"
    if [ "${ASSERTS_FAIL:-0}" -gt 0 ]; then
        echo "  PASS  arm 3: mutation M1 went red as expected ($ASSERTS_FAIL assertions failed)"
    else
        echo "  FAIL  arm 3: mutation M1 stayed green (expected K1, K3, K12 failures)"
        fail=1
    fi
fi

# M2: drop config.alpha * danglingMass + (src/pagerank.cpp)
cp -R "$ROOT/src" "$WORK/mut_m2"
sed -i.bak 's/config\.alpha \* danglingMass +//' "$WORK/mut_m2/pagerank.cpp"
if cmp -s "$ROOT/src/pagerank.cpp" "$WORK/mut_m2/pagerank.cpp"; then
    echo "  FAIL  arm 3: mutation M2 did not take (source unmodified)"
    fail=1
elif ! "$CXX" $CXXSTD -I"$WORK/mut_m2/infra" -I"$ROOT/third_party" -I"$WORK/mut_m2" -I"$ROOT/third_party/deps/doctest" \
        "$ROOT/test/verify_pagerank.cpp" "$WORK/mut_m2/pagerank.cpp" "$WORK/mut_m2/infra/diagnostics.cpp" \
        -o "$WORK/pr_m2" > "$WORK/bld_m2.log" 2>&1; then
    echo "  FAIL  arm 3: failed to compile M2 mutant"
    fail=1
else
    "$WORK/pr_m2" -tc="*K3:*,*K6:*" > "$WORK/out_m2.log" 2>&1 || true
    read_counts "$WORK/out_m2.log"
    if [ "${ASSERTS_FAIL:-0}" -gt 0 ]; then
        echo "  PASS  arm 3: mutation M2 went red as expected ($ASSERTS_FAIL assertions failed)"
    else
        echo "  FAIL  arm 3: mutation M2 stayed green (expected K3, K6 failures)"
        fail=1
    fi
fi

# M3: remove || values[edgeIndex] < T( 0 ) from src/infra/csrverify.h
cp -R "$ROOT/src" "$WORK/mut_m3"
sed -i.bak 's/|| values\[edgeIndex\] < T( 0 )//' "$WORK/mut_m3/infra/csrverify.h"
if cmp -s "$ROOT/src/infra/csrverify.h" "$WORK/mut_m3/infra/csrverify.h"; then
    echo "  FAIL  arm 3: mutation M3 did not take (source unmodified)"
    fail=1
elif ! "$CXX" $CXXSTD -I"$WORK/mut_m3/infra" -I"$ROOT/third_party" -I"$WORK/mut_m3" -I"$ROOT/third_party/deps/doctest" \
        "$ROOT/test/verify_csr.cpp" "$WORK/mut_m3/infra/diagnostics.cpp" \
        -o "$WORK/csr_m3" > "$WORK/bld_m3.log" 2>&1; then
    echo "  FAIL  arm 3: failed to compile M3 mutant"
    fail=1
else
    "$WORK/csr_m3" -tc="*C5:*" > "$WORK/out_m3.log" 2>&1 || true
    read_counts "$WORK/out_m3.log"
    if [ "${ASSERTS_FAIL:-0}" -gt 0 ]; then
        echo "  PASS  arm 3: mutation M3 went red as expected ($ASSERTS_FAIL assertions failed)"
    else
        echo "  FAIL  arm 3: mutation M3 stayed green (expected C5j failure)"
        fail=1
    fi
fi

exit "$fail"
