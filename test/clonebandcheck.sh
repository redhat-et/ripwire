#!/usr/bin/env bash
# clonebandcheck.sh — gate for the Y3 minhash pre-gate in src/clones.h (findClonesType3).
#
# The Type-3 pass used to run the exact k-gram-set Jaccard merge on EVERY distinct length-band-surviving pair
# (O(|fp|) each, millions of pairs on real corpora — the --quality-delta floor). Y3 inserts a deterministic
# 128-component minhash sketch gate (fixed multiplier constants, zero randomness) between the pair de-dup and
# the exact merge. This gate proves, on a self-contained fixture:
#
#   1. RECALL PARITY — the emitted Type-3 pair set with the pre-gate ON is byte-identical to the exact
#      (pre-gate compiled out via -DCTX_TYPE3_SKETCH_OFF) pair set, including a borderline pair engineered
#      at fp-Jaccard 0.4884 (just above the 0.40 gate) — the tripwire a broken/correlated hash family fails.
#   2. PAIR-VISIT REDUCTION — the ON build's `jaccardMerges` counter is ≥ 8× smaller than `distinctPairs`
#      on the chaff-heavy fixture (deterministic COUNTER assert; wall time is never asserted).
#   3. DETERMINISM — two runs byte-identical (also asserted inside the harness across counters).
#
# Regenerating expectations: none are pinned — parity is a live A/B diff between the two compiled binaries.
#
# Usage:  bash test/clonebandcheck.sh            (compiles with c++/clang++)
#         CXX=clang++ bash test/clonebandcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"

# §CI-P3: ask THIS front end how it spells C++23 rather than assuming the Clang-17 spelling — an
# AppleClang 15 (LLVM 16) macos-14 runner rejects `-std=c++23` outright and took this gate with it
# (PR #1, run 30732976779). Rationale + the CMake mapping this mirrors: scripts/cxxstd.sh.
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
HARNESS="$ROOT/test/cloneband_harness.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT

echo "clonebandcheck: CXX=$CXX"

# ── compile the harness twice: pre-gate ON (shipped) and OFF (exact baseline). Same include path + diagnostics.cpp
#    link as type3clonecheck.sh (Diagnostics' DISCLOSE seam). ─────────────────────────────────────────
build_one() {   # $1 = tag, $2.. = extra flags
    local tag="$1"; shift
    if ! "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra "$@" \
            -I"$ROOT/src/infra" -I"$ROOT/third_party" -I"$ROOT/src" \
            "$HARNESS" "$ROOT/src/infra/diagnostics.cpp" -o "$WORK/harness_$tag" 2> "$WORK/cc_$tag.log"; then
        echo "  FAIL  harness ($tag) failed to compile"; sed 's/^/    /' "$WORK/cc_$tag.log"; exit 2
    fi
    echo "  PASS  harness compiled ($tag)"
}
build_one on
build_one off -DCTX_TYPE3_SKETCH_OFF

# ── run both; each enforces its own S-checks (nonzero exit = fail) ───────────────────────────────────────────────
mkdir -p "$WORK/fix_on" "$WORK/fix_off"
if ! "$WORK/harness_on"  "$WORK/fix_on"  > "$WORK/out_on.txt";  then echo "clonebandcheck: FAIL (ON harness)";  sed 's/^/    /' "$WORK/out_on.txt";  exit 2; fi
if ! "$WORK/harness_off" "$WORK/fix_off" > "$WORK/out_off.txt"; then echo "clonebandcheck: FAIL (OFF harness)"; sed 's/^/    /' "$WORK/out_off.txt"; exit 2; fi
sed 's/^/    /' "$WORK/out_on.txt"

# ── recall parity: the emitted pair lines (PAIR id id sim) must be byte-identical ON vs OFF ─────────────────────
grep '^PAIR\|^EMITTED' "$WORK/out_on.txt"  > "$WORK/pairs_on.txt"
grep '^PAIR\|^EMITTED' "$WORK/out_off.txt" > "$WORK/pairs_off.txt"
if ! diff -u "$WORK/pairs_off.txt" "$WORK/pairs_on.txt" > "$WORK/pairs.diff"; then
    echo "  FAIL  recall parity: pre-gate ON emitted a different Type-3 pair set than the exact baseline"
    sed 's/^/    /' "$WORK/pairs.diff"
    echo "clonebandcheck: FAIL"
    exit 2
fi
echo "  PASS  recall parity: ON pair set byte-identical to the exact (OFF) baseline"

# ── the fixture emitted something (belt-and-suspenders against a vacuous parity) ────────────────────────────────
n="$( grep -c '^PAIR' "$WORK/pairs_on.txt" )"
if [ "$n" -lt 3 ]; then echo "  FAIL  fixture emitted only $n pairs (expected >= 3)"; echo "clonebandcheck: FAIL"; exit 2; fi
echo "  PASS  fixture emitted $n Type-3 pairs (near-clones + borderline present)"

# ── T3-PAIRSEEN walk parity (QD-ENVOY-TIME): the candidate-major walk against the bucket walk it replaced ───────────
# findClonesType3 de-duplicates pairs per candidate (sorted partner lists) instead of through a global pair hash, and
# re-runs the bucket walk when the pair cap is reached, so the capped "first N" stay the bucket walk's. Two parities,
# each on PAIR + EMITTED + STATS + CAP lines (every counter, not just the pairs):
#   W1  uncapped: the shipped build vs -DCTX_TYPE3_BUCKET_WALK (the bucket walk alone);
#   W2  capped at 2: the same pair of builds with -DCTX_TYPE3_MAX_PAIRS=2. Its premise: the cap really fired (CAP 1) with
#       two pairs kept. On this fixture the two kept pairs happen not to depend on the visit order, so W2 pins the rest of
#       what the re-run restores: the bucket walk's counters (a build that keeps the candidate walk's own first N instead
#       reports raw=47844 against the bucket walk's 2133, measured 2026-11-11) and the disclosure.
#   W3  the cap re-run does not pay the LCS twice (CodeRabbit 4542253199): the capped build's LCS DPs (LCSDP, every DP run)
#       are fewer than its candidate walk's (the cap, 2) plus the bucket walk's own (the capped bucket-walk build's LCSDP), and
#       never fewer than the bucket walk's. Premise: both LCSDP readings present and the cap fired.
#   W4  the partner list is bounded by the candidates (CodeRabbit 4542253208): the candidate walk's largest partner list
#       (PARTNERS) is <= cands - 1, with each partner held once, while its raw bucket visits (raw=) exceed cands (the premise:
#       counted, FAILS when the fixture stops repeating partners).
# The capped harnesses fail their own S2 check by design (two pairs kept of three), so their exit code is not read; the
# uncapped bucket-walk harness has no such excuse, and its exit code is (CodeRabbit 4542253220).
build_one walk -DCTX_TYPE3_BUCKET_WALK
build_one cap -DCTX_TYPE3_MAX_PAIRS=2
build_one capwalk -DCTX_TYPE3_MAX_PAIRS=2 -DCTX_TYPE3_BUCKET_WALK
walk_lines() { grep '^PAIR\|^EMITTED\|^STATS\|^CAP' "$1"; }
mkdir -p "$WORK/fix_walk" "$WORK/fix_cap" "$WORK/fix_capwalk"
"$WORK/harness_walk"    "$WORK/fix_walk"    > "$WORK/out_walk.txt"; rcwalk=$?
if [ "$rcwalk" -ne 0 ]; then
    echo "  FAIL  W1 the uncapped bucket-walk harness exited $rcwalk (its own S-checks)"; grep 'FAIL' "$WORK/out_walk.txt" | sed 's/^/    /'; echo "clonebandcheck: FAIL"; exit 2
fi
"$WORK/harness_cap"     "$WORK/fix_cap"     > "$WORK/out_cap.txt"
"$WORK/harness_capwalk" "$WORK/fix_capwalk" > "$WORK/out_capwalk.txt"
walk_lines "$WORK/out_on.txt" > "$WORK/w_on.txt"; walk_lines "$WORK/out_walk.txt" > "$WORK/w_walk.txt"
if ! diff -u "$WORK/w_walk.txt" "$WORK/w_on.txt" > "$WORK/w1.diff"; then
    echo "  FAIL  W1 walk parity (uncapped): the candidate walk differs from the bucket walk"; sed 's/^/    /' "$WORK/w1.diff"; echo "clonebandcheck: FAIL"; exit 2
fi
grep -q '^CAP 0$' "$WORK/w_on.txt" || { echo "  FAIL  W1 premise: the uncapped run reports the cap fired"; echo "clonebandcheck: FAIL"; exit 2; }
echo "  PASS  W1 walk parity (uncapped): pairs and every Type3Stats counter identical to the bucket walk"
walk_lines "$WORK/out_cap.txt" > "$WORK/w_cap.txt"; walk_lines "$WORK/out_capwalk.txt" > "$WORK/w_capwalk.txt"
if ! grep -q '^CAP 1$' "$WORK/w_cap.txt" || ! grep -q '^EMITTED 2$' "$WORK/w_cap.txt"; then
    echo "  FAIL  W2 premise: the cap-2 build did not fire the cap with two pairs kept"; sed 's/^/    /' "$WORK/w_cap.txt"; echo "clonebandcheck: FAIL"; exit 2
fi
if ! diff -u "$WORK/w_capwalk.txt" "$WORK/w_cap.txt" > "$WORK/w2.diff"; then
    echo "  FAIL  W2 walk parity (cap 2): the capped pass kept other pairs than the bucket walk"; sed 's/^/    /' "$WORK/w2.diff"; echo "clonebandcheck: FAIL"; exit 2
fi
echo "  PASS  W2 walk parity (cap 2, cap fired): the bucket walk's first-N pairs, counters and disclosure"

lcsdp(){ sed -n 's/^LCSDP \([0-9][0-9]*\) PARTNERS [0-9][0-9]*$/\1/p' "$1"; }
dpcap="$( lcsdp "$WORK/out_cap.txt" )"; dpwalk="$( lcsdp "$WORK/out_capwalk.txt" )"
if [ -z "$dpcap" ] || [ -z "$dpwalk" ]; then
    echo "  FAIL  W3 premise: no LCSDP line (cap ${dpcap:-?}, bucket walk ${dpwalk:-?})"; echo "clonebandcheck: FAIL"; exit 2
fi
if [ "$dpcap" -ge $(( dpwalk + 2 )) ] || [ "$dpcap" -lt "$dpwalk" ]; then
    echo "  FAIL  W3 the capped pass ran $dpcap LCS DPs (want < the candidate walk's 2 + the bucket walk's $dpwalk, and >= $dpwalk)"; echo "clonebandcheck: FAIL"; exit 2
fi
echo "  PASS  W3 the cap re-run reuses the candidate walk's LCS: $dpcap DPs (the bucket walk alone: $dpwalk; both walks in full: $(( dpwalk + 2 )))"
cands="$( sed -n 's/^STATS cands=\([0-9][0-9]*\) raw=.*/\1/p' "$WORK/out_on.txt" )"; raw="$( sed -n 's/^STATS cands=[0-9]* raw=\([0-9][0-9]*\) .*/\1/p' "$WORK/out_on.txt" )"
peak="$( sed -n 's/^LCSDP [0-9][0-9]* PARTNERS \([0-9][0-9]*\)$/\1/p' "$WORK/out_on.txt" )"
if [ -z "$cands" ] || [ -z "$raw" ] || [ -z "$peak" ] || [ "$raw" -le "$cands" ]; then
    echo "  FAIL  W4 premise: cands=${cands:-?} raw=${raw:-?} partners=${peak:-?} (want raw > cands: partners repeat across buckets)"; echo "clonebandcheck: FAIL"; exit 2
fi
if [ "$peak" -ge "$cands" ]; then
    echo "  FAIL  W4 the largest partner list holds $peak entries (want <= cands - 1 = $(( cands - 1 )): each partner once)"; echo "clonebandcheck: FAIL"; exit 2
fi
echo "  PASS  W4 the largest partner list holds $peak entries <= cands - 1 ($(( cands - 1 ))), over $raw raw visits"

echo "clonebandcheck: OK"
exit 0
