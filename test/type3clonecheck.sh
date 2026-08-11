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
# PART 2 (P0-6, clone GROUPING + duplication %) runs against the shipped binary's --clones surface, because
# what it pins is a REPORTING contract, not a detector one: the detector emits PAIRS, and three functions
# that are all near-copies of each other produce three pairs of two — never the one group of three a reader
# needs to see. Union-find over the pair graph turns pairs into groups (gid= on every row, clone_groups= on
# the root), and the corpus duplication percentage prices the whole thing in LOC. Both are additive
# attributes on an existing verb, so the arms live with the detector's own family rather than in a new file.
#
# PART 1 is independent of the ripwire binary; PART 2 needs it (RIPWIRE_BIN, as every binary gate here).
# Both use their OWN temp dirs.
# Usage:  bash test/type3clonecheck.sh            (compiles with c++/clang++)
#         CXX=clang++ bash test/type3clonecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"

# §CI-P3: ask THIS front end how it spells C++23 rather than assuming the Clang-17 spelling — an
# AppleClang 15 (LLVM 16) macos-14 runner rejects `-std=c++23` outright and took this gate with it
# (PR #1, run 30732976779). Rationale + the CMake mapping this mirrors: scripts/cxxstd.sh.
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
HARNESS="$ROOT/test/type3clone_harness.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/type3harness"
FIX="$WORK/fix"; mkdir -p "$FIX"

echo "type3clonecheck: CXX=$CXX"

# ── compile the harness against clones.h (header-only): infra + src on the include path ───────────────────────
# diagnostics.cpp supplies Diagnostics::ConsoleLog::handleDegraded (the DEGRADED_PATH_ALERT seam) in debug builds —
# link it exactly as the real ripwire target does, so the pair-cap degrade path resolves.
if ! "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra \
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
    if ! "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra -DCTX_T3_CAP_FIXTURE ${capdef[@]+"${capdef[@]}"} \
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


# ══════════════════════════════════════════════════════════════════════════════════════════════════════
# PART 2 (P0-6) — clone GROUPING (union-find over the pair graph) and the corpus duplication percentage,
# on the shipped --clones surface.
# ══════════════════════════════════════════════════════════════════════════════════════════════════════
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "  FAIL  PART 2 needs a ripwire binary at $BIN (build first, or set RIPWIRE_BIN)"; exit 2; }
p2fail=0
p2ok(){ printf '  PASS  %s\n' "$*"; }
p2no(){ printf '  FAIL  %s\n' "$*"; p2fail=1; }
echo "type3clonecheck: PART 2 (grouping + duplication %) BIN=$BIN"

W2="$WORK/p2"; mkdir -p "$W2/grp" "$W2/dupexact" "$W2/noclone"

# A body of N statements, well past kMinCloneTokens (40) normalized tokens.
#
# The operator CYCLE is not decoration. Type-3 candidate pairs must first survive the k-gram fingerprint
# Jaccard prefilter (kType3MinFpJaccard), and a body of N *identically shaped* lines de-duplicates to a
# ONE-element fingerprint set — so a 20-line `aN = N` body scores J = 1/4 against the same body plus one
# `if`, misses the 0.40 bar, and the pair is never compared at all (MEASURED while writing this gate: the
# uniform-body fixture yielded 1 pair where 3 were expected). Varying the operator gives each body a
# realistic spread of distinct k-grams, which is what the prefilter was tuned against.
bod()
{
    local n="$1" i op
    printf '    v0 = 0\n'
    for i in $( seq 1 $(( n - 1 )) ); do
        case $(( i % 8 )) in
            0) op='+' ;;  1) op='-' ;;  2) op='*' ;;  3) op='//' ;;
            4) op='%' ;;  5) op='&' ;;  6) op='|' ;;  *) op='^' ;;
        esac
        printf '    v%d = v%d %s %d\n' "$i" "$(( i - 1 ))" "$op" "$i"
    done
}

# grp/: THREE functions that are pairwise near-copies (each differs from the next by one inserted `if`).
# The detector reports three PAIRS; a reader needs ONE group of three. That gap is what gid= closes.
{ printf 'def f_one():\n';   bod 20;                                          printf '    return v0\n\n'; \
  printf 'def f_two():\n';   bod 20; printf '    if v0:\n        pass\n';     printf '    return v0\n\n'; \
  printf 'def f_three():\n'; bod 20; printf '    if v0:\n        pass\n    if v1:\n        pass\n'; printf '    return v0\n'; } > "$W2/grp/near.py"

# dupexact/: exactly two IDENTICAL bodies and nothing else, so the duplication arithmetic is checkable by
# hand — one group of two equal-LOC members ⇒ exactly half the corpus LOC is redundant ⇒ dup_pct 50.0.
{ printf 'def alpha():\n'; bod 20; printf '    return v0\n\n'; \
  printf 'def beta():\n';  bod 20; printf '    return v0\n'; } > "$W2/dupexact/two.py"

# noclone/: one body only ⇒ nothing can be duplicated ⇒ the zero arm (a zero here means "none found",
# and it must be a REAL zero, not the same 0 a broken computation would print for the corpora above).
{ printf 'def solo():\n'; bod 20; printf '    return v0\n'; } > "$W2/noclone/one.py"

cl(){ "$BIN" "$1" --clones --no-cache 2>"$W2/err"; }
attr(){ printf '%s' "$2" | grep -oE "$1=\"[^\"]*\"" | head -1 | sed "s/^$1=\"//;s/\"$//"; }

G="$( cl "$W2/grp" )"
D="$( cl "$W2/dupexact" )"
N="$( cl "$W2/noclone" )"

# PRESENCE GUARD (CONTRIBUTING §2): every arm below reads attributes off a row stream that must exist
# first. If the detector found no near-miss pairs in grp/, the grouping arms would pass vacuously.
t3="$( attr type3 "$G" )"
[ "${t3:-0}" -ge 3 ] \
    && p2ok "guard: grp/ yields $t3 Type-3 PAIRS (the grouping arms have something to group)" \
    || p2no "guard: grp/ yielded type3=${t3:-none} — expected >= 3 pairs; the grouping arms would be inert"

# ── arm F: every emitted group row carries a gid= ────────────────────────────────────────────────────
rows="$( printf '%s' "$G" | grep -oE '<group [^>]*>' | wc -l | tr -d ' ' )"
gids="$( printf '%s' "$G" | grep -oE '<group [^>]*>' | grep -cE 'gid="[0-9]+"' | tr -d ' ' )"
[ "$rows" -gt 0 ] && [ "$rows" = "$gids" ] \
    && p2ok "arm F: all $rows group rows carry gid=" \
    || p2no "arm F: $gids of $rows group rows carry gid="

# ── arm G: UNION-FIND — three mutually-similar bodies collapse to ONE group id, not three ────────────
distinct="$( printf '%s' "$G" | grep -oE 'gid="[0-9]+"' | sort -u | wc -l | tr -d ' ' )"
cg="$( attr clone_groups "$G" )"
if [ "$distinct" = 1 ] && [ "$cg" = 1 ]; then
    p2ok "arm G: $t3 pairs over three mutual near-copies collapse to ONE component (clone_groups=1, 1 distinct gid)"
else
    p2no "arm G: expected 1 component, got clone_groups=${cg:-absent} with $distinct distinct gid values over $t3 pairs"
fi
# MUTATION: grouping must not be a constant. Two INDEPENDENT clone relations must report two components.
mkdir -p "$W2/two"
cp "$W2/dupexact/two.py" "$W2/two/pairA.py"
# 40 statements vs pairA's 20 ⇒ the two relations cannot cross-pair (the length band cuts at 0.70 and
# these sit near 0.5), so "2 components" is a fact about the grouping, not about the detector's reach.
{ printf 'def gamma():\n'; bod 40; printf '    return v0\n\n'; \
  printf 'def delta():\n'; bod 40; printf '    return v0\n'; } > "$W2/two/pairB.py"
T="$( cl "$W2/two" )"
cg2="$( attr clone_groups "$T" )"
[ "$cg2" = 2 ] \
    && p2ok "arm G-mut: two independent clone relations report clone_groups=2 (grouping discriminates)" \
    || p2no "arm G-mut: two independent clone relations reported clone_groups=${cg2:-absent}, expected 2"

# ── arm H: the duplication percentage, computed by hand on dupexact/ ─────────────────────────────────
dl="$( attr dup_loc "$D" )"; tl="$( attr total_loc "$D" )"; dp="$( attr dup_pct "$D" )"
if [ -n "$dl" ] && [ -n "$tl" ] && [ "${tl:-0}" -gt 0 ] && [ "$(( dl * 2 ))" = "$tl" ]; then
    p2ok "arm H1: two identical equal-LOC bodies ⇒ dup_loc($dl) is exactly half of total_loc($tl)"
else
    p2no "arm H1: dup_loc=${dl:-absent} total_loc=${tl:-absent} — expected dup_loc*2 == total_loc"
fi
[ "$dp" = "50.0" ] \
    && p2ok "arm H2: dup_pct=50.0 on the hand-computed corpus" \
    || p2no "arm H2: dup_pct=${dp:-absent}, expected 50.0"

# ── arm I: a corpus with no clones reports a REAL zero (none found), not an absent attribute ─────────
ndl="$( attr dup_loc "$N" )"; ndp="$( attr dup_pct "$N" )"; ncg="$( attr clone_groups "$N" )"
if [ "$ndl" = 0 ] && [ "$ndp" = "0.0" ] && [ "$ncg" = 0 ]; then
    p2ok "arm I: a clone-free corpus reports dup_loc=0 dup_pct=0.0 clone_groups=0 (none found, stated)"
else
    p2no "arm I: clone-free corpus reported dup_loc=${ndl:-absent} dup_pct=${ndp:-absent} clone_groups=${ncg:-absent}"
fi

# ── arm J: honesty — the derived counts are FLOORS (the pair list is capped upstream) ────────────────
printf '%s' "$G" | grep -q 'counts_floor="1"' \
    && p2ok "arm J1: the root discloses counts_floor=\"1\" (the pair list the groups derive from is capped)" \
    || p2no "arm J1: no counts_floor=\"1\" on the clones root — a capped-derived count must be labelled a floor"
printf '%s' "$G" | grep -q 'dup_pct=duplicated-LOC' \
    && p2ok "arm J2: the legend DEFINES dup_pct (numerator, denominator and the per-group counting rule)" \
    || p2no "arm J2: the legend does not define dup_pct"

# ── arm K: determinism + well-formedness of the extended output ──────────────────────────────────────
G2="$( cl "$W2/grp" )"
if [ -z "$G" ]; then
    p2no "arm K1: EMPTY --clones output — vacuously identical, not deterministic"
elif [ "$G" = "$G2" ]; then
    p2ok "arm K1: two --clones runs byte-identical (determinism)"
else
    p2no "arm K1: two --clones runs DIFFER"
fi
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$G" | xmllint --noout - 2>"$W2/xl" && p2ok "arm K2: extended --clones output is well-formed XML" \
        || { p2no "arm K2: xmllint rejected the extended output"; sed 's/^/    /' "$W2/xl" | head -3; }
else
    p2no "arm K2: xmllint missing — cannot verify well-formedness (install libxml2-utils)"
fi

[ "$p2fail" = 0 ] || { echo "type3clonecheck: FAILURES ABOVE (PART 2)"; exit 1; }

echo "type3clonecheck: ALL PASS"
exit 0
