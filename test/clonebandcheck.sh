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
HARNESS="$ROOT/test/cloneband_harness.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT

echo "clonebandcheck: CXX=$CXX"

# ── compile the harness twice: pre-gate ON (shipped) and OFF (exact baseline). Same include path + fastmath.cpp
#    link as type3clonecheck.sh (Diagnostics' DEGRADED_PATH_ALERT seam). ─────────────────────────────────────────
build_one() {   # $1 = tag, $2.. = extra flags
    local tag="$1"; shift
    if ! "$CXX" -std=c++23 -O2 -g -Wall -Wextra "$@" \
            -I"$ROOT/src/infra" -I"$ROOT/third_party" -I"$ROOT/src" \
            "$HARNESS" "$ROOT/src/infra/fastmath.cpp" -o "$WORK/harness_$tag" 2> "$WORK/cc_$tag.log"; then
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

echo "clonebandcheck: OK"
exit 0
