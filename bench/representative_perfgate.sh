#!/usr/bin/env bash
# Representative A6 performance drift gate. It builds a deterministic generated corpus from a hash-pinned
# fixture and applies absolute budgets only on the recorded canonical machine. Other machines report the
# same five-sample measurements without pass/fail; no shared regression is normalized away by another path.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
RUNS="${CTXPACK_REP_PERF_RUNS:-5}"
FIXTURE_HASH="a22b4425ff9750e75d35fb510443a65f54c3cc0c"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUS="$TMP/corpus"

[ -x "$BIN" ] || { echo "representative_perfgate: missing binary: $BIN"; exit 2; }
case "$RUNS" in *[!0-9]*|'') echo "representative_perfgate: RUNS must be numeric"; exit 2;; esac
[ "$RUNS" -ge 5 ] || { echo "representative_perfgate: RUNS must be at least 5"; exit 2; }

actualHash="$( cd "$ROOT/test/fixture" && find . -type f -print0 | sort -z | xargs -0 shasum | shasum | awk '{print $1}' )"
[ "$actualHash" = "$FIXTURE_HASH" ] || {
    echo "representative_perfgate: fixture drifted ($actualHash != $FIXTURE_HASH); review shape and update the pin"
    exit 2
}

mkdir -p "$CORPUS"
copyIndex=0
while [ "$copyIndex" -lt 80 ]; do
    cp -R "$ROOT/test/fixture" "$CORPUS/unit_$copyIndex"
    copyIndex=$(( copyIndex + 1 ))
done
fileCount="$( find "$CORPUS" -type f | wc -l | tr -d ' ' )"
byteCount="$( find "$CORPUS" -type f -exec stat -f %z {} \; | awk '{s+=$1} END{print s+0}' )"
[ "$fileCount" = 480 ] || { echo "representative_perfgate: corpus shape mismatch: files=$fileCount"; exit 2; }
[ "$byteCount" = 183040 ] || { echo "representative_perfgate: corpus shape mismatch: bytes=$byteCount"; exit 2; }
"$BIN" "$CORPUS" --no-cache > "$TMP/default.out" 2>/dev/null || { echo "representative_perfgate: default preflight failed"; exit 1; }
grep -q 'files=480 symbols=1120 edges=320 ' "$TMP/default.out" \
    || { echo "representative_perfgate: semantic corpus shape drifted (expected files=480 symbols=1120 edges=320)"; exit 2; }

timer()
{
    perl -MTime::HiRes=time -e '
        open STDOUT, ">", "/dev/null" or die $!;
        open STDERR, ">", "/dev/null" or die $!;
        my $start = time();
        system @ARGV;
        my $status = $?;
        my $elapsed = (time() - $start) * 1000.0;
        open STDOUT, ">&", 3 or die $!;
        printf "%.6f\n", $elapsed;
        exit($status == -1 ? 127 : ($status >> 8));
    ' 3>&1 -- "$@"
}

median_ms()
{
    local samples="$TMP/samples"
    : > "$samples"
    local sampleIndex=0
    while [ "$sampleIndex" -lt "$RUNS" ]; do
        timer "$@" >> "$samples" || { echo "representative_perfgate: timed command failed: $*" >&2; return 1; }
        sampleIndex=$(( sampleIndex + 1 ))
    done
    sort -n "$samples" | awk -v n="$RUNS" 'NR==int((n+1)/2){print; exit}'
}

INDEX="$TMP/index"
"$BIN" "$CORPUS" --index-out="$INDEX" >/dev/null 2>"$TMP/index.err" || { cat "$TMP/index.err"; exit 1; }
[ -s "$INDEX.lean.ctxpackcache" ] && [ -s "$INDEX.rich.ctxpackcache" ] || { echo "representative_perfgate: index preflight failed"; exit 1; }
( cd "$CORPUS" && "$BIN" . --quality-baseline --no-cache >/dev/null 2>&1 ) || { echo "representative_perfgate: quality baseline preflight failed"; exit 1; }

richBefore="$( shasum "$INDEX.rich.ctxpackcache" | awk '{print $1}' )"
CTXPACK_CACHE_STATS=1 "$BIN" "$CORPUS" --for=distance --cache="$INDEX.rich.ctxpackcache" >"$TMP/retrieval.out" 2>"$TMP/retrieval.err" \
    || { echo "representative_perfgate: retrieval preflight failed"; exit 1; }
richAfter="$( shasum "$INDEX.rich.ctxpackcache" | awk '{print $1}' )"
[ "$richBefore" = "$richAfter" ] && grep -q 'cache-stats.*reparsed=0' "$TMP/retrieval.err" \
    || { echo "representative_perfgate: retrieval did not consume the warm rich index unchanged"; cat "$TMP/retrieval.err"; exit 1; }
"$BIN" "$CORPUS" --report --no-cache >"$TMP/report.out" 2>/dev/null || { echo "representative_perfgate: report preflight failed"; exit 1; }
( cd "$CORPUS" && "$BIN" . --quality-delta --no-cache >"$TMP/quality.out" 2>/dev/null ) \
    || { echo "representative_perfgate: quality-delta preflight failed"; exit 1; }
"$BIN" "$CORPUS" --dead-code --no-cache >"$TMP/dead.out" 2>/dev/null || { echo "representative_perfgate: dead-code preflight failed"; exit 1; }
[ -s "$TMP/retrieval.out" ] && grep -q '^# ctxpack architecture report' "$TMP/report.out" \
    && grep -q 'quality-delta' "$TMP/quality.out" && grep -q 'dead-code' "$TMP/dead.out" \
    || { echo "representative_perfgate: semantic preflight failed"; exit 1; }

coldMs="$( median_ms "$BIN" "$CORPUS" --no-cache )" || exit 1
retrievalMs="$( median_ms "$BIN" "$CORPUS" --for=distance --cache="$INDEX.rich.ctxpackcache" )" || exit 1
reportMs="$( median_ms "$BIN" "$CORPUS" --report --no-cache )" || exit 1
qualityMs="$( median_ms sh -c 'cd "$1" && "$2" . --quality-delta --no-cache' sh "$CORPUS" "$BIN" )" || exit 1
deadMs="$( median_ms "$BIN" "$CORPUS" --dead-code --no-cache )" || exit 1
mcpMs="$( python3 "$ROOT/bench/mcp_session_timing.py" "$BIN" "$CORPUS" "$RUNS" )" || exit 1

printf 'representative_perfgate: machine=%s/%s fixture=%s copies=80 files=%s bytes=%s runs=%s\n' \
       "$( uname -s )" "$( uname -m )" "$FIXTURE_HASH" "$fileCount" "$byteCount" "$RUNS"
printf '  cold=%8.3f ms  warm-index-retrieval=%8.3f  report=%8.3f  quality-delta=%8.3f  dead-code=%8.3f  mcp=%8.3f\n' \
       "$coldMs" "$retrievalMs" "$reportMs" "$qualityMs" "$deadMs" "$mcpMs"

machineId="$( system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Identifier/{print $2; exit}' )"
canonicalMachine="Mac17,8"
printf '  machine_id=%s canonical_budget_machine=%s policy=absolute-on-match-report-only-otherwise\n' "${machineId:-unknown}" "$canonicalMachine"
if [ "$machineId" != "$canonicalMachine" ]; then
    echo "representative_perfgate: measurements only; absolute budgets apply only to $canonicalMachine"
    exit 0
fi

fail=0
check_absolute()
{
    local name="$1" measured="$2" budget="$3"
    if awk -v measured="$measured" -v budget="$budget" 'BEGIN{exit !(measured<=budget)}'; then
        printf '  PASS  %-22s %8.3f <= %8.3f ms absolute\n' "$name" "$measured" "$budget"
    else
        printf '  FAIL  %-22s %8.3f >  %8.3f ms absolute\n' "$name" "$measured" "$budget"
        fail=1
    fi
}

check_absolute cold                 "$coldMs"      100
check_absolute warm-index-retrieval "$retrievalMs"  30
check_absolute report               "$reportMs"    100
check_absolute quality-delta        "$qualityMs"   220
check_absolute dead-code            "$deadMs"      100
check_absolute mcp-warm-request      "$mcpMs"        80
exit "$fail"
