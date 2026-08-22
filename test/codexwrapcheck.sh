#!/usr/bin/env bash
# codexwrapcheck.sh — Codex setup stays CLI-first and restricts optional MCP to audit/health verbs.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "codexwrapcheck: no binary at $BIN — build first"; exit 2; }
"$BIN" wrap codex --force >"$TMP/out" 2>"$TMP/err"

first_command="$( grep -v '^#' "$TMP/out" | sed '/^[[:space:]]*$/d' | head -1 )"
[ "$first_command" = "[mcp_servers.ripwire]" ] || {
    echo "codexwrapcheck: first actionable line is not the restricted MCP table: $first_command"
    exit 1
}
grep -q '^\[mcp_servers\.ripwire\]$' "$TMP/out" || { echo "codexwrapcheck: TOML fallback missing"; exit 1; }
grep -q '^enabled_tools = \["analyze", "quality_delta", "flags", "doc_drift"\]$' "$TMP/out" \
    || { echo "codexwrapcheck: MCP is not restricted to audit/health verbs"; exit 1; }
grep -q '^default_tools_approval_mode = "approve"$' "$TMP/out" \
    || { echo "codexwrapcheck: audit-only MCP approval mode missing"; exit 1; }
grep -q '^bash skills/install\.sh --codex' "$TMP/out" || { echo "codexwrapcheck: canonical skill install missing"; exit 1; }
grep -q '^bash skills/install\.sh --codex --hook' "$TMP/out" || { echo "codexwrapcheck: Codex hook install missing"; exit 1; }
echo "codexwrapcheck: ALL PASS"
