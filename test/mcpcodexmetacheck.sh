#!/usr/bin/env bash
# mcpcodexmetacheck.sh — Codex-facing MCP metadata must describe the shared workflow and side effects.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "mcpcodexmetacheck: no binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "mcpcodexmetacheck: python3 required"; exit 2; }

printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
    | "$BIN" --mcp 2>/dev/null >"$TMP/mcp.jsonl"

python3 - "$TMP/mcp.jsonl" <<'PY'
import json
import sys

rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
assert len(rows) == 2, f"expected initialize + tools/list, got {len(rows)} rows"

init = rows[0]["result"]
instructions = init.get("instructions", "")
required = ("explore", "from_trace", "edit_check", "quality_delta", "batch")
missing = [word for word in required if word not in instructions[:512]]
assert not missing, f"initialize instructions first 512 chars missing {missing}: {instructions[:512]!r}"

tools = rows[1]["result"]["tools"]
assert len(tools) == 31, f"expected 31 advertised tools, got {len(tools)}"
write_tools = {"quality_baseline", "replace_symbol_body", "insert_before_symbol", "insert_after_symbol"}
destructive_tools = {"replace_symbol_body"}
for tool in tools:
    name = tool["name"]
    ann = tool.get("annotations")
    assert isinstance(ann, dict), f"{name}: annotations missing"
    assert ann.get("readOnlyHint") is (name not in write_tools), f"{name}: wrong readOnlyHint"
    assert ann.get("destructiveHint") is (name in destructive_tools), f"{name}: wrong destructiveHint"
    assert ann.get("openWorldHint") is False, f"{name}: openWorldHint must be false"

print("mcpcodexmetacheck: ALL PASS")
PY
