#!/usr/bin/env bash
# perfgate.sh — the perf LEDGER (Wave 2 #8 originally "make the perf story self-guarding"; retired from
# threshold-gating to informational-ledger mode by owner directive 2026-08-08: "perf budgets are NOT the
# model — best tool first, then make it fast"; measurement stays a ledger, never red CI).
#
# Builds NOTHING. Times a selected corpus (default: this repo's own root — src/ + third_party/ +
# everything else the denylist keeps, checked into git — stable unless someone adds/removes a lot
# of files) cold (--no-cache) and warm (--cache) with RIPWIRE_BIN, takes the MEDIAN of 5 runs each via a
# high-resolution timer, prints the table, and appends a dated entry to bench/PROFILE.md. It does NOT
# compare the medians against any budget and it does NOT fail because a number moved — corpus growth,
# machine variance and deliberate feature additions all move these numbers for reasons that have nothing
# to do with a regression, and a red gate that fires on all three trains everyone to ignore it. Read the
# ledger; a human (or a future automated trend check over PROFILE.md's history) decides what a moving
# number means.
#
# What this script STILL fails loudly on: the binary is missing, a timed command itself crashes or hangs,
# or a semantic preflight shows the tool produced garbage (no core map, cache not transparent, degrade
# note absent, ...). Those are correctness bugs, not perf drift, and retiring the budget comparison does
# not mean retiring the harness's ability to notice its own tool is broken.
#
# NOT wired into test/regression.sh as a full run (perf gates flake in CI: shared runners, thermal
# throttling, noisy neighbors) — this is an ON-DEMAND + PRE-RELEASE measurement, run by a human (or a
# release script) on a quiet machine, not on every push. test/perfharnesscheck.sh DOES run this script's
# --preflight-only mode under test/regression.sh, to prove the harness itself still works.
#
# bench/perf_budgets.txt is kept as a HISTORICAL reference (the last budgets this script ever enforced,
# and the rationale for the 1.5x headroom convention) — it is no longer read by this script. See its own
# header.
#
# Usage:
#   bench/perfgate.sh                          # uses ./build/ripwire
#   RIPWIRE_BIN=build_prof/ripwire bench/perfgate.sh
#   RIPWIRE_PERF_CORPUS=../your-large-cpp-corpus RIPWIRE_PERF_LABEL=cpp bench/perfgate.sh
#   RIPWIRE_PERF_NAV_ARG=--deps RIPWIRE_PERF_NAV_KEY=deps_cpp RIPWIRE_PERF_LABEL=cpp bench/perfgate.sh
#   bench/perfgate.sh --preflight-only          # semantic harness checks only; no timing/ledger entry
#   bench/perfgate.sh --no-ledger               # measure + print the table, skip the bench/PROFILE.md
#                                                # append (for a throwaway A/B, e.g. via RIPWIRE_BIN=)
#
# Exit codes: 0 = measurement completed (this is now the ONLY outcome once the binary runs cleanly — a
# slow median is a data point, not a failure). 1 = a timed command crashed or a semantic preflight failed
# (the harness itself is broken). 2 = usage / missing binary error.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"     # allow a repo-relative RIPWIRE_BIN
CORPUS="${RIPWIRE_PERF_CORPUS:-$ROOT}"
[ "${CORPUS#/}" = "$CORPUS" ] && CORPUS="$ROOT/$CORPUS"     # allow a repo-relative RIPWIRE_PERF_CORPUS
LABEL="${RIPWIRE_PERF_LABEL:-}"
case "$LABEL" in
    *[!A-Za-z0-9_]*)
        echo "perfgate: RIPWIRE_PERF_LABEL may contain only A-Z, a-z, 0-9, and _"
        exit 2
        ;;
esac
KEY_COLD="cold"
KEY_WARM="warm"
if [ -n "$LABEL" ]; then
    KEY_COLD="cold_$LABEL"
    KEY_WARM="warm_$LABEL"
fi
NAV_ARG="${RIPWIRE_PERF_NAV_ARG:-}"
NAV_KEY="${RIPWIRE_PERF_NAV_KEY:-}"
if [ "$LABEL" = "cpp" ] && [ -z "$NAV_ARG" ] && [ -z "$NAV_KEY" ]; then
    NAV_ARG="--deps"
    NAV_KEY="deps_cpp"
fi
if [ -n "$NAV_ARG" ] && [ -z "$NAV_KEY" ]; then
    NAV_KEY="nav_${LABEL:-default}"
fi
case "$NAV_KEY" in
    *[!A-Za-z0-9_]*)
        echo "perfgate: RIPWIRE_PERF_NAV_KEY may contain only A-Z, a-z, 0-9, and _"
        exit 2
        ;;
esac
PROFILE_MD="$ROOT/bench/PROFILE.md"
RUNS=5
PREFLIGHT_ONLY=0
WRITE_LEDGER=1
case "${1:-}" in
    "") ;;
    --preflight-only) PREFLIGHT_ONLY=1 ;;
    --no-ledger)      WRITE_LEDGER=0 ;;
    *) echo "usage: bench/perfgate.sh [--preflight-only|--no-ledger]"; exit 2 ;;
esac

[ -x "$BIN" ] || { echo "perfgate: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

# ---- selected corpus.
# ripwire takes exactly ONE positional <dir>, so the default points at $ROOT itself rather than passing
# src/ and third_party/ as two args (not supported) — same effective corpus (stable-ish size, checked
# into git), single invocation. RIPWIRE_PERF_CORPUS can override this for C++-heavy trees. ----
[ -d "$CORPUS" ] || { echo "perfgate: corpus dir missing: $CORPUS"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# median_ms CMD... — runs CMD $RUNS times with a monotonic high-resolution timer, rejects any non-zero
# command status, and prints the median wall time in ms. The old /usr/bin/time parser silently accepted a
# failed command and rounded fast workloads to 10 ms buckets, making both failure and small regressions easy
# to miss.
median_ms()
{
    local times=()
    local i
    for (( i = 0; i < RUNS; ++i )); do
        local elapsed
        elapsed="$( perl -MTime::HiRes=time -e '
            open STDOUT, ">", "/dev/null" or die $!;
            open STDERR, ">", "/dev/null" or die $!;
            my $start = time();
            system @ARGV;
            my $status = $?;
            my $elapsed = (time() - $start) * 1000.0;
            open STDOUT, ">&", 3 or die $!;
            printf "%.6f\n", $elapsed;
            exit($status == -1 ? 127 : ($status >> 8));
        ' 3>&1 -- "$@" )" || { echo "perfgate: FAILED timed command: $*" >&2; return 1; }
        [ -z "$elapsed" ] && { echo "perfgate: timer produced no sample: $*" >&2; return 1; }
        times+=( "$elapsed" )
    done
    printf '%s\n' "${times[@]}" | sort -n | awk -v n="$RUNS" '{ a[NR]=$1 } END { mid=int((n+1)/2); if (n%2==1) print a[mid]; else print (a[mid]+a[mid+1])/2 }'
}

# ---- keys measured: cold (--no-cache) and warm (--cache=<sidecar>, primed then re-measured) ----
echo "perfgate: BIN=$BIN  corpus=$CORPUS  label=${LABEL:-default}  runs=$RUNS (median)"
echo ""

# NOTE: plain vars, not an associative array — macOS ships bash 3.2 (no `declare -A`) and this script
# must run with the system /bin/bash, not require homebrew bash.
echo "-- cold (--no-cache) --"
"$BIN" "$CORPUS" --no-cache > "$TMP/cold.preflight" 2>"$TMP/cold.preflight.err" \
    || { echo "perfgate: cold semantic preflight failed"; cat "$TMP/cold.preflight.err"; exit 1; }
grep -Eq '<r([ >])' "$TMP/cold.preflight" || { echo "perfgate: cold preflight did not emit the core map"; exit 1; }
cold_ms=""
if [ "$PREFLIGHT_ONLY" -eq 0 ]; then
    cold_ms="$( median_ms "$BIN" "$CORPUS" --no-cache )" || exit 1
    printf '  %-24s %8.1f ms\n' "cold" "$cold_ms"
fi

echo "-- warm (--cache=<sidecar>, primed) --"
CACHE_FILE="$TMP/perfgate_cache.bin"
"$BIN" "$CORPUS" --cache="$CACHE_FILE" >"$TMP/prime.out" 2>"$TMP/prime.err" \
    || { echo "perfgate: warm-cache prime failed"; cat "$TMP/prime.err"; exit 1; }
[ -s "$CACHE_FILE" ] && diff -q "$TMP/cold.preflight" "$TMP/prime.out" >/dev/null \
    || { echo "perfgate: warm-cache prime failed semantic/cache-transparency preflight"; exit 1; }
warm_ms=""
if [ "$PREFLIGHT_ONLY" -eq 0 ]; then
    warm_ms="$( median_ms "$BIN" "$CORPUS" --cache="$CACHE_FILE" )" || exit 1
    printf '  %-24s %8.1f ms\n' "warm" "$warm_ms"
fi
nav_ms=""
if [ -n "$NAV_ARG" ]; then
    echo "-- navigation ($NAV_ARG, warm cache) --"
    "$BIN" "$CORPUS" "$NAV_ARG" --cache="$CACHE_FILE" >"$TMP/nav.preflight" 2>"$TMP/nav.preflight.err" \
        || { echo "perfgate: navigation semantic preflight failed"; cat "$TMP/nav.preflight.err"; exit 1; }
    [ -s "$TMP/nav.preflight" ] || { echo "perfgate: navigation preflight emitted no result"; exit 1; }
    if [ "$PREFLIGHT_ONLY" -eq 0 ]; then
        nav_ms="$( median_ms "$BIN" "$CORPUS" "$NAV_ARG" --cache="$CACHE_FILE" )" || exit 1
        printf '  %-24s %8.1f ms\n' "$NAV_KEY" "$nav_ms"
    fi
fi
echo ""

if [ "$PREFLIGHT_ONLY" -eq 1 ]; then
    echo "perfgate: all semantic preflights passed."
    exit 0
fi

# ---- ledger mode (owner directive 2026-08-08): print a recap table, append a dated bench/PROFILE.md
# entry, exit 0 unconditionally. No budget file is read or written — bench/perf_budgets.txt is retired
# to a historical reference (see its own header) and --write-budgets no longer exists.
echo "-- measured (ledger, no pass/fail) --"
printf '  %-24s %8.1f ms\n' "$KEY_COLD" "$cold_ms"
printf '  %-24s %8.1f ms\n' "$KEY_WARM" "$warm_ms"
[ -n "$NAV_ARG" ] && printf '  %-24s %8.1f ms\n' "$NAV_KEY" "$nav_ms"
echo ""

if [ "$WRITE_LEDGER" -eq 1 ]; then
    {
        printf '\n## %s — perfgate ledger: label=%s\n\n' "$( date -u '+%Y-%m-%d' )" "${LABEL:-default}"
        printf 'Ledger-mode measurement (owner directive 2026-08-08: perf budgets are not the model — best\n'
        printf 'tool first, then make it fast; no pass/fail — see bench/perfgate.sh header). BIN=%s\n' "$BIN"
        printf 'corpus=%s runs=%s (median) machine=%s generated=%s\n\n' "$CORPUS" "$RUNS" "$( uname -sm )" "$( date -u '+%Y-%m-%d %H:%M UTC' )"
        printf '| key | median (ms) |\n|---|---:|\n'
        printf '| %s | %.1f |\n' "$KEY_COLD" "$cold_ms"
        printf '| %s | %.1f |\n' "$KEY_WARM" "$warm_ms"
        [ -n "$NAV_ARG" ] && printf '| %s | %.1f |\n' "$NAV_KEY" "$nav_ms"
    } >> "$PROFILE_MD"
    echo "perfgate: appended ledger entry to $PROFILE_MD"
fi
echo "perfgate: measurement complete."
exit 0
