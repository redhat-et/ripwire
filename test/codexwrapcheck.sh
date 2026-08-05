#!/usr/bin/env bash
# codexwrapcheck.sh — Codex setup leads with the supported CLI command and retains a TOML fallback.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "codexwrapcheck: no binary at $BIN — build first"; exit 2; }
"$BIN" wrap codex --force >"$TMP/out" 2>"$TMP/err"

first_command="$( grep -v '^#' "$TMP/out" | sed '/^[[:space:]]*$/d' | head -1 )"
[ "$first_command" = "codex mcp add ripwire -- ripwire --mcp" ] || {
    echo "codexwrapcheck: first actionable line is not the Codex CLI command: $first_command"
    exit 1
}
grep -q '^\[mcp_servers\.ripwire\]$' "$TMP/out" || { echo "codexwrapcheck: TOML fallback missing"; exit 1; }
grep -q '^bash skills/install\.sh --codex' "$TMP/out" || { echo "codexwrapcheck: canonical skill install missing"; exit 1; }
echo "codexwrapcheck: ALL PASS"
