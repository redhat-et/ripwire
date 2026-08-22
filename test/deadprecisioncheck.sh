#!/usr/bin/env bash
# deadprecisioncheck.sh — A5 high-confidence internal-linkage dead-code gate.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/deadfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

"$BIN" "$CORPUS" --dead-code --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --dead-code --no-cache >"$TMP/b" 2>/dev/null
diff -q "$TMP/a" "$TMP/b" >/dev/null || { echo "FAIL dead-code output is not deterministic"; exit 1; }

python3 - "$TMP/a" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
if root.get("confidence") != "high":
    raise SystemExit("FAIL dead-code default must disclose confidence=high")
if root.get("evidence") != "internal-linkage+zero-callers":
    raise SystemExit("FAIL dead-code default must qualify its graph evidence")

names = [node.get("n") for node in root.findall("d")]
if names != ["orphan"] or root.get("count") != "1":
    raise SystemExit(f"FAIL expected only internal static orphan, found {names}")

print("PASS high-confidence internal-only dead candidate=orphan")
PY
