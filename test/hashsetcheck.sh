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
#   D  the detector: a planted `HashMap<std::uint32_t, char> seen;` outside the registry is flagged, so is one written
#      across two lines (`HashMap<std::uint32_t,` then `char> split;`), and so is a table that REUSES a registered name in
#      a file the registry does not list it for (`procMacroMemo` in p.h); a planted graph.h `procMacroMemo` is not.
#   E  a scan that cannot read a file fails (CodeRabbit 4550333700): pipefail, and each scan's status is tested; a planted
#      chmod-000 file after a readable one must turn the pipeline non-zero (premise: the readable one's site was printed).
#   S  every integer-keyed HashMap<K, char|bool|u8> under src/ names a registered table: one whose value is read (a memo's
#      answer, a per-edge flag). A row is a FILE and a name, so a new table borrowing a registered name elsewhere is still
#      caught. A new membership-only table is a HashSet<K>; a new value-reading one is added below, with what reads the
#      value. The scan reads whole files, so a declaration split across lines is seen.
#
# Usage: bash test/hashsetcheck.sh [BIN]   (BIN unused: a source scan)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ fail=1; printf '  FAIL  %s\n' "$*"; return 0; }

# the tables whose value IS read — file, name: what reads it
REGISTRY='
graph.h         lazyPairs          a lazy import pair, 0 once an eager import of the same pair is seen
resolve.h       lazyPairs          the same table, resolve side
resolve.h       lazyPairsOut       the same table, passed out
graph.h         namesMemo          memoized answer (does the file name the class)
graph.h         refNamesMemo       the same over fileRefClasses
graph.h         procMacroMemo      memoized #[proc_macro] verdict
graph.h         preludeBindMemo    memoized prelude-bind verdict
ifacedispatch.h samMemo_           memoized lambdaImplements( T )
graph.h         rubySingletonSites returns the Ruby def-side bits per site
graph.h         sites              rubySingletonSites: the def-side bits
graph.h         singletons         the same, read as out.defSides
mcpverbs.h      viaOut             which direction the BFS edge was stored in
clones.h        pairSeen           being removed by QD-ENVOY-TIME (candidate-major walk)
resolve.h       visibleMemo        memoized fileVisibleFrom include-suffix verdict (NARROW-MEMO)
'
pairs="$( printf '%s\n' "$REGISTRY" | awk 'NF{print $1 " " $2}' )"

# integer-keyed HashMap< K, char|bool|u8 > and the identifier that follows it (a variable, a parameter or a function), read
# over whole files so a declaration split across lines matches; a match whose line opens with // is a comment
scan(){
    python3 -c '
import os, re, sys
pat = re.compile( r"HashMap<\s*(?:std::)?(?:u?int(?:8|16|32|64)_t|NodeId|std::size_t|size_t|unsigned|int|FileId)\s*,\s*"
                  r"(?:char|bool|(?:std::)?uint8_t|unsigned char)\s*>\s*[*&]?\s*(?:const\s+)?[*&]?\s*([A-Za-z_][A-Za-z0-9_]*)" )
for top in sys.argv[ 1: ]:
    for d, subdirs, files in os.walk( top ):
        subdirs.sort()
        for f in sorted( files ):
            path = os.path.join( d, f )
            with open( path, errors="replace" ) as fh:
                text = fh.read()
            for m in pat.finditer( text ):
                lineStart = text.rfind( "\n", 0, m.start() ) + 1
                if text[ lineStart:m.start() ].lstrip().startswith( "//" ):
                    continue
                print( "%s:%d %s" % ( path, text.count( "\n", 0, m.start() ) + 1, m.group( 1 ) ) )
' "$@"
}
classify(){   # stdin: "file:line name" → prints violations, counts registered (a row is the file's basename AND the name)
    reg=0; bad=0
    while read -r at name; do
        f="${at%:*}"; f="${f##*/}"
        if printf '%s\n' "$pairs" | grep -qx "$f $name"; then reg=$(( reg + 1 )); else bad=$(( bad + 1 )); echo "$at $name"; fi
    done
    echo "REG $reg BAD $bad"
}

set -o pipefail   # CodeRabbit 4550333700: a scan that dies mid-tree fails its pipeline, not only classify's tail
# ---- D ----
mkdir -p "$TMP/plant"
printf 'void f()\n{\n    HashMap<std::uint32_t, char> seen;\n    HashMap<NodeId, bool> procMacroMemo;\n    HashMap<std::uint32_t,\n            char> split;\n}\n' >"$TMP/plant/p.h"
printf 'void g()\n{\n    HashMap<NodeId, bool> procMacroMemo;\n}\n' >"$TMP/plant/graph.h"
d="$( scan "$TMP/plant" | classify )" || no "D: the scan pipeline over the plant failed (exit $?)"
if printf '%s\n' "$d" | grep -q 'p.h:3 seen' && printf '%s\n' "$d" | grep -q 'p.h:4 procMacroMemo' && printf '%s\n' "$d" | grep -q 'p.h:5 split' \
   && printf '%s\n' "$d" | grep -q '^REG 1 BAD 3$'; then
    ok "D: planted membership-only maps are flagged (one line, split across lines, a registered name reused in another file); graph.h's procMacroMemo is not"
else
    no "D: the detector missed the planted site: $( printf '%s' "$d" | tr '\n' ';' )"
fi

# ---- E: a scan that cannot read a file fails the gate (premise: the readable file before it was scanned) ----
mkdir -p "$TMP/unread"
printf 'HashMap<std::uint32_t, char> early;\n' >"$TMP/unread/a.h"; printf 'HashMap<std::uint32_t, char> late;\n' >"$TMP/unread/b.h"
chmod 000 "$TMP/unread/b.h"
if cat "$TMP/unread/b.h" >/dev/null 2>&1; then
    echo "  SKIP  E: chmod 000 leaves b.h readable here (root?): the partial scan cannot be staged"
else
    e="$( scan "$TMP/unread" 2>/dev/null | classify )"; erc=$?
    if printf '%s\n' "$e" | grep -q 'a.h:1 early' && [ "$erc" -ne 0 ]; then ok "E: an unreadable file fails the scan pipeline (exit $erc; premise: a.h's site was printed first)"
    else no "E: a partial scan exited $erc (want non-zero) or printed no a.h site: $( printf '%s' "$e" | tr '\n' ';' )"; fi
fi
chmod 644 "$TMP/unread/b.h"

# ---- P + S ----
r="$( scan "$ROOT/src" | sed "s#^$ROOT/##" | classify )" || no "P: the scan pipeline over src/ failed (exit $?): the counts below are of a partial scan"
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
