#!/usr/bin/env bash
# strkerncheck.sh — SIMD-vs-scalar parity gate for src/infra/strkern.h, and the tokenizer equivalence
# gate for the mask-driven walkers in src/lexindex.h.
#
# It drives the CMake target `ripwire_test_strkern` (test/verify_strkern.cpp), the repo's doctest form —
# DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN, one TEST_CASE per kernel, one CHECK/REQUIRE per assertion, built
# beside ripwire_test_csr / ripwire_test_pagerank / ripwire_test_radix. Until 2026-09-10 the same arms
# lived in a standalone test/strkern_harness.cpp (14 `checkf` arms) and test/emitescape_harness.cpp (4);
# the doctest target carries all 18 plus a compiled-path assertion and, since the #127 review round, a
# LexHeadIndex empty-bucket case; this gate prints both counts so a lost arm is arithmetic, not a
# feeling, and MIN_ASSERTIONS is a FLOOR, never an exact expectation.
#
# THE TARGET IS BUILT THREE TIMES, and each build is a different question:
#
#   1  CMAKE, FULL G1 SANITIZERS.  `cmake -DRIPWIRE_TESTS=ON -DRIPWIRE_ASAN=ON` in a scratch dir, then
#      `--target ripwire_test_strkern`. This is the arm that proves the SHIPPED target builds and runs —
#      the same target `ctest` runs — under -fsanitize=address,undefined,integer,float-* with
#      -fno-sanitize-recover=all, so a nibble-table read one lane past the end ABORTS rather than
#      reporting and exiting 0. It runs EVERY test case in the TU (kernels and escapers both): this is
#      the G1 arm for the whole file, which is why test/emitescapecheck.sh does not build a second
#      sanitized copy of the same source to re-prove it.
#   2  DIRECT $CXX, -DSTRKERN_MUTATE=1.  CAN GO RED. The mutation flips one bit of the SIMD-only nibble
#      table, narrows the fold's range by one, drops findByteset's high half, and drops the high half of
#      the set from Byteset256::words. That build MUST fail. If it passes, every parity assertion above
#      is unbinding and this gate is decoration. A compile flag, not a build type — a second CMake
#      configure to pass one -D would cost a configure to say nothing extra.
#   3  DIRECT $CXX, `-arch x86_64 -march=x86-64-v3`, run under Rosetta 2.  BEST EFFORT. CMake cannot
#      express a second architecture for one target inside this tree, so this arm compiles the same
#      source the way the pre-doctest gate did. It is a SKIP, never a failure, when the SDK or Rosetta is
#      unavailable — the authoritative AVX2 proof is the ubuntu-24.04 CI leg.
#
# NON-VACUITY sits between 1 and 2: on arm64 the banner must say NEON, on x86-64 AVX2. A scalar-only
# build on those arches would compare the oracle to itself and pass while proving nothing.
#
# Independent of the ripwire binary and of main.cpp (pinned in test/binoverridecheck.sh's EXEMPT dict).
# Usage:  bash test/strkerncheck.sh            (compiles with c++/clang++)
#         CXX=clang++ bash test/strkerncheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"

# ask THIS front end how it spells C++23 (see scripts/cxxstd.sh — AppleClang 15 rejects -std=c++23)
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
SRC="$ROOT/test/verify_strkern.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
ARCH="$( uname -m )"
fail=0

# The arm counts the two standalone harnesses carried before 2026-09-10, kept here so this gate can state
# the before/after rather than assert the after alone. 14 + 4; the doctest target adds the compiled-path
# assertion, so 19 is the floor below.
LEGACY_STRKERN_ARMS=14
LEGACY_ESCAPE_ARMS=4
MIN_ASSERTIONS=19

echo "strkerncheck: CXX=$CXX arch=$ARCH  target=ripwire_test_strkern"

# ── 1: the CMake target, under the complete G1 sanitizer stack ────────────────────────────────────────
# FETCHCONTENT_FULLY_DISCONNECTED=ON because every dependency is vendored: a gate must not reach the
# network, and if one ever tries, this is where it fails loudly instead of hanging.
if ! cmake -S "$ROOT" -B "$WORK/cmb" -DRIPWIRE_TESTS=ON -DRIPWIRE_ASAN=ON \
        -DFETCHCONTENT_FULLY_DISCONNECTED=ON > "$WORK/cfg.log" 2>&1; then
    echo "  FAIL  cmake configure (-DRIPWIRE_TESTS=ON -DRIPWIRE_ASAN=ON) failed"
    tail -20 "$WORK/cfg.log" | sed 's/^/    /'
    exit 2
fi
if ! cmake --build "$WORK/cmb" --target ripwire_test_strkern -j 2 > "$WORK/build.log" 2>&1; then
    echo "  FAIL  ripwire_test_strkern failed to build under the G1 sanitizers"
    tail -30 "$WORK/build.log" | sed 's/^/    /'
    exit 2
fi

# Apple's arm64 runtime rejects LeakSanitizer at startup; mirror CMakeLists.txt's platform policy rather
# than claiming a leak check that cannot run (see the note beside ripwire_asan_fixture there).
if [ "$( uname -s )" = "Darwin" ]; then
    ASAN_OPTS="detect_leaks=0:halt_on_error=1:abort_on_error=1"
else
    ASAN_OPTS="detect_leaks=1:halt_on_error=1:abort_on_error=1"
fi
ASAN_OPTIONS="$ASAN_OPTS" UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
    LSAN_OPTIONS="suppressions=$ROOT/lsan_suppressions.txt" RIPWIRE_ROOT="$ROOT" \
    "$WORK/cmb/ripwire_test_strkern" > "$WORK/out_main.log" 2>&1
rc=$?

# doctest's own tally line is the arm count: "[doctest] assertions: N | N passed | K failed |"
read_counts()   # $1 = log; sets CASES, CASES_PASS, ASSERTS, ASSERTS_FAIL
{
    CASES="$(      sed -n 's/^\[doctest\] test cases: *\([0-9][0-9]*\) .*/\1/p'                "$1" | tail -1 )"
    CASES_PASS="$( sed -n 's/^\[doctest\] test cases: *[0-9][0-9]* | *\([0-9][0-9]*\) passed.*/\1/p' "$1" | tail -1 )"
    ASSERTS="$(    sed -n 's/^\[doctest\] assertions: *\([0-9][0-9]*\) .*/\1/p'                "$1" | tail -1 )"
    ASSERTS_FAIL="$( sed -n 's/.*| *\([0-9][0-9]*\) failed |$/\1/p'                            "$1" | tail -1 )"
    : "${CASES:=0}" "${CASES_PASS:=0}" "${ASSERTS:=0}" "${ASSERTS_FAIL:=0}"
}
read_counts "$WORK/out_main.log"

if [ "$rc" -ne 0 ] || [ "${ASSERTS_FAIL:-1}" != "0" ]; then
    echo "  FAIL  parity/equivalence assertion failed (exit $rc, $ASSERTS_FAIL failed):"
    grep -B 2 -A 6 'ERROR\|FAILED' "$WORK/out_main.log" | sed 's/^/    /' | head -40
    exit 2
fi
if [ "$ASSERTS" -lt "$MIN_ASSERTIONS" ]; then
    echo "  FAIL  the doctest target ran $ASSERTS assertions; the two harnesses it replaced carried"
    echo "        $LEGACY_STRKERN_ARMS + $LEGACY_ESCAPE_ARMS = $(( LEGACY_STRKERN_ARMS + LEGACY_ESCAPE_ARMS )), and the target must be >= $MIN_ASSERTIONS."
    echo "        An arm was deleted, or a TEST_CASE stopped being registered."
    exit 2
fi
printf '  PASS  %s test cases / %s assertions green under the full G1 sanitizers (was %s + %s arms in two standalone harnesses) (%s)\n' \
       "$CASES" "$ASSERTS" "$LEGACY_STRKERN_ARMS" "$LEGACY_ESCAPE_ARMS" \
       "$( grep '^strkern: path=' "$WORK/out_main.log" | sed 's/strkern: //' )"

WANT=""
case "$ARCH" in
    arm64|aarch64) WANT="NEON" ;;
    x86_64|amd64)  WANT="AVX2" ;;
esac
if [ -n "$WANT" ]; then
    if grep -q "^strkern path: $WANT$" "$WORK/out_main.log"; then
        printf '  PASS  non-vacuity: %s on %s\n' "$( grep '^strkern path: ' "$WORK/out_main.log" )" "$ARCH"
    else
        echo "  FAIL  non-vacuity ($ARCH must compile the $WANT path; banner says '$( grep '^strkern path: ' "$WORK/out_main.log" )')"
        echo "        a scalar-only build here compares the oracle to itself — the parity arms prove nothing"
        fail=1
    fi
fi

# ── COMPILER PORTABILITY, read off the SOURCE (CodeRabbit #127 / 3985249663) ─────────────────────────
# The scalar twins are ALWAYS compiled and the vector paths compile under MSVC's /arch:AVX2, so no path in
# this header may use a GCC/Clang-only builtin. `__builtin_ctzll` was the whole population: MSVC has no
# such intrinsic, and the pending Windows port (PR #44) would not have compiled the file at all. The
# portable spelling is <bit>'s std::countr_zero, which is the same instruction everywhere and is DEFINED
# at zero where the builtin is undefined.
#
# This is a SOURCE arm, not a build arm, and deliberately so: the only compiler on this box accepts both
# spellings, so no local build can tell them apart — the difference is visible in the text or nowhere.
# CAN GO RED: put `__builtin_ctzll` back on any one of the eight sites and this arm fires.
# CODE lines only: the prose above names the retired builtin on purpose, and a gate that cannot tell a
# comment from a call site would forbid writing down what the rule is.
HDR="$ROOT/src/infra/strkern.h"
code_hits(){ grep -n "$1" "$HDR" 2>/dev/null | grep -vE '^[0-9]+: *(//|\*|/\*)'; }
BUILTINS="$( code_hits '__builtin_' | wc -l | tr -d ' ' )"
# `grep -c … || echo 0` printed "0" TWICE on a zero count (grep prints 0 AND exits 1), a two-line value
# `-lt` cannot compare — so the arm could PASS on the very count it exists to refuse (CodeRabbit on #127).
CTZ="$( grep -o 'std::countr_zero(' "$HDR" 2>/dev/null | wc -l | tr -d ' ' )"
if [ "$BUILTINS" != "0" ]; then
    echo "  FAIL  portability: src/infra/strkern.h uses $BUILTINS GCC/Clang-only __builtin_ — MSVC cannot compile it:"
    code_hits '__builtin_' | sed 's/^/        /' | head -10
    fail=1
elif [ "$CTZ" -lt 8 ]; then
    echo "  FAIL  portability: only $CTZ std::countr_zero( call sites in strkern.h — the eight trailing-zero"
    echo "        counts (2 scalar twins + 6 vector) are the population this arm is non-vacuous over"
    fail=1
else
    printf '  PASS  portability: 0 __builtin_ in strkern.h, %s std::countr_zero( sites (<bit>, one spelling for the repo)\n' "$CTZ"
fi
if ! grep -q '^#include <bit>' "$HDR"; then
    echo "  FAIL  portability: strkern.h calls std::countr_zero without including <bit>"
    fail=1
fi

# compile one flavour of the target directly; $1 = label, remaining args = extra compile flags. Echoes the
# binary path on success, nothing on failure (the caller decides whether a compile failure is fatal).
compile_direct()
{
    local LABEL="$1"; shift
    local BIN="$WORK/verify_$LABEL"
    if ! "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra "$@" \
            -I"$ROOT/src/infra" -I"$ROOT/src" -I"$ROOT/third_party" -I"$ROOT/third_party/deps/doctest" \
            -DRIPWIRE_TEST_ROOT="\"$ROOT\"" \
            "$SRC" "$ROOT/src/infra/diagnostics.cpp" -o "$BIN" 2> "$WORK/cc_$LABEL.log"; then
        return 1
    fi
    printf '%s\n' "$BIN"
}

# ── 2: CAN GO RED ─────────────────────────────────────────────────────────────────────────────────────
# The mutation touches ONLY code inside `#if defined( STRKERN_MUTATE )` in src/infra/strkern.h, so a red
# run here is a parity assertion biting, not a broken build. Sanitizers are off for this arm: it is
# expected to fail, and we want it to fail on the assertion, not on a slow abort.
REDBIN="$( compile_direct mutate -DSTRKERN_MUTATE=1 )"
if [ -z "$REDBIN" ]; then
    echo "  FAIL  can-go-red arm failed to COMPILE (the mutation must build, then fail at runtime)"
    sed 's/^/    /' "$WORK/cc_mutate.log" | head -20
    fail=1
elif RIPWIRE_ROOT="$ROOT" "$REDBIN" > "$WORK/out_mutate.log" 2>&1; then
    echo "  FAIL  can-go-red: -DSTRKERN_MUTATE=1 build PASSED — the parity assertions are not binding"
    fail=1
else
    read_counts "$WORK/out_mutate.log"
    printf '  PASS  can-go-red: -DSTRKERN_MUTATE=1 fails %s of %s assertions as designed\n' "$ASSERTS_FAIL" "$ASSERTS"
fi

# ── 2b: THE FAILING SWEEP MUST HAVE SWEPT THE SAME CORPUS (CodeRabbit #127 / 3985249745) ──────────────
# Arm 2's red run is only evidence about the SHIPPED kernels if the broken build walked the same buffers
# the green build walked. The sweep's probes draw from one shared DeterministicRng, so a probe skipped
# because its arm had already failed used to shorten the stream: every later buffer and every later probe
# input moved, and a second, independent divergence could be shifted out of the run entirely — the failure
# report then described a sweep nobody had ever seen green. verify_strkern.cpp now runs every probe
# unconditionally and keeps only the FIRST message per arm, which makes this comparison the proof.
#
# The line is `strkern sweep-rng: <state> buffers=<n>`; the state is the generator's, after the loop, so
# it is a pure function of how many draws were made. CAN GO RED: put the `if( r.<arm>Fail.empty() )`
# guards back and the mutated build — whose arms all fail on iteration 0 — prints a different state.
GREEN_RNG="$(  grep -m1 '^strkern sweep-rng: ' "$WORK/out_main.log"   2>/dev/null )"
MUTATE_RNG="$( grep -m1 '^strkern sweep-rng: ' "$WORK/out_mutate.log" 2>/dev/null )"
if [ -z "$GREEN_RNG" ] || [ -z "$MUTATE_RNG" ]; then
    echo "  FAIL  sweep corpus: no 'strkern sweep-rng:' line (green='$GREEN_RNG' mutated='$MUTATE_RNG')"
    fail=1
elif [ "$GREEN_RNG" = "$MUTATE_RNG" ]; then
    printf '  PASS  sweep corpus: the MUTATED build swept the same buffers as the green one (%s)\n' "$GREEN_RNG"
else
    echo "  FAIL  sweep corpus: a failing arm moved the RNG stream — the red run is not the green run's sweep"
    echo "        green   $GREEN_RNG"
    echo "        mutated $MUTATE_RNG"
    fail=1
fi

# A cross-arch slice that Rosetta 2 cannot run fails at EXEC (rc 126, "Bad CPU type in executable",
# "cannot execute binary file", "Exec format error"); that — and only that — is the environment saying
# no. A slice that RAN and exited nonzero (a doctest assertion, an abort) is a red, never a SKIP
# (CodeRabbit on #127: the old branch read every nonzero exit as "no Rosetta").
# Can the TRANSLATED x86_64 runtime execute AVX2 at all? Rosetta 2 gained AVX2 in macOS 15; CI's macos-14
# runners SIGILL a -march=x86-64-v3 slice at its first vector instruction (PR #127 run 4, rc 132, no output).
# The sysctl probes are NOT trustworthy here: on a macOS 26 host whose Rosetta runs the v3 slice green,
# `arch -x86_64 sysctl -n hw.optional.avx2_0` still prints 0 and leaf7_features lists no AVX2 — so the probe
# EXECUTES one AVX2 instruction under Rosetta and reads the exit. rc 0 + "avx2 ok" => available; rc 132
# (SIGILL) or an exec failure => rosetta_no_avx2, and arms 3/3b/3c SKIP with that reason. Where the probe
# runs, a slice that exits nonzero — SIGILL included — is a FAIL, never a SKIP. The probe is compiled with
# -march=x86-64-v3 itself and touches every ISA extension the floor implies (see the C below).
ROSETTA_AVX2="unknown"
rosetta_avx2_probe(){
    cat > "$WORK/avx2probe.c" <<'EOF_PROBE'
// The probe must exercise the SAME feature set the slice is compiled with (-march=x86-64-v3 = AVX, AVX2,
// BMI1, BMI2, FMA, LZCNT, MOVBE, F16C). Its first cut was one AVX2 add compiled with -mavx2 — and clang
// folded that to a scalar `addb` despite the volatile (otool: zero ymm/VEX opcodes), so it printed "ok"
// on every runtime and never chose the baseline slice (PR #127 run 7). Which v3 extension Sonoma's
// Rosetta 2 lacks is not known; only that the v3 slice SIGILLs there. Hence: the floor's own -march,
// every extension touched, every value through a volatile, and the gate DISASSEMBLES the binary to
// assert the opcodes are really in it (below) — a probe that proves nothing must fail, not pass.
#include <immintrin.h>
#include <stdint.h>
#include <stdio.h>
int main( void )
{
    volatile uint64_t seed = 0x00F0F0F0F0F0F0F3ull;
    volatile int      sh   = 3;
    __m256i a = _mm256_set1_epi8( (char) seed );                      // AVX2 broadcast
    __m256i b = _mm256_add_epi8( a, a );                              // AVX2 add
    unsigned char out[ 32 ];
    _mm256_storeu_si256( (__m256i*) out, b );
    uint64_t v   = seed;
    uint64_t r1  = _pdep_u64( v, 0xF0F0F0F0F0F0F0F0ull ) ^ _pext_u64( v, 0x0F0F0F0F0F0F0F0Full );   // BMI2
    uint64_t r2  = _lzcnt_u64( v ) + _tzcnt_u64( v );                                          // LZCNT / BMI1
    uint64_t r3  = ( v << sh ) | ( v >> sh );                                                   // shlx/shrx (BMI2)
    __m256   f   = _mm256_fmadd_ps( _mm256_set1_ps( (float) sh ), _mm256_set1_ps( 2.0f ), _mm256_set1_ps( 1.0f ) );   // FMA
    float    fo[ 8 ];
    _mm256_storeu_ps( fo, f );
    __m128i  h   = _mm256_cvtps_ph( f, 0 );                                                     // F16C
    uint16_t ho[ 8 ];
    _mm_storeu_si128( (__m128i*) ho, h );
    uint64_t r4  = __builtin_bswap64( *(volatile uint64_t*) &v );                              // MOVBE-eligible
    printf( "v3 ok %d %llu %llu %llu %g %u %llu\n", out[ 0 ], (unsigned long long) r1, (unsigned long long) r2,
            (unsigned long long) r3, (double) fo[ 0 ], (unsigned) ho[ 0 ], (unsigned long long) r4 );
    return out[ 0 ] == (unsigned char) ( 2 * (char) seed ) ? 0 : 1;   // reaching this line at all is the fact; a SIGILL never does
}
EOF_PROBE
    if ! "${CC:-cc}" -arch x86_64 -march=x86-64-v3 -O1 "$WORK/avx2probe.c" -o "$WORK/avx2probe" 2>"$WORK/avx2probe.cc.log"; then
        ROSETTA_AVX2="no_toolchain"; return 1
    fi
    # The probe must CONTAIN the instructions it claims to execute — a folded probe (run 7) answered "ok"
    # without a single vector opcode. Disassemble and require one opcode from each class; if no
    # disassembler is on the host, the probe cannot be trusted and the mirror takes the baseline slice.
    if command -v otool >/dev/null 2>&1; then
        otool -tv "$WORK/avx2probe" > "$WORK/avx2probe.dis" 2>/dev/null
    elif command -v objdump >/dev/null 2>&1; then
        objdump -d "$WORK/avx2probe" > "$WORK/avx2probe.dis" 2>/dev/null
    else
        ROSETTA_AVX2="no (no disassembler to verify the probe's opcodes)"; return 1
    fi
    for cls in 'ymm' 'pdep' 'pext' 'lzcnt' 'tzcnt' 'vfmadd' 'vcvtph2ps|vcvtps2ph'; do
        if ! grep -qE "$cls" "$WORK/avx2probe.dis"; then
            ROSETTA_AVX2="no (the probe binary lacks a $cls opcode — folded by the compiler; the probe proves nothing)"; return 1
        fi
    done
    "$WORK/avx2probe" > "$WORK/avx2probe.out" 2>&1; local rc=$?
    if [ "$rc" = 0 ] && grep -q '^v3 ok' "$WORK/avx2probe.out"; then
        ROSETTA_AVX2="yes"; return 0
    fi
    ROSETTA_AVX2="no (probe rc=$rc: $( tail -1 "$WORK/avx2probe.out" 2>/dev/null | tr -d '\n' ))"; return 1
}
exec_unavailable(){   # $1 = rc, $2 = output log — the exec-format shapes only; AVX2 absence is decided by the probe above
    [ "$1" = 126 ] && return 0
    grep -qE 'Bad CPU type|cannot execute binary file|Exec format error' "$2"
}

# ── 3 / 3b / 3c: the x86_64 mirror under Rosetta 2 — v3 (AVX2) where the translated runtime can run it,
# the x86-64 BASELINE (the scalar twins on x86) where it cannot ────────────────────────────────────────
# The shipped x86-64 floor is -march=x86-64-v3 (CMakeLists.txt sets it unconditionally for x86-64
# targets). CI's ubuntu legs run that slice natively; on an arm64 Mac it runs under Rosetta 2, which gained
# AVX2 only in macOS 15 — so the probe above decides WHICH slice this host can execute. Owner (2026-09-11):
# a non-AVX2 build of the mirror is fine for the no-AVX2 hosts — strkern.h has no SSE2 path, so that slice
# runs the SCALAR twins and the tokenizer on x86, under the same assertions, sanitizer and mutation control.
# The release floor does not move; this is the test slice only.
#   3  — the slice runs green and compiled the expected path (AVX2 or scalar);
#   3b — the same slice under -fsanitize=undefined,integer (UBSan's runtime is a universal dylib; ASan stays
#        off here — arm 1 owns memory safety on the host ISA); a sanitizer report is a FAIL;
#   3c — CONTROL: the slice built with -DSTRKERN_MUTATE=1 must fail on its OWN assertions (rc != 0,
#        rc != 132, assertion output) — a SIGILL can never satisfy it.
# A slice that RAN and exited nonzero is a FAIL, never a SKIP; only an exec-format failure SKIPs.
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    rosetta_avx2_probe || true
    if [ "$ROSETTA_AVX2" = "yes" ]; then
        X86_MARCH="-march=x86-64-v3"; X86_PATH="AVX2"; X86_LABEL="x86_64/AVX2 (v3) mirror"
    else
        X86_MARCH="-march=x86-64";    X86_PATH="scalar"; X86_LABEL="x86_64 baseline (scalar) mirror"
        printf '  INFO  rosetta_no_avx2 — the translated runtime cannot execute AVX2 here (%s); the mirror runs the x86-64 baseline slice (scalar twins on x86); CI ubuntu-24.04 runs the v3 slice natively\n' "$ROSETTA_AVX2"
    fi
    if X86BIN="$( compile_direct x86 -arch x86_64 $X86_MARCH )" && [ -n "$X86BIN" ]; then
        RIPWIRE_ROOT="$ROOT" "$X86BIN" > "$WORK/out_x86.log" 2>&1; rc_x86=$?
        if [ "$rc_x86" = 0 ]; then
            read_counts "$WORK/out_x86.log"
            if grep -q "^strkern path: $X86_PATH\$" "$WORK/out_x86.log"; then
                printf '  PASS  3: %s runs green under Rosetta 2 (%s assertions, path=%s)\n' "$X86_LABEL" "$ASSERTS" "$X86_PATH"
            else
                echo "  FAIL  3: $X86_LABEL built but compiled a different path: $( grep '^strkern path: ' "$WORK/out_x86.log" ) (expected $X86_PATH)"
                fail=1
            fi
        elif exec_unavailable "$rc_x86" "$WORK/out_x86.log"; then
            printf '  SKIP  3: %s built but cannot execute here (no Rosetta 2): %s\n' "$X86_LABEL" "$( tail -1 "$WORK/out_x86.log" )"
        else
            echo "  FAIL  3: $X86_LABEL RAN and exited $rc_x86: $( tail -2 "$WORK/out_x86.log" | tr '\n' ' ' )"
            fail=1
        fi
        if X86UB="$( compile_direct x86ub -arch x86_64 $X86_MARCH -fsanitize=undefined,integer -fno-sanitize-recover=all )" && [ -n "$X86UB" ]; then
            RIPWIRE_ROOT="$ROOT" UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 "$X86UB" > "$WORK/out_x86ub.log" 2>&1; rc_ub=$?
            if [ "$rc_ub" = 0 ]; then
                read_counts "$WORK/out_x86ub.log"
                printf '  PASS  3b: %s is clean under -fsanitize=undefined,integer (%s assertions)\n' "$X86_LABEL" "$ASSERTS"
            elif grep -q 'runtime error' "$WORK/out_x86ub.log"; then
                echo "  FAIL  3b: $X86_LABEL trips UBSan integer checks: $( grep -m1 'runtime error' "$WORK/out_x86ub.log" | sed 's|.*/src/|src/|' )"
                fail=1
            elif exec_unavailable "$rc_ub" "$WORK/out_x86ub.log"; then
                printf '  SKIP  3b: %s UBSan slice cannot execute here (no Rosetta 2): %s\n' "$X86_LABEL" "$( tail -1 "$WORK/out_x86ub.log" )"
            else
                echo "  FAIL  3b: $X86_LABEL UBSan slice RAN and exited $rc_ub without a sanitizer report: $( tail -2 "$WORK/out_x86ub.log" | tr '\n' ' ' )"
                fail=1
            fi
        else
            echo "  FAIL  3b: the $X86_LABEL did not build with -fsanitize=undefined,integer: $( head -2 "$WORK/cc_x86ub.log" | tr '\n' ' ' )"
            fail=1
        fi
        if X86MUT="$( compile_direct x86mut -arch x86_64 $X86_MARCH -DSTRKERN_MUTATE=1 )" && [ -n "$X86MUT" ]; then
            RIPWIRE_ROOT="$ROOT" "$X86MUT" > "$WORK/out_x86mut.log" 2>&1; rc_mut=$?
            if [ "$rc_mut" != 0 ] && [ "$rc_mut" != 132 ] && grep -qE 'FAILED|assertion|CHECK' "$WORK/out_x86mut.log"; then
                echo "  PASS  3c control: the mutated $X86_LABEL RAN and failed on its own assertions (rc=$rc_mut) — a red, classified as a red"
            elif [ "$rc_mut" = 132 ]; then
                echo "  FAIL  3c control: the mutated $X86_LABEL died with SIGILL although the probe ran — a real red, not the mutation"
                fail=1
            else
                echo "  FAIL  3c control: the mutated $X86_LABEL exited $rc_mut without failing an assertion — the mutation is not visible on the $X86_PATH path"
                fail=1
            fi
        else
            echo "  FAIL  3c control: the mutated $X86_LABEL did not build: $( head -2 "$WORK/cc_x86mut.log" | tr '\n' ' ' )"
            fail=1
        fi
    else
        printf '  SKIP  3/3b/3c: no x86_64 cross slice on this toolchain (no macOS x86_64 SDK); CI ubuntu-24.04 runs the v3 slice natively\n'
    fi
fi

if [ "$fail" = 0 ]; then
    echo "strkerncheck: PASS"
else
    echo "strkerncheck: FAILURES ABOVE"
fi
exit "$fail"
