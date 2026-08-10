#!/usr/bin/env bash
# refresh-opencode-schema.sh — MANUAL, NEVER IN CI.
#
# test/opencodewrapcheck.sh validates `ripwire wrap opencode` against a VENDORED copy of opencode's
# published config schema. This script is how that copy gets refreshed. It is deliberately not a
# gate and is deliberately not called by test/regression.sh:
#
#   * no gate in this tree reaches the outside network (the only curl in test/ is mcpremotecheck.sh
#     against 127.0.0.1), and a gate that fetches a live URL is flaky by construction;
#   * the published schema is UNVERSIONED — no $id, no version field — and opencode ships releases
#     multiple times a day, so "current" is not a reproducible input to a deterministic build (G3).
#
# It prints a diff and the new sha256. It does NOT overwrite the pin, and it does NOT edit the gate:
# a human reads the diff, decides whether the emitter must change, then updates BOTH the fixture and
# the `want=` sha256 in test/opencodewrapcheck.sh in the same commit.
#
# Usage:  bash test/tools/refresh-opencode-schema.sh
set -u

URL="https://opencode.ai/config.json"
ROOT="$( cd "$( dirname "$0" )/../.." && pwd )"
PINNED="$ROOT/test/fixtures/opencode-config.schema.json"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

command -v curl    >/dev/null 2>&1 || { echo "refresh: curl required";    exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "refresh: python3 required"; exit 2; }
[ -f "$PINNED" ] || { echo "refresh: no pinned copy at $PINNED"; exit 2; }

echo "fetching $URL ..."
if ! curl -fsSL --max-time 30 "$URL" -o "$TMP/live.json"; then
    echo "refresh: fetch failed — nothing changed"
    exit 1
fi

if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/live.json"; then
    echo "refresh: fetched document is not valid JSON — nothing changed"
    exit 1
fi

sha_of(){ shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' || sha256sum "$1" | awk '{print $1}'; }

if cmp -s "$PINNED" "$TMP/live.json"; then
    echo "unchanged — pin is current (sha256 $( sha_of "$PINNED" ))"
    exit 0
fi

echo
echo "=== the pinned copy is STALE. Structural diff of the MCP definitions: ==="
python3 - "$PINNED" "$TMP/live.json" <<'PY'
import json, sys

old = json.load( open( sys.argv[1] ) )
new = json.load( open( sys.argv[2] ) )

def local( doc ):
    return doc.get( "$defs", {} ).get( "McpLocalConfig", {} )

o, n = local( old ), local( new )
op, np = set( o.get( "properties", {} ) ), set( n.get( "properties", {} ) )
orq, nrq = set( o.get( "required", [] ) ), set( n.get( "required", [] ) )

print( "  McpLocalConfig properties added:   %s" % ( sorted( np - op ) or "none" ) )
print( "  McpLocalConfig properties removed: %s" % ( sorted( op - np ) or "none" ) )
print( "  required added:                    %s" % ( sorted( nrq - orq ) or "none" ) )
print( "  required removed:                  %s" % ( sorted( orq - nrq ) or "none" ) )
print( "  additionalProperties:              %r -> %r"
       % ( o.get( "additionalProperties" ), n.get( "additionalProperties" ) ) )

cfg_old = set( old.get( "$defs", {} ).get( "Config", {} ).get( "properties", {} ) )
cfg_new = set( new.get( "$defs", {} ).get( "Config", {} ).get( "properties", {} ) )
if "mcp" not in cfg_new:
    print( "  *** Config.properties.mcp IS GONE — the top-level key changed. wrap opencode is WRONG. ***" )
print( "  Config keys added:                 %s" % ( sorted( cfg_new - cfg_old ) or "none" ) )
print( "  Config keys removed:               %s" % ( sorted( cfg_old - cfg_new ) or "none" ) )
PY

echo
echo "=== to adopt ==="
echo "  cp '$TMP/live.json' '$PINNED'      # (copy now, before this script's temp dir is cleaned)"
echo "  new sha256: $( sha_of "$TMP/live.json" )"
echo "  then update want= in test/opencodewrapcheck.sh and re-run it."
exit 1
