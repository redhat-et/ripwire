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
#   4. Assert the wrap output prints the collapsed "<path>" skills install line.
#   5. Every agent recipe (and every --all stanza) carries the pasteable use-when blurb block,
#      naming the right context file per client (CLAUDE.md / AGENTS.md / .cursor/rules / …).
#   6. The blurb body is emitted from ONE shared source — byte-identical across agents.
#   7. The skills-install line is ONE unconditional collapsed command, the same shape on every
#      install layout (checkout, curl-staged prefix, a mise shim, an aqua proxy, or nothing local
#      at all): `"<resolved binary path>" skills install[ <agent flag>]`, never the old three-arm
#      filesystem probe or its dead-end `# skills not found locally` comment. Byte-determinism per
#      case.
#
# Usage:
#   test/wrapverbscheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=build_w3i/ripwire test/wrapverbscheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
if [ "$LIVE_COUNT" -gt 0 ]; then ok "tools/list returned $LIVE_COUNT verb(s)"; else no "tools/list returned zero verbs"; fi

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
echo "=== 3. collapsed skills install line present ==="

if echo "$WRAP_OUT" | grep -qE '^'\''[^'\'']+'\'' skills install( --[a-z-]+)?( --hook)?([[:space:]]|$)'; then
    ok "wrap claude prints the collapsed \"<path>\" skills install line"
else
    no "wrap claude does NOT print the collapsed skills-install line — the skill-adoption step is invisible"
fi

echo
echo "=== 4. wrap --all with fake agent config dirs ==="

# Create a temporary HOME with two agent config directories
TEST_HOME="$TMP/test_home"
mkdir -p "$TEST_HOME/.claude" "$TEST_HOME/.codex"

# Run wrap --all with HOME redirected. XDG_CONFIG_HOME must be cleared too: opencode resolves its
# config dir through xdg-basedir, so a developer (or CI image) with XDG_CONFIG_HOME set would leak a
# real opencode install into this fake home and break the surface count below. HERMES_HOME gets the
# same clearing treatment: Hermes is detected via ${HERMES_HOME:-~/.hermes}, and a leaked real
# HERMES_HOME would count a Hermes surface that is not actually in this fake home.
WRAP_ALL_OUT="$( HOME="$TEST_HOME" XDG_CONFIG_HOME= HERMES_HOME= "$BIN" wrap --all 2>&1 )"

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
WRAP_ALL_OUT2="$( HOME="$TEST_HOME" XDG_CONFIG_HOME= HERMES_HOME= "$BIN" wrap --all 2>&1 )"
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
echo "=== 7. skills-line: collapsed 'skills install' command, every layout ==="

REAL_TMP="$( cd "$TMP" && pwd -P )"

# The collapsed contract (redhat-et/ripwire#225 task 12): ONE unconditional line,
# `"<resolved binary path>" skills install[ <agent flag>]`, on every layout, since the skills are
# embedded in the binary and there is nothing left to probe for. Not `$`-anchored: the real line
# carries a trailing `# deploy to ... ` comment.
assert_skills_line() {
    _label="$1"; _out="$2"
    if echo "$_out" | grep -qE '^'\''[^'\'']+'\'' skills install( --[a-z-]+)?( --hook)?([[:space:]]|$)'; then
        ok "$_label: prints the collapsed \"<path>\" skills install line"
    else
        no "$_label: does NOT print the collapsed skills-install line"
    fi
    if echo "$_out" | grep -q 'bash skills/install\.sh'; then
        no "$_label: still prints the OLD 'bash skills/install.sh' probe line"
    else
        ok "$_label: no old 'bash skills/install.sh' probe line"
    fi
    if echo "$_out" | grep -q 'skills not found locally'; then
        no "$_label: still prints the OLD 'skills not found locally' dead-end comment"
    else
        ok "$_label: no old 'skills not found locally' dead-end comment"
    fi
}

# case a — cwd is a checkout (./skills/install.sh exists)
mkdir -p "$TMP/case_a/skills"
: > "$TMP/case_a/skills/install.sh"
A_OUT="$( cd "$TMP/case_a" && "$BIN" wrap claude 2>/dev/null )"
assert_skills_line "case a (checkout cwd)" "$A_OUT"

# case b — prebuilt prefix layout: <prefix>/bin/<binary> + <prefix>/share/ripwire/skills/install.sh
# (the curl installer's staged copy). Copy, don't symlink: the binary realpath()s itself, and a
# symlink would resolve back to the build tree.
mkdir -p "$TMP/prefix/bin" "$TMP/prefix/share/ripwire/skills" "$TMP/case_b"
cp "$BIN" "$TMP/prefix/bin/ripwire-copy"
: > "$TMP/prefix/share/ripwire/skills/install.sh"
B_OUT="$( cd "$TMP/case_b" && "$TMP/prefix/bin/ripwire-copy" wrap claude 2>/dev/null )"
assert_skills_line "case b (prebuilt prefix)" "$B_OUT"
B_CODEX_OUT="$( cd "$TMP/case_b" && "$TMP/prefix/bin/ripwire-copy" wrap codex 2>/dev/null )"
assert_skills_line "case b (prebuilt prefix, codex)" "$B_CODEX_OUT"
if echo "$B_CODEX_OUT" | grep -qE '^'\''[^'\'']+'\'' skills install --codex([[:space:]]|$)'; then
    ok "case b (prebuilt prefix, codex): the --codex flag is carried on the collapsed line"
else
    no "case b (prebuilt prefix, codex): the --codex flag is missing from the collapsed line"
fi

# case c — no checkout, no staged copy: the embedded binary still needs no sibling to find
mkdir -p "$TMP/bare/bin" "$TMP/case_c"
cp "$BIN" "$TMP/bare/bin/ripwire-copy"
C_OUT="$( cd "$TMP/case_c" && "$TMP/bare/bin/ripwire-copy" wrap claude 2>/dev/null )"
assert_skills_line "case c (nothing local)" "$C_OUT"

# case mise — installs/<tool>/<version>/<archive>/, shims/ripwire execs the real binary (mise never
# symlinks a shim straight to the target — see prompts/help-wanted/install-discovery-mise-aqua.md)
ARCHIVE="ripwire-0.0.0-fixture"
MISE_INSTALL="$TMP/mise/installs/ripwire/0.0.0/$ARCHIVE"
mkdir -p "$MISE_INSTALL/skills" "$TMP/mise/shims" "$TMP/case_mise"
cp "$BIN" "$MISE_INSTALL/ripwire"
: > "$MISE_INSTALL/skills/install.sh"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$MISE_INSTALL/ripwire" >"$TMP/mise/shims/ripwire"
chmod +x "$TMP/mise/shims/ripwire"
MISE_OUT="$( cd "$TMP/case_mise" && "$TMP/mise/shims/ripwire" wrap claude 2>/dev/null )"
assert_skills_line "case mise (shim)" "$MISE_OUT"
# I3b: a generic single-quoted-path shape matches ANY path — this arm exists specifically to prove
# the recipe names the SHIM's own resolved target, not just some path, so assert that exact string.
# realpath, not $TMP literally: the recipe prints the binary's OWN resolved path, and on macOS $TMP
# (/var/folders/...) and its canonical form (/private/var/folders/...) differ as strings for the
# same file (sourceinstallcheck.sh hit this same gotcha) — compare against REAL_TMP instead.
MISE_INSTALL_REAL="$REAL_TMP/mise/installs/ripwire/0.0.0/$ARCHIVE"
if echo "$MISE_OUT" | grep -qF "'$MISE_INSTALL_REAL/ripwire' skills install"; then
    ok "case mise (shim): the recipe names the shim's own resolved path ($MISE_INSTALL_REAL/ripwire)"
else
    no "case mise (shim): the recipe does not name $MISE_INSTALL_REAL/ripwire specifically"
fi

# case aqua — pkgs/github_release/github.com/<owner>/<repo>/<version>/<archive>.tar.gz/<archive>/,
# bin/ripwire -> aqua-proxy, a shim that execs the real binary (aqua never symlinks straight to it)
AQUA_INSTALL="$TMP/aqua/pkgs/github_release/github.com/redhat-et/ripwire/v0.0.0/$ARCHIVE.tar.gz/$ARCHIVE"
mkdir -p "$AQUA_INSTALL/skills" "$TMP/aqua/bin" "$TMP/case_aqua"
cp "$BIN" "$AQUA_INSTALL/ripwire"
: > "$AQUA_INSTALL/skills/install.sh"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$AQUA_INSTALL/ripwire" >"$TMP/aqua/bin/aqua-proxy"
chmod +x "$TMP/aqua/bin/aqua-proxy"
ln -s aqua-proxy "$TMP/aqua/bin/ripwire"
AQUA_OUT="$( cd "$TMP/case_aqua" && "$TMP/aqua/bin/ripwire" wrap claude 2>/dev/null )"
assert_skills_line "case aqua (proxy shim)" "$AQUA_OUT"
AQUA_INSTALL_REAL="$REAL_TMP/aqua/pkgs/github_release/github.com/redhat-et/ripwire/v0.0.0/$ARCHIVE.tar.gz/$ARCHIVE"
if echo "$AQUA_OUT" | grep -qF "'$AQUA_INSTALL_REAL/ripwire' skills install"; then
    ok "case aqua (proxy shim): the recipe names the shim's own resolved path ($AQUA_INSTALL_REAL/ripwire)"
else
    no "case aqua (proxy shim): the recipe does not name $AQUA_INSTALL_REAL/ripwire specifically"
fi

# determinism per fixture: same invocation twice, byte-identical
B_OUT2="$( cd "$TMP/case_b" && "$TMP/prefix/bin/ripwire-copy" wrap claude 2>/dev/null )"
[ "$B_OUT" = "$B_OUT2" ] && ok "case b output is deterministic (byte-identical on two runs)" \
                          || no "case b output is NOT deterministic"
C_OUT2="$( cd "$TMP/case_c" && "$TMP/bare/bin/ripwire-copy" wrap claude 2>/dev/null )"
[ "$C_OUT" = "$C_OUT2" ] && ok "case c output is deterministic (byte-identical on two runs)" \
                          || no "case c output is NOT deterministic"
MISE_OUT2="$( cd "$TMP/case_mise" && "$TMP/mise/shims/ripwire" wrap claude 2>/dev/null )"
[ "$MISE_OUT" = "$MISE_OUT2" ] && ok "case mise output is deterministic (byte-identical on two runs)" \
                                || no "case mise output is NOT deterministic"
AQUA_OUT2="$( cd "$TMP/case_aqua" && "$TMP/aqua/bin/ripwire" wrap claude 2>/dev/null )"
[ "$AQUA_OUT" = "$AQUA_OUT2" ] && ok "case aqua output is deterministic (byte-identical on two runs)" \
                               || no "case aqua output is NOT deterministic"

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
echo "=== 7. agent surfaces ask for the compact legend (A1-2, owner decision 2026-09-12) ==="
# Every command the blurb spells for an XML verb carries --legend=compact (the legend is most of a small
# --callers/--uses/--impact answer, and byte-identical rows either way); --for never does (its compact legend is its
# own, and the first call of a session wants the full one). The verb list is the shipped policy, spelled here so a
# blurb edit that drops the flag on one of them is red, not a judgement call.
COMPACT_VERBS="callers impact uses expand exemplar quality-delta test-gate pack-task from-trace edit-check"
BT='`'
"$BIN" wrap claude 2>/dev/null | blurb_body >"$TMP/blurb7"
[ -s "$TMP/blurb7" ] || no "7 presence: no blurb body to inspect"
for _v in $COMPACT_VERBS; do
    _spans="$( grep -oE -- '`[^`]*`' "$TMP/blurb7" | grep -E -- "--$_v(=|$BT| )" )"
    [ -n "$_spans" ] || { no "7 presence: the blurb no longer spells --$_v — re-author this arm"; continue; }
    if printf '%s\n' "$_spans" | grep -vq -- '--legend=compact'; then
        no "7: a blurb command for --$_v lacks --legend=compact: $( printf '%s\n' "$_spans" | grep -v -- '--legend=compact' | head -1 )"
    else
        ok "7: every blurb command for --$_v carries --legend=compact"
    fi
done
if grep -oE -- '`[^`]*`' "$TMP/blurb7" | grep -E -- '--for=' | grep -q -- '--legend=compact'; then
    no "7: a --for command in the blurb carries --legend=compact (the first call wants the full legend; --for's compact legend is its own)"
else
    ok "7: no --for command in the blurb carries --legend=compact"
fi

echo
echo "=== 8. every agent surface also says how to get the FULL legend back (owner question, 2026-09-13) ==="
# Compact is what the generated commands ask for; an agent must also know when and how to ask for the full
# legend (a term it does not recognise, a floor or cap it needs explained, a map a human will read). Four
# surfaces, one sentence each — the wrap blurb (the session-start primer extracts it), the router skill (the
# skills' shared conventions, not seventeen bodies), the prompt router's injected context, and the MCP
# schema's `legend` field. The phrase asserted is the one the four surfaces share; a surface that drops it
# is red, not a judgement call.
FULL_PHRASE='--legend=full'
if grep -qF -- "$FULL_PHRASE" "$TMP/blurb7" && grep -qiF 'definition' "$TMP/blurb7"; then
    ok "8: the wrap blurb says when to add --legend=full"
else
    no "8: the wrap blurb never says how to get the full legend back (no --legend=full line)"
fi
if grep -qF -- "$FULL_PHRASE" "$ROOT/skills/ripwire-router/SKILL.md"; then
    ok "8: skills/ripwire-router/SKILL.md carries the --legend=full convention"
else
    no "8: skills/ripwire-router/SKILL.md never mentions --legend=full"
fi
for _h in ripwire-claude-route.sh ripwire-claude-toolroute.sh ripwire-codex-route.sh; do
    if grep -q -- "add --legend=full" "$ROOT/hooks/$_h"; then
        ok "8: hooks/$_h's injected context says to add --legend=full when a definition is unclear"
    else
        no "8: hooks/$_h's injected context never mentions --legend=full"
    fi
done
if printf '{"jsonrpc":"2.0","id":1,"method":"tools/list"}\n' | "$BIN" --mcp 2>/dev/null | grep -q 'restores the full legend'; then
    ok "8: the MCP schema's legend field says \"full\" restores the full legend"
else
    no "8: the MCP schema's legend field does not say that \"full\" restores the full legend"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
