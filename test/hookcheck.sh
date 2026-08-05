#!/usr/bin/env bash
# hookcheck.sh — gate for hooks/ripwire-nudge.sh (Phase B5.2, the
# opt-in PreToolUse "nudge raw grep toward ripwire" hook, extended by Phase B9 to `git diff`/`git log`/
# `git show --stat`) and its installer, skills/install.sh --hook.
#
# The hook is ADVISORY-ONLY by design (see the script's own header): it must never block/deny/rewrite a
# tool call, must only speak once per session per pattern, must stay silent off its target tools (Grep;
# a Bash command that's a recursive grep/rg; `git diff`/`git log`/`git show --stat`; and NOT `git
# status`/add/commit/push/pull/checkout/branch), and must degrade to silence — not a crash — the moment
# its preconditions (git repo, ripwire on PATH) aren't met. This gate feeds it synthetic PreToolUse JSON
# on stdin and asserts each of those properties, plus the installer's idempotency.
#
# Usage:  test/hookcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success. Never touches the
# real ~/.claude — every run is sandboxed under a scratch TMPDIR/HOME.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
HOOK="$ROOT/hooks/ripwire-nudge.sh"
INSTALL="$ROOT/skills/install.sh"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -f "$HOOK" ] || { echo "no $HOOK"; exit 2; }
[ -x "$HOOK" ] || { echo "$HOOK is not executable"; exit 2; }
[ -f "$INSTALL" ] || { echo "no $INSTALL"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ---- shared fixtures: a real (but tiny) git repo, and a stub `ripwire` binary on a scratch PATH ----
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "dev@x.com"
git -C "$REPO" config user.name  "Dev"

NONREPO="$TMP/nonrepo"; mkdir -p "$NONREPO"   # a plain dir, deliberately NOT a git repo

BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\necho ripwire-stub\n' >"$BIN/ripwire"; chmod +x "$BIN/ripwire"
WITH_RIPWIRE="$BIN:$PATH"
NO_RIPWIRE="/usr/bin:/bin"   # a PATH with no ripwire on it

run_hook()
{
    # run_hook JSON PATHVAL TMPDIRVAL  -> prints stdout, sets $RC
    printf '%s' "$1" | PATH="$2" TMPDIR="$3" bash "$HOOK"
}

is_valid_json()
{
    if command -v jq >/dev/null 2>&1; then jq -e . >/dev/null 2>&1; else python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; fi
}

echo "hookcheck: HOOK=$HOOK"

# ── (1) Grep case: fires, valid JSON, allow-never-deny, names --grep ───────────────────────────────
T1="$TMP/t1"; mkdir -p "$T1"
GREP_JSON='{"session_id":"grepcase","cwd":"'"$REPO"'","tool_name":"Grep","tool_input":{"pattern":"needle","path":"."}}'
OUT1="$( run_hook "$GREP_JSON" "$WITH_RIPWIRE" "$T1" )"; RC1=$?
echo "-- Grep case output --"; echo "$OUT1"; echo "(exit=$RC1)"

[ "$RC1" -eq 0 ] && ok "Grep case: exit 0" || no "Grep case: exit was $RC1"
[ -n "$OUT1" ] && printf '%s' "$OUT1" | is_valid_json && ok "Grep case: valid JSON on stdout" \
    || no "Grep case: stdout is not valid JSON (or empty)"
printf '%s' "$OUT1" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"allow"' \
    && ok "Grep case: permissionDecision allow" || no "Grep case: missing/wrong permissionDecision"
printf '%s' "$OUT1" | grep -qi 'deny\|"ask"' \
    && no "Grep case: output mentions deny/ask (must never)" || ok "Grep case: no deny/ask anywhere"
printf '%s' "$OUT1" | grep -q -- '--grep' \
    && ok "Grep case: suggestion names --grep" || no "Grep case: suggestion missing --grep"

# ── (2) Grep case, second invocation same session: dedup — silent, still exit 0 ────────────────────
OUT1B="$( run_hook "$GREP_JSON" "$WITH_RIPWIRE" "$T1" )"; RC1B=$?
echo "-- Grep case, 2nd invocation (dedup) --"; echo "[$OUT1B]"; echo "(exit=$RC1B)"
[ "$RC1B" -eq 0 ] && ok "Grep dedup: exit 0" || no "Grep dedup: exit was $RC1B"
[ -z "$OUT1B" ] && ok "Grep dedup: silent on 2nd call (no spam)" || no "Grep dedup: 2nd call was not silent: $OUT1B"

# ── (3) Bash-grep case (recursive): fires, names --grep or --for ───────────────────────────────────
T3="$TMP/t3"; mkdir -p "$T3"
BASHGREP_JSON='{"session_id":"bashcase","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"grep -rn needle ."}}'
OUT3="$( run_hook "$BASHGREP_JSON" "$WITH_RIPWIRE" "$T3" )"; RC3=$?
echo "-- Bash-grep case output --"; echo "$OUT3"; echo "(exit=$RC3)"

[ "$RC3" -eq 0 ] && ok "Bash-grep case: exit 0" || no "Bash-grep case: exit was $RC3"
printf '%s' "$OUT3" | is_valid_json && ok "Bash-grep case: valid JSON on stdout" \
    || no "Bash-grep case: stdout is not valid JSON"
printf '%s' "$OUT3" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"allow"' \
    && ok "Bash-grep case: permissionDecision allow" || no "Bash-grep case: missing/wrong permissionDecision"
printf '%s' "$OUT3" | grep -qE -- '--grep|--for' \
    && ok "Bash-grep case: suggestion names --grep/--for" || no "Bash-grep case: suggestion missing a verb"

# ripgrep spelling also counts
T3B="$TMP/t3b"; mkdir -p "$T3B"
RG_JSON='{"session_id":"rgcase","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"rg needle ."}}'
OUT3B="$( run_hook "$RG_JSON" "$WITH_RIPWIRE" "$T3B" )"; RC3B=$?
[ "$RC3B" -eq 0 ] && [ -n "$OUT3B" ] && ok "Bash rg case: fires (exit 0, non-empty)" \
    || no "Bash rg case: did not fire as expected (exit=$RC3B out=[$OUT3B])"

# ── (3c) git diff case (Phase B9): fires, names --situ ──────────────────────────────────────────────
T3C="$TMP/t3c"; mkdir -p "$T3C"
GITDIFF_JSON='{"session_id":"gitdiffcase","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"git diff HEAD"}}'
OUT3C="$( run_hook "$GITDIFF_JSON" "$WITH_RIPWIRE" "$T3C" )"; RC3C=$?
echo "-- git diff case output --"; echo "$OUT3C"; echo "(exit=$RC3C)"
[ "$RC3C" -eq 0 ] && ok "git diff case: exit 0" || no "git diff case: exit was $RC3C"
printf '%s' "$OUT3C" | is_valid_json && ok "git diff case: valid JSON on stdout" \
    || no "git diff case: stdout is not valid JSON"
printf '%s' "$OUT3C" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"allow"' \
    && ok "git diff case: permissionDecision allow" || no "git diff case: missing/wrong permissionDecision"
printf '%s' "$OUT3C" | grep -q -- '--situ' \
    && ok "git diff case: suggestion names --situ" || no "git diff case: suggestion missing --situ"

# --stat, path-limited form also fires (fresh session)
T3C2="$TMP/t3c2"; mkdir -p "$T3C2"
GITDIFFSTAT_JSON='{"session_id":"gitdiffstatcase","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"git diff --stat -- src/foo.cpp"}}'
OUT3C2="$( run_hook "$GITDIFFSTAT_JSON" "$WITH_RIPWIRE" "$T3C2" )"; RC3C2=$?
[ "$RC3C2" -eq 0 ] && printf '%s' "$OUT3C2" | grep -q -- '--situ' \
    && ok "git diff --stat path case: fires and names --situ" \
    || no "git diff --stat path case: exit=$RC3C2 out=[$OUT3C2]"

# ── (3d) git log case (Phase B9): fires, names --rank-by=churn ─────────────────────────────────────
T3D="$TMP/t3d"; mkdir -p "$T3D"
GITLOG_JSON='{"session_id":"gitlogcase","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"git log --oneline -5"}}'
OUT3D="$( run_hook "$GITLOG_JSON" "$WITH_RIPWIRE" "$T3D" )"; RC3D=$?
echo "-- git log case output --"; echo "$OUT3D"; echo "(exit=$RC3D)"
[ "$RC3D" -eq 0 ] && ok "git log case: exit 0" || no "git log case: exit was $RC3D"
printf '%s' "$OUT3D" | is_valid_json && ok "git log case: valid JSON on stdout" \
    || no "git log case: stdout is not valid JSON"
printf '%s' "$OUT3D" | grep -q -- '--rank-by=churn' \
    && ok "git log case: suggestion names --rank-by=churn" || no "git log case: suggestion missing --rank-by=churn"

# ── (3e) git show --stat case (Phase B9): fires, names --map-diff ──────────────────────────────────
T3E="$TMP/t3e"; mkdir -p "$T3E"
GITSHOW_JSON='{"session_id":"gitshowcase","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"git show abc123 --stat"}}'
OUT3E="$( run_hook "$GITSHOW_JSON" "$WITH_RIPWIRE" "$T3E" )"; RC3E=$?
echo "-- git show --stat case output --"; echo "$OUT3E"; echo "(exit=$RC3E)"
[ "$RC3E" -eq 0 ] && ok "git show --stat case: exit 0" || no "git show --stat case: exit was $RC3E"
printf '%s' "$OUT3E" | is_valid_json && ok "git show --stat case: valid JSON on stdout" \
    || no "git show --stat case: stdout is not valid JSON"
printf '%s' "$OUT3E" | grep -q -- '--map-diff' \
    && ok "git show --stat case: suggestion names --map-diff" || no "git show --stat case: suggestion missing --map-diff"

# dedup: a second git-diff call in the SAME session is silent (per-category dedup extends to new categories)
OUT3C_DEDUP="$( run_hook "$GITDIFF_JSON" "$WITH_RIPWIRE" "$T3C" )"; RC3C_DEDUP=$?
[ "$RC3C_DEDUP" -eq 0 ] && [ -z "$OUT3C_DEDUP" ] && ok "git diff dedup: silent on 2nd call (no spam)" \
    || no "git diff dedup: 2nd call was not silent: $OUT3C_DEDUP"

# ── (4) Negative: Bash command that is NOT a recursive grep -> silent ──────────────────────────────
T4="$TMP/t4"; mkdir -p "$T4"
BASHOTHER_JSON='{"session_id":"othercase","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"ls -la"}}'
OUT4="$( run_hook "$BASHOTHER_JSON" "$WITH_RIPWIRE" "$T4" )"; RC4=$?
[ "$RC4" -eq 0 ] && ok "Bash non-grep: exit 0" || no "Bash non-grep: exit was $RC4"
[ -z "$OUT4" ] && ok "Bash non-grep: silent (not a tree-wide search)" || no "Bash non-grep: unexpectedly fired: $OUT4"

# single-file grep (no recursive flag) -> also silent
T4B="$TMP/t4b"; mkdir -p "$T4B"
BASHFILEGREP_JSON='{"session_id":"filegrepcase","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"grep needle one_file.txt"}}'
OUT4B="$( run_hook "$BASHFILEGREP_JSON" "$WITH_RIPWIRE" "$T4B" )"; RC4B=$?
[ "$RC4B" -eq 0 ] && [ -z "$OUT4B" ] && ok "Bash single-file grep: silent (not recursive)" \
    || no "Bash single-file grep: exit=$RC4B out=[$OUT4B], expected silent"

# git status -> silent (Phase B9: state-inspecting but not text-search/diff/log/show-stat; nudging it is spam)
T4D="$TMP/t4d"; mkdir -p "$T4D"
GITSTATUS_JSON='{"session_id":"gitstatuscase","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"git status"}}'
OUT4D="$( run_hook "$GITSTATUS_JSON" "$WITH_RIPWIRE" "$T4D" )"; RC4D=$?
[ "$RC4D" -eq 0 ] && [ -z "$OUT4D" ] && ok "git status: silent (not a diff/log/show-stat)" \
    || no "git status: exit=$RC4D out=[$OUT4D], expected silent"

# git commit -m x -> silent (state-changing commands are never nudged)
T4E="$TMP/t4e"; mkdir -p "$T4E"
GITCOMMIT_JSON='{"session_id":"gitcommitcase","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}'
OUT4E="$( run_hook "$GITCOMMIT_JSON" "$WITH_RIPWIRE" "$T4E" )"; RC4E=$?
[ "$RC4E" -eq 0 ] && [ -z "$OUT4E" ] && ok "git commit: silent (state-changing, never nudged)" \
    || no "git commit: exit=$RC4E out=[$OUT4E], expected silent"

# git add / push / pull / checkout / branch -> silent (same rationale)
T4F="$TMP/t4f"; mkdir -p "$T4F"
ALLSILENT=1
for c in "git add ." "git push" "git pull" "git checkout main" "git branch -a"; do
    J='{"session_id":"gitmisc-'"$(printf '%s' "$c" | tr -c 'a-zA-Z0-9' '_')"'","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"'"$c"'"}}'
    O="$( run_hook "$J" "$WITH_RIPWIRE" "$T4F" )"; R=$?
    if [ "$R" -ne 0 ] || [ -n "$O" ]; then ALLSILENT=0; echo "  (unexpected fire for [$c]: exit=$R out=[$O])"; fi
done
[ "$ALLSILENT" -eq 1 ] && ok "git add/push/pull/checkout/branch: all silent" \
    || no "git add/push/pull/checkout/branch: at least one unexpectedly fired"

# a completely unrelated tool (Edit) -> silent, and fast (no subprocess spawned)
T4C="$TMP/t4c"; mkdir -p "$T4C"
EDIT_JSON='{"session_id":"editcase","cwd":"'"$REPO"'","tool_name":"Edit","tool_input":{"file_path":"x"}}'
START_NS=$(date +%s%N 2>/dev/null || echo 0)
OUT4C="$( run_hook "$EDIT_JSON" "$WITH_RIPWIRE" "$T4C" )"; RC4C=$?
END_NS=$(date +%s%N 2>/dev/null || echo 0)
[ "$RC4C" -eq 0 ] && [ -z "$OUT4C" ] && ok "Other tool (Edit): silent" || no "Other tool (Edit): exit=$RC4C out=[$OUT4C]"
if [ "$START_NS" != "0" ] && [ "$END_NS" != "0" ]; then
    MS=$(( (END_NS - START_NS) / 1000000 ))
    echo "  (Edit-case wall time: ${MS} ms)"
fi

# ── (5) Negative: non-git target dir -> silent even though ripwire is on PATH ──────────────────────
T5="$TMP/t5"; mkdir -p "$T5"
NONGIT_JSON='{"session_id":"nongitcase","cwd":"'"$NONREPO"'","tool_name":"Grep","tool_input":{"pattern":"needle"}}'
OUT5="$( run_hook "$NONGIT_JSON" "$WITH_RIPWIRE" "$T5" )"; RC5=$?
[ "$RC5" -eq 0 ] && [ -z "$OUT5" ] && ok "Non-git dir: silent" || no "Non-git dir: exit=$RC5 out=[$OUT5], expected silent"

# ── (6) Negative: ripwire missing from PATH -> silent even in a git repo ───────────────────────────
T6="$TMP/t6"; mkdir -p "$T6"
NOCTX_JSON='{"session_id":"noctxcase","cwd":"'"$REPO"'","tool_name":"Grep","tool_input":{"pattern":"needle"}}'
OUT6="$( run_hook "$NOCTX_JSON" "$NO_RIPWIRE" "$T6" )"; RC6=$?
[ "$RC6" -eq 0 ] && [ -z "$OUT6" ] && ok "ripwire missing: silent" || no "ripwire missing: exit=$RC6 out=[$OUT6], expected silent"

# ── (7) Different session ids each get their own one-time nudge (dedup is per-session, not global) ─
T7="$TMP/t7"; mkdir -p "$T7"
GREP_JSON_S2='{"session_id":"grepcase2","cwd":"'"$REPO"'","tool_name":"Grep","tool_input":{"pattern":"needle"}}'
OUT7="$( run_hook "$GREP_JSON_S2" "$WITH_RIPWIRE" "$T7" )"; RC7=$?
[ "$RC7" -eq 0 ] && [ -n "$OUT7" ] && ok "New session id: fires independently of case (1)'s dedup marker" \
    || no "New session id: exit=$RC7 out=[$OUT7], expected a fresh nudge"

# ── (8) installer: skills/install.sh --hook writes the documented settings.json snippet ────────────
HOOK_HOME="$TMP/hookhome"; mkdir -p "$HOOK_HOME"
INSTOUT1="$( HOME="$HOOK_HOME" bash "$INSTALL" --hook 2>&1 )"; INSTRC1=$?
SETTINGS="$HOOK_HOME/.claude/settings.json"
echo "-- install.sh --hook output --"; echo "$INSTOUT1"
[ "$INSTRC1" -eq 0 ] && ok "install.sh --hook: exit 0" || no "install.sh --hook: exit was $INSTRC1"
[ -f "$SETTINGS" ] && ok "install.sh --hook: wrote $SETTINGS" || no "install.sh --hook: $SETTINGS not created"
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
    jq -e --arg cmd "$HOOK" 'any((.hooks.PreToolUse // [])[]?.hooks[]?; .command == $cmd)' "$SETTINGS" >/dev/null 2>&1 \
        && ok "settings.json references hooks/ripwire-nudge.sh" \
        || no "settings.json does not reference the hook script"
    jq -e '(.hooks.PreToolUse // [])[] | select(.hooks[]?.command | test("ripwire-nudge")) | .matcher == "Grep|Bash"' \
        "$SETTINGS" >/dev/null 2>&1 \
        && ok "settings.json matcher is Grep|Bash" || no "settings.json matcher missing/wrong"
fi
printf '%s' "$INSTOUT1" | grep -qi 'will add' && ok "install.sh --hook prints what it will change" \
    || no "install.sh --hook did not announce the change before writing it"

# ── (9) installer idempotency: running --hook twice does not duplicate the entry ───────────────────
INSTOUT2="$( HOME="$HOOK_HOME" bash "$INSTALL" --hook 2>&1 )"; INSTRC2=$?
echo "-- install.sh --hook, 2nd run --"; echo "$INSTOUT2"
[ "$INSTRC2" -eq 0 ] && ok "install.sh --hook (2nd run): exit 0" || no "install.sh --hook (2nd run): exit was $INSTRC2"
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
    COUNT="$( jq '[(.hooks.PreToolUse // [])[] | select(.hooks[]?.command | test("ripwire-nudge"))] | length' "$SETTINGS" )"
    [ "$COUNT" = "1" ] && ok "install.sh --hook is idempotent (1 entry after 2 runs)" \
        || no "install.sh --hook duplicated the entry ($COUNT entries after 2 runs)"
fi

# ── (10) installer never bundles --hook into default/--codex/--claude runs ─────────────────────────
DEFAULT_HOME="$TMP/defaulthome"; mkdir -p "$DEFAULT_HOME"
HOME="$DEFAULT_HOME" bash "$INSTALL" >/dev/null 2>&1
[ -f "$DEFAULT_HOME/.claude/settings.json" ] \
    && no "default install.sh (no flag) touched settings.json — --hook must be opt-in only" \
    || ok "default install.sh (no flag) never touches settings.json"

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
