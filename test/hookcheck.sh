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

# ---- meter-row readers. Defined HERE, above section (1), rather than inside section (11) where they
#      were born: since the §RETIRED change the hook says nothing on the PreToolUse path, so the ROW is
#      what every arm from (1) onward has to read to assert anything at all.
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

echo "hookcheck: HOOK=$HOOK"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# §RETIRED (2026-09-02) — WHAT SECTIONS (1)-(7), (12) AND (12c) NOW ASSERT.
#
# The randomized A/B registered in docs/EVALS.md §4 measured BOTH nudge tiers inert, and the hook
# applied the consequence: the PreToolUse path emits NOTHING, on every tool call, in both arms. The
# arms below used to assert the text of a tip; they now assert the two things that replaced it —
# stdout is EMPTY, and the METER ROW still records which call the retired advice would have landed on
# (`nudge=retired` for the base tier, `nudge=retired-sweep` for the escalation, `dedup` inside the
# cooldown). That second half is the load-bearing one: an eligibility rule that stops being gated the
# moment its delivery is removed will drift, and the drift is invisible because nothing speaks.
#
# The SessionStart primer is untouched and still gated by section (3i) and arms A3/A4 — it is the one
# thing this hook still says, and the one behaviour the arm still separates.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

# ── (1) Grep case: counted, ELIGIBLE, and silent ──────────────────────────────────────────────────
# Pattern is an OR-chain (P4.2, 2026-08-29): the §CEDE gate still decides base-tier ELIGIBILITY, so a
# short single literal would log nudge=none and this arm would pass for the wrong reason.
T1="$TMP/t1"; mkdir -p "$T1"
L1="$TMP/t1.jsonl"
GREP_JSON='{"session_id":"grepcase","cwd":"'"$REPO"'","tool_name":"Grep","tool_input":{"pattern":"foo|bar","path":"."}}'
OUT1="$( printf '%s' "$GREP_JSON" | env RIPWIRE_METER_LOG="$L1" PATH="$WITH_RIPWIRE" TMPDIR="$T1" bash "$HOOK" )"; RC1=$?
echo "-- Grep case output --"; echo "[$OUT1]"; echo "(exit=$RC1)"

[ "$RC1" -eq 0 ] && ok "Grep case: exit 0" || no "Grep case: exit was $RC1"
[ -z "$OUT1" ] && ok "Grep case: SILENT — the retired base tier says nothing" \
    || no "Grep case: the retired base tier emitted ${#OUT1} byte(s): [$OUT1]"
[ "$( meterrowget "$L1" 1 nudge )" = "retired" ] && [ "$( meterrowget "$L1" 1 nudged )" = "0" ] \
    && ok "Grep case: the delivery moment is still RECORDED (nudged=0 nudge=retired)" \
    || no "Grep case: row = nudged=[$( meterrowget "$L1" 1 nudged )] nudge=[$( meterrowget "$L1" 1 nudge )]"

# ── (2) Grep case, second invocation same session: inside the cooldown ────────────────────────────
OUT1B="$( printf '%s' "$GREP_JSON" | env RIPWIRE_METER_LOG="$L1" PATH="$WITH_RIPWIRE" TMPDIR="$T1" bash "$HOOK" )"; RC1B=$?
echo "-- Grep case, 2nd invocation (dedup) --"; echo "[$OUT1B]"; echo "(exit=$RC1B)"
[ "$RC1B" -eq 0 ] && ok "Grep dedup: exit 0" || no "Grep dedup: exit was $RC1B"
[ -z "$OUT1B" ] && ok "Grep dedup: silent on 2nd call" || no "Grep dedup: 2nd call was not silent: $OUT1B"
[ "$( meterrowget "$L1" 2 nudge )" = "dedup" ] \
    && ok "Grep dedup: the cooldown is still recorded on the row (nudge=dedup)" \
    || no "Grep dedup: row 2 nudge=[$( meterrowget "$L1" 2 nudge )], expected dedup"

# ── (3) Bash-grep case (recursive): fires, names --grep or --for ───────────────────────────────────
# OR-chain pattern (P4.2) — see the note at case (1).
T3="$TMP/t3"; mkdir -p "$T3"
BASHGREP_JSON='{"session_id":"bashcase","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"grep -rn '\''needle|other'\'' ."}}'
L3="$TMP/t3.jsonl"
OUT3="$( printf '%s' "$BASHGREP_JSON" | env RIPWIRE_METER_LOG="$L3" PATH="$WITH_RIPWIRE" TMPDIR="$T3" bash "$HOOK" )"; RC3=$?
echo "-- Bash-grep case output --"; echo "[$OUT3]"; echo "(exit=$RC3)"

[ "$RC3" -eq 0 ] && ok "Bash-grep case: exit 0" || no "Bash-grep case: exit was $RC3"
[ -z "$OUT3" ] && ok "Bash-grep case: silent" || no "Bash-grep case: emitted [$OUT3]"
[ "$( meterrowget "$L3" 1 class )" = "grep" ] && [ "$( meterrowget "$L3" 1 nudge )" = "retired" ] \
    && ok "Bash-grep case: counted as grep, delivery moment recorded (nudge=retired)" \
    || no "Bash-grep case: row = class=[$( meterrowget "$L3" 1 class )] nudge=[$( meterrowget "$L3" 1 nudge )]"

# ripgrep spelling also counts (OR-chain pattern, P4.2 — see the note at case (1))
T3B="$TMP/t3b"; mkdir -p "$T3B"; L3B="$TMP/t3b.jsonl"
RG_JSON='{"session_id":"rgcase","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"rg '\''needle|other'\'' ."}}'
OUT3B="$( printf '%s' "$RG_JSON" | env RIPWIRE_METER_LOG="$L3B" PATH="$WITH_RIPWIRE" TMPDIR="$T3B" bash "$HOOK" )"; RC3B=$?
[ "$RC3B" -eq 0 ] && [ -z "$OUT3B" ] && [ "$( meterrowget "$L3B" 1 nudge )" = "retired" ] \
    && ok "Bash rg case: eligible, recorded, silent (exit 0)" \
    || no "Bash rg case: exit=$RC3B out=[$OUT3B] nudge=[$( meterrowget "$L3B" 1 nudge )]"

# ── (3c)-(3e) the git-history categories: still classified, still eligible, silent ─────────────────
# One loop rather than three near-identical blocks: with no text to inspect, what each of these arms
# now asserts is the same three facts, and the class is the only thing that differs.
G3BAD=""
i=0
for pair in "gitdiffcase|git diff HEAD|git-diff" \
            "gitdiffstatcase|git diff --stat -- src/foo.cpp|git-diff" \
            "gitlogcase|git log --oneline -5|git-log" \
            "gitshowcase|git show abc123 --stat|git-show-stat"; do
    sid="${pair%%|*}"; rest="${pair#*|}"; c="${rest%|*}"; want="${rest#*|}"; i=$(( i + 1 ))
    TG="$TMP/t3g_$i"; mkdir -p "$TG"; LG="$TMP/t3g_$i.jsonl"
    J='{"session_id":"'"$sid"'","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"'"$c"'"}}'
    O="$( printf '%s' "$J" | env RIPWIRE_METER_LOG="$LG" PATH="$WITH_RIPWIRE" TMPDIR="$TG" bash "$HOOK" )"; R=$?
    gc="$( meterrowget "$LG" 1 class )"; gn="$( meterrowget "$LG" 1 nudge )"
    [ "$R" -eq 0 ] && [ -z "$O" ] && [ "$gc" = "$want" ] && [ "$gn" = "retired" ] \
        || G3BAD="$G3BAD [$c -> exit=$R out=${O:+set} class=$gc nudge=$gn, want $want/retired]"
done
[ -z "$G3BAD" ] \
    && ok "git diff/log/show --stat: classified, delivery moment recorded, all silent" \
    || no "git-history cases:$G3BAD"

# dedup: a second git-diff call in the SAME session records the cooldown
T3C="$TMP/t3c"; mkdir -p "$T3C"; L3C="$TMP/t3c.jsonl"
GITDIFF_JSON='{"session_id":"gitdiffdedup","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":{"command":"git diff HEAD"}}'
printf '%s' "$GITDIFF_JSON" | env RIPWIRE_METER_LOG="$L3C" PATH="$WITH_RIPWIRE" TMPDIR="$T3C" bash "$HOOK" >/dev/null 2>&1
OUT3C_DEDUP="$( printf '%s' "$GITDIFF_JSON" | env RIPWIRE_METER_LOG="$L3C" PATH="$WITH_RIPWIRE" TMPDIR="$T3C" bash "$HOOK" )"; RC3C_DEDUP=$?
[ "$RC3C_DEDUP" -eq 0 ] && [ -z "$OUT3C_DEDUP" ] && [ "$( meterrowget "$L3C" 2 nudge )" = "dedup" ] \
    && ok "git diff dedup: the 2nd call records nudge=dedup" \
    || no "git diff dedup: exit=$RC3C_DEDUP out=[$OUT3C_DEDUP] nudge=[$( meterrowget "$L3C" 2 nudge )]"

# ── (3f) Read case (2026-08-10 audit): fires, names --expand, allow-never-deny ─────────────────────
# The read nudge is the load-bearing one: whole-file reads are the largest token sink in an agent loop
# and the only default a skill description cannot intercept.
T3F="$TMP/t3f"; mkdir -p "$T3F"; L3F="$TMP/t3f.jsonl"
READ_JSON='{"session_id":"readcase","cwd":"'"$REPO"'","tool_name":"Read","tool_input":{"file_path":"src/foo.cpp"}}'
OUT3F="$( printf '%s' "$READ_JSON" | env RIPWIRE_METER_LOG="$L3F" PATH="$WITH_RIPWIRE" TMPDIR="$T3F" bash "$HOOK" )"; RC3F=$?
echo "-- Read case output --"; echo "[$OUT3F]"; echo "(exit=$RC3F)"
[ "$RC3F" -eq 0 ] && ok "Read case: exit 0" || no "Read case: exit was $RC3F"
[ -z "$OUT3F" ] && ok "Read case: silent" || no "Read case: emitted [$OUT3F]"
[ "$( meterrowget "$L3F" 1 class )" = "read" ] && [ "$( meterrowget "$L3F" 1 nudge )" = "retired" ] \
    && ok "Read case: counted as read, delivery moment recorded (nudge=retired)" \
    || no "Read case: row = class=[$( meterrowget "$L3F" 1 class )] nudge=[$( meterrowget "$L3F" 1 nudge )]"

# dedup within the read category
OUT3F2="$( printf '%s' "$READ_JSON" | env RIPWIRE_METER_LOG="$L3F" PATH="$WITH_RIPWIRE" TMPDIR="$T3F" bash "$HOOK" )"; RC3F2=$?
[ "$RC3F2" -eq 0 ] && [ -z "$OUT3F2" ] && [ "$( meterrowget "$L3F" 2 nudge )" = "dedup" ] \
    && ok "Read dedup: 2nd call records nudge=dedup" \
    || no "Read dedup: exit=$RC3F2 out=[$OUT3F2] nudge=[$( meterrowget "$L3F" 2 nudge )]"

# A Grep in the SAME session reaches its OWN first-sighting slot: read and grep are different habits
# with independent cooldown clocks, and with nothing on stdout the row is the only place that shows.
# OR-chain pattern (P4.2, 2026-08-29) — see the note at case (1).
GREP_SAME='{"session_id":"readcase","cwd":"'"$REPO"'","tool_name":"Grep","tool_input":{"pattern":"x|y"}}'
OUT3F3="$( printf '%s' "$GREP_SAME" | env RIPWIRE_METER_LOG="$L3F" PATH="$WITH_RIPWIRE" TMPDIR="$T3F" bash "$HOOK" )"; RC3F3=$?
[ "$RC3F3" -eq 0 ] && [ -z "$OUT3F3" ] && [ "$( meterrowget "$L3F" 3 nudge )" = "retired" ] \
    && ok "Read and Grep keep INDEPENDENT cooldown clocks (grep row 3 is a fresh first sighting)" \
    || no "Read/Grep share a cooldown clock: row 3 nudge=[$( meterrowget "$L3F" 3 nudge )], expected retired"

# ── (3g) Glob case: classified, eligible, silent ───────────────────────────────────────────────────
T3G="$TMP/t3gl"; mkdir -p "$T3G"; L3G="$TMP/t3gl.jsonl"
GLOB_JSON='{"session_id":"globcase","cwd":"'"$REPO"'","tool_name":"Glob","tool_input":{"pattern":"**/*.cpp"}}'
OUT3G="$( printf '%s' "$GLOB_JSON" | env RIPWIRE_METER_LOG="$L3G" PATH="$WITH_RIPWIRE" TMPDIR="$T3G" bash "$HOOK" )"; RC3G=$?
echo "-- Glob case output --"; echo "[$OUT3G]"; echo "(exit=$RC3G)"
[ "$RC3G" -eq 0 ] && [ -z "$OUT3G" ] && [ "$( meterrowget "$L3G" 1 class )" = "glob" ] \
    && [ "$( meterrowget "$L3G" 1 nudge )" = "retired" ] \
    && ok "Glob case: counted as glob, delivery moment recorded, silent" \
    || no "Glob case: exit=$RC3G out=[$OUT3G] class=[$( meterrowget "$L3G" 1 class )] nudge=[$( meterrowget "$L3G" 1 nudge )]"

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
REALBIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
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

# ── (7) Different session ids keep independent cooldown state (per-session, not global) ───────────
# OR-chain pattern (P4.2) — see the note at case (1). With nothing on stdout, the row is the proof:
# a second session's FIRST eligible call must read `retired` (its own first sighting), not `dedup`.
T7="$TMP/t7"; mkdir -p "$T7"; L7="$TMP/t7.jsonl"
GREP_JSON_S2='{"session_id":"grepcase2","cwd":"'"$REPO"'","tool_name":"Grep","tool_input":{"pattern":"foo|bar"}}'
OUT7="$( printf '%s' "$GREP_JSON_S2" | env RIPWIRE_METER_LOG="$L7" PATH="$WITH_RIPWIRE" TMPDIR="$T7" bash "$HOOK" )"; RC7=$?
[ "$RC7" -eq 0 ] && [ -z "$OUT7" ] && [ "$( meterrowget "$L7" 1 nudge )" = "retired" ] \
    && ok "New session id: fresh cooldown state, independent of case (1)'s markers" \
    || no "New session id: exit=$RC7 out=[$OUT7] nudge=[$( meterrowget "$L7" 1 nudge )]"

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
    # Re-pinned 2026-09-05 (lane T): the matcher is a whole-name REGEX now. The 2026-09-04 form
    # `Read|Glob|Grep|Bash|mcp__ripwire__` held only exact-list characters, so Claude Code compared
    # `mcp__ripwire__` as a whole tool name and no MCP call ever reached the hook — section (14).
    jq -e '(.hooks.PreToolUse // [])[] | select(.hooks[]?.command | test("ripwire-nudge")) | .matcher == "^(Read|Glob|Grep|Bash|Edit|Write|MultiEdit|NotebookEdit|mcp__ripwire__.*)$"' \
        "$SETTINGS" >/dev/null 2>&1 \
        && ok "settings.json PreToolUse matcher is ^(Read|Glob|Grep|Bash|Edit|Write|MultiEdit|NotebookEdit|mcp__ripwire__.*)\$" || no "settings.json PreToolUse matcher missing/wrong"
    # Read/Glob are load-bearing, not incidental: the whole-file read is the largest token sink in the
    # loop and the one default no skill description can intercept. Assert them by NAME so a future
    # matcher edit that quietly drops them fails here.
    for m in Read Glob Grep Bash Edit Write MultiEdit NotebookEdit; do
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
# OR-chain pattern (P4.2, 2026-08-29): a single literal no longer reaches the dedup mechanics at all
# (category is demoted to "" before this block, so the row logs nudge=none, not nudge=fired/dedup) —
# see the note at case (1). This arm is about the dedup/seq/post_nudge MACHINERY, not the grep gate.
TM4="$TMP/tm4"; mkdir -p "$TM4"; L4="$TMP/m4.jsonl"
M4_JSON='{"session_id":"meter4","cwd":"'"$REPO"'","tool_name":"Grep","tool_input":{"pattern":"n|m"}}'
OUTM4="$( run_meter "$L4" "$M4_JSON" "$TM4" )"
[ "$( meterrowget "$L4" 1 nudged )" = "0" ] && [ "$( meterrowget "$L4" 1 nudge )" = "retired" ] && [ -z "$OUTM4" ] \
    && ok "M4 meter: the delivery moment is logged nudged=0 nudge=retired (§RETIRED: recorded, not spoken)" \
    || no "M4 meter: nudged=[$( meterrowget "$L4" 1 nudged )] nudge=[$( meterrowget "$L4" 1 nudge )] out=[${OUTM4:+set}]"
OUTM5="$( run_meter "$L4" "$M4_JSON" "$TM4" )"
[ "$( meterrows "$L4" )" = "2" ] && [ "$( meterrowget "$L4" 2 nudged )" = "0" ] && [ "$( meterrowget "$L4" 2 nudge )" = "dedup" ] && [ -z "$OUTM5" ] \
    && ok "M5 meter: a call inside the cooldown is STILL counted, as nudged=0 nudge=dedup" \
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
[ "$( meterrowget "$L15" 1 class )" = "git-diff" ] && [ "$( meterrowget "$L15" 1 family )" = "git" ] && [ "$( meterrowget "$L15" 1 nudge )" = "retired" ] \
    && ok "M15 meter: git diff -> git-diff/git, and the retired delivery moment is recorded on the row" \
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

# ── M19-M20: the arm is on every row, and the PreToolUse path is now ARM-INDEPENDENT ───────────────
# §RETIRED (2026-09-02): with both tiers silent in both arms, the PreToolUse path can no longer differ
# by arm — so these arms assert exactly that, plus the two things that did NOT change: the arm is still
# resolved, still recorded on the row, and still defaults to treatment. The one behaviour the arm does
# separate is the SessionStart primer, gated by A3/A4.
# OR-chain pattern (P4.2, 2026-08-29): a literal `grep -rn needle .` would demote category to "" before
# the arm is consulted, and these arms would pass for the wrong reason (nudge=none).
TM19="$TMP/tm19"; mkdir -p "$TM19"; L19="$TMP/m19.jsonl"
OUTM19="$( run_meter "$L19" "$( bashjson meter19 "grep -rn 'needle|other' ." )" "$TM19" RIPWIRE_METER_ARM=control )"
[ "$( meterrowget "$L19" 1 arm )" = "control" ] && [ "$( meterrowget "$L19" 1 nudged )" = "0" ] \
    && [ "$( meterrowget "$L19" 1 nudge )" = "retired" ] && [ -z "$OUTM19" ] \
    && ok "M19 meter: control arm counts the call, records the delivery moment, and says nothing" \
    || no "M19 meter: arm=[$( meterrowget "$L19" 1 arm )] nudged=[$( meterrowget "$L19" 1 nudged )] nudge=[$( meterrowget "$L19" 1 nudge )] out=[$OUTM19]"
TM20="$TMP/tm20"; mkdir -p "$TM20"; L20="$TMP/m20.jsonl"
OUTM20="$( run_meter "$L20" "$( bashjson meter20 "grep -rn 'needle|other' ." )" "$TM20" )"
[ "$( meterrowget "$L20" 1 arm )" = "treatment" ] && [ -z "$OUTM20" ] \
    && [ "$( meterrowget "$L20" 1 nudge )" = "retired" ] \
    && ok "M20 meter: DEFAULT arm is treatment, and treatment's PreToolUse path is silent too" \
    || no "M20 meter: default arm=[$( meterrowget "$L20" 1 arm )] nudge=[$( meterrowget "$L20" 1 nudge )] out=[${OUTM20:+set}]"
[ "$OUTM19" = "$OUTM20" ] \
    && ok "M20b meter: control and treatment produce BYTE-IDENTICAL PreToolUse output (both empty)" \
    || no "M20b meter: the arms still differ on the PreToolUse path: control=[$OUTM19] treatment=[$OUTM20]"

# ── M21-M23: the meter is subordinate to the call it observes ───────────────────────────────────────
# OR-chain pattern (P4.2) — same reason as M19/M20: these arms are about the meter's failure-tolerance,
# not the grep gate, and need a nudge-eligible call to prove the nudge survives that failure.
TM21="$TMP/tm21"; mkdir -p "$TM21"
UNWRITABLE="$TMP/unwritable"; mkdir -p "$UNWRITABLE"; chmod 500 "$UNWRITABLE"
OUTM21="$( printf '%s' "$( bashjson meter21 "grep -rn 'needle|other' ." )" \
    | env HOME="$UNWRITABLE" PATH="$WITH_RIPWIRE" TMPDIR="$TM21" bash "$HOOK" )"; RCM21=$?
chmod 700 "$UNWRITABLE"
[ "$RCM21" -eq 0 ] && [ -z "$OUTM21" ] \
    && ok "M21 meter: an unwritable log costs the hooked command nothing (exit 0, no stderr, no stdout)" \
    || no "M21 meter: unwritable log broke the hook: exit=$RCM21 out=[$OUTM21]"
TM22="$TMP/tm22"; mkdir -p "$TM22"; L22="$TMP/m22.jsonl"
OUTM22="$( run_meter "$L22" "$( bashjson meter22 "grep -rn 'needle|other' ." )" "$TM22" RIPWIRE_METER=0 )"; RCM22=$?
[ "$( meterrows "$L22" )" = "0" ] && [ -z "$OUTM22" ] && [ "$RCM22" -eq 0 ] \
    && ok "M22 meter: RIPWIRE_METER=0 opts out of counting and costs the hooked call nothing" \
    || no "M22 meter: opt-out left $( meterrows "$L22" ) row(s), exit=$RCM22 out=[${OUTM22:+set}]"
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
    # termrow SEQ SESSION TOOL CLASS FAMILY DETAIL [AGENT SURFACE TARGET]
    # Six arguments write a v2 row (the shape every row before 2026-09-05 has, so the FIND fixture
    # keeps proving the report reads them); nine write a v3 row with agent/surface/target for §5b.
    if [ "$#" -ge 9 ]; then
        printf '{"v":3,"ts":"2026-09-05T00:00:00Z","seq":%s,"session":"%s","repo":"/x/repo","tag":"repo","tool":"%s","class":"%s","family":"%s","nudged":0,"nudge":"none","post_nudge":0,"post_sweep":0,"arm":"treatment","detail":"%s","agent":"%s","surface":"%s","target":"%s"}\n' \
            "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" >>"$TERMLOG"
    else
        printf '{"v":2,"ts":"2026-08-12T00:00:00Z","seq":%s,"session":"%s","repo":"/x/repo","tag":"repo","tool":"%s","class":"%s","family":"%s","nudged":0,"nudge":"none","post_nudge":0,"post_sweep":0,"arm":"treatment","detail":"%s"}\n' \
            "$1" "$2" "$3" "$4" "$5" "$6" >>"$TERMLOG"
    fi
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

# ── S1-S6: the grep sweep, RETIRED (2026-09-02). Three calls, ONE escalation moment, recorded and
#    silent. Patterns are single literals on purpose: this is the real-world "same-class sweep of
#    known-literal greps" shape, and the escalation tier still reaches its threshold at the 3rd call
#    even though none of the three passes the base tier's §CEDE gate. That the ESCALATION MOMENT is
#    still identified at exactly call 3 is the whole contract now — the text it used to carry is gone
#    and the arms that asserted `--for="alpha beta gamma"`, the repo-directory interpolation and the
#    per-class message wording went with it, because there is nothing left for them to read.
TS1="$TMP/ts1"; mkdir -p "$TS1"; LS1="$TMP/s1.jsonl"
SW1="$( sweep_run "$LS1" "$TS1" "$( grepjson sweepgrep alpha )" )"
SW2="$( sweep_run "$LS1" "$TS1" "$( grepjson sweepgrep beta )" )"
SW3="$( sweep_run "$LS1" "$TS1" "$( grepjson sweepgrep gamma )" )"; RCS3=$?
SW4="$( sweep_run "$LS1" "$TS1" "$( grepjson sweepgrep delta )" )"

[ -z "$SW1" ] && ok "S1 sweep: call 1 (a single literal) is silent" \
    || no "S1 sweep: call 1 emitted: [$SW1]"
[ -z "$SW2" ] && ok "S3 sweep: call 2 is silent, and is not the escalation moment" \
    || no "S3 sweep: call 2 emitted: [$SW2]"
[ "$( meterrowget "$LS1" 2 nudge )" = "none" ] \
    && ok "S3b sweep: call 2's row says nudge=none (two same-class calls are not a sweep)" \
    || no "S3b sweep: row 2 nudge=[$( meterrowget "$LS1" 2 nudge )], expected none"
[ "$RCS3" -eq 0 ] && [ -z "$SW3" ] && ok "S2 sweep: call 3 is silent (exit 0)" \
    || no "S2 sweep: call 3 exit=$RCS3 out=[$SW3]"
[ -z "$SW4" ] && ok "S4 sweep: call 4 is silent too" || no "S4 sweep: call 4 emitted: [$SW4]"

# ── S5: the escalation MOMENT is on the ROW. Without this the eligibility question — how often was
#    the sweep threshold even reached — cannot be asked at all, and it is the covariate the next
#    instrument's readout needs.
[ "$( meterrowget "$LS1" 3 nudge )" = "retired-sweep" ] && [ "$( meterrowget "$LS1" 3 nudged )" = "0" ] \
    && ok "S5 sweep: the escalation moment is logged nudged=0 nudge=retired-sweep" \
    || no "S5 sweep: row 3 = nudged=[$( meterrowget "$LS1" 3 nudged )] nudge=[$( meterrowget "$LS1" 3 nudge )]"
[ "$( meterrowget "$LS1" 3 post_sweep )" = "0" ] && [ "$( meterrowget "$LS1" 4 post_sweep )" = "1" ] \
    && ok "S5b sweep: post_sweep marks the calls AFTER the escalation moment, not the one at it" \
    || no "S5b sweep: post_sweep was [$( meterrowget "$LS1" 3 post_sweep )] then [$( meterrowget "$LS1" 4 post_sweep )]"
[ "$( meterrows "$LS1" )" = "4" ] \
    && ok "S5c sweep: all four calls are still counted" \
    || no "S5c sweep: expected 4 rows, got $( meterrows "$LS1" )"

# ── S6: NOTHING reaches stdout on any of the four calls, and nothing reaches stderr either. This is
#    the §RETIRED contract stated positively: the PreToolUse path is now a pure instrument.
ERRS6="$TMP/s6.err"; TS6="$TMP/ts6"; mkdir -p "$TS6"
S6BAD=""
for pt in a b c d e; do
    O="$( sweep_run "$TMP/s6.jsonl" "$TS6" "$( grepjson sweepsilent "$pt" )" 2>>"$ERRS6" )"
    [ -z "$O" ] || S6BAD="$S6BAD [$pt: $O]"
done
[ -z "$S6BAD" ] && ok "S6 sweep: five same-class calls, zero bytes of stdout across all of them" \
    || no "S6 sweep: output leaked:$S6BAD"
[ ! -s "$ERRS6" ] && ok "S6b sweep: and nothing on the hooked call's stderr" \
    || no "S6b sweep: stderr leaked: $( cat "$ERRS6" )"

# ── S7-S9: the read, glob and git-history sweeps reach their own escalation moments ────────────────
S79BAD=""
i=0
for spec in "read|/w/proj/src/a.cpp|/w/proj/src/b.cpp|/w/proj/src/c.cpp" \
            "glob|**/*.c|**/*.h|**/*.py"; do
    kind="${spec%%|*}"; rest="${spec#*|}"; i=$(( i + 1 ))
    TS="$TMP/ts7_$i"; mkdir -p "$TS"; LS="$TMP/s7_$i.jsonl"
    n=0
    while [ -n "$rest" ]; do
        arg="${rest%%|*}"; case "$rest" in *"|"*) rest="${rest#*|}" ;; *) rest="" ;; esac
        n=$(( n + 1 ))
        if [ "$kind" = read ]; then J="$( readjson "sweep$kind" "$arg" )"; else J="$( globjson "sweep$kind" "$arg" )"; fi
        O="$( sweep_run "$LS" "$TS" "$J" )"
        [ -z "$O" ] || S79BAD="$S79BAD [$kind call$n emitted]"
    done
    [ "$( meterrowget "$LS" 3 nudge )" = "retired-sweep" ] || S79BAD="$S79BAD [$kind row3=$( meterrowget "$LS" 3 nudge )]"
done
TS9="$TMP/ts9"; mkdir -p "$TS9"; LS9="$TMP/s9.jsonl"
for c in 'git diff HEAD' 'git diff --stat' 'git diff -- src/'; do
    O="$( sweep_run "$LS9" "$TS9" "$( bashjson sweepgit "$c" )" )"
    [ -z "$O" ] || S79BAD="$S79BAD [git-diff emitted]"
done
[ "$( meterrowget "$LS9" 3 nudge )" = "retired-sweep" ] || S79BAD="$S79BAD [git-diff row3=$( meterrowget "$LS9" 3 nudge )]"
[ -z "$S79BAD" ] \
    && ok "S7-S9 sweep: read / glob / git-history sweeps each reach their escalation moment, silently" \
    || no "S7-S9 sweep:$S79BAD"

# ── S10: classes track INDEPENDENTLY — a spent grep escalation must not consume the read tier's ────
TS10="$TMP/ts10"; mkdir -p "$TS10"; LS10="$TMP/s10.jsonl"
for pt in a b c; do sweep_run "$LS10" "$TS10" "$( grepjson sweepboth "$pt" )" >/dev/null; done
for f in /q/x/1.c /q/x/2.c /q/x/3.c; do sweep_run "$LS10" "$TS10" "$( readjson sweepboth "$f" )" >/dev/null; done
[ "$( meterrowget "$LS10" 3 nudge )" = "retired-sweep" ] && [ "$( meterrowget "$LS10" 6 nudge )" = "retired-sweep" ] \
    && ok "S10 sweep: a spent grep escalation does not consume the read escalation slot" \
    || no "S10 sweep: rows 3/6 = [$( meterrowget "$LS10" 3 nudge )]/[$( meterrowget "$LS10" 6 nudge )]"

# ── S12: the off-switches still resolve. RIPWIRE_SWEEP=0 now gates the sweep COUNTERS only, since
#    there is no delivery left to gate — so with it set, the 3rd call must fall through to the base
#    tier's own verdict instead of being named an escalation moment.
TS12="$TMP/ts12"; mkdir -p "$TS12"; LS12="$TMP/s12.jsonl"
for pt in "a|z" "b|z"; do sweep_run "$LS12" "$TS12" "$( grepjson sweepoff "$pt" )" RIPWIRE_SWEEP=0 >/dev/null; done
SW12="$( sweep_run "$LS12" "$TS12" "$( grepjson sweepoff 'c|z' )" RIPWIRE_SWEEP=0 )"
[ -z "$SW12" ] && [ "$( meterrowget "$LS12" 3 nudge )" = "dedup" ] \
    && ok "S12 sweep: RIPWIRE_SWEEP=0 stops the escalation bookkeeping and leaves counting intact" \
    || no "S12 sweep: with RIPWIRE_SWEEP=0 the 3rd call gave out=[$SW12] nudge=[$( meterrowget "$LS12" 3 nudge )]"
TS12B="$TMP/ts12b"; mkdir -p "$TS12B"; LS12B="$TMP/s12b.jsonl"
for pt in a b c; do sweep_run "$LS12B" "$TS12B" "$( grepjson sweepctl "$pt" )" RIPWIRE_METER_ARM=control >/dev/null; done
[ "$( meterrowget "$LS12B" 3 nudge )" = "retired-sweep" ] \
    && ok "S12b sweep: the control arm reaches the SAME escalation moment (the tiers are arm-independent now)" \
    || no "S12b sweep: control-arm 3rd call logged nudge=[$( meterrowget "$LS12B" 3 nudge )]"
TS12C="$TMP/ts12c"; mkdir -p "$TS12C"; LS12C="$TMP/s12c.jsonl"
for pt in "a|z" "b|z" "c|z"; do sweep_run "$LS12C" "$TS12C" "$( grepjson sweepn4 "$pt" )" RIPWIRE_SWEEP_N=4 >/dev/null; done
sweep_run "$LS12C" "$TS12C" "$( grepjson sweepn4 'd|z' )" RIPWIRE_SWEEP_N=4 >/dev/null
[ "$( meterrowget "$LS12C" 3 nudge )" = "dedup" ] && [ "$( meterrowget "$LS12C" 4 nudge )" = "retired-sweep" ] \
    && ok "S12c sweep: RIPWIRE_SWEEP_N=4 moves the threshold to the 4th call" \
    || no "S12c sweep: N=4 gave row3=[$( meterrowget "$LS12C" 3 nudge )] row4=[$( meterrowget "$LS12C" 4 nudge )]"

# ── S13: the sweep path degrades to SILENCE off its preconditions, and never onto stderr ───────────
TS13="$TMP/ts13"; mkdir -p "$TS13"; ERR13="$TMP/s13.err"
S13BAD=""
for pt in a b c; do
    O="$( printf '%s' '{"session_id":"sweepnongit","cwd":"'"$NONREPO"'","tool_name":"Grep","tool_input":{"pattern":"'"$pt"'"}}' \
        | env HOME="$METERHOME" RIPWIRE_METER_LOG="$TMP/s13.jsonl" PATH="$WITH_RIPWIRE" TMPDIR="$TS13" bash "$HOOK" 2>>"$ERR13" )"
    R=$?; [ "$R" -eq 0 ] && [ -z "$O" ] || S13BAD="$S13BAD [nongit:$R:$O]"
done
TS13B="$TMP/ts13b"; mkdir -p "$TS13B"
for pt in a b c; do
    O="$( printf '%s' "$( grepjson sweepnorip "$pt" )" \
        | env HOME="$METERHOME" RIPWIRE_METER_LOG="$TMP/s13b.jsonl" PATH="$NO_RIPWIRE" TMPDIR="$TS13B" bash "$HOOK" 2>>"$ERR13" )"
    R=$?; [ "$R" -eq 0 ] && [ -z "$O" ] || S13BAD="$S13BAD [norip:$R:$O]"
done
[ -z "$S13BAD" ] && ok "S13 sweep: a 3-call sweep in a non-git dir / with no ripwire stays silent, exit 0" \
    || no "S13 sweep: fired or failed off its preconditions:$S13BAD"
# S13c: `gated` needs a call that is base-tier ELIGIBLE and then fails a precondition. A single
# literal is ineligible before gating is ever consulted (§CEDE) and logs `none`, which would make this
# arm pass on a hook that had lost the gating branch entirely.
TS13C="$TMP/ts13c"; mkdir -p "$TS13C"; LS13C="$TMP/s13c.jsonl"
printf '%s' '{"session_id":"gatedcase","cwd":"'"$NONREPO"'","tool_name":"Grep","tool_input":{"pattern":"needle|other"}}' \
    | env HOME="$METERHOME" RIPWIRE_METER_LOG="$LS13C" PATH="$WITH_RIPWIRE" TMPDIR="$TS13C" bash "$HOOK" >/dev/null 2>&1
[ "$( meterrowget "$LS13C" 1 nudge )" = "gated" ] \
    && ok "S13c sweep: an eligible call outside a git repo is still counted, as nudge=gated" \
    || no "S13c sweep: non-git eligible row nudge=[$( meterrowget "$LS13C" 1 nudge )], expected gated"
[ ! -s "$ERR13" ] && ok "S13b sweep: the escalation path writes nothing to the hooked call's stderr" \
    || no "S13b sweep: stderr leaked: $( cat "$ERR13" )"

# ── S14: a Bash grep and the Grep tool are the SAME habit and count toward ONE sweep ───────────────
TS14="$TMP/ts14"; mkdir -p "$TS14"; LS14="$TMP/s14.jsonl"
sweep_run "$LS14" "$TS14" "$( bashjson sweepbash 'grep -rn needleone .' )" >/dev/null
sweep_run "$LS14" "$TS14" "$( bashjson sweepbash 'rg needletwo src/' )" >/dev/null
SW14="$( sweep_run "$LS14" "$TS14" "$( grepjson sweepbash needlethree )" )"
[ -z "$SW14" ] && [ "$( meterrowget "$LS14" 3 nudge )" = "retired-sweep" ] \
    && ok "S14 sweep: Bash grep/rg and the Grep tool count as ONE sweep (mixed shapes, one threshold)" \
    || no "S14 sweep: mixed grep sweep gave out=[$SW14] row3=[$( meterrowget "$LS14" 3 nudge )]"

# ── S15: the §RETIRED contract, asserted against the SCRIPT rather than one payload. A future edit
#    that reintroduces a PreToolUse message would pass every arm above that only reads a row.
#    Comments are stripped first: the file DELIBERATELY keeps the retired mechanism's design record,
#    including the PreToolUse response shape it used to emit, and a naive grep would read the record
#    as the code.
grep -v '^[[:space:]]*#' "$HOOK" | grep -Fq 'hookEventName":"PreToolUse' \
    && no "S15 retired: the hook still contains a live PreToolUse output emitter" \
    || ok "S15 retired: no live PreToolUse output emitter remains in the hook"
grep -v '^[[:space:]]*#' "$HOOK" | grep -Fq 'hookEventName":"SessionStart' \
    && ok "S15b retired: the SessionStart primer emitter is still there (only the nudges were retired)" \
    || no "S15b retired: the SessionStart primer emitter is gone — too much was removed"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# (12c) §CEDE — THE LITERAL-GREP CEDE (P4.2, 2026-08-29), AS AN ELIGIBILITY RULE (§RETIRED 2026-09-02)
#
# Agents correctly drop to `rg`/`grep` for a known-literal hunt (our own docs concede the case), so the
# base tier stopped treating that first call as a nudge moment at all. Since the tier itself was
# retired the rule no longer decides whether anything is SAID — it decides whether the row records a
# base-tier moment, which is what the next instrument compares its own coverage against. The arms
# below are therefore unchanged in what they exercise and changed in what they read: the `nudge` field
# instead of the message. A short single literal must log `none`; an OR-chain or a second `-e` must
# log `retired`. If that ever silently widens, every "how often was the moment reached" number
# computed across the change is wrong and nothing on stdout would have shown it.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

CEDEBAD=""
i=0
# spec fields are separated by `^`, NOT `|`: the OR-chain cases below carry a literal `|` inside the
# pattern, which is the entire signal under test, and a `|` separator would eat it.
for spec in "P1 Grep-tool single literal^grep^needle^none" \
            "P2 Bash 'grep -rn STR .'^bash^grep -rn needle .^none" \
            "P3 Bash rg \"exact string\"^bash^rg \\\"exact string\\\" .^none" \
            "P4 Grep-tool OR-chain^grep^TODO|FIXME^retired" \
            "P5 Bash rg OR-chain^bash^rg 'foo|bar' .^retired" \
            "P6 Bash rg two -e flags^bash^rg -e foo -e bar .^retired" \
            "P7 Bash rg one -e flag^bash^rg -e needle .^none"; do
    lbl="${spec%%^*}"; rest="${spec#*^}"; kind="${rest%%^*}"; rest="${rest#*^}"
    arg="${rest%^*}"; want="${rest##*^}"; i=$(( i + 1 ))
    TP="$TMP/tp_$i"; mkdir -p "$TP"; LP="$TMP/p_$i.jsonl"
    if [ "$kind" = grep ]; then J="$( grepjson "cede$i" "$arg" )"; else J="$( bashjson "cede$i" "$arg" )"; fi
    O="$( sweep_run "$LP" "$TP" "$J" )"
    got="$( meterrowget "$LP" 1 nudge )"; gc="$( meterrowget "$LP" 1 class )"
    [ -z "$O" ] || CEDEBAD="$CEDEBAD [$lbl emitted output]"
    [ "$got" = "$want" ] || CEDEBAD="$CEDEBAD [$lbl -> nudge=$got, want $want]"
    [ "$gc" = "grep" ] || CEDEBAD="$CEDEBAD [$lbl -> class=$gc, want grep]"
done
[ -z "$CEDEBAD" ] \
    && ok "P1-P7 cede: single literals log nudge=none, OR-chains and multi -e log nudge=retired, all silent" \
    || no "P1-P7 cede:$CEDEBAD"

# P8: the CHAIN case still needs no new code — a literal grep (ineligible) then a Read (eligible),
# same session, independent tiers. Read from the rows, since neither call speaks.
TP8="$TMP/tp8"; mkdir -p "$TP8"; LP8="$TMP/p8.jsonl"
OUTP8G="$( sweep_run "$LP8" "$TP8" "$( grepjson cedechain needle )" )"
OUTP8R="$( sweep_run "$LP8" "$TP8" "$( readjson cedechain src/foo.cpp )" )"
[ -z "$OUTP8G" ] && [ -z "$OUTP8R" ] \
    && [ "$( meterrowget "$LP8" 1 nudge )" = "none" ] && [ "$( meterrowget "$LP8" 2 nudge )" = "retired" ] \
    && ok "P8 cede: grep(ineligible) then read(eligible) — the read tier is reached independently" \
    || no "P8 cede: chain gave rows [$( meterrowget "$LP8" 1 nudge )]/[$( meterrowget "$LP8" 2 nudge )] out=[$OUTP8G][$OUTP8R]"

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
    # §RETIRED (2026-09-02): the retirement is only honest if the schema doc carries the new `nudge`
    # vocabulary AND says what the A/B found. A code change that silently outruns its own schema doc is
    # the exact failure the v1/v2 boundary note exists to prevent.
    C3RMISS=""
    for needle in 'retired-sweep' 'What the A/B found'; do
        grep -Fq "$needle" "$SCHEMADOC" || C3RMISS="$C3RMISS $needle"
    done
    [ -z "$C3RMISS" ] && ok "C3r docs: SUBSTITUTION_METER.md carries the retirement and the new nudge vocabulary" \
        || no "C3r docs: SUBSTITUTION_METER.md is missing:$C3RMISS"
fi
EVALSDOC="$ROOT/docs/EVALS.md"
if [ -f "$EVALSDOC" ]; then
    grep -Fq 'Nudge sweep-escalation efficacy' "$EVALSDOC" && grep -Fq 'post_sweep' "$EVALSDOC" \
        && ok "C3b docs: EVALS.md carries the pre-registered efficacy readout for the escalation" \
        || no "C3b docs: EVALS.md has no sweep-escalation registration — the verdict is unregistered"
    # The registration promised a verdict. A registered band with no resolution is a band nobody paid.
    grep -Fq 'PreToolUse nudge A/B' "$EVALSDOC" \
        && ok "C3c docs: EVALS.md carries the A/B READOUT that resolved that registration" \
        || no "C3c docs: EVALS.md has a registered band with no readout beside it"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# (12b) THE CLASSIFIER-GAP ROUND, and the ARM CONTRACT  (Track B §S2c, 2026-08-12)
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
# A1-A4 are a different bug in the same file, reproduced live by the E1 lane: THE DORMANT A/B TOGGLE
# WAS BROKEN IN EXACTLY THE CONFIGURATION THAT WILL USE IT. `meter_init` resolved the arm AFTER the
# "no log destination" early return, so a control-arm run with no named log kept the `treatment`
# default and was nudged anyway; and the SessionStart primer — ~1.6 KB, the largest thing this hook
# ever says — never consulted the arm at all. Either one would have made the first real A/B measure
# the nudge it was supposed to be withholding. A control arm that silently does not control is worse
# than none, because the data it produces looks valid.
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
for pair in 'echo "=== docs ==="; grep -n E1 docs/COMMANDS.md@@grep' \
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

# ── A1-A4: THE ARM CONTRACT. The toggle must work in the configuration that will use it. ────────────
# A1 asserts the ONE configuration a real control arm runs in — the arm named, the fixture guard on,
# no destination named — because that is exactly the configuration in which meter_init once silently
# did the opposite of the documented thing.
#
# §RETIRED (2026-09-02): A2's positive control moved. The PreToolUse path is now silent in BOTH arms,
# so "treatment still speaks" cannot be the thing that proves the arm was consulted; A3/A4 carry that
# job alone, on the SessionStart primer, which is the only arm-differentiated behaviour left. The
# OR-chain patterns stay, because A1/A2 still need a base-tier-ELIGIBLE call for their rows to mean
# anything — see the note at case (1).
TA1="$TMP/ta1"; mkdir -p "$TA1"
ARMHOME="$TMP/armhome"; mkdir -p "$ARMHOME"
OUTA1="$( printf '%s' "$( grepjson armcase 'needle|other' )" \
    | env -u RIPWIRE_METER_LOG -u RIPWIRE_HOME HOME="$ARMHOME" RIPWIRE_METER_FIXTURE=1 \
        RIPWIRE_METER_ARM=control PATH="$WITH_RIPWIRE" TMPDIR="$TA1" bash "$HOOK" )"; RCA1=$?
[ "$RCA1" -eq 0 ] && [ -z "$OUTA1" ] \
    && ok "A1 arm: the control arm is silent even with no log destination (the arm resolves first)" \
    || no "A1 arm: control arm emitted ${#OUTA1} byte(s), exit=$RCA1 — meter_init resolved the arm too late"

TA2="$TMP/ta2"; mkdir -p "$TA2"; LA2="$TMP/a2.jsonl"
OUTA2="$( sweep_run "$LA2" "$TA2" "$( grepjson armlog 'needle|other' )" RIPWIRE_METER_ARM=control )"
TA2B="$TMP/ta2b"; mkdir -p "$TA2B"; LA2B="$TMP/a2b.jsonl"
OUTA2B="$( sweep_run "$LA2B" "$TA2B" "$( grepjson armlogt 'needle|other' )" )"
[ -z "$OUTA2" ] && [ "$( meterrowget "$LA2" 1 arm )" = "control" ] && [ -z "$OUTA2B" ] \
    && [ "$( meterrowget "$LA2B" 1 arm )" = "treatment" ] \
    && ok "A2 arm: with a log named, both arms count, record and stay silent on the PreToolUse path" \
    || no "A2 arm: control out=[${OUTA2:+set}] arm=[$( meterrowget "$LA2" 1 arm )]; treatment out=[${OUTA2B:+set}] arm=[$( meterrowget "$LA2B" 1 arm )]"

# A3: the SessionStart primer is a nudge — by a wide margin the largest one — so the control arm does
# not get it. A control arm silent all session that is then handed the whole manual at startup would
# have made the first A/B measure the primer and call it the nudge.
#
# Both arms run against a stub whose `wrap` DOES emit the paste fence. The section's ordinary stub
# prints one word, so the primer would be empty and A3 would pass on a hook that never consulted the
# arm at all — the silence has to be attributable to the arm and to nothing else, which is what A4
# then proves from the other side.
WRAPBIN="$TMP/wrapbin"; mkdir -p "$WRAPBIN"
{
    printf '#!/bin/sh\n'
    printf 'echo "# --- paste into CLAUDE.md ---"\n'
    printf 'echo "ripwire: map before you read."\n'
    printf 'echo "# --- end paste ---"\n'
} >"$WRAPBIN/ripwire"
chmod +x "$WRAPBIN/ripwire"
WRAP_PATH="$WRAPBIN:$PATH"
TA3="$TMP/ta3"; mkdir -p "$TA3"; LA3="$TMP/a3.jsonl"
OUTA3="$( printf '%s' '{"session_id":"armss","cwd":"'"$REPO"'","source":"startup"}' \
    | env HOME="$METERHOME" RIPWIRE_METER_LOG="$LA3" RIPWIRE_METER_FIXTURE=1 RIPWIRE_METER_ARM=control \
        PATH="$WRAP_PATH" TMPDIR="$TA3" bash "$HOOK" --session-start )"; RCA3=$?
[ "$RCA3" -eq 0 ] && [ -z "$OUTA3" ] \
    && ok "A3 arm: the SessionStart primer is suppressed in the control arm" \
    || no "A3 arm: control-arm primer emitted ${#OUTA3} byte(s), exit=$RCA3"
[ "$( meterrowget "$LA3" 1 class )" = "session-start" ] && [ "$( meterrowget "$LA3" 1 arm )" = "control" ] \
    && ok "A3b arm: the control arm is still COUNTED — the session boundary row is written anyway" \
    || no "A3b arm: control session-start row = [$( meterrowget "$LA3" 1 class )/$( meterrowget "$LA3" 1 arm )]"

# A4: the positive control for A3. Suppressing the primer everywhere would pass A3 for the wrong reason.
TA4="$TMP/ta4"; mkdir -p "$TA4"; LA4="$TMP/a4.jsonl"
OUTA4="$( printf '%s' '{"session_id":"armsst","cwd":"'"$REPO"'","source":"startup"}' \
    | env HOME="$METERHOME" RIPWIRE_METER_LOG="$LA4" RIPWIRE_METER_FIXTURE=1 \
        PATH="$WRAP_PATH" TMPDIR="$TA4" bash "$HOOK" --session-start )"
[ -n "$OUTA4" ] && printf '%s' "$OUTA4" | is_valid_json \
    && ok "A4 arm: the treatment arm still gets the SessionStart primer (A3's positive control)" \
    || no "A4 arm: treatment primer was empty or invalid: [$OUTA4]"

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
# (12d) THE POLL CLASSES AND THE WORKTREE TAG — three instrument defects found while reading the A/B
#
# All three were found by MINING the live log for the 2026-09-02 readout, not by inspection, and each
# one biases a number the readout published:
#
#   PB  ~14% of the window's `grep`-class rows are POLLS, not searches. `grep -c Building <buildlog>`
#       and `grep -q PARGATES_EXIT <taskfile>` are progress polls on a running job; `ps aux | grep
#       "[t]est"` is a liveness check. None of them retrieves content, so none of them can ever be
#       substituted by a ranked map — counting them as native retrieval inflates the denominator with
#       calls the tool is not competing for. They were also NOT evenly distributed across arms, which
#       made the artifact directional. They get `build-poll` / `process-poll`, family `meta`, excluded
#       from the rate exactly like `gate-run`.
#
#   TAG `tag` was the basename of the repo DIRECTORY, so every linked worktree of one repository
#       reported as its own repo (a dozen `.claude/worktrees/<name>` checkouts of ripwire showed up as
#       a dozen "repos"). The per-repo cut is the one that controls for composition, so a per-repo cut
#       that splits one repo into twelve is the cut most damaged by it. `tag` now comes from the
#       repo's git COMMON dir, which a linked worktree shares with its main worktree.
#
# The negative controls are the point of this section: a rule that swallows an ordinary recursive grep
# (PB5), or a tag derivation that folds two genuinely different repos together (TAG2), is worse than
# the defect it fixes.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

PBBAD=""
i=0
for triple in "grep -c Building /tmp/build.log^build-poll^meta" \
              "grep -c \\\"===\\\" /tmp/gate.log^build-poll^meta" \
              "grep -q PARGATES_EXIT /tmp/task.outp^build-poll^meta" \
              "rg -q needle src/^build-poll^meta" \
              "ps aux | grep \\\"[t]est_thing\\\"^process-poll^meta" \
              "pgrep -f ripwire^process-poll^meta" \
              "grep -rn needle .^grep^native" \
              "grep -C 3 needle file.txt^grep^native" \
              "rg needle src/^grep^native"; do
    c="${triple%%^*}"; rest="${triple#*^}"; wc_="${rest%^*}"; wf="${rest#*^}"; i=$(( i + 1 ))
    TPB="$TMP/tpb_$i"; mkdir -p "$TPB"; LPB="$TMP/pb_$i.jsonl"
    sweep_run "$LPB" "$TPB" "$( bashjson "pollcase_$i" "$c" )" >/dev/null 2>&1
    gc="$( meterrowget "$LPB" 1 class )"; gf="$( meterrowget "$LPB" 1 family )"
    [ "$gc" = "$wc_" ] && [ "$gf" = "$wf" ] || PBBAD="$PBBAD [$c -> $gc/$gf, want $wc_/$wf]"
done
[ -z "$PBBAD" ] \
    && ok "PB1-PB5 classifier: count/quiet greps are build-poll, ps/pgrep are process-poll, real searches unchanged" \
    || no "PB1-PB5 classifier: misclassified:$PBBAD"

# PB6: a poll is not a sweep. Five `grep -c` polls in one session must never reach an escalation
# moment — the class they carry is not in the sweep set, which is the same reason a build never was.
TPB6="$TMP/tpb6"; mkdir -p "$TPB6"; LPB6="$TMP/pb6.jsonl"
PB6BAD=""
for n in 1 2 3 4 5; do
    O="$( sweep_run "$LPB6" "$TPB6" "$( bashjson pollsweep 'grep -c Building /tmp/build.log' )" )"
    [ -z "$O" ] || PB6BAD="$PB6BAD [call$n emitted]"
    case "$( meterrowget "$LPB6" "$n" nudge )" in
        none) ;;
        *) PB6BAD="$PB6BAD [call$n nudge=$( meterrowget "$LPB6" "$n" nudge )]" ;;
    esac
done
[ -z "$PB6BAD" ] && [ "$( meterrows "$LPB6" )" = "5" ] \
    && ok "PB6 classifier: five build polls are counted, never nudge-eligible, never an escalation moment" \
    || no "PB6 classifier:$PB6BAD (rows=$( meterrows "$LPB6" ))"

# ── TAG1-TAG3: `tag` folds a linked worktree into its main worktree, and nothing else ──────────────
# A real `git worktree add`, not a simulation: the whole defect lives in what git reports for a
# checkout whose .git is a FILE pointing at the main repo's common dir.
WTMAIN="$TMP/wtmain"; mkdir -p "$WTMAIN"
git -C "$WTMAIN" init -q
git -C "$WTMAIN" config user.email "dev@x.com"; git -C "$WTMAIN" config user.name "Dev"
printf 'x\n' >"$WTMAIN/f.txt"; git -C "$WTMAIN" add f.txt >/dev/null 2>&1
git -C "$WTMAIN" commit -q -m init >/dev/null 2>&1
WTLINK="$TMP/vibrant-euler-dd516f"
if git -C "$WTMAIN" worktree add -q -b wtbranch "$WTLINK" >/dev/null 2>&1; then
    TW1="$TMP/ttag1"; mkdir -p "$TW1"; LW1="$TMP/tag1.jsonl"
    sweep_run "$LW1" "$TW1" '{"session_id":"wtcase","cwd":"'"$WTLINK"'","tool_name":"Grep","tool_input":{"pattern":"needle"}}' >/dev/null 2>&1
    GOTTAG="$( meterrowget "$LW1" 1 tag )"
    [ "$GOTTAG" = "wtmain" ] \
        && ok "TAG1 tag: a linked worktree reports its MAIN worktree's name (wtmain), not its own dir" \
        || no "TAG1 tag: linked worktree reported tag=[$GOTTAG], expected wtmain"
    # and `repo` still names the worktree the call actually happened in — folding the TAG must not
    # falsify the path, which is the field that says where the row came from.
    GOTREPO="$( meterrowget "$LW1" 1 repo )"
    case "$GOTREPO" in
        *vibrant-euler-dd516f) ok "TAG1b tag: repo= still names the worktree the call happened in" ;;
        *) no "TAG1b tag: repo=[$GOTREPO] — folding the tag must not falsify the path" ;;
    esac
else
    echo "  SKIP  TAG1 (git worktree add unavailable)"
fi
TW2="$TMP/ttag2"; mkdir -p "$TW2"; LW2="$TMP/tag2.jsonl"
sweep_run "$LW2" "$TW2" '{"session_id":"tagplain","cwd":"'"$WTMAIN"'","tool_name":"Grep","tool_input":{"pattern":"needle"}}' >/dev/null 2>&1
[ "$( meterrowget "$LW2" 1 tag )" = "wtmain" ] \
    && ok "TAG2 tag: an ordinary repo still reports its own basename (the negative control)" \
    || no "TAG2 tag: plain repo reported tag=[$( meterrowget "$LW2" 1 tag )], expected wtmain"
TW2B="$TMP/ttag2b"; mkdir -p "$TW2B"; LW2B="$TMP/tag2b.jsonl"
sweep_run "$LW2B" "$TW2B" '{"session_id":"tagsub","cwd":"'"$REPO"'","tool_name":"Grep","tool_input":{"pattern":"needle"}}' >/dev/null 2>&1
[ "$( meterrowget "$LW2B" 1 tag )" = "repo" ] \
    && ok "TAG2b tag: two different repos still get two different tags (no over-folding)" \
    || no "TAG2b tag: second repo reported tag=[$( meterrowget "$LW2B" 1 tag )], expected repo"
TW3="$TMP/ttag3"; mkdir -p "$TW3"; LW3="$TMP/tag3.jsonl"
sweep_run "$LW3" "$TW3" '{"session_id":"tagnonrepo","cwd":"'"$NONREPO"'","tool_name":"Grep","tool_input":{"pattern":"needle"}}' >/dev/null 2>&1
[ "$( meterrowget "$LW3" 1 tag )" = "nonrepo" ] \
    && ok "TAG3 tag: outside a repo the tag still falls back to the directory basename" \
    || no "TAG3 tag: non-repo reported tag=[$( meterrowget "$LW3" 1 tag )], expected nonrepo"
# The SessionStart path derives the tag too, and derived it separately — a fix applied to one and not
# the other would split a session's own rows across two tags.
TW4="$TMP/ttag4"; mkdir -p "$TW4"; LW4="$TMP/tag4.jsonl"
if [ -d "$WTLINK" ]; then
    printf '%s' '{"session_id":"tagss","cwd":"'"$WTLINK"'","source":"startup"}' \
        | env HOME="$METERHOME" RIPWIRE_METER_LOG="$LW4" RIPWIRE_METER_FIXTURE=1 \
            PATH="$WITH_RIPWIRE" TMPDIR="$TW4" bash "$HOOK" --session-start >/dev/null 2>&1
    [ "$( meterrowget "$LW4" 1 tag )" = "wtmain" ] \
        && ok "TAG4 tag: the SessionStart row folds the worktree the same way the PreToolUse rows do" \
        || no "TAG4 tag: session-start row tag=[$( meterrowget "$LW4" 1 tag )], expected wtmain"
fi

# ── PB7: the schema doc carries the two new classes and the tag change as a schema note ───────────
if [ -f "$SCHEMADOC" ]; then
    PB7MISS=""
    for needle in 'build-poll' 'process-poll' 'git-common-dir'; do
        grep -Fq "$needle" "$SCHEMADOC" || PB7MISS="$PB7MISS $needle"
    done
    [ -z "$PB7MISS" ] && ok "PB7 docs: SUBSTITUTION_METER.md documents the poll classes and the tag derivation" \
        || no "PB7 docs: SUBSTITUTION_METER.md is missing:$PB7MISS"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# (14) LIVE SHAPE, MATCHER SEMANTICS, NATIVE-EDIT ROWS, ROW SCHEMA v3 AND THE EDIT BAND
#      (terminality round A, 2026-09-05, lane T)
#
# WHY THIS SECTION EXISTS. A live probe on 2026-09-05 (the installed hook shimmed with a stdin tee for
# two tool calls): a REAL `mcp__ripwire__whereis` call from a Claude Code desktop session produced NO
# PreToolUse payload at all under the installed matcher `Read|Glob|Grep|Bash|mcp__ripwire__` — the tee
# saw the Bash and Read calls around it and never the MCP call. The reason is the documented matcher
# contract (code.claude.com/docs/en/hooks, "Matcher patterns"): a matcher made ONLY of letters, digits,
# `_`, `-`, spaces, `,` and `|` is an EXACT-STRING LIST, so `mcp__ripwire__` was compared as a whole
# tool name and matched nothing; only a matcher containing any other character is evaluated as a
# JavaScript regular expression (unanchored, `RegExp.prototype.test`). Every MCP row was therefore
# invisible for as long as the meter has existed — 0 of 51,002 rows on the frozen 2026-09-05 snapshot —
# and the two arms that were supposed to guard it passed for the wrong reason: M12 feeds the hook a
# payload directly (never through the matcher) and M25 greps the matcher for a SUBSTRING.
#
# V1 models the documented contract exactly and evaluates the INSTALLED matcher against whole tool
# names. V2 feeds the real desktop payload shape (every extra key the live payload carries). V3 proves
# a settings.json written by the OLD installer is refreshed to the new matcher by a re-run of --hook.
# V4 pins the new `native-edit` class and the v3 row fields (`agent`, `surface`, `target`). V5 pins the
# target field on the CLI/MCP EDIT verbs. E1-E9 pin §5b of bench/substitution_report.py — the EDIT band
# registered in docs/EVALS.md ("Terminality round A") — on a synthetic fixture whose right answer is
# known by construction, including a MUTATION CONTROL that proves the policy-read column is live.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

# ── matcher_fires MATCHER NAME... — prints "NAME fires" / "NAME silent" per name, under the DOCUMENTED
#    Claude Code contract: exact-string list when the matcher holds only [A-Za-z0-9_ ,|-], else an
#    unanchored regex. `*`/empty match everything. ──
matcher_fires()
{
    python3 - "$@" <<'PY'
import re, sys
m = sys.argv[1]
names = sys.argv[2:]
if m in ("", "*"):
    fires = lambda n: True
elif re.fullmatch(r"[A-Za-z0-9_\- ,|]*", m):
    alts = [a.strip() for a in re.split(r"[|,]", m)]
    fires = lambda n: n in alts
else:
    rx = re.compile(m)
    fires = lambda n: rx.search(n) is not None
for n in names:
    print("%s %s" % (n, "fires" if fires(n) else "silent"))
PY
}

# ── V1: the INSTALLED Claude matcher fires on every tool the meter needs, and on nothing else ───────
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
    INSTMATCH="$( jq -r '(.hooks.PreToolUse // [])[] | select(.hooks[]?.command | test("ripwire-nudge")) | .matcher' "$SETTINGS" | head -n1 )"
    echo "-- installed Claude PreToolUse matcher: [$INSTMATCH] --"
    V1OUT="$( matcher_fires "$INSTMATCH" mcp__ripwire__whereis mcp__ripwire__replace_symbol_body Read Glob Grep Bash Edit Write MultiEdit NotebookEdit Task WebFetch TodoWrite )"
    echo "$V1OUT"
    V1BAD=""
    for n in mcp__ripwire__whereis mcp__ripwire__replace_symbol_body Read Glob Grep Bash Edit Write MultiEdit NotebookEdit; do
        printf '%s\n' "$V1OUT" | grep -qx "$n fires" || V1BAD="$V1BAD $n"
    done
    [ -z "$V1BAD" ] \
        && ok "V1 matcher: the installed matcher, evaluated as Claude Code evaluates it, fires on every metered tool (MCP verbs, Read/Glob/Grep/Bash, the four native edit tools)" \
        || no "V1 matcher: [$INSTMATCH] never fires for:$V1BAD (an exact-string list matches a whole tool name — a prefix matches nothing)"
    V1OVER=""
    for n in Task WebFetch TodoWrite; do
        printf '%s\n' "$V1OUT" | grep -qx "$n silent" || V1OVER="$V1OVER $n"
    done
    [ -z "$V1OVER" ] \
        && ok "V1b matcher: the installed matcher is silent on tools the meter has no rule for (no fork per Task/WebFetch/TodoWrite call)" \
        || no "V1b matcher: [$INSTMATCH] also fires on:$V1OVER — every one of those is a wasted fork per call"
    # The Codex installer writes its own matcher; same contract, same whole-name evaluation.
    CODEXMATCH="$( grep -E '^codexHookMatcher=' "$INSTALL" | head -n1 | sed -E 's/^codexHookMatcher="(.*)"$/\1/' )"
    V1COUT="$( matcher_fires "$CODEXMATCH" mcp__ripwire__whereis Read Glob Grep Bash Edit Write MultiEdit NotebookEdit )"
    V1CBAD=""
    for n in mcp__ripwire__whereis Read Glob Grep Bash Edit Write MultiEdit NotebookEdit; do
        printf '%s\n' "$V1COUT" | grep -qx "$n fires" || V1CBAD="$V1CBAD $n"
    done
    [ -z "$V1CBAD" ] \
        && ok "V1c matcher: the Codex matcher [$CODEXMATCH] fires on the same whole tool names" \
        || no "V1c matcher: the Codex matcher [$CODEXMATCH] never fires for:$V1CBAD"
fi

# ── V2: the LIVE payload shape — every key a real desktop session sends, not the four-key fixture ───
# livejson SESSION TOOL TOOL_INPUT_JSON — the shape captured from a Claude Code desktop session on
# 2026-09-05: session_id, transcript_path, cwd, scratchpad_dir, prompt_id, permission_mode, effort
# (an OBJECT), hook_event_name, tool_name, tool_input, tool_use_id.
livejson()
{
    printf '{"session_id":"%s","transcript_path":"/home/op/.claude/projects/-home-op-repo/%s.jsonl","cwd":"%s","scratchpad_dir":"/private/tmp/claude-501/-home-op-repo/%s/scratchpad","prompt_id":"prompt-%s","permission_mode":"auto","effort":{"level":"high"},"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s,"tool_use_id":"toolu_01%s"}' \
        "$1" "$1" "$REPO" "$1" "$1" "$2" "$3" "$1"
}
TV2="$TMP/tv2"; mkdir -p "$TV2"; LV2="$TMP/v2.jsonl"
OUTV2A="$( run_meter "$LV2" "$( livejson live1 Bash '{"command":"grep -rn needle src","description":"search"}' )" "$TV2" )"; RCV2A=$?
OUTV2B="$( run_meter "$LV2" "$( livejson live1 Read '{"file_path":"/x/repo/src/a.cpp","limit":80}' )" "$TV2" )"; RCV2B=$?
OUTV2C="$( run_meter "$LV2" "$( livejson live1 mcp__ripwire__whereis '{"path":"'"$REPO"'","symbol":"meter_log"}' )" "$TV2" )"; RCV2C=$?
OUTV2D="$( run_meter "$LV2" "$( livejson live1 Edit '{"file_path":"/x/repo/src/a.cpp","old_string":"a","new_string":"b"}' )" "$TV2" )"; RCV2D=$?
echo "-- live-shape rows --"; [ -f "$LV2" ] && cat "$LV2"
[ "$RCV2A" -eq 0 ] && [ "$RCV2B" -eq 0 ] && [ "$RCV2C" -eq 0 ] && [ "$RCV2D" -eq 0 ] \
    && [ -z "$OUTV2A$OUTV2B$OUTV2C$OUTV2D" ] \
    && ok "V2 live-shape: Bash, Read, an MCP verb and Edit under the real payload shape all exit 0 and say nothing" \
    || no "V2 live-shape: exits $RCV2A/$RCV2B/$RCV2C/$RCV2D, stdout=[$OUTV2A$OUTV2B$OUTV2C$OUTV2D]"
[ "$( meterrowget "$LV2" 1 class )" = "grep" ] && [ "$( meterrowget "$LV2" 2 class )" = "read" ] \
    && ok "V2a live-shape: the Bash grep and the Read row classify exactly as under the four-key fixture" \
    || no "V2a live-shape: classes [$( meterrowget "$LV2" 1 class )] [$( meterrowget "$LV2" 2 class )], expected grep, read"
[ "$( meterrowget "$LV2" 3 class )" = "ripwire-mcp" ] && [ "$( meterrowget "$LV2" 3 family )" = "ripwire" ] \
    && [ "$( meterrowget "$LV2" 3 tool )" = "mcp__ripwire__whereis" ] \
    && ok "V2b live-shape: mcp__ripwire__whereis writes a ripwire-mcp/ripwire row (the numerator's MCP half exists)" \
    || no "V2b live-shape: MCP row = [$( meterrowget "$LV2" 3 class )/$( meterrowget "$LV2" 3 family )] tool=[$( meterrowget "$LV2" 3 tool )]"
[ "$( meterrowget "$LV2" 3 detail )" = "meter_log" ] && [ "$( meterrowget "$LV2" 3 surface )" = "mcp" ] \
    && ok "V2c live-shape: the MCP row's detail is the symbol argument and its surface is mcp" \
    || no "V2c live-shape: MCP row detail=[$( meterrowget "$LV2" 3 detail )] surface=[$( meterrowget "$LV2" 3 surface )]"
[ "$( meterrowget "$LV2" 4 class )" = "native-edit" ] && [ "$( meterrowget "$LV2" 4 family )" = "edit" ] \
    && [ "$( meterrowget "$LV2" 4 target )" = "/x/repo/src/a.cpp" ] && [ "$( meterrowget "$LV2" 4 nudged )" = "0" ] \
    && [ "$( meterrowget "$LV2" 4 nudge )" = "none" ] \
    && ok "V2d live-shape: Edit writes a native-edit/edit row carrying target=file_path, never nudged" \
    || no "V2d live-shape: Edit row = [$( meterrowget "$LV2" 4 class )/$( meterrowget "$LV2" 4 family )] target=[$( meterrowget "$LV2" 4 target )] nudged=[$( meterrowget "$LV2" 4 nudged )] nudge=[$( meterrowget "$LV2" 4 nudge )]"
V2E_BAD=""
for i in 1 2 3 4; do
    [ "$( meterrowget "$LV2" "$i" v )" = "3" ] || V2E_BAD="$V2E_BAD v[$i]=$( meterrowget "$LV2" "$i" v )"
    [ "$( meterrowget "$LV2" "$i" agent )" = "claude" ] || V2E_BAD="$V2E_BAD agent[$i]=$( meterrowget "$LV2" "$i" agent )"
    [ "$( meterrowget "$LV2" "$i" session )" = "live1" ] || V2E_BAD="$V2E_BAD session[$i]=$( meterrowget "$LV2" "$i" session )"
done
[ "$( meterrowget "$LV2" 1 surface )" = "cli" ] && [ "$( meterrowget "$LV2" 2 surface )" = "native" ] \
    && [ "$( meterrowget "$LV2" 4 surface )" = "native" ] || V2E_BAD="$V2E_BAD surface=[$( meterrowget "$LV2" 1 surface )/$( meterrowget "$LV2" 2 surface )/$( meterrowget "$LV2" 4 surface )]"
[ -z "$V2E_BAD" ] \
    && ok "V2e schema v3: every row carries v=3, agent=claude, the live session id, and surface cli/native/mcp" \
    || no "V2e schema v3:$V2E_BAD"
# The other three native edit tools, and NotebookEdit's differently-named path key.
LV2F="$TMP/v2f.jsonl"; TV2F="$TMP/tv2f"; mkdir -p "$TV2F"
run_meter "$LV2F" "$( livejson live2 Write '{"file_path":"/x/repo/docs/new.md","content":"hi"}' )" "$TV2F" >/dev/null 2>&1
run_meter "$LV2F" "$( livejson live2 MultiEdit '{"file_path":"/x/repo/src/b.cpp","edits":[{"old_string":"a","new_string":"b"}]}' )" "$TV2F" >/dev/null 2>&1
run_meter "$LV2F" "$( livejson live2 NotebookEdit '{"notebook_path":"/x/repo/nb.ipynb","new_source":"x"}' )" "$TV2F" >/dev/null 2>&1
[ "$( meterrowget "$LV2F" 1 target )" = "/x/repo/docs/new.md" ] && [ "$( meterrowget "$LV2F" 2 target )" = "/x/repo/src/b.cpp" ] \
    && [ "$( meterrowget "$LV2F" 3 target )" = "/x/repo/nb.ipynb" ] \
    && [ "$( meterrowget "$LV2F" 1 class )$( meterrowget "$LV2F" 2 class )$( meterrowget "$LV2F" 3 class )" = "native-editnative-editnative-edit" ] \
    && ok "V2f native-edit: Write, MultiEdit and NotebookEdit (notebook_path) each write a native-edit row naming the target" \
    || no "V2f native-edit: targets [$( meterrowget "$LV2F" 1 target )] [$( meterrowget "$LV2F" 2 target )] [$( meterrowget "$LV2F" 3 target )]"
# The agent field is the runner's, not a constant: the Codex wrapper names itself through the env.
LV2G="$TMP/v2g.jsonl"; TV2G="$TMP/tv2g"; mkdir -p "$TV2G"
run_meter "$LV2G" "$( livejson live3 Read '{"file_path":"/x/repo/src/a.cpp"}' )" "$TV2G" RIPWIRE_METER_AGENT=codex >/dev/null 2>&1
[ "$( meterrowget "$LV2G" 1 agent )" = "codex" ] \
    && ok "V2g schema v3: RIPWIRE_METER_AGENT names the runner (the Codex wrapper's contract)" \
    || no "V2g schema v3: agent=[$( meterrowget "$LV2G" 1 agent )] under RIPWIRE_METER_AGENT=codex"
grep -q 'RIPWIRE_METER_AGENT' "$ROOT/hooks/ripwire-codex-nudge.sh" \
    && ok "V2h schema v3: hooks/ripwire-codex-nudge.sh sets RIPWIRE_METER_AGENT so Codex rows are attributed" \
    || no "V2h schema v3: hooks/ripwire-codex-nudge.sh never sets RIPWIRE_METER_AGENT — Codex rows would read as claude"

# ── V3: a settings.json carrying the OLD (exact-list) matcher is REFRESHED by a re-run of --hook ────
STALE_HOME="$TMP/stalehome"; mkdir -p "$STALE_HOME/.claude"
printf '{"hooks":{"PreToolUse":[{"matcher":"Read|Glob|Grep|Bash|mcp__ripwire__","hooks":[{"type":"command","command":"%s"}]}],"SessionStart":[{"matcher":"startup|resume|clear","hooks":[{"type":"command","command":"%s --session-start"}]}]}}\n' \
    "$HOOK" "$HOOK" >"$STALE_HOME/.claude/settings.json"
STALEOUT="$( HOME="$STALE_HOME" bash "$INSTALL" --hook 2>&1 )"; STALERC=$?
STALEMATCH="$( jq -r '(.hooks.PreToolUse // [])[] | select(.hooks[]?.command | test("ripwire-nudge")) | .matcher' "$STALE_HOME/.claude/settings.json" 2>/dev/null | head -n1 )"
echo "-- --hook over a stale matcher: [$STALEMATCH] --"; echo "$STALEOUT" | head -n 3
# I2 (V1, wave-1 verifier 2026-09-05): three &&-chained conditions used to share ONE failure message
# that reported only the first two, so the third failing printed two IDENTICAL matcher strings beside a
# FAIL and named no reason:
#     FAIL  V3 refresh: exit=0 matcher after re-run=[Read|Glob|Grep|Bash|mcp__ripwire__] expected [Read|Glob|Grep|Bash|mcp__ripwire__]
# Each condition now names itself and prints what it found against what it expected -- the same class F2
# just fixed for pargates, applied inside the arm.
V3FIRES="$( matcher_fires "$STALEMATCH" mcp__ripwire__whereis )"
if [ "$STALERC" -ne 0 ]; then
    no "V3 refresh: install.sh --hook exited $STALERC (expected 0) over a stale matcher — last line: $( printf '%s' "$STALEOUT" | tail -n 1 )"
elif [ "$STALEMATCH" != "$INSTMATCH" ]; then
    no "V3 refresh: --hook did NOT rewrite the stale entry — matcher after re-run=[$STALEMATCH], expected [$INSTMATCH]"
elif [ "$V3FIRES" != "mcp__ripwire__whereis fires" ]; then
    no "V3 refresh: the matcher was rewritten to [$STALEMATCH] but it does not MATCH a real MCP tool name — matcher_fires said [$V3FIRES], expected [mcp__ripwire__whereis fires] (a matcher made only of [A-Za-z0-9_ ,|-] is an exact-name list, so a bare prefix matches nothing)"
else
    ok "V3 refresh: re-running --hook rewrites the 2026-09-04 exact-list matcher to the current one (an operator who re-runs --hook is repaired)"
fi
STALECOUNT="$( jq '[(.hooks.PreToolUse // [])[] | select(.hooks[]?.command | test("ripwire-nudge"))] | length' "$STALE_HOME/.claude/settings.json" 2>/dev/null )"
[ "$STALECOUNT" = "1" ] \
    && ok "V3b refresh: the refresh edits the entry in place (still exactly one PreToolUse entry)" \
    || no "V3b refresh: $STALECOUNT PreToolUse entries after the refresh"

# ── V5: the TARGET field on the EDIT verbs — CLI (from the command line) and MCP (from tool_input) ──
LV5="$TMP/v5.jsonl"; TV5="$TMP/tv5"; mkdir -p "$TV5"
run_meter "$LV5" "$( bashjson v5a './build/ripwire . --replace-symbol-body=foo --edit-target-file=src/a.cpp --edit-payload=-' )" "$TV5" >/dev/null 2>&1
run_meter "$LV5" "$( bashjson v5a './build/ripwire . --edit-plan=plan.json --apply' )" "$TV5" >/dev/null 2>&1
run_meter "$LV5" "$( bashjson v5a 'ripwire . --insert-after-symbol=bar --edit-target-file=\"src/b b.cpp\" --edit-payload=p.txt --no-post-check' )" "$TV5" >/dev/null 2>&1
run_meter "$LV5" "$( livejson v5a mcp__ripwire__replace_symbol_body '{"path":"'"$REPO"'","symbol":"foo","file":"src/a.cpp","new_body":"int foo(){}","post_check":false}' )" "$TV5" >/dev/null 2>&1
run_meter "$LV5" "$( livejson v5a mcp__ripwire__insert_before_symbol '{"path":"'"$REPO"'","symbol":"bar","text":"// x"}' )" "$TV5" >/dev/null 2>&1
echo "-- edit-target rows --"; [ -f "$LV5" ] && cat "$LV5"
[ "$( meterrowget "$LV5" 1 class )" = "ripwire-cli" ] && [ "$( meterrowget "$LV5" 1 target )" = "src/a.cpp" ] \
    && ok "V5a target: a CLI edit verb records --edit-target-file= as the row's target" \
    || no "V5a target: class=[$( meterrowget "$LV5" 1 class )] target=[$( meterrowget "$LV5" 1 target )]"
[ "$( meterrowget "$LV5" 2 class )" = "ripwire-cli" ] && [ "$( meterrowget "$LV5" 2 target )" = "" ] \
    && ok "V5b target: a CLI edit with no --edit-target-file= records an EMPTY target (the hook cannot know the file a bare name resolves to)" \
    || no "V5b target: class=[$( meterrowget "$LV5" 2 class )] target=[$( meterrowget "$LV5" 2 target )] expected empty"
[ "$( meterrowget "$LV5" 3 target )" = "src/b b.cpp" ] \
    && ok "V5c target: a quoted --edit-target-file= value is recorded unquoted, spaces kept" \
    || no "V5c target: target=[$( meterrowget "$LV5" 3 target )] expected [src/b b.cpp]"
[ "$( meterrowget "$LV5" 4 class )" = "ripwire-mcp" ] && [ "$( meterrowget "$LV5" 4 target )" = "src/a.cpp" ] \
    && [ "$( meterrowget "$LV5" 4 detail )" = "foo post_check=0" ] \
    && ok "V5d target: an MCP edit twin records file= as target, symbol as detail, and a skipped post-check as ' post_check=0'" \
    || no "V5d target: class=[$( meterrowget "$LV5" 4 class )] target=[$( meterrowget "$LV5" 4 target )] detail=[$( meterrowget "$LV5" 4 detail )]"
[ "$( meterrowget "$LV5" 5 target )" = "" ] && [ "$( meterrowget "$LV5" 5 detail )" = "bar" ] \
    && ok "V5e target: an MCP edit twin without file= records an empty target and no post_check suffix" \
    || no "V5e target: target=[$( meterrowget "$LV5" 5 target )] detail=[$( meterrowget "$LV5" 5 detail )]"

# ── E1-E9: §5b, terminality by EDIT verb, pinned on a SYNTHETIC v3 fixture ──────────────────────────
#
# The band's three columns, from docs/EVALS.md ("Terminality round A", EDIT band): (a) policy-read — a
# Read/grep of the edit's TARGET FILE, reported and never counted; (b) sweep — a Read/grep of any OTHER
# file, or a native edit of the SAME target, in the window; (c) redundant-check — an --edit-check /
# edit_check on the same symbol right after an edit whose receipt carried the folded post-check.
# TERMINAL = neither (b) nor (c). Printed per agent and per surface. An edit row that recorded no
# target and was followed by a read cannot be told (a) from (b): it is counted under `unattrib`,
# excluded from terminal%, never folded either way.
#
# The fixture, one session per case so each row of the table is traceable to one line here:
#   e-a  CLI replace, Read of the TARGET, build                -> TERMINAL, policy-read
#   e-b  CLI replace, Read of ANOTHER file                     -> sweep
#   e-c  CLI replace, build, --edit-check on the SAME symbol   -> redundant-check
#   e-d  CLI replace --no-post-check, --edit-check same symbol -> TERMINAL (no folded check to distrust)
#   e-e  CLI insert-after, native Edit of the SAME target      -> sweep
#   e-f  CLI --edit-plan (no target), Read of some file        -> unattrib
#   e-g  CLI --safe-delete, build                              -> TERMINAL
#   e-h  MCP replace (file=src/a.cpp), Read of the target      -> TERMINAL, policy-read
#   e-i  MCP replace, MCP edit_check same symbol               -> redundant-check
#   e-j  MCP insert-before, Grep tool (pattern names no file)  -> sweep
#   e-k  codex CLI replace, build                              -> TERMINAL
#   e-l  codex CLI replace, Read of another file               -> sweep
#   e-m  agent="" CLI replace (target src/m.cpp), build        -> TERMINAL, in its OWN (unknown) bucket
#   e-n  agent="" CLI replace (no target), Read of some file   -> unattrib, same bucket
# e-m/e-n are V1 I3+I4: a v3 row that CARRIES `agent` and leaves it EMPTY is a writer that failed to
# identify itself, and folding it into claude files another runner's rows under Claude Code with no
# trace (bench/substitution_report.py's row_agent used `row.get("agent") or "claude"`, which cannot
# tell an ABSENT v2 field from an EMPTY v3 one). Together they also make one bucket where n=2 and
# decidable=1, which is the I4 case: the small-n NOTE and the column headed `n` must not print two
# different quantities under the same letter.
EDITLOG="$TMP/editband.jsonl"
# v3 rows through the same writer as the FIND fixture (termrow's nine-argument form), into their own log.
editrow() { TERMLOG="$EDITLOG" termrow "$@"; }
ecli()   { editrow "$1" "$2" Bash ripwire-cli ripwire "$3" "${4:-claude}" cli "${5:-}"; }
emcp()   { editrow "$1" "$2" "mcp__ripwire__$3" ripwire-mcp ripwire "$4" claude mcp "${5:-}"; }
eread()  { editrow "$1" "$2" Read read native "$3" "${4:-claude}" native ''; }
ebuild() { editrow "$1" "$2" Bash build other 'cmake --build build -j' "${3:-claude}" cli ''; }
: >"$EDITLOG"
ecli   1 e-a './build/ripwire . --replace-symbol-body=foo --edit-target-file=src/a.cpp --edit-payload=-' claude src/a.cpp
eread  2 e-a '/x/repo/src/a.cpp'
ebuild 3 e-a
ecli   1 e-b './build/ripwire . --replace-symbol-body=bar --edit-target-file=src/b.cpp --edit-payload=-' claude src/b.cpp
eread  2 e-b '/x/repo/src/other.cpp'
ecli   1 e-c './build/ripwire . --replace-symbol-body=baz --edit-target-file=src/c.cpp --edit-payload=-' claude src/c.cpp
ebuild 2 e-c
ecli   3 e-c './build/ripwire . --edit-check=baz'
ecli   1 e-d './build/ripwire . --replace-symbol-body=qux --edit-target-file=src/d.cpp --edit-payload=- --no-post-check' claude src/d.cpp
ecli   2 e-d './build/ripwire . --edit-check=src/d.cpp:qux'
ecli   1 e-e './build/ripwire . --insert-after-symbol=foo --edit-target-file=src/a.cpp --edit-payload=-' claude src/a.cpp
editrow 2 e-e Edit native-edit edit '/x/repo/src/a.cpp' claude native '/x/repo/src/a.cpp'
ecli   1 e-f './build/ripwire . --edit-plan=plan.json --apply' claude ''
eread  2 e-f '/x/repo/src/z.cpp'
ecli   1 e-g './build/ripwire . --safe-delete=dead' claude ''
ebuild 2 e-g
emcp   1 e-h replace_symbol_body 'foo' src/a.cpp
eread  2 e-h '/x/repo/src/a.cpp'
emcp   1 e-i replace_symbol_body 'bar' src/b.cpp
emcp   2 e-i edit_check 'bar'
emcp   1 e-j insert_before_symbol 'foo' src/a.cpp
editrow 2 e-j Grep grep native 'needle' claude native ''
ecli   1 e-k 'ripwire . --replace-symbol-body=foo --edit-target-file=src/a.cpp --edit-payload=-' codex src/a.cpp
ebuild 2 e-k codex
ecli   1 e-l 'ripwire . --replace-symbol-body=bar --edit-target-file=src/b.cpp --edit-payload=-' codex src/b.cpp
eread  2 e-l '/x/repo/src/other.cpp' codex
# agent="" — passed through termrow's nine-argument form, which writes the field EMPTY rather than
# omitting it (ecli/eread/ebuild all default an empty argument back to claude, which is the fold itself)
editrow 1 e-m Bash ripwire-cli ripwire './build/ripwire . --replace-symbol-body=zed --edit-target-file=src/m.cpp --edit-payload=-' '' cli src/m.cpp
editrow 2 e-m Bash build other 'cmake --build build -j' '' cli ''
editrow 1 e-n Bash ripwire-cli ripwire './build/ripwire . --replace-symbol-body=zee --edit-payload=-' '' cli ''
editrow 2 e-n Read read native '/x/repo/src/q.cpp' '' native ''

if [ -f "$REPORT" ]; then
    python3 "$REPORT" "$EDITLOG" >"$TMP/edit.out" 2>&1; RCE=$?
    tr -s ' ' <"$TMP/edit.out" >"$TMP/edit.sq"
    echo "-- substitution_report.py §5b on the EDIT-band fixture --"
    sed -n '/^5b\./,$p' "$TMP/edit.out"
    edithas()
    {
        # edithas ARMID EXPECTED-SQUEEZED-LINE DESCRIPTION
        grep -Fqx " $2" "$TMP/edit.sq" \
            && ok "$1 edit-band: $3" \
            || no "$1 edit-band: expected the row [$2] — see $TMP/edit.out"
    }
    [ "$RCE" -eq 0 ] && grep -qi 'terminality by EDIT verb' "$TMP/edit.out" \
        && ok "E1 edit-band: the report prints a §5b terminality-by-EDIT-verb section" \
        || no "E1 edit-band: exit=$RCE and/or no §5b section — see $TMP/edit.out"
    # The three columns are DEFINED above the table, by name, so a percentage is never read without them.
    grep -q 'policy-read' "$TMP/edit.out" && grep -q 'redundant-check' "$TMP/edit.out" \
        && grep -qi 'never counted' "$TMP/edit.out" && grep -q 'unattrib' "$TMP/edit.out" \
        && ok "E2 edit-band: §5b defines policy-read (never counted), sweep, redundant-check and unattrib above the table" \
        || no "E2 edit-band: §5b does not define its columns — see $TMP/edit.out"
    grep -q 'agent=claude surface=cli' "$TMP/edit.out" && grep -q 'agent=claude surface=mcp' "$TMP/edit.out" \
        && grep -q 'agent=codex surface=cli' "$TMP/edit.out" \
        && ok "E3 edit-band: the table is printed per agent and per surface (claude/cli, claude/mcp, codex/cli)" \
        || no "E3 edit-band: missing an agent/surface block — see $TMP/edit.out"
    # claude/cli: --replace-symbol-body n=4 -> e-a terminal (policy-read), e-b sweep, e-c redundant, e-d terminal.
    edithas E4 "--replace-symbol-body 4 50.0% 1 1 1 0" \
        "claude/cli --replace-symbol-body: 4 calls, 2 terminal, policy-read 1 (reported, not counted), sweep 1, redundant-check 1"
    edithas E5 "--insert-after-symbol 1 0.0% 0 1 0 0" \
        "a native Edit of the SAME target inside the window is a sweep"
    edithas E6 "--edit-plan 1 n/a 0 0 0 1" \
        "an edit with no recorded target followed by a read is unattrib, excluded from terminal% (n/a), never folded"
    edithas E6b "--safe-delete 1 100.0% 0 0 0 0" "--safe-delete followed by a build is terminal"
    # claude/mcp: replace n=2 -> e-h terminal (policy-read), e-i redundant; insert-before -> e-j sweep.
    edithas E7 "mcp:replace_symbol_body 2 50.0% 1 0 1 0" \
        "claude/mcp replace_symbol_body: a Read of file= is policy-read; an edit_check on the same symbol is redundant"
    edithas E7b "mcp:insert_before_symbol 1 0.0% 0 1 0 0" "a Grep-tool call (pattern only, names no file) is a sweep"
    # codex/cli: n=2 -> e-k terminal, e-l sweep.
    edithas E8 "--replace-symbol-body 2 50.0% 0 1 0 0" "codex/cli --replace-symbol-body: 2 calls, 1 terminal, 1 sweep"
    # E10 (V1 I3): an EMPTY agent on a v3 row is its OWN bucket, never folded into claude. Two proofs,
    # because either alone can pass for the wrong reason: the (unknown) block exists, AND claude/cli's
    # --replace-symbol-body is still n=4 (a fold would have made it 6).
    if grep -q 'agent=(unknown) surface=cli' "$TMP/edit.out"; then
        edithas E10 "--replace-symbol-body 2 100.0% 0 0 0 1" \
            "an EMPTY agent= on a v3 row gets its own (unknown) bucket (n=2: e-m terminal, e-n unattrib)"
    else
        no "E10 edit-band: no 'agent=(unknown) surface=cli' block — a v3 row with agent=\"\" was folded into another runner's bucket; see $TMP/edit.out"
    fi
    grep -Fqx " --replace-symbol-body 4 50.0% 1 1 1 0" "$TMP/edit.sq" \
        && ok "E10b edit-band: claude/cli --replace-symbol-body is still n=4 — the two agent=\"\" rows did NOT fold into claude" \
        || no "E10b edit-band: claude/cli --replace-symbol-body moved — the empty-agent rows were folded in; see $TMP/edit.out"
    # E9: THE MUTATION CONTROL. Move e-a's policy Read to another file: the row it feeds must change
    # (policy-read 1->0, sweep 1->2, terminal 50.0%->25.0%). A column that never moves is not a column.
    sed '/"session":"e-a".*"tool":"Read"/ s#"detail":"/x/repo/src/a.cpp"#"detail":"/x/repo/src/zzz.cpp"#' "$EDITLOG" >"$TMP/editmut.jsonl"
    python3 "$REPORT" "$TMP/editmut.jsonl" 2>&1 | tr -s ' ' >"$TMP/editmut.sq"
    grep -Fqx " --replace-symbol-body 4 25.0% 0 2 1 0" "$TMP/editmut.sq" \
        && ok "E9 edit-band: MUTATION CONTROL — re-pointing the policy Read at another file moves the row (50.0% -> 25.0%, policy-read 1 -> 0, sweep 1 -> 2): the column is live" \
        || no "E9 edit-band: the mutated fixture did not move the row — see $TMP/editmut.sq"
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
# The floor moved 20 -> 12 at §RETIRED (2026-09-02) and the reason is bookkeeping, not weakening:
# sections (1)-(7) now name their OWN sandbox log per arm, because with nothing on stdout the row is
# the only thing left to assert against and a shared sink cannot be indexed by row number. Those rows
# moved from this sink to another sandbox file under the same $TMP; none of them moved toward $HOME,
# which is what I2 below proves by provenance rather than by counting.
GS_ROWS="$( meterrows "$GATE_SINK" )"
[ "$GS_ROWS" -ge 12 ] \
    && ok "I1 isolation: the rows sections (1)-(10) used to leak land in the gate's own sink ($GS_ROWS rows)" \
    || no "I1 isolation: gate sink holds $GS_ROWS row(s) — isolation must redirect the rows, not drop them"

# ── I3: the L2 guard. A harness that names no destination writes NO row ────────────────────────────
# OR-chain pattern (P4.2, 2026-08-29) — needs to actually be base-tier eligible; see the note at (1).
TI3="$TMP/ti3"; mkdir -p "$TI3"
GUARDHOME="$TMP/guardhome"; mkdir -p "$GUARDHOME"
OUTI3="$( printf '%s' "$( grepjson guardcase 'needle|other' )" \
    | env -u RIPWIRE_METER_LOG -u RIPWIRE_HOME HOME="$GUARDHOME" RIPWIRE_METER_FIXTURE=1 \
        PATH="$WITH_RIPWIRE" TMPDIR="$TI3" bash "$HOOK" )"; RCI3=$?
[ "$RCI3" -eq 0 ] && [ -z "$OUTI3" ] && [ ! -f "$GUARDHOME/.ripwire/substitution.jsonl" ] \
    && ok "I3 isolation: RIPWIRE_METER_FIXTURE with no named destination writes no row and costs the call nothing" \
    || no "I3 isolation: exit=$RCI3 out=[${OUTI3:+set}] rows=$( meterrows "$GUARDHOME/.ripwire/substitution.jsonl" )"

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
