#!/usr/bin/env bash
# wrapverbscheck.sh — A4-S2 drift gate: `ripwire wrap claude` must mention EVERY verb name the
# live MCP server actually serves via tools/list, and must point at skills/install.sh. Without
# this gate, a new MCP verb can ship (tools/list grows) without ever appearing in the wrap
# recipe — the only portable adoption surface silently goes stale (exactly what A4-S2 found: 10
# of 21 verbs listed, no install.sh line).
#
# Flow (mirrors test/mcpverbscheck.sh's JSON-RPC-over-stdin pattern):
#   1. Start the MCP server, send initialize + tools/list, extract every tool "name".
#   2. Run `ripwire wrap claude`.
#   3. Assert every live verb name appears in the wrap output (word-boundary match, so e.g.
#      "for" doesn't false-positive on "before").
#   4. Assert the wrap output names skills/install.sh.
#   5. Every agent recipe (and every --all stanza) carries the pasteable use-when blurb block,
#      naming the right context file per client (CLAUDE.md / AGENTS.md / .cursor/rules / …).
#   6. The blurb body is emitted from ONE shared source — byte-identical across agents.
#   7. The skills-install line is a three-way probe, not an unconditional `bash skills/install.sh`:
#      (a) cwd has ./skills/install.sh → the checkout line; (b) else <exeDir>/../share/ripwire/
#      skills/install.sh exists (the curl installer's staged copy) → `bash "<abs path>"`;
#      (c) else a clone-pointer comment, never a dead command. Plus byte-determinism per case.
#
# Usage:
#   test/wrapverbscheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=build_w3i/ripwire test/wrapverbscheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
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
echo "=== 2. ripwire wrap claude — verb coverage ==="

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

[ "$missing" -eq 0 ] && ok "all $LIVE_COUNT live verbs are mentioned in 'ripwire wrap claude'" \
                     || no "$missing live verb(s) missing from 'ripwire wrap claude'"

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

# Run wrap --all with HOME redirected. XDG_CONFIG_HOME must be cleared too: opencode resolves its
# config dir through xdg-basedir, so a developer (or CI image) with XDG_CONFIG_HOME set would leak a
# real opencode install into this fake home and break the surface count below.
WRAP_ALL_OUT="$( HOME="$TEST_HOME" XDG_CONFIG_HOME= "$BIN" wrap --all 2>&1 )"

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

echo
echo "=== 5. use-when blurb block — every agent, right target file ==="

# extract the blurb body (the lines BETWEEN the paste fences) from a recipe on stdin
blurb_body() {
    sed -n '/^# --- paste into /,/^# --- end paste ---$/p' | sed '1d;$d'
}

check_blurb() {
    _agent="$1"; _target="$2"
    _out="$( "$BIN" wrap "$_agent" 2>/dev/null )"
    if echo "$_out" | grep -qF -- "# --- paste into $_target"; then
        ok "wrap $_agent blurb fence names $_target"
    else
        no "wrap $_agent blurb fence missing or names the wrong file (wanted $_target)"
    fi
    if echo "$_out" | grep -qF -- "# --- end paste ---"; then
        ok "wrap $_agent blurb fence is closed"
    else
        no "wrap $_agent blurb fence never closes"
    fi
    _bodylines="$( echo "$_out" | blurb_body | wc -l | tr -d ' ' )"
    if [ "$_bodylines" -ge 10 ] && [ "$_bodylines" -le 20 ]; then
        ok "wrap $_agent blurb body is $_bodylines lines (10-20 band)"
    else
        no "wrap $_agent blurb body is $_bodylines lines — outside the 10-20 band"
    fi
}

check_blurb claude   "CLAUDE.md"
check_blurb codex    "AGENTS.md"
check_blurb cursor   ".cursor/rules"
check_blurb windsurf ".windsurfrules"
check_blurb gemini   "GEMINI.md"
check_blurb opencode "AGENTS.md"
check_blurb aider    "CONVENTIONS.md"

# --all: each detected stanza carries its own blurb (fake HOME detects claude + codex + aider)
if echo "$WRAP_ALL_OUT" | grep -qF -- "# --- paste into CLAUDE.md" \
   && echo "$WRAP_ALL_OUT" | grep -qF -- "# --- paste into AGENTS.md" \
   && echo "$WRAP_ALL_OUT" | grep -qF -- "# --- paste into CONVENTIONS.md"; then
    ok "wrap --all stanzas each carry their blurb (CLAUDE.md + AGENTS.md + CONVENTIONS.md fences)"
else
    no "wrap --all is missing a per-stanza blurb fence"
fi

echo
echo "=== 6. blurb body — one shared source, byte-identical across agents ==="

"$BIN" wrap claude 2>/dev/null | blurb_body >"$TMP/blurb_claude"
"$BIN" wrap gemini 2>/dev/null | blurb_body >"$TMP/blurb_gemini"
"$BIN" wrap aider  2>/dev/null | blurb_body >"$TMP/blurb_aider"
if cmp -s "$TMP/blurb_claude" "$TMP/blurb_gemini" && cmp -s "$TMP/blurb_claude" "$TMP/blurb_aider"; then
    ok "blurb body is byte-identical across claude/gemini/aider (single source of truth)"
else
    no "blurb body DIVERGES between agents — the shared-source contract is broken"
fi

# the body must carry the load-bearing verbs of the use-when protocol
for _needle in '--for=' '--pack-task=' '--from-trace=' '--callers=' '--impact=' '--uses=' \
               '--edit-check=' '--exemplar=' '--quality-delta' '--test-gate' 'counts_floor'; do
    if grep -qF -- "$_needle" "$TMP/blurb_claude"; then
        ok "blurb names $_needle"
    else
        no "blurb is missing $_needle — the use-when protocol lost a verb"
    fi
done

echo
echo "=== 7. skills-line three-way probe ==="

REAL_TMP="$( cd "$TMP" && pwd -P )"

# case a — cwd is a checkout (./skills/install.sh exists) → the relative checkout line
mkdir -p "$TMP/case_a/skills"
: > "$TMP/case_a/skills/install.sh"
A_OUT="$( cd "$TMP/case_a" && "$BIN" wrap claude 2>/dev/null )"
if echo "$A_OUT" | grep -q '^bash skills/install\.sh'; then
    ok "case a (checkout cwd): relative 'bash skills/install.sh' line kept"
else
    no "case a (checkout cwd): relative skills line missing"
fi

# case b — prebuilt prefix layout: <prefix>/bin/<binary> + <prefix>/share/ripwire/skills/install.sh
# (the curl installer's staged copy — a fixed design contract). Copy, don't symlink: the binary
# realpath()s itself, and a symlink would resolve back to the build tree.
mkdir -p "$TMP/prefix/bin" "$TMP/prefix/share/ripwire/skills" "$TMP/case_b"
cp "$BIN" "$TMP/prefix/bin/ripwire-copy"
: > "$TMP/prefix/share/ripwire/skills/install.sh"
STAGED="$REAL_TMP/prefix/share/ripwire/skills/install.sh"
B_OUT="$( cd "$TMP/case_b" && "$TMP/prefix/bin/ripwire-copy" wrap claude 2>/dev/null )"
if echo "$B_OUT" | grep -qF "bash \"$STAGED\""; then
    ok "case b (prebuilt prefix): absolute staged path printed ($STAGED)"
else
    no "case b (prebuilt prefix): absolute staged path NOT printed"
fi
B_CODEX_OUT="$( cd "$TMP/case_b" && "$TMP/prefix/bin/ripwire-copy" wrap codex 2>/dev/null )"
if echo "$B_CODEX_OUT" | grep -qF "bash \"$STAGED\" --codex"; then
    ok "case b (prebuilt prefix, codex): staged path printed with --codex"
else
    no "case b (prebuilt prefix, codex): staged --codex line NOT printed"
fi

# case c — no checkout, no staged copy → a clone-pointer comment, never a dead command
mkdir -p "$TMP/bare/bin" "$TMP/case_c"
cp "$BIN" "$TMP/bare/bin/ripwire-copy"
C_OUT="$( cd "$TMP/case_c" && "$TMP/bare/bin/ripwire-copy" wrap claude 2>/dev/null )"
if echo "$C_OUT" | grep -q 'skills not found locally' && echo "$C_OUT" | grep -qF 'github.com/redhat-et/ripwire'; then
    ok "case c (nothing local): clone-pointer comment printed"
else
    no "case c (nothing local): clone-pointer comment missing"
fi
if echo "$C_OUT" | grep -q '^bash skills/install\.sh'; then
    no "case c (nothing local): still prints the DEAD 'bash skills/install.sh' command"
else
    ok "case c (nothing local): no dead install command"
fi

# determinism per probe case: same invocation twice, byte-identical
B_OUT2="$( cd "$TMP/case_b" && "$TMP/prefix/bin/ripwire-copy" wrap claude 2>/dev/null )"
if [ "$B_OUT" = "$B_OUT2" ]; then
    ok "case b output is deterministic (byte-identical on two runs)"
else
    no "case b output is NOT deterministic"
fi
C_OUT2="$( cd "$TMP/case_c" && "$TMP/bare/bin/ripwire-copy" wrap claude 2>/dev/null )"
if [ "$C_OUT" = "$C_OUT2" ]; then
    ok "case c output is deterministic (byte-identical on two runs)"
else
    no "case c output is NOT deterministic"
fi

echo
echo "=== 8. one-shot --for recipes budget with --token-budget, never --max-tokens ==="

# --for does not read --max-tokens: it warns on stderr and emits the full, unbudgeted result.
# --token-budget is the flag that actually shapes --for's output. The wrap recipes are the tool's
# own advice, so they must not teach the inert pairing (found live 2026-08-20: wrap claude
# recommended `--for="<task>" --max-tokens=2000`, which produced an unbudgeted map + a warning).
for _agent in claude codex cursor windsurf gemini opencode aider; do
    _out="$( "$BIN" wrap "$_agent" 2>/dev/null )"
    if echo "$_out" | grep -- '--for=' | grep -q -- '--max-tokens'; then
        no "wrap $_agent pairs --for with --max-tokens — inert advice, --for ignores that flag"
    else
        ok "wrap $_agent never pairs --for with --max-tokens"
    fi
done
# the three recipes that ship a budgeted one-shot --for line must budget it with --token-budget=
for _agent in claude opencode aider; do
    _out="$( "$BIN" wrap "$_agent" 2>/dev/null )"
    if echo "$_out" | grep -- '--for=' | grep -q -- '--token-budget='; then
        ok "wrap $_agent one-shot --for recipe carries --token-budget="
    else
        no "wrap $_agent one-shot --for recipe lost its --token-budget= budget"
    fi
done

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
