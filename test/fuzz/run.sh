#!/usr/bin/env bash
# Bounded full fuzz sweep. Not part of normal regression; invoke explicitly from the G1/release gate.
#
#   bash test/fuzz/run.sh [BUILD_DIR] [SECONDS] [GRAMMARS]   # every grammar (or the GRAMMARS named) for SECONDS each
#   bash test/fuzz/run.sh --list                             # print the grammars a sweep would run, one per line
#
# The grammar list is not written here. It is the NAME of every add_ripwire_fuzzer( NAME LANGUAGE KEY ) call in
# CMakeLists.txt, the same lines that create the ripwire_fuzz_<NAME> targets, so a new grammar's fuzzer is swept as soon
# as it is registered (a hand-kept list here once swept 17 of 25). test/g1configcheck.sh compares `--list` with those
# lines. To run fewer, name them, as the third argument or in RIPWIRE_FUZZ_GRAMMARS ("lua proto"); a name with no
# add_ripwire_fuzzer line is refused rather than reported missing.

set -u

ROOT="$( cd "$( dirname "$0" )/../.." && pwd )"

ALL_GRAMMARS="$( sed -n 's/^[[:space:]]*add_ripwire_fuzzer([[:space:]]*\([A-Za-z0-9_]*\)[[:space:]].*/\1/p' "$ROOT/CMakeLists.txt" | tr '\n' ' ' )"
[ -n "${ALL_GRAMMARS// /}" ] || { echo "run.sh: no add_ripwire_fuzzer( NAME ... ) lines in CMakeLists.txt" >&2; exit 2; }

if [ "${1:-}" = "--list" ]; then
    printf '%s\n' $ALL_GRAMMARS
    exit 0
fi

BUILD_DIR="${1:-$ROOT/fuzz}"
DURATION_SEC="${2:-120}"
GRAMMARS="${3:-${RIPWIRE_FUZZ_GRAMMARS:-$ALL_GRAMMARS}}"
JOBS="${RIPWIRE_FUZZ_JOBS:-4}"

for grammar in $GRAMMARS; do
    case " $ALL_GRAMMARS " in
        *" $grammar "*) ;;
        *) echo "run.sh: '$grammar' has no add_ripwire_fuzzer line in CMakeLists.txt (known: $ALL_GRAMMARS)" >&2; exit 2 ;;
    esac
done
[ -n "${GRAMMARS// /}" ] || { echo "run.sh: empty grammar list" >&2; exit 2; }

TMP="$( mktemp -d )"
FAILED=0

if [ "$( uname -s )" = "Darwin" ]; then
    DETECT_LEAKS=0
else
    DETECT_LEAKS=1
fi

case "$BUILD_DIR" in
    /*) ;;
    *) BUILD_DIR="$ROOT/$BUILD_DIR" ;;
esac

cleanup()
{
    if [ "$FAILED" = 0 ]; then
        rm -rf "$TMP"
    else
        printf 'fuzz artifacts and logs preserved at %s\n' "$TMP" >&2
    fi
}
trap cleanup EXIT

mkdir -p "$TMP/artifacts" "$TMP/logs"

run_one()
{
    grammar="$1"
    binary="$BUILD_DIR/ripwire_fuzz_$grammar"
    corpus="$TMP/corpus-$grammar"
    artifacts="$TMP/artifacts/$grammar"
    mkdir -p "$corpus" "$artifacts"

    if [ ! -x "$binary" ]; then
        printf 'missing fuzz target: %s\n' "$binary" >"$TMP/logs/$grammar.log"
        return 2
    fi

    cp "$ROOT/test/fuzz/seeds/common/utf8.txt" "$corpus/utf8"
    cp "$ROOT/test/fuzz/seeds/$grammar/valid" "$corpus/valid"
    : >"$corpus/empty"
    printf '\0' >"$corpus/nul"
    dd if=/dev/zero bs=65536 count=1 2>/dev/null | LC_ALL=C tr '\000' '\377' >"$corpus/ff64k"

    ASAN_OPTIONS="detect_leaks=$DETECT_LEAKS:halt_on_error=1:abort_on_error=1" \
    UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
    LSAN_OPTIONS="suppressions=$ROOT/lsan_suppressions.txt" \
    "$binary" "$corpus" \
        -max_total_time="$DURATION_SEC" -max_len=65536 -timeout=10 -print_final_stats=1 \
        -artifact_prefix="$artifacts/" >"$TMP/logs/$grammar.log" 2>&1
}

PIDS=""
NAMES=""
ACTIVE=0

wait_batch()
{
    oldIFS="$IFS"
    IFS=' '
    set -- $PIDS
    pids="$*"
    set -- $NAMES
    names="$*"
    IFS="$oldIFS"

    index=1
    for pid in $pids; do
        name="$( printf '%s\n' "$names" | cut -d' ' -f"$index" )"
        if wait "$pid"; then
            printf 'PASS  fuzz/%s\n' "$name"
        else
            printf 'FAIL  fuzz/%s (see %s/logs/%s.log)\n' "$name" "$TMP" "$name" >&2
            FAILED=1
        fi
        index=$(( index + 1 ))
    done
    PIDS=""
    NAMES=""
    ACTIVE=0
}

for grammar in $GRAMMARS; do
    run_one "$grammar" &
    PIDS="$PIDS $!"
    NAMES="$NAMES $grammar"
    ACTIVE=$(( ACTIVE + 1 ))
    if [ "$ACTIVE" -ge "$JOBS" ]; then
        wait_batch
    fi
done
[ "$ACTIVE" -eq 0 ] || wait_batch

[ "$FAILED" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$FAILED"
