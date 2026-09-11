#!/usr/bin/env bash
# codexplugincheck.sh — the repository root is a self-contained Codex plugin bundle.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
MANIFEST="$ROOT/.codex-plugin/plugin.json"
MCP="$ROOT/.mcp.json"

command -v python3 >/dev/null 2>&1 || { echo "codexplugincheck: python3 required"; exit 2; }
[ -f "$MANIFEST" ] || { echo "codexplugincheck: missing $MANIFEST"; exit 1; }
[ -f "$MCP" ] || { echo "codexplugincheck: missing $MCP"; exit 1; }

python3 - "$ROOT" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
manifest = json.loads((root / ".codex-plugin/plugin.json").read_text())
mcp = json.loads((root / ".mcp.json").read_text())

assert manifest["name"] == "ripwire"
assert re.fullmatch(r"\d+\.\d+\.\d+", manifest["version"]), manifest["version"]
assert manifest["skills"] == "./skills/"
assert manifest["mcpServers"] == "./.mcp.json"
assert manifest["license"] == "Apache-2.0"
assert "codex" in manifest["keywords"] and "openai-codex" in manifest["keywords"]

server = mcp.get("mcpServers", {}).get("ripwire")
assert server == {"command": "ripwire", "args": ["--mcp"]}, server

skills = sorted((root / "skills").glob("ripwire-*/SKILL.md"))
assert len(skills) == 17, f"expected 17 bundled skills, got {len(skills)}"
print("codexplugincheck: ALL PASS")
PY
