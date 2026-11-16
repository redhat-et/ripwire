#!/usr/bin/env bash
# traceasanlinearcheck.sh — --from-trace's ASan frame parser (src/tracein.h detail::parseAsan) is LINEAR
# in the trace text's size, not quadratic.
#
# THE DEFECT. parseAsan finds the source location on an ASan/UBSan frame line (`#0 0x.. in FUNC
# path:line:col`) by trying the LAST space-separated token first, then the last two, then the last
# three, … — because a demangled C++ function name can itself contain spaces
# (`rw::alpha(int const&)`), so the split cannot just be the first space. The original implementation
# re-derived the whole candidate on every widening try (rfind(':')/rfind(' ')/looksLikePath over a
# substring that only grows), which redoes the SAME work at every step: O(k^2) in the space-separated
# word count k. A line built from thousands of short, non-path-shaped "words" with no valid trailing
# location anywhere (the pattern a fuzzer, a minified diagnostic dump, or a pasted non-stack-trace blob
# produces) turned 160 KB of trace text into ~4 s of one --from-trace call.
#
# THE FIX. Every quantity the naive rescan recomputed is actually INVARIANT once the growing window
# first reaches it (a colon's position never moves; "does this stretch contain '.'/'/'" can only flip
# false->true as the window grows left, never back), so parseAsan now computes each ONCE and walks word
# boundaries in a single backward pass — O(after.size()) total, not O(words^2) — landing on the exact
# same candidate the original per-word rescan would have found first.
#
# Arms:
#   (A) CORRECTNESS — a real multi-word demangled frame (`rw::alpha(int const&) src/mod.cpp:8:1`, the
#       same shape test/tracecheck.sh's (A2a) fixture uses) still extracts path=src/mod.cpp, line=8 and
#       the whole func string, not a naive first-space split.
#   (B) NEAR-LINEAR TIMING — a PATHOLOGICAL line (many thousands of short, non-path-shaped words, one
#       lone path character planted in the very FIRST word so every candidate up to the last is tried
#       and fails, ending in a real `:digits` so the trailing-digit check alone cannot short-circuit) at
#       roughly 40 KB / 160 KB / 640 KB / 2.5 MB: each ~4x size step must cost roughly a ~4x time step,
#       not the ~16x a real O(k^2) would show. Generous slack (8x) keeps this off CI noise while still
#       catching a genuine quadratic regression, which blows the ratio by 100x+ at the top end. Each size
#       is timed 5 times, round-robin, and the ratios compare MEDIANS (#352: one stalled sample failed B1).
#   (C) REGRESSION — an ordinary single-space ASan frame (test/tracecheck.sh's own fixture) still parses.
#
# MUTATION CONTROL: arm B is exactly what a revert to the per-candidate rescan trips — arm A and C still
# pass (the algorithm is a rewrite, not a capability change), only the TIMING ratio in B goes red. Run
# against a pre-fix binary — RIPWIRE_BIN=<base>/ripwire bash test/traceasanlinearcheck.sh — arm B must FAIL.
# Re-proven for the median form (#352): a per-word `after.substr( start ).find_first_of( "./" )` rescan planted in
# scanAsanWordBoundaries measured medians 132 / 1033 / 14094 ms / timeout (40 KB / 160 KB / 640 KB / 2.5 MB) and failed B1, B2 and B3.
#
# B3 is RELATIVE (62.5x the run's own 160 KB median; see the comment at B3) so a loaded host cannot flake it; B4 proves the
# rule on fixed numbers. B3_INJECT_PCT=1200 (test-only) scales the measured 2.5 MB median to simulate the quadratic case.
#
# Usage:  bash test/traceasanlinearcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/traceasanlinearcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "traceasanlinearcheck: python3 required"; exit 2; }
echo "traceasanlinearcheck: BIN=$BIN"

# ===================================================================================================
# (P) THE RUNNER — arm B times every run through test/lib/caprun.py, never timeout(1). Stock macOS ships no
# timeout(1), and `timeout 20 …` then answered 127 in about a millisecond: arm B read that as a 1 ms TIMING SAMPLE for
# all four sizes and passed without parsing a single trace (CodeRabbit on #277). The runner is proven on this host
# first: it passes an exit status through, enforces its cap, and reports a command it cannot start as EXECFAIL.
# ===================================================================================================
echo "-- (P) the capped runner works on this host"
CAPRUN="$ROOT/test/lib/caprun.py"
capRun(){ python3 "$CAPRUN" "$@" 2>&1 | tail -1; }   # capRun SECONDS [opts] -- CMD… -> "rc=N ms=M" | "TIMEOUT ms=M" | "EXECFAIL …"
if [ ! -f "$CAPRUN" ]; then
    no "P0: the runner test/lib/caprun.py is missing — arm B cannot time anything"
else
    P1="$( capRun 5 -- sh -c 'exit 3' )"; P2="$( capRun 1 -- sleep 5 )"; P3="$( capRun 5 -- "$TMP/no-such-binary" )"
    case "$P1" in "rc=3 "*) ok "P1: an exit status passes through the runner ($P1)" ;; *) no "P1: the runner did not report rc=3: $P1" ;; esac
    case "$P2" in "TIMEOUT "*) ok "P2: the runner enforces its cap ($P2)" ;; *) no "P2: the runner did not time out a 5 s sleep under a 1 s cap: $P2" ;; esac
    case "$P3" in "EXECFAIL "*) ok "P3: a command that cannot start is EXECFAIL, never a timing" ;; *) no "P3: a missing command was not reported as EXECFAIL: $P3" ;; esac
fi

mkdir -p "$TMP/corpus"
run_trace(){ # $1 = trace file NAME, written under $TMP (an absolute --from-trace path, so this never
             # depends on the corpus cwd the way a relative one silently would if the fixture and the
             # corpus root ever drift apart)
    ( cd "$TMP/corpus" && "$BIN" . --from-trace="$TMP/$1" --no-cache 2>/dev/null )
}
attr(){ printf '%s' "$2" | grep -o "$1=\"[^\"]*\"" | head -1; }

# ===================================================================================================
# (A) a demangled, space-carrying function name — the exact shape tracecheck.sh (A2a) exercises
# ===================================================================================================
echo "-- (A) a demangled 'rw::alpha(int const&)' frame still splits on the RIGHT boundary"
cat > "$TMP/demangled.txt" <<'EOF'
    #0 0x1 in rw::alpha(int const&) src/mod.cpp:8:1
EOF
OUT_A="$( run_trace demangled.txt )"
if printf '%s' "$OUT_A" | grep -q '<skipped p="src/mod.cpp" line="8"'; then
    ok "A1: path=src/mod.cpp line=8 extracted correctly from a space-carrying func name"
else
    no "A1: the demangled frame did not extract path=src/mod.cpp line=8"; printf '%s\n' "$OUT_A" | head -c 400
fi

# ===================================================================================================
# (C) an ordinary single-space ASan frame — the plain case must be untouched
# ===================================================================================================
echo "-- (C) an ordinary ASan frame (single space before the location) still parses"
cat > "$TMP/plain.txt" <<'EOF'
    #0 0x108a in doWork src/engine.cpp:5:8
EOF
OUT_C="$( run_trace plain.txt )"
if printf '%s' "$OUT_C" | grep -q '<skipped p="src/engine.cpp" line="5"'; then
    ok "C1: path=src/engine.cpp line=5 extracted from an ordinary frame"
else
    no "C1: the ordinary frame did not extract path=src/engine.cpp line=5"; printf '%s\n' "$OUT_C" | head -c 400
fi

# ===================================================================================================
# (B) near-linear timing on a pathological, never-resolving line at 4 sizes
# ===================================================================================================
echo "-- (B) near-linear timing: 40 KB / 160 KB / 640 KB / 2.5 MB pathological ASan lines"

gen(){ # $1 = approx target size in bytes, $2 = output path
    python3 -c "
import sys
target = $1
# one lone path char in the FIRST word — every candidate up to the very last word must be tried and
# fail, so the whole line is walked; ends in a real ':digits' so the fast trailing-digit check alone
# cannot short-circuit the walk.
words = ['a.b']
n = 1
size = len('    #0 0x1 in ') + len(words[0])
while size < target:
    w = 'w%d' % n
    words.append(w)
    size += len(w) + 1
    n += 1
words[-1] = words[-1] + ':123'
line = '    #0 0x1 in ' + ' '.join(words) + chr(10)
open('$2', 'w').write(line)
"
}

gen 40000    "$TMP/patho_40k.txt"
gen 160000   "$TMP/patho_160k.txt"
gen 640000   "$TMP/patho_640k.txt"
gen 2500000  "$TMP/patho_2500k.txt"

# TIMED_OUT_MS: a hang is not "slow", it is the O(k^2) failure mode itself — a per-file 20s ceiling (the
# fixed implementation takes tens of MILLIseconds even at 2.5 MB) turns "the process never returned" into
# an explicit, ranked-huge timing number instead of killing this whole gate out from under the harness.
TIMED_OUT_MS=99999999
# A timing is only a sample when the run COMPLETED with rc=0: a crash, a non-zero exit or a command that never started
# is a failure of this arm, never a fast measurement. timed_trace echoes the runner's line; msOf turns it into a number.
timed_trace(){ # $1 = fixture name -> the runner's one-line result
    capRun 20 --cwd "$TMP/corpus" -- "$BIN" . --from-trace="$TMP/$1" --no-cache
}
msOf(){ # $1 = label, $2 = runner line -> prints ms, or TIMED_OUT_MS for a timeout or a failed run (the B0 loop above records that FAIL)
    case "$2" in
        "rc=0 ms="*) printf '%s' "${2#rc=0 ms=}" ;;
        "TIMEOUT "*) printf '%s' "$TIMED_OUT_MS" ;;
        *)           printf '%s' "$TIMED_OUT_MS" ;;
    esac
}
# #352: ONE sample per size let a single scheduler stall fail the arm. The full-matrix run on 3fcd515f read
# 31 / 65 / 637 / 1382 ms: B1 saw 65 -> 637 (9.8x) and called it quadratic, while the SAME run's next step,
# 640 KB -> 2.5 MB, cost 2.2x, below even linear (a real O(k^2) turns 637 ms into ~10 s there). The 640 KB run
# stalled once. So every size is timed REPS times, round-robin across the sizes (a burst of load lands on one
# rep of every size, not on every rep of one size), and B1-B3 compare MEDIANS: one stalled rep per size, or two,
# moves nothing. A real quadratic is slow on EVERY rep, so the median keeps it — see the mutation control above.
REPS=5
R40=(); R160=(); R640=(); R2500=()
for (( rep = 0; rep < REPS; ++rep )); do
    R40+=( "$( timed_trace patho_40k.txt )" ); R160+=( "$( timed_trace patho_160k.txt )" )
    R640+=( "$( timed_trace patho_640k.txt )" ); R2500+=( "$( timed_trace patho_2500k.txt )" )
done
samplesOk=1
checkSamples(){ # $1 = label, $2.. = the runner lines of that size
    local label="$1" r; shift
    for r in "$@"; do
        case "$r" in
            "rc=0 ms="*|"TIMEOUT "*) ;;
            *) samplesOk=0; no "B0: a $label run is not a timing sample — $r (a failed or unstarted run must never read as fast)" ;;
        esac
    done
}
checkSamples "40 KB" "${R40[@]}"; checkSamples "160 KB" "${R160[@]}"; checkSamples "640 KB" "${R640[@]}"; checkSamples "2.5 MB" "${R2500[@]}"
medianMs(){ # $1 = label, $2.. = runner lines -> the median ms (a timeout counts as TIMED_OUT_MS, so it can only raise it)
    local label="$1" r; shift
    for r in "$@"; do msOf "$label" "$r"; echo; done | sort -n | awk '{ v[NR] = $1 } END { print v[ int( ( NR + 1 ) / 2 ) ] }'
}
ms40=$(medianMs 40k "${R40[@]}"); ms160=$(medianMs 160k "${R160[@]}"); ms640=$(medianMs 640k "${R640[@]}"); ms2500=$(medianMs 2500k "${R2500[@]}")
allMs(){ local r; for r in "$@"; do printf '%s ' "$( msOf x "$r" )"; done; }
echo "     samples (ms): 40 KB [ $(allMs "${R40[@]}")]  160 KB [ $(allMs "${R160[@]}")]  640 KB [ $(allMs "${R640[@]}")]  2.5 MB [ $(allMs "${R2500[@]}")]"
echo "     medians of $REPS:"
echo "     40 KB: ${ms40} ms   160 KB: ${ms160} ms   640 KB: ${ms640} ms   2.5 MB: ${ms2500} ms"

# B1-B3 compare real samples only: with a B0 failure above they would compare the sentinel with itself.
if [ "$samplesOk" = 1 ]; then
    # linear ~= 4x per step; quadratic ~= 16x per step. 8x is generous slack over linear while still well
    # below what even ONE quadratic doubling would show, so this does not flake on a loaded CI box.
    if [ "$ms640" -le $(( ms160 * 8 )) ]; then
        ok "B1: 160 KB -> 640 KB (4x size) cost <= 8x time (${ms160}ms -> ${ms640}ms) — not quadratic"
    else
        no "B1: 160 KB -> 640 KB cost ${ms160}ms -> ${ms640}ms, more than 8x — looks quadratic"
    fi
    if [ "$ms2500" -le $(( ms640 * 12 )) ]; then
        ok "B2: 640 KB -> 2.5 MB (~4x size) cost <= 12x time (${ms640}ms -> ${ms2500}ms) — not quadratic"
    else
        no "B2: 640 KB -> 2.5 MB cost ${ms640}ms -> ${ms2500}ms, more than 12x — looks quadratic"
    fi
    # B3: the 2.5 MB line must not cost quadratic time. The cap is RELATIVE to this run's own 160 KB median (same
    # host, same load, same minute), scaled linearly by the size ratio (2500000/160000 = 15.6x) and widened by K = 4:
    #     cap = K * max( ms160, B3_FLOOR_MS ) * (2500/160); in integers:  ms2500 * 100 <= base * B3_CAP_PCT, B3_CAP_PCT = 6250
    # (6250 % = 62.5x = 4 * 15.625). WHY NOT AN ABSOLUTE CAP: #641's loaded macOS shard read 40 KB 77 / 160 KB 190 /
    # 640 KB 1250 / 2.5 MB 3395 ms, which failed the old absolute 3000 ms although B1/B2 passed (a loaded host slows every
    # size together). 3395/190 = 17.9x there, 1382/65 = 21x on a quiet run: both far under 62.5x. A real quadratic at
    # 2.5 MB is (2500/160)^2 = 244x the 160 KB time, or a 20 s TIMEOUT (TIMED_OUT_MS), both over the cap. B3_FLOOR_MS keeps a
    # tiny, timer-granular 160 KB median from making the cap absurdly tight. B3_INJECT_PCT is a TEST-ONLY knob that scales the
    # measured 2.5 MB median (the mutant arm below proves B3 bites); it is 100 in every real run.
    B3_CAP_PCT=6250; B3_FLOOR_MS=20
    b3Within(){ # $1 = ms160, $2 = ms2500 -> 0 when within the cap
        # A timed-out baseline is not a baseline: with every size at TIMED_OUT_MS the relative cap would scale with the
        # sentinel itself and pass (CodeRabbit, #670). A timeout on either side is out of the cap.
        if [ "$1" -ge "$TIMED_OUT_MS" ] || [ "$2" -ge "$TIMED_OUT_MS" ]; then return 1; fi
        local base="$1"; [ "$base" -lt "$B3_FLOOR_MS" ] && base="$B3_FLOOR_MS"
        [ $(( $2 * 100 )) -le $(( base * B3_CAP_PCT )) ]
    }
    ms2500m=$(( ms2500 * ${B3_INJECT_PCT:-100} / 100 ))
    capMs=$(( ( ms160 < B3_FLOOR_MS ? B3_FLOOR_MS : ms160 ) * B3_CAP_PCT / 100 ))
    if b3Within "$ms160" "$ms2500m"; then
        ok "B3: the 2.5 MB pathological trace parses in ${ms2500m} ms (<= ${capMs} ms = 62.5x this run's 160 KB median of ${ms160} ms)"
    else
        no "B3: the 2.5 MB pathological trace took ${ms2500m} ms, over ${capMs} ms (62.5x the run's own 160 KB median ${ms160} ms) — looks unbounded"
    fi
    echo "     B3 margin: ${ms2500m} ms of ${capMs} ms cap ($(( ms2500m * 100 / capMs )) % used)"
    # B4 premise self-test of the rule itself on fixed numbers (no timing): the #641 loaded run passes, the quadratic fails.
    b4n=0
    b4(){ # $1 = label, $2 = ms160, $3 = ms2500, $4 = want (pass|fail)
        local got=fail; b3Within "$2" "$3" && got=pass; b4n=$(( b4n + 1 ))
        if [ "$got" = "$4" ]; then ok "B4: $1 -> B3 rule says $got"; else no "B4: $1 -> B3 rule said $got, wanted $4"; fi
    }
    b4 "#641 loaded macOS shard (160 KB 190 ms, 2.5 MB 3395 ms)" 190 3395 pass
    b4 "quiet run (160 KB 65 ms, 2.5 MB 1382 ms)" 65 1382 pass
    b4 "quadratic at 2.5 MB (160 KB 65 ms, 2.5 MB 65*244 ms)" 65 15860 fail
    b4 "quadratic that hit the runner cap (timeout)" 1033 "$TIMED_OUT_MS" fail
    b4 "every size timed out (sentinel baseline)" "$TIMED_OUT_MS" "$TIMED_OUT_MS" fail
    [ "$b4n" = 5 ] || no "B4: expected 5 rule self-tests, ran $b4n"
fi

if [ "$fail" = 0 ]; then
    echo "ALL PASS"
else
    echo "FAILURES ABOVE"
fi
exit "$fail"
