#!/usr/bin/env bash
# svectorcheck.sh — correctness gate for the small-vector arms behind rw::SmallVec (src/smallvec.h).
#
# The conversion wave is about to point ~138 nested-vector sites and ~24 map-of-vector objects at one
# alias, and that alias can resolve to four different containers. This gate is what makes that safe:
#
#   A. the differential harness (bench/bench_svector_diff.cpp) compiles and runs green. It replays a
#      seeded, spill-boundary-biased operation stream against std::vector (the oracle),
#      ankerl::svector and rw::svector in lockstep and compares element sequence and
#      size() after EVERY operation, plus an exhaustive swap sweep over every inline/heap pairing.
#      Multiple seeds, because one seed is one sample.
#   B. the LAYOUT PINS in src/infra/svector.h actually fire when the layout changes. A static_assert
#      that cannot fail is decoration; this arm mutates the struct in a scratch copy and requires the
#      build to break. (src/layout.h:229 records a FixedStr change that silently halved a size with no
#      test to catch it — this is that lesson, gated.)
#   C. rw::SmallVec is substitutable: every arm of src/smallvec.h compiles against the real call sites.
#      This is the claim the one-line A/B flip rests on, so a missing operation must fail HERE and not
#      halfway through a measurement run.
#   D. the shape rig (bench/bench_svector_wave.cpp) compiles — it carries the known-negative arm, and a
#      measurement rig that stops building is a measurement rig nobody re-runs.
#
# Usage:  bash test/svectorcheck.sh        |  CXX=clang++ bash test/svectorcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
INC=( -I"$ROOT/src" -I"$ROOT/src/infra" -I"$ROOT/third_party" -I"$ROOT/bench" )
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "svectorcheck: CXX=$CXX"

# ── presence guard: every arm this gate claims to check must actually be on disk, or the gate passes
#    for the wrong reason (CONTRIBUTING.md §2, "green while inert"). ──────────────────────────────────
for f in src/infra/svector.h src/smallvec.h bench/bench_svector_diff.cpp bench/bench_svector_wave.cpp; do
    [ -f "$ROOT/$f" ] || { no "missing $f — nothing to check"; exit 1; }
done
ok "all four small-vector sources present"

# ── A. the differential harness, over several seeds ──────────────────────────────────────────────────
if ! "$CXX" "$CXXSTD" -O2 -Wall -Wextra "${INC[@]}" "$ROOT/bench/bench_svector_diff.cpp" -o "$WORK/diff" 2>"$WORK/cc.log"; then
    no "bench_svector_diff.cpp does not compile"; sed 's/^/    /' "$WORK/cc.log" | head -20
else
    ok "bench_svector_diff.cpp compiles"
    seedsFailed=0
    for s in 1 7 42 2718281828 8675309; do
        if ! "$WORK/diff" "$s" 8000 >"$WORK/diff.$s.log" 2>&1; then
            no "differential harness diverged at seed $s"
            grep -E 'FAIL|diverged|oracle:|rw    :|ankerl:' "$WORK/diff.$s.log" | head -8 | sed 's/^/    /'
            seedsFailed=1
        fi
    done
    [ "$seedsFailed" = 0 ] && ok "differential harness green on 5 seeds (3 arms in lockstep + swap sweep)"
fi

# ── B. the layout pins FIRE. A static_assert nobody can trip is decoration. ──────────────────────────
# A scratch copy of the header gets one extra member, which must break the sizeof pin. Mutating a copy,
# never the tree: a gate that edits tracked source and crashes leaves the repo dirty.
mkdir -p "$WORK/mut"
cp "$ROOT/src/infra/svector.h" "$WORK/mut/svector.h"
# add a member right after the cap_ field declaration
if ! grep -qE 'std::uint32_t +cap_ +=' "$WORK/mut/svector.h"; then
    no "layout-pin mutation arm could not find the cap_ field — the probe target moved, so this arm proves nothing"
else
    # Spacing-tolerant on purpose: the field declarations were re-aligned when the union landed and the
    # exact-spacing probe stopped matching. The presence guard above caught that (rather than the arm
    # silently passing), which is the whole reason it exists — but a probe that survives a re-indent is
    # better than one that has to be re-taught after every touch.
    sed -i.bak -E 's/(std::uint32_t +cap_ +=[^;]*;)/\1 std::uint64_t mutationProbe_ = 0;/' "$WORK/mut/svector.h"
    printf '#include "svector.h"\nint main(){ return int( sizeof( rw::svector<unsigned,2> ) ); }\n' > "$WORK/mut/m.cpp"
    if "$CXX" "$CXXSTD" -fsyntax-only -I"$WORK/mut" "$WORK/mut/m.cpp" 2>"$WORK/mut.log"; then
        no "the sizeof pin did NOT fire on a struct that grew 8 bytes — the layout pins are inert"
    elif grep -q 'must be 16 B' "$WORK/mut.log"; then
        ok "layout pins fire (an added member breaks the build, naming the 16 B contract)"
    else
        no "the mutated header failed to compile, but not on the sizeof pin — the arm is not measuring what it claims"
        head -5 "$WORK/mut.log" | sed 's/^/    /'
    fi
fi

# ── C. every arm of the alias compiles against the REAL call sites ───────────────────────────────────
# graph.h is the heaviest consumer (byName, canonByName, fnBindTargetIds, the C-family lambda), so a
# syntax-only parse of it per arm is the substitutability proof the A/B flip depends on.
armName(){ case "$1" in 0) echo 'std::vector';; 1) echo 'ankerl::svector';; 2) echo 'rw::svector';; esac; }
for arm in 0 1 2; do
    printf '#include "graph.h"\n' > "$WORK/arm$arm.cpp"
    if "$CXX" "$CXXSTD" -fsyntax-only -DRIPWIRE_SMALLVEC="$arm" "${INC[@]}" "$WORK/arm$arm.cpp" 2>"$WORK/arm$arm.log"; then
        ok "arm $arm ($(armName $arm)) compiles against src/graph.h"
    else
        no "arm $arm ($(armName $arm)) does NOT compile against src/graph.h — the one-alias A/B flip is broken"
        grep -E 'error:' "$WORK/arm$arm.log" | head -6 | sed 's/^/    /'
    fi
done

# ── D. the measurement rig still builds ──────────────────────────────────────────────────────────────
if "$CXX" "$CXXSTD" -fsyntax-only -Wall -Wextra "${INC[@]}" "$ROOT/bench/bench_svector_wave.cpp" 2>"$WORK/wave.log"; then
    ok "bench_svector_wave.cpp compiles (the rig carrying the known-negative arm)"
else
    no "bench_svector_wave.cpp does not compile"; grep -E 'error:' "$WORK/wave.log" | head -10 | sed 's/^/    /'
fi

# ── the default arm must remain the shipped one: a stray edit to src/smallvec.h that moves the default
#    would silently change every binary this repo builds. ──────────────────────────────────────────────
if grep -qE '^[[:space:]]*#define[[:space:]]+RIPWIRE_SMALLVEC[[:space:]]+RIPWIRE_SMALLVEC_RW[[:space:]]*$' "$ROOT/src/smallvec.h"; then
    ok "src/smallvec.h default arm is still rw::svector (the shipped container)"
else
    no "src/smallvec.h's default arm changed — that moves every build; it needs its own reviewed commit"
fi

if [ "$fail" = 0 ]; then echo "svectorcheck: OK"; else echo "svectorcheck: FAILURES ABOVE"; fi
exit "$fail"
