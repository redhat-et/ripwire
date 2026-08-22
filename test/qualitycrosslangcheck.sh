#!/usr/bin/env bash
# qualitycrosslangcheck.sh — gate for the §P13.4 cross-language bare-name collision on the api-surface kind.
# canonicalId degrades to the BARE NAME for scope-less free functions (resolve.h), so a module-level Python
# `def add(a,b,c,d)` and a C header `int add(int,int)` share ONE baseline key. computeSnapshot's paramsBySym
# MAX-aggregates over ALL symbols sharing that key (Python side wins: 4), but the delta's now-side used to
# aggregate over the PUBLIC (header-declared) overload set only (C side: 2) — an asymmetry that manufactured
# a phantom `api-surface surface="contract-change" was="4" now="2"` row, and a gating exit 2, on a CLEAN
# tree. The contract this gate pins: a clean working tree IS its own HEAD, so --quality-delta must be
# vacuously exit 0 with regressions="0" — no matter what same-named symbols coexist across languages.
# Usage:  test/qualitycrosslangcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/qualitycrosslangcheck.sh
# Exits non-zero on any failure. Does NOT edit regression.sh. Needs git.
set -u
BIN="${1:-${RIPWIRE_BIN:-./build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

REPO="$(mktemp -d)"; trap 'rm -rf "$REPO"' EXIT
cd "$REPO" || exit 1
git init -q; git config user.email x@y; git config user.name x
mkdir -p src/core tools
# the collision trio: a 4-param module-level Python `add` (scope-less → bare-name canonId) vs a 2-param
# C `add` declared in a header (the PUBLIC surface) + its non-header definition
printf 'def add(section, cmd, what, opts):\n    return [section, cmd, what, opts]\n' > tools/capture.py
printf 'int add( int a, int b );\nint scale( int v, int k );\n' > src/core/math.h
printf '#include "math.h"\nint add( int a, int b ){ return a + b; }\nint scale( int v, int k ){ return v * k; }\n' > src/core/math.cpp
git add -A; git commit -qm init

# 1) CLEAN tree (working tree == HEAD) → vacuously no regressions, exit 0, and no api-surface row at all
clean_out="$("$BIN" "$REPO" --quality-delta --no-cache 2>/dev/null)"; clean_rc=$?
[ "$clean_rc" -eq 0 ] \
    && ok "clean tree exits 0 (cross-language same-name symbols present)" \
    || no "clean tree exited $clean_rc (phantom gating regression)"
echo "$clean_out" | grep -q 'regressions="0"' \
    && ok "clean tree reports regressions=\"0\"" \
    || { no "clean tree reports a non-zero regression count"; echo "     got: $(echo "$clean_out" | grep -oE 'regressions="[0-9]+"')"; }
echo "$clean_out" | grep -q 'kind="api-surface"' \
    && { no "clean tree emits a phantom api-surface row"; echo "     got: $(echo "$clean_out" | grep -oE '<r kind="api-surface"[^>]*>')"; } \
    || ok "clean tree emits no api-surface row"

# 2) positive control — the kind still FIRES on a real public-contract arity edit. `scale` has a UNIQUE name
#    (no cross-language mask on its key), so widening it 2→3 params in header+definition must produce a
#    major contract-change row (was=2 now=3) and the gating exit 2.
printf 'int add( int a, int b );\nint scale( int v, int k, int bias );\n' > src/core/math.h
printf '#include "math.h"\nint add( int a, int b ){ return a + b; }\nint scale( int v, int k, int bias ){ return v * k + bias; }\n' > src/core/math.cpp
edit_out="$("$BIN" "$REPO" --quality-delta --no-cache 2>/dev/null)"; edit_rc=$?
echo "$edit_out" | grep -q 'kind="api-surface" sym="scale" was="2" now="3" surface="contract-change"' \
    && ok "real public arity edit still flags api-surface contract-change (was=2 now=3)" \
    || { no "real public arity edit no longer flagged (fix over-suppressed)"; echo "     got: $(echo "$edit_out" | grep -oE '<r kind="api-surface"[^>]*>')"; }
[ "$edit_rc" -eq 2 ] \
    && ok "real contract change still gates (exit 2)" \
    || no "real contract change exited $edit_rc, expected 2"

# 3) determinism on the clean-tree shape
git checkout -q -- src/core/math.h src/core/math.cpp
r1="$("$BIN" "$REPO" --quality-delta --no-cache 2>/dev/null)"; r2="$("$BIN" "$REPO" --quality-delta --no-cache 2>/dev/null)"
[ "$r1" = "$r2" ] && ok "--quality-delta deterministic run-to-run" || no "--quality-delta non-deterministic"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
