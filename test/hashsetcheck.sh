#!/usr/bin/env bash
# hashsetcheck.sh — a membership table is a HashSet, not a map whose value nobody reads (card HASHSET-ALIAS, owner 11-11,
# reports mem-audit-fable-1111). model.h had HashMap and no set alias, so integer-keyed "have I seen K" tables drifted to
# HashMap<K, char|bool|u8>: 16 B per u64 entry where the key alone is 8 B (8 vs 4 for a u32), and on cockroach the edge-key
# tables alone held 84 MiB that way. HashSet<K> (src/model.h) is the same container family with the same insertion-order
# iteration, so a migration moves no output byte.
#
# Arms:
#   P  the premise: the scan reaches src/ and finds the integer-keyed char/bool/u8 maps that DO read their value (the
#      registry below); fails on zero, which would mean the pattern no longer matches anything and the gate is blind.
#   D  the detector: a planted `HashMap<std::uint32_t, char> seen;` outside the registry is flagged.
#   S  every integer-keyed HashMap<K, char|bool|u8> under src/ names a registered table: one whose value is read (a memo's
#      answer, a per-edge flag). A new membership-only table is a HashSet<K>; a new value-reading one is added below,
#      with what reads the value.
#
# Usage: bash test/hashsetcheck.sh [BIN]   (BIN unused: a source scan)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ fail=1; printf '  FAIL  %s\n' "$*"; return 0; }

# the tables whose value IS read — name: what reads it
REGISTRY='
implEdges        graph.h: 1 = every site committing the edge was a one-implementor dispatch (lane L6)
impl             resolve.h EdgeProvenanceSets: the same implEdges, read by value
lazyPairs        graph.h / resolve.h: a lazy import pair, 0 once an eager import of the same pair is seen
lazyPairsOut     resolve.h: the same table, passed out
namesMemo        graph.h: memoized answer (does the file name the class)
refNamesMemo     graph.h: the same over fileRefClasses
procMacroMemo    graph.h: memoized #[proc_macro] verdict
preludeBindMemo  graph.h: memoized prelude-bind verdict
samMemo_         ifacedispatch.h: memoized lambdaImplements( T )
rubySingletonSites graph.h: returns the Ruby def-side bits per site
sites            graph.h rubySingletonSites: the def-side bits
singletons       graph.h: the same, read as out.defSides
viaOut           mcpverbs.h: which direction the BFS edge was stored in
pairSeen         clones.h: being removed by QD-ENVOY-TIME (candidate-major walk)
'
names="$( printf '%s\n' "$REGISTRY" | awk 'NF{print $1}' )"

# integer-keyed HashMap< K, char|bool|u8 > and the identifier that follows it (a variable, a parameter or a function)
scan(){
    grep -rnE 'HashMap<\s*(std::)?(u?int(8|16|32|64)_t|NodeId|std::size_t|size_t|unsigned|int|FileId)\s*,\s*(char|bool|(std::)?uint8_t|unsigned char)\s*>' "$@" \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
        | sed -E 's/^([^:]+):([0-9]+):.*HashMap<[^>]*>[[:space:]]*[*&]?[[:space:]]*(const[[:space:]]+)?[*&]?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*).*/\1:\2 \4/'
}
classify(){   # stdin: "file:line name" → prints violations, counts registered
    reg=0; bad=0
    while read -r at name; do
        if printf '%s\n' "$names" | grep -qx "$name"; then reg=$(( reg + 1 )); else bad=$(( bad + 1 )); echo "$at $name"; fi
    done
    echo "REG $reg BAD $bad"
}

# ---- D ----
mkdir -p "$TMP/plant"
printf 'void f()\n{\n    HashMap<std::uint32_t, char> seen;\n    HashMap<NodeId, bool> procMacroMemo;\n}\n' >"$TMP/plant/p.h"
d="$( scan "$TMP/plant" | classify )"
if printf '%s\n' "$d" | grep -q 'p.h:3 seen' && printf '%s\n' "$d" | grep -q '^REG 1 BAD 1$'; then
    ok "D: a planted membership-only map is flagged, a registered name is not"
else
    no "D: the detector missed the planted site: $( printf '%s' "$d" | tr '\n' ';' )"
fi

# ---- P + S ----
r="$( scan "$ROOT/src" | sed "s#^$ROOT/##" | classify )"
reg="$( printf '%s\n' "$r" | sed -nE 's/^REG ([0-9]+) BAD ([0-9]+)$/\1/p' )"
bad="$( printf '%s\n' "$r" | sed -nE 's/^REG ([0-9]+) BAD ([0-9]+)$/\2/p' )"
if [ "${reg:-0}" -lt 1 ]; then
    no "P: the scan found no registered value-reading table under src/ (the pattern is blind)"
else
    ok "P: the scan reaches src/ and sees $reg registered value-reading table site(s)"
fi
if [ "${bad:-1}" -ne 0 ]; then
    no "S: $bad integer-keyed HashMap<K, char|bool|u8> site(s) not in the registry (a membership table is HashSet<K>):"
    printf '%s\n' "$r" | grep -v '^REG ' | sed 's/^/          /'
else
    ok "S: every integer-keyed char/bool/u8 map under src/ reads its value"
fi

if [ "$fail" -eq 0 ]; then echo "PASS hashsetcheck"; exit 0; fi
echo "FAIL hashsetcheck"; exit 1
