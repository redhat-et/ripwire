#!/usr/bin/env bash
# cxxstd.sh — the ONE place the standalone harness gates ask "how does THIS front end spell C++23?".
# Sourced, not executed:   . "$ROOT/scripts/cxxstd.sh";  CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
#
# It lives in scripts/ (beside formatcheck.sh and scorecard.sh — the repo's shared shell) and NOT in test/,
# because test/gateexitcheck.sh sweeps every test/*.sh AS A GATE and requires each to exit non-zero on a
# recorded failure. This is a sourced LIBRARY with no terminal region, so parked in test/ it turned that
# meta-gate red ("could not be checked: the extraction is not runnable in isolation") — correctly, since
# gateexitcheck's premise is that everything in test/ is a gate. The fix is to not violate the premise.
#
# WHY THIS EXISTS (PR #1, run 30732976779, release (macos-14)). Seven gates compile a standalone harness
# by hand — type3clonecheck, clonebandcheck, clonelexcheck, adaptivecutshapecheck, connectcorecheck,
# columnarcommacheck, utf8scrubcheck — and every one of them hardcoded `-std=c++23`. All seven, and ONLY
# those seven, went red on macos-14 while the Build step and all 300+ other gates stayed green, and while
# ubuntu-24.04 (clang 18 / gcc 13) passed them.
#
# `-std=c++23` is a Clang 17 spelling. Clang 16 and earlier accept the standard ONLY as `-std=c++2b` and
# reject `c++23` outright ("invalid value 'c++23' in '-std=c++23'"). The macos-14 runner reports
# `AppleClang 15.0.0.15000309` — LLVM 16 — so the flag is rejected before a single line is parsed.
#
# The CMake build never noticed because CMake already knows this. From CMake's own
# Modules/Compiler/AppleClang-CXX.cmake:
#
#     if (NOT CMAKE_CXX_COMPILER_VERSION VERSION_LESS 16.0)
#       set(CMAKE_CXX23_STANDARD_COMPILE_OPTION "-std=c++23")
#     ...
#       set(CMAKE_CXX23_STANDARD_COMPILE_OPTION "-std=c++2b")
#
# i.e. `set(CMAKE_CXX_STANDARD 23)` emits `-std=c++2b` on that toolchain. The real ripwire target therefore
# built fine on the very runner where seven hand-rolled compile lines could not. This function is that same
# mapping, done by PROBE rather than by version table, so it is right for any front end and needs no
# maintenance when a new one lands.
#
# BEHAVIOUR IS IDENTICAL EVERYWHERE: `c++23` is tried FIRST, so every toolchain that understands the modern
# spelling keeps using it byte for byte; only a front end that rejects it falls back, and it falls back to
# the SAME language mode, not to an older standard. If neither is accepted the canonical `-std=c++23` is
# returned unchanged (with rc=1) so the caller's compile fails loudly, naming the flag, instead of this
# helper silently downgrading the harness to C++17.

# ripwire_cxx_std_flag CXX  →  prints the C++23 flag spelling CXX accepts; rc=1 if it accepts neither.
ripwire_cxx_std_flag()
{
    local cxx="${1:-c++}" probe flag rc=1
    probe="$( mktemp -d )"
    printf 'int main(){ return 0; }\n' > "$probe/cxxstd_probe.cpp"

    for flag in -std=c++23 -std=c++2b; do
        if "$cxx" "$flag" -fsyntax-only "$probe/cxxstd_probe.cpp" >/dev/null 2>&1; then
            rc=0
            break
        fi
    done
    [ "$rc" -eq 0 ] || flag=-std=c++23          # neither accepted → keep the canonical spelling so the failure names itself

    rm -rf "$probe"
    printf '%s' "$flag"
    return "$rc"
}
