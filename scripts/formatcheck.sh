#!/usr/bin/env bash
# scripts/formatcheck.sh — the clang-format gate, and the advisory report next to it
#
# Two modes, because .clang-format can honestly gate only part of this tree:
#
#   scripts/formatcheck.sh              GATE. Runs clang-format --dry-run --Werror over the
#                                       files listed in GATED below and exits non-zero if any
#                                       of them has drifted. CI runs exactly this.
#   scripts/formatcheck.sh --advisory   REPORT. Names every first-party C++ file clang-format
#                                       would rewrite. Always exits 0. Never a gate.
#   scripts/formatcheck.sh --list       Prints the gated file list and exits.
#
# WHY THE LIST IS SHORT (9 of 98 files). CONTRIBUTING.md §3's house style is hand-formatted in
# ways clang-format has no option to preserve — multi-statement one-liners, `for( … ) if( … )
# return i;`, several initialiser rows or `case` labels packed per line, wrap seams chosen by
# hand at 160-200 columns. Measured at 73963d2: reformatting all 98 first-party C++ files
# changes 11837 lines that survive `git diff -w`, i.e. real joins and splits, across 89 files.
# So a whole-tree --Werror check would be red on a correctly-styled tree. GATED therefore holds
# exactly the files that already agree with .clang-format byte for byte; they are gated so they
# stay that way, and the other 89 are reported by --advisory so the gap stays visible.
#
# ADDING TO THE LIST is the good outcome: run `clang-format -i` on a file, confirm
# `git diff -w --output=/tmp/d && [ ! -s /tmp/d ]` (whitespace only), run the suite, then add it.
# REMOVING FROM THE LIST is a legitimate outcome too. If you write house-style code in a gated
# file — a packed table, a `{ a; b; }` one-liner — this check will call it unformatted and the
# house style is the one that is right. Delete the path from GATED rather than un-writing the
# code, and say so in the commit message.
#
# VERSION PIN. clang-format's output moves across major releases, so an unpinned checker reports
# drift on a tree that was formatted correctly. .clang-format was produced and verified with
# clang-format 22; this script refuses any other major unless RIPWIRE_FORMAT_ANY_VERSION=1.
#
# Override the binary with CLANG_FORMAT=/path/to/clang-format (homebrew LLVM is not on PATH on
# macOS by default: /opt/homebrew/opt/llvm/bin/clang-format).

set -uo pipefail
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CF="${CLANG_FORMAT:-clang-format}"
WANT_MAJOR=22

# ─── the gated set: files that already match .clang-format exactly ────────────────────────────
read -r -d '' GATED << 'GATED_EOF' || true
src/csrverify.h
src/graphlegend.h
src/hashutil.h
src/infra/radixSort.h
src/namesplit.h
src/ownersview.h
src/pagerank.cpp
src/pagerank.h
src/stdinline.h
GATED_EOF

mode="gate"
case "${1:-}" in
    --advisory ) mode="advisory" ;;
    --list     ) printf '%s\n' "$GATED"; exit 0 ;;
    "" )         ;;
    * )          echo "usage: $0 [--advisory|--list]" >&2; exit 2 ;;
esac

command -v "$CF" >/dev/null 2>&1 || { echo "error: no clang-format at '$CF' — set CLANG_FORMAT=/path/to/clang-format"; exit 2; }

# ─── version pin ──────────────────────────────────────────────────────────────────────────────
have="$( "$CF" --version 2>/dev/null | sed -n 's/.*version \([0-9][0-9]*\).*/\1/p' | head -1 )"
if [ -z "$have" ]; then
    echo "error: could not read a major version out of '$CF --version'"; exit 2
fi
if [ "$have" != "$WANT_MAJOR" ] && [ "${RIPWIRE_FORMAT_ANY_VERSION:-0}" != "1" ]; then
    echo "error: clang-format $have found, but .clang-format is pinned to major $WANT_MAJOR."
    echo "       Different majors format differently, so this check would report false drift."
    echo "       Install LLVM $WANT_MAJOR, or set RIPWIRE_FORMAT_ANY_VERSION=1 to run anyway."
    exit 2
fi

cd "$ROOT" || exit 2

# ─── advisory mode: report the whole first-party set, never fail ──────────────────────────────
if [ "$mode" = "advisory" ]; then
    all="$( { find src -type f \( -name '*.h' -o -name '*.cpp' -o -name '*.inl' \); ls test/*.cpp 2>/dev/null; } | LC_ALL=C sort )"
    total=0; drifted=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        total=$(( total + 1 ))
        if ! "$CF" --style=file --dry-run --Werror "$f" >/dev/null 2>&1; then
            drifted=$(( drifted + 1 ))
            echo "  would reformat: $f"
        fi
    done <<< "$all"
    echo "formatcheck --advisory: $drifted of $total first-party C++ file(s) differ from .clang-format."
    echo "This is a report, not a gate — see the header of $0 for why the number is not zero."
    exit 0
fi

# ─── gate mode ────────────────────────────────────────────────────────────────────────────────
missing=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || { echo "  FAIL  gated file is missing from the tree: $f"; missing=1; }
done <<< "$GATED"
[ "$missing" -eq 0 ] || { echo "formatcheck: FAILURES (a gated path no longer exists — fix the list in $0)"; exit 1; }

rc=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if "$CF" --style=file --dry-run --Werror "$f" >/dev/null 2>&1; then
        echo "  PASS  $f"
    else
        echo "  FAIL  $f is not formatted to .clang-format"
        "$CF" --style=file --dry-run --Werror "$f" 2>&1 | sed 's/^/        /'
        rc=1
    fi
done <<< "$GATED"

if [ "$rc" -eq 0 ]; then
    echo "formatcheck: ALL PASS (clang-format $have, $( printf '%s\n' "$GATED" | grep -c . ) gated file(s))"
else
    echo "formatcheck: FAILURES — run '$CF -i --style=file <file>', or drop the file from GATED in $0"
    echo "             if the code that broke it is correct house style (see this script's header)."
fi
exit "$rc"
