#!/usr/bin/env bash
# zoomcheck.sh — the S5-D --zoom gate (multi-level Louvain → NESTED module hierarchy).
#
#   test/zoomcheck.sh                          # uses build/ripwire on test/zoomfix
#   RIPWIRE_BIN=asan/ripwire test/zoomcheck.sh
#
# The fixture test/zoomfix has 3 directories (core/, io/, util/), each holding TWO tight call-clusters plus a
# top-level app.cpp that bridges all three. Single-level Louvain finds 6 communities; multi-level CONTRACTS
# them into 3 top modules (one per dir), each containing its 2 clusters → a 2-level NESTED hierarchy. The
# script asserts: ≥2 hierarchy levels, the tree is actually NESTED (a level-0 <module> appears inside a
# level-1 <module>), the top is labelled by directory, cross-module BRIDGES are emitted, --zoom --mermaid
# nests subgraphs, and the whole thing is DETERMINISTIC (run twice, byte-identical) and well-formed XML.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/zoomfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "zoomcheck: BIN=$BIN  CORPUS=$CORPUS"

# 1) determinism — byte-identical output run-to-run (multi-level Louvain must stay seeded/ordered stably)
"$BIN" "$CORPUS" --zoom --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --zoom --no-cache >"$TMP/b" 2>/dev/null
diff -q "$TMP/a" "$TMP/b" >/dev/null && ok "determinism (byte-identical, $(wc -c <"$TMP/a" | tr -d ' ') B)" || no "determinism (non-deterministic output)"
ZOOM="$( cat "$TMP/a" )"

# 2) ≥2 hierarchy levels (the whole point of multi-level — a single partition is NOT a hierarchy)
LEVELS="$( printf '%s' "$ZOOM" | grep -o 'levels="[0-9]*"' | grep -o '[0-9]*' )"
[ "${LEVELS:-0}" -ge 2 ] && ok "hierarchy has ≥2 levels (levels=$LEVELS)" || no "hierarchy levels=${LEVELS:-?} (expected ≥2)"

# 3) the hierarchy is NESTED — a level-0 <module> is emitted INSIDE a level-1 <module> (not a flat list). We
#    assert a level="1" module open-tag appears, then a level="0" module before that level-1 module closes.
printf '%s' "$ZOOM" | grep -q 'level="1"' && ok "a top/intermediate module (level=1) exists" || no "no level=1 module (hierarchy not contracted)"
printf '%s' "$ZOOM" \
  | python3 -c '
import sys,re
s=sys.stdin.read()
depth=0; nested=False; sawL1=False
for m in re.finditer(r"<(/?)module(?:\s+level=\"(\d+)\")?([^>]*?)(/?)>", s):
    close,lvl,_,selfc=m.groups()
    if close:
        depth-=1; continue
    if lvl=="1": sawL1=True
    if lvl=="0" and depth>0: nested=True      # a level-0 module nested under an open (level-1) module
    if not selfc: depth+=1
sys.exit(0 if (sawL1 and nested) else 1)
' && ok "level-0 modules are NESTED inside level-1 modules (true tree)" || no "modules are flat, not nested"

# 4) top modules are labelled by their directory (core/io/util) — the dominant-dir label is meaningful
for d in core io util; do
  printf '%s' "$ZOOM" | grep -q "dir=\"[^\"]*zoomfix/$d\"" && ok "top module labelled dir .../$d" || no "no top module for dir .../$d"
done

# 5) cross-module BRIDGES are emitted (app.cpp bridges the three subsystems → ≥1 <bridge>)
BRIDGES="$( printf '%s' "$ZOOM" | grep -o '<bridge ' | wc -l | tr -d ' ' )"
[ "$BRIDGES" -ge 1 ] && ok "cross-module bridges shown ($BRIDGES)" || no "no <bridge> emitted (expected ≥1)"

# 6) well-formed XML
if command -v xmllint >/dev/null 2>&1; then
  printf '%s' "$ZOOM" | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else ok "xml well-formed (xmllint absent — skipped)"; fi

# 7) --zoom --mermaid: a nested-subgraph diagram, deterministic, with subgraph blocks
"$BIN" "$CORPUS" --zoom --mermaid --no-cache >"$TMP/m1" 2>/dev/null
"$BIN" "$CORPUS" --zoom --mermaid --no-cache >"$TMP/m2" 2>/dev/null
{ diff -q "$TMP/m1" "$TMP/m2" >/dev/null && grep -q '^flowchart' "$TMP/m1" && grep -q 'subgraph ' "$TMP/m1"; } \
  && ok "--zoom --mermaid deterministic nested-subgraph diagram" || { no "--zoom --mermaid broken/non-deterministic"; head -6 "$TMP/m1"; }

# 8) --zoom=DEPTH respects an explicit depth cap (=1 → exactly 2 levels: base + 1 contraction)
D1="$( "$BIN" "$CORPUS" --zoom=1 --no-cache 2>/dev/null | grep -o 'levels="[0-9]*"' | grep -o '[0-9]*' )"
[ "${D1:-0}" -eq 2 ] && ok "--zoom=1 caps at 2 levels (base + 1 contraction)" || no "--zoom=1 levels=${D1:-?} (expected 2)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
