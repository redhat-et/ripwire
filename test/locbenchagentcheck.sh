#!/usr/bin/env bash
# locbenchagentcheck.sh — the placebo round's agent driver, bench/locbench/agent_loc.py
# (bench/locbench/PREREG_PLACEBO.md "Agent driver contract").
#
# WHY THIS GATE EXISTS. The prereg froze the driver's contract before the driver existed, so the driver cannot be
# fitted to a result. Every clause is checked here with fixtures, a scripted stub model and a fake `claude`
# executable — no network, no model, no token:
#   * payloads only from the seal: sha256 + bytes verified per episode; a broken seal refuses BEFORE any call;
#   * ripwire is not on the child PATH (a planted ripwire dir AND this gate's BIN dir are stripped), the child
#     runs in an empty cwd with no built-in tools, no settings, no MCP;
#   * grep/read over git-tracked files only, 8,000-byte cap with the cut disclosed, no escape from the checkout;
#   * 15 turns, the 250,000-input-token guard, a no-submit episode is a counted miss;
#   * the record names model, resolved_model (from the provider trailer), arm, seed, credential NAME, tokens split
#     by cache category (None when unreported, never 0), tool calls by kind, and saves a transcript;
#   * pilot selection is TRAIN-only round-robin; the prereg's power arithmetic reproduces; main() refuses a
#     held-out instance without --allow-heldout.
# Red on the base commit by construction: agent_loc.py did not exist there (ImportError -> exit 1).
set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "BIN=$BIN $( "$BIN" --version 2>/dev/null | head -1 )"
command -v python3 >/dev/null 2>&1 || { echo "locbenchagentcheck: python3 required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "locbenchagentcheck: git required"; exit 2; }
[ -x "$BIN" ] || { echo "locbenchagentcheck: no ripwire binary at $BIN — build first"; exit 2; }
python3 "$ROOT/bench/locbench/test_agent_loc.py" "$BIN"
