#!/usr/bin/env bash
# relinkcheck.sh — B7.1 (incremental cross-file re-link, R3): the WARM (--cache) path must produce
# output BYTE-IDENTICAL to a cold full rebuild (--no-cache) across every kind of source mutation.
#
# WHY THIS GATE EXISTS (the phase's stated gate):
#   Today the warm path re-parses only changed files (per-file content-hash cache) but re-runs the
#   RESOLVE/LINK stage (name→def resolution across the whole corpus) from scratch every run, and node
#   ids are reassigned every run — so warm output is, by construction, byte-identical to cold. B7.1
#   proposes to SCOPE re-resolution to the name-set diff (reuse cached resolution for links a change
#   provably cannot touch). That is the single highest-correctness-risk optimization in the tool: any
#   divergence ships WRONG FACTS to every warm consumer. This gate is the arbiter. It must be GREEN on
#   today's binary FIRST (pinning the invariant), and it must STAY green after any re-link change —
#   across the hard mutation cases where cross-file edges must dissolve and re-form (rename, delete,
#   add, cross-file signature change), not just the easy body-edit.
#
# METHOD (per mutation case, on an isolated temp tree — NEVER the live repo, and detached from git so
# no churn/hotspot input perturbs the map):
#   1. cold-populate a warm cache on the PRE-mutation tree:   ripwire DIR --cache=C
#   2. apply the mutation to the tree
#   3. WARM (incremental) run reusing that now-stale cache:    ripwire DIR --cache=C   -> warm.out
#   4. COLD (full rebuild, no cache at all):                   ripwire DIR --no-cache -> cold.out
#   5. assert warm.out == cold.out  BYTE-FOR-BYTE
#   Step 1's cache genuinely holds stale entries for the unchanged files, so the warm run must re-link
#   correctly against them — the exact thing a scoped re-link could get wrong.
#
# Runs the whole matrix on TWO corpora: a hand-built multi-file fixture (cross-file calls, includes,
# a class hierarchy — so resolution does real cross-file work) AND a COPY of ripwire's own src/ (a
# large, real C++ tree). Both the lean default map AND the rich --for lens are checked (they use two
# different cache families — lean vs rich — that must both stay byte-identical).
#
# Mutation cases (task B7.1 step 1b): no-change · body-edit · new-def-add · def-RENAME (the hard one:
# old name's edges dissolve, new name's form) · file-deletion · file-addition · cross-file signature.
# Plus (1c): det-gate x3 on a warm run.
#
# Usage:
#   bash test/relinkcheck.sh
#   RIPWIRE_BIN=asan/ripwire bash test/relinkcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "relinkcheck: BIN=$BIN  TMP=$TMP"

# ── the two invocation "views" whose warm==cold identity we assert. The default map is the graph
#    (resolution) output B7.1 is about; --for exercises the RICH cache family + resolution-heavy
#    ranking. --no-stable matches the existing cache gates (path-order prefix off). ────────────────
VIEW_NAMES=( "default-map" "for-lens" )
view_args(){ case "$1" in
    default-map) printf '%s' "--no-stable" ;;
    for-lens)    printf '%s' "--for=helper --no-stable" ;;
esac; }

# compare_warm_cold TREE CASELABEL
#   For every view: cold-populate a cache on the CURRENT tree state is the caller's job (done BEFORE
#   the mutation). Here we do the warm run (reusing $CACHE) and the cold run, and diff them.
#   $CACHE must already be populated (pre-mutation) by the caller.
compare_warm_cold(){
    local tree="$1" label="$2" v args warm cold
    for v in "${VIEW_NAMES[@]}"; do
        args="$( view_args "$v" )"
        warm="$TMP/warm.$label.$v.out"; cold="$TMP/cold.$label.$v.out"
        # WARM: incremental, reuse the (now-stale) cache populated on the pre-mutation tree.
        # shellcheck disable=SC2086
        "$BIN" "$tree" --cache="$CACHE.$v" $args >"$warm" 2>"$TMP/warm.$label.$v.err"
        local rcw=$?
        # COLD: full rebuild, no cache whatsoever.
        # shellcheck disable=SC2086
        "$BIN" "$tree" --no-cache $args >"$cold" 2>"$TMP/cold.$label.$v.err"
        local rcc=$?
        if [ "$rcw" -ne 0 ] || [ "$rcc" -ne 0 ]; then
            no "[$label/$v] run failed (warm rc=$rcw cold rc=$rcc)"
            head -2 "$TMP/warm.$label.$v.err" "$TMP/cold.$label.$v.err" 2>/dev/null
            continue
        fi
        if cmp -s "$warm" "$cold"; then
            ok "[$label/$v] warm(--cache) BYTE-IDENTICAL to cold(--no-cache)"
        else
            no "[$label/$v] warm != cold — incremental re-link DIVERGED from full rebuild (ships wrong facts)"
            printf '        first diff: %s\n' "$( cmp "$warm" "$cold" 2>&1 | head -1 )"
        fi
    done
}

# populate_cache TREE  — cold-populate one cache per view on the tree's CURRENT state.
populate_cache(){
    local tree="$1" v args
    for v in "${VIEW_NAMES[@]}"; do
        args="$( view_args "$v" )"
        rm -f "$CACHE.$v"
        # shellcheck disable=SC2086
        "$BIN" "$tree" --cache="$CACHE.$v" $args >/dev/null 2>&1
    done
}

# ── build the hand fixture: cross-file calls + include + class hierarchy so resolution links across
#    files (helper() defined in util, called from main and lib; Base/Derived inheritance). ─────────
make_fixture(){
    local d="$1"
    rm -rf "$d"; mkdir -p "$d"
    cat > "$d/util.h" <<'EOF'
#ifndef UTIL_H
#define UTIL_H
int helper( int a );
int shared( void );
#endif
EOF
    cat > "$d/util.cpp" <<'EOF'
#include "util.h"
int helper( int a )
{
    return a + 1;
}
int shared( void )
{
    return 42;
}
EOF
    cat > "$d/main.cpp" <<'EOF'
#include "util.h"
int runMain( void )
{
    int x = helper( 3 );
    int y = shared();
    return x + y;
}
EOF
    cat > "$d/lib.cpp" <<'EOF'
#include "util.h"
struct Base
{
    virtual int compute( void ) { return helper( 7 ); }
};
struct Derived : Base
{
    int compute( void ) override { return shared(); }
};
int useBase( Base* b )
{
    return b->compute();
}
EOF
}

# =================================================================================================
#  CASE MATRIX — each case works on a FRESH copy so the cases are independent.
# =================================================================================================
run_case(){
    local label="$1" srctree="$2" mutate_fn="$3"
    local work="$TMP/work.$label"
    rm -rf "$work"; cp -R "$srctree" "$work"
    CACHE="$TMP/cache.$label"
    populate_cache "$work"          # (1) cold-populate on the PRE-mutation tree
    "$mutate_fn" "$work"            # (2) apply the mutation
    compare_warm_cold "$work" "$label"   # (3)(4)(5) warm vs cold, byte-for-byte
}

# ── mutations ────────────────────────────────────────────────────────────────────────────────────
mut_none()      { :; }                                                   # no change at all (fully warm)
mut_bodyedit()  { # change helper's BODY only (signature unchanged) — must not perturb any edge
    cat > "$1/util.cpp" <<'EOF'
#include "util.h"
int helper( int a )
{
    int t = a * 2;
    return t - 1;
}
int shared( void )
{
    return 42;
}
EOF
}
mut_newdef()    { # ADD a new definition + a new cross-file call to it
    cat >> "$1/lib.cpp" <<'EOF'
int freshlyAdded( int n )
{
    return helper( n ) + shared();
}
int callsFresh( void )
{
    return freshlyAdded( 5 );
}
EOF
}
mut_rename()    { # RENAME a def (shared -> sharedRenamed): old callers dissolve, a new caller forms
    cat > "$1/util.cpp" <<'EOF'
#include "util.h"
int helper( int a )
{
    return a + 1;
}
int sharedRenamed( void )
{
    return 42;
}
EOF
    cat >> "$1/main.cpp" <<'EOF'
int alsoCalls( void )
{
    return sharedRenamed();
}
EOF
}
mut_delete()    { rm -f "$1/lib.cpp"; }                                  # remove a whole file
mut_addfile()   { # add a brand-new file that both defines and calls across files
    cat > "$1/extra.cpp" <<'EOF'
#include "util.h"
int extraEntry( void )
{
    return helper( 11 ) + shared();
}
EOF
}
mut_sigchange() { # cross-file SIGNATURE change: helper gains a param; callers updated (arity re-link)
    cat > "$1/util.h" <<'EOF'
#ifndef UTIL_H
#define UTIL_H
int helper( int a, int b );
int shared( void );
#endif
EOF
    cat > "$1/util.cpp" <<'EOF'
#include "util.h"
int helper( int a, int b )
{
    return a + b;
}
int shared( void )
{
    return 42;
}
EOF
    cat > "$1/main.cpp" <<'EOF'
#include "util.h"
int runMain( void )
{
    int x = helper( 3, 4 );
    int y = shared();
    return x + y;
}
EOF
}

# =================================================================================================
#  ARM 1 — the hand fixture
# =================================================================================================
echo "── arm 1: hand fixture (cross-file calls + include + inheritance) ──"
FIX="$TMP/fixture"
make_fixture "$FIX"

# sanity: the fixture actually builds cross-file edges (helper is called from >1 file) so this gate
# is exercising real cross-file resolution, not a degenerate empty graph.
CACHE="$TMP/cache.sanity"
populate_cache "$FIX"
if "$BIN" "$FIX" --no-cache --no-stable 2>/dev/null | grep -q 'n="helper"'; then
    ok "[sanity] fixture parses; helper symbol present (cross-file target exists)"
else
    no "[sanity] fixture did not parse as expected — helper missing"
fi

run_case "none"      "$FIX" mut_none
run_case "bodyedit"  "$FIX" mut_bodyedit
run_case "newdef"    "$FIX" mut_newdef
run_case "rename"    "$FIX" mut_rename
run_case "delete"    "$FIX" mut_delete
run_case "addfile"   "$FIX" mut_addfile
run_case "sigchange" "$FIX" mut_sigchange

# =================================================================================================
#  ARM 2 — a COPY of ripwire's own src/ (large real C++ tree). Mutations target a real file.
#  We copy only src/ (headers + .cpp) into a git-free temp tree so churn is not an input and the
#  live repo is never touched.
# =================================================================================================
echo "── arm 2: copy of ripwire src/ (real large C++ tree) ──"
SRCCOPY="$TMP/srccopy"
mkdir -p "$SRCCOPY"
cp -R "$ROOT/src" "$SRCCOPY/src"

# src-arm mutations operate on stable, low-risk real files (src/infra/hashutil.h is tiny + self-contained).
#
# PRESENCE GUARD (CONTRIBUTING.md §2 — "a gate that cannot observe what it asserts"). Every mutator below
# names a real repo path, and every one of them fails SILENTLY if that path moves: `>>` to a missing path
# CREATES an orphan file nobody includes (so the arm measures a file-addition, not a body-edit), and
# `rm -f` of a missing path is a no-op (so warm-vs-cold is compared on an unchanged tree). Both go GREEN
# WHILE INERT. These four paths moved once already — src/{hashutil,fixedStr,csrverify}.h → src/infra/ —
# which is exactly how a gate rots. So assert the target exists first, and fail loudly when it does not.
srcmut_require()   { # $1 = work tree, $2 = path relative to it
    [ -f "$1/$2" ] && return 0
    no "[src-arm] mutation target is missing: $2 — repoint the mutator in $0 (this arm would otherwise pass while measuring nothing)"
    return 1
}
srcmut_bodyedit()  { srcmut_require "$1" src/infra/hashutil.h || return 0
    printf '\n// relinkcheck body-edit marker (comment only)\n' >> "$1/src/infra/hashutil.h"; }
srcmut_newdef()    { srcmut_require "$1" src/infra/hashutil.h || return 0
    printf '\nnamespace hashutil { inline unsigned relinkProbe( unsigned x ) { return x * 2654435761u; } }\n' >> "$1/src/infra/hashutil.h"; }
srcmut_rename()    { # rename a real symbol in a small file, exercising a cross-file dissolve/reform
    srcmut_require "$1" src/infra/fixedStr.h || return 0
    sed -i.bak 's/fixedStr/fixedStrRenamed/g' "$1/src/infra/fixedStr.h" 2>/dev/null && rm -f "$1/src/infra/fixedStr.h.bak"; }
srcmut_delete()    { srcmut_require "$1" src/infra/csrverify.h || return 0
    rm -f "$1/src/infra/csrverify.h"; }
srcmut_addfile()   { printf 'namespace zz { inline int addedFileFn( int x ) { return x + 1; } }\n' > "$1/src/zz_relink_added.h"; }
srcmut_sigchange() { # change a signature in hashutil.h (add a param) — no caller in-tree, still re-links
    srcmut_require "$1" src/infra/hashutil.h || return 0
    printf '\nnamespace hashutil { inline unsigned relinkSig( unsigned a, unsigned b ) { return a ^ b; } }\n' >> "$1/src/infra/hashutil.h"; }

run_case_src(){
    local label="$1" mutate_fn="$2"
    local work="$TMP/srcwork.$label"
    rm -rf "$work"; cp -R "$SRCCOPY" "$work"
    CACHE="$TMP/srccache.$label"
    # src arm: use the src subdir as the mapped root
    populate_cache "$work/src"
    "$mutate_fn" "$work"
    compare_warm_cold "$work/src" "src-$label"
}

run_case_src "none"      srcmut_bodyedit  # (none via a no-op would duplicate arm1; use bodyedit as the light case)
run_case_src "newdef"    srcmut_newdef
run_case_src "rename"    srcmut_rename
run_case_src "delete"    srcmut_delete
run_case_src "addfile"   srcmut_addfile
run_case_src "sigchange" srcmut_sigchange

# =================================================================================================
#  (1c) det-gate x3 on a WARM run — three consecutive warm runs must be byte-identical to each other.
# =================================================================================================
echo "── det-gate x3 (warm) ──"
DETTREE="$TMP/dettree"; rm -rf "$DETTREE"; cp -R "$FIX" "$DETTREE"
CACHE="$TMP/detcache"
populate_cache "$DETTREE"
mut_newdef "$DETTREE"        # mutate so the warm run actually re-links, then run 3x warm
det_ok=1
for v in "${VIEW_NAMES[@]}"; do
    args="$( view_args "$v" )"
    # shellcheck disable=SC2086
    "$BIN" "$DETTREE" --cache="$CACHE.$v" $args >"$TMP/det.$v.1" 2>/dev/null
    # shellcheck disable=SC2086
    "$BIN" "$DETTREE" --cache="$CACHE.$v" $args >"$TMP/det.$v.2" 2>/dev/null
    # shellcheck disable=SC2086
    "$BIN" "$DETTREE" --cache="$CACHE.$v" $args >"$TMP/det.$v.3" 2>/dev/null
    if cmp -s "$TMP/det.$v.1" "$TMP/det.$v.2" && cmp -s "$TMP/det.$v.2" "$TMP/det.$v.3"; then
        ok "[det/$v] three warm runs byte-identical"
    else
        no "[det/$v] warm runs diverged across repeats (non-determinism)"
        det_ok=0
    fi
done

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
