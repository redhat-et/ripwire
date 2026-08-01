#!/usr/bin/env bash
# gointerfacecheck.sh — F3 gate: Go interface method requirements are captured.
#
# For a Go `interface`, ripwire emitted the interface TYPE but NONE of its method requirements — the
# interface's entire contract was invisible with no honesty signal (ambiguous=0 unresolved=0),
# inconsistent with Swift (protocol func requirements ARE captured) and with Go impl methods. The fix
# adds (method_elem name: (field_identifier) @name) @definition.method to queries/go/tags.scm —
# tree-sitter-go models each interface requirement as a `method_elem` inside interface_type (distinct
# from `method_declaration`, which has a receiver + body). This gate asserts the >=2 requirements appear
# as method symbols. It FAILS on HEAD (Get/Put/Delete absent).
#
# Self-contained mktemp fixture; honors RIPWIRE_BIN.
#
# Usage:
#   test/gointerfacecheck.sh
#   RIPWIRE_BIN=asan/ripwire test/gointerfacecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

mkdir -p "$TMP/g"
cat > "$TMP/g/store.go" <<'EOF'
package m

type Store interface {
	Get(k string) int
	Put(k string, v int)
	Delete(k string) bool
}

type Impl struct{}

func (i Impl) Get(k string) int { return 0 }
EOF

XML="$TMP/map.xml"
"$BIN" "$TMP/g" --no-cache > "$XML" 2>/dev/null

command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$XML" && ok "map: passes xmllint --noout" || no "map: xmllint failed"; }

# parse name -> (kind, count)
# §P6.3 repin: identical-(kind,id) rows now collapse into one row with overloads="N" — count
# captured symbols as the sum of overloads weights (absent = 1), not raw rows. The interface-
# requirement + impl-method pair shares a scope-less id here, so it renders as overloads="2";
# the both-exist fact this gate asserts is carried by the weight.
python3 - "$XML" <<'PYEOF' > "$TMP/syms"
import sys, re
from collections import Counter
xml = open(sys.argv[1], encoding='utf-8').read()
c = Counter()
for m in re.finditer(r'<s t="(\w+)" n="([^"]*)"([^>]*)>', xml):
    ov = re.search(r'overloads="(\d+)"', m.group(3))
    c[(m.group(2), m.group(1))] += int(ov.group(1)) if ov else 1
for (n, t), k in sorted(c.items()):
    print("%s\t%s\t%d" % (n, t, k))
PYEOF

count_of(){ awk -F'\t' -v n="$1" '$1==n{s+=$3} END{print s+0}' "$TMP/syms"; }

# the interface TYPE itself survives (unchanged behavior)
awk -F'\t' '$1=="Store" && $2=="iface"{ found=1 } END{ exit found?0:1 }' "$TMP/syms" \
    && ok "interface type Store still captured (t=\"iface\")" \
    || no "interface type Store missing: $( cat "$TMP/syms" )"

# Put and Delete are interface-only requirements → each must appear as a method symbol.
[ "$( count_of Put )" -ge 1 ]    && ok "interface requirement 'Put' captured as a symbol"    || no "interface requirement 'Put' DROPPED (F3): $( grep -c Put "$TMP/syms" )"
[ "$( count_of Delete )" -ge 1 ] && ok "interface requirement 'Delete' captured as a symbol" || no "interface requirement 'Delete' DROPPED (F3)"

# Put/Delete are tagged t="method"
awk -F'\t' '$1=="Put"||$1=="Delete"{ if($2!="method") bad=1 } END{ exit bad?1:0 }' "$TMP/syms" \
    && ok "interface requirements tagged t=\"method\"" \
    || no "interface requirements not tagged t=\"method\""

# Get: interface requirement + the Impl method both exist → 2 Get symbols (distinct scopes).
[ "$( count_of Get )" -ge 2 ] \
    && ok "'Get' present twice (interface requirement + Impl method) — both captured" \
    || no "'Get' should appear as BOTH the interface requirement and the Impl method (>=2), got $( count_of Get )"

# honesty: no new mis-resolution introduced
"$BIN" "$TMP/g" --no-cache 2>/dev/null | grep -q 'ambiguous=0 unresolved=0' \
    && ok "header ambiguous=0 unresolved=0 (clean)" \
    || no "header no longer ambiguous=0 unresolved=0 (unexpected edge noise)"

# determinism + warm==cold
"$BIN" "$TMP/g" --no-cache > "$TMP/det_a" 2>/dev/null
"$BIN" "$TMP/g" --no-cache > "$TMP/det_b" 2>/dev/null
diff -q "$TMP/det_a" "$TMP/det_b" >/dev/null && ok "determinism: byte-identical across two cold runs" || no "determinism: differs across runs"
"$BIN" "$TMP/g" --no-cache > "$TMP/cold" 2>/dev/null
"$BIN" "$TMP/g"            > /dev/null 2>&1
"$BIN" "$TMP/g"            > "$TMP/warm" 2>/dev/null
diff -q "$TMP/cold" "$TMP/warm" >/dev/null && ok "determinism: warm == cold (stable ids)" || no "determinism: warm != cold"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
