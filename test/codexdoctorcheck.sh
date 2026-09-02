#!/usr/bin/env bash
# codexdoctorcheck.sh — isolated active-surface gate for `--doctor --agent=codex`.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

HOME_FAKE="$TMP/home"; CODEX_FAKE="$TMP/codex"; AGENTS_FAKE="$TMP/agents"
BINDIR="$TMP/bin"; REPO="$TMP/repo"; CACHE="$TMP/cache"
mkdir -p "$HOME_FAKE" "$CODEX_FAKE" "$AGENTS_FAKE" "$BINDIR" "$REPO" "$CACHE"
cp -p "$BIN" "$BINDIR/ripwire"; chmod +x "$BINDIR/ripwire"
printf 'int f(){return 0;}\n' >"$REPO/f.cpp"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name Dev
git -C "$REPO" add -A && git -C "$REPO" commit -qm init

# The real installer owns the manifest contract. This remains isolated to AGENTS_FAKE.
HOME="$HOME_FAKE" CODEX_HOME="$CODEX_FAKE" AGENTS_HOME="$AGENTS_FAKE" \
    bash "$ROOT/skills/install.sh" --codex >/dev/null
[ -f "$AGENTS_FAKE/skills/.ripwire-manifest-v1" ] \
    && ok "Codex install emits the versioned skills manifest" \
    || no "Codex install omitted .ripwire-manifest-v1"

HOOKDIR="$TMP/hooks"; mkdir -p "$HOOKDIR"
for h in ripwire-codex-nudge.sh ripwire-codex-route.sh; do
    printf '#!/bin/sh\nexit 0\n' >"$HOOKDIR/$h"
    chmod +x "$HOOKDIR/$h"
done
cat >"$CODEX_FAKE/hooks.json" <<EOF
{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"$HOOKDIR/ripwire-codex-nudge.sh"}]}],
"SessionStart":[{"hooks":[{"type":"command","command":"$HOOKDIR/ripwire-codex-nudge.sh --session-start"}]}],
"UserPromptSubmit":[{"hooks":[{"type":"command","command":"$HOOKDIR/ripwire-codex-route.sh"}]}]},
"unrelated_secret":"DO_NOT_PRINT_CODEX_DOCTOR_SECRET"}
EOF
cat >"$CODEX_FAKE/config.toml" <<EOF
[mcp_servers.ripwire]
command = "$BINDIR/ripwire"
args = ["--mcp"]
enabled_tools = ["analyze", "quality_delta", "flags", "doc_drift"]
default_tools_approval_mode = "approve"
token = "DO_NOT_PRINT_CODEX_DOCTOR_SECRET"
EOF

run_doctor()
{
    HOME="$HOME_FAKE" CODEX_HOME="$CODEX_FAKE" AGENTS_HOME="$AGENTS_FAKE" \
        PATH="$BINDIR:/usr/bin:/bin" TMPDIR="$CACHE" \
        "$BINDIR/ripwire" "$REPO" --doctor --agent=codex --no-cache 2>&1
}

OUT="$( run_doctor )"; RC=$?
[ "$RC" -eq 0 ] && ok "fully wired fake Codex surface exits 0" || no "healthy Codex doctor exited $RC: $OUT"
printf '%s' "$OUT" | grep -q '<doctor checks="10" passed="10" agent="codex"' \
    && ok "Codex selection adds four checks and labels the report" \
    || no "Codex doctor root did not report checks=10 passed=10 agent=codex"
for row in codex-binary codex-skills codex-hooks codex-mcp; do
    printf '%s' "$OUT" | grep -q "<c n=\"$row\" ok=\"1\"" \
        && ok "healthy row present: $row" || no "healthy row missing/failing: $row"
done
printf '%s' "$OUT" | xmllint --noout - 2>/dev/null \
    && ok "Codex doctor output is well-formed XML" || no "Codex doctor output is malformed XML"
printf '%s' "$OUT" | grep -q 'DO_NOT_PRINT_CODEX_DOCTOR_SECRET' \
    && no "Codex doctor leaked an unrelated config secret" || ok "Codex doctor does not print config secrets"

before="$( cksum "$CODEX_FAKE/hooks.json" "$CODEX_FAKE/config.toml" "$AGENTS_FAKE/skills/.ripwire-manifest-v1"; find "$AGENTS_FAKE/skills" -mindepth 1 -maxdepth 1 -print | sort )"
run_doctor >/dev/null
after="$( cksum "$CODEX_FAKE/hooks.json" "$CODEX_FAKE/config.toml" "$AGENTS_FAKE/skills/.ripwire-manifest-v1"; find "$AGENTS_FAKE/skills" -mindepth 1 -maxdepth 1 -print | sort )"
[ "$before" = "$after" ] && ok "Codex doctor is read-only" || no "Codex doctor mutated the active surface"

declared="$( sed -n 's/^skill=//p' "$AGENTS_FAKE/skills/.ripwire-manifest-v1" | head -1 )"
mv "$AGENTS_FAKE/skills/$declared" "$TMP/$declared"
SOUT="$( run_doctor )"; SRC=$?
[ "$SRC" -eq 1 ] && printf '%s' "$SOUT" | grep -q '<c n="codex-skills" ok="0"' \
    && ok "missing manifest-declared skill fails parity" || no "missing declared skill did not fail parity"
printf '%s' "$SOUT" | grep -q 'skills/install.sh --codex' \
    && ok "skill failure names the exact repair command" || no "skill failure omitted repair command"
mv "$TMP/$declared" "$AGENTS_FAKE/skills/$declared"
mkdir "$AGENTS_FAKE/skills/ripwire-undocumented"
SOUT="$( run_doctor )"
printf '%s' "$SOUT" | grep -q '<c n="codex-skills" ok="0"' \
    && ok "undeclared live skill fails parity" || no "undeclared live skill did not fail parity"
rmdir "$AGENTS_FAKE/skills/ripwire-undocumented"

chmod -x "$HOOKDIR/ripwire-codex-route.sh"
HOUT="$( run_doctor )"; HRC=$?
[ "$HRC" -eq 1 ] && printf '%s' "$HOUT" | grep -q '<c n="codex-hooks" ok="0"' \
    && ok "non-executable Codex hook fails" || no "non-executable Codex hook did not fail"
printf '%s' "$HOUT" | grep -q 'skills/install.sh --codex --hook' \
    && ok "hook failure names the exact repair command" || no "hook failure omitted repair command"
chmod +x "$HOOKDIR/ripwire-codex-route.sh"

sed "s#command = \"$BINDIR/ripwire\"#command = \"$TMP/missing-ripwire\"#" "$CODEX_FAKE/config.toml" >"$TMP/bad.toml"
mv "$TMP/bad.toml" "$CODEX_FAKE/config.toml"
MOUT="$( run_doctor )"; MRC=$?
[ "$MRC" -eq 1 ] && printf '%s' "$MOUT" | grep -q '<c n="codex-mcp" ok="0"' \
    && ok "non-executable MCP command fails" || no "non-executable MCP command did not fail"
printf '%s' "$MOUT" | grep -q 'ripwire wrap codex' \
    && ok "MCP failure names the precise recipe command" || no "MCP failure omitted repair command"
printf '%s' "$MOUT" | grep -q 'DO_NOT_PRINT_CODEX_DOCTOR_SECRET' \
    && no "failing Codex doctor leaked a config secret" || ok "failing Codex doctor still redacts config secrets"

# `claude` was this arm's "unknown value" until 2026-09-02, when --agent gained a claude surface of
# its own (src/codexdoctor.h::claudeInspect, gated by test/routehookcheck.sh section V). The arm still
# needs a value the parser genuinely does not know, so it now uses one that names no agent at all.
BAD="$( "$BIN" "$REPO" --doctor --agent=notanagent --no-cache 2>&1 )"; BRC=$?
[ "$BRC" -eq 1 ] && printf '%s' "$BAD" | grep -q 'supported: codex' \
    && ok "unknown --agent value refuses with the supported set" || no "unknown --agent value did not refuse precisely"
ALONE="$( "$BIN" "$REPO" --agent=codex --no-cache 2>&1 )"; ARC=$?
[ "$ARC" -eq 1 ] && printf '%s' "$ALONE" | grep -q -- '--agent=codex modifies --doctor' \
    && ok "--agent=codex alone refuses as an inert modifier" || no "--agent=codex alone silently no-opped"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "SOME CHECKS FAILED"; exit 1
