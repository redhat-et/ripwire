#!/usr/bin/env bash
# type3clonecheck.sh — gate for Type-3 (gapped / near-miss) clone detection in src/clones.h.
#
# clones.h is header-only, so this gate compiles a tiny standalone harness (test/type3clone_harness.cpp) that
# #includes clones.h, builds a hand-made IngestResult over on-disk fixture files, and asserts the four required
# behaviours + a MUTATION check:
#   A  truly-identical bodies      → Type-1/2 group (findClones), NOT a Type-3 pair.
#   B  identical + one inserted stmt→ Type-3 pair (findClonesType3), similarity in [kType3MinSimilarity,1).
#   C  dissimilar bodies           → neither pass reports them (no false positive).
#   D  determinism                 → two runs byte-identical.
#   E  mutation                    → a threshold raised above the measured similarity drops the near-miss pair.
#
# Independent of the ripwire binary and of main.cpp (which this feature does not touch). Uses its OWN temp dir.
# Usage:  bash test/type3clonecheck.sh            (compiles with c++/clang++)
#         CXX=clang++ bash test/type3clonecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"
HARNESS="$ROOT/test/type3clone_harness.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/type3harness"
FIX="$WORK/fix"; mkdir -p "$FIX"

echo "type3clonecheck: CXX=$CXX"

# ── compile the harness against clones.h (header-only): infra + src on the include path ───────────────────────
# diagnostics.cpp supplies Diagnostics::ConsoleLog::handleDegraded (the DEGRADED_PATH_ALERT seam) in debug builds —
# link it exactly as the real ripwire target does, so the pair-cap degrade path resolves.
if ! "$CXX" -std=c++23 -O2 -g -Wall -Wextra \
        -I"$ROOT/src/infra" -I"$ROOT/third_party" -I"$ROOT/src" \
        "$HARNESS" "$ROOT/src/infra/diagnostics.cpp" -o "$BIN" 2> "$WORK/cc.log"; then
    echo "  FAIL  harness failed to compile"; sed 's/^/    /' "$WORK/cc.log"; exit 2
fi
echo "  PASS  harness compiled"

# ── run it: nonzero exit ⇒ a behavioural assertion failed ────────────────────────────────────────────────────
if ! "$BIN" "$FIX"; then
    echo "type3clonecheck: FAIL"
    exit 2
fi

# ── cap-hitting fixture (B1): compile the harness with the Type-3 pair-cap lowered at COMPILE TIME and assert the
#    NEW deterministic behaviour — the cap truncates to the FIRST N prefilter-surviving pairs (id-ordered), the
#    dropped set is fixed by the insertion-ordered bucket walk, and VARYING the cap constant CHANGES the emitted set
#    (the mutation check: an impl that ignored the cap would emit 6 for every C and fail C=2/C=3). Built via the same
#    infra+src include path + diagnostics.cpp link as the primary harness above. ──────────────────────────────────────
cap_run() {   # $1 = cap value ("default" = the shipped 200000); $2 = expected emitted count
    local tag="$1"; local capdef=(); [ "$tag" != "default" ] && capdef=( -DCTX_TYPE3_MAX_PAIRS="$tag" )
    local cbin="$WORK/capharness_$tag"; local cdir="$WORK/cap_$tag"; mkdir -p "$cdir"
    if ! "$CXX" -std=c++23 -O2 -g -Wall -Wextra -DCTX_T3_CAP_FIXTURE ${capdef[@]+"${capdef[@]}"} \
            -I"$ROOT/src/infra" -I"$ROOT/third_party" -I"$ROOT/src" \
            "$HARNESS" "$ROOT/src/infra/diagnostics.cpp" -o "$cbin" 2> "$WORK/cc_$tag.log"; then
        echo "  FAIL  cap harness (cap=$tag) failed to compile"; sed 's/^/    /' "$WORK/cc_$tag.log"; exit 2
    fi
    local out rc got
    out="$( "$cbin" "$cdir" 2>/dev/null )"; rc=$?
    printf '%s\n' "$out" | sed 's/^/    /'
    [ "$rc" -eq 0 ] || { echo "  FAIL  cap harness (cap=$tag) assertion failed"; exit 2; }
    got="$( printf '%s' "$out" | grep -oE 'emitted=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
    [ "$got" = "$2" ] || { echo "  FAIL  cap=$tag emitted=$got, expected $2 (cap did not discriminate)"; exit 2; }
    echo "  PASS  cap=$tag → emitted $got pairs (expected $2)"
}
echo "type3clonecheck: cap-hitting fixture (pair-cap = first-N prefilter-surviving)"
cap_run 2       2   # cap below the 6 available pairs → keep first 2, drop 4
cap_run 3       3   # raise the cap by 1 → keep first 3 (mutation: +1 pair vs cap=2)
cap_run default 6   # shipped cap never trips on 6 pairs → all 6 emitted (proves 6 really survive)

echo "type3clonecheck: ALL PASS"
exit 0
