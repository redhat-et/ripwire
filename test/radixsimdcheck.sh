#!/usr/bin/env bash
# radixsimdcheck.sh — SIMD-vs-scalar parity gate for the radix byte-histogram fast paths:
#   radix::detail::buildHistogramsContiguousKeys<uint32_t/uint64_t/float>  (src/infra/radixSort.inl —
#   NEON on arm64, SSE2 on x86_64, the scalar loop elsewhere) and the IEEE sortable-word flip behind
#   the float path.
#
# Compiles test/radixsimd_harness.cpp under the FULL G1 sanitizer set and runs it. The harness restates
# the histogram contract bytewise from an independently-formulated sortable-word oracle and sweeps the
# vector seams: remainder tails for both lane widths, unaligned base pointers, byte-boundary values in
# every lane, all-equal fills, ±0.0/denormals/sign boundaries, plus end-to-end sortKeyLarge-vs-stable_sort.
#
# On arm64 macOS with Rosetta installed, a SECOND pass cross-compiles the harness -arch x86_64 and runs
# it under Rosetta, so the SSE2 kernels are gated on Apple Silicon dev machines too, not just x86 CI.
# The pass is probed (compile+run a sanitized stub); a Mac without Rosetta skips it LOUDLY.
#
# NON-VACUITY: the harness banner must say the NEON kernel engaged on arm64, the SSE one on x86_64
# (including the Rosetta pass). A scalar-only build on those arches compares the contract to itself —
# that is a FAIL here, not a pass.
#
# Independent of the ripwire binary and of main.cpp. Does NOT edit regression.sh (it is listed there).
# Usage:  bash test/radixsimdcheck.sh            (compiles with c++/clang++)
#         CXX=clang++ bash test/radixsimdcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"

# ask THIS front end how it spells C++23 (see scripts/cxxstd.sh — AppleClang 15 rejects -std=c++23)
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
HARNESS="$ROOT/test/radixsimd_harness.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
ARCH="$( uname -m )"

echo "radixsimdcheck: CXX=$CXX arch=$ARCH"

# G1's 'integer' / float-cast groups are Clang spellings; GCC only has the address,undefined core.
# Probe THIS front end rather than guessing from its name (same posture as scripts/cxxstd.sh).
SAN="-fsanitize=address,undefined,integer,float-divide-by-zero,float-cast-overflow"
printf 'int main(){return 0;}\n' > "$WORK/probe.cpp" 2>/dev/null || true
if ! "$CXX" $SAN -fsyntax-only "$WORK/probe.cpp" 2>/dev/null; then
    SAN="-fsanitize=address,undefined"
fi

# one compile+run+non-vacuity pass; $1 = label, $2 = required kernel banner ("" = no requirement),
# remaining args = extra compile flags
run_pass()
{
    local LABEL="$1" WANT="$2"; shift 2
    local BIN="$WORK/harness_$LABEL"

    # G1 sanitizer set — the kernels are exactly where a bad lane width or misaligned load hides;
    # -fno-sanitize-recover=all is the linchpin (a UB run must not exit 0). diagnostics.cpp supplies
    # the VERIFY handlers, linked exactly as the real target does.
    if ! "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra "$@" \
            $SAN -fno-sanitize-recover=all \
            -I"$ROOT/src/infra" -I"$ROOT/src" -I"$ROOT/third_party" \
            "$HARNESS" "$ROOT/src/infra/diagnostics.cpp" -o "$BIN" 2> "$WORK/cc_$LABEL.log"; then
        echo "  FAIL  [$LABEL] harness failed to compile"; sed 's/^/    /' "$WORK/cc_$LABEL.log"; exit 2
    fi

    if ! "$BIN" > "$WORK/out_$LABEL.log"; then
        echo "  FAIL  [$LABEL] parity/invariant assertion failed:"
        grep -B 1 -A 2 'FAIL\|mismatch' "$WORK/out_$LABEL.log" | sed 's/^/    /' | head -20
        exit 2
    fi

    # non-vacuity: the vector kernel must actually have engaged on architectures that have one
    if [ -n "$WANT" ]; then
        if ! grep -q "radix histogram kernel: $WANT" "$WORK/out_$LABEL.log"; then
            echo "  FAIL  [$LABEL] non-vacuity (this pass should run the $WANT kernel; banner disagrees — parity was vacuous)"
            grep 'kernel' "$WORK/out_$LABEL.log" | sed 's/^/    /'
            exit 2
        fi
    fi
    echo "  PASS  [$LABEL] $( grep -c 'PASS' "$WORK/out_$LABEL.log" ) harness arms green ($( head -1 "$WORK/out_$LABEL.log" | sed 's/radixsimd: //' ))"
}

WANT=""
case "$ARCH" in
    arm64|aarch64) WANT="NEON" ;;
    x86_64|amd64)  WANT="SSE"  ;;
esac
run_pass baseline "$WANT"

# second pass on Apple Silicon: cross-compile -arch x86_64 and run under Rosetta, so the SSE2 kernels
# are exercised (with the same sanitizer set) on the machines this repo is developed on. Probed first:
# no Rosetta, or no x86_64 sanitizer runtime, ⇒ a LOUD skip — never a silent one (a skipped pass that
# prints nothing reads as "covered" in a green log).
if [ "$( uname -s )" = "Darwin" ] && [ "$ARCH" = "arm64" ]; then
    printf 'int main(){return 0;}\n' > "$WORK/rosetta_probe.cpp"
    if "$CXX" "$CXXSTD" -arch x86_64 $SAN -fno-sanitize-recover=all "$WORK/rosetta_probe.cpp" -o "$WORK/rosetta_probe" 2>/dev/null \
            && "$WORK/rosetta_probe" 2>/dev/null; then
        run_pass rosetta-x86_64 "SSE" -arch x86_64
    else
        echo "  SKIP  [rosetta-x86_64] Rosetta or the x86_64 sanitizer runtime is unavailable — SSE2 kernels NOT gated on this machine"
    fi
fi

echo "radixsimdcheck: PASS"
