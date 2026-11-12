#!/usr/bin/env bash
# edgemarkcheck.sh — buildGraph's per-edge marks (card EDGE-FLAGS, speed audit 11-11 card 6; mem-audit-fable-1111). Each site
# that commits a (from, to) edge ORs what it said about the edge into the accumulator row (resolve.h EdgeMark): split, binding,
# import, final-segment, impl-only, proven (its absence is name-only), link, anchor-miss. Those were nine per-edge key tables
# before; the flatten reads the bits into outProv / outNameOnly / outAnchorMiss.
#
# The fixture is ASSEMBLED here from committed fixtures, one per mark (test/ffifix binding, test/ifacedispatchfix impl and split,
# test/mdanchorfix link and anchor-miss, test/pyaliascallfix import, test/attribmultideffix split and name-only), plus narrowcheck
# arm 25's qualified-type pair (final-segment) and a generated call grid for edge count, so one run holds every mark at once.
#
# Arms:
#   Q  RIPWIRE_STATS is stderr only: the full map is byte-identical with and without it.
#   N  the premise: the `[mem] edge marks` line shows >= 1 edge of EACH of the nine marks (proven among them: the grid's plain
#      calls) and >= 1000 edges. It counts what it saw and fails on a zero, so a fixture that stops producing a mark cannot let O
#      pass on an absent attribute (CodeRabbit 4543019682: without proven here, an accumulator that stopped setting
#      kEdgeMarkProven turned every grid edge into via="name" and still passed).
#   O  the bits reach the output: the full map carries prov="split", "binding", "import", "final-segment", via="impl",
#      via="name", via="link" and anchor="missing"; binding and anchor-miss rows equal the marked edges exactly (no other
#      mark outranks binding in edgeProvenance, and anchor="missing" is a link edge's own bit); and an evidence-bound grid edge
#      (grid_0_0 -> grid_0_1, a same-file call to a unique name) prints as a plain <c n="grid_0_1"/>, never via="name".
#
# Usage: bash test/edgemarkcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ fail=1; printf '  FAIL  %s\n' "$*"; return 0; }

if ! "$BIN" --version 2>/dev/null | grep -q '^ripwire '; then
    echo "  FAIL  $BIN does not run"; echo "FAIL edgemarkcheck"; exit 1
fi

REPO="$TMP/repo"; mkdir -p "$REPO"
for d in ffifix ifacedispatchfix mdanchorfix pyaliascallfix attribmultideffix; do
    if [ ! -d "$ROOT/test/$d" ]; then no "fixture test/$d is missing"; continue; fi
    cp -R "$ROOT/test/$d" "$REPO/$d"
done
V="$REPO/fseg"; mkdir -p "$V/lib" "$V/lib3" "$V/app"
printf 'struct map { int find( int k ) { return k; } };\n' >"$V/lib/map.h"
printf 'namespace store { struct tree { int find( int k ) { return k; } }; }\n' >"$V/lib3/tree.h"
printf 'int lookupInRepoLocal() { store::tree table; return table.find( 1 ); }\n' >"$V/app/inrepo.cpp"
printf 'int lookupExternal( ext::map<int, int>& table ) { return table.find( 1 ); }\n' >"$V/app/external.cpp"
G="$REPO/grid"; mkdir -p "$G"
for f in $( seq 0 29 ); do   # 30 files x 40 functions, each calling the next three: ~3,500 plain proven edges
    {
        for n in $( seq 0 39 ); do
            printf 'int grid_%d_%d() { return grid_%d_%d() + grid_%d_%d() + grid_%d_%d(); }\n' "$f" "$n" \
                "$f" $(( ( n + 1 ) % 40 )) "$f" $(( ( n + 2 ) % 40 )) $(( ( f + 1 ) % 30 )) "$n"
        done
    } >"$G/g$f.c"
done

# ---- Q ----
( cd "$REPO" && "$BIN" . --no-cache --legend=compact --top-k=100000 >"$TMP/plain.map" 2>/dev/null ); rcp=$?
( cd "$REPO" && RIPWIRE_STATS=1 "$BIN" . --no-cache --legend=compact --top-k=100000 >"$TMP/stats.map" 2>"$TMP/stats.err" ); rcs=$?
if [ "$rcp" -ne 0 ] || [ "$rcs" -ne 0 ]; then
    no "Q: the map exited $rcp (plain) / $rcs (RIPWIRE_STATS)"
elif ! cmp -s "$TMP/plain.map" "$TMP/stats.map"; then
    no "Q: the map differs with RIPWIRE_STATS set"
else
    ok "Q: the full map is byte-identical with RIPWIRE_STATS set ($( wc -c <"$TMP/plain.map" | tr -d ' ' ) B)"
fi

# ---- N ----
line="$( grep '^\[mem\] edge marks ' "$TMP/stats.err" | head -1 )"
val(){ printf '%s\n' "$line" | tr ' ' '\n' | sed -n "s/^$1=\([0-9][0-9]*\)$/\1/p"; }
edges="$( val edges )"
if [ -z "$line" ]; then
    no "N: no [mem] edge marks line on stderr"
else
    seen=0
    for m in split binding import final-segment impl-only proven link anchor-miss name-only; do
        v="$( val "$m" )"
        if [ "${v:-0}" -ge 1 ]; then seen=$(( seen + 1 )); else no "N: no edge carries the $m mark (${v:-absent})"; fi
    done
    [ "$seen" -eq 9 ] && ok "N: all nine marks seen: ${line#\[mem\] edge marks }"
    if [ "${edges:-0}" -lt 1000 ]; then no "N: the fixture holds ${edges:-0} edges (want >= 1000)"; fi
fi

# ---- O ----
cnt(){ grep -o "$1" "$TMP/plain.map" | wc -l | tr -d ' '; }
present=0
for a in 'prov="split"' 'prov="binding"' 'prov="import"' 'prov="final-segment"' 'via="impl"' 'via="name"' 'via="link"' 'anchor="missing"'; do
    n="$( cnt "$a" )"
    if [ "$n" -ge 1 ]; then present=$(( present + 1 )); else no "O: the map carries no $a"; fi
done
[ "$present" -eq 8 ] && ok "O: every mark's attribute reaches the map"
for pair in 'binding:prov="binding"' 'anchor-miss:anchor="missing"'; do
    m="${pair%%:*}"; a="${pair#*:}"
    want="$( val "$m" )"; got="$( cnt "$a" )"
    if [ -n "$want" ] && [ "$got" -eq "$want" ]; then ok "O: $a rows $got = $m edges"; else no "O: $a rows $got, $m edges ${want:-absent}"; fi
done

g00="$( grep -oE '<s t="fn" n="grid_0_0"[^>]*>(<c [^>]*/>)*' "$TMP/plain.map" | head -1 )"
g01="$( printf '%s' "$g00" | grep -oE '<c n="grid_0_1"[^>]*/>' | head -1 )"
if [ -z "$g01" ]; then no "O: the map has no grid_0_0 -> grid_0_1 callee row (the premise): ${g00:-<no grid_0_0 row>}"
elif [ "$g01" = '<c n="grid_0_1"/>' ]; then ok "O: the evidence-bound grid edge grid_0_0 -> grid_0_1 prints $g01 (no via=)"
else no "O: the evidence-bound grid edge prints $g01 (want <c n=\"grid_0_1\"/>)"; fi

if [ "$fail" -eq 0 ]; then echo "PASS edgemarkcheck"; exit 0; fi
echo "FAIL edgemarkcheck"; exit 1
