#!/usr/bin/env bash
# opencodewrapcheck.sh — `ripwire wrap opencode` emits a config opencode actually READS.
#
# The failure mode this gate exists for is not a crash: it is a recipe that emits the
# familiar-but-wrong shape (the `mcpServers` stanza every other wrapped agent uses). That config
# parses, installs, looks right, and silently does nothing, because opencode's key is `mcp` and its
# entry carries `type` + a single `command` ARRAY. A grep-only gate cannot tell those apart, so this
# one parses the emitted JSON and checks it against opencode's own published schema.
#
# The schema is VENDORED at test/fixtures/opencode-config.schema.json (pinned; opencode ships
# releases multiple times a day and the published schema is unversioned with no $id). No gate in
# this tree reaches the network and G3 forbids host-installed dependencies, so conformance is
# checked by reading the pinned schema's own McpLocalConfig definition rather than by running a
# JSON Schema validator. Refresh the pin with test/tools/refresh-opencode-schema.sh (manual, never
# in CI) — a refreshed schema automatically re-tightens the assertions below.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN
SCHEMA="$ROOT/test/fixtures/opencode-config.schema.json"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]     || { echo "opencodewrapcheck: no binary at $BIN — build first"; exit 2; }
[ -f "$SCHEMA" ]  || { echo "opencodewrapcheck: missing pinned schema at $SCHEMA"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "opencodewrapcheck: python3 required"; exit 2; }

# ── 1. the agent is recognized at all ───────────────────────────────────────────────────────────
# runWrap's whitelist is a separate site from the emitter; an unlisted agent falls through to the
# generic `mcpServers` stanza with exit 2 — which would pass a naive "did it print JSON" check.
"$BIN" wrap opencode --force >"$TMP/out.txt" 2>"$TMP/err.txt"
rc=$?
if [ "$rc" = 0 ]; then
    ok "wrap opencode exits 0 (agent is in the recognized list)"
else
    no "wrap opencode exited $rc — opencode is not in runWrap's recognized-agent list"
    sed 's/^/        /' "$TMP/err.txt" | head -5
fi

# ── 2. the wrong-shape guard ────────────────────────────────────────────────────────────────────
# Scoped to EMITTED lines, not prose: the recipe's comments deliberately name the `mcpServers` shape
# to warn that opencode parses it and then ignores it. A `#` line saying so is the feature; the same
# string in the config body is the bug. (§3 re-checks this on the parsed object.)
if grep -v '^#' "$TMP/out.txt" | grep -q 'mcpServers'; then
    no "a non-comment line contains 'mcpServers' — that is the shape opencode IGNORES (silent no-op)"
else
    ok "no 'mcpServers' in any emitted (non-comment) line"
fi

# ── 3. extract + parse the JSON block, then check it against the pinned schema ───────────────────
# Block = the first line that is exactly '{' through the first subsequent line that is exactly '}'.
awk '/^\{$/{f=1} f{print} /^\}$/{if(f)exit}' "$TMP/out.txt" >"$TMP/cfg.json"
if [ ! -s "$TMP/cfg.json" ]; then
    no "no JSON object found in wrap opencode output"
else
    python3 - "$TMP/cfg.json" "$SCHEMA" >"$TMP/py.txt" 2>&1 <<'PY'
import json, sys

cfg_path, schema_path = sys.argv[1], sys.argv[2]
try:
    cfg = json.load( open( cfg_path ) )
except Exception as e:
    print( "FAIL emitted block is not valid JSON: %s" % e ); sys.exit( 0 )
print( "PASS emitted block parses as JSON" )

schema = json.load( open( schema_path ) )
local  = schema[ "$defs" ][ "McpLocalConfig" ]
allowed  = set( local[ "properties" ] )
required = set( local.get( "required", [] ) )

# top level: the key is `mcp`, and the schema must still agree that is where servers live
if "mcp" not in schema[ "$defs" ][ "Config" ][ "properties" ]:
    print( "FAIL pinned schema has no Config.properties.mcp — refresh changed the shape" ); sys.exit( 0 )
if "mcp" not in cfg:
    print( "FAIL emitted config has no top-level 'mcp' key" ); sys.exit( 0 )
print( "PASS top-level 'mcp' key present" )

if "mcpServers" in cfg:
    print( "FAIL config carries a 'mcpServers' key — opencode parses that and ignores it" ); sys.exit( 0 )
print( "PASS config carries no 'mcpServers' key" )

if cfg.get( "$schema" ) != "https://opencode.ai/config.json":
    print( "FAIL $schema is %r, expected https://opencode.ai/config.json" % cfg.get( "$schema" ) )
else:
    print( "PASS $schema line points at opencode's published schema" )

entry = cfg[ "mcp" ].get( "ripwire" )
if not isinstance( entry, dict ):
    print( "FAIL mcp.ripwire missing or not an object" ); sys.exit( 0 )

if entry.get( "type" ) != "local":
    print( "FAIL mcp.ripwire.type is %r, expected 'local'" % entry.get( "type" ) )
else:
    print( "PASS mcp.ripwire.type == 'local'" )

cmd = entry.get( "command" )
if not isinstance( cmd, list ) or not all( isinstance( x, str ) for x in cmd ):
    print( "FAIL command must be an ARRAY of strings (not a command/args pair), got %r" % ( cmd, ) )
elif cmd[ :1 ] != [ "ripwire" ] or "--mcp" not in cmd:
    print( "FAIL command %r does not invoke ripwire --mcp" % ( cmd, ) )
else:
    print( "PASS command is a string array invoking ripwire --mcp" )

# additionalProperties:false in the pinned schema — any stray key is a hard validation failure
extra = set( entry ) - allowed
if extra:
    print( "FAIL keys %s are not in McpLocalConfig (schema sets additionalProperties:false)" % sorted( extra ) )
else:
    print( "PASS every emitted key is allowed by the pinned McpLocalConfig" )

missing = required - set( entry )
if missing:
    print( "FAIL required McpLocalConfig keys missing: %s" % sorted( missing ) )
else:
    print( "PASS all schema-required keys present (%s)" % ", ".join( sorted( required ) ) )
PY
    while IFS= read -r line; do
        case "$line" in
            PASS*) ok "${line#PASS }" ;;
            *)     no "${line#FAIL }" ;;
        esac
    done < "$TMP/py.txt"
fi

# ── 4. the rules half — opencode reads AGENTS.md automatically ───────────────────────────────────
if grep -q '^# --- paste into AGENTS.md ---$' "$TMP/out.txt" && grep -q '^# --- end paste ---$' "$TMP/out.txt"; then
    ok "AGENTS.md context blurb is fenced and present"
else
    no "no AGENTS.md paste fence — kWrapBlurbTargets is missing its opencode row"
fi

# ── 5. CLI-first ordering — the recipe leads with the shell path, MCP is the alternative ─────────
# opencode has a bash tool, and the MCP server's 30 verb schemas are standing context every turn
# whether called or not (docs/EVALS.md §5). So the CLI line must come BEFORE the MCP stanza.
cli_line=$( grep -n -- '--for=' "$TMP/out.txt" | head -1 | cut -d: -f1 )
mcp_line=$( grep -n '"mcp"' "$TMP/out.txt" | head -1 | cut -d: -f1 )
if [ -n "$cli_line" ] && [ -n "$mcp_line" ] && [ "$cli_line" -lt "$mcp_line" ]; then
    ok "CLI recipe precedes the MCP stanza (line $cli_line < $mcp_line)"
else
    no "CLI recipe must precede the MCP stanza (cli=${cli_line:-none} mcp=${mcp_line:-none})"
fi

# ── 6. determinism (house contract) ─────────────────────────────────────────────────────────────
"$BIN" wrap opencode --force >"$TMP/out2.txt" 2>/dev/null
if cmp -s "$TMP/out.txt" "$TMP/out2.txt"; then
    ok "two runs byte-identical"
else
    no "wrap opencode is not deterministic across runs"
fi

# ── 7. the pin itself ───────────────────────────────────────────────────────────────────────────
# Recorded so a silent fixture edit is visible in review; refresh via test/tools/refresh-opencode-schema.sh.
want="dcd450a9a5ff40d2b73f821b39c1885fad849c73ae738e59f318e51d44e28728"
got=$( shasum -a 256 "$SCHEMA" 2>/dev/null | awk '{print $1}' )
if [ -z "$got" ]; then
    got=$( sha256sum "$SCHEMA" 2>/dev/null | awk '{print $1}' )
fi
if [ "$got" = "$want" ]; then
    ok "pinned schema sha256 matches the recorded pin"
else
    no "pinned schema changed (sha256 $got != $want) — update the pin AND re-read the assertions above"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
