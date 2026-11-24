#!/usr/bin/env bash
# scripts/tidycheck.sh — the GATING clang-tidy subset: checks that sit at zero findings on this tree, kept there.
#
#   scripts/tidycheck.sh [BUILD_DIR]    GATE. Runs clang-tidy 22 with --checks='-*,<GATING below>' and
#                                       --warnings-as-errors='*' over TUS below; exits non-zero on any finding.
#                                       CI's style job runs exactly this (CLANG_TIDY=clang-tidy-22).
#   scripts/tidycheck.sh --ratchet [BUILD_DIR]
#                                       GATE, the second one. Runs the RATCHET checks below (no --warnings-as-errors)
#                                       and diffs the report against .clang-tidy-baseline.txt's rows for those checks
#                                       with scripts/tidyadvisory_diff.py --scope --gate: exits 1 on any finding that is
#                                       not already a baseline row, 2 when clang-tidy failed. CI's style job runs it
#                                       on every event. RATCHET_NIGHTLY's extra check is gated by its own nightly
#                                       job instead (ci.yml tidy-exception-escape), with the same diff — see RATCHET below.
#   scripts/tidycheck.sh --list         Prints the gating list, both ratchet lists and the TU list, and exits.
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
GATING='bugprone-use-after-move,bugprone-dangling-handle,bugprone-sizeof-expression,bugprone-integer-division,bugprone-infinite-loop,clang-analyzer-core.*,clang-analyzer-cplusplus.InnerPointer'

# ─── the ratchet checks (0.7.1): high-signal, but NOT at zero rows, so they cannot join GATING ─────────────────────
# Every finding of these is a crash, a terminate, a read of freed or uninitialised memory, or a wrong value — but some
# sit on accepted baseline rows today (bugprone-exception-escape 43, bugprone-unchecked-optional-access 10, and 1-2 each
# for signed-char-misuse, throwing-static-initialization, inc-dec-in-conditions, suspicious-stringview-data-usage,
# suspicious-missing-comma; counts in .clang-tidy-ratchet.txt). So the gate is "no NEW row": a finding that is not
# already in the baseline fails, a baselined one passes, a fixed one is pruned. use-after-move and dangling-handle are
# also in GATING above; listing them here as well costs nothing and keeps this list the whole high-signal set.
# misc-dangling-* matches no check in clang-tidy 22 (the dangling checks are bugprone-*); it is kept so a future
# misc-dangling check is ratcheted the day it exists.
# bugprone-exception-escape is NOT in the per-event list: it walks every call reachable from each noexcept function,
# and on main.cpp's TU (the whole header-only program) it is the cost of the advisory run. Measured 2026-11-23 on
# 30ed48862, Homebrew clang-tidy 22.1.8, macOS: the per-event list below took 154 s (unchecked-optional-access) + 31 s
# (the rest) on main.cpp, while exception-escape alone ran more than 8 h and was stopped (libc++ exposes every
# string_view::substr's throw; CI's libstdc++ does not, so it is cheaper there, but not measured). So it is gated
# NIGHTLY, in its own job (ci.yml tidy-exception-escape: parallel TUs, a per-TU timeout inside the job limit), with
# the same diff and --gate. The advisory catalogue runs without it: it was nearly that step's whole 5 h 27 min.
RATCHET='bugprone-unchecked-optional-access,bugprone-use-after-move,bugprone-dangling-handle,misc-dangling-*,bugprone-suspicious-missing-comma,bugprone-signed-char-misuse,bugprone-suspicious-stringview-data-usage,bugprone-throwing-static-initialization,bugprone-inc-dec-in-conditions'
RATCHET_NIGHTLY="$RATCHET,bugprone-exception-escape"

# ─── the TU list: CI's advisory clang-tidy step lints the same five ─────────────────────────────────────────────
TUS="src/main.cpp src/ingest.cpp src/pagerank.cpp src/tsprobe.cpp src/infra/diagnostics.cpp"

MODE=gate
case "${1:-}" in
    --list )    printf 'checks: %s\nratchet: %s\nratchet-nightly: %s\nTUs: %s\n' "$GATING" "$RATCHET" "$RATCHET_NIGHTLY" "$TUS"; exit 0 ;;
    --ratchet ) MODE=ratchet; shift ;;
    -* )        echo "usage: $0 [--ratchet] [BUILD_DIR] | --list" >&2; exit 2 ;;
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

if [ "$MODE" = ratchet ]; then
    # One clang-tidy per TU, in parallel: the TUs are independent and main.cpp's dominates either way. The report is the
    # concatenation; tidyadvisory_diff.py dedupes a header's finding across TUs. The worst exit status is the run's.
    TMPR="$( mktemp -d )"
    trap 'rm -rf "$TMPR"' EXIT
    echo "tidycheck --ratchet: $CT (major $WANT_MAJOR), $( echo "$RATCHET" | tr ',' '\n' | grep -c . ) check(s) over: $TUS"
    i=0; pids=()
    for tu in $TUS; do
        "$CT" -p "$BUILD" --quiet ${extra[@]+"${extra[@]}"} --checks="-*,$RATCHET" "$tu" >"$TMPR/r.$i.txt" 2>&1 &
        pids+=( "$!" ); i=$(( i + 1 ))
    done
    worst=0
    for p in "${pids[@]}"; do wait "$p"; r=$?; [ "$r" -gt "$worst" ] && worst=$r; done
    cat "$TMPR"/r.*.txt >"$TMPR/report.txt"
    echo "$worst" >"$TMPR/rc"
    python3 "$ROOT/scripts/tidyadvisory_diff.py" --report "$TMPR/report.txt" --rc "$TMPR/rc" --root "$ROOT" \
        --baseline "$ROOT/.clang-tidy-baseline.txt" --scope "$RATCHET" --gate
    rc=$?
    if [ "$rc" -eq 0 ]; then echo "tidycheck --ratchet: PASS — no finding outside the baseline in the ratchet set"
    else echo "tidycheck --ratchet: FAIL (rc=$rc) — fix the NEW rows above (a baselined row needs review, not a re-baseline)"; fi
    exit "$rc"
fi

echo "tidycheck: $CT (major $WANT_MAJOR), $( echo "$GATING" | tr ',' '\n' | grep -c . ) check(s) over: $TUS"
# shellcheck disable=SC2086
"$CT" -p "$BUILD" --quiet ${extra[@]+"${extra[@]}"} --checks="-*,$GATING" --warnings-as-errors='*' $TUS
rc=$?
if [ "$rc" -eq 0 ]; then echo "tidycheck: PASS — 0 findings from the gating subset"; else echo "tidycheck: FAIL (rc=$rc) — see the findings above"; fi
exit "$rc"
