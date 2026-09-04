#!/usr/bin/env bash
# portablebuildcheck.sh — gate for L1 ( independence MUST-FIX #5): "Non-NATIVE build hardcodes
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
#   2) default configure + RIPWIRE_PRETEND_LINUX=ON (the test-only hook): must emit -O2 -ffast-math
#      -fno-finite-math-only and NOTHING Apple/host-specific (-mcpu=apple-m1 absent, -march=native absent).
#      This is the provable half of "Linux/x86-64/aarch64 must configure cleanly with no Apple flags" —
#      see the NOTE at the bottom for what this machine cannot prove.
#   3) RIPWIRE_NATIVE=ON: must emit -march=native (opt-in, unaffected by RIPWIRE_PRETEND_LINUX).
#   4) the real top-level CMakeLists.txt no longer hardcodes -mcpu=apple-m1 unconditionally (it must be
#      confined to the RIPWIRE_IS_APPLE_SILICON branch inside cmake/PortableFlags.cmake).
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

# Configure the probe with the given extra -D args; echoes the RIPWIRE_ARCH_FLAGS line (without the
# 'RIPWIRE_ARCH_FLAGS:' prefix), or nothing if the configure failed outright.
run_probe(){
    local dir="$1"; shift
    mk_probe "$dir"
    local log="$dir/configure.log"
    if ! cmake -S "$dir" -B "$dir/build" "$@" >"$log" 2>&1; then
        printf 'CONFIGURE_FAILED\n'
        return
    fi
    grep -o 'RIPWIRE_ARCH_FLAGS:.*' "$log" | tail -1 | sed 's/^RIPWIRE_ARCH_FLAGS://'
}

echo "portablebuildcheck: BIN=n/a (CMake-configure-level gate, no ripwire binary needed)"

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

# ── #2: RIPWIRE_PRETEND_LINUX=ON — the provable portable-path check ────────────────────────────────────
linuxFlags="$( run_probe "$TMP/linux" -DRIPWIRE_PRETEND_LINUX=ON )"
if [ "$linuxFlags" = "CONFIGURE_FAILED" ]; then
    no "RIPWIRE_PRETEND_LINUX=ON configure failed outright: $(tail -5 "$TMP/linux/configure.log" 2>/dev/null)"
elif printf '%s' "$linuxFlags" | grep -q -- '-mcpu=apple-m1'; then
    no "RIPWIRE_PRETEND_LINUX=ON still emits -mcpu=apple-m1: '$linuxFlags'"
elif printf '%s' "$linuxFlags" | grep -q -- '-march=native'; then
    no "RIPWIRE_PRETEND_LINUX=ON still emits -march=native: '$linuxFlags'"
elif printf '%s' "$linuxFlags" | grep -q -- '-O2' && printf '%s' "$linuxFlags" | grep -q -- '-ffast-math' \
     && printf '%s' "$linuxFlags" | grep -q -- '-fno-finite-math-only'; then
    ok "RIPWIRE_PRETEND_LINUX=ON configures clean with NO Apple/host-specific flag: '$linuxFlags'"
else
    no "RIPWIRE_PRETEND_LINUX=ON flags missing expected portable baseline: '$linuxFlags'"
fi

# ── #3: RIPWIRE_NATIVE=ON stays opt-in and unaffected by the pretend-Linux hook ─────────────────────────
nativeFlags="$( run_probe "$TMP/native" -DRIPWIRE_NATIVE=ON -DRIPWIRE_PRETEND_LINUX=ON )"
if printf '%s' "$nativeFlags" | grep -q -- '-march=native'; then
    ok "RIPWIRE_NATIVE=ON emits -march=native regardless of RIPWIRE_PRETEND_LINUX: '$nativeFlags'"
else
    no "RIPWIRE_NATIVE=ON did not emit -march=native: '$nativeFlags'"
fi
if printf '%s' "$nativeFlags" | grep -q -- '-mcpu=apple-m1'; then
    no "RIPWIRE_NATIVE=ON unexpectedly also emits -mcpu=apple-m1: '$nativeFlags'"
else
    ok "RIPWIRE_NATIVE=ON does not also emit -mcpu=apple-m1"
fi

# ── #4/#5: the REAL top-level CMakeLists.txt routes through the module, no reintroduced literal ─────────
if grep -Eq '^\s*add_compile_options\(-O2 -mcpu=apple-m1' "$CMAKE_TOP"; then
    no "CMakeLists.txt still hardcodes -mcpu=apple-m1 unconditionally"
else
    ok "CMakeLists.txt no longer hardcodes -mcpu=apple-m1 unconditionally"
fi
if grep -q 'include(cmake/PortableFlags.cmake)' "$CMAKE_TOP" && grep -q 'add_compile_options(\${RIPWIRE_ARCH_FLAGS})' "$CMAKE_TOP"; then
    ok "CMakeLists.txt routes the optimization profile through cmake/PortableFlags.cmake"
else
    no "CMakeLists.txt does not route through cmake/PortableFlags.cmake"
fi

# ── #6: no ORDERED STL algorithm over std::string_view with the DEFAULT comparator, anywhere in src/ ──
# WHY THIS IS A PORTABILITY RULE AND NOT A STYLE ONE. libstdc++'s string_view three-way compare computes
# `n1 - n2` on size_type and lets it wrap (bits/string_view.h, _S_compare). That wrap is well-defined C++,
# but the G1 sanitizer stack runs -fsanitize=integer, which reports it, and -fno-sanitize-recover=all turns
# the report into an abort. libc++ (every macOS leg, including the macOS ASan leg) computes the same answer
# without the subtraction and never reports. So `std::binary_search( first, last, sv )` is green on this
# machine, green on the macOS sanitizer leg, and aborts EVERY ranked run on the Linux sanitizer leg.
# That is exactly what happened at 69a17f9: the external-name veto's two table lookups took main red with
# `unsigned integer overflow: 3 - 17` inside std::binary_search, on a repository whose own macOS battery
# and macOS ASan leg were both clean. The rule is therefore mechanical: pass an explicit byte-comparator.
SVBAD="$( grep -rnE '(binary_search|lower_bound|upper_bound|equal_range)\(' "$ROOT/src" 2>/dev/null \
          | grep -vE '^\s*[0-9]+:\s*//' \
          | grep -E 'kPythonBuiltinNames|kCFamilyStdNames|string_view' \
          | grep -vE 'nameLess|svLess|, *\[' || true )"
if [ -z "$SVBAD" ]; then
    ok "#6 no ordered STL search over string_view relies on libstdc++'s wrapping three-way compare"
else
    no "#6 ordered STL search over string_view with the DEFAULT comparator — aborts the Linux G1 leg (pass an explicit byte-comparator):"
    printf '%s\n' "$SVBAD" | sed 's/^/        /'
fi

# NOTE (what this gate can prove vs what only Linux CI can prove): this machine is Apple-Silicon macOS, so
# it can prove the FLAG-SELECTION LOGIC never emits an Apple-specific flag once RIPWIRE_IS_APPLE_SILICON is
# false (checks #2/#3 above, via the RIPWIRE_PRETEND_LINUX hook), and that the real CMakeLists.txt wires
# that logic in (checks #4/#5). It CANNOT prove that clang/gcc on actual Linux/x86-64 hardware accepts the
# resulting flags and links a working binary, nor exercise CMAKE_SYSTEM_PROCESSOR values this host never
# reports (e.g. "x86_64"). That end-to-end proof is exactly what .github/workflows/ci.yml's ubuntu-24.04
# matrix leg provides; this gate is the local, sub-second proxy that catches a regression before it ever
# reaches CI.

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
