#!/usr/bin/env bash
# Representative A6 performance LEDGER (retired from threshold-gating to informational-ledger mode by
# owner directive 2026-08-08: "perf budgets are not the model — best tool first, then make it fast"; see
# bench/perfgate.sh's header for the full rationale, which applies here identically). It builds a
# deterministic generated corpus from a hash-pinned fixture and reports the same five-sample measurements
# on every machine — no absolute budget, no pass/fail, no machine-identity branch. The semantic preflights
# (fixture-shape, cache-transparency, blob-header checks) still fail loudly: those catch the harness being
# broken, not the numbers moving.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
RUNS="${RIPWIRE_REP_PERF_RUNS:-5}"
FIXTURE_HASH="08352db35d9c93c4fc7e3af7f38469af8f8b86d1"
PROFILE_MD="$ROOT/bench/PROFILE.md"
PREFLIGHT_ONLY=0
WRITE_LEDGER=1
case "${1:-}" in
    "") ;;
    --preflight-only) PREFLIGHT_ONLY=1 ;;
    --no-ledger)      WRITE_LEDGER=0 ;;
    *) echo "usage: bench/representative_perfgate.sh [--preflight-only|--no-ledger]"; exit 2 ;;
esac
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
# cat|wc -c, not stat: `stat -f %z` is BSD-only — GNU stat errors on it, byteCount summed to 0, and
# this preflight exited 2 on every Linux CI runner (the flavour trap the cache gates document).
byteCount="$( find "$CORPUS" -type f -exec cat {} + | wc -c | tr -d ' ' )"
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
[ -s "$INDEX.lean.ripwirecache" ] && [ -s "$INDEX.rich.ripwirecache" ] || { echo "representative_perfgate: index preflight failed"; exit 1; }
( cd "$CORPUS" && "$BIN" . --quality-baseline --no-cache >/dev/null 2>&1 ) || { echo "representative_perfgate: quality baseline preflight failed"; exit 1; }

richBefore="$( shasum "$INDEX.rich.ripwirecache" | awk '{print $1}' )"
RIPWIRE_CACHE_STATS=1 "$BIN" "$CORPUS" --for=distance --cache="$INDEX.rich.ripwirecache" >"$TMP/retrieval.out" 2>"$TMP/retrieval.err" \
    || { echo "representative_perfgate: retrieval preflight failed"; exit 1; }
richAfter="$( shasum "$INDEX.rich.ripwirecache" | awk '{print $1}' )"
[ "$richBefore" = "$richAfter" ] && grep -q 'cache-stats.*reparsed=0' "$TMP/retrieval.err" \
    || { echo "representative_perfgate: retrieval did not consume the warm rich index unchanged"; cat "$TMP/retrieval.err"; exit 1; }
"$BIN" "$CORPUS" --report --no-cache >"$TMP/report.out" 2>/dev/null || { echo "representative_perfgate: report preflight failed"; exit 1; }
( cd "$CORPUS" && "$BIN" . --quality-delta --no-cache >"$TMP/quality.out" 2>/dev/null ) \
    || { echo "representative_perfgate: quality-delta preflight failed"; exit 1; }
"$BIN" "$CORPUS" --dead-code --no-cache >"$TMP/dead.out" 2>/dev/null || { echo "representative_perfgate: dead-code preflight failed"; exit 1; }
[ -s "$TMP/retrieval.out" ] && grep -q '^# ripwire architecture report' "$TMP/report.out" \
    && grep -q 'quality-delta' "$TMP/quality.out" && grep -q 'dead-code' "$TMP/dead.out" \
    || { echo "representative_perfgate: semantic preflight failed"; exit 1; }

if [ "$PREFLIGHT_ONLY" -eq 1 ]; then
    echo "representative_perfgate: all semantic preflights passed."
    exit 0
fi

coldMs="$( median_ms "$BIN" "$CORPUS" --no-cache )" || exit 1
retrievalMs="$( median_ms "$BIN" "$CORPUS" --for=distance --cache="$INDEX.rich.ripwirecache" )" || exit 1
reportMs="$( median_ms "$BIN" "$CORPUS" --report --no-cache )" || exit 1
qualityMs="$( median_ms sh -c 'cd "$1" && "$2" . --quality-delta --no-cache' sh "$CORPUS" "$BIN" )" || exit 1
deadMs="$( median_ms "$BIN" "$CORPUS" --dead-code --no-cache )" || exit 1
mcpMs="$( python3 "$ROOT/bench/mcp_session_timing.py" "$BIN" "$CORPUS" "$RUNS" )" || exit 1

printf 'representative_perfgate: machine=%s/%s fixture=%s copies=80 files=%s bytes=%s runs=%s\n' \
       "$( uname -s )" "$( uname -m )" "$FIXTURE_HASH" "$fileCount" "$byteCount" "$RUNS"
printf '  cold=%8.3f ms  warm-index-retrieval=%8.3f  report=%8.3f  quality-delta=%8.3f  dead-code=%8.3f  mcp=%8.3f\n' \
       "$coldMs" "$retrievalMs" "$reportMs" "$qualityMs" "$deadMs" "$mcpMs"

# ledger mode (owner directive 2026-08-08): report the machine for context, but no budget comparison and
# no machine-identity branch — every machine gets the same measurement-only treatment now.
machineId="$( system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Identifier/{print $2; exit}' )"
printf '  machine_id=%s policy=ledger (no pass/fail — owner directive 2026-08-08)\n' "${machineId:-unknown}"

if [ "$WRITE_LEDGER" -eq 1 ]; then
    {
        printf '\n## %s — representative_perfgate ledger\n\n' "$( date -u '+%Y-%m-%d' )"
        printf 'Ledger-mode measurement (owner directive 2026-08-08: perf budgets are not the model — best\n'
        printf 'tool first, then make it fast; no pass/fail — see bench/representative_perfgate.sh header).\n'
        printf 'machine=%s/%s (%s) fixture=%s copies=80 files=%s bytes=%s runs=%s generated=%s\n\n' \
               "$( uname -s )" "$( uname -m )" "${machineId:-unknown}" "$FIXTURE_HASH" "$fileCount" "$byteCount" "$RUNS" "$( date -u '+%Y-%m-%d %H:%M UTC' )"
        printf '| key | median (ms) |\n|---|---:|\n'
        printf '| cold | %.3f |\n' "$coldMs"
        printf '| warm-index-retrieval | %.3f |\n' "$retrievalMs"
        printf '| report | %.3f |\n' "$reportMs"
        printf '| quality-delta | %.3f |\n' "$qualityMs"
        printf '| dead-code | %.3f |\n' "$deadMs"
        printf '| mcp-warm-request | %.3f |\n' "$mcpMs"
    } >> "$PROFILE_MD"
    echo "representative_perfgate: appended ledger entry to $PROFILE_MD"
fi
echo "representative_perfgate: measurement complete."
exit 0
