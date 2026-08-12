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
# real ~/.claude, and — since 2026-08-12, enforced by section (13) rather than asserted here — never
# the real ~/.ripwire/substitution.jsonl either. See FIXTURE ISOLATION below before adding an arm.

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

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# FIXTURE ISOLATION (2026-08-12) — READ THIS BEFORE ADDING AN ARM.
#
# The hook's second job is the substitution meter: it appends one JSONL row per observed tool call to
# ~/.ripwire/substitution.jsonl. This gate feeds it invented payloads by the dozen, and every one of
# those rows is indistinguishable at analysis time from a row a real agent produced. Until 2026-08-12
# the arms below ran with the ambient environment, so the meter resolved the REAL $HOME and one run
# of this gate appended 30 synthetic rows across 24 fixture "sessions" to the operator's live log —
# while printing ALL PASS. The instrument was measuring its own test fixtures.
#
# The contract is now: A GATE RUN CAN NEVER TOUCH THE DEFAULT LOG. Two independent layers, because a
# single layer is a thing a future arm can forget:
#
#   L1  this block exports a sandbox destination ONCE. Every invocation below inherits it through
#       `env`, including one written later by someone who never read this comment. An arm that wants
#       its own file still passes RIPWIRE_METER_LOG explicitly; that simply overrides the sandbox
#       with another sandbox.
#   L2  RIPWIRE_METER_FIXTURE tells the hook a harness is driving it. If an arm actively strips L1
#       (`env -u`), the hook refuses to fall back to $HOME and writes nothing — see §FIXTURE in
#       hooks/ripwire-nudge.sh.
#
# Section (13) asserts that both layers held. Exactly two arms there run without L2, deliberately, to
# keep the production HOME-fallback path gated; both sandbox $HOME, and arm I2 is what catches it if
# either one ever stops.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# Captured BEFORE the exports below, so it names the operator's real log and not the sandbox.
REAL_METER_LOG="${RIPWIRE_METER_LOG:-${RIPWIRE_HOME:-$HOME/.ripwire}/substitution.jsonl}"
REAL_METER_BYTES=0
[ -f "$REAL_METER_LOG" ] && REAL_METER_BYTES="$( wc -c <"$REAL_METER_LOG" 2>/dev/null | tr -d ' ' )"
GATEHOME="$TMP/gatehome"; mkdir -p "$GATEHOME"
export RIPWIRE_HOME="$GATEHOME"                          # meter.conf comes from here too, i.e. nowhere
export RIPWIRE_METER_LOG="$GATEHOME/substitution.jsonl"  # the sandbox every unnamed arm lands in
export RIPWIRE_METER_FIXTURE=1                           # L2: refuse a $HOME fallback if L1 is stripped
GATE_SINK="$RIPWIRE_METER_LOG"

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
# M1/M18 are about the meter RESOLVING its own default filename, so they are the two arms that must
# not simply be handed one. Passing $DEFAULTS drops L1's explicit path (an empty value reads as unset
# to the hook) and names the meter home instead, so what those arms exercise is the resolution — but
# inside a sandbox, never against $HOME. The bare-$HOME rung below it is gated separately, by arm I4.
DEFAULTS="RIPWIRE_METER_LOG= RIPWIRE_HOME=$METERHOME/.ripwire"

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
run_meter "" "$M1_JSON" "$TM1" $DEFAULTS >/dev/null 2>&1; RCM1=$?
echo "-- meter default-path row --"; [ -f "$DEFAULT_LOG" ] && cat "$DEFAULT_LOG"
[ "$RCM1" -eq 0 ] && ok "M1 meter: hooked call still exits 0" || no "M1 meter: exit was $RCM1"
[ "$( meterrows "$DEFAULT_LOG" )" = "1" ] \
    && ok "M1 meter: one row lazily created at <meter home>/substitution.jsonl (the default filename)" \
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
# The fixture changed at S2c (2026-08-12) and the reason is the arm's whole point. It used to be
# `for f in *.c; do grep needle $f; done`, which the segment walk now READS — the loop body is a
# grep and calling it ambiguous was the classifier's limitation, not the line's. What must still land
# as `unclassified` is a line whose retrieval is somewhere the walk deliberately does not go: inside
# a command substitution. Keeping the retired fixture would have gated a bug as if it were a
# contract.
run_meter "$L16" "$( bashjson meter16 'echo \"count: $(grep -c needle f.txt)\"' )" "$TM16" >/dev/null 2>&1
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
run_meter "" '{"session_id":"meter18","cwd":"'"$REPO2"'","tool_name":"Grep","tool_input":{"pattern":"n"}}' "$TM18" $DEFAULTS >/dev/null 2>&1
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
fi

# ── T1-T11: §5 terminality by verb, pinned on a SYNTHETIC fixture log  (Track T item T0) ────────────
#
# WHY A FIXTURE AND NOT THE GATE'S OWN SINK. Every other meter arm here asserts a property of the
# HOOK, so the hook's own output is the right input. §5 is an ANALYSIS, and an analysis is gated by
# feeding it data whose right answer is known by construction — the sink's contents change with every
# arm anyone adds above, so an assertion against it could only ever be "it did not crash".
#
# The fixture below encodes, by hand, one instance of each thing the metric has to get right:
#
#   - a TERMINAL --for (t-a: the follow-ups are build/git-misc/shell-misc, none of them a sweep);
#   - a NON-TERMINAL --for followed by THREE greps (t-b), so the follow-up recorded is the FIRST one;
#   - a window truncated by the NEXT RIPWIRE CALL (t-a seq4) and by SESSION END (t-a seq6, t-d seq7,
#     t-e seq1) — the empty-window disclosure counts exactly those;
#   - the k=5 EDGE, twice and from both sides (t-f, t-g): five non-sweep calls then a grep is TERMINAL
#     because the grep is out of the window; four then a grep is not. An off-by-one in either
#     direction reds exactly one of that pair, which is the point of gating the edge rather than the
#     middle;
#   - a git-history follow-up (t-b seq8), which counts as a sweep here though it is outside §1's ratio;
#   - an n<10 verb (--grep, n=3) carrying its NOTE row, and an n>=10 verb (--for, n=12) carrying none;
#   - an MCP row, whose verb comes from the tool name rather than from a command line;
#   - the flagless map behind a `cd` prefix and ahead of a pipeline (t-e) — `| grep -n --color foo`
#     must NOT be read as the verb `--color`.
#
# The assertions are on the space-SQUEEZED table rows, so they pin every value the table states while
# leaving column widths free to be laid out for a reader.
TERMLOG="$TMP/terminality.jsonl"
termrow()
{
    # termrow SEQ SESSION TOOL CLASS FAMILY DETAIL
    printf '{"v":2,"ts":"2026-08-12T00:00:00Z","seq":%s,"session":"%s","repo":"/x/repo","tag":"repo","tool":"%s","class":"%s","family":"%s","nudged":0,"nudge":"none","post_nudge":0,"post_sweep":0,"arm":"treatment","detail":"%s"}\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" >>"$TERMLOG"
}
termrip() { termrow "$1" "$2" Bash ripwire-cli ripwire "$3"; }
termbuild() { termrow "$1" "$2" Bash build other 'cmake --build build -j'; }
termgrep() { termrow "$1" "$2" Grep grep native 'needle'; }
termread() { termrow "$1" "$2" Read read native '/x/repo/a.cpp'; }

: >"$TERMLOG"
# t-a — three TERMINAL --for: non-sweep follow-ups, then a window ended by the next ripwire call, then
#       a window ended by the session.
termrip  1 t-a './build/ripwire . --for=alpha'
termbuild 2 t-a
termrow  3 t-a Bash git-misc git 'git status'
termrip  4 t-a './build/ripwire . --for=beta'
termrow  5 t-a Bash shell-misc other 'ls -la docs/'
termrip  6 t-a './build/ripwire . --for=gamma'
# t-b — the sweep case: --for then THREE greps (first one is the recorded follow-up), --for then one
#       grep, --for then a git-history call.
termrip  1 t-b 'cd /x/repo && ./build/ripwire . --for=delta'
termgrep 2 t-b; termgrep 3 t-b; termgrep 4 t-b
termrip  5 t-b './build/ripwire . --for=epsilon --top-k=3'
termgrep 6 t-b
termrip  7 t-b './build/ripwire . --for=zeta'
termrow  8 t-b Bash git-log git 'git log --oneline -20'
# t-c — the --grep verb (n<10, two read follow-ups) and the MCP verb.
termrip  1 t-c './build/ripwire . --grep=needle'
termread 2 t-c
termrip  3 t-c './build/ripwire . --grep=needle'
termread 4 t-c
termrip  5 t-c './build/ripwire . --grep=needle'
termbuild 6 t-c
termrow  7 t-c mcp__ripwire__for ripwire-mcp ripwire 'rank the parser'
termbuild 8 t-c
termrow  9 t-c mcp__ripwire__for ripwire-mcp ripwire 'rank the ranker'
# t-d — four more TERMINAL --for, which is what lifts --for over the small-n floor.
termrip  1 t-d './build/ripwire . --for=iota'
termbuild 2 t-d
termrip  3 t-d './build/ripwire . --for=kappa'
termrow  4 t-d Bash shell-misc other 'ls -la'
termrip  5 t-d './build/ripwire . --for=lambda'
termrow  6 t-d Bash git-misc git 'git status'
termrip  7 t-d './build/ripwire . --for=mu'
# t-e — the flagless map, behind a cd prefix, ahead of a pipeline carrying flags of its own.
termrip  1 t-e 'cd /x/repo && ./build/ripwire . > /tmp/a 2>&1 | grep -n --color foo'
# t-f/t-g — the k=5 window edge, from both sides. FIVE non-sweep calls put the grep out of the window
#           (terminal); FOUR leave it inside (not terminal).
termrip  1 t-f './build/ripwire . --for=nu'
termbuild 2 t-f; termbuild 3 t-f; termbuild 4 t-f; termbuild 5 t-f; termbuild 6 t-f
termgrep 7 t-f
termrip  1 t-g './build/ripwire . --for=xi'
termbuild 2 t-g; termbuild 3 t-g; termbuild 4 t-g; termbuild 5 t-g
termgrep 6 t-g

if [ -f "$REPORT" ]; then
    python3 "$REPORT" "$TERMLOG" >"$TMP/term.out" 2>&1; RCT=$?
    tr -s ' ' <"$TMP/term.out" >"$TMP/term.sq"
    echo "-- substitution_report.py §5 on the terminality fixture --"
    sed -n '/^5\./,$p' "$TMP/term.out"
    termhas()
    {
        # termhas ARMID EXPECTED-SQUEEZED-LINE DESCRIPTION
        grep -Fqx " $2" "$TMP/term.sq" \
            && ok "$1 terminality: $3" \
            || no "$1 terminality: expected the row [$2] — see $TMP/term.out"
    }
    [ "$RCT" -eq 0 ] && grep -qi 'terminality by verb' "$TMP/term.out" \
        && ok "T1 terminality: the report prints a §5 terminality-by-verb section" \
        || no "T1 terminality: exit=$RCT and/or no §5 section — see $TMP/term.out"
    # The definitions travel WITH the number: a terminality % read without its window rule is a
    # number somebody quotes wrong, so the header is gated, not left to the docs.
    grep -q 'up to the next ripwire call, the session end' "$TMP/term.out" \
        && grep -q 'or 5 calls' "$TMP/term.out" \
        && grep -q 'sweep = find git-diff git-log git-show-stat glob grep read' "$TMP/term.out" \
        && ok "T2 terminality: §5 states its window and its sweep set above the table" \
        || no "T2 terminality: §5 does not state the window/sweep definitions — see $TMP/term.out"
    termhas T3  "--for 12 66.7% grep (3)"     "--for: 12 calls, 8 terminal, first follow-up grep x3"
    termhas T4  "--grep 3 33.3% read (2)"     "--grep: 3 calls, 1 terminal, read x2"
    termhas T5  "mcp:for 2 100.0% (none)"     "an MCP row takes its verb from the tool name"
    termhas T6  "(map) 1 100.0% (none)"       "a flagless run behind cd, ahead of a pipeline, is the map"
    termhas T7  "(all) 18 66.7% grep (3)"     "the (all) row totals every verb"
    termhas T8  "empty windows: 4 of 18 -- the next observed call was another ripwire call, or the" \
                "the empty-window count is disclosed, not folded in silently"
    # n<10 gets a NOTE; n>=10 does not. Three verbs are under the floor (--grep, mcp:for, (map)); --for
    # and (all) are over it. A NOTE on every row would be as useless as a NOTE on none.
    NOTES="$( grep -c 'NOTE: n=. (<10)' "$TMP/term.sq" )"; [ -n "$NOTES" ] || NOTES=0
    [ "$NOTES" -eq 3 ] \
        && ok "T9 terminality: exactly the three n<10 verbs carry a small-n NOTE row" \
        || no "T9 terminality: $NOTES NOTE row(s), expected 3 — see $TMP/term.out"
    # The k=5 edge, asserted as the PAIR. One arm alone passes under an off-by-one in one direction.
    : >"$TMP/term_f.jsonl"; grep -F '"t-f"' "$TERMLOG" >"$TMP/term_f.jsonl"
    : >"$TMP/term_g.jsonl"; grep -F '"t-g"' "$TERMLOG" >"$TMP/term_g.jsonl"
    python3 "$REPORT" "$TMP/term_f.jsonl" 2>&1 | tr -s ' ' | grep -Fqx " --for 1 100.0% (none)" \
        && python3 "$REPORT" "$TMP/term_g.jsonl" 2>&1 | tr -s ' ' | grep -Fqx " --for 1 0.0% grep (1)" \
        && ok "T10 terminality: the k=5 window edge holds from both sides (5 calls out, 4 calls in)" \
        || no "T10 terminality: the window edge is off by one — see $TMP/term_f.jsonl / $TMP/term_g.jsonl"
    python3 "$REPORT" "$TERMLOG" >"$TMP/term2.out" 2>&1
    cmp -s "$TMP/term.out" "$TMP/term2.out" \
        && ok "T11 terminality: two runs over the same log are byte-identical (ties broken by name)" \
        || no "T11 terminality: the report is not deterministic — diff $TMP/term.out $TMP/term2.out"
    # T12: the 200-character `detail` cap, which a REAL log hit on its first reading. A line cut
    # mid-flag must not be filed under the prefix that survived — `--qualit` counted apart from
    # `--quality-delta` splits one verb's n across two rows and understates both. Cut before any flag
    # is a different unknown again: the verb may be one character past the cap.
    TRUNCLOG="$TMP/term_trunc.jsonl"; : >"$TRUNCLOG"
    TERMLOG_MAIN="$TERMLOG"; TERMLOG="$TRUNCLOG"
    THEAD='cd /x/'
    TCUT=0
    for TTAIL in ' && ./build/ripwire . --qualit' ' && ./build/ripwire /x/repo/src'; do
        TCUT=$(( TCUT + 1 ))
        # exactly 200 characters: the cap, reached mid-flag on the first line and mid-path on the second
        TPAD="$( printf '%*s' "$(( 200 - ${#THEAD} - ${#TTAIL} ))" '' | tr ' ' 'a' )"
        termrip 1 "t-cut$TCUT" "${THEAD}${TPAD}${TTAIL}"
    done
    TERMLOG="$TERMLOG_MAIN"
    python3 "$REPORT" "$TRUNCLOG" 2>&1 | tr -s ' ' >"$TMP/trunc.sq"
    grep -Fqx " --qualit... 1 100.0% (none)" "$TMP/trunc.sq" \
        && grep -Fqx " (truncated) 1 100.0% (none)" "$TMP/trunc.sq" \
        && ok "T12 terminality: a detail cut at the 200-char cap is labelled truncated, never filed under the surviving prefix" \
        || no "T12 terminality: the truncation labels are wrong — see $TRUNCLOG and $TMP/trunc.sq"
else
    no "M26 meter: bench/substitution_report.py does not exist"
    no "M27b meter: bench/substitution_report.py does not exist"
    no "T1 terminality: bench/substitution_report.py does not exist"
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

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# (12b) THE CLASSIFIER-GAP ROUND  (Track B §S2c, 2026-08-12)
#
# WHY THIS SECTION EXISTS. docs/EVALS.md §4 registers the sweep-escalation readout with a secondary
# condition it can fail on: the `unclassified` share must stay under 15%, or the readout was taken
# with a drifting instrument. On the post-isolation-deploy window it was running at roughly a third
# of all rows — the readout was compromised before it could be read. Mining those rows' `detail`
# fields found three structural gaps and one missing class, each pinned below by the shape that
# produced it:
#
#   C4  THE FIRST WORD IS NOT THE COMMAND. `echo "=== x ==="; grep -n E1 f`, `mkdir -p $D; ls -R $D`,
#       `git reset --soft X && ./build/ripwire . --quality-delta` — the classifier read word one and
#       gave up. The last of those is the same undercount-the-numerator failure the v1->v2 `cd` fix
#       was about, one separator further along.
#   C5  A NEWLINE IS A SEPARATOR, NOT A SPACE. The un-escape substituted a space, gluing a multi-line
#       command into one unsplittable segment.
#   C6  THE HEAD DOES NOT ALWAYS JUDGE SEGMENT ONE. The prefix strip eats whole leading segments, so
#       a walk that skips a fixed count re-judges the segment the head already saw and stops there.
#   C7  PIPELINE STAGES ARE NOT COMMANDS THE AGENT CHOSE. `… | head -40` pages another command's
#       output; counting it as a native read inflates the rate's denominator with pagers.
#   C8  A PATH COMPONENT IS NOT A COMMAND WORD. The vocabulary scan fired on `ripwire` inside
#       `/opt/homebrew/share/ripwire/hooks/…`.
#   C9  AN OPAQUE SCRIPT IS NOT A MISSING RULE. `unclassified` means "this table needs a rule" and is
#       read as a bug report; `python3 -c …` needs no rule, it needs a name — `script-run`.
#   C10 `cat > f` IS A WRITE. And a heredoc's body is not a command sequence.
#
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

# `@@` separates fixture from expectation below, because these fixtures contain `|` on purpose.
clscase()
{
    # clscase LOG TMPDIR INDEX COMMAND -> classifies one line into LOG, prints nothing
    sweep_run "$1" "$2" "$( bashjson "w_$3" "$( printf '%s' "$4" | sed 's/\\/\\\\/g; s/"/\\"/g' )" )" >/dev/null 2>&1
}

# ── C4: the SEGMENT WALK. The command is in a later sequenced segment than the first. ───────────────
TC4="$TMP/tw1"; mkdir -p "$TC4"; LC4="$TMP/w1.jsonl"
C4BAD=""
i=0
for pair in 'echo "=== docs ==="; grep -n E1 PLAN.md@@grep' \
            'mkdir -p /tmp/d; ls -R /tmp/d@@find' \
            'D=/tmp/d; cd /tmp/d && cat notes.txt@@read' \
            'git status --porcelain && git diff --stat@@git-diff' \
            'git fetch origin; git log --oneline -3@@git-log' \
            'git reset -q --soft HEAD~1 && ./build/ripwire . --quality-delta@@ripwire-cli' \
            'bash test/hookcheck.sh > /tmp/hc.out; grep -E "^  FAIL" /tmp/hc.out@@grep' \
            'mkdir -p /tmp/d ; cd /tmp/d ; grep -rn needle .@@grep' \
            'for g in acheck bcheck; do bash test/$g.sh; done@@gate-run' \
            'cmake --build build -j 8 && ls -la build@@build'; do
    c="${pair%%@@*}"; want="${pair#*@@}"; i=$(( i + 1 ))
    clscase "$LC4" "$TC4" "$i" "$c"
    got="$( meterrowget "$LC4" "$i" class )"
    [ "$got" = "$want" ] || C4BAD="$C4BAD [$c -> $got, want $want]"
done
[ -z "$C4BAD" ] \
    && ok "C4 classifier: the segment walk reads the command out of a later ;/&&/|| segment" \
    || no "C4 classifier: misclassified:$C4BAD"

# ── C5: a NEWLINE is a command separator. The multi-line worktree idiom, end to end. ────────────────
TC5="$TMP/tw2"; mkdir -p "$TC5"; LC5="$TMP/w2.jsonl"
printf '%s' '{"session_id":"w2case","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"cd /w\nfor g in acheck bcheck\ndo\n  bash test/$g.sh\ndone"}}' \
    | env HOME="$METERHOME" RIPWIRE_METER_LOG="$LC5" PATH="$WITH_RIPWIRE" TMPDIR="$TC5" bash "$HOOK" >/dev/null 2>&1
[ "$( meterrowget "$LC5" 1 class )" = "gate-run" ] \
    && ok "C5 classifier: a multi-line loop classifies by its BODY (a newline reads as a separator)" \
    || no "C5 classifier: multi-line loop classified as [$( meterrowget "$LC5" 1 class )], want gate-run"

# ── C6: the walk must skip the segment the HEAD judged — not a fixed count of segments ──────────────
# `cd /w &&` is eaten by the prefix strip, so the head's verdict is about segment TWO. A walk that
# blindly skipped segment one would re-judge `bash -n …`, return script-run, and never see the
# ripwire call — silently undercounting the numerator, this instrument's worst failure mode.
TC6="$TMP/tw3"; mkdir -p "$TC6"; LC6="$TMP/w3.jsonl"
clscase "$LC6" "$TC6" 1 'cd /w && bash -n hooks/x.sh && ./build/ripwire . --for=y'
[ "$( meterrowget "$LC6" 1 class )" = "ripwire-cli" ] \
    && ok "C6 classifier: the walk resumes AFTER the head's segment, so a later ripwire call is seen" \
    || no "C6 classifier: got [$( meterrowget "$LC6" 1 class )], want ripwire-cli"

# ── C7: PIPELINE stages are not walked, and pagers are not retrieval ────────────────────────────────
# The pair is the point: `| grep` keeps its evidence (unclassified, per C2c) while `| head` does not
# manufacture a native read. Both errors bias the substitution rate, in opposite directions.
TC7="$TMP/tw4"; mkdir -p "$TC7"; LC7="$TMP/w4.jsonl"
C7BAD=""
i=0
for pair in 'ls docs/ | head -40@@shell-misc' \
            'ls test | grep -i doccommand@@unclassified' \
            'ls -la /tmp/d 2>&1 | head; wc -l /tmp/x@@shell-misc' \
            'cat src/foo.cpp | head -40@@read'; do
    c="${pair%%@@*}"; want="${pair#*@@}"; i=$(( i + 1 ))
    clscase "$LC7" "$TC7" "$i" "$c"
    got="$( meterrowget "$LC7" "$i" class )"
    [ "$got" = "$want" ] || C7BAD="$C7BAD [$c -> $got, want $want]"
done
[ -z "$C7BAD" ] \
    && ok "C7 classifier: a piped pager is not a read, and a piped grep still keeps its evidence" \
    || no "C7 classifier: misclassified:$C7BAD"

# ── C8: a `/` after the word means a PATH COMPONENT, not an invocation ──────────────────────────────
TC8="$TMP/tw5"; mkdir -p "$TC8"; LC8="$TMP/w5.jsonl"
C8BAD=""
i=0
for pair in 'stat -f %m /opt/homebrew/share/ripwire/hooks/x.sh@@shell-misc' \
            'diff -q /opt/homebrew/share/ripwire/hooks/x.sh hooks/x.sh@@shell-misc' \
            'xargs grep needle < filelist@@unclassified'; do
    c="${pair%%@@*}"; want="${pair#*@@}"; i=$(( i + 1 ))
    clscase "$LC8" "$TC8" "$i" "$c"
    got="$( meterrowget "$LC8" "$i" class )"
    [ "$got" = "$want" ] || C8BAD="$C8BAD [$c -> $got, want $want]"
done
[ -z "$C8BAD" ] \
    && ok "C8 classifier: a directory named ripwire is not a ripwire call; xargs grep still is a grep" \
    || no "C8 classifier: misclassified:$C8BAD"

# ── C9: `script-run` — an opaque program gets a NAME, and its text is not walked ────────────────────
TC9="$TMP/tw6"; mkdir -p "$TC9"; LC9="$TMP/w6.jsonl"
C9BAD=""
i=0
for pair in 'python3 -c "import json; print(1)"@@script-run' \
            'python3 bench/substitution_scrub.py /tmp/log.jsonl@@script-run' \
            'bash -n hooks/x.sh@@script-run' \
            'node -e "console.log(1)"@@script-run' \
            'python3 test/pargates.py . ./build/ripwire -j 6@@gate-run'; do
    c="${pair%%@@*}"; want="${pair#*@@}"; i=$(( i + 1 ))
    clscase "$LC9" "$TC9" "$i" "$c"
    got="$( meterrowget "$LC9" "$i" class )"
    [ "$got" = "$want" ] || C9BAD="$C9BAD [$c -> $got, want $want]"
done
[ -z "$C9BAD" ] && [ "$( meterrowget "$LC9" 1 family )" = "other" ] \
    && ok "C9 classifier: script-run names the opaque program, family other (never in the rate)" \
    || no "C9 classifier: misclassified:$C9BAD family=[$( meterrowget "$LC9" 1 family )]"
# an INLINE program's own text is not a command sequence: a `;` inside it must not be walked
TC9B="$TMP/tw6b"; mkdir -p "$TC9B"; LC9B="$TMP/w6b.jsonl"
clscase "$LC9B" "$TC9B" 1 'python3 -c "import os; cat = 1; print(cat)"'
[ "$( meterrowget "$LC9B" 1 class )" = "script-run" ] \
    && ok "C9b classifier: the walk does not descend into an inline program and read its text as shell" \
    || no "C9b classifier: inline program classified as [$( meterrowget "$LC9B" 1 class )], want script-run"
# and like build, a script-run is counted but never nudged or escalated
TC9C="$TMP/tw6c"; mkdir -p "$TC9C"; LC9C="$TMP/w6c.jsonl"
C9CBAD=""
for i in 1 2 3 4; do
    O="$( sweep_run "$LC9C" "$TC9C" "$( bashjson scriptsweep 'python3 -c \"print(1)\"' )" )"
    [ -z "$O" ] || C9CBAD="$C9CBAD [call$i fired]"
done
[ -z "$C9CBAD" ] && [ "$( meterrows "$LC9C" )" = "4" ] \
    && ok "C9c classifier: four script runs are counted and never nudged or escalated" \
    || no "C9c classifier: script-run nudged$C9CBAD (rows=$( meterrows "$LC9C" ))"

# ── C10: `cat >` is a WRITE, and a heredoc body is not a command sequence ────────────────────────────
TC10="$TMP/tw7"; mkdir -p "$TC10"; LC10="$TMP/w7.jsonl"
C10BAD=""
i=0
for pair in 'cat > /tmp/msg.txt@@shell-misc' \
            'cat /tmp/msg.txt@@read' \
            'git add -A && cat > /tmp/msg.txt <<EOF ; fix(x): grep the thing ; EOF@@git-misc'; do
    c="${pair%%@@*}"; want="${pair#*@@}"; i=$(( i + 1 ))
    clscase "$LC10" "$TC10" "$i" "$c"
    got="$( meterrowget "$LC10" "$i" class )"
    [ "$got" = "$want" ] || C10BAD="$C10BAD [$c -> $got, want $want]"
done
[ -z "$C10BAD" ] \
    && ok "C10 classifier: a redirect makes it a write, and a heredoc body is never read as commands" \
    || no "C10 classifier: misclassified:$C10BAD"

# ── C11: the docs carry the S2c contract ─────────────────────────────────────────────────────────────
if [ -f "$SCHEMADOC" ]; then
    C11MISS=""
    for needle in 'script-run' 'segment' 'pipeline' 'path component'; do
        grep -Fqi "$needle" "$SCHEMADOC" || C11MISS="$C11MISS $needle"
    done
    [ -z "$C11MISS" ] && ok "C11 docs: SUBSTITUTION_METER.md documents the walk, the pipeline rule and script-run" \
        || no "C11 docs: SUBSTITUTION_METER.md is missing:$C11MISS"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# (13) FIXTURE ISOLATION — the arms that prove a gate run cannot reach the operator's log
#
# The design and the bug are documented at the top of this file. This section runs LAST because I2,
# the arm that matters, is a statement about everything above it.
#
# I2 does not compare byte sizes. On a machine where the hook is installed, a real agent session can
# append to the live log while this gate is running, so a size assertion is flaky in exactly the
# situation the assertion is for. Provenance is exact instead: every fixture repo in this gate lives
# under `$TMP`, a per-run `mktemp -d` path that no other process on the machine can produce, so a row
# in the operator's log naming it is proof that THIS run leaked — and no amount of concurrent real
# activity can forge one. The byte delta is printed alongside as information, never as a verdict.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

# ── I1: isolation REDIRECTS the rows, it does not silently drop them ────────────────────────────────
# The positive control for I2. If L1 were implemented by turning the meter off, I2 would pass for the
# wrong reason and every arm in section (11) would still be exercising the write path by luck.
GS_ROWS="$( meterrows "$GATE_SINK" )"
[ "$GS_ROWS" -ge 20 ] \
    && ok "I1 isolation: the rows sections (1)-(10) used to leak land in the gate's own sink ($GS_ROWS rows)" \
    || no "I1 isolation: gate sink holds $GS_ROWS row(s) — isolation must redirect the rows, not drop them"

# ── I3: the L2 guard. A harness that names no destination writes NO row, and still nudges ───────────
TI3="$TMP/ti3"; mkdir -p "$TI3"
GUARDHOME="$TMP/guardhome"; mkdir -p "$GUARDHOME"
OUTI3="$( printf '%s' "$( grepjson guardcase needle )" \
    | env -u RIPWIRE_METER_LOG -u RIPWIRE_HOME HOME="$GUARDHOME" RIPWIRE_METER_FIXTURE=1 \
        PATH="$WITH_RIPWIRE" TMPDIR="$TI3" bash "$HOOK" )"; RCI3=$?
[ "$RCI3" -eq 0 ] && [ -n "$OUTI3" ] && [ ! -f "$GUARDHOME/.ripwire/substitution.jsonl" ] \
    && ok "I3 isolation: RIPWIRE_METER_FIXTURE with no named destination writes no row, and the nudge still fires" \
    || no "I3 isolation: exit=$RCI3 nudge=[${OUTI3:+set}] rows=$( meterrows "$GUARDHOME/.ripwire/substitution.jsonl" )"

# ── I4: with the guard absent, the production $HOME fallback still resolves ─────────────────────────
# THE ONE ARM THAT OPTS OUT OF L2, so that the resolution real installs actually use stays gated. It
# sandboxes $HOME to do it; if that sandbox is ever dropped, I2 below is what fails.
TI4="$TMP/ti4"; mkdir -p "$TI4"
FALLHOME="$TMP/fallbackhome"; mkdir -p "$FALLHOME"
printf '%s' "$( grepjson fallbackcase needle )" \
    | env -u RIPWIRE_METER_LOG -u RIPWIRE_HOME -u RIPWIRE_METER_FIXTURE HOME="$FALLHOME" \
        PATH="$WITH_RIPWIRE" TMPDIR="$TI4" bash "$HOOK" >/dev/null 2>&1
[ "$( meterrows "$FALLHOME/.ripwire/substitution.jsonl" )" = "1" ] \
    && ok "I4 isolation: without the guard, \$HOME/.ripwire/substitution.jsonl is still the default (production path gated)" \
    || no "I4 isolation: the HOME fallback wrote $( meterrows "$FALLHOME/.ripwire/substitution.jsonl" ) row(s), expected 1"

# ── I5-I6: the scrub tool. A guard stops NEW pollution; existing logs still need repairing ──────────
SCRUB="$ROOT/bench/substitution_scrub.py"
if [ -f "$SCRUB" ]; then
    # The gate's own sink is the ideal fixture: by construction every row in it is synthetic, so a
    # correct scrub leaves nothing. This is a stronger test than a hand-built sample — it re-derives
    # itself from whatever arms this file grows.
    SZ_BEFORE="$( wc -c <"$GATE_SINK" 2>/dev/null | tr -d ' ' )"
    python3 "$SCRUB" "$GATE_SINK" --out "$TMP/scrubbed.jsonl" >"$TMP/scrub.out" 2>&1; RCSC=$?
    SZ_AFTER="$( wc -c <"$GATE_SINK" 2>/dev/null | tr -d ' ' )"
    echo "-- substitution_scrub.py output (tail) --"; tail -n 12 "$TMP/scrub.out"
    # not `meterrows`: on a file that EXISTS but is empty, `grep -c` prints 0 and exits 1, so that
    # helper's `|| echo 0` fires on top of the 0 it already printed. An empty cleaned copy is exactly
    # the expected result here, so this arm counts its own way.
    SCRUBROWS="$( grep -c . "$TMP/scrubbed.jsonl" 2>/dev/null )"; [ -n "$SCRUBROWS" ] || SCRUBROWS=0
    [ "$RCSC" -eq 0 ] && [ "$SCRUBROWS" -eq 0 ] \
        && ok "I5 scrub: bench/substitution_scrub.py removes every fixture row from a gate-written log" \
        || no "I5 scrub: exit=$RCSC, $SCRUBROWS row(s) survived — see $TMP/scrub.out"
    [ "$SZ_BEFORE" = "$SZ_AFTER" ] \
        && ok "I5b scrub: the input log is never modified in place" \
        || no "I5b scrub: input changed size $SZ_BEFORE -> $SZ_AFTER"
    if python3 "$SCRUB" "$GATE_SINK" --out "$GATE_SINK" >/dev/null 2>&1; then
        no "I5c scrub: writing the cleaned copy OVER its input must be refused"
    else
        ok "I5c scrub: refuses to write the cleaned copy over its input"
    fi
    grep -qi 'removed' "$TMP/scrub.out" \
        && ok "I5d scrub: the run reports what it removed and why" \
        || no "I5d scrub: no removal report in the output"
else
    no "I5 scrub: bench/substitution_scrub.py does not exist"
fi
if [ -f "$SCHEMADOC" ]; then
    I6MISS=""
    for needle in 'RIPWIRE_METER_FIXTURE' 'substitution_scrub.py'; do
        grep -Fq "$needle" "$SCHEMADOC" || I6MISS="$I6MISS $needle"
    done
    [ -z "$I6MISS" ] && ok "I6 docs: SUBSTITUTION_METER.md carries the isolation contract and the scrub tool" \
        || no "I6 docs: SUBSTITUTION_METER.md is missing:$I6MISS"
fi

# ── I2: THE CANARY. No row in the operator's real log came from this run. ───────────────────────────
NOW_BYTES=0
[ -f "$REAL_METER_LOG" ] && NOW_BYTES="$( wc -c <"$REAL_METER_LOG" 2>/dev/null | tr -d ' ' )"
echo "  (operator log $REAL_METER_LOG: ${REAL_METER_BYTES} -> ${NOW_BYTES} bytes during this run;"
echo "   a delta here is concurrent REAL agent activity, which is why the assertion is provenance, not size)"
if [ -f "$REAL_METER_LOG" ]; then
    LEAKED="$( grep -c -F "$TMP" "$REAL_METER_LOG" 2>/dev/null )"
    [ -n "$LEAKED" ] || LEAKED=0
    [ "$LEAKED" -eq 0 ] \
        && ok "I2 isolation: the operator's meter log contains NO row from this run's fixtures" \
        || no "I2 isolation: $LEAKED fixture row(s) LEAKED into $REAL_METER_LOG — an arm escaped both layers"
else
    ok "I2 isolation: no operator meter log on this machine — nothing this run could have polluted"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
