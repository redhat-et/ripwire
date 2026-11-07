#!/usr/bin/env bash
# clonepersistcheck.sh — gate for CLONES-PERSIST (src/clones.h cloneBodyKey / findClones, the v50 def-record key).
#
# A Function/Method def's exact-clone key (a 40-bit hash of its normalized token stream + its token count, one u64)
# is computed at parse time from the bytes already in memory and rides the cache record, so a warm findClones
# groups bodies with NO file I/O and re-reads only the members of keys shared by >= 2 bodies, where it compares
# the real normalized strings as the one-pass detector always did. This gate proves:
#
#   (H)  the harness (test/clonepersist_harness.cpp, checks K1-K7: key identity, non-zero, saturation, a FORCED
#        key collision that must not print a false clone, keyless/partial-key parity, an unreadable member, the
#        total order) passes against the shipped clones.h;
#   (M)  MUTANT: the same harness compiled against a copy of clones.h with the verify step removed (shared-key
#        members grouped unread) FAILS K4 — so the harness can see a missing verification;
#   (M2) MUTANT: a copy whose token field does not saturate FAILS K3;
#   (E)  end to end on a runtime fixture (C++ and Python clones, a non-clone of equal token count): --clones and
#        --for (clone=) are byte-identical across --no-cache, a cold --cache fill and the warm --cache re-run; the
#        warm run is a real warm hit (RIPWIRE_CACHE_STATS reparsed=0); the --clones output names the planted
#        groups (positive twin: a crashing or silent binary fails here, not passes).
#
# Usage:  bash test/clonepersistcheck.sh                 (BIN=build/ripwire)
#         RIPWIRE_BIN=asan/ripwire bash test/clonepersistcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
CXX="${CXX:-c++}"
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
HARNESS="$ROOT/test/clonepersist_harness.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
fail=0
ok(){ echo "  PASS  $*"; }
no(){ echo "  FAIL  $*"; fail=1; }
echo "clonepersistcheck: BIN=$BIN CXX=$CXX"

build_harness() {   # $1 = tag, $2 = include dir holding the clones.h to test
    "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra -I"$2" -I"$ROOT/src/infra" -I"$ROOT/third_party" -I"$ROOT/src" \
        "$HARNESS" "$ROOT/src/infra/diagnostics.cpp" -o "$WORK/harness_$1" 2> "$WORK/cc_$1.log"
}

# ── (H) shipped clones.h ─────────────────────────────────────────────────────────────────────────────────────
if build_harness shipped "$ROOT/src"; then
    mkdir -p "$WORK/fix_h"
    if "$WORK/harness_shipped" "$WORK/fix_h" > "$WORK/h.txt"; then ok "(H) harness K1-K7 pass on the shipped clones.h"; else no "(H) harness failed on the shipped clones.h"; fi
    sed 's/^/    /' "$WORK/h.txt"
    [ "$( grep -c '^  PASS  K' "$WORK/h.txt" )" -eq 11 ] && ok "(H) liveness: all 11 K checks ran and passed" || no "(H) not all 11 K checks ran and passed"
else
    no "(H) harness failed to compile"; sed 's/^/    /' "$WORK/cc_shipped.log"
fi

# ── (M) mutant: the verify step removed ──────────────────────────────────────────────────────────────────────
mkdir -p "$WORK/mut" "$WORK/fix_m"
VERIFY_LINE='            v.norm = normalizeSpan( bytes, s.sigEndByte, s.endByte, v.tokens, usesHashLineComments( s.lang ) );'
if grep -qF "$VERIFY_LINE" "$ROOT/src/clones.h"; then
    python3 - "$ROOT/src/clones.h" "$WORK/mut/clones.h" "$VERIFY_LINE" <<'PY'
import sys
src, dst, line = sys.argv[1], sys.argv[2], sys.argv[3]
text = open( src ).read()
open( dst, "w" ).write( text.replace( line, "            v.tokens = cloneKeyTokens( ing.cloneKeys[v.id] );   // MUTANT: no verify", 1 ) )
PY
    if build_harness mutant "$WORK/mut"; then
        if "$WORK/harness_mutant" "$WORK/fix_m" > "$WORK/m.txt"; then
            no "(M) the mutant without the verify step PASSED the harness — K4 cannot see a false clone"
        elif grep -q '  FAIL  K4' "$WORK/m.txt"; then
            ok "(M) the mutant without the verify step fails K4 (forced key collision printed a false clone)"
        else
            no "(M) the mutant failed, but not on K4"; sed 's/^/    /' "$WORK/m.txt"
        fi
    else
        no "(M) mutant harness failed to compile"; sed 's/^/    /' "$WORK/cc_mutant.log"
    fi
else
    no "(M) the verify line this gate mutates is not in src/clones.h — update VERIFY_LINE with the code"
fi

# ── (M2) mutant: the token field does not saturate (a 2^24-token body spills into the hash bits) ───────────────
SAT_EXPR='tokens < kCloneKeyTokenMask ? tokens : kCloneKeyTokenMask'
mkdir -p "$WORK/mut2" "$WORK/fix_m2"
if grep -qF "$SAT_EXPR" "$ROOT/src/clones.h"; then
    python3 - "$ROOT/src/clones.h" "$WORK/mut2/clones.h" "$SAT_EXPR" <<'PY'
import sys
src, dst, expr = sys.argv[1], sys.argv[2], sys.argv[3]
open( dst, "w" ).write( open( src ).read().replace( expr, "tokens", 1 ) )
PY
    if build_harness mutant2 "$WORK/mut2"; then
        if "$WORK/harness_mutant2" "$WORK/fix_m2" > "$WORK/m2.txt"; then
            no "(M2) the non-saturating mutant PASSED the harness — K3 cannot see an overflowing token field"
        elif grep -q '  FAIL  K3' "$WORK/m2.txt"; then
            ok "(M2) the non-saturating mutant fails K3"
        else
            no "(M2) the mutant failed, but not on K3"; sed 's/^/    /' "$WORK/m2.txt"
        fi
    else
        no "(M2) mutant harness failed to compile"; sed 's/^/    /' "$WORK/cc_mutant2.log"
    fi
else
    no "(M2) the saturation expression this gate mutates is not in src/clones.h — update SAT_EXPR with the code"
fi

# ── (E) end to end ───────────────────────────────────────────────────────────────────────────────────────────
if [ ! -x "$BIN" ]; then
    no "(E) binary not found: $BIN"
else
    F="$WORK/fx"; mkdir -p "$F/src" "$F/py"
    cat > "$F/src/a.cpp" <<'EOF'
int sumScaled( int* values, int count, int scale )
{
    int total = 0;
    for( int i = 0; i < count; ++i )
    {
        if( values[i] > 0 ) { total += values[i] * scale; } else { total -= values[i] / 2; }
    }
    return total + count * 3;
}
int otherShape( int* values, int count, int scale )
{
    int total = 0;
    for( int i = 0; i < count; ++i )
    {
        if( values[i] > 0 ) { total -= values[i] * scale; } else { total += values[i] / 2; }
    }
    return total - count * 3;
}
EOF
    cat > "$F/src/b.cpp" <<'EOF'
int weightedSum( int* xs, int n, int w )
{
    int acc = 0;
    for( int j = 0; j < n; ++j )
    {
        if( xs[j] > 0 ) { acc += xs[j] * w; } else { acc -= xs[j] / 9; }
    }
    return acc + n * 4;
}
EOF
    cat > "$F/py/m.py" <<'EOF'
def collect_pairs(items, limit):
    out = []
    for item in items:
        if item.size > limit and item.name != "skip":
            out.append((item.name, item.size * 2))
        else:
            out.append((item.name, 0))
    return out


def gather_rows(rows, cap):
    acc = []
    for row in rows:
        if row.size > cap and row.name != "omit":
            acc.append((row.name, row.size * 7))
        else:
            acc.append((row.name, 1))
    return acc
EOF
    C="$WORK/cache"
    run(){ ( cd "$F" || exit 1; "$BIN" "$F" "$@" 2>/dev/null ); }
    run --clones --no-cache > "$WORK/cl.nc"; rc_nc=$?
    run --clones --cache="$C.lean" > "$WORK/cl.cold"; rc_cold=$?
    run --clones --cache="$C.lean" > "$WORK/cl.warm"; rc_warm=$?
    if [ "$rc_nc" -ne 0 ] || [ "$rc_cold" -ne 0 ] || [ "$rc_warm" -ne 0 ]; then
        no "(E) --clones exited nonzero (no-cache $rc_nc, cold $rc_cold, warm $rc_warm)"
    fi
    if [ -s "$WORK/cl.nc" ] && cmp -s "$WORK/cl.nc" "$WORK/cl.cold" && cmp -s "$WORK/cl.nc" "$WORK/cl.warm"; then
        ok "(E) --clones byte-identical: --no-cache, cold --cache, warm --cache"
    else
        no "(E) --clones differs across --no-cache / cold / warm (or is empty)"
    fi
    if grep -q 'sumScaled' "$WORK/cl.nc" && grep -q 'weightedSum' "$WORK/cl.nc" && grep -q 'collect_pairs' "$WORK/cl.nc" && grep -q 'gather_rows' "$WORK/cl.nc"; then
        ok "(E) positive twin: --clones names both planted groups (C++ sumScaled/weightedSum, Python collect_pairs/gather_rows)"
    else
        no "(E) --clones does not name the planted clone groups"
    fi
    R="$( RIPWIRE_CACHE_STATS=1 "$BIN" "$F" --clones --cache="$C.lean" 2>&1 >/dev/null | grep -oE 'reparsed=[0-9]+' | head -1 | cut -d= -f2 )"
    [ "$R" = "0" ] && ok "(E) the warm --clones run is a real warm hit (reparsed=0)" || no "(E) the warm --clones run re-parsed (reparsed=${R:-none})"
    FOR='--for=sum the scaled values'
    run "$FOR" --no-cache > "$WORK/for.nc"; r1=$?
    run "$FOR" --cache="$C.rich" > "$WORK/for.cold"; r2=$?
    run "$FOR" --cache="$C.rich" > "$WORK/for.warm"; r3=$?
    if [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$r3" -eq 0 ] && [ -s "$WORK/for.nc" ] && cmp -s "$WORK/for.nc" "$WORK/for.cold" && cmp -s "$WORK/for.nc" "$WORK/for.warm"; then
        ok "(E) --for byte-identical: --no-cache, cold --cache, warm --cache"
    else
        no "(E) --for differs across --no-cache / cold / warm, exits nonzero ($r1 $r2 $r3) or is empty"
    fi
    grep -q 'clone=' "$WORK/for.nc" && ok "(E) positive twin: the --for answer carries clone=" || no "(E) the --for answer carries no clone= (the arm proves nothing)"
fi

[ "$fail" -eq 0 ] && echo "clonepersistcheck: ALL PASS" || echo "clonepersistcheck: FAIL"
exit "$fail"
