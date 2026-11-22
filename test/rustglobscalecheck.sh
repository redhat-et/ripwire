#!/usr/bin/env bash
# rustglobscalecheck.sh — RUST-GLOB-SCALE: graph.h rustOutsideGlobMaySupply reads each glob `use` of a file ONCE, not once per call.
#
# THE COST. rustOutsideGlobMaySupply (RUST-USE-PRINT-NAMESPACE's glob twin) is asked for every bare Rust call and every in-tree
# namesake of it in another file. Each ask re-read every import record of the caller's file and re-ran, for every glob `use` at a
# level of the call's chain, levelAt (a walk of the file's symbols) and rustPathProvablyOutside (a module-path walk). The work was
# calls x candidates x globs: on a large Rust workspace it was half of the call-graph build. The glob verdicts depend on the file
# alone, so they are now taken once per file (receiverevidence.h rustGlobFileFacts) and every ask reads the per-level summary.
#
# THE ARMS (counts read off the RIPWIRE_STATS line `[mem] rust_glob asks=A reads=R verdicts=V`), on a generated crate whose one
# file holds G outside globs (`use ext_k::*;`) and C bare calls of functions another file defines — run at (G, C) = (n, n),
# (n, 2n) and (2n, 2n):
#   P1  PREMISE — the calls reach the hedge: asks >= C at every size, and verdicts > 0. FAILS on fewer (a run that never asks
#       proves nothing about how its asks scale).
#   S1  verdicts at (2n, 2n) are at most 2.5x those at (n, n): one per glob (a verdict per glob per call is 4x).
#   S2  import records read at (n, 2n) are at most 1.25x those at (n, n): doubling the CALLS reads no more `use` rows (a
#       rescan per call is 2x). The file's own verdicts still read its `use` rows once per glob (rustRootNamesTreePackage and
#       rustPathProvablyOutside look the glob's head up by name), so reads grow with globs squared, per FILE: printed as INFO.
#   A1  one call is answered once: with every called name defined in 3 other files the ladder asks per candidate (asks >= 2C,
#       the premise), and the answers computed (`answers=`, the asks a binary without that field computes all of) are <= C.
#   E1  the hedge still answers: every generated call is kept by name (`via="name"`) at every size, as before the memo.
#   D   determinism: two runs at (2n, 2n) are byte-identical.
#
# Usage:  bash test/rustglobscalecheck.sh [BIN]   |   RIPWIRE_BIN=build/ripwire bash test/rustglobscalecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "rustglobscalecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home"; export HOME="$TMP/home"

# gen G C: a crate under $TMP/gG_cC whose src/a.rs holds G outside globs and one fn making C bare calls of b.rs's functions
gen(){
    local g="$1" c="$2" d="$TMP/g$1_c$2" i
    mkdir -p "$d/app/src"
    printf '[package]\nname = "app"\nversion = "0.1.0"\n' > "$d/app/Cargo.toml"
    printf 'mod a;\nmod b;\n' > "$d/app/src/lib.rs"
    {
        for (( i = 1; i <= g; i++ )); do printf 'use ext_%d::*;\n' "$i"; done
        printf '\npub fn caller() {\n'
        for (( i = 1; i <= c; i++ )); do printf '    work_%d();\n' "$i"; done
        printf '}\n'
    } > "$d/app/src/a.rs"
    for (( i = 1; i <= c; i++ )); do printf 'pub fn work_%d() {}\n' "$i"; done > "$d/app/src/b.rs"
}
# genmany G C: gen, plus two more files (c.rs, e.rs) defining every called name: three candidates per call
genmany(){
    gen "$1" "$2"
    local d="$TMP/g$1_c$2"
    printf 'mod a;\nmod b;\nmod c;\nmod e;\n' > "$d/app/src/lib.rs"
    cp "$d/app/src/b.rs" "$d/app/src/c.rs"; cp "$d/app/src/b.rs" "$d/app/src/e.rs"
}
# run DIR TAG: stdout, stderr and rc of one map of $TMP/DIR into $TMP/TAG.{out,err,rc}
run(){ ( cd "$TMP/$1" || exit 1; RIPWIRE_STATS=1 "$BIN" "$TMP/$1" --no-cache </dev/null >"$TMP/$2.out" 2>"$TMP/$2.err" ); echo $? >"$TMP/$2.rc"; }
count(){ grep -m1 '^\[mem\] rust_glob ' "$TMP/$1.err" | grep -oE "$2=[0-9]+" | cut -d= -f2; }

N=40; N2=$(( 2 * N ))
gen "$N" "$N"; gen "$N" "$N2"; gen "$N2" "$N2"
run "g${N}_c${N}" nn; run "g${N}_c${N2}" nc; run "g${N2}_c${N2}" cc
premise=1; e1fail=0
for t in nn nc cc; do
    calls="$N2"; [ "$t" = nn ] && calls="$N"
    rc="$( cat "$TMP/$t.rc" )"; a="$( count "$t" asks )"; r="$( count "$t" reads )"; v="$( count "$t" verdicts )"
    echo "  INFO  $t: calls=$calls asks=${a:-none} reads=${r:-none} verdicts=${v:-none} rc=$rc"
    if [ "$rc" != 0 ] || [ "${a:-0}" -lt "$calls" ] || [ "${v:-0}" -le 0 ]; then premise=0; fi
    e="$( grep -o 'n="work_[0-9]*"[^>]*via="name"' "$TMP/$t.out" | wc -l | tr -d ' ' )"
    if [ "$e" != "$calls" ]; then e1fail=1; no "E1 $t: calls kept via=\"name\": $e of $calls"; fi
done
if [ "$premise" = 1 ]; then ok "P1 every run exits 0 and its calls reach the glob hedge"; else no "P1 premise: a run failed, asked fewer than its calls, or ran no verdict (INFO lines above)"; fi
v1="$( count nn verdicts )"; v2="$( count cc verdicts )"
if [ "${v1:-0}" -gt 0 ] && [ $(( ${v2:-0} * 10 )) -le $(( v1 * 25 )) ]; then
    ok "S1 glob verdicts grow linearly: $v1 -> $v2 for 2x the calls and globs"
else
    no "S1 glob verdicts '${v1:-none}' -> '${v2:-none}' for 2x the calls and globs (want <= 2.5x; a verdict per glob per call is 4x)"
fi
r1="$( count nn reads )"; r2="$( count nc reads )"
if [ "${r1:-0}" -gt 0 ] && [ $(( ${r2:-0} * 100 )) -le $(( r1 * 125 )) ]; then
    ok "S2 import records read do not grow with the calls: $r1 -> $r2 for 2x the calls"
else
    no "S2 import records read '${r1:-none}' -> '${r2:-none}' for 2x the calls at the same globs (want <= 1.25x; a rescan per call is 2x)"
fi
mkdir -p "$TMP/many"; ( TMP="$TMP/many"; genmany "$N" "$N" ); run "many/g${N}_c${N}" many
ma="$( count many asks )"; mans="$( count many answers )"; mans="${mans:-$ma}"
if [ "$( cat "$TMP/many.rc" )" = 0 ] && [ "${ma:-0}" -ge $(( 2 * N )) ] && [ "${mans:-x}" -le "$N" ] 2>/dev/null; then
    ok "A1 $N calls with 3 candidates each: $ma asks, $mans answered"
else
    no "A1 $N calls with 3 candidates each: rc=$( cat "$TMP/many.rc" ) asks='${ma:-none}' (want >= $(( 2 * N ))) answered='${mans:-none}' (want <= $N)"
fi
if [ "$e1fail" = 0 ]; then ok "E1 every generated call is kept by name at every size"; fi

run "g${N2}_c${N2}" d
if [ "$( cat "$TMP/d.rc" )" = 0 ] && cmp -s "$TMP/cc.out" "$TMP/d.out"; then ok "D two runs at (2n, 2n) are byte-identical"; else no "D the (2n, 2n) map is not deterministic (rc=$( cat "$TMP/d.rc" ))"; fi

[ "$fail" = 0 ] && echo "rustglobscalecheck: PASS" || echo "rustglobscalecheck: FAIL"
exit "$fail"
