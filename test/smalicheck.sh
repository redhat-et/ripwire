#!/usr/bin/env bash
# smalicheck.sh — smali ingest gate.
#
# Synthetic apktool-shaped fixture (test/smalifix/), not a decoded APK:
#   A.smali     — Lcom/example/A; with <init>, addOne(I)I, addTwo(I)I.
#                 addTwo invokes Lcom/example/A; -> addOne(I)I (spaces around ->).
#   Decoy.smali — Lcom/example/Decoy;->addOne(I)I, which must not receive that edge.
#
# Indexed names keep the class and the JVM descriptor, so <init> stays intact and a
# bare addOne does not collide across classes. Fields, const-string, switches,
# annotations, .super, and .implements are not symbols.
#
# Usage:
#   test/smalicheck.sh
#   RIPWIRE_BIN=asan/ripwire test/smalicheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/smalifix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "smalicheck: BIN=$BIN  FIX=$FIX"

CLS='Lcom/example/A;'
INIT='Lcom/example/A;-><init>()V'
ONE='Lcom/example/A;->addOne(I)I'
TWO='Lcom/example/A;->addTwo(I)I'
DECOY_CLS='Lcom/example/Decoy;'
DECOY_ONE='Lcom/example/Decoy;->addOne(I)I'

MAP_OUT="$TMP/map.xml"
$BIN "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
if [ "$MAP_EXIT" -eq 0 ]; then ok "default map: exits 0"; else no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"; fi

if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$MAP_OUT"; then ok "default map: passes xmllint --noout"; else no "default map: xmllint failed"; fi
else
    ok "default map: xmllint absent — skipped"
fi

[ -s "$TMP/map.err" ] && no "default map: unexpected stderr: $( cat "$TMP/map.err" )" || ok "default map: clean stderr"

python3 - "$MAP_OUT" "$CLS" "$INIT" "$ONE" "$TWO" "$DECOY_CLS" "$DECOY_ONE" <<'PYEOF' >"$TMP/parsed"
import sys, xml.etree.ElementTree as ET
xml_path, cls, init, one, two, decoy_cls, decoy_one = sys.argv[1:]
root = ET.parse(xml_path).getroot()
by_file = {}
for f in root.iter("f"):
    name = f.get("p", "").rsplit("/", 1)[-1]
    syms = []
    for s in f.findall("s"):
        calls = [c.get("n") for c in s.findall("c")]
        syms.append({"t": s.get("t"), "n": s.get("n"), "calls": calls})
    by_file[name] = syms

def report(file_name, expected):
    syms = by_file.get(file_name, [])
    names = [s["n"] for s in syms]
    missing = [n for n in expected if n not in names]
    extra = [n for n in names if n not in expected]
    kinds_ok = all(any(s["n"] == n and s["t"] == t for s in syms) for n, t in expected.items())
    print("FILE:%s SYMS:%d MISSING:%s EXTRA:%s KINDS:%s" % (
        file_name, len(syms),
        ",".join(missing) or "none",
        ",".join(extra) or "none",
        kinds_ok))

report("A.smali", {cls: "cls", init: "method", one: "method", two: "method"})
report("Decoy.smali", {decoy_cls: "cls", decoy_one: "method"})
a = by_file.get("A.smali", [])
edge_n = sum(s["calls"].count(one) for s in a if s["n"] == two)
decoy_hit = sum(s["calls"].count(decoy_one) for s in a if s["n"] == two)
print("EDGE_N:%d DECOY_HIT:%d" % (edge_n, decoy_hit))
PYEOF
cat "$TMP/parsed"

grep -q 'FILE:A.smali SYMS:4 MISSING:none EXTRA:none KINDS:True' "$TMP/parsed" \
    && ok "A.smali: class, <init>, addOne, addTwo — qualified, no extras" \
    || no "A.smali: expected those four symbols: $( grep 'FILE:A.smali' "$TMP/parsed" )"
grep -q 'FILE:Decoy.smali SYMS:2 MISSING:none EXTRA:none KINDS:True' "$TMP/parsed" \
    && ok "Decoy.smali: class and its own addOne" \
    || no "Decoy.smali: expected class + addOne: $( grep 'FILE:Decoy.smali' "$TMP/parsed" )"
grep -q 'EDGE_N:1 DECOY_HIT:0' "$TMP/parsed" \
    && ok "addTwo calls A.addOne once and not Decoy.addOne" \
    || no "edge: $( grep EDGE_N "$TMP/parsed" )"

echo
echo "=== determinism and warm == cold ==="
$BIN "$FIX" --no-cache >"$TMP/det_a.xml" 2>/dev/null
$BIN "$FIX" --no-cache >"$TMP/det_b.xml" 2>/dev/null
cmp -s "$TMP/det_a.xml" "$TMP/det_b.xml" \
    && ok "determinism: two --no-cache runs byte-identical" \
    || no "determinism: runs differ"
$BIN "$FIX" --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
$BIN "$FIX" --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
cmp -s "$TMP/cold" "$TMP/warm" \
    && ok "warm == cold" \
    || no "warm != cold"

echo
echo "=== mutation: rename the invoke target → the edge vanishes ==="
MUT="$TMP/mut"
mkdir -p "$MUT"
cp "$FIX/Decoy.smali" "$MUT/Decoy.smali"
sed 's/Lcom\/example\/A; -> addOne(I)I/Lcom\/example\/A;->addOneX(I)I/' "$FIX/A.smali" >"$MUT/A.smali"
$BIN "$MUT" --no-cache >"$TMP/mut.xml" 2>/dev/null
python3 - "$TMP/mut.xml" "$TWO" "$ONE" <<'PYEOF' >"$TMP/mut_check"
import sys, xml.etree.ElementTree as ET
xml_path, two, one = sys.argv[1:]
root = ET.parse(xml_path).getroot()
edge = False
for f in root.iter("f"):
    if not f.get("p", "").endswith("A.smali"):
        continue
    for s in f.findall("s"):
        if s.get("n") == two and any(c.get("n") == one for c in s.findall("c")):
            edge = True
print("EDGE_GONE:%s" % (not edge))
PYEOF
cat "$TMP/mut_check"
grep -q 'EDGE_GONE:True' "$TMP/mut_check" \
    && ok "mutation: renamed invoke target drops the addTwo -> addOne edge" \
    || no "mutation: the edge survived a renamed invoke target"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
