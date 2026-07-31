#!/usr/bin/env bash
# wrapverbscheck.sh — A4-S2 drift gate: `ctxpack wrap claude` must mention EVERY verb name the
# live MCP server actually serves via tools/list, and must point at skills/install.sh. Without
# this gate, a new MCP verb can ship (tools/list grows) without ever appearing in the wrap
# recipe — the only portable adoption surface silently goes stale (exactly what A4-S2 found: 10
# of 21 verbs listed, no install.sh line).
#
# Flow (mirrors test/mcpverbscheck.sh's JSON-RPC-over-stdin pattern):
#   1. Start the MCP server, send initialize + tools/list, extract every tool "name".
#   2. Run `ctxpack wrap claude`.
#   3. Assert every live verb name appears in the wrap output (word-boundary match, so e.g.
#      "for" doesn't false-positive on "before").
#   4. Assert the wrap output names skills/install.sh.
#
# Usage:
#   test/wrapverbscheck.sh                          # uses build/ctxpack
#   CTXPACK_BIN=build_w3i/ctxpack test/wrapverbscheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "wrapverbscheck: BIN=$BIN"

mcp_call() {
    printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null
}

echo
echo "=== 1. tools/list — collect every live verb name ==="

LIST_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 )"

python3 -c '
import sys, json
resp = json.loads(sys.argv[1])
if "error" in resp:
    print("__ERROR__:" + json.dumps(resp["error"]))
    sys.exit(0)
for t in resp["result"]["tools"]:
    print(t["name"])
' "$LIST_OUT" >"$TMP/live_verbs"

if head -1 "$TMP/live_verbs" | grep -q '^__ERROR__'; then
    echo "$( cat "$TMP/live_verbs" )"
    no "tools/list returned an error — cannot enumerate live verbs"
    echo; echo "SOME CHECKS FAILED"; exit 1
fi

LIVE_COUNT="$( wc -l <"$TMP/live_verbs" | tr -d ' ' )"
[ "$LIVE_COUNT" -gt 0 ] && ok "tools/list returned $LIVE_COUNT verb(s)" || no "tools/list returned zero verbs"

echo
echo "=== 2. ctxpack wrap claude — verb coverage ==="

WRAP_OUT="$( "$BIN" wrap claude 2>&1 )"

missing=0
while IFS= read -r verb; do
    [ -n "$verb" ] || continue
    # word-boundary match: "for" must not match inside "before"/"forgotten" etc.
    if echo "$WRAP_OUT" | grep -qE "(^|[^A-Za-z0-9_])${verb}([^A-Za-z0-9_]|\$)"; then
        ok "wrap claude mentions verb '$verb'"
    else
        no "wrap claude is MISSING verb '$verb' (shipped in tools/list, absent from the recipe — A4-S2 regression)"
        missing=$(( missing + 1 ))
    fi
done <"$TMP/live_verbs"

[ "$missing" -eq 0 ] && ok "all $LIVE_COUNT live verbs are mentioned in 'ctxpack wrap claude'" \
                     || no "$missing live verb(s) missing from 'ctxpack wrap claude'"

echo
echo "=== 3. skills/install.sh line present ==="

if echo "$WRAP_OUT" | grep -q 'skills/install\.sh'; then
    ok "wrap claude names skills/install.sh"
else
    no "wrap claude does NOT mention skills/install.sh — the skill-adoption step is invisible"
fi

echo
echo "=== 4. wrap --all with fake agent config dirs ==="

# Create a temporary HOME with two agent config directories
TEST_HOME="$TMP/test_home"
mkdir -p "$TEST_HOME/.claude" "$TEST_HOME/.codex"

# Run wrap --all with HOME redirected
WRAP_ALL_OUT="$( HOME="$TEST_HOME" "$BIN" wrap --all 2>&1 )"

# Check that both agents are mentioned
if echo "$WRAP_ALL_OUT" | grep -q 'claude'; then
    ok "wrap --all includes claude"
else
    no "wrap --all missing claude configuration"
fi

if echo "$WRAP_ALL_OUT" | grep -q 'codex'; then
    ok "wrap --all includes codex"
else
    no "wrap --all missing codex configuration"
fi

# aider is always available (doesn't need a config dir)
if echo "$WRAP_ALL_OUT" | grep -q 'aider'; then
    ok "wrap --all includes aider (always available)"
else
    no "wrap --all missing aider configuration"
fi

# Check that summary line is present and correct (claude + codex + aider = 3 configured, cursor/windsurf/gemini = 3 skipped)
if echo "$WRAP_ALL_OUT" | grep -q 'summary: 3 surfaces configured'; then
    ok "wrap --all summary line correct (3 surfaces: claude, codex, aider)"
else
    no "wrap --all summary line incorrect or missing"
fi

# Check that agents not detected are skipped
if echo "$WRAP_ALL_OUT" | grep -q 'skipped'; then
    ok "wrap --all mentions skipped agents"
else
    no "wrap --all does not mention skipped agents"
fi

# Det-gate: run twice and verify output is identical
WRAP_ALL_OUT2="$( HOME="$TEST_HOME" "$BIN" wrap --all 2>&1 )"
if [ "$WRAP_ALL_OUT" = "$WRAP_ALL_OUT2" ]; then
    ok "wrap --all output is deterministic (byte-identical on two runs)"
else
    no "wrap --all output is NOT deterministic"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
