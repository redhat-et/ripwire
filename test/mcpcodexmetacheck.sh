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
assert len(tools) == 33, f"expected 33 advertised tools, got {len(tools)}"
write_tools = {"quality_baseline", "replace_symbol_body", "insert_before_symbol", "insert_after_symbol"}
destructive_tools = {"replace_symbol_body"}
append_tools = {"insert_before_symbol", "insert_after_symbol"}
titles = []
for tool in tools:
    name = tool["name"]
    ann = tool.get("annotations")
    assert isinstance(ann, dict), f"{name}: annotations missing"
    assert ann.get("readOnlyHint") is (name not in write_tools), f"{name}: wrong readOnlyHint"
    assert ann.get("destructiveHint") is (name in destructive_tools), f"{name}: wrong destructiveHint"
    assert ann.get("openWorldHint") is False, f"{name}: openWorldHint must be false"
    # MCP 2025-06-18 / audit 2026-11-26 item 8, OWNER RULING 2026-11-26: idempotentHint rides only the WRITE tools, the
    # spec calling it meaningful only when readOnlyHint is false (a read is idempotent by construction, and the 29 copies
    # cost 638 B a session). quality_baseline rewrites the same sidecar for the same HEAD and replace_symbol_body splices
    # the same body over the same span, so a repeat has no further effect; the two inserts insert AGAIN on every call.
    if name in write_tools:
        assert ann.get("idempotentHint") is (name not in append_tools), f"{name}: wrong idempotentHint {ann.get('idempotentHint')!r}"
    else:
        assert "idempotentHint" not in ann, f"{name}: a read-only tool carries idempotentHint (the spec: meaningful only when readOnlyHint is false)"
    # `title` (2025-06-18, the display name a host shows instead of the snake_case name)
    title = tool.get("title")
    assert isinstance(title, str) and 0 < len(title) <= 32 and title != name, f"{name}: title missing or not a display name: {title!r}"
    titles.append(title)

assert len(set(titles)) == len(titles), f"two tools share a title: {sorted(t for t in titles if titles.count(t) > 1)}"

print("mcpcodexmetacheck: ALL PASS")
PY
