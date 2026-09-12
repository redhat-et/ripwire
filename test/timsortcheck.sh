#!/usr/bin/env bash
# timsortcheck.sh — the vendored timsort's correctness, provenance and ZERO-ALLOCATION contract.
#
# WHY THIS GATE EXISTS
#   src/infra/timsort.hpp is a tool with NO CALL SITE. That is deliberate — it was measured against
#   std::sort, radix, pdqsort, std::stable_sort and a three-line std::is_sorted guard on the real captured
#   id sets of three call sites across seven corpora, and it won nowhere (bench/PROFILE.md, 2026-09-10).
#   It is vendored so the layer offers the third algorithm rather than a silent gap, and the facade names
#   the refutation at the point of use.
#
#   A header nothing calls is a header nothing checks. Two things can rot in it without a single build
#   going red, and the second is the dangerous one:
#
#     1. It stops compiling, or stops sorting correctly. Loud enough once anyone tries to use it.
#     2. It stops being ALLOCATION-FREE. The ONLY reason to prefer this copy over the upstream release is
#        a LOCAL PATCH that adds gfx::timsort_workspace — caller-owned scratch, reserved once, so a sort
#        in a hot path never reaches the allocator (G2, the same property radixSort.h's scratch buys).
#        Upstream has no such entry point at ANY of its 13 tags. So the ordinary maintenance action —
#        "bump the vendored header to the current release" — DELETES the property, and deletes it
#        silently: the code still compiles, still sorts, still passes any test that only checks output,
#        and a G2-clean call site quietly starts allocating on every call. Arms E/F/G are that tripwire.
#
#   Upstream's version macro cannot be used as the tripwire, because upstream shipped v3.0.1 WITHOUT
#   bumping GFX_TIMSORT_VERSION_PATCH — it reads 0 at both the v3.0.0 and the v3.0.1 tag. Arm H pins the
#   provenance in prose instead, where a re-vendor has to read it.
#
# Arms:
#   A  presence — the vendored header, the facade and the harness are all on disk (a missing file must
#      fail here, not pass by leaving every later arm with nothing to examine).
#   B  self-contained (G3) — timsort.hpp compiles ALONE against -I src/infra and nothing else: no
#      third_party header, no src/ header, no host-installed dependency. Warnings are errors.
#   C  correctness + STABILITY — the differential harness vs std::stable_sort over 8 shapes x 15 sizes x
#      several seeds, on records tagged with their arrival index, through BOTH facade entry points.
#   D  determinism — the whole harness run is byte-identical across two invocations.
#   E  THE PROPERTY — after one reserve_for(), 200 sorts through the workspace entry point perform
#      ZERO heap allocations.
#   F  contrast (CONTRIBUTING.md §2, "an arm that cannot fail") — the SAME 200 sorts through the owning
#      entry point must allocate. Without this, arm E's zero could equally mean "the counter is dead".
#   G  mutation control — a scratch copy whose workspace constructor is rewritten to bind its own vectors
#      (exactly what a naive re-vendor from upstream produces) must turn arm E RED. A tripwire that
#      cannot be tripped is decoration.
#   H  provenance — the header records the pinned upstream version, states that the workspace is a LOCAL
#      PATCH and not upstream, and warns that an upgrade drops the zero-allocation property.
#   I  facade truth — fastSort.h documents all three algorithms, and its "no call site" claim is checked
#      against the tree rather than trusted.
#   J  no orphan numbers — the ratios the facade quotes to justify the refusal appear in bench/PROFILE.md
#      too, so the comment and the ledger cannot drift apart.
#
# Usage:  bash test/timsortcheck.sh        |  CXX=clang++ bash test/timsortcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
HDR="$ROOT/src/infra/timsort.hpp"
FACADE="$ROOT/src/infra/fastSort.h"
HARNESS="$ROOT/test/timsort_harness.cpp"
LEDGER="$ROOT/bench/PROFILE.md"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "timsortcheck: CXX=$CXX"

# ── A: presence ──────────────────────────────────────────────────────────────────────────────────────
missing=0
for f in src/infra/timsort.hpp src/infra/fastSort.h test/timsort_harness.cpp bench/PROFILE.md; do
    if [ ! -f "$ROOT/$f" ]; then no "A: missing $f — nothing to check"; missing=1; fi
done
if [ "$missing" -ne 0 ]; then echo "SOME CHECKS FAILED"; exit 1; fi
ok "A: vendored header, facade, harness and ledger all present"

# ── B: self-contained (G3) — the layer's include path and NOTHING else ───────────────────────────────
cat > "$WORK/alone.cpp" <<'EOF'
#include "timsort.hpp"
#include <vector>
int main() { std::vector<int> v { 3, 1, 2 }; gfx::timsort( v.begin(), v.end() ); return v[ 0 ] == 1 ? 0 : 1; }
EOF
if "$CXX" "$CXXSTD" -O1 -Wall -Wextra -Werror -I"$ROOT/src/infra" "$WORK/alone.cpp" -o "$WORK/alone" 2>"$WORK/alone.log"; then
    if "$WORK/alone" >/dev/null 2>&1; then
        ok "B: timsort.hpp compiles and runs standalone against src/infra alone, warnings-as-errors"
    else
        no "B: standalone TU built but did not sort"
    fi
else
    no "B: timsort.hpp is not self-contained against -I src/infra (or warns)"
    sed 's/^/    /' "$WORK/alone.log" | head -20
fi

# ── build the harness once for C/D/E/F ───────────────────────────────────────────────────────────────
# -I src, not -I src/infra: the harness spells the layer header `infra/fastSort.h`, which is the
# spelling test/infraportcheck.sh arm (D) requires of every first-party file outside the layer.
INC=( -I"$ROOT/src" -I"$ROOT/third_party" )
harnessBuilt=0
if "$CXX" "$CXXSTD" -O2 -Wall -Wextra "${INC[@]}" "$HARNESS" -o "$WORK/h" 2>"$WORK/cc.log"; then
    harnessBuilt=1
    ok "harness compiles"
else
    no "timsort_harness.cpp does not compile"
    sed 's/^/    /' "$WORK/cc.log" | head -25
fi

if [ "$harnessBuilt" -eq 1 ]; then
    # ── C: correctness + stability, several seeds ────────────────────────────────────────────────────
    seedsFailed=0
    for s in 1 7 42 2718281828 8675309; do
        if ! "$WORK/h" correct "$s" >"$WORK/correct.$s.log" 2>&1; then
            no "C: differential diverged at seed $s"
            grep -E 'MISMATCH|RESULT' "$WORK/correct.$s.log" | head -8 | sed 's/^/    /'
            seedsFailed=1
        fi
    done
    if [ "$seedsFailed" -eq 0 ]; then
        # non-vacuity: the run must actually have compared something.
        cases="$( sed -n 's/.*cases=\([0-9]*\).*/\1/p' "$WORK/correct.1.log" | head -1 )"
        if [ "${cases:-0}" -ge 100 ]; then
            ok "C: $cases shape/size cases per seed x 5 seeds agree with std::stable_sort, stability included"
        else
            no "C: harness reported only ${cases:-0} cases — the differential is not covering the shapes it claims"
        fi
    fi

    # ── D: determinism ───────────────────────────────────────────────────────────────────────────────
    "$WORK/h" correct 42 >"$WORK/det.a" 2>&1
    "$WORK/h" correct 42 >"$WORK/det.b" 2>&1
    if diff -q "$WORK/det.a" "$WORK/det.b" >/dev/null 2>&1; then
        ok "D: two runs of the harness are byte-identical"
    else
        no "D: harness output is not deterministic across runs"
    fi

    # ── E: THE PROPERTY — zero allocations after reserve_for ─────────────────────────────────────────
    if "$WORK/h" alloc >"$WORK/alloc.log" 2>&1; then
        wsAllocs="$( sed -n 's/^RESULT mode=alloc .*allocs=\([0-9]*\).*/\1/p' "$WORK/alloc.log" | head -1 )"
        wsSorted="$( sed -n 's/^RESULT mode=alloc .*sorted=\([0-9]*\).*/\1/p' "$WORK/alloc.log" | head -1 )"
        if [ -z "${wsAllocs:-}" ]; then
            no "E: harness printed no parseable alloc RESULT line"
            sed 's/^/    /' "$WORK/alloc.log" | head -10
        elif [ "${wsSorted:-0}" -ne 1 ]; then
            no "E: the measured region did not leave the data sorted — the count means nothing"
        elif [ "$wsAllocs" -eq 0 ]; then
            ok "E: 200 workspace sorts of 4096 records after one reserve_for = 0 heap allocations"
        else
            no "E: the workspace path allocated $wsAllocs times across 200 sorts — the zero-allocation property is GONE"
            sed 's/^/    /' "$WORK/alloc.log" | head -10
        fi
    else
        no "E: alloc mode exited non-zero"
        sed 's/^/    /' "$WORK/alloc.log" | head -10
    fi

    # ── F: contrast — the owning entry point must allocate ───────────────────────────────────────────
    if "$WORK/h" allocnaive >"$WORK/naive.log" 2>&1; then
        ownAllocs="$( sed -n 's/^RESULT mode=allocnaive .*allocs=\([0-9]*\).*/\1/p' "$WORK/naive.log" | head -1 )"
        if [ -z "${ownAllocs:-}" ]; then
            no "F: harness printed no parseable allocnaive RESULT line"
        elif [ "$ownAllocs" -gt 0 ]; then
            ok "F: the owning entry point allocates $ownAllocs times over the same 200 sorts — arm E's counter is live"
        else
            no "F: the owning entry point ALSO reported 0 allocations — the instrument is dead, so arm E proves nothing"
        fi
    else
        no "F: allocnaive mode exited non-zero"
    fi
fi

# ── G: mutation control — simulate the patch being dropped by a re-vendor ────────────────────────────
#    BOTH layer headers are copied into the scratch include dir, and src/infra is kept OFF the mutated
#    build's include path. A quoted #include resolves against the INCLUDING FILE'S OWN DIRECTORY before
#    any -I, so a scratch copy of timsort.hpp alone is invisible: the real src/infra/fastSort.h would
#    pull in its real neighbour and this control would report a perfect zero forever, which is exactly
#    what it did on first run.
mkdir -p "$WORK/mut/infra"
cp "$FACADE" "$WORK/mut/infra/fastSort.h"
sed 's/tmp_(workspace\.tmp_), pending_(workspace\.pending_)/tmp_(ownedTmp_), pending_(ownedPending_)/' \
    "$HDR" > "$WORK/mut/infra/timsort.hpp"
if cmp -s "$HDR" "$WORK/mut/infra/timsort.hpp"; then
    no "G: the mutation did not take — the workspace constructor's initialiser list was not found, so this control proves nothing"
else
    if "$CXX" "$CXXSTD" -O2 -w -I"$WORK/mut" -I"$ROOT/third_party" "$HARNESS" -o "$WORK/hmut" 2>"$WORK/mut.log"; then
        if "$WORK/hmut" alloc >"$WORK/mutalloc.log" 2>&1; then
            mutAllocs="$( sed -n 's/^RESULT mode=alloc .*allocs=\([0-9]*\).*/\1/p' "$WORK/mutalloc.log" | head -1 )"
            if [ "${mutAllocs:-0}" -gt 0 ]; then
                ok "G: dropping the workspace patch makes arm E red ($mutAllocs allocations) — the tripwire can trip"
            else
                no "G: the mutated header STILL reported 0 allocations — arm E cannot detect a dropped patch"
            fi
        else
            # A mutated build that refuses to run is also a detection, but a weaker one; say so rather
            # than counting it as the property.
            no "G: the mutated harness did not complete — the control could not reach a verdict"
        fi
    else
        no "G: the mutated header does not compile — the control could not reach a verdict"
        sed 's/^/    /' "$WORK/mut.log" | head -10
    fi
fi

# ── H: provenance recorded in the header ─────────────────────────────────────────────────────────────
hmiss=0
grep -q 'v3\.0\.1' "$HDR" || { no "H: the header does not pin the upstream version (v3.0.1)"; hmiss=1; }
grep -q 'github\.com/timsort/cpp-TimSort' "$HDR" || { no "H: the header does not name the upstream project"; hmiss=1; }
grep -qi 'LOCAL PATCH' "$HDR" || { no "H: the header does not record that the workspace is a LOCAL PATCH"; hmiss=1; }
grep -q 'timsort_workspace' "$HDR" || { no "H: gfx::timsort_workspace is absent — the patched entry point is gone"; hmiss=1; }
# NOT `grep -i MIT`: that matches "LIMITATION" inside the licence body itself and can never fail.
grep -q 'SPDX-License-Identifier: MIT' "$HDR" || { no "H: the header carries no MIT SPDX identifier"; hmiss=1; }
grep -q 'Permission is hereby granted' "$HDR" || { no "H: the upstream MIT licence body has been stripped"; hmiss=1; }
# The upgrade warning is the whole point of H: a re-vendor must meet it before it deletes arms E/F.
grep -qi 'upgrad' "$HDR" || { no "H: the header carries no warning about upgrading over the patch"; hmiss=1; }
# And the version macro must be called out as unusable, or the next reader repeats the mistake.
grep -q 'GFX_TIMSORT_VERSION_PATCH' "$HDR" || { no "H: the header does not explain that the version macro is not a version"; hmiss=1; }
[ "$hmiss" -eq 0 ] && ok "H: upstream pin, MIT text, LOCAL PATCH record, upgrade warning and the version-macro caveat are all in the header"

# ── I: facade truth — three algorithms, and the "no call site" claim checked against the tree ────────
imiss=0
for name in 'unstable' 'unstableBranchless' 'stable'; do
    grep -q "infra::sort::$name" "$FACADE" || { no "I: fastSort.h's header comment does not list infra::sort::$name"; imiss=1; }
done
# Real call sites: any use of the facade's stable entry or gfx::timsort outside the facade, the vendored
# header and this gate's own harness.
#
# The scan is factored into a function so the NON-VACUITY PROBE below can run the identical detector over
# a directory that deliberately contains one. Without that probe this arm cannot tell "no call sites"
# from "the detector matched nothing because it is broken", and it would pass — loudly and wrongly — on
# the branch that says the facade's disclosure is correct. That is CONTRIBUTING.md §2 shape 1.
scanCallSites(){   # $1... = directories to scan
    grep -rn --include='*.h' --include='*.hpp' --include='*.cpp' -e 'infra::sort::stable' -e 'gfx::timsort' \
         "$@" 2>/dev/null \
        | grep -v '/infra/fastSort\.h:' | grep -v '/infra/timsort\.hpp:' | wc -l | tr -d ' '
}
mkdir -p "$WORK/probe"
printf 'void f() { infra::sort::stable( a, b, c ); }\n' > "$WORK/probe/user.cpp"
if [ "$( scanCallSites "$WORK/probe" )" -ge 1 ]; then
    ok "I: call-site detector fires on a deliberate use — a zero below means zero, not a broken scan"
else
    no "I: the call-site detector did NOT fire on a file that calls infra::sort::stable — every verdict below is unreliable"
    imiss=1
fi
callSites="$( scanCallSites "$ROOT/src" "$ROOT/bench" )"
if [ "$callSites" -eq 0 ]; then
    if grep -qi 'no call site' "$FACADE"; then
        ok "I: three algorithms documented; timsort has 0 call sites and the facade says so"
    else
        no "I: timsort has 0 call sites but fastSort.h does not say so — the comment has to state it, that is the whole disclosure"
        imiss=1
    fi
else
    if grep -qi 'no call site' "$FACADE"; then
        no "I: fastSort.h still claims timsort has no call site, but $callSites use(s) exist — update the comment"
        imiss=1
    else
        ok "I: three algorithms documented; timsort now has $callSites call site(s) and the facade no longer claims otherwise"
    fi
fi
[ "$imiss" -eq 0 ] || true

# ── J: no orphan numbers — the facade's ratios exist in the ledger too ───────────────────────────────
jmiss=0
for n in '0.35x' '0.58x' '1.71x' '6.0x'; do
    if ! grep -qF "$n" "$FACADE"; then
        no "J: fastSort.h does not quote the measured ratio $n — the refutation has to be at the point of use"
        jmiss=1
    elif ! grep -qF "$n" "$LEDGER"; then
        no "J: fastSort.h quotes $n but bench/PROFILE.md does not — comment and ledger have drifted"
        jmiss=1
    fi
done
[ "$jmiss" -eq 0 ] && ok "J: every ratio the facade quotes is backed by the same figure in bench/PROFILE.md"

if [ "$fail" -ne 0 ]; then
    echo "FAILURES ABOVE"
    exit 1
fi
echo "ALL PASS"
