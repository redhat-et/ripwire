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

# ── (3f) Read case (2026-08-10 audit): fires, names --expand, allow-never-deny ─────────────────────
# The read nudge is the load-bearing one: whole-file reads are the largest token sink in an agent loop
# and the only default a skill description cannot intercept.
T3F="$TMP/t3f"; mkdir -p "$T3F"
READ_JSON='{"session_id":"readcase","cwd":"'"$REPO"'","tool_name":"Read","tool_input":{"file_path":"src/foo.cpp"}}'
OUT3F="$( run_hook "$READ_JSON" "$WITH_RIPWIRE" "$T3F" )"; RC3F=$?
echo "-- Read case output --"; echo "$OUT3F"; echo "(exit=$RC3F)"
[ "$RC3F" -eq 0 ] && ok "Read case: exit 0" || no "Read case: exit was $RC3F"
printf '%s' "$OUT3F" | is_valid_json && ok "Read case: valid JSON on stdout" \
    || no "Read case: stdout is not valid JSON"
printf '%s' "$OUT3F" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"allow"' \
    && ok "Read case: permissionDecision allow" || no "Read case: missing/wrong permissionDecision"
printf '%s' "$OUT3F" | grep -qi 'deny\|"ask"' \
    && no "Read case: output mentions deny/ask (must never)" || ok "Read case: no deny/ask anywhere"
printf '%s' "$OUT3F" | grep -q -- '--expand' \
    && ok "Read case: suggestion names --expand" || no "Read case: suggestion missing --expand"

# dedup within the read category
OUT3F2="$( run_hook "$READ_JSON" "$WITH_RIPWIRE" "$T3F" )"; RC3F2=$?
[ "$RC3F2" -eq 0 ] && [ -z "$OUT3F2" ] && ok "Read dedup: silent on 2nd call" \
    || no "Read dedup: 2nd call was not silent: $OUT3F2"

# a Grep in the SAME session still fires: read and grep are different habits, deduped separately
GREP_SAME='{"session_id":"readcase","cwd":"'"$REPO"'","tool_name":"Grep","tool_input":{"pattern":"x"}}'
OUT3F3="$( run_hook "$GREP_SAME" "$WITH_RIPWIRE" "$T3F" )"; RC3F3=$?
[ "$RC3F3" -eq 0 ] && [ -n "$OUT3F3" ] \
    && ok "Read and Grep dedup independently (different habits, one nudge each)" \
    || no "Read/Grep share a dedup marker: exit=$RC3F3 out=[$OUT3F3]"

# ── (3g) Glob case: fires, names --for ─────────────────────────────────────────────────────────────
T3G="$TMP/t3g"; mkdir -p "$T3G"
GLOB_JSON='{"session_id":"globcase","cwd":"'"$REPO"'","tool_name":"Glob","tool_input":{"pattern":"**/*.cpp"}}'
OUT3G="$( run_hook "$GLOB_JSON" "$WITH_RIPWIRE" "$T3G" )"; RC3G=$?
echo "-- Glob case output --"; echo "$OUT3G"; echo "(exit=$RC3G)"
[ "$RC3G" -eq 0 ] && ok "Glob case: exit 0" || no "Glob case: exit was $RC3G"
printf '%s' "$OUT3G" | is_valid_json && ok "Glob case: valid JSON on stdout" \
    || no "Glob case: stdout is not valid JSON"
printf '%s' "$OUT3G" | grep -q -- '--for' \
    && ok "Glob case: suggestion names --for" || no "Glob case: suggestion missing --for"

# ── (3h) Read/Glob degrade to silence off their preconditions, same as every other category ────────
T3H="$TMP/t3h"; mkdir -p "$T3H"
READ_NONGIT='{"session_id":"readnongit","cwd":"'"$NONREPO"'","tool_name":"Read","tool_input":{"file_path":"x"}}'
OUT3H="$( run_hook "$READ_NONGIT" "$WITH_RIPWIRE" "$T3H" )"; RC3H=$?
[ "$RC3H" -eq 0 ] && [ -z "$OUT3H" ] && ok "Read in non-git dir: silent" \
    || no "Read in non-git dir: exit=$RC3H out=[$OUT3H]"
T3H2="$TMP/t3h2"; mkdir -p "$T3H2"
OUT3H2="$( run_hook "$READ_JSON" "$NO_RIPWIRE" "$T3H2" )"; RC3H2=$?
[ "$RC3H2" -eq 0 ] && [ -z "$OUT3H2" ] && ok "Read with ripwire off PATH: silent" \
    || no "Read with ripwire off PATH: exit=$RC3H2 out=[$OUT3H2]"

# ── (3i) SessionStart mode: emits the wrap blurb as additionalContext, once ────────────────────────
# The blurb is EXTRACTED from `ripwire wrap claude`, so this also pins that the two cannot drift. Needs
# the REAL binary (the stub cannot emit a wrap recipe), so it is skipped when one isn't available.
REALBIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${REALBIN#/}" = "$REALBIN" ] && REALBIN="$ROOT/$REALBIN"
if [ -x "$REALBIN" ]; then
    RBIN="$TMP/realbin"; mkdir -p "$RBIN"; ln -sf "$REALBIN" "$RBIN/ripwire"
    WITH_REAL="$RBIN:$PATH"
    T3I="$TMP/t3i"; mkdir -p "$T3I"
    SS_JSON='{"session_id":"sscase","cwd":"'"$REPO"'","source":"startup"}'
    OUT3I="$( printf '%s' "$SS_JSON" | PATH="$WITH_REAL" TMPDIR="$T3I" bash "$HOOK" --session-start )"; RC3I=$?
    echo "-- SessionStart case (first 3 lines) --"; printf '%s' "$OUT3I" | head -c 300; echo; echo "(exit=$RC3I)"
    [ "$RC3I" -eq 0 ] && ok "SessionStart: exit 0" || no "SessionStart: exit was $RC3I"
    printf '%s' "$OUT3I" | is_valid_json && ok "SessionStart: valid JSON on stdout" \
        || no "SessionStart: stdout is not valid JSON"
    printf '%s' "$OUT3I" | grep -q '"hookEventName"[[:space:]]*:[[:space:]]*"SessionStart"' \
        && ok "SessionStart: hookEventName is SessionStart" || no "SessionStart: wrong/missing hookEventName"
    printf '%s' "$OUT3I" | grep -qi 'deny\|"permissionDecision"' \
        && no "SessionStart: must not carry a permission decision" || ok "SessionStart: no permission decision"
    # the injected text is the wrap blurb: it must carry the prohibition block, which is the whole point
    printf '%s' "$OUT3I" | grep -q 'Do NOT open a file you have not located first' \
        && ok "SessionStart: injects the wrap blurb's prohibition block" \
        || no "SessionStart: injected text is missing the prohibitions (drifted from src/wrap.h?)"
    OUT3I2="$( printf '%s' "$SS_JSON" | PATH="$WITH_REAL" TMPDIR="$T3I" bash "$HOOK" --session-start )"; RC3I2=$?
    [ "$RC3I2" -eq 0 ] && [ -z "$OUT3I2" ] && ok "SessionStart dedup: silent on 2nd call" \
        || no "SessionStart dedup: 2nd call was not silent"
    T3I3="$TMP/t3i3"; mkdir -p "$T3I3"
    SS_NONGIT='{"session_id":"ssnongit","cwd":"'"$NONREPO"'","source":"startup"}'
    OUT3I3="$( printf '%s' "$SS_NONGIT" | PATH="$WITH_REAL" TMPDIR="$T3I3" bash "$HOOK" --session-start )"; RC3I3=$?
    [ "$RC3I3" -eq 0 ] && [ -z "$OUT3I3" ] && ok "SessionStart in non-git dir: silent" \
        || no "SessionStart in non-git dir: exit=$RC3I3 out=[$OUT3I3]"
else
    echo "  SKIP  SessionStart checks (no real binary at $REALBIN)"
fi

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
    jq -e '(.hooks.PreToolUse // [])[] | select(.hooks[]?.command | test("ripwire-nudge")) | .matcher == "Read|Glob|Grep|Bash|mcp__ripwire__"' \
        "$SETTINGS" >/dev/null 2>&1 \
        && ok "settings.json PreToolUse matcher is Read|Glob|Grep|Bash|mcp__ripwire__" || no "settings.json PreToolUse matcher missing/wrong"
    # Read/Glob are load-bearing, not incidental: the whole-file read is the largest token sink in the
    # loop and the one default no skill description can intercept. Assert them by NAME so a future
    # matcher edit that quietly drops them fails here.
    for m in Read Glob Grep Bash; do
        jq -e --arg m "$m" '(.hooks.PreToolUse // [])[] | select(.hooks[]?.command | test("ripwire-nudge")) | .matcher | test($m)' \
            "$SETTINGS" >/dev/null 2>&1 \
            && ok "PreToolUse matcher covers $m" || no "PreToolUse matcher lost $m"
    done
    jq -e '(.hooks.SessionStart // [])[] | select(.hooks[]?.command | test("ripwire-nudge.*--session-start"))' \
        "$SETTINGS" >/dev/null 2>&1 \
        && ok "settings.json registers the SessionStart primer hook" || no "SessionStart primer hook not registered"
fi
printf '%s' "$INSTOUT1" | grep -qi 'will add' && ok "install.sh --hook prints what it will change" \
    || no "install.sh --hook did not announce the change before writing it"

# ── (9) installer idempotency: running --hook twice does not duplicate the entry ───────────────────
INSTOUT2="$( HOME="$HOOK_HOME" bash "$INSTALL" --hook 2>&1 )"; INSTRC2=$?
echo "-- install.sh --hook, 2nd run --"; echo "$INSTOUT2"
[ "$INSTRC2" -eq 0 ] && ok "install.sh --hook (2nd run): exit 0" || no "install.sh --hook (2nd run): exit was $INSTRC2"
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
    COUNT="$( jq '[(.hooks.PreToolUse // [])[] | select(.hooks[]?.command | test("ripwire-nudge"))] | length' "$SETTINGS" )"
    [ "$COUNT" = "1" ] && ok "install.sh --hook is idempotent (1 PreToolUse entry after 2 runs)" \
        || no "install.sh --hook duplicated the PreToolUse entry ($COUNT entries after 2 runs)"
    SCOUNT="$( jq '[(.hooks.SessionStart // [])[] | select(.hooks[]?.command | test("ripwire-nudge"))] | length' "$SETTINGS" )"
    [ "$SCOUNT" = "1" ] && ok "install.sh --hook is idempotent (1 SessionStart entry after 2 runs)" \
        || no "install.sh --hook duplicated the SessionStart entry ($SCOUNT entries after 2 runs)"
fi

# ── (10) installer never bundles --hook into default/--codex/--claude runs ─────────────────────────
DEFAULT_HOME="$TMP/defaulthome"; mkdir -p "$DEFAULT_HOME"
HOME="$DEFAULT_HOME" bash "$INSTALL" >/dev/null 2>&1
[ -f "$DEFAULT_HOME/.claude/settings.json" ] \
    && no "default install.sh (no flag) touched settings.json — --hook must be opt-in only" \
    || ok "default install.sh (no flag) never touches settings.json"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# (11) THE SUBSTITUTION METER (Track B §S2, 2026-08-11)
#
# The hook's second job: one JSONL row per observed tool call, appended to ONE GLOBAL log
# (~/.ripwire/substitution.jsonl) so a session in any repo feeds the same denominator. The unit of
# observation is a TOOL CALL, not a task — the task-success outcome eval is dead on power grounds
# (8.5-26pp MDE floor), and substitution per call is the measurement that survives that arithmetic.
#
# What these arms pin, and why each one is here rather than left to inspection:
#   - a row exists at all, at the DEFAULT global path, lazily created (M1-M3);
#   - the counted call and the nudge are SEPARABLE: nudged/nudge/post_nudge are logged per row, so
#     "the nudge caused the next ripwire call" stays a distinguishable hypothesis (M4-M7);
#   - rtk's rewrite is UNWRAPPED (M8-M9). `rtk grep …` is what the Bash hook actually sees on this
#     machine; a meter that scores it as "not a grep" would report a substitution rate that is pure
#     artifact of another tool's hook;
#   - ripwire's own calls are the NUMERATOR and are never nudged (M10-M12);
#   - the truer denominator: native read/find/awk-search forms, not just Grep/Glob (M13-M15);
#   - ambiguity is LOGGED, never dropped (M16), and out-of-scope calls are not rows (M17);
#   - the A/B toggle exists and is logged NOW, dormant, so phase 2 costs an env var (M19-M20);
#   - and the whole thing is subordinate to the tool call it observes: an unwritable log must cost
#     the hooked command nothing (M21).
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

METERHOME="$TMP/meterhome"; mkdir -p "$METERHOME"
DEFAULT_LOG="$METERHOME/.ripwire/substitution.jsonl"

run_meter()
{
    # run_meter LOGFILE JSON TMPDIRVAL [VAR=VAL ...]  — LOGFILE "" means "use the ~/.ripwire default"
    _l="$1"; _j="$2"; _t="$3"; shift 3
    if [ -n "$_l" ]; then
        printf '%s' "$_j" | env HOME="$METERHOME" RIPWIRE_METER_LOG="$_l" PATH="$WITH_RIPWIRE" TMPDIR="$_t" "$@" bash "$HOOK"
    else
        printf '%s' "$_j" | env HOME="$METERHOME" PATH="$WITH_RIPWIRE" TMPDIR="$_t" "$@" bash "$HOOK"
    fi
}

meterrows()   { [ -f "$1" ] && grep -c . "$1" 2>/dev/null || echo 0; }
meterrowget() {
    # meterrowget FILE ROWINDEX KEY   (1-based; also validates that every row parses as JSON)
    python3 - "$1" "$2" "$3" <<'PY' 2>/dev/null
import json, sys
path, idx, key = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rows = [json.loads(l) for l in open(path) if l.strip()]
print("" if len(rows) < idx else rows[idx - 1].get(key, "<missing>"))
PY
}
bashjson() { printf '{"session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" "$REPO" "$2"; }

# ── M1-M3: a classified call writes one row, at the DEFAULT global path, with the full field set ────
TM1="$TMP/tm1"; mkdir -p "$TM1"
M1_JSON='{"session_id":"meter1","cwd":"'"$REPO"'","tool_name":"Grep","tool_input":{"pattern":"needle"}}'
run_meter "" "$M1_JSON" "$TM1" >/dev/null 2>&1; RCM1=$?
echo "-- meter default-path row --"; [ -f "$DEFAULT_LOG" ] && cat "$DEFAULT_LOG"
[ "$RCM1" -eq 0 ] && ok "M1 meter: hooked call still exits 0" || no "M1 meter: exit was $RCM1"
[ "$( meterrows "$DEFAULT_LOG" )" = "1" ] \
    && ok "M1 meter: one row lazily created at ~/.ripwire/substitution.jsonl" \
    || no "M1 meter: expected 1 row at $DEFAULT_LOG, got $( meterrows "$DEFAULT_LOG" )"
M2_MISSING=""
for k in v ts seq session repo tag tool class family nudged nudge post_nudge post_sweep arm detail; do
    val="$( meterrowget "$DEFAULT_LOG" 1 "$k" )"
    case "$val" in ""|"<missing>") M2_MISSING="$M2_MISSING $k" ;; esac
done
# `nudged`/`post_nudge`/`post_sweep` are legitimately 0 and `detail` legitimately empty — by presence
for k in nudged post_nudge post_sweep detail; do
    python3 -c 'import json,sys; d=json.loads(open(sys.argv[1]).readline()); sys.exit(0 if sys.argv[2] in d else 1)' \
        "$DEFAULT_LOG" "$k" 2>/dev/null && M2_MISSING="$( printf '%s' "$M2_MISSING" | sed "s/ $k//" )"
done
[ -z "$M2_MISSING" ] && ok "M2 meter: row carries the full documented field set" \
    || no "M2 meter: row is missing field(s):$M2_MISSING"
[ "$( meterrowget "$DEFAULT_LOG" 1 class )" = "grep" ] && [ "$( meterrowget "$DEFAULT_LOG" 1 family )" = "native" ] \
    && ok "M3 meter: Grep tool classifies as grep/native" \
    || no "M3 meter: Grep tool classified as [$( meterrowget "$DEFAULT_LOG" 1 class )/$( meterrowget "$DEFAULT_LOG" 1 family )]"

# ── M4-M7: the nudge and the count are separable — nudged, dedup, seq, post_nudge ───────────────────
TM4="$TMP/tm4"; mkdir -p "$TM4"; L4="$TMP/m4.jsonl"
M4_JSON='{"session_id":"meter4","cwd":"'"$REPO"'","tool_name":"Grep","tool_input":{"pattern":"n"}}'
OUTM4="$( run_meter "$L4" "$M4_JSON" "$TM4" )"
[ "$( meterrowget "$L4" 1 nudged )" = "1" ] && [ "$( meterrowget "$L4" 1 nudge )" = "fired" ] && [ -n "$OUTM4" ] \
    && ok "M4 meter: the call the nudge fired on is logged nudged=1 nudge=fired" \
    || no "M4 meter: nudged=[$( meterrowget "$L4" 1 nudged )] nudge=[$( meterrowget "$L4" 1 nudge )] out=[${OUTM4:+set}]"
OUTM5="$( run_meter "$L4" "$M4_JSON" "$TM4" )"
[ "$( meterrows "$L4" )" = "2" ] && [ "$( meterrowget "$L4" 2 nudged )" = "0" ] && [ "$( meterrowget "$L4" 2 nudge )" = "dedup" ] && [ -z "$OUTM5" ] \
    && ok "M5 meter: a deduped (silent) call is STILL counted, as nudged=0 nudge=dedup" \
    || no "M5 meter: rows=$( meterrows "$L4" ) nudged=[$( meterrowget "$L4" 2 nudged )] nudge=[$( meterrowget "$L4" 2 nudge )] out=[$OUTM5]"
[ "$( meterrowget "$L4" 1 seq )" = "1" ] && [ "$( meterrowget "$L4" 2 seq )" = "2" ] \
    && ok "M6 meter: seq is monotonic within a session (1,2) — sequences are reconstructable" \
    || no "M6 meter: seq was [$( meterrowget "$L4" 1 seq )] then [$( meterrowget "$L4" 2 seq )]"
[ "$( meterrowget "$L4" 1 post_nudge )" = "0" ] && [ "$( meterrowget "$L4" 2 post_nudge )" = "1" ] \
    && ok "M7 meter: post_nudge separates pre-nudge from post-nudge calls in a session" \
    || no "M7 meter: post_nudge was [$( meterrowget "$L4" 1 post_nudge )] then [$( meterrowget "$L4" 2 post_nudge )]"

# ── M8-M9: the rtk unwrap. `rtk grep …` / `rtk proxy rg …` are what the hook actually sees here ─────
TM8="$TMP/tm8"; mkdir -p "$TM8"; L8="$TMP/m8.jsonl"
run_meter "$L8" "$( bashjson meter8 'rtk grep -rn needle .' )" "$TM8" >/dev/null 2>&1
[ "$( meterrowget "$L8" 1 class )" = "grep" ] \
    && ok "M8 meter: rtk unwrap — 'rtk grep -rn …' classifies as grep" \
    || no "M8 meter: 'rtk grep -rn …' classified as [$( meterrowget "$L8" 1 class )], expected grep"
TM9="$TMP/tm9"; mkdir -p "$TM9"; L9="$TMP/m9.jsonl"
run_meter "$L9" "$( bashjson meter9 'rtk proxy rg needle src/' )" "$TM9" >/dev/null 2>&1
[ "$( meterrowget "$L9" 1 class )" = "grep" ] \
    && ok "M9 meter: rtk unwrap — 'rtk proxy rg …' classifies as grep" \
    || no "M9 meter: 'rtk proxy rg …' classified as [$( meterrowget "$L9" 1 class )], expected grep"

# ── M10-M12: ripwire's own calls are the numerator, and are never nudged ────────────────────────────
TM10="$TMP/tm10"; mkdir -p "$TM10"; L10="$TMP/m10.jsonl"
OUTM10="$( run_meter "$L10" "$( bashjson meter10 'ripwire . --grep=needle' )" "$TM10" )"
[ "$( meterrowget "$L10" 1 class )" = "ripwire-cli" ] && [ "$( meterrowget "$L10" 1 family )" = "ripwire" ] \
    && ok "M10 meter: a ripwire CLI call classifies as ripwire-cli/ripwire (the numerator)" \
    || no "M10 meter: ripwire CLI classified as [$( meterrowget "$L10" 1 class )/$( meterrowget "$L10" 1 family )]"
[ -z "$OUTM10" ] && [ "$( meterrowget "$L10" 1 nudged )" = "0" ] \
    && ok "M11 meter: a ripwire invocation is never nudged (no 'use ripwire' at a ripwire call)" \
    || no "M11 meter: ripwire call was nudged: out=[$OUTM10] nudged=[$( meterrowget "$L10" 1 nudged )]"
TM12="$TMP/tm12"; mkdir -p "$TM12"; L12="$TMP/m12.jsonl"
MCP_JSON='{"session_id":"meter12","cwd":"'"$REPO"'","tool_name":"mcp__ripwire__for","tool_input":{"task":"x"}}'
OUTM12="$( run_meter "$L12" "$MCP_JSON" "$TM12" )"
[ "$( meterrowget "$L12" 1 class )" = "ripwire-mcp" ] && [ -z "$OUTM12" ] \
    && ok "M12 meter: an MCP ripwire verb classifies as ripwire-mcp and is silent" \
    || no "M12 meter: mcp verb classified as [$( meterrowget "$L12" 1 class )] out=[$OUTM12]"

# ── M13-M15: the TRUER denominator — native read/search forms the old hook never looked at ──────────
TM13="$TMP/tm13"; mkdir -p "$TM13"; L13="$TMP/m13.jsonl"
M13BAD=""
i=0
for pair in "cat src/foo.cpp|read" "head -50 src/foo.cpp|read" "tail -n 20 log.txt|read" \
            "find . -name '*.cpp'|find" "ls -R src|find" "awk '/needle/ {print}' f.txt|grep" \
            "git grep needle|grep" "sed -n '1,80p' src/foo.cpp|read"; do
    c="${pair%|*}"; want="${pair#*|}"; i=$(( i + 1 ))
    run_meter "$L13" "$( bashjson "meter13_$i" "$( printf '%s' "$c" | sed 's/"/\\"/g' )" )" "$TM13" >/dev/null 2>&1
    got="$( meterrowget "$L13" "$i" class )"
    [ "$got" = "$want" ] || M13BAD="$M13BAD [$c -> $got, want $want]"
done
[ -z "$M13BAD" ] && ok "M13 meter: native read/search Bash forms classify (cat/head/tail/find/ls -R/awk/git grep/sed -n)" \
    || no "M13 meter: misclassified:$M13BAD"
TM14="$TMP/tm14"; mkdir -p "$TM14"; L14="$TMP/m14.jsonl"
run_meter "$L14" '{"session_id":"meter14","cwd":"'"$REPO"'","tool_name":"Read","tool_input":{"file_path":"src/foo.cpp"}}' "$TM14" >/dev/null 2>&1
run_meter "$L14" '{"session_id":"meter14","cwd":"'"$REPO"'","tool_name":"Glob","tool_input":{"pattern":"**/*.cpp"}}' "$TM14" >/dev/null 2>&1
[ "$( meterrowget "$L14" 1 class )" = "read" ] && [ "$( meterrowget "$L14" 2 class )" = "glob" ] \
    && ok "M14 meter: Read -> read, Glob -> glob" \
    || no "M14 meter: Read/Glob classified as [$( meterrowget "$L14" 1 class )/$( meterrowget "$L14" 2 class )]"
TM15="$TMP/tm15"; mkdir -p "$TM15"; L15="$TMP/m15.jsonl"
run_meter "$L15" "$( bashjson meter15 'git diff HEAD' )" "$TM15" >/dev/null 2>&1
[ "$( meterrowget "$L15" 1 class )" = "git-diff" ] && [ "$( meterrowget "$L15" 1 family )" = "git" ] && [ "$( meterrowget "$L15" 1 nudged )" = "1" ] \
    && ok "M15 meter: git diff -> git-diff/git, and the nudge it fires is recorded on the row" \
    || no "M15 meter: git diff row = [$( meterrowget "$L15" 1 class )/$( meterrowget "$L15" 1 family )/nudged=$( meterrowget "$L15" 1 nudged )]"

# ── M16-M17: ambiguity is logged, out-of-scope is not a row ─────────────────────────────────────────
TM16="$TMP/tm16"; mkdir -p "$TM16"; L16="$TMP/m16.jsonl"
run_meter "$L16" "$( bashjson meter16 'for f in *.c; do grep needle $f; done' )" "$TM16" >/dev/null 2>&1
[ "$( meterrowget "$L16" 1 class )" = "unclassified" ] \
    && ok "M16 meter: an ambiguous search line is logged as unclassified, never silently dropped" \
    || no "M16 meter: ambiguous line classified as [$( meterrowget "$L16" 1 class )], expected unclassified"
# M17 changed contract at S2b (2026-08-11). `cmake --build` and `git status` used to write no row;
# they now write `build`/`git-misc` rows, because Track B §S4 ranks the absorption queue from the
# command mix an agent ACTUALLY runs and a class that writes no row is one that survey cannot see.
# What must still write no row is a line this meter has no name for at all.
TM17="$TMP/tm17"; mkdir -p "$TM17"; L17="$TMP/m17.jsonl"
run_meter "$L17" "$( bashjson meter17 'npx create-thing --yes' )" "$TM17" >/dev/null 2>&1
run_meter "$L17" "$( bashjson meter17b 'brew upgrade' )" "$TM17" >/dev/null 2>&1
[ "$( meterrows "$L17" )" = "0" ] \
    && ok "M17 meter: a Bash line this meter has no name for still writes no row" \
    || no "M17 meter: unnamed commands wrote $( meterrows "$L17" ) row(s): $( cat "$L17" 2>/dev/null )"

# ── M18: ONE global log across repos, rows tagged by repo ───────────────────────────────────────────
REPO2="$TMP/repo2"; mkdir -p "$REPO2"; git -C "$REPO2" init -q
git -C "$REPO2" config user.email "dev@x.com"; git -C "$REPO2" config user.name "Dev"
TM18="$TMP/tm18"; mkdir -p "$TM18"
run_meter "" '{"session_id":"meter18","cwd":"'"$REPO2"'","tool_name":"Grep","tool_input":{"pattern":"n"}}' "$TM18" >/dev/null 2>&1
LASTROW="$( meterrows "$DEFAULT_LOG" )"
[ "$LASTROW" = "2" ] && [ "$( meterrowget "$DEFAULT_LOG" 2 tag )" = "repo2" ] && [ "$( meterrowget "$DEFAULT_LOG" 1 tag )" = "repo" ] \
    && ok "M18 meter: two repos append to the ONE global log, each row tagged by repo" \
    || no "M18 meter: global log has $LASTROW row(s), tags [$( meterrowget "$DEFAULT_LOG" 1 tag )/$( meterrowget "$DEFAULT_LOG" 2 tag )]"

# ── M19-M20: the dormant A/B toggle. Ships built, ships OFF; the arm is on every row ────────────────
TM19="$TMP/tm19"; mkdir -p "$TM19"; L19="$TMP/m19.jsonl"
OUTM19="$( run_meter "$L19" "$( bashjson meter19 'grep -rn needle .' )" "$TM19" RIPWIRE_METER_ARM=control )"
[ "$( meterrowget "$L19" 1 arm )" = "control" ] && [ "$( meterrowget "$L19" 1 nudged )" = "0" ] \
    && [ "$( meterrowget "$L19" 1 nudge )" = "control" ] && [ -z "$OUTM19" ] \
    && ok "M19 meter: control arm counts the call and suppresses the nudge, and says so on the row" \
    || no "M19 meter: arm=[$( meterrowget "$L19" 1 arm )] nudged=[$( meterrowget "$L19" 1 nudged )] nudge=[$( meterrowget "$L19" 1 nudge )] out=[$OUTM19]"
TM20="$TMP/tm20"; mkdir -p "$TM20"; L20="$TMP/m20.jsonl"
OUTM20="$( run_meter "$L20" "$( bashjson meter20 'grep -rn needle .' )" "$TM20" )"
[ "$( meterrowget "$L20" 1 arm )" = "treatment" ] && [ -n "$OUTM20" ] \
    && ok "M20 meter: DEFAULT arm is treatment — observation is always on, alternation is not" \
    || no "M20 meter: default arm=[$( meterrowget "$L20" 1 arm )] out=[${OUTM20:+set}]"

# ── M21-M23: the meter is subordinate to the call it observes ───────────────────────────────────────
TM21="$TMP/tm21"; mkdir -p "$TM21"
UNWRITABLE="$TMP/unwritable"; mkdir -p "$UNWRITABLE"; chmod 500 "$UNWRITABLE"
OUTM21="$( printf '%s' "$( bashjson meter21 'grep -rn needle .' )" \
    | env HOME="$UNWRITABLE" PATH="$WITH_RIPWIRE" TMPDIR="$TM21" bash "$HOOK" )"; RCM21=$?
chmod 700 "$UNWRITABLE"
[ "$RCM21" -eq 0 ] && [ -n "$OUTM21" ] && printf '%s' "$OUTM21" | is_valid_json \
    && ok "M21 meter: an unwritable log costs the hooked command nothing (exit 0, nudge still emitted)" \
    || no "M21 meter: unwritable log broke the hook: exit=$RCM21 out=[$OUTM21]"
TM22="$TMP/tm22"; mkdir -p "$TM22"; L22="$TMP/m22.jsonl"
OUTM22="$( run_meter "$L22" "$( bashjson meter22 'grep -rn needle .' )" "$TM22" RIPWIRE_METER=0 )"
[ "$( meterrows "$L22" )" = "0" ] && [ -n "$OUTM22" ] \
    && ok "M22 meter: RIPWIRE_METER=0 opts out of counting only — the nudge still works" \
    || no "M22 meter: opt-out left $( meterrows "$L22" ) row(s), out=[${OUTM22:+set}]"
TM23="$TMP/tm23"; mkdir -p "$TM23"; L23="$TMP/m23.jsonl"
run_meter "$L23" '{"session_id":"meter23","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"grep -rn \"a\\nb\" ."}}' "$TM23" >/dev/null 2>&1
[ "$( meterrows "$L23" )" = "1" ] && [ "$( wc -l <"$L23" | tr -d ' ' )" = "1" ] \
    && ok "M23 meter: one row is exactly one line (JSONL holds for embedded newlines/quotes)" \
    || no "M23 meter: multi-line command produced $( wc -l <"$L23" 2>/dev/null | tr -d ' ' ) line(s)"

# ── M23b: a TMPDIR that does not exist — silent, and the sequence number survives ───────────────────
# Found by hand, then gated: `cmd >>f 2>/dev/null` opens the redirect BEFORE applying 2>/dev/null, so a
# missing directory printed two lines of shell error onto the hooked call's stderr and left seq=0. A
# meter that narrates its own failures into the tool it observes is worse than no meter.
L23B="$TMP/m23b.jsonl"
ERR23B="$TMP/m23b.err"
run_meter "$L23B" "$( bashjson meter23b 'grep -rn needle .' )" "$TMP/does/not/exist" >/dev/null 2>"$ERR23B"
[ ! -s "$ERR23B" ] && ok "M23b meter: a non-existent TMPDIR writes nothing to the hooked call's stderr" \
    || no "M23b meter: stderr leaked: $( cat "$ERR23B" )"
[ "$( meterrowget "$L23B" 1 seq )" = "1" ] \
    && ok "M23b meter: the per-session counter survives a non-existent TMPDIR (seq=1, not 0)" \
    || no "M23b meter: seq was [$( meterrowget "$L23B" 1 seq )] under a missing TMPDIR"

# ── M23c: a quote-bearing command line still yields exactly one valid JSON row ──────────────────────
# jq builds the row when it is on PATH; without it the hook hand-escapes. Either way an embedded quote
# or backslash is the one input that can corrupt a JSONL log, so it is gated directly.
TM23C="$TMP/tm23c"; mkdir -p "$TM23C"; L23C="$TMP/m23c.jsonl"
printf '%s' '{"session_id":"meter23c","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"rtk grep -rn \"a\\\\\"b\" ."}}' \
    | env HOME="$METERHOME" RIPWIRE_METER_LOG="$L23C" PATH="$WITH_RIPWIRE" TMPDIR="$TM23C" bash "$HOOK" >/dev/null 2>&1
[ "$( meterrows "$L23C" )" = "1" ] && [ "$( meterrowget "$L23C" 1 class )" = "grep" ] \
    && ok "M23c meter: a quote-bearing command yields exactly one valid JSON row" \
    || no "M23c meter: rows=$( meterrows "$L23C" ) class=[$( meterrowget "$L23C" 1 class )] — see $L23C"

# ── M24: SessionStart is a countable session boundary ───────────────────────────────────────────────
TM24="$TMP/tm24"; mkdir -p "$TM24"; L24="$TMP/m24.jsonl"
printf '%s' '{"session_id":"meter24","cwd":"'"$REPO"'","source":"startup"}' \
    | env HOME="$METERHOME" RIPWIRE_METER_LOG="$L24" PATH="$WITH_RIPWIRE" TMPDIR="$TM24" bash "$HOOK" --session-start >/dev/null 2>&1
[ "$( meterrowget "$L24" 1 class )" = "session-start" ] && [ "$( meterrowget "$L24" 1 family )" = "meta" ] \
    && ok "M24 meter: SessionStart writes a session-start/meta row (sessions are countable)" \
    || no "M24 meter: session-start row = [$( meterrowget "$L24" 1 class )/$( meterrowget "$L24" 1 family )]"

# ── M25: the installer's matcher makes MCP ripwire verbs visible to the hook ────────────────────────
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
    jq -e '(.hooks.PreToolUse // [])[] | select(.hooks[]?.command | test("ripwire-nudge")) | .matcher | test("mcp__ripwire__")' \
        "$SETTINGS" >/dev/null 2>&1 \
        && ok "M25 meter: install.sh --hook matcher covers mcp__ripwire__ (the numerator is observable)" \
        || no "M25 meter: PreToolUse matcher does not cover mcp__ripwire__ — MCP verbs invisible to the meter"
fi

# ── M26-M27: the schema doc and the analysis stub are part of the deliverable, not an afterthought ──
SCHEMADOC="$ROOT/docs/SUBSTITUTION_METER.md"
REPORT="$ROOT/bench/substitution_report.py"
if [ -f "$SCHEMADOC" ]; then
    M26MISS=""
    for needle in 'substitution.jsonl' 'rtk' 'MCP' 'unclassified' 'RIPWIRE_METER_ARM' 'post_nudge'; do
        grep -Fq "$needle" "$SCHEMADOC" || M26MISS="$M26MISS $needle"
    done
    [ -z "$M26MISS" ] && ok "M26 meter: docs/SUBSTITUTION_METER.md documents the schema, rtk unwrap and the MCP disclosure" \
        || no "M26 meter: docs/SUBSTITUTION_METER.md is missing:$M26MISS"
else
    no "M26 meter: docs/SUBSTITUTION_METER.md does not exist"
fi
if [ -f "$REPORT" ]; then
    python3 "$REPORT" "$DEFAULT_LOG" >"$TMP/report.out" 2>&1; RCR=$?
    echo "-- substitution_report.py output --"; cat "$TMP/report.out"
    [ "$RCR" -eq 0 ] && grep -qi 'substitution rate' "$TMP/report.out" \
        && ok "M27 meter: bench/substitution_report.py reads the log and prints a substitution rate" \
        || no "M27 meter: substitution_report.py exit=$RCR (see output above)"
    grep -qiE 'bigram|n-gram|ngram' "$TMP/report.out" \
        && ok "M27b meter: the report prints within-session command-class n-grams (scenario bundles)" \
        || no "M27b meter: the report has no n-gram section"
else
    no "M26 meter: bench/substitution_report.py does not exist"
    no "M27b meter: bench/substitution_report.py does not exist"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# (12) §SWEEP — the sweep-escalation nudge, and the widened classifier  (Track B §S2b, 2026-08-12)
#
# WHY THIS SECTION EXISTS. The meter's first 12 hours measured the one-time nudges converting at
# ZERO — 455 fired, substitution after them 0.8%, indistinguishable from before them — while the
# dominant behaviour was the SAME-CLASS SWEEP (grep→grep→grep ×357 as a trigram, read×3 ×187,
# git-diff×3 ×119). The escalation is the falsifiable response: at the Nth call of a class, say the
# EXACT command instead of the verb. Its efficacy verdict is pre-registered in docs/EVALS.md §4 and
# is NOT this gate's business — this gate pins the mechanism's contract, all of which is behaviour a
# reader would otherwise have to take on trust:
#
#   - it fires at N and not before, exactly once per class per session (S1-S4, S10);
#   - the text is PASTE-READY: the grep escalation carries the agent's own patterns inside a runnable
#     --for="…", the read escalation the directory of the file just read (S2, S7, S14) — a nudge that
#     names a verb and an ellipsis is the thing measured not to work;
#   - the escalation is RECORDED (nudge=sweep3 on the firing row, post_sweep=1 after it), because an
#     unmeasurable nudge is one nobody can ever turn off on evidence (S5);
#   - it never blocks, never denies, degrades to silence off its preconditions (S6, S13);
#   - RIPWIRE_SWEEP=0 and the control arm suppress it, and with it suppressed the first two calls are
#     BYTE-IDENTICAL to a run with it on — the feature is additive or it is not shipped (S11-S12);
#   - and the classifier fixtures pin the `cd`-prefix strip that recovered 82.7% of the live log's
#     `unclassified` rows, plus the new non-retrieval classes (C1-C2).
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

sweep_run()
{
    # sweep_run LOGFILE TMPDIRVAL JSON [VAR=VAL ...] -> stdout of the hook
    _l="$1"; _t="$2"; _j="$3"; shift 3
    printf '%s' "$_j" | env HOME="$METERHOME" RIPWIRE_METER_LOG="$_l" PATH="$WITH_RIPWIRE" \
        TMPDIR="$_t" "$@" bash "$HOOK"
}
grepjson() { printf '{"session_id":"%s","cwd":"%s","tool_name":"Grep","tool_input":{"pattern":"%s"}}' "$1" "$REPO" "$2"; }
readjson() { printf '{"session_id":"%s","cwd":"%s","tool_name":"Read","tool_input":{"file_path":"%s"}}' "$1" "$REPO" "$2"; }
globjson() { printf '{"session_id":"%s","cwd":"%s","tool_name":"Glob","tool_input":{"pattern":"%s"}}' "$1" "$REPO" "$2"; }

# ── S1-S6: the grep sweep. Three calls, one escalation, on the third, carrying the observed patterns
TS1="$TMP/ts1"; mkdir -p "$TS1"; LS1="$TMP/s1.jsonl"
SW1="$( sweep_run "$LS1" "$TS1" "$( grepjson sweepgrep alpha )" )"
SW2="$( sweep_run "$LS1" "$TS1" "$( grepjson sweepgrep beta )" )"
SW3="$( sweep_run "$LS1" "$TS1" "$( grepjson sweepgrep gamma )" )"; RCS3=$?
SW4="$( sweep_run "$LS1" "$TS1" "$( grepjson sweepgrep delta )" )"
echo "-- sweep escalation (grep, 3rd call) --"; echo "$SW3"

[ -n "$SW1" ] && printf '%s' "$SW1" | grep -Fq 'ripwire tip: ' && ok "S1 sweep: call 1 is the ordinary one-time tip" \
    || no "S1 sweep: call 1 was not the base nudge: [$SW1]"
[ -z "$SW2" ] && ok "S3 sweep: call 2 does NOT escalate (two same-class calls are not a sweep)" \
    || no "S3 sweep: call 2 fired something: [$SW2]"
[ "$RCS3" -eq 0 ] && [ -n "$SW3" ] && printf '%s' "$SW3" | grep -Fq 'SWEEP' \
    && ok "S2 sweep: call 3 escalates (exit 0, names itself a SWEEP)" \
    || no "S2 sweep: call 3 did not escalate: exit=$RCS3 out=[$SW3]"
printf '%s' "$SW3" | grep -Fq -- '--for=\"alpha beta gamma\"' \
    && ok "S2b sweep: the escalation is PASTE-READY — --for= carries the 3 observed patterns" \
    || no "S2b sweep: escalation lacks --for=\"alpha beta gamma\": [$SW3]"
# the hook tags rows with `git rev-parse --show-toplevel`, which resolves symlinks — on macOS
# $TMPDIR lives under /var -> /private/var, so compare against the resolved path the hook will use
REPO_TOP="$( git -C "$REPO" rev-parse --show-toplevel 2>/dev/null )"
printf '%s' "$SW3" | grep -Fq "ripwire $REPO_TOP --for" \
    && ok "S2c sweep: the pasted command names the repo directory, not a placeholder" \
    || no "S2c sweep: escalation does not name $REPO_TOP"
[ -z "$SW4" ] && ok "S4 sweep: call 4 is silent (one escalation per class per session)" \
    || no "S4 sweep: call 4 escalated a second time: [$SW4]"
printf '%s' "$SW3" | is_valid_json && ok "S6 sweep: escalation is valid JSON" \
    || no "S6 sweep: escalation is not valid JSON"
printf '%s' "$SW3" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"allow"' \
    && ok "S6b sweep: escalation is permissionDecision allow (advisory, never a blocker)" \
    || no "S6b sweep: escalation is not an allow"
printf '%s' "$SW3" | grep -qi 'deny\|"ask"\|updatedInput' \
    && no "S6c sweep: escalation mentions deny/ask/updatedInput (must never)" \
    || ok "S6c sweep: no deny/ask/updatedInput anywhere in the escalation"

# ── S5: the escalation is on the ROW. Without this the efficacy question cannot be asked at all ─────
[ "$( meterrowget "$LS1" 3 nudge )" = "sweep3" ] && [ "$( meterrowget "$LS1" 3 nudged )" = "1" ] \
    && ok "S5 sweep: the firing row is logged nudged=1 nudge=sweep3" \
    || no "S5 sweep: row 3 = nudged=[$( meterrowget "$LS1" 3 nudged )] nudge=[$( meterrowget "$LS1" 3 nudge )]"
[ "$( meterrowget "$LS1" 3 post_sweep )" = "0" ] && [ "$( meterrowget "$LS1" 4 post_sweep )" = "1" ] \
    && ok "S5b sweep: post_sweep marks the calls AFTER the escalation, not the one it fired on" \
    || no "S5b sweep: post_sweep was [$( meterrowget "$LS1" 3 post_sweep )] then [$( meterrowget "$LS1" 4 post_sweep )]"
[ "$( meterrows "$LS1" )" = "4" ] \
    && ok "S5c sweep: all four calls are still counted (escalating does not drop a row)" \
    || no "S5c sweep: expected 4 rows, got $( meterrows "$LS1" )"

# ── S7: the read sweep names the directory of the file just read, not a placeholder ─────────────────
TS7="$TMP/ts7"; mkdir -p "$TS7"; LS7="$TMP/s7.jsonl"
sweep_run "$LS7" "$TS7" "$( readjson sweepread /w/proj/src/a.cpp )" >/dev/null
sweep_run "$LS7" "$TS7" "$( readjson sweepread /w/proj/src/b.cpp )" >/dev/null
SW7="$( sweep_run "$LS7" "$TS7" "$( readjson sweepread /w/proj/src/c.cpp )" )"
echo "-- sweep escalation (read, 3rd call) --"; echo "$SW7"
printf '%s' "$SW7" | grep -Fq -- '--pack-task' && printf '%s' "$SW7" | grep -Fq -- '--expand' \
    && ok "S7 sweep: the read escalation names --pack-task and --expand" \
    || no "S7 sweep: read escalation missing --pack-task/--expand: [$SW7]"
printf '%s' "$SW7" | grep -Fq 'ripwire /w/proj/src --pack-task' \
    && ok "S7b sweep: it is scoped to the directory of the file just read" \
    || no "S7b sweep: read escalation does not name /w/proj/src"

# ── S8-S9: the glob and git-history sweeps name their one-call substitutes ──────────────────────────
TS8="$TMP/ts8"; mkdir -p "$TS8"; LS8="$TMP/s8.jsonl"
sweep_run "$LS8" "$TS8" "$( globjson sweepglob '**/*.c' )" >/dev/null
sweep_run "$LS8" "$TS8" "$( globjson sweepglob '**/*.h' )" >/dev/null
SW8="$( sweep_run "$LS8" "$TS8" "$( globjson sweepglob '**/*.py' )" )"
printf '%s' "$SW8" | grep -Fq 'SWEEP' && printf '%s' "$SW8" | grep -Fq -- '--for=' \
    && ok "S8 sweep: the glob sweep escalates and names --for" \
    || no "S8 sweep: glob escalation = [$SW8]"
TS9="$TMP/ts9"; mkdir -p "$TS9"; LS9="$TMP/s9.jsonl"
sweep_run "$LS9" "$TS9" "$( bashjson sweepgit 'git diff HEAD' )" >/dev/null
sweep_run "$LS9" "$TS9" "$( bashjson sweepgit 'git diff --stat' )" >/dev/null
SW9="$( sweep_run "$LS9" "$TS9" "$( bashjson sweepgit 'git diff -- src/' )" )"
printf '%s' "$SW9" | grep -Fq 'SWEEP' && printf '%s' "$SW9" | grep -Fq -- '--situ' \
    && ok "S9 sweep: the git-history sweep escalates and names --situ" \
    || no "S9 sweep: git-diff escalation = [$SW9]"

# ── S10: classes dedup INDEPENDENTLY — a spent grep escalation must not silence a read sweep ────────
TS10="$TMP/ts10"; mkdir -p "$TS10"; LS10="$TMP/s10.jsonl"
for p in a b c; do sweep_run "$LS10" "$TS10" "$( grepjson sweepboth "$p" )" >/dev/null; done
for f in /q/x/1.c /q/x/2.c; do sweep_run "$LS10" "$TS10" "$( readjson sweepboth "$f" )" >/dev/null; done
SW10="$( sweep_run "$LS10" "$TS10" "$( readjson sweepboth /q/x/3.c )" )"
printf '%s' "$SW10" | grep -Fq -- '--pack-task' \
    && ok "S10 sweep: a spent grep escalation does not consume the read escalation" \
    || no "S10 sweep: read sweep did not escalate after a grep sweep: [$SW10]"

# ── S11: NON-SWEEP BEHAVIOUR IS BYTE-UNCHANGED. The feature is additive or it is not shipped. ───────
# Same inputs, escalation off vs on: calls 1 and 2 of every category must match byte for byte.
S11BAD=""
for spec in "grep|$( grepjson X alpha )|$( grepjson X beta )" \
            "read|$( readjson X /w/p/a.c )|$( readjson X /w/p/b.c )" \
            "glob|$( globjson X '**/*.c' )|$( globjson X '**/*.h' )" \
            "gitdiff|$( bashjson X 'git diff HEAD' )|$( bashjson X 'git diff --stat' )"; do
    lbl="${spec%%|*}"; rest="${spec#*|}"; j1="${rest%%|*}"; j2="${rest#*|}"
    TA="$TMP/s11a_$lbl"; TB="$TMP/s11b_$lbl"; mkdir -p "$TA" "$TB"
    A1="$( sweep_run "$TMP/s11a.jsonl" "$TA" "$j1" )"; A2="$( sweep_run "$TMP/s11a.jsonl" "$TA" "$j2" )"
    B1="$( sweep_run "$TMP/s11b.jsonl" "$TB" "$j1" RIPWIRE_SWEEP=0 )"
    B2="$( sweep_run "$TMP/s11b.jsonl" "$TB" "$j2" RIPWIRE_SWEEP=0 )"
    [ "$A1" = "$B1" ] && [ "$A2" = "$B2" ] || S11BAD="$S11BAD $lbl"
done
[ -z "$S11BAD" ] \
    && ok "S11 sweep: calls 1-2 are byte-identical with the escalation on and off (purely additive)" \
    || no "S11 sweep: pre-sweep output differs with the feature on, for:$S11BAD"

# ── S12: the two off-switches. RIPWIRE_SWEEP=0 is what a null EVALS §4 readout ships. ───────────────
TS12="$TMP/ts12"; mkdir -p "$TS12"; LS12="$TMP/s12.jsonl"
for p in a b; do sweep_run "$LS12" "$TS12" "$( grepjson sweepoff "$p" )" RIPWIRE_SWEEP=0 >/dev/null; done
SW12="$( sweep_run "$LS12" "$TS12" "$( grepjson sweepoff c )" RIPWIRE_SWEEP=0 )"
[ -z "$SW12" ] && [ "$( meterrowget "$LS12" 3 nudge )" = "dedup" ] \
    && ok "S12 sweep: RIPWIRE_SWEEP=0 disables the escalation and leaves counting intact" \
    || no "S12 sweep: with RIPWIRE_SWEEP=0 the 3rd call gave out=[$SW12] nudge=[$( meterrowget "$LS12" 3 nudge )]"
TS12B="$TMP/ts12b"; mkdir -p "$TS12B"; LS12B="$TMP/s12b.jsonl"
for p in a b c; do sweep_run "$LS12B" "$TS12B" "$( grepjson sweepctl "$p" )" RIPWIRE_METER_ARM=control >/dev/null; done
[ "$( meterrowget "$LS12B" 3 nudge )" = "control" ] \
    && ok "S12b sweep: the control arm never escalates (the A/B stays clean)" \
    || no "S12b sweep: control-arm 3rd call logged nudge=[$( meterrowget "$LS12B" 3 nudge )]"
TS12C="$TMP/ts12c"; mkdir -p "$TS12C"; LS12C="$TMP/s12c.jsonl"
for p in a b c; do sweep_run "$LS12C" "$TS12C" "$( grepjson sweepn4 "$p" )" RIPWIRE_SWEEP_N=4 >/dev/null; done
SW12C="$( sweep_run "$LS12C" "$TS12C" "$( grepjson sweepn4 d )" RIPWIRE_SWEEP_N=4 )"
[ "$( meterrowget "$LS12C" 3 nudge )" = "dedup" ] && printf '%s' "$SW12C" | grep -Fq 'SWEEP' \
    && [ "$( meterrowget "$LS12C" 4 nudge )" = "sweep4" ] \
    && ok "S12c sweep: RIPWIRE_SWEEP_N=4 moves the threshold, and the row says sweep4" \
    || no "S12c sweep: N=4 gave row3=[$( meterrowget "$LS12C" 3 nudge )] row4=[$( meterrowget "$LS12C" 4 nudge )]"

# ── S13: the escalation degrades to SILENCE off its preconditions, and never onto stderr ────────────
TS13="$TMP/ts13"; mkdir -p "$TS13"; ERR13="$TMP/s13.err"
S13BAD=""
for p in a b c; do
    O="$( printf '%s' '{"session_id":"sweepnongit","cwd":"'"$NONREPO"'","tool_name":"Grep","tool_input":{"pattern":"'"$p"'"}}' \
        | env HOME="$METERHOME" RIPWIRE_METER_LOG="$TMP/s13.jsonl" PATH="$WITH_RIPWIRE" TMPDIR="$TS13" bash "$HOOK" 2>>"$ERR13" )"
    R=$?; [ "$R" -eq 0 ] && [ -z "$O" ] || S13BAD="$S13BAD [nongit:$R:$O]"
done
TS13B="$TMP/ts13b"; mkdir -p "$TS13B"
for p in a b c; do
    O="$( printf '%s' "$( grepjson sweepnorip "$p" )" \
        | env HOME="$METERHOME" RIPWIRE_METER_LOG="$TMP/s13b.jsonl" PATH="$NO_RIPWIRE" TMPDIR="$TS13B" bash "$HOOK" 2>>"$ERR13" )"
    R=$?; [ "$R" -eq 0 ] && [ -z "$O" ] || S13BAD="$S13BAD [norip:$R:$O]"
done
[ -z "$S13BAD" ] && ok "S13 sweep: a 3-call sweep in a non-git dir / with no ripwire stays silent, exit 0" \
    || no "S13 sweep: fired or failed off its preconditions:$S13BAD"
[ ! -s "$ERR13" ] && ok "S13b sweep: the escalation path writes nothing to the hooked call's stderr" \
    || no "S13b sweep: stderr leaked: $( cat "$ERR13" )"

# ── S14: a Bash grep sweep escalates too, and the patterns come off the command line ────────────────
# Grep-the-tool and `grep -rn` on the command line are the SAME habit and must count toward one sweep.
TS14="$TMP/ts14"; mkdir -p "$TS14"; LS14="$TMP/s14.jsonl"
sweep_run "$LS14" "$TS14" "$( bashjson sweepbash 'grep -rn needleone .' )" >/dev/null
sweep_run "$LS14" "$TS14" "$( bashjson sweepbash 'rg needletwo src/' )" >/dev/null
SW14="$( sweep_run "$LS14" "$TS14" "$( grepjson sweepbash needlethree )" )"
echo "-- sweep escalation (mixed Bash-grep + Grep tool) --"; echo "$SW14"
printf '%s' "$SW14" | grep -Fq -- '--for=\"needleone needletwo needlethree\"' \
    && ok "S14 sweep: Bash grep/rg and the Grep tool count as ONE sweep, patterns from both" \
    || no "S14 sweep: mixed grep sweep gave [$SW14]"

# ── C1: the `cd`-prefix strip. 816 of the live log's 927 unclassified rows began with `cd <path> &&`
#        — the worktree idiom — and stripping it is what took `unclassified` from 42.9% to 7.4%. ─────
TC1="$TMP/tc1"; mkdir -p "$TC1"; LC1="$TMP/c1.jsonl"
C1BAD=""
i=0
for pair in "cd /w && grep -rn needle .|grep" \
            "cd /w && VAR=y grep -rn needle .|grep" \
            "cd /w && rtk grep -rn needle .|grep" \
            "VAR=1 cd /w && env FOO=2 rg needle src|grep" \
            "cd /w && cd sub && cat x.txt|read" \
            "cd /w && sed -n '1,80p' src/a.cpp|read" \
            "cd /w && ./build/ripwire . --for=x|ripwire-cli" \
            "cd /w && git -C /o diff HEAD|git-diff"; do
    c="${pair%|*}"; want="${pair#*|}"; i=$(( i + 1 ))
    sweep_run "$LC1" "$TC1" "$( bashjson "cdcase_$i" "$( printf '%s' "$c" | sed 's/"/\\"/g' )" )" >/dev/null 2>&1
    got="$( meterrowget "$LC1" "$i" class )"
    [ "$got" = "$want" ] || C1BAD="$C1BAD [$c -> $got, want $want]"
done
[ -z "$C1BAD" ] && ok "C1 classifier: cd/pushd + assignments + rtk strip recursively, in any order" \
    || no "C1 classifier: misclassified:$C1BAD"

# ── C1b: a MULTI-LINE command. jq's @tsv escapes the newline, so without the un-escape the whole
#         line is one token (`/a/b\ngit`) and the row lands as unclassified — 742 rows' worth. ───────
TC1B="$TMP/tc1b"; mkdir -p "$TC1B"; LC1B="$TMP/c1b.jsonl"
printf '%s' '{"session_id":"multiline","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"cd /w\ngit diff HEAD\ngit status"}}' \
    | env HOME="$METERHOME" RIPWIRE_METER_LOG="$LC1B" PATH="$WITH_RIPWIRE" TMPDIR="$TC1B" bash "$HOOK" >/dev/null 2>&1
[ "$( meterrowget "$LC1B" 1 class )" = "git-diff" ] \
    && ok "C1b classifier: a MULTI-LINE 'cd <dir>\\ngit diff' classifies as git-diff, not unclassified" \
    || no "C1b classifier: multi-line command classified as [$( meterrowget "$LC1B" 1 class )]"
[ "$( meterrows "$LC1B" )" = "1" ] \
    && ok "C1c classifier: a multi-line command is still exactly one JSONL row" \
    || no "C1c classifier: multi-line command wrote $( meterrows "$LC1B" ) row(s)"

# ── C2: the non-retrieval classes. Never in the rate (family other/meta/git) — they exist so the S4
#        absorption survey can rank the command mix an agent actually runs. ─────────────────────────
TC2="$TMP/tc2"; mkdir -p "$TC2"; LC2="$TMP/c2.jsonl"
C2BAD=""
i=0
for triple in "cmake --build build -j 8|build|other" \
              "make -j4|build|other" \
              "cargo build --release|build|other" \
              "npm test|gate-run|meta" \
              "python3 test/pargates.py . ./build/ripwire -j 6|gate-run|meta" \
              "bash test/hookcheck.sh|gate-run|meta" \
              "cd /w && ./test/lintcheck.sh|gate-run|meta" \
              "git push origin main|git-remote|git" \
              "git fetch origin|git-remote|git" \
              "gh pr view 31|git-remote|git" \
              "git status --porcelain|git-misc|git" \
              "git add src/ && git commit -q -m x|git-misc|git" \
              "mkdir -p /tmp/x|shell-misc|other" \
              "wc -l a.txt|shell-misc|other" \
              "ls -la docs/|shell-misc|other"; do
    c="${triple%%|*}"; rest="${triple#*|}"; wc_="${rest%|*}"; wf="${rest#*|}"; i=$(( i + 1 ))
    sweep_run "$LC2" "$TC2" "$( bashjson "clscase_$i" "$( printf '%s' "$c" | sed 's/"/\\"/g' )" )" >/dev/null 2>&1
    gc="$( meterrowget "$LC2" "$i" class )"; gf="$( meterrowget "$LC2" "$i" family )"
    [ "$gc" = "$wc_" ] && [ "$gf" = "$wf" ] || C2BAD="$C2BAD [$c -> $gc/$gf, want $wc_/$wf]"
done
[ -z "$C2BAD" ] && ok "C2 classifier: build / gate-run / git-remote / git-misc / shell-misc, with their families" \
    || no "C2 classifier: misclassified:$C2BAD"

# ── C2b: the new classes are counted but NEVER nudged and NEVER swept. A build is not a retrieval. ──
TC2B="$TMP/tc2b"; mkdir -p "$TC2B"; LC2B="$TMP/c2b.jsonl"
C2BBAD=""
for i in 1 2 3 4; do
    O="$( sweep_run "$LC2B" "$TC2B" "$( bashjson buildsweep 'cmake --build build -j 8' )" )"
    [ -z "$O" ] || C2BBAD="$C2BBAD [call$i fired: $O]"
done
[ -z "$C2BBAD" ] && [ "$( meterrows "$LC2B" )" = "4" ] \
    && ok "C2b classifier: four builds in a session are counted and never nudged or escalated" \
    || no "C2b classifier: build calls nudged$C2BBAD (rows=$( meterrows "$LC2B" ))"

# ── C2c: `ls test | grep -i doc` stays unclassified — shell-misc must not destroy grep evidence ─────
TC2C="$TMP/tc2c"; mkdir -p "$TC2C"; LC2C="$TMP/c2c.jsonl"
sweep_run "$LC2C" "$TC2C" "$( bashjson lspipe 'ls test | grep -i doccommand' )" >/dev/null 2>&1
[ "$( meterrowget "$LC2C" 1 class )" = "unclassified" ] \
    && ok "C2c classifier: shell-misc defers to the vocabulary scan (a piped grep keeps its evidence)" \
    || no "C2c classifier: 'ls test | grep …' classified as [$( meterrowget "$LC2C" 1 class )]"

# ── C3: the docs carry the new contract — the schema doc is part of the deliverable ────────────────
if [ -f "$SCHEMADOC" ]; then
    C3MISS=""
    for needle in 'post_sweep' 'RIPWIRE_SWEEP' 'sweep3' 'shell-misc' 'gate-run' 'git-remote' 'cd'; do
        grep -Fq "$needle" "$SCHEMADOC" || C3MISS="$C3MISS $needle"
    done
    [ -z "$C3MISS" ] && ok "C3 docs: SUBSTITUTION_METER.md documents the escalation and the new classes" \
        || no "C3 docs: SUBSTITUTION_METER.md is missing:$C3MISS"
fi
EVALSDOC="$ROOT/docs/EVALS.md"
if [ -f "$EVALSDOC" ]; then
    grep -Fq 'Nudge sweep-escalation efficacy' "$EVALSDOC" && grep -Fq 'post_sweep' "$EVALSDOC" \
        && ok "C3b docs: EVALS.md carries the pre-registered efficacy readout for the escalation" \
        || no "C3b docs: EVALS.md has no sweep-escalation registration — the verdict is unregistered"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
