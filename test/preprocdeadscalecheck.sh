#!/usr/bin/env bash
# preprocdeadscalecheck.sh — the PREPROCESSOR-DEAD walk's SCALING gate, and the ranges it must still yield.
#
#   bash test/preprocdeadscalecheck.sh                       # build/ripwire
#   bash test/preprocdeadscalecheck.sh build/ripwire_base    # the RED run (base binary walks with ts_node_child)
#   RIPWIRE_BIN=asan/ripwire bash test/preprocdeadscalecheck.sh
#   RIPWIRE_REF_BIN=/path/to/pre-change/ripwire bash test/preprocdeadscalecheck.sh   # arms (D1)/(D2)
#
# WHY A SECOND SCALING GATE. test/padscalecheck.sh already asserts that the comment-flood pathology
# (ONE file whose root holds tens of thousands of children) stays linear across the ingest walks it
# reaches. It cannot reach THIS one: `collectPreprocDeadRanges` (src/preprocdead.h) short-circuits on
# `src.find( "#if" ) == npos`, and padscalecheck's fixture contains no `#if` at all — so its 28 000-line
# file never enters the walk. Every C/C++ header in the world carries an INCLUDE GUARD, which is what
# opens that gate in practice, so the pathology hid behind a text test that real corpora always defeat.
# Measured on llvm-project (audit P1-0, 2026-09-10): `ts_node_child_iterator_next` = 62.99% of busy
# leaves of a cold run and this one walk's inclusive subtree = 56.67% of busy CPU, ~107 s of 188 s.
#
# WHAT THE THREE FIXTURES ARE FOR. `guard/nN` = an include guard + N line comments + one `#if 0`/`#else`
# pair + one real function. The guard makes the whole file ONE preproc_ifdef node whose child list is
# N wide and INPUT-controlled, which is exactly the width `ts_node_child( n, i )` costs O(C^2) to index.
# `plain/n16000` is the same flood with the guard removed: byte-for-byte the same parse work, the same
# node widths, and NO `#if` text — so the difference between the two is the preproc-dead walk and
# nothing else. That control is why arm (C) can name this walk rather than "ingest got slower".
#
# ARMS
#   (A) RANGES — the dead-range SET itself, through the only surface that exposes it: a call inside
#       `#if 0` is not served as a live role="call" row by --uses while the live call to the same callee
#       in the same file still is. BOTH halves, because "no dead row" also passes on an empty answer.
#       Asserted on the FLOODED fixture, so it is the converted wide walk that produced the ranges.
#   (B) SCALING — user CPU, guard/n1000 vs guard/n16000. 16x the width must not cost ~256x the CPU.
#   (C) ISOLATION — guard/n16000 vs plain/n16000 (same flood, no `#if` text). This is the arm that
#       names the walk; it does not short-circuit on a fast absolute number the way (B) does.
#   (D1) BYTE-IDENTICAL vs RIPWIRE_REF_BIN on the generated fixtures — the conversion must not move
#        one byte of output. (D2) the same against the committed C/C++ fixture trees. Both SKIPPED and
#        disclosed when RIPWIRE_REF_BIN is unset (a gate cannot hold a "before" binary of its own).
#   (E) MUTATION — every verdict shape above is shown able to fail, against hand-built inputs.
#
# User CPU, never wall, so a loaded box cannot flake the ratios; and every ratio floors its divisor so a
# ~0 s small arm cannot manufacture a large one.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
REF="${RIPWIRE_REF_BIN:-}"
[ -n "$REF" ] && [ "${REF#/}" = "$REF" ] && REF="$ROOT/$REF"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "preprocdeadscalecheck: python3 required"; exit 2; }
echo "preprocdeadscalecheck: BIN=$BIN"
[ -n "$REF" ] && echo "preprocdeadscalecheck: REF=$REF"

# FOLLOW-UP (audit P1-0, 2026-09-10) — this gate covers src/preprocdead.h ONLY. 52 further indexed
# `ts_node_child( n, i )` sites survive in src/ (`grep -rn 'ts_node_child( ' src/ | grep -v _count`).
# Every one was read and classified; the TRIP CLASS is what sets the loop's C, and only class 1 is a
# defect. They live in files other lanes are editing this round, so the list is the deliverable, not the
# diff; the full table with the reasoning is in the lane report.
#
#   CLASS 1 — per node, width from the FILE (the O(C^2) shape this lane just fixed; convert next):
#     src/ingest_astquery.h:1226  collectSpanTiers   whole-subtree stack walk, ALL children, from the root
#     src/pattern.h:1007          findMatches        whole-subtree stack walk, ALL children, from the root
#     src/pattern.h:429           smallestContaining descends level by level, all children at each level
#     src/pattern.h:493           snapshotNode       collects all children of an arbitrary matched node
#     src/pattern.h:875           matchChildren      collects all children of an arbitrary candidate node
#     src/slice.h:1158            sliceWalk          whole-subtree recursion over all children
#     src/slice.h:1090            sliceWalkPreproc   all children of a preproc node — the SAME include-guard
#                                                    width this lane just measured at 62x
#     src/ingest_crawl.h:516      measureFileHealth  whole-subtree stack walk (ERROR/MISSING hunt)
#     src/ingest_metrics.h:1347   ln_collectLocalDecls  recursion over all children (depth-capped 512,
#                                                    width uncapped)
#     src/ingest_sidecap.h:199    ffiVisitNode       every decl of an `extern "C" { … }` block
#   CLASS 2 — per node, width from the INPUT but small in practice (measure before converting):
#     src/ingest_astquery.h:1807 collectGatedLocalNames (one def's re-parsed top level)
#     src/ingest_relations.h:1768 capturePythonImportBinds (names in one import statement)
#     src/ingest_sidecap.h:477 routesVisitNode (decorators on one definition)
#     src/ingest_binds.h:1343 bindsVisitNode (declarators of one `declaration`)
#     src/ingest_names.h:61 firstChildOfType (early-returning search, any node)
#   CLASS 3 — width from the GRAMMAR, correct as written, do NOT convert (the remaining ~37):
#     base clauses, parameter/argument lists, type annotations, attribute lists, fixed-index probes
#     (`ts_node_child( n, 0 )`), and every `cc_*`/`ev_*` fixed-shape scan. See the note on
#     src/infra/tschildren.h for why a grammar-bounded width keeps the indexed form.

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────
# Generated, never committed: a committed 1 MB comment flood would join every OTHER gate's view of test/
# (trap: a gate fixture that is also part of the live tree the tool indexes).
gen(){ # $1 = dir, $2 = comment line count, $3 = "guard" | "plain"
    mkdir -p "$1"
    python3 - "$1/big.c" "$2" "$3" <<'PY'
import sys
path, n, mode = sys.argv[ 1 ], int( sys.argv[ 2 ] ), sys.argv[ 3 ]
L = []
if mode == "guard":
    L += [ "#ifndef RIPWIRE_SCALE_GUARD_H", "#define RIPWIRE_SCALE_GUARD_H", "" ]
L += [ "int target( int x );" ]
L += [ "// pad " + "x" * 60 ] * n
L += [ "int liveCaller( int x )", "{", "    return target( x );", "}" ]
if mode == "guard":
    L += [ "int deadCaller( int x )", "{", "    return 0;", "#if 0",
           "    return target( x );", "#endif", "}" ]
L += [ "int worker( void ) { return 424242; }" ]
if mode == "guard":
    L += [ "#endif" ]
open( path, 'w' ).write( "\n".join( L ) + "\n" )
PY
}
gen "$TMP/guard/n1000"  1000  guard
gen "$TMP/guard/n4000"  4000  guard
gen "$TMP/guard/n16000" 16000 guard
gen "$TMP/plain/n16000" 16000 plain

# user-CPU seconds (user+sys) of one cold ingest of $1
usercpu(){ # $1 = corpus dir, $2 = binary
    { /usr/bin/time -p "$2" "$1" --no-cache >/dev/null; } 2>"$TMP/t" || { echo FAIL; return; }
    awk '/^user/ { u = $2 } /^sys/ { s = $2 } END { printf "%.2f", u + s }' "$TMP/t"
}

# The one ratio verdict, so no arm hand-rolls a second arithmetic for the same job. Prints
# "fast" | "linear" | "quad <ratio>". $1 small, $2 big, $3 ratio ceiling, $4 absolute short-circuit.
verdict(){ awk -v s="$1" -v b="$2" -v cap="$3" -v floor="$4" 'BEGIN {
    if( b + 0 < floor + 0 ) { print "fast"; exit }        # absolute cost already fine — scaling is moot
    if( s + 0 < 0.02 ) { s = 0.02 }                       # floor the divisor: a ~0 arm cannot invent a ratio
    if( b / s < cap + 0 ) { printf "linear %.1f", b / s } else { printf "quad %.1f", b / s }
}'; }

# ── (A) the ranges themselves — asserted on the FLOODED fixture ───────────────────────────────────────
echo
echo "=== (A) the dead-range SET: a call inside \`#if 0\` is not a live call, the \`#else\`-side one is ==="
"$BIN" "$TMP/guard/n1000" --no-cache --uses=big.c:target >"$TMP/a_uses.xml" 2>/dev/null
A_ROOT="$( python3 -c '
import re,sys
d=open(sys.argv[1]).read()
m=re.search(r"<uses\b[^>]*>",d)
sys.stdout.write(m.group(0) if m else "")' "$TMP/a_uses.xml" )"
rows(){ python3 -c '
import re,sys
d=open(sys.argv[1]).read()
sys.stdout.write("\n".join(r for r in re.findall(r"<u\b[^>]*>",d) if sys.argv[2] in r))' "$1" "$2"; }
if [ -z "$A_ROOT" ]; then
    no "(A) no <uses> root element (empty capture — the arm reading it would have been vacuous)"
else
    A_LIVE="$( rows "$TMP/a_uses.xml" liveCaller )"
    A_DEAD="$( rows "$TMP/a_uses.xml" deadCaller )"
    if [ -z "$A_LIVE" ]; then
        no "(A) control broken — the LIVE call from liveCaller is missing; the dead-row half would be vacuous"
    elif [ -n "$A_DEAD" ]; then
        no "(A) a call site inside \`#if 0\` is served as a live row: $A_DEAD (#62)"
    else
        ok "(A) live call present, \`#if 0\` call absent (on a 1000-child preproc_ifdef node)"
    fi
fi
# determinism of the same answer — the walk order is part of the output contract
"$BIN" "$TMP/guard/n1000" --no-cache --uses=big.c:target >"$TMP/a_uses2.xml" 2>/dev/null
if [ ! -s "$TMP/a_uses.xml" ]; then
    no "(A) determinism (empty --uses answer)"
elif cmp -s "$TMP/a_uses.xml" "$TMP/a_uses2.xml"; then
    ok "(A) determinism (two cold --uses runs byte-identical, $( wc -c <"$TMP/a_uses.xml" | tr -d ' ' ) B)"
else
    no "(A) determinism (two cold --uses runs differ)"
fi

# ── (B) scaling: 16x the child width must not cost ~256x the CPU ─────────────────────────────────────
echo
echo "=== (B) scaling across child width (1000 -> 16000 children of one preproc_ifdef) ==="
b_small="$( usercpu "$TMP/guard/n1000"  "$BIN" )"
b_big="$(   usercpu "$TMP/guard/n16000" "$BIN" )"
if [ "$b_small" = FAIL ] || [ "$b_big" = FAIL ] || [ -z "$b_small" ] || [ -z "$b_big" ]; then
    no "(B) scaling (a timed ingest run failed outright)"
else
    v="$( verdict "$b_small" "$b_big" 24 1.0 )"
    case "$v" in
        fast)      ok "(B) 16000-child ingest ${b_big}s CPU < 1.0s — the O(C^2) walk is absent";;
        linear\ *) ok "(B) ${v#linear } x CPU for 16x the width (small=${b_small}s big=${b_big}s; linear ~16, quadratic ~256)";;
        *)         no "(B) ${v#quad } x CPU for 16x the width — the O(children^2) walk is back (small=${b_small}s big=${b_big}s)";;
    esac
fi

# ── (C) isolation: the SAME flood without `#if` text must cost about the same ────────────────────────
echo
echo "=== (C) isolation: guarded vs unguarded flood of identical width (the preproc-dead walk alone) ==="
c_plain="$( usercpu "$TMP/plain/n16000" "$BIN" )"
if [ "$c_plain" = FAIL ] || [ -z "$c_plain" ] || [ "$b_big" = FAIL ] || [ -z "$b_big" ]; then
    no "(C) isolation (a timed ingest run failed outright)"
else
    v="$( verdict "$c_plain" "$b_big" 8 0.30 )"
    case "$v" in
        fast)      ok "(C) guarded flood ${b_big}s CPU < 0.30s — the walk costs nothing measurable (unguarded ${c_plain}s)";;
        linear\ *) ok "(C) ${v#linear } x the unguarded flood (guarded=${b_big}s plain=${c_plain}s) — under the 8x ceiling";;
        *)         no "(C) an include guard costs ${v#quad } x the identical unguarded flood — collectPreprocDeadRanges is quadratic (guarded=${b_big}s plain=${c_plain}s)";;
    esac
fi

# ── (D) byte-identical against a reference binary ────────────────────────────────────────────────────
echo
echo "=== (D) byte-identical output vs RIPWIRE_REF_BIN ==="
if [ -z "$REF" ]; then
    skip "(D1)/(D2) RIPWIRE_REF_BIN unset — no reference binary to compare against (set it to the pre-change build)"
elif [ ! -x "$REF" ]; then
    no "(D) RIPWIRE_REF_BIN=$REF is not executable"
else
    d_fail=0
    for d in "$TMP/guard/n1000" "$TMP/guard/n4000" "$TMP/guard/n16000" "$TMP/plain/n16000"; do
        "$BIN" "$d" --no-cache --top-k=100000 >"$TMP/d_new" 2>/dev/null
        "$REF" "$d" --no-cache --top-k=100000 >"$TMP/d_ref" 2>/dev/null
        if [ ! -s "$TMP/d_ref" ]; then
            no "(D1) reference map of $( basename "$d" ) is empty — the comparison would be vacuous"; d_fail=1
        elif ! cmp -s "$TMP/d_new" "$TMP/d_ref"; then
            no "(D1) map of $( basename "$d" ) differs from the reference binary"; d_fail=1
        fi
    done
    [ "$d_fail" = 0 ] && ok "(D1) all four generated fixtures map byte-identically to the reference"
    d_fail=0
    d_seen=0
    for d in "$ROOT/test/preproccondfix" "$ROOT/test/cfix" "$ROOT/test/cppqualfix" "$ROOT/test/cudafix" "$ROOT/test/metalfix"; do
        [ -d "$d" ] || continue
        d_seen=$(( d_seen + 1 ))
        "$BIN" "$d" --no-cache --top-k=100000 >"$TMP/d_new" 2>/dev/null
        "$REF" "$d" --no-cache --top-k=100000 >"$TMP/d_ref" 2>/dev/null
        if [ ! -s "$TMP/d_ref" ]; then
            no "(D2) reference map of $( basename "$d" ) is empty — the comparison would be vacuous"; d_fail=1
        elif ! cmp -s "$TMP/d_new" "$TMP/d_ref"; then
            no "(D2) map of $( basename "$d" ) differs from the reference binary"; d_fail=1
        fi
    done
    if [ "$d_seen" = 0 ]; then
        no "(D2) no committed C/C++ fixture tree found — the arm would have been vacuous"
    elif [ "$d_fail" = 0 ]; then
        ok "(D2) $d_seen committed C/C++ fixture trees map byte-identically to the reference"
    fi
fi

# ── (E) mutation: every verdict shape above is shown able to fail ────────────────────────────────────
echo
echo "=== (E) MUTATION — the verdict and row readers are shown able to fail ==="
case "$( verdict 0.01 2.56 24 1.0 )" in
    quad\ *) ok "(E) B-shape: a quadratic pair (0.01s -> 2.56s) IS called quad";;
    *)       no "(E) the (B) verdict cannot see a quadratic pair";;
esac
case "$( verdict 0.10 1.60 24 1.0 )" in
    linear\ *) ok "(E) B-shape: a 16x pair (0.10s -> 1.60s) IS called linear";;
    *)         no "(E) the (B) verdict calls a linear pair quadratic";;
esac
case "$( verdict 0.02 1.16 8 0.30 )" in
    quad\ *) ok "(E) C-shape: the measured pre-change isolation pair (0.02s vs 1.16s) IS called quad";;
    *)       no "(E) the (C) verdict cannot see the pathology it was written against";;
esac
case "$( verdict 0.01 0.20 8 0.30 )" in
    fast) ok "(E) C-shape: a sub-0.30s big arm short-circuits to fast";;
    *)    no "(E) the (C) absolute short-circuit does not fire";;
esac
printf '<uses of="x" count="2"><u role="call" p="big.c:7" in_id="big.c::liveCaller"/><u role="call" p="big.c:13" in_id="big.c::deadCaller"/></uses>' >"$TMP/m_d.xml"
if [ -n "$( rows "$TMP/m_d.xml" deadCaller )" ] && [ -n "$( rows "$TMP/m_d.xml" liveCaller )" ]; then
    ok "(E) A-shape: a served \`#if 0\` row IS detected when one is present"
else
    no "(E) the (A) row reader cannot see rows that are present"
fi
if [ -n "$( rows "$TMP/m_d.xml" noSuchCaller )" ]; then
    no "(E) the (A) row reader invents rows that are absent"
else
    ok "(E) A-shape: an absent caller name yields no rows"
fi

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
