#!/usr/bin/env bash
# clonelexcheck.sh — gate for the clone-normalizer apostrophe/comment lexing fix (A4-F2) and the O(1)
# keyword membership (A4-P3) in src/clones.h.
#
# clones.h is header-only, so this gate compiles a tiny standalone harness (test/clonelex_harness.cpp) that
# #includes clones.h and asserts the exact token stream normalizeSpan()/normalizeTokens() produce for:
#   F2-a  Rust lifetime `'a` (punctuation) vs a real char literal `'a'` ($S).
#   F2-b  C++14 digit separators (1'000'000) collapsing to a single $N.
#   F2-c  real char literals ('x' '\n' '\\' '\xNN' '\0') still normalizing to $S.
#   F2-d  ' right after an identifier byte staying punctuation.
#   F2-e  two bodies differing only AFTER an unpaired lifetime ' normalizing DIFFERENTLY (the core repro).
#   F2-f  Python/shell `#` line comments (incl. a `don't` contraction) dropped when stripHashComments.
#   P3    cloneIsKeyword membership correctness.
#   MUT   a mutation self-test (lifetime stream must differ from char-literal stream).
#
# Independent of the ripwire binary and of main.cpp. Uses its OWN temp dir. Does NOT edit regression.sh.
# Usage:  bash test/clonelexcheck.sh            (compiles with c++/clang++)
#         CXX=clang++ bash test/clonelexcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"
HARNESS="$ROOT/test/clonelex_harness.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/clonelexharness"

echo "clonelexcheck: CXX=$CXX"

# ── compile the harness against clones.h (header-only): infra + src on the include path ───────────────────────
# fastmath.cpp supplies Diagnostics::ConsoleLog::handleDegraded (the DEGRADED_PATH_ALERT seam) — link it exactly
# as the real ripwire target does, so any degrade path resolves at link time.
if ! "$CXX" -std=c++23 -O2 -g -Wall -Wextra \
        -I"$ROOT/src/infra" -I"$ROOT/third_party" -I"$ROOT/src" \
        "$HARNESS" "$ROOT/src/infra/fastmath.cpp" -o "$BIN" 2> "$WORK/cc.log"; then
    echo "  FAIL  harness failed to compile"; sed 's/^/    /' "$WORK/cc.log"; exit 2
fi
echo "  PASS  harness compiled"

# ── run it: nonzero exit ⇒ a behavioural assertion failed ────────────────────────────────────────────────────
if "$BIN"; then
    echo "clonelexcheck: ALL PASS"
    exit 0
else
    echo "clonelexcheck: FAIL"
    exit 2
fi
