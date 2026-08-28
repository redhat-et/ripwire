#!/usr/bin/env bash
# codexinstallhonestycheck.sh — D1: skills/install.sh must never claim "done. Registered ..." and
# exit 0 when the jq merge into hooks.json / settings.json actually failed.
#
# Verified red on 1dc7b01 (both install_codex_hook AND install_claude_hook share the identical shape:
# `jq ... "$settings" >"$tmp" && mv "$tmp" "$settings"` followed by an UNCONDITIONAL success echo and
# exit 0): write an unparseable hooks.json/settings.json, run the installer, and the old script printed
# "done. Registered ..." on stdout, exited 0, and left `jq: parse error` as the only diagnostic on
# stderr — while the merge silently did nothing. The original file survives (mv is &&-gated on jq
# success), so data is safe, but the SUCCESS CLAIM is false: the user believes routing/nudging is live
# and the session silently gets none.
#
# This gate asserts, for both the --codex --hook and the (Claude) --hook paths, against a corrupt
# hooks.json/settings.json:
#   (a) the target file is byte-unchanged,
#   (b) stdout never claims "Registered",
#   (c) the installer exits non-zero,
#   (d) the actual jq diagnostic still reaches stderr (nothing is silently swallowed).
#
# Usage:  test/codexinstallhonestycheck.sh   |   RIPWIRE_BIN=build/ripwire test/codexinstallhonestycheck.sh
# Fully hermetic: every run gets its own mktemp -d HOME/CODEX_HOME/AGENTS_HOME; nothing here ever
# touches the operator's real ~/.claude, ~/.codex, ~/.agents or ~/.ripwire. Exits non-zero on any
# failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
: "$BIN"   # unused by this gate (install.sh needs no ripwire binary), kept for the shared convention
INSTALL="$ROOT/skills/install.sh"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -f "$INSTALL" ] || { echo "no $INSTALL"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "codexinstallhonestycheck.sh needs jq on PATH"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORRUPT='{ this is : not valid json ,,,'

# Captured BEFORE any HOME/CODEX_HOME/AGENTS_HOME override below, so these name the OPERATOR's real
# dotfiles, never the sandbox — the canary in (4) proves none of this gate's runs touched them.
REAL_CODEX_HOOKS="${CODEX_HOME:-$HOME/.codex}/hooks.json"
REAL_CLAUDE_SETTINGS="$HOME/.claude/settings.json"
REAL_CODEX_SUM="$( [ -f "$REAL_CODEX_HOOKS" ] && cksum "$REAL_CODEX_HOOKS" 2>/dev/null || echo absent )"
REAL_CLAUDE_SUM="$( [ -f "$REAL_CLAUDE_SETTINGS" ] && cksum "$REAL_CLAUDE_SETTINGS" 2>/dev/null || echo absent )"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# (1) --codex --hook against a corrupt hooks.json
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
CODEX_HOME="$TMP/codexhome"; mkdir -p "$CODEX_HOME"
printf '%s' "$CORRUPT" >"$CODEX_HOME/hooks.json"
cp "$CODEX_HOME/hooks.json" "$TMP/codex-orig.json"

CLAUDE_FALLBACK="$TMP/codex-run-home"; AGENTS_HOME_1="$TMP/codex-run-agents"
OUT1="$( HOME="$CLAUDE_FALLBACK" AGENTS_HOME="$AGENTS_HOME_1" CODEX_HOME="$CODEX_HOME" \
    bash "$INSTALL" --codex --hook 2>"$TMP/codex-err1" )"
RC1=$?
echo "-- --codex --hook against corrupt hooks.json (stdout) --"; echo "$OUT1"
echo "-- stderr --"; cat "$TMP/codex-err1"
echo "(exit=$RC1)"

if diff -q "$TMP/codex-orig.json" "$CODEX_HOME/hooks.json" >/dev/null 2>&1; then
    ok "codex: hooks.json is byte-unchanged after a failed merge"
else
    no "codex: hooks.json was modified despite the jq parse error"
fi
printf '%s' "$OUT1" | grep -qi 'registered' \
    && no "codex: stdout claims \"Registered\" despite the merge failing" \
    || ok "codex: stdout does not claim success"
[ "$RC1" -ne 0 ] && ok "codex: installer exits non-zero on merge failure (rc=$RC1)" \
    || no "codex: installer exited 0 despite the merge failing"
grep -qi 'parse error' "$TMP/codex-err1" \
    && ok "codex: the jq parse-error diagnostic still reaches stderr" \
    || no "codex: jq's diagnostic went missing from stderr"
grep -qi 'nothing changed' "$TMP/codex-err1" \
    && ok "codex: the refusal explicitly says nothing changed" \
    || no "codex: no explicit \"nothing changed\" refusal on stderr"

# sanity/positive-control: the SAME installer, against VALID json, still succeeds and claims so —
# otherwise this gate could pass by making the installer permanently unable to report success at all.
CODEX_HOME_OK="$TMP/codexhome-ok"; mkdir -p "$CODEX_HOME_OK"
echo '{}' >"$CODEX_HOME_OK/hooks.json"
OUT1B="$( HOME="$TMP/codex-run-home-ok" AGENTS_HOME="$TMP/codex-run-agents-ok" CODEX_HOME="$CODEX_HOME_OK" \
    bash "$INSTALL" --codex --hook 2>&1 )"
RC1B=$?
[ "$RC1B" -eq 0 ] && printf '%s' "$OUT1B" | grep -qi 'registered' \
    && ok "codex positive control: valid hooks.json still merges and reports success (rc=0)" \
    || no "codex positive control: valid-JSON run failed too (rc=$RC1B) — gate would pass for the wrong reason"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# (2) --hook (Claude, default client) against a corrupt settings.json
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
CLAUDE_HOME_ROOT="$TMP/claudehome"; mkdir -p "$CLAUDE_HOME_ROOT/.claude"
printf '%s' "$CORRUPT" >"$CLAUDE_HOME_ROOT/.claude/settings.json"
cp "$CLAUDE_HOME_ROOT/.claude/settings.json" "$TMP/claude-orig.json"

OUT2="$( HOME="$CLAUDE_HOME_ROOT" AGENTS_HOME="$TMP/claude-run-agents" \
    bash "$INSTALL" --hook 2>"$TMP/claude-err2" )"
RC2=$?
echo "-- --hook (Claude) against corrupt settings.json (stdout) --"; echo "$OUT2"
echo "-- stderr --"; cat "$TMP/claude-err2"
echo "(exit=$RC2)"

if diff -q "$TMP/claude-orig.json" "$CLAUDE_HOME_ROOT/.claude/settings.json" >/dev/null 2>&1; then
    ok "claude: settings.json is byte-unchanged after a failed merge"
else
    no "claude: settings.json was modified despite the jq parse error"
fi
printf '%s' "$OUT2" | grep -qi 'registered' \
    && no "claude: stdout claims \"Registered\" despite the merge failing" \
    || ok "claude: stdout does not claim success"
[ "$RC2" -ne 0 ] && ok "claude: installer exits non-zero on merge failure (rc=$RC2)" \
    || no "claude: installer exited 0 despite the merge failing"
grep -qi 'parse error' "$TMP/claude-err2" \
    && ok "claude: the jq parse-error diagnostic still reaches stderr" \
    || no "claude: jq's diagnostic went missing from stderr"

# ── (3) --claude --hook (explicit-mode path through the SAME function) against corrupt settings.json ──
CLAUDE_HOME_ROOT2="$TMP/claudehome2"; mkdir -p "$CLAUDE_HOME_ROOT2/.claude"
printf '%s' "$CORRUPT" >"$CLAUDE_HOME_ROOT2/.claude/settings.json"
cp "$CLAUDE_HOME_ROOT2/.claude/settings.json" "$TMP/claude-orig2.json"
OUT3="$( HOME="$CLAUDE_HOME_ROOT2" AGENTS_HOME="$TMP/claude-run-agents2" \
    bash "$INSTALL" --claude --hook 2>"$TMP/claude-err3" )"
RC3=$?
if diff -q "$TMP/claude-orig2.json" "$CLAUDE_HOME_ROOT2/.claude/settings.json" >/dev/null 2>&1 \
    && ! printf '%s' "$OUT3" | grep -qi 'registered' && [ "$RC3" -ne 0 ]; then
    ok "--claude --hook (explicit mode): unchanged file, no false success claim, exit $RC3"
else
    no "--claude --hook (explicit mode): unchanged=$( diff -q "$TMP/claude-orig2.json" "$CLAUDE_HOME_ROOT2/.claude/settings.json" >/dev/null 2>&1 && echo yes || echo no ) rc=$RC3 out=[$OUT3]"
fi

# positive control for the Claude path too
CLAUDE_HOME_OK="$TMP/claudehome-ok"; mkdir -p "$CLAUDE_HOME_OK/.claude"
echo '{}' >"$CLAUDE_HOME_OK/.claude/settings.json"
OUT2B="$( HOME="$CLAUDE_HOME_OK" AGENTS_HOME="$TMP/claude-run-agents-ok" bash "$INSTALL" --hook 2>&1 )"
RC2B=$?
[ "$RC2B" -eq 0 ] && printf '%s' "$OUT2B" | grep -qi 'registered' \
    && ok "claude positive control: valid settings.json still merges and reports success (rc=0)" \
    || no "claude positive control: valid-JSON run failed too (rc=$RC2B) — gate would pass for the wrong reason"

# ── (4) hermeticity canary: none of the above ever touched a REAL dotfile ──────────────────────────
# Every run above passed its OWN HOME/CODEX_HOME/AGENTS_HOME (all fresh mktemp -d paths under $TMP), so
# none of them should have gone anywhere near $REAL_CODEX_HOOKS / $REAL_CLAUDE_SETTINGS. Re-checked by
# content, not just existence, so a run that appended to (rather than replaced) the real file still trips it.
AFTER_CODEX_SUM="$( [ -f "$REAL_CODEX_HOOKS" ] && cksum "$REAL_CODEX_HOOKS" 2>/dev/null || echo absent )"
AFTER_CLAUDE_SUM="$( [ -f "$REAL_CLAUDE_SETTINGS" ] && cksum "$REAL_CLAUDE_SETTINGS" 2>/dev/null || echo absent )"
[ "$REAL_CODEX_SUM" = "$AFTER_CODEX_SUM" ] \
    && ok "hermetic: operator's real $REAL_CODEX_HOOKS untouched (cksum unchanged: $REAL_CODEX_SUM)" \
    || no "hermetic VIOLATION: operator's real $REAL_CODEX_HOOKS changed ($REAL_CODEX_SUM -> $AFTER_CODEX_SUM)"
[ "$REAL_CLAUDE_SUM" = "$AFTER_CLAUDE_SUM" ] \
    && ok "hermetic: operator's real $REAL_CLAUDE_SETTINGS untouched (cksum unchanged: $REAL_CLAUDE_SUM)" \
    || no "hermetic VIOLATION: operator's real $REAL_CLAUDE_SETTINGS changed ($REAL_CLAUDE_SUM -> $AFTER_CLAUDE_SUM)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
