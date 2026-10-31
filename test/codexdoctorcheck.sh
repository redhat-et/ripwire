#!/usr/bin/env bash
# codexdoctorcheck.sh — isolated active-surface gate for `--doctor --agent=codex`.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
        "$BINDIR/ripwire" "$REPO" --doctor --agent=codex --no-cache "$@" 2>&1
}

# L1 (2026-09-19): the CLI default is the compact posture, whose root leads with schema=; the checks= read below
# anchors on the full-posture `<doctor checks=` shape, so this run asks for --legend=full (rows identical).
OUT="$( run_doctor --legend=full )"; RC=$?
if [ "$RC" -eq 0 ]; then ok "fully wired fake Codex surface exits 0"; else no "healthy Codex doctor exited $RC: $OUT"; fi
# DERIVED, not pinned at 10: what this arm actually asserts is that --agent=codex adds exactly FOUR rows to
# whatever the base doctor emits, that every row passed on a fully wired surface, and that the report is
# labelled. A literal total measures the BASE check count instead — it was 10, then 11 when the base grew an
# index-cache row, and re-pinning the number teaches nobody what the arm is for.
BASE_ROWS="$( HOME="$HOME_FAKE" CODEX_HOME="$CODEX_FAKE" AGENTS_HOME="$AGENTS_FAKE" \
    PATH="$BINDIR:/usr/bin:/bin" TMPDIR="$CACHE" "$BINDIR/ripwire" "$REPO" --doctor --no-cache 2>/dev/null \
    | grep -o '<c n="' | wc -l | tr -d ' ' )"
CODEX_CHECKS="$( printf '%s' "$OUT" | grep -o '<doctor checks="[0-9]*"' | grep -o '[0-9]*' )"
CODEX_PASSED="$( printf '%s' "$OUT" | grep -o 'passed="[0-9]*"' | head -1 | grep -o '[0-9]*' )"
[ -n "$BASE_ROWS" ] && [ "$CODEX_CHECKS" = "$(( BASE_ROWS + 4 ))" ] \
    && [ "$CODEX_PASSED" = "$CODEX_CHECKS" ] \
    && printf '%s' "$OUT" | grep -q 'agent="codex"' \
    && ok "Codex selection adds four checks (base $BASE_ROWS -> $CODEX_CHECKS), all passed, and labels the report" \
    || no "Codex doctor reported checks=\"$CODEX_CHECKS\" passed=\"$CODEX_PASSED\" against a base of $BASE_ROWS rows (expected checks=passed=$(( BASE_ROWS + 4 )) and agent=\"codex\")"
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
if [ "$before" = "$after" ]; then ok "Codex doctor is read-only"; else no "Codex doctor mutated the active surface"; fi

declared="$( sed -n 's/^skill=//p' "$AGENTS_FAKE/skills/.ripwire-manifest-v1" | head -1 )"
mv "$AGENTS_FAKE/skills/$declared" "$TMP/$declared"
SOUT="$( run_doctor )"; SRC=$?
[ "$SRC" -eq 1 ] && printf '%s' "$SOUT" | grep -q '<c n="codex-skills" ok="0"' \
    && ok "missing manifest-declared skill fails parity" || no "missing declared skill did not fail parity"
printf '%s' "$SOUT" | grep -q 'skills/install.sh --codex' \
    && ok "skill failure names the exact repair command" || no "skill failure omitted repair command"
mv "$TMP/$declared" "$AGENTS_FAKE/skills/$declared"
mkdir "$AGENTS_FAKE/skills/ripwire-undocumented"
printf -- '---\nname: ripwire-undocumented\n---\n' >"$AGENTS_FAKE/skills/ripwire-undocumented/SKILL.md"
SOUT="$( run_doctor )"
printf '%s' "$SOUT" | grep -q '<c n="codex-skills" ok="0"' \
    && ok "undeclared live skill fails parity" || no "undeclared live skill did not fail parity"
rm -rf "$AGENTS_FAKE/skills/ripwire-undocumented"
# A declared name that is only an EMPTY directory (0.6.3's Git Bash `ln -sfn` leftover, #334) loads no skill, so
# it is not live and parity fails. RED on 0.6.4, which counted any `ripwire-*` directory as live.
mv "$AGENTS_FAKE/skills/$declared" "$TMP/$declared"
mkdir "$AGENTS_FAKE/skills/$declared"
EOUT="$( run_doctor )"; ERC=$?
[ "$ERC" -eq 1 ] && printf '%s' "$EOUT" | grep -q '<c n="codex-skills" ok="0"' \
    && ok "a declared skill left as an empty directory fails parity (no SKILL.md, not live)" \
    || no "a declared skill left as an empty directory still passed parity (exit $ERC): $( printf '%s' "$EOUT" | grep -o '<c n="codex-skills"[^>]*>' )"
rmdir "$AGENTS_FAKE/skills/$declared"
mv "$TMP/$declared" "$AGENTS_FAKE/skills/$declared"
EOUT="$( run_doctor )"
printf '%s' "$EOUT" | grep -q '<c n="codex-skills" ok="1"' \
    && ok "restoring the skill restores parity (the empty-directory arm above can pass)" \
    || no "parity did not come back after restoring $declared: $( printf '%s' "$EOUT" | grep -o '<c n="codex-skills"[^>]*>' )"

chmod -x "$HOOKDIR/ripwire-codex-route.sh"
HOUT="$( run_doctor )"; HRC=$?
[ "$HRC" -eq 1 ] && printf '%s' "$HOUT" | grep -q '<c n="codex-hooks" ok="0"' \
    && ok "non-executable Codex hook fails" || no "non-executable Codex hook did not fail"
printf '%s' "$HOUT" | grep -q 'skills/install.sh --codex --hook' \
    && ok "hook failure names the exact repair command" || no "hook failure omitted repair command"
chmod +x "$HOOKDIR/ripwire-codex-route.sh"

# F1 (install-hardening review): skills/install.sh single-quotes a hook path that needs it, e.g. a checkout under a
# path with a space. The doctor reads such a command as the script BETWEEN the quotes; before, the quotes stayed in the
# path it looked up, so a hook that ran was reported broken and the repair hint could never clear the row.
QDIR="$TMP/hook dir"; mkdir -p "$QDIR"
for h in ripwire-codex-nudge.sh ripwire-codex-route.sh; do
    printf '#!/bin/sh\nexit 0\n' >"$QDIR/$h"; chmod +x "$QDIR/$h"
done
cp "$CODEX_FAKE/hooks.json" "$TMP/hooks.json.plain"
quoted_hooks() # $1 = directory holding the two scripts
{
    cat >"$CODEX_FAKE/hooks.json" <<EOF
{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"'$1/ripwire-codex-nudge.sh'"}]}],
"SessionStart":[{"hooks":[{"type":"command","command":"'$1/ripwire-codex-nudge.sh' --session-start"}]}],
"UserPromptSubmit":[{"hooks":[{"type":"command","command":"'$1/ripwire-codex-route.sh'"}]}]}}
EOF
}
quoted_hooks "$QDIR"
QOUT="$( run_doctor )"; QRC=$?
{ [ "$QRC" -eq 0 ] && printf '%s' "$QOUT" | grep -q '<c n="codex-hooks" ok="1"'; } \
    && ok "a quoted Codex hook command (path with a space) resolves to its script: codex-hooks ok" \
    || no "a quoted Codex hook command was reported broken (exit $QRC): $( printf '%s' "$QOUT" | grep -o '<c n="codex-hooks"[^>]*>' )"
quoted_hooks "$TMP/no such dir"
QOUT="$( run_doctor )"; QRC=$?
{ [ "$QRC" -eq 1 ] && printf '%s' "$QOUT" | grep -q '<c n="codex-hooks" ok="0"'; } \
    && ok "a quoted Codex hook command naming a missing script still fails codex-hooks" \
    || no "a quoted command to a missing script passed codex-hooks (exit $QRC): $( printf '%s' "$QOUT" | grep -o '<c n="codex-hooks"[^>]*>' )"
cat >"$CODEX_FAKE/hooks.json" <<EOF
{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"'$QDIR/ripwire-codex-nudge.sh"}]}],
"SessionStart":[{"hooks":[{"type":"command","command":"'$QDIR/ripwire-codex-nudge.sh --session-start"}]}],
"UserPromptSubmit":[{"hooks":[{"type":"command","command":"'$QDIR/ripwire-codex-route.sh"}]}]}}
EOF
QOUT="$( run_doctor )"
printf '%s' "$QOUT" | grep -q '<c n="codex-hooks" ok="0"' \
    && ok "an UNTERMINATED quote names no script: codex-hooks fails" \
    || no "an unterminated quoted command passed codex-hooks: $( printf '%s' "$QOUT" | grep -o '<c n="codex-hooks"[^>]*>' )"
cp "$TMP/hooks.json.plain" "$CODEX_FAKE/hooks.json"
# the Claude row reads the same command shape: install from a checkout under a path with a space, as a user would
CHK="$TMP/sp ace"; CL_HOME="$TMP/clhome"; mkdir -p "$CHK" "$CL_HOME"
cp -R "$ROOT/skills" "$CHK/skills"; cp -R "$ROOT/hooks" "$CHK/hooks"
HOME="$CL_HOME" bash "$CHK/skills/install.sh" --hook >/dev/null 2>&1
claude_doctor() { HOME="$CL_HOME" PATH="$BINDIR:/usr/bin:/bin" TMPDIR="$CACHE" "$BINDIR/ripwire" "$REPO" --doctor --agent=claude --no-cache 2>&1; }
CLOUT="$( claude_doctor )"
printf '%s' "$CLOUT" | grep -q '<c n="claude-hooks" ok="1"' \
    && ok "a hook installed from a path with a space is reported working by --doctor --agent=claude" \
    || no "claude-hooks reported a quoted, working hook as broken: $( printf '%s' "$CLOUT" | grep -o '<c n="claude-hooks"[^>]*>' )"
rm -f "$CHK/hooks/ripwire-nudge.sh"
CLOUT="$( claude_doctor )"
printf '%s' "$CLOUT" | grep -q '<c n="claude-hooks" ok="0"' \
    && ok "the same quoted registration fails claude-hooks once its script is gone" \
    || no "claude-hooks passed with the quoted script deleted: $( printf '%s' "$CLOUT" | grep -o '<c n="claude-hooks"[^>]*>' )"

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
