#!/usr/bin/env bash
# scripts/tidycheck.sh — the GATING clang-tidy subset: checks that sit at zero findings on this tree, kept there.
#
#   scripts/tidycheck.sh [BUILD_DIR]    GATE. Runs clang-tidy 22 with --checks='-*,<GATING below>' and
#                                       --warnings-as-errors='*' over TUS below; exits non-zero on any finding.
#                                       CI's style job runs exactly this (CLANG_TIDY=clang-tidy-22).
#   scripts/tidycheck.sh --list         Prints the gating check list and the TU list, and exits.
#
# WHAT GATES AND WHAT DOES NOT. `.clang-tidy`'s broad catalogue stays ADVISORY (CI runs it with continue-on-error;
# see that file's header). This script gates only checks whose every finding is a program that computes a
# silently wrong answer, and only those measured at ZERO rows on this tree when they were added — so the gate
# costs nothing today and says "never make it worse" to the next edit. The counts behind each choice are in
# `.clang-tidy`'s header. A new finding here is a bug to fix, not a line to NOLINT: a check that turns out to be
# noisy is removed from GATING with its count, the same way it was admitted.
#
# BUILD_DIR must hold a compile_commands.json. When none is given, a configure-only tree is made at build-tidy/
# (the same two commands as CI: no compile, only the generated version.h the TUs include).
#
# VERSION PIN. clang-tidy's checks change across majors; the zero was measured with 22. The resolution order is
# formatgatecheck.sh's: CLANG_TIDY when set (named explicitly: always used, and a wrong major is an ERROR, exit 2 —
# CI names it, so CI can never skip), else a major-22 clang-tidy-22 / clang-tidy on PATH, else Homebrew's keg-only
# <brew prefix>/opt/llvm@22/bin/clang-tidy (pinned by major: <brew prefix>/opt/llvm may be a different major).
# When none of those is major 22 the script prints a SKIP line naming what it found and exits 0 — a SKIP is not a
# pass, and it prints no verdict before it.

set -uo pipefail
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
WANT_MAJOR=22
# Homebrew's prefix: /opt/homebrew on Apple silicon, /usr/local on Intel macOS; read from brew when it is on PATH.
BREW_PREFIX="${HOMEBREW_PREFIX:-}"
[ -n "$BREW_PREFIX" ] || { command -v brew >/dev/null 2>&1 && BREW_PREFIX="$( brew --prefix 2>/dev/null )"; }
[ -n "$BREW_PREFIX" ] || BREW_PREFIX=/opt/homebrew
BREW_TIDY="${RIPWIRE_TIDY_BREW:-$BREW_PREFIX/opt/llvm@22/bin/clang-tidy}"   # override only to test the SKIP arm

# ─── the gating checks: each one at 0 rows on the TUs below when admitted ────────────────────────────────────────
GATING='bugprone-use-after-move,bugprone-dangling-handle,bugprone-sizeof-expression,bugprone-integer-division,bugprone-infinite-loop,clang-analyzer-core.*'

# ─── the TU list: CI's advisory clang-tidy step lints the same five ─────────────────────────────────────────────
TUS="src/main.cpp src/ingest.cpp src/pagerank.cpp src/tsprobe.cpp src/infra/diagnostics.cpp"

case "${1:-}" in
    --list ) printf 'checks: %s\nTUs: %s\n' "$GATING" "$TUS"; exit 0 ;;
    -* )     echo "usage: $0 [BUILD_DIR|--list]" >&2; exit 2 ;;
esac

. "$ROOT/scripts/llvmmajor.sh"   # llvm_major, shared with test/formatgatecheck.sh

if [ -n "${CLANG_TIDY:-}" ]; then
    CT="$CLANG_TIDY"; have="$( llvm_major "$CT" )"
    if [ "$have" != "$WANT_MAJOR" ]; then
        echo "error: CLANG_TIDY='$CT' is major '${have:-none}', and the gating subset is pinned to $WANT_MAJOR."; exit 2
    fi
else
    CT=""; seen=""
    for c in "$( command -v clang-tidy-$WANT_MAJOR 2>/dev/null )" "$( command -v clang-tidy 2>/dev/null )" "$BREW_TIDY"; do
        [ -n "$c" ] || continue
        m="$( llvm_major "$c" )"; seen="$seen ${c}=${m:-unreadable}"
        [ "$m" = "$WANT_MAJOR" ] && { CT="$c"; break; }
    done
    if [ -z "$CT" ]; then
        echo "SKIP  tidycheck: no clang-tidy major $WANT_MAJOR found (tried:${seen:- nothing on PATH or at $BREW_TIDY})."
        echo "      This is NOT a pass. Install LLVM $WANT_MAJOR (macOS: brew install llvm@22) or set CLANG_TIDY=/path."
        exit 0
    fi
fi

cd "$ROOT" || exit 2
BUILD="${1:-build-tidy}"
if [ ! -f "$BUILD/compile_commands.json" ]; then
    [ -z "${1:-}" ] || { echo "error: no compile_commands.json in '$BUILD'"; exit 2; }
    cmake -S . -B "$BUILD" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null \
        && cmake --build "$BUILD" --target ripwire_version_stamp >/dev/null \
        || { echo "error: could not configure a compile database at $BUILD"; exit 2; }
fi

# A Homebrew clang-tidy on macOS does not find the SDK's headers from AppleClang's compile database by itself.
extra=()
if [ "$( uname -s )" = "Darwin" ] && command -v xcrun >/dev/null 2>&1; then
    extra=( "--extra-arg=-isysroot$( xcrun --show-sdk-path )" )
fi

echo "tidycheck: $CT (major $WANT_MAJOR), $( echo "$GATING" | tr ',' '\n' | grep -c . ) check(s) over: $TUS"
# shellcheck disable=SC2086
"$CT" -p "$BUILD" --quiet ${extra[@]+"${extra[@]}"} --checks="-*,$GATING" --warnings-as-errors='*' $TUS
rc=$?
if [ "$rc" -eq 0 ]; then echo "tidycheck: PASS — 0 findings from the gating subset"; else echo "tidycheck: FAIL (rc=$rc) — see the findings above"; fi
exit "$rc"
