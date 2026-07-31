#!/usr/bin/env bash
# lintprecisioncheck.sh — A5 numeric semantics and pagination-honesty gate.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXTURE="$TMP/fixture"
mkdir -p "$FIXTURE"

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

cat >"$FIXTURE/numeric.cpp" <<'CPP'
int numericContexts( int n )
{
    double zero = 0.0;
    float one = 1.0f;
    double two = 2.0;
    int minusOne = -1;
    unsigned mask = unsigned( n ) & 0x80;
    int realFinding = n * 42;
    return int( zero + one + two ) + minusOne + int( mask ) + realFinding;
}
CPP

"$BIN" "$FIXTURE" --lint --no-cache >"$TMP/numeric.a" 2>/dev/null
"$BIN" "$FIXTURE" --lint --no-cache >"$TMP/numeric.b" 2>/dev/null
diff -q "$TMP/numeric.a" "$TMP/numeric.b" >/dev/null || { echo "FAIL numeric lint is not deterministic"; exit 1; }

"$BIN" "$ROOT/src" --lint --limit=3 --offset=0 --no-cache >"$TMP/page1" 2>/dev/null
"$BIN" "$ROOT/src" --lint --limit=3 --offset=3 --no-cache >"$TMP/page2" 2>/dev/null
# "full" must be a limit no real corpus can reach: src/ crossed 1000 findings once §P0.2 gave each rule its
# own budget (664 → 1175), and a "full" page that silently truncates makes the seam assertions vacuous.
"$BIN" "$ROOT/src" --lint --limit=1000000 --offset=0 --no-cache >"$TMP/full" 2>/dev/null
"$BIN" "$ROOT/src" --lint --no-cache >"$TMP/default" 2>/dev/null

python3 - "$TMP/numeric.a" "$TMP/page1" "$TMP/page2" "$TMP/full" "$TMP/default" <<'PY'
import sys
import xml.etree.ElementTree as ET

numeric_path, page1_path, page2_path, full_path, default_path = sys.argv[1:]

numeric = ET.parse(numeric_path).getroot()
magic = [node for node in numeric.findall("f") if node.get("rule") == "magic-number"]
if len(magic) != 1 or magic[0].text != "42":
    found = [(node.text, node.get("p")) for node in magic]
    raise SystemExit(f"FAIL expected exactly one semantic magic number 42, found {found}")

roots = [ET.parse(path).getroot() for path in (page1_path, page2_path, full_path, default_path)]
page1, page2, full, default = roots
required = ("shown", "total", "has_more", "next_offset", "offset", "limit")
for page in (page1, page2, full):
    missing = [name for name in required if page.get(name) is None]
    if missing:
        raise SystemExit(f"FAIL paginated lint missing honesty attrs {missing}")
    if int(page.get("shown")) != len(page.findall("f")):
        raise SystemExit("FAIL lint shown does not equal emitted finding count")

if int(page1.get("shown")) != 3 or page1.get("has_more") != "1" or page1.get("next_offset") != "3":
    raise SystemExit("FAIL first lint page has dishonest shown/has_more/next_offset")
if page1.get("total") != page2.get("total") or page1.get("total") != full.get("total"):
    raise SystemExit("FAIL lint total changed across pages")

def rows(root):
    return [ET.tostring(node, encoding="unicode") for node in root.findall("f")]

if rows(page1) + rows(page2) != rows(full)[:6]:
    raise SystemExit("FAIL lint page seam dropped, duplicated, or reordered findings")
if any(default.get(name) is not None for name in required):
    raise SystemExit("FAIL default lint leaked pagination attrs; legacy schema must stay byte-neutral")
if len(rows(default)) != int(default.get("findings", "-1")) or rows(default) != rows(full):
    raise SystemExit("FAIL default lint hides a row cap instead of emitting the advertised full result")

print(f"PASS magic=1 shown={page1.get('shown')} total={page1.get('total')}")
PY
