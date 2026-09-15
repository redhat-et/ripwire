#!/usr/bin/env bash
# adaptivecutshapecheck.sh — A4-F4 unit-style gate, run BEFORE any relevance-cliff cut work: reproduces the
# exact deterministic score-vector shape the audit used (head cliff ~35% relative drop at rank 8 + a much
# larger ~98% relative drop far out in the tail, beyond hardCeil=40) and asserts adaptiveCut(...,
# scanFullDistribution=true) actually CUTS ON THE HEAD CLIFF instead of being inert (kept 40/40).
#
# Before the fix: tracking only the single GLOBAL-max relative drop meant the big-but-unreachable tail drop
# (beyond hardCeil) always won over the real, in-cap head cliff, so the cut candidate (bestCutKept=60ish)
# failed the `< hardCeil` guard and the function fell back to "keep the whole ceiling" — 40/40, inert on
# exactly the sharp queries adaptive-cut exists for.
#
# This is a standalone .cpp (lexical.h is header-only) compiled directly with clang++ — no CMake wiring
# needed, and a synthetic score vector is the precise, deterministic way to pin this exact shape (a
# real-corpus repro is not guaranteed to keep landing on the identical rank/pct numbers as source drifts).
#
# Usage: bash test/adaptivecutshapecheck.sh
# Exits non-zero on any failure. Does NOT touch regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
SRC="$ROOT/test/adaptivecutshapefix/adaptive_cut_shape_test.cpp"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
ROOT_NATIVE="$ROOT"
SRC_NATIVE="$SRC"
TMP_NATIVE="$TMP"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "adaptivecutshapecheck: SRC=$SRC"

WINDOWS_GATE=0
case "$( uname -s 2>/dev/null )" in
    MINGW*|MSYS*) WINDOWS_GATE=1 ;;
esac
[ "${OS:-}" = Windows_NT ] && WINDOWS_GATE=1
if [ "$WINDOWS_GATE" -eq 1 ]; then
    # Git for Windows does not normally put LLVM's GNU-style driver on PATH, while the native CMake
    # build uses clang-cl. Use the installed clang++ directly for this standalone source, because the
    # rest of this gate intentionally speaks portable -std/-I/-o driver syntax.
    CXX="${CXX:-C:/Program Files/LLVM/bin/clang++.exe}"
    if ! command -v cygpath >/dev/null 2>&1; then
        no "cygpath is required to pass native Windows paths to clang++"
        exit 1
    fi
    ROOT_NATIVE="$( cygpath -w "$ROOT" )"
    SRC_NATIVE="$( cygpath -w "$SRC" )"
    TMP_NATIVE="$( cygpath -w "$TMP" )"
    if [ -z "${RIPWIRE_NATIVE_PATH:-}" ]; then
        VC_VARS="${RIPWIRE_VCVARS:-C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat}"
        VC_ENV_BAT="$TMP/vcenv.bat"
        {
            printf '@echo off\n'
            printf 'call "%s" amd64 10.0.19041.0 >nul\n' "$VC_VARS"
            printf 'if errorlevel 1 exit /b %%errorlevel%%\n'
            printf 'set\n'
        } > "$VC_ENV_BAT"
        VC_ENV_NATIVE="$VC_ENV_BAT"
        command -v cygpath >/dev/null 2>&1 && VC_ENV_NATIVE="$( cygpath -w "$VC_ENV_NATIVE" )"
        if ! MSYS_NO_PATHCONV=1 cmd.exe /d /c "$VC_ENV_NATIVE" > "$TMP/vcenv.txt"; then
            no "could not initialize the MSVC environment for the standalone probe"
            cat "$TMP/vcenv.txt"
            echo "FAILURES ABOVE"
            exit 1
        fi
        while IFS= read -r line; do
            case "$line" in
                INCLUDE=*|LIB=*|LIBPATH=*) export "${line%%=*}=${line#*=}" ;;
            esac
        done < <( tr -d '\015' < "$TMP/vcenv.txt" )
    fi
    CXX_EXTRA=( -D_MSVC_LANG=202302L -D_CRT_SECURE_NO_WARNINGS -D_CRT_NONSTDC_NO_DEPRECATE )
    if [ -z "${RIPWIRE_NATIVE_PATH:-}" ]; then
        CXX_EXTRA+=( -include "$ROOT_NATIVE/src/infra/platform_compat.h" )
    fi
else
    CXX="${CXX:-clang++}"
    # …and if `clang++` is not on PATH, use whatever C++ driver is (the same fallback utf8scrubcheck
    # already does). This gate prefers clang++ but does not depend on it, and a machine that only ships
    # `c++`/`g++` used to fail it with a bare "clang++: command not found" — a missing tool reported as a
    # product defect. Reproduced on a stock ubuntu:24.04 image while diagnosing PR #1.
    command -v "$CXX" >/dev/null 2>&1 || CXX=c++
    command -v "$CXX" >/dev/null 2>&1 || CXX=g++
    CXX_EXTRA=()
fi

# §CI-P3: ask THIS front end how it spells C++23 rather than assuming the Clang-17 spelling — an
# AppleClang 15 (LLVM 16) macos-14 runner rejects `-std=c++23` outright and took this gate with it
# (PR #1, run 30732976779). Rationale + the CMake mapping this mirrors: scripts/cxxstd.sh.
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
"$CXX" "$CXXSTD" "${CXX_EXTRA[@]}" -I "$ROOT_NATIVE/src" -I "$ROOT_NATIVE/src/infra" -I "$ROOT_NATIVE/third_party" "$SRC_NATIVE" "$ROOT_NATIVE/src/infra/diagnostics.cpp" -o "$TMP_NATIVE/t" 2>"$TMP/build.err"
[ "$WINDOWS_GATE" -eq 1 ] && test -f "$TMP_NATIVE/t.exe" && cp "$TMP_NATIVE/t.exe" "$TMP/t" 2>/dev/null || true
if [ -x "$TMP/t" ]; then
    ok "gate binary built"
else
    no "build failed"; cat "$TMP/build.err"; echo "FAILURES ABOVE"; exit 1
fi

OUT="$( "$TMP/t" )"
printf '%s\n' "$OUT"

FULL_KEPT="$(  printf '%s\n' "$OUT" | grep '^full:'   | grep -oE 'kept=[0-9]+'       | cut -d= -f2 )"
FULL_HIT="$(   printf '%s\n' "$OUT" | grep '^full:'   | grep -oE 'hitCeiling=[0-9]+' | cut -d= -f2 )"
FULL_DROP="$(  printf '%s\n' "$OUT" | grep '^full:'   | grep -oE 'dropPct=[0-9]+'    | cut -d= -f2 )"
CAP_KEPT="$(   printf '%s\n' "$OUT" | grep '^capped:' | grep -oE 'kept=[0-9]+'       | cut -d= -f2 )"

# the FIX: scanFullDistribution=true must cut at the head cliff (kept in [5,10], NOT the ceiling 40) —
# this is the exact regression the finding describes ("keeps 40/40" was the bug).
{ [ -n "$FULL_KEPT" ] && [ "$FULL_KEPT" -ge 5 ] && [ "$FULL_KEPT" -le 10 ]; } \
    && ok "A4-F4: scanFullDistribution=true cuts at the head cliff (kept=$FULL_KEPT, not 40/40)" \
    || no "A4-F4: NOT fixed — scanFullDistribution=true kept=$FULL_KEPT (want a small head-cliff cut, e.g. ~7)"
[ "$FULL_HIT" = "0" ] && ok "A4-F4: hitCeiling=false (a real cut was made, not a ceiling cap)" \
    || no "A4-F4: hitCeiling=$FULL_HIT (expected false — a cut should have fired)"
{ [ -n "$FULL_DROP" ] && [ "$FULL_DROP" -ge 25 ] && [ "$FULL_DROP" -le 45 ]; } \
    && ok "A4-F4: reported dropPct=$FULL_DROP is the in-cap ~35% head cliff, not the beyond-cap ~98% tail drop" \
    || no "A4-F4: dropPct=$FULL_DROP does not match the expected ~35% head-cliff magnitude"

# sanity: the capped (scanFullDistribution=false) scan already found this same head cliff before the fix —
# proves the test shape itself is sound and the fix doesn't change the ALREADY-CORRECT capped-mode behavior.
[ "$CAP_KEPT" = "$FULL_KEPT" ] \
    && ok "sanity: capped-mode (unaffected by this fix) agrees with full-mode on the same head cliff" \
    || no "sanity FAILED: capped=$CAP_KEPT vs full=$FULL_KEPT — the fixture shape may not isolate the bug as intended"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
