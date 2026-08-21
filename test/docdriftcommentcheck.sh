#!/usr/bin/env bash
# docdriftcommentcheck.sh — comment text never becomes a live corpus value fact.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXTURE="$TMP/fixture"
mkdir -p "$FIXTURE"

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

cat >"$FIXTURE/README.md" <<'MD'
# Comment precision

- `kLineComment` = 4.
- `kBlockComment` = 5.
- `kRealLimit` = 6.
MD

cat >"$FIXTURE/values.cpp" <<'CPP'
// constexpr int kLineComment = 40;
/*
constexpr int kBlockComment = 50;
*/
constexpr int kRealLimit = 7;
CPP

"$BIN" "$FIXTURE" --doc-drift --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIXTURE" --doc-drift --no-cache >"$TMP/b" 2>/dev/null
cmp -s "$TMP/a" "$TMP/b" || { echo "FAIL doc-drift comment output is not deterministic"; exit 1; }

python3 - "$TMP/a" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
rows = root.findall("./doc/a")

comment_names = {"kLineComment", "kBlockComment"}
leaked = [row.attrib for row in rows if any(name in row.get("ref", "") for name in comment_names)]
if leaked:
    raise SystemExit(f"FAIL C/C++ comment text became live value facts: {leaked}")

control = [row for row in rows if "kRealLimit" in row.get("ref", "")]
if len(control) != 1 or control[0].get("why") != "const-value" or control[0].get("got") != "7" or control[0].get("tgt") != "values.cpp:5":
    detail = [row.attrib for row in control]
    raise SystemExit(f"FAIL real declaration control was not harvested: {detail}")

if root.get("prose") != "2":
    raise SystemExit(f"FAIL expected two comment-only claims to become prose, got prose={root.get('prose')}")

print("PASS line/block comments ignored and real declaration retained")
PY
