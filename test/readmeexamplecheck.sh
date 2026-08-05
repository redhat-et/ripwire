#!/usr/bin/env bash
# readmeexamplecheck.sh — README's advertised callers example must match the current binary's paths.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "readmeexamplecheck: no binary at $BIN — build first"; exit 2; }
( cd "$ROOT" && "$BIN" . --callers=rankGraphTeleport --no-cache ) >"$TMP/live"

python3 - "$ROOT/README.md" "$TMP/live" <<'PY'
import re
import sys

readme = open(sys.argv[1], encoding="utf-8").read()
live = open(sys.argv[2], encoding="utf-8").read()
rows = re.findall(r'<s t="[^"]+" n="([^"]+)" p="([^"]+)"/>', live)
assert rows, "live callers command returned no rows"
missing = []
for name, path in rows:
    rendered = f'<s t="fn" n="{name}" p="{path}"/>'
    if rendered not in readme:
        missing.append(rendered)
assert not missing, "README callers example has stale/missing rows:\n" + "\n".join(missing)
print("readmeexamplecheck: ALL PASS")
PY
