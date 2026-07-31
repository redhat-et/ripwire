#!/usr/bin/env bash
# perfgate.sh — the drift alarm (Wave 2 #8: "make the perf story self-guarding").
#
# Builds NOTHING. Times a selected corpus (default: this repo's own root — src/ + third_party/ +
# everything else the denylist keeps, checked into git — stable unless someone adds/removes a lot
# of files) cold (--no-cache) and warm (--cache) with RIPWIRE_BIN,
# takes the MEDIAN of 5 runs each via /usr/bin/time, and compares against budgets recorded in
# bench/perf_budgets.txt. Exits 1 with a loud message the moment a median exceeds its budget — that's
# the whole point: a silent regression (someone adds an O(n^2) loop, a rehash cascade, an accidental
# un-cached re-parse) shows up as a hard failure instead of a shrug next time someone eyeballs PROFILE.md.
#
# NOT wired into test/regression.sh. Perf gates flake in CI (shared runners, thermal throttling, noisy
# neighbors) — this is an ON-DEMAND + PRE-RELEASE gate, run by a human (or a release script) on a quiet
# machine, not on every push. Budgets carry 1.5x headroom over a measured baseline for exactly this
# reason (see bench/perf_budgets.txt header for the rationale).
#
# Usage:
#   bench/perfgate.sh                          # uses ./build/ripwire
#   RIPWIRE_BIN=build_prof/ripwire bench/perfgate.sh
#   RIPWIRE_PERF_CORPUS=../your-large-cpp-corpus RIPWIRE_PERF_LABEL=cpp bench/perfgate.sh
#   RIPWIRE_PERF_NAV_ARG=--deps RIPWIRE_PERF_NAV_KEY=deps_cpp RIPWIRE_PERF_LABEL=cpp bench/perfgate.sh
#   bench/perfgate.sh --write-budgets           # (re)generate perf_budgets.txt from THIS machine's
#                                                # measured medians x 1.5 — use when you've made a
#                                                # deliberate, verified perf change and want a new floor.
#
# Exit codes: 0 = all medians within budget. 1 = at least one median exceeded its budget (or a run
# failed). 2 = usage / missing binary error.

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
BUDGETS="$ROOT/bench/perf_budgets.txt"
RUNS=5
WRITE_BUDGETS=0
[ "${1:-}" = "--write-budgets" ] && WRITE_BUDGETS=1

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
grep -q '<r>' "$TMP/cold.preflight" || { echo "perfgate: cold preflight did not emit the core map"; exit 1; }
cold_ms="$( median_ms "$BIN" "$CORPUS" --no-cache )" || exit 1
printf '  %-24s %8.1f ms\n' "cold" "$cold_ms"

echo "-- warm (--cache=<sidecar>, primed) --"
CACHE_FILE="$TMP/perfgate_cache.bin"
"$BIN" "$CORPUS" --cache="$CACHE_FILE" >"$TMP/prime.out" 2>"$TMP/prime.err" \
    || { echo "perfgate: warm-cache prime failed"; cat "$TMP/prime.err"; exit 1; }
[ -s "$CACHE_FILE" ] && diff -q "$TMP/cold.preflight" "$TMP/prime.out" >/dev/null \
    || { echo "perfgate: warm-cache prime failed semantic/cache-transparency preflight"; exit 1; }
warm_ms="$( median_ms "$BIN" "$CORPUS" --cache="$CACHE_FILE" )" || exit 1
printf '  %-24s %8.1f ms\n' "warm" "$warm_ms"
nav_ms=""
if [ -n "$NAV_ARG" ]; then
    echo "-- navigation ($NAV_ARG, warm cache) --"
    "$BIN" "$CORPUS" "$NAV_ARG" --cache="$CACHE_FILE" >"$TMP/nav.preflight" 2>"$TMP/nav.preflight.err" \
        || { echo "perfgate: navigation semantic preflight failed"; cat "$TMP/nav.preflight.err"; exit 1; }
    [ -s "$TMP/nav.preflight" ] || { echo "perfgate: navigation preflight emitted no result"; exit 1; }
    nav_ms="$( median_ms "$BIN" "$CORPUS" "$NAV_ARG" --cache="$CACHE_FILE" )" || exit 1
    printf '  %-24s %8.1f ms\n' "$NAV_KEY" "$nav_ms"
fi
echo ""

# key_to_ms KEY — looks up the measured median for a budget key by name (bash-3.2-safe: no assoc arrays)
key_to_ms()
{
    case "$1" in
        "$KEY_COLD") echo "$cold_ms" ;;
        "$KEY_WARM") echo "$warm_ms" ;;
        "$NAV_KEY") echo "$nav_ms" ;;
        *) echo "" ;;
    esac
}

# ---- write-budgets mode: regenerate perf_budgets.txt from these medians x 1.5, then exit ----
if [ "$WRITE_BUDGETS" -eq 1 ]; then
    {
        echo "# perf_budgets.txt — perfgate.sh budgets (Wave 2 #8: the drift alarm)"
        echo "#"
        echo "# format: <key> <max_ms>   (one per line; # comments and blank lines ignored)"
        echo "#"
        echo "# Rationale: each budget = measured median x 1.5 on the machine/date below. The 1.5x"
        echo "# headroom absorbs normal machine variance (thermal throttling, background load, P/E core"
        echo "# scheduling jitter) WITHOUT masking a real regression — a genuine perf bug is rarely a 10-20%"
        echo "# wobble, it's a missing cache hit or an added O(n^2) pass, which blows well past 1.5x."
        echo "# Regenerate one label with: bench/perfgate.sh --write-budgets   (only after a DELIBERATE,"
        echo "# verified perf change — don't silently ratchet budgets up to make a regression disappear)."
        echo "#"
        echo "# updated label: ${LABEL:-default}"
        echo "# updated corpus: $CORPUS"
        echo "# generated: $( date -u '+%Y-%m-%d %H:%M UTC' )  machine: $( uname -sm )"
        echo "#"
        if [ -f "$BUDGETS" ]; then
            awk -v cold="$KEY_COLD" -v warm="$KEY_WARM" -v nav="$NAV_KEY" 'NF && $1 !~ /^#/ && $1 != cold && $1 != warm && (nav == "" || $1 != nav) { print }' "$BUDGETS"
        fi
        printf '%s %.0f\n' "$KEY_COLD" "$( awk -v v="$cold_ms" 'BEGIN{print v*1.5}' )"
        printf '%s %.0f\n' "$KEY_WARM" "$( awk -v v="$warm_ms" 'BEGIN{print v*1.5}' )"
        if [ -n "$NAV_ARG" ]; then
            printf '%s %.0f\n' "$NAV_KEY" "$( awk -v v="$nav_ms" 'BEGIN{print v*1.5}' )"
        fi
    } > "$TMP/perf_budgets.txt"
    mv "$TMP/perf_budgets.txt" "$BUDGETS"
    echo "perfgate: wrote $BUDGETS"
    exit 0
fi

# ---- compare against recorded budgets ----
[ -f "$BUDGETS" ] || { echo "perfgate: no budgets file at $BUDGETS — run 'bench/perfgate.sh --write-budgets' once to seed it"; exit 2; }

fail=0
matchCount=0
while read -r key max_ms; do
    [ -z "${key:-}" ] && continue
    case "$key" in \#*) continue ;; esac
    m="$( key_to_ms "$key" )"
    [ -z "$m" ] && continue
    matchCount=$(( matchCount + 1 ))
    over="$( awk -v m="$m" -v b="$max_ms" 'BEGIN{ print (m > b) ? 1 : 0 }' )"
    if [ "$over" -eq 1 ]; then
        printf '  FAIL  %-6s %8.1f ms  >  budget %s ms\n' "$key" "$m" "$max_ms"
        fail=1
    else
        printf '  PASS  %-6s %8.1f ms  <=  budget %s ms\n' "$key" "$m" "$max_ms"
    fi
done < "$BUDGETS"

echo ""
if [ "$matchCount" -eq 0 ]; then
    echo "perfgate: no matching budgets for label '${LABEL:-default}' in $BUDGETS"
    echo "perfgate: run with --write-budgets for this label, or choose an existing RIPWIRE_PERF_LABEL."
    exit 2
fi
if [ "$fail" -eq 1 ]; then
    echo "*** PERFGATE FAILED — a median exceeded its budget. This is the drift alarm firing: a hot"
    echo "*** path likely regressed (rehash cascade, dropped cache hit, new O(n^2) pass, ...). Profile"
    echo "*** with -DRIPWIRE_PROFILE=ON (see bench/PROFILE.md) before assuming it's just machine noise."
    exit 1
fi
echo "perfgate: all medians within budget."
exit 0
