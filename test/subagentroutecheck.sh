#!/usr/bin/env bash
# subagentroutecheck.sh — gate for the SubagentStart routing note (lane HK2, 2026-11-21): the `--subagent-start` mode of
# hooks/ripwire-nudge.sh, its registration by `skills/install.sh --hook`, the `claude-subagent-route` row of
# `--doctor --agent=claude`, and the one delegation sentence in `ripwire wrap claude`.
#
# WHY THE NOTE EXISTS. Claude Code's built-in Explore and Plan subagents do not load CLAUDE.md, so the use-when block a
# user pasted there never reaches the agent that does the codebase search. The note is a short factual statement of
# which verb answers which moment, put into those subagents' context at spawn.
#
# Every arm here is NEW behaviour, so each carries the red-on-the-parent proof (LANE_CONSTRAINTS §17): on a0c020bb6 the
# hook has no such mode, the installer registers no SubagentStart entry, the doctor has no such row and the wrap text
# has no such sentence. The silence arms (B)-(E) pass on the parent too (a hook with no such mode is silent), so each
# is PAIRED with a positive control in the same arm: the same invocation with the one condition lifted must speak.
#
#   (A) Explore and Plan get one JSON line: hookEventName SubagentStart, additionalContext naming --for, --expand=SYM
#       and --test-gate in that order
#   (B) every other agent_type gets nothing; RIPWIRE_SUBAGENT_ROUTE=all widens to them; =0|off and an unknown value
#       silence everything
#   (C) the note prints in BOTH meter arms and in an unconfigured (auto) install, same bytes (owner ruling 155, "note
#       for all"): the control-arm silence of the SessionStart primer does not apply to it
#   (D) no ripwire on PATH, no jq, outside a git work tree, inside .git: nothing, rc 0
#   (E) malformed input, empty input, another event: nothing, rc 0
#   (F) the byte cap: additionalContext <= 400 B (every chosen subagent pays it on every turn)
#   (G) deterministic and payload-blind: the same bytes for any cwd, agent_id, session or transcript path
#   (H) writes nothing unless RIPWIRE_SUBAGENT_ROUTE_LOG names a file; then one row per decision, never the text
#   (I) `skills/install.sh --hook` registers exactly one SubagentStart entry, idempotently; an install made before this
#       mode existed gains it on a re-run; another copy's registration is refreshed, not doubled; a user's own
#       SubagentStart hook and the opt-in subagent primer are kept
#   (J) --doctor --agent=claude: claude-subagent-route installed="0" ok="1" on a bare home, installed="1" after the
#       install, ok="0" with a hint once the script is gone; claude-hooks still counts 2 nudge refs
#   (K) `ripwire wrap claude` carries the three-moment brief block (--for before reading source; --expand/--callers/
#       --impact before the first edit; --quality-delta then --test-gate before done; not for a lane that reads no
#       source) on one line of the paste block, inside the 20-line band and a 350 B cap; no other agent's recipe has it;
#       skills/ripwire-orient/subagent-brief.md carries the same block byte for byte
#   (L) every command the note and the block name runs on a fixture repo with the real binary
#   (M) `--agent-brief`, the PROBE-ONLY PreToolUse mode: for an Agent or Task call it returns updatedInput whose prompt
#       is the original plus the block, byte-equal to wrap's, every other input field kept, never a permissionDecision;
#       silent for other tools, a prompt that already names ripwire and the no-op cases; not silenced
#       by the meter's control arm either; and skills/install.sh --hook does NOT register it
#   (N) uninstall: INSTALL.md's documented hook strip ("**3. Hooks**"), run as written, removes the SubagentStart entry
#       and keeps a user's own SubagentStart hook
#
# Usage: test/subagentroutecheck.sh [PATH_TO_RIPWIRE]. Never touches the real ~/.claude or ~/.ripwire.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_SUBAGENT_ROUTE RIPWIRE_SUBAGENT_ROUTE_LOG RIPWIRE_METER_ARM RIPWIRE_METER RIPWIRE_METER_FILE RIPWIRE_METER_FIXTURE RIPWIRE_METER_AGENT
HOOK="$ROOT/hooks/ripwire-nudge.sh"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$HOOK" ] || { echo "subagentroutecheck: $HOOK missing or not executable"; exit 2; }
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "subagentroutecheck: no ripwire binary at $BIN"; exit 2; }
JQ="$( command -v jq )" || { echo "subagentroutecheck: jq is required"; exit 2; }
GIT="$( command -v git )" || { echo "subagentroutecheck: git is required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
PBIN="$TMP/pbin"; mkdir -p "$PBIN"; ln -s "$BIN" "$PBIN/ripwire"; ln -s "$JQ" "$PBIN/jq"; ln -s "$GIT" "$PBIN/git"
# (D) needs a PATH with every tool the hook uses EXCEPT the one under test: macOS ships /usr/bin/jq, so a PATH that
# keeps /usr/bin can never prove the no-jq arm, and a Homebrew ripwire must not leak into the no-ripwire one.
NORW="$TMP/norw"; NOJQ="$TMP/nojq"; mkdir -p "$NORW" "$NOJQ"
for tool in bash cat tr awk sed grep head cut date mkdir wc dirname basename cksum; do
    tp="$( command -v "$tool" )" || { echo "subagentroutecheck: $tool is required"; exit 2; }
    ln -s "$tp" "$NORW/$tool"; ln -s "$tp" "$NOJQ/$tool"
done
ln -s "$JQ" "$NORW/jq"; ln -s "$GIT" "$NORW/git"; ln -s "$BIN" "$NOJQ/ripwire"; ln -s "$GIT" "$NOJQ/git"
HPATH="$PBIN:/usr/bin:/bin"
FHOME="$TMP/home"; mkdir -p "$FHOME"
REPO="$TMP/repo"; mkdir -p "$REPO"
cat >"$REPO/app.py" <<'SRC'
def helper(x):
    return x + 1

def caller_one():
    return helper(1)
SRC
git -C "$REPO" init -q && git -C "$REPO" add app.py \
    && git -C "$REPO" -c user.name=t -c user.email=t@t commit -qm init || { echo "subagentroutecheck: fixture repo"; exit 2; }
PLAIN="$TMP/plain"; mkdir -p "$PLAIN"

# payload CWD AGENT_TYPE [EVENT] [AGENT_ID] [SESSION] — a SubagentStart payload in the documented shape.
payload()
{
    "$JQ" -cn --arg c "$1" --arg t "$2" --arg e "${3:-SubagentStart}" --arg a "${4:-agent-a1}" --arg s "${5:-sess-fixture}" \
        '{session_id:$s, transcript_path:("/x/" + $s + ".jsonl"), cwd:$c, hook_event_name:$e, agent_id:$a, agent_type:$t}'
}
# hook JSON [ENV...] — run the mode with a sandboxed HOME and NO meter arm set (an unconfigured install, which the meter
# hashes into treatment or control by session id); HOUT = stdout, HRC = status.
HRC=0
hook()
{
    _j="$1"; shift
    HOUT="$( printf '%s' "$_j" | env HOME="$FHOME" PATH="$HPATH" "$@" bash "$HOOK" --subagent-start )"
    HRC=$?
    [ "$HRC" -eq 0 ] || no "exit status $HRC (every path must exit 0) for: $*"
}
ctxOf(){ printf '%s' "$1" | "$JQ" -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
# speaks LABEL / silent LABEL — judge the last hook() call.
speaks()
{
    if [ -n "$( ctxOf "$HOUT" )" ]; then ok "$1"; else no "$1 — expected the note, got: '$( printf '%s' "$HOUT" | head -c 120 )'"; fi
}
silent()
{
    if [ -z "$HOUT" ]; then ok "$1"; else no "$1 — expected no output, got: '$( printf '%s' "$HOUT" | head -c 120 )'"; fi
}

echo "(A) Explore and Plan get the note"
hook "$( payload "$REPO" Explore )"
EXPLORE_OUT="$HOUT"
ctx="$( ctxOf "$HOUT" )"
evn="$( printf '%s' "$HOUT" | "$JQ" -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null )"
[ "$evn" = "SubagentStart" ] \
    && ok "hookEventName is SubagentStart" \
    || no "hookEventName: '$evn'"
[ -n "$HOUT" ] && [ "$( printf '%s\n' "$HOUT" | wc -l | tr -d ' ' )" = 1 ] \
    && ok "one JSON line on stdout" \
    || no "stdout is not one line"
printf '%s' "$HOUT" | "$JQ" -e '(.hookSpecificOutput | keys) == ["additionalContext","hookEventName"] and (keys == ["hookSpecificOutput"])' >/dev/null 2>&1 \
    && ok "the object holds hookSpecificOutput{hookEventName,additionalContext} and nothing else (no decision, no updatedInput)" \
    || no "unexpected keys in the hook output"
case "$ctx" in *'ripwire <dir> --for="<task>"'*) ok "names the orient call: ripwire <dir> --for=\"<task>\"";; *) no "the --for call is missing";; esac
case "$ctx" in *'ripwire <dir> --expand=SYM'*) ok "names --expand=SYM for one symbol";; *) no "--expand=SYM is missing";; esac
case "$ctx" in *'ripwire <dir> --test-gate'*) ok "names --test-gate";; *) no "--test-gate is missing";; esac
case "$ctx" in *'before opening files'*) ok "places the orient call before opening files";; *) no "does not say the orient call comes before opening files";; esac
pf="${ctx%%--for=*}"; pe="${ctx%%--expand=*}"; pt="${ctx%%--test-gate*}"
[ -n "$ctx" ] && [ "${#pf}" -lt "${#pe}" ] && [ "${#pe}" -lt "${#pt}" ] \
    && ok "order: --for, then --expand, then --test-gate" \
    || no "verb order wrong"
hook "$( payload "$REPO" Plan )"
[ -n "$HOUT" ] && [ "$HOUT" = "$EXPLORE_OUT" ] \
    && ok "Plan gets the same bytes as Explore" \
    || no "Plan output differs from Explore's, or is empty"

echo "(B) agent types that load CLAUDE.md get nothing; the switch"
for t in general-purpose claude statusline-setup my-custom-agent ""; do
    hook "$( payload "$REPO" "$t" )"; silent "agent_type '${t:-<empty>}' is not spoken to"
done
hook "$( payload "$REPO" explore )"; silent "the match is exact: 'explore' is not Explore"
hook "$( payload "$REPO" general-purpose )" RIPWIRE_SUBAGENT_ROUTE=all
[ -n "$HOUT" ] && [ "$HOUT" = "$EXPLORE_OUT" ] \
    && ok "RIPWIRE_SUBAGENT_ROUTE=all speaks to general-purpose, same bytes" \
    || no "RIPWIRE_SUBAGENT_ROUTE=all did not widen the note"
for v in 0 off; do
    hook "$( payload "$REPO" Explore )" RIPWIRE_SUBAGENT_ROUTE="$v"; silent "RIPWIRE_SUBAGENT_ROUTE=$v silences Explore"
done
hook "$( payload "$REPO" Explore )" RIPWIRE_SUBAGENT_ROUTE=al; silent "an unknown switch value reads as off (a typo must not widen or keep it)"
hook "$( payload "$REPO" Explore )"; speaks "positive control: the same Explore payload with no switch speaks"

echo "(C) the note prints in both meter arms (ruling 155)"
# RED PROOF: at 80ec317ec the mode exited silently when the meter arm was control, so the control case below, and
# about half of the unconfigured session ids, printed nothing there.
for armv in control treatment auto; do
    hook "$( payload "$REPO" Explore )" RIPWIRE_METER_ARM="$armv"
    [ -n "$HOUT" ] && [ "$HOUT" = "$EXPLORE_OUT" ] \
        && ok "RIPWIRE_METER_ARM=$armv: the note, same bytes" \
        || no "RIPWIRE_METER_ARM=$armv: expected the note, got: '$( printf '%s' "$HOUT" | head -c 80 )'"
done
mkdir -p "$TMP/chome/.ripwire"; printf 'arm=control\n' >"$TMP/chome/.ripwire/meter.conf"
hook "$( payload "$REPO" Plan )" HOME="$TMP/chome"
[ -n "$HOUT" ] && [ "$HOUT" = "$EXPLORE_OUT" ] \
    && ok "arm=control in meter.conf: the note, same bytes" \
    || no "arm=control in meter.conf silenced the note"
spoke=0
for sid in s01 s02 s03 s04 s05 s06 s07 s08 s09 s10 s11 s12 s13 s14 s15 s16; do
    hook "$( payload "$REPO" Explore SubagentStart agent-a1 "$sid" )"
    if [ "$HOUT" = "$EXPLORE_OUT" ]; then spoke=$(( spoke + 1 )); fi
done
[ "$spoke" = 16 ] \
    && ok "unconfigured install: 16 of 16 session ids get the note (the session-hash split does not apply)" \
    || no "unconfigured install: only $spoke of 16 session ids got the note"

echo "(D) no-op where the commands could not run"
hook "$( payload "$REPO" Explore )" PATH="$NORW"; silent "no ripwire on PATH: nothing"
hook "$( payload "$REPO" Explore )" PATH="$NOJQ"; silent "no jq on PATH: nothing"
hook "$( payload "$PLAIN" Explore )"; silent "outside a git work tree: nothing"
hook "$( payload "$REPO/.git" Explore )"; silent "inside .git: nothing"
hook "$( payload "$TMP/does-not-exist" Explore )"; silent "a cwd that does not exist: nothing"
hook "$( payload "$REPO" Explore )" GIT_DIR="$REPO/.git"; speaks "an inherited GIT_DIR does not decide it: the repo cwd still speaks"
hook "$( payload "$PLAIN" Explore )" GIT_DIR="$REPO/.git"; silent "an inherited GIT_DIR does not decide it: the plain cwd stays silent"

echo "(E) malformed input and other events"
hook 'not json'; silent "malformed input: nothing"
hook ''; silent "empty input: nothing"
hook '{}'; silent "an object with no event: nothing"
hook "$( payload "$REPO" Explore SessionStart )"; silent "a SessionStart payload: nothing"
hook "$( payload "$REPO" Explore SubagentStop )"; silent "a SubagentStop payload: nothing"

echo "(F) the byte cap"
nb="$( printf '%s' "$ctx" | wc -c | tr -d ' ' )"
ob="$( printf '%s\n' "$EXPLORE_OUT" | wc -c | tr -d ' ' )"
[ -n "$ctx" ] && [ "$nb" -le 400 ] \
    && ok "additionalContext is $nb B (cap 400); the whole stdout line is $ob B" \
    || no "additionalContext is $nb B — over the 400 B cap, or empty"
[ -n "$ctx" ] && [ "$nb" -ge 150 ] \
    && ok "and it is not a stub ($nb B >= 150)" \
    || no "additionalContext is only $nb B"

echo "(G) deterministic and payload-blind"
hook "$( payload "$REPO" Explore )"; a="$HOUT"
hook "$( payload "$REPO" Explore )"; b="$HOUT"
[ -n "$a" ] && [ "$a" = "$b" ] && [ "$a" = "$EXPLORE_OUT" ] \
    && ok "the same input twice gives the same bytes" \
    || no "two runs of the same input differ"
HOSTILE="$TMP/re\"po \$(touch $TMP/pwned) \`id\`"; mkdir -p "$HOSTILE"
git -C "$HOSTILE" init -q 2>/dev/null
hook "$( payload "$HOSTILE" Explore SubagentStart 'agent-"; rm -rf /' 'sess $(id) "x"' )"
[ -n "$HOUT" ] && [ "$HOUT" = "$EXPLORE_OUT" ] && [ ! -e "$TMP/pwned" ] \
    && ok "a hostile cwd, agent_id and session give byte-identical output and run nothing" \
    || no "payload text reached the output, or was executed"

echo "(H) writes nothing unless a log is named"
left="$( find "$FHOME" -type f 2>/dev/null | head -5 )"
[ -z "$left" ] \
    && ok "the sandbox HOME holds no file after every run above (no meter row, no marker)" \
    || no "the hook wrote under HOME: $left"
LOG="$TMP/route.tsv"
hook "$( payload "$REPO" Explore )" RIPWIRE_SUBAGENT_ROUTE_LOG="$LOG"
hook "$( payload "$REPO" general-purpose )" RIPWIRE_SUBAGENT_ROUTE_LOG="$LOG"
hook "$( payload "$PLAIN" Plan )" RIPWIRE_SUBAGENT_ROUTE_LOG="$LOG"
[ -f "$LOG" ] && [ "$( wc -l <"$LOG" | tr -d ' ' )" = 3 ] \
    && ok "RIPWIRE_SUBAGENT_ROUTE_LOG: one row per decision (3 runs, 3 rows)" \
    || no "log rows: $( [ -f "$LOG" ] && wc -l <"$LOG" || echo none )"
[ -f "$LOG" ] && [ "$( sed -n 1p "$LOG" )" = "$( printf 'Explore\tdelivered\t%s' "$nb" )" ] \
    && [ "$( sed -n 2p "$LOG" )" = "$( printf 'general-purpose\tskip-agent-type\t0' )" ] \
    && [ "$( sed -n 3p "$LOG" )" = "$( printf 'Plan\tskip-not-git\t0' )" ] \
    && ok "rows are agent_type, decision, bytes: delivered / skip-agent-type / skip-not-git" \
    || no "log rows are not the expected three: $( [ -f "$LOG" ] && tr '\t\n' ' |' <"$LOG" )"
[ -f "$LOG" ] && ! grep -q -- '--for' "$LOG" \
    && ok "a row never carries the text" \
    || no "the log carries the note's text, or is missing"

echo "(I) skills/install.sh --hook registers it"
CFG="$TMP/cfg"; mkdir -p "$CFG"
printf '%s\n' '{"hooks":{"SubagentStart":[{"matcher":"*","hooks":[{"type":"command","command":"/x/mine.sh"}]},{"matcher":"*","hooks":[{"type":"command","command":"/opt/x/hooks/ripwire-subagent-primer.sh","timeout":5}]}]},"theme":"dark"}' >"$CFG/settings.json"
inst(){ env HOME="$FHOME" CLAUDE_CONFIG_DIR="$CFG" PATH="$HPATH" bash "$ROOT/skills/install.sh" --hook --no-hook-legend-seen >"$TMP/inst.out" 2>&1; }
count(){ "$JQ" '[.hooks.SubagentStart[]?.hooks[]? | select((.command // "") | test("/hooks/ripwire-nudge\\.sh.? --subagent-start$"))] | length' "$CFG/settings.json"; }
inst; r1=$?
grep -q 'hooks.SubagentStart' "$TMP/inst.out" \
    && ok "the installer announces the SubagentStart entry before writing it" \
    || no "the installer did not announce the SubagentStart entry"
grep -q 'remove:.*SubagentStart' "$TMP/inst.out" \
    && ok "its remove: line names the SubagentStart entry" \
    || no "the remove: line does not name the SubagentStart entry"
n1="$( count )"; inst; r2=$?; n2="$( count )"
[ "$r1" = 0 ] && [ "$r2" = 0 ] \
    && ok "installer rc 0 twice" \
    || no "installer rc $r1/$r2: $( tail -3 "$TMP/inst.out" )"
[ "$n1" = 1 ] && [ "$n2" = 1 ] \
    && ok "exactly one SubagentStart routing entry after one run and after two" \
    || no "SubagentStart routing entries: $n1 after one run, $n2 after two"
"$JQ" -e '[.hooks.SubagentStart[] | select(.hooks[0].command | test("ripwire-nudge"))][0] | .matcher == "*" and .hooks[0].type == "command" and .hooks[0].timeout == 5' "$CFG/settings.json" >/dev/null 2>&1 \
    && ok "matcher \"*\", type command, timeout 5" \
    || no "the registered entry's shape is wrong"
"$JQ" -e '.theme == "dark" and ([.hooks.SubagentStart[].hooks[].command] | index("/x/mine.sh") != null and index("/opt/x/hooks/ripwire-subagent-primer.sh") != null)' "$CFG/settings.json" >/dev/null 2>&1 \
    && ok "the user's own SubagentStart hook, the opt-in primer's entry and other keys are kept" \
    || no "the installer dropped an existing SubagentStart entry or key"
"$JQ" -e '([.hooks.PreToolUse[]?.hooks[]? | select(.command | endswith("/hooks/ripwire-nudge.sh"))] | length) == 1 and ([.hooks.SessionStart[]?.hooks[]? | select(.command | endswith("ripwire-nudge.sh --session-start"))] | length) == 1' "$CFG/settings.json" >/dev/null 2>&1 \
    && ok "the PreToolUse and SessionStart entries are still one each" \
    || no "the PreToolUse / SessionStart entries changed count"
# an install made BEFORE this mode existed: the nudge is registered, the SubagentStart entry is not.
"$JQ" '.hooks.SubagentStart |= map( select( .hooks[0].command | test("ripwire-nudge") | not ) )' "$CFG/settings.json" >"$TMP/s2" && mv "$TMP/s2" "$CFG/settings.json"
[ "$( count )" = 0 ] || no "fixture: could not strip the entry"
inst
[ "$( count )" = 1 ] \
    && ok "an install that predates the mode gains the entry on a re-run" \
    || no "re-running --hook over an older install left $( count ) SubagentStart routing entries"
# another copy's registration (the Homebrew share dir) is refreshed in place, not doubled.
"$JQ" '.hooks.SubagentStart |= map( if (.hooks[0].command | test("ripwire-nudge")) then .hooks[0].command = "/opt/homebrew/share/ripwire/hooks/ripwire-nudge.sh --subagent-start" else . end )' "$CFG/settings.json" >"$TMP/s2" && mv "$TMP/s2" "$CFG/settings.json"
inst
c1="$( "$JQ" -r '[.hooks.SubagentStart[].hooks[].command | select(test("ripwire-nudge"))] | join("|")' "$CFG/settings.json" )"
[ "$c1" = "$ROOT/hooks/ripwire-nudge.sh --subagent-start" ] \
    && ok "another copy's registration is refreshed, not duplicated" \
    || no "refresh left: $c1"
# the registered command, run the way Claude Code runs it (through a shell), speaks.
regCmd="$( "$JQ" -r '[.hooks.SubagentStart[].hooks[].command | select(test("ripwire-nudge"))][0]' "$CFG/settings.json" )"
out="$( payload "$REPO" Explore | env HOME="$FHOME" PATH="$HPATH" sh -c "$regCmd" )"
[ -n "$out" ] && [ "$out" = "$EXPLORE_OUT" ] \
    && ok "the registered command, run through a shell, emits the note" \
    || no "the registered command printed: '$( printf '%s' "$out" | head -c 120 )'"

echo "(J) --doctor --agent=claude"
row(){ env HOME="$FHOME" CLAUDE_CONFIG_DIR="$1" PATH="$HPATH" "$BIN" "$REPO" --doctor --agent=claude 2>/dev/null | tr '<' '\n' | grep "n=\"$2\"" || true; }
BARE="$TMP/bare"; mkdir -p "$BARE"
r="$( row "$BARE" claude-subagent-route )"
printf '%s' "$r" | grep -q 'ok="1"' && printf '%s' "$r" | grep -q 'installed="0"' \
    && ok "absent: claude-subagent-route ok=\"1\" installed=\"0\"" \
    || no "absent-case row: [$r]"
r="$( row "$CFG" claude-subagent-route )"
printf '%s' "$r" | grep -q 'ok="1"' && printf '%s' "$r" | grep -q 'installed="1"' && printf '%s' "$r" | grep -q 'refs="1"' \
    && ok "installed: claude-subagent-route ok=\"1\" installed=\"1\" refs=\"1\"" \
    || no "installed-case row: [$r]"
r="$( row "$CFG" claude-hooks )"
printf '%s' "$r" | grep -q 'ok="1"' && printf '%s' "$r" | grep -q 'nudge_refs="2"' \
    && ok "claude-hooks still counts 2 nudge refs (the SubagentStart entry is the new row's, not a third)" \
    || no "claude-hooks row: [$r]"
# only the SubagentStart entry, no PreToolUse/SessionStart: claude-hooks must not read it as half an install.
ONLY="$TMP/only"; mkdir -p "$ONLY"
"$JQ" '{hooks:{SubagentStart:[.hooks.SubagentStart[] | select(.hooks[0].command | test("ripwire-nudge"))], PreToolUse:.hooks.PreToolUse}}' "$CFG/settings.json" >"$ONLY/settings.json"
r="$( row "$ONLY" claude-hooks )"
printf '%s' "$r" | grep -q 'ok="0"' && printf '%s' "$r" | grep -q 'nudge_refs="1"' \
    && ok "PreToolUse + SubagentStart with no SessionStart primer: claude-hooks ok=\"0\", nudge_refs=\"1\"" \
    || no "claude-hooks counted the SubagentStart entry as a nudge ref: [$r]"
GONE="$TMP/gone"; mkdir -p "$GONE"
"$JQ" '.hooks.SubagentStart |= map( if (.hooks[0].command | test("ripwire-nudge")) then .hooks[0].command = "/nonexistent/hooks/ripwire-nudge.sh --subagent-start" else . end )' "$CFG/settings.json" >"$GONE/settings.json"
r="$( row "$GONE" claude-subagent-route )"
printf '%s' "$r" | grep -q 'ok="0"' && printf '%s' "$r" | grep -q 'hint=' \
    && ok "script gone: claude-subagent-route ok=\"0\" and a hint" \
    || no "broken install not reported: [$r]"
printf '%s' "$r" | grep -q '/nonexistent' \
    && no "the doctor row prints a command line (it must carry counts and booleans only)" \
    || ok "the row carries no command line"

echo "(K) ripwire wrap claude: the three-moment brief block"
body(){ "$BIN" wrap "$1" --force 2>/dev/null | sed -n '/^# --- paste into /,/^# --- end paste ---$/p' | sed '1d;$d'; }
body claude >"$TMP/blurb_claude"
n="$( grep -c 'delegate to subagents' "$TMP/blurb_claude" )"
[ "$n" = 1 ] \
    && ok "the paste block addresses delegation on exactly one line" \
    || no "'delegate to subagents' appears on $n lines of wrap claude's paste block"
line="$( grep 'delegate to subagents' "$TMP/blurb_claude" )"
BLOCK="${line#*every brief that reads source: }"
[ -n "$line" ] && [ "$BLOCK" != "$line" ] \
    && ok "it says: paste this into every brief that reads source (a lane that reads none is left out)" \
    || no "the lead-in 'paste this into every brief that reads source: ' is missing: $line"
case "$BLOCK" in *'before reading source, `ripwire <dir> --for="<task>"`'*) ok "moment 1: --for before reading source";; *) no "moment 1 missing: $BLOCK";; esac
case "$BLOCK" in *'before the first edit, `--expand=SYM --legend=compact`, `--callers=SYM --legend=compact` or `--impact=SYM --legend=compact`'*) ok "moment 2: --expand / --callers / --impact before the first edit";; *) no "moment 2 missing: $BLOCK";; esac
case "$BLOCK" in *'before reporting done, commit, then `--quality-delta=BASE..HEAD --legend=compact` and `--test-gate --legend=compact`'*) ok "moment 3: commit, --quality-delta=BASE..HEAD, then --test-gate before reporting done";; *) no "moment 3 missing: $BLOCK";; esac
p1="${BLOCK%%--for=*}"; p2="${BLOCK%%--expand=*}"; p3="${BLOCK%%--quality-delta*}"; p4="${BLOCK%%--test-gate*}"
[ -n "$BLOCK" ] && [ "${#p1}" -lt "${#p2}" ] && [ "${#p2}" -lt "${#p3}" ] && [ "${#p3}" -lt "${#p4}" ] \
    && ok "the moments are in task order" \
    || no "the moments are out of order"
kb="$( printf '%s' "$BLOCK" | wc -c | tr -d ' ' )"
[ "$kb" -ge 100 ] && [ "$kb" -le 350 ] \
    && ok "the block is $kb B (cap 350: it is pasted into every brief)" \
    || no "the block is $kb B, outside 100..350"
case "$line" in '- One task:'*'--plan-lanes=N'*) ok "it rides on the parallel-agents line (no new line)";; *) no "it is not on the parallel-agents line";; esac
bl="$( wc -l <"$TMP/blurb_claude" | tr -d ' ' )"
[ "$bl" = 20 ] \
    && ok "the paste block is still 20 lines" \
    || no "the paste block is $bl lines"
others=0
for a in codex cursor windsurf gemini opencode openclaw hermes aider; do
    body "$a" >"$TMP/blurb_$a"
    [ -s "$TMP/blurb_$a" ] || no "$a: wrap printed no paste block (the check below would pass vacuously)"
    if grep -q 'delegate to subagents' "$TMP/blurb_$a"; then no "$a: the brief block leaked into its recipe"; fi
    others=$(( others + 1 ))
done
if [ "$others" = 8 ] && [ "$fail" = 0 ]; then ok "none of the other 8 agents' paste blocks carries it"; fi
sed 's/ When you delegate to subagents.*$//' "$TMP/blurb_claude" | grep -F -- '- One task:' >"$TMP/l_claude"
grep -F -- '- One task:' "$TMP/blurb_gemini" >"$TMP/l_gemini"
[ -s "$TMP/l_gemini" ] && cmp -s "$TMP/l_claude" "$TMP/l_gemini" \
    && ok "with the block removed, claude's line is the shared line byte for byte" \
    || no "claude's parallel-agents line differs from the shared one beyond the block"
BRIEFMD="$ROOT/skills/ripwire-orient/subagent-brief.md"
[ -n "$BLOCK" ] && grep -qxF -- "$BLOCK" "$BRIEFMD" \
    && ok "skills/ripwire-orient/subagent-brief.md carries the same block as its own line, byte for byte" \
    || no "skills/ripwire-orient/subagent-brief.md does not carry wrap's block verbatim on one line"
"$BIN" wrap claude --force 2>/dev/null | grep -v '^# --- ' | grep '^#' | grep -q 'SubagentStart' \
    && ok "the recipe discloses that the hook install registers a SubagentStart note" \
    || no "wrap claude does not disclose the SubagentStart registration"

echo "(L) the commands the note and the block name run"
"$BIN" "$REPO" --for="helper caller_one" >"$TMP/o1" 2>&1; r=$?
[ "$r" = 0 ] && grep -q 'helper' "$TMP/o1" \
    && ok "--for=...: rc 0, names the symbol" \
    || no "--for rc $r"
"$BIN" "$REPO" --expand=helper --legend=compact >"$TMP/o2" 2>&1; r=$?
[ "$r" = 0 ] && grep -q 'return x + 1' "$TMP/o2" \
    && ok "--expand=SYM --legend=compact: rc 0, prints the body" \
    || no "--expand rc $r: $( head -c 200 "$TMP/o2" )"
( cd "$REPO" && "$BIN" . --test-gate --legend=compact >"$TMP/o3" 2>&1 ); r=$?
case "$r" in 0|4) ok "--test-gate --legend=compact: rc $r";; *) no "--test-gate rc $r: $( head -c 200 "$TMP/o3" )";; esac

"$BIN" "$REPO" --callers=helper --legend=compact >"$TMP/o4" 2>&1; r=$?
[ "$r" = 0 ] && grep -q 'caller_one' "$TMP/o4" \
    && ok "--callers=SYM: rc 0, names the caller" \
    || no "--callers rc $r: $( head -c 200 "$TMP/o4" )"
"$BIN" "$REPO" --impact=helper --legend=compact >"$TMP/o5" 2>&1; r=$?
[ "$r" = 0 ] \
    && ok "--impact=SYM: rc 0" \
    || no "--impact rc $r: $( head -c 200 "$TMP/o5" )"
printf 'def helper_two(y):\n    return helper(y) * 2\n' >>"$REPO/app.py"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -qam second || no "fixture: second commit"
( cd "$REPO" && "$BIN" . --quality-delta=HEAD~1..HEAD --legend=compact >"$TMP/o6" 2>&1 ); r=$?
case "$r" in 0|2) ok "--quality-delta=BASE..HEAD: rc $r";; *) no "--quality-delta=BASE..HEAD rc $r: $( head -c 200 "$TMP/o6" )";; esac

echo "(M) --agent-brief: the probe-only PreToolUse mode"
# agentCall TOOL PROMPT [CWD] — a PreToolUse payload for a subagent spawn, in the documented shape.
agentCall()
{
    "$JQ" -cn --arg t "$1" --arg p "$2" --arg c "${3:-$REPO}" \
        '{session_id:"sess-fixture", transcript_path:"/x/s.jsonl", cwd:$c, hook_event_name:"PreToolUse", tool_name:$t,
          tool_input:{description:"find it", prompt:$p, subagent_type:"Explore"}}'
}
brief()
{
    _j="$1"; shift
    HOUT="$( printf '%s' "$_j" | env HOME="$FHOME" PATH="$HPATH" "$@" bash "$HOOK" --agent-brief )"
    HRC=$?
    [ "$HRC" -eq 0 ] || no "exit status $HRC (every path must exit 0) for: $*"
}
brief "$( agentCall Agent 'Locate the function helper.' )"
AGENT_OUT="$HOUT"
got="$( printf '%s' "$HOUT" | "$JQ" -r '.hookSpecificOutput.updatedInput.prompt // empty' 2>/dev/null )"
want="$( printf 'Locate the function helper.\n\n%s' "$BLOCK" )"
[ -n "$BLOCK" ] && [ "$got" = "$want" ] \
    && ok "Agent: updatedInput.prompt is the original prompt, a blank line, and wrap's block byte for byte" \
    || no "Agent: updatedInput.prompt is not prompt + block: '$( printf '%s' "$got" | head -c 160 )'"
printf '%s' "$HOUT" | "$JQ" -e '.hookSpecificOutput | .hookEventName == "PreToolUse" and .updatedInput.description == "find it"
    and .updatedInput.subagent_type == "Explore" and (.updatedInput | keys) == ["description","prompt","subagent_type"]' >/dev/null 2>&1 \
    && ok "hookEventName PreToolUse; every other input field passed through, none added" \
    || no "the updated input lost or gained a field"
printf '%s' "$HOUT" | "$JQ" -e '.hookSpecificOutput | has("permissionDecision") | not' >/dev/null 2>&1 \
    && ok "no permissionDecision (the hook does not approve a spawn)" \
    || no "the hook carries a permissionDecision nobody asked for"
brief "$( agentCall Task 'Locate the function helper.' )"
[ -n "$HOUT" ] && [ "$HOUT" = "$AGENT_OUT" ] \
    && ok "the Task tool name gets the same bytes" \
    || no "Task differs from Agent, or is empty"
brief "$( agentCall Agent 'Locate the function helper.' )"
[ "$HOUT" = "$AGENT_OUT" ] \
    && ok "the same input twice gives the same bytes" \
    || no "two runs differ"
brief "$( agentCall Bash 'Locate the function helper.' )"; silent "another tool (Bash): nothing"
brief "$( agentCall Agent 'Orient with ripwire, then locate helper.' )"; silent "a prompt that already names ripwire: nothing (the block is added once)"
brief "$( agentCall Agent 'Locate the function helper.' )" RIPWIRE_METER_ARM=control
[ -n "$HOUT" ] && [ "$HOUT" = "$AGENT_OUT" ] \
    && ok "the meter's control arm does not silence it: same bytes" \
    || no "RIPWIRE_METER_ARM=control changed or silenced the rewrite"
brief "$( agentCall Agent 'x' )" PATH="$NORW"; silent "no ripwire on PATH: nothing"
brief "$( agentCall Agent 'x' )" PATH="$NOJQ"; silent "no jq: nothing"
brief "$( agentCall Agent 'x' "$PLAIN" )"; silent "outside a git work tree: nothing"
brief 'not json'; silent "malformed input: nothing"
brief "$( payload "$REPO" Explore )"; silent "a SubagentStart payload: nothing"
"$JQ" -e '[.. | objects | .command? // empty | select(test("--agent-brief"))] | length == 0' "$CFG/settings.json" >/dev/null 2>&1 \
    && ok "skills/install.sh --hook registered no --agent-brief entry (the mode is not installed by anything)" \
    || no "the installer registered the probe-only --agent-brief mode"
if grep -q -- '--agent-brief' "$ROOT/skills/install.sh"; then no "skills/install.sh names --agent-brief"; else ok "skills/install.sh does not name --agent-brief"; fi

echo "(N) uninstall: INSTALL.md's hook strip"
STRIP="$( awk '/^\*\*3\. Hooks\*\*/{s=1} s&&/^```bash$/{c=1;next} c&&/^```$/{exit} c' "$ROOT/INSTALL.md" )"
[ "$( count )" = 1 ] || no "(N) precondition: the fixture should hold one SubagentStart routing entry, has $( count )"
if [ -z "$STRIP" ]; then
    no "INSTALL.md has no \`\`\`bash block after \"**3. Hooks**\" — the hook strip this arm runs is gone"
else
    ( cd "$TMP" && env HOME="$FHOME" CLAUDE_CONFIG_DIR="$CFG" PATH="$HPATH" sh -c "$STRIP" ) >"$TMP/strip.out" 2>&1
    left="$( "$JQ" '[.. | objects | .command? // empty | select(test("ripwire-nudge"))] | length' "$CFG/settings.json" 2>/dev/null )"
    [ "$left" = 0 ] \
        && ok "the documented strip removes the SubagentStart routing entry (and every other ripwire-nudge entry)" \
        || no "after the documented strip $left ripwire-nudge entries remain: $( head -3 "$TMP/strip.out" )"
    "$JQ" -e '[.hooks.SubagentStart[]?.hooks[]?.command] | index("/x/mine.sh") != null' "$CFG/settings.json" >/dev/null 2>&1 \
        && ok "the user's own SubagentStart hook is kept" \
        || no "the strip removed the user's own SubagentStart hook"
fi

[ "$fail" = 0 ] && echo "subagentroutecheck: ALL PASS" || echo "subagentroutecheck: FAIL"
exit "$fail"
