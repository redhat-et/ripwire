#!/usr/bin/env bash
# portablebuildcheck.sh — gate for L1 (AUDIT5 independence MUST-FIX #5): "Non-NATIVE build hardcodes
# -mcpu=apple-m1 -ffast-math — Linux/x86 fails out of the box".
#
# Exercises the REAL arch-flag-selection logic in cmake/PortableFlags.cmake — not a reimplementation —
# by include()-ing it into a tiny standalone CMakeLists.txt in a scratch dir. This is deliberately NOT a
# full `cmake -S . -B ...` configure of the real project: that would pay for all 15 FetchContent grammar
# clones just to inspect three compiler flags. PortableFlags.cmake only touches APPLE/CMAKE_SYSTEM_PROCESSOR
# and the two options, so a `project(x LANGUAGES NONE)` host is enough to drive it for real.
#
# Checks:
#   1) default (no flags) configure on THIS machine: if this machine really is Apple Silicon, the auto
#      -mcpu=apple-m1 branch must fire (proves auto-detect still gives Apple-Silicon devs today's behavior).
#   2) default configure + CTXPACK_PRETEND_LINUX=ON (the test-only hook): must emit -O2 -ffast-math
#      -fno-finite-math-only and NOTHING Apple/host-specific (-mcpu=apple-m1 absent, -march=native absent).
#      This is the provable half of "Linux/x86-64/aarch64 must configure cleanly with no Apple flags" —
#      see the NOTE at the bottom for what this machine cannot prove.
#   3) CTXPACK_NATIVE=ON: must emit -march=native (opt-in, unaffected by CTXPACK_PRETEND_LINUX).
#   4) the real top-level CMakeLists.txt no longer hardcodes -mcpu=apple-m1 unconditionally (it must be
#      confined to the CTXPACK_IS_APPLE_SILICON branch inside cmake/PortableFlags.cmake).
#   5) the real top-level CMakeLists.txt still routes through cmake/PortableFlags.cmake (didn't drift back
#      to an inline literal).
#
# Usage: test/portablebuildcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
MODULE="$ROOT/cmake/PortableFlags.cmake"
CMAKE_TOP="$ROOT/CMakeLists.txt"
TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v cmake >/dev/null 2>&1 || { echo "no cmake on PATH"; exit 2; }
[ -f "$MODULE" ] || { echo "missing $MODULE"; exit 2; }

# Build a tiny standalone project dir that only includes PortableFlags.cmake and prints its result.
mk_probe(){
    local dir="$1"
    mkdir -p "$dir/src"
    cat >"$dir/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.24)
project(portableprobe LANGUAGES NONE)
include("$MODULE")
EOF
}

# Configure the probe with the given extra -D args; echoes the CTXPACK_ARCH_FLAGS line (without the
# 'CTXPACK_ARCH_FLAGS:' prefix), or nothing if the configure failed outright.
run_probe(){
    local dir="$1"; shift
    mk_probe "$dir"
    local log="$dir/configure.log"
    if ! cmake -S "$dir" -B "$dir/build" "$@" >"$log" 2>&1; then
        printf 'CONFIGURE_FAILED\n'
        return
    fi
    grep -o 'CTXPACK_ARCH_FLAGS:.*' "$log" | tail -1 | sed 's/^CTXPACK_ARCH_FLAGS://'
}

echo "portablebuildcheck: BIN=n/a (CMake-configure-level gate, no ctxpack binary needed)"

# ── #1: default configure on THIS machine — Apple Silicon devs keep today's behavior ───────────────────
hostFlags="$( run_probe "$TMP/host" )"
hostArch="$( uname -s ):$( uname -m )"
if [ "$( uname -s )" = "Darwin" ] && { [ "$( uname -m )" = "arm64" ] || [ "$( uname -m )" = "aarch64" ]; }; then
    if printf '%s' "$hostFlags" | grep -q -- '-mcpu=apple-m1'; then
        ok "default configure on real Apple Silicon ($hostArch) auto-applies -mcpu=apple-m1: '$hostFlags'"
    else
        no "default configure on real Apple Silicon ($hostArch) did NOT apply -mcpu=apple-m1: '$hostFlags'"
    fi
else
    skip_note="host is $hostArch, not Apple Silicon — auto-detect branch not exercised by #1 on this machine"
    printf '  SKIP  %s\n' "$skip_note"
fi

# ── #2: CTXPACK_PRETEND_LINUX=ON — the provable portable-path check ────────────────────────────────────
linuxFlags="$( run_probe "$TMP/linux" -DCTXPACK_PRETEND_LINUX=ON )"
if [ "$linuxFlags" = "CONFIGURE_FAILED" ]; then
    no "CTXPACK_PRETEND_LINUX=ON configure failed outright: $(tail -5 "$TMP/linux/configure.log" 2>/dev/null)"
elif printf '%s' "$linuxFlags" | grep -q -- '-mcpu=apple-m1'; then
    no "CTXPACK_PRETEND_LINUX=ON still emits -mcpu=apple-m1: '$linuxFlags'"
elif printf '%s' "$linuxFlags" | grep -q -- '-march=native'; then
    no "CTXPACK_PRETEND_LINUX=ON still emits -march=native: '$linuxFlags'"
elif printf '%s' "$linuxFlags" | grep -q -- '-O2' && printf '%s' "$linuxFlags" | grep -q -- '-ffast-math' \
     && printf '%s' "$linuxFlags" | grep -q -- '-fno-finite-math-only'; then
    ok "CTXPACK_PRETEND_LINUX=ON configures clean with NO Apple/host-specific flag: '$linuxFlags'"
else
    no "CTXPACK_PRETEND_LINUX=ON flags missing expected portable baseline: '$linuxFlags'"
fi

# ── #3: CTXPACK_NATIVE=ON stays opt-in and unaffected by the pretend-Linux hook ─────────────────────────
nativeFlags="$( run_probe "$TMP/native" -DCTXPACK_NATIVE=ON -DCTXPACK_PRETEND_LINUX=ON )"
if printf '%s' "$nativeFlags" | grep -q -- '-march=native'; then
    ok "CTXPACK_NATIVE=ON emits -march=native regardless of CTXPACK_PRETEND_LINUX: '$nativeFlags'"
else
    no "CTXPACK_NATIVE=ON did not emit -march=native: '$nativeFlags'"
fi
if printf '%s' "$nativeFlags" | grep -q -- '-mcpu=apple-m1'; then
    no "CTXPACK_NATIVE=ON unexpectedly also emits -mcpu=apple-m1: '$nativeFlags'"
else
    ok "CTXPACK_NATIVE=ON does not also emit -mcpu=apple-m1"
fi

# ── #4/#5: the REAL top-level CMakeLists.txt routes through the module, no reintroduced literal ─────────
if grep -Eq '^\s*add_compile_options\(-O2 -mcpu=apple-m1' "$CMAKE_TOP"; then
    no "CMakeLists.txt still hardcodes -mcpu=apple-m1 unconditionally"
else
    ok "CMakeLists.txt no longer hardcodes -mcpu=apple-m1 unconditionally"
fi
if grep -q 'include(cmake/PortableFlags.cmake)' "$CMAKE_TOP" && grep -q 'add_compile_options(\${CTXPACK_ARCH_FLAGS})' "$CMAKE_TOP"; then
    ok "CMakeLists.txt routes the optimization profile through cmake/PortableFlags.cmake"
else
    no "CMakeLists.txt does not route through cmake/PortableFlags.cmake"
fi

# NOTE (what this gate can prove vs what only Linux CI can prove): this machine is Apple-Silicon macOS, so
# it can prove the FLAG-SELECTION LOGIC never emits an Apple-specific flag once CTXPACK_IS_APPLE_SILICON is
# false (checks #2/#3 above, via the CTXPACK_PRETEND_LINUX hook), and that the real CMakeLists.txt wires
# that logic in (checks #4/#5). It CANNOT prove that clang/gcc on actual Linux/x86-64 hardware accepts the
# resulting flags and links a working binary, nor exercise CMAKE_SYSTEM_PROCESSOR values this host never
# reports (e.g. "x86_64"). That end-to-end proof is exactly what .github/workflows/ci.yml's ubuntu-24.04
# matrix leg provides; this gate is the local, sub-second proxy that catches a regression before it ever
# reaches CI.

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
