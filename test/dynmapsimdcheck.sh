#!/usr/bin/env bash
# dynmapsimdcheck.sh — SIMD-vs-scalar parity gate for the vendored vector kernels:
#   stree::dyn::node_rank<Key,B>::lt/le   (src/infra/dynamic_map.hpp — NEON on arm64, SSE on x86_64)
#   rw::FixedStr::operator==              (src/infra/fixedStr.h        — same split)
#
# Compiles test/dynmapsimd_harness.cpp under the FULL G1 sanitizer set and runs it. The harness restates
# the rank/equality contracts as independent scalar oracles and sweeps adversarial patterns (sentinel
# padding, sign boundaries, non-power-of-two B, every single-byte FixedStr difference position).
#
# On x86_64 the gate runs TWO passes: the default baseline (SSE2 — 32-bit/float kernels; 64-bit integers
# stay scalar) and -march=x86-64-v2 (SSE4.2 — the 64-bit integer kernels, including the production
# uint64 shape from quality.h). Skipping the second pass would leave the production kernel untested.
#
# NON-VACUITY: on arm64 the harness banner must say the NEON kernels engaged; on x86_64, the SSE ones.
# A scalar-only build on those arches compares the contract to itself — that is a FAIL here, not a pass.
#
# Independent of the ripwire binary and of main.cpp. Does NOT edit regression.sh (it is listed there).
# Usage:  bash test/dynmapsimdcheck.sh            (compiles with c++/clang++)
#         CXX=clang++ bash test/dynmapsimdcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"

# ask THIS front end how it spells C++23 (see scripts/cxxstd.sh — AppleClang 15 rejects -std=c++23)
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
HARNESS="$ROOT/test/dynmapsimd_harness.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
ARCH="$( uname -m )"

echo "dynmapsimdcheck: CXX=$CXX arch=$ARCH"

# G1's 'integer' / float-cast groups are Clang spellings; GCC only has the address,undefined core.
# Probe THIS front end rather than guessing from its name (same posture as scripts/cxxstd.sh).
SAN="-fsanitize=address,undefined,integer,float-divide-by-zero,float-cast-overflow"
printf 'int main(){return 0;}\n' > "$WORK/probe.cpp" 2>/dev/null || true
if ! "$CXX" $SAN -fsyntax-only "$WORK/probe.cpp" 2>/dev/null; then
    SAN="-fsanitize=address,undefined"
fi

# one compile+run+non-vacuity pass; $1 = label, remaining args = extra compile flags
run_pass()
{
    local LABEL="$1"; shift
    local BIN="$WORK/harness_$LABEL"

    # G1 sanitizer set — the kernels are exactly where a bad lane width or misaligned load hides;
    # -fno-sanitize-recover=all is the linchpin (a UB run must not exit 0).
    if ! "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra "$@" \
            $SAN -fno-sanitize-recover=all \
            -I"$ROOT/src/infra" -I"$ROOT/src" -I"$ROOT/third_party" \
            "$HARNESS" -o "$BIN" 2> "$WORK/cc_$LABEL.log"; then
        echo "  FAIL  [$LABEL] harness failed to compile"; sed 's/^/    /' "$WORK/cc_$LABEL.log"; exit 2
    fi

    if ! "$BIN" > "$WORK/out_$LABEL.log"; then
        echo "  FAIL  [$LABEL] parity/invariant assertion failed:"
        grep -B 1 -A 2 'FAIL\|mismatch' "$WORK/out_$LABEL.log" | sed 's/^/    /' | head -20
        exit 2
    fi

    # non-vacuity: the vector kernel must actually have engaged on architectures that have one
    local WANT=""
    case "$ARCH" in
        arm64|aarch64) WANT="NEON" ;;
        x86_64|amd64)  WANT="SSE"  ;;
    esac
    if [ -n "$WANT" ]; then
        if ! { grep -q "rank kernel: $WANT" "$WORK/out_$LABEL.log" && grep -q "fixedstr eq: $WANT" "$WORK/out_$LABEL.log"; }; then
            echo "  FAIL  [$LABEL] non-vacuity ($ARCH should run $WANT kernels; banner disagrees — parity was vacuous)"
            grep 'kernel\|eq:' "$WORK/out_$LABEL.log" | sed 's/^/    /'
            exit 2
        fi
    fi
    echo "  PASS  [$LABEL] $( grep -c 'PASS' "$WORK/out_$LABEL.log" ) harness arms green ($( head -1 "$WORK/out_$LABEL.log" | sed 's/dynmapsimd: //' ))"
}

run_pass baseline

# second x86 pass: light up the SSE4.2 64-bit integer kernels (the production uint64 shape) — without
# this the baseline pass silently leaves them on the scalar template and the gate under-tests.
case "$ARCH" in
    x86_64|amd64) run_pass x86-64-v2 -march=x86-64-v2 ;;
esac

echo "dynmapsimdcheck: PASS"
