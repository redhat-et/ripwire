#!/usr/bin/env bash
# Bounded full fuzz sweep. Not part of normal regression; invoke explicitly from the G1/release gate.

set -u

ROOT="$( cd "$( dirname "$0" )/../.." && pwd )"
BUILD_DIR="${1:-$ROOT/fuzz}"
DURATION_SEC="${2:-120}"
JOBS="${CTXPACK_FUZZ_JOBS:-4}"
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

GRAMMARS="cpp python go rust typescript tsx swift objc javascript bash java ruby json"
mkdir -p "$TMP/artifacts" "$TMP/logs"

run_one()
{
    grammar="$1"
    binary="$BUILD_DIR/ctxpack_fuzz_$grammar"
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
