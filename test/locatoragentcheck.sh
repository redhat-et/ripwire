#!/usr/bin/env bash
# locatoragentcheck.sh — gate for the ripwire-locator Claude Code subagent and the main-thread delegation sentence (lane LC1,
# 2026-11-22, owner ruling 185).
#
# WHY. In Claude Code every tool result stays in the main conversation and is re-sent with each later request, so a
# ~7K-token --for answer read in the main thread rides every request after it. A subagent runs ripwire in its own short
# context and hands back only ranges; the main thread then carries the ~300-token report instead. This gate holds the
# three pieces that make that route exist: the agent file, its installation, and the sentence that tells the main thread
# to use it. It measures no saving: whether the route saves tokens is the R5 arm's question, not this gate's.
#
#   (A) skills/agents/ripwire-locator.md has valid frontmatter per code.claude.com/docs/en/sub-agents: a `---` fence, only
#       documented camelCase keys, name ripwire-locator (no `:`), a description, tools EXACTLY Bash, Read, Grep, Glob (no
#       Agent/Task: a locator that can spawn would nest; no Edit/Write: it locates, it does not change), a documented model
#   (B) the output contract is written in the prompt: EDIT/READ/MISSING lines, `path:start-end`, one turn of ranged Reads,
#       the ~300-token ceiling, nothing before or after the report
#   (C) byte budgets: description <= 400 B (it sits in the main thread's Agent tool listing on EVERY request), prompt body
#       <= 2,400 B (the subagent's own per-request carry)
#   (D) skills/install.sh installs it for Claude into ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents, idempotently, under a temp
#       HOME; keeps a user's own file at that path; installs nothing for --codex or an explicit PATH; a checkout without the
#       agent file still installs its skills with rc 0 (a release staged before this file existed)
#   (E) `ripwire wrap claude` carries the delegation sentence once, on the orient line, still 20 lines; no other agent's
#       recipe names the locator; RIPWIRE_NO_LOCATOR_ROUTE=1 (the A/B handle) prints the default output with exactly that
#       sentence removed, byte for byte, and nothing else changed
#   (F) the SessionStart primer (hooks/ripwire-nudge.sh --session-start, which re-prints the wrap block) carries it, and
#       drops it under RIPWIRE_NO_LOCATOR_ROUTE=1
#   (G) the subagent-facing texts do NOT carry it (the SubagentStart note, the three-moment brief block): a subagent told to
#       delegate to the locator would nest one
#   (H) skills/ripwire-orient/SKILL.md tells the main thread the same route
#   (I) the opt-out (owner ruling 189): --no-locator-agent and RIPWIRE_NO_LOCATOR_AGENT=1 each install the skills and write
#       no agent file, and say so; the opt-out leaves a user's own file at that path untouched; the default (D) still writes
#       it; the flag is documented in INSTALL.md and README.md, and both curl installers name the variable they pass through
#       (test/releaseinstallcheck.sh (E8)/(E9) drive the one-liner itself)
#
# Usage: test/locatoragentcheck.sh [PATH_TO_RIPWIRE]. Never touches the real ~/.claude, ~/.agents or ~/.ripwire.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_LOCATOR_ROUTE RIPWIRE_NO_LOCATOR_AGENT RIPWIRE_SUBAGENT_ROUTE RIPWIRE_METER_ARM RIPWIRE_METER RIPWIRE_METER_FILE RIPWIRE_METER_AGENT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "locatoragentcheck: no ripwire binary at $BIN"; exit 2; }
JQ="$( command -v jq )" || { echo "locatoragentcheck: jq is required"; exit 2; }
AGENT="$ROOT/skills/agents/ripwire-locator.md"
HOOK="$ROOT/hooks/ripwire-nudge.sh"
INST="$ROOT/skills/install.sh"
SENTENCE='Main thread: for a code lookup, delegate to the `ripwire-locator` subagent (when installed) and ask it for edit ranges; run a full `--for` here only when you need the whole map.'
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

echo "(A) frontmatter"
if [ -f "$AGENT" ]; then ok "the agent file exists: skills/agents/ripwire-locator.md"; else no "skills/agents/ripwire-locator.md is missing"; fi
: >"$TMP/fm"; : >"$TMP/bodytext"
if [ -f "$AGENT" ]; then
    awk 'NR==1{next} /^---$/{exit} {print}' "$AGENT" >"$TMP/fm"
    awk 'f{print} /^---$/{c++; if(c==2){f=1}}' "$AGENT" >"$TMP/bodytext"
fi
if [ "$( head -n1 "$AGENT" 2>/dev/null )" = "---" ] && [ "$( grep -c '^---$' "$AGENT" 2>/dev/null )" -ge 2 ]; then
    ok "opens with a --- fence and closes it"
else
    no "no --- fenced frontmatter"
fi
documented=" name description tools disallowedTools model permissionMode maxTurns skills mcpServers hooks memory effort isolation color initialPrompt background omitClaudeMd autoCompactWindow experimental "
undocumented=""
while IFS= read -r l; do
    k="${l%%:*}"
    case "$documented" in *" $k "*) ;; *) undocumented="$undocumented $k" ;; esac
done <"$TMP/fm"
if [ -s "$TMP/fm" ] && [ -z "$undocumented" ]; then
    ok "every frontmatter key is documented (Claude Code ignores an unknown key without an error)"
else
    no "undocumented or no frontmatter keys:${undocumented:- (none read)}"
fi
fmval(){ sed -n "s/^$1:[[:space:]]*//p" "$TMP/fm" | head -n1; }
if [ "$( fmval name )" = "ripwire-locator" ]; then ok "name: ripwire-locator"; else no "name is '$( fmval name )'"; fi
desc="$( fmval description )"
if [ -n "$desc" ]; then ok "description is present"; else no "description is empty"; fi
tools="$( fmval tools | tr -d ' ' | tr ',' '\n' | sort | tr '\n' ',' )"
if [ "$tools" = "Bash,Glob,Grep,Read," ]; then
    ok "tools are exactly Bash, Read, Grep, Glob (no Agent/Task, no Edit/Write)"
else
    no "tools are '$tools', want exactly Bash,Glob,Grep,Read"
fi
model="$( fmval model )"
case "$model" in
    "") ok "model unset: the subagent runs on the main conversation's model (the docs' subagent model order), and the skill scan has no model: line to warn on" ;;
    sonnet|opus|haiku|fable|inherit|claude-*) ok "model is a documented value: $model" ;;
    *) no "model '$model' is not a documented value" ;;
esac
mt="$( fmval maxTurns )"
case "$mt" in
    "") ok "maxTurns unset" ;;
    *[!0-9]*) no "maxTurns '$mt' is not a positive integer" ;;
    *) if [ "$mt" -ge 4 ]; then ok "maxTurns $mt leaves room for --for + one ranged Read turn + a follow-up + the report"; else no "maxTurns $mt is too small to finish"; fi ;;
esac

( cd "$ROOT" && "$BIN" wrap claude --force >/dev/null 2>"$TMP/scan" )
if ! grep -q 'skills/agents/ripwire-locator.md' "$TMP/scan"; then ok "wrap's skill scan of ./skills raises nothing on the agent file"; else no "wrap's skill scan flags the agent file: $( grep -m1 ripwire-locator "$TMP/scan" )"; fi

echo "(B) the output contract is in the prompt"
for needle in 'EDIT path:start-end' 'READ path:start-end' 'MISSING' 'ripwire <root> --for="<task>"' 'ONE turn' '300 tokens' 'nothing before or after'; do
    if grep -qF -- "$needle" "$TMP/bodytext"; then ok "names: $needle"; else no "the prompt does not carry: $needle"; fi
done
if grep -qiF 'never whole files' "$TMP/bodytext"; then ok "ranged Reads only"; else no "the prompt does not forbid whole-file Reads"; fi

echo "(C) byte budgets"
db="$( printf '%s' "$desc" | wc -c | tr -d ' ' )"
bb="$( wc -c <"$TMP/bodytext" | tr -d ' ' )"
if [ "$db" -ge 80 ] && [ "$db" -le 400 ]; then ok "description is $db B (cap 400: the main thread's Agent tool listing carries it on every request)"; else no "description is $db B, outside 80..400"; fi
if [ "$bb" -ge 500 ] && [ "$bb" -le 2400 ]; then ok "prompt body is $bb B (cap 2,400)"; else no "prompt body is $bb B, outside 500..2400"; fi

echo "(D) the installer"
H1="$TMP/h1"; mkdir -p "$H1"
HOME="$H1" bash "$INST" >"$TMP/i1" 2>&1; r=$?
dest="$H1/.claude/agents/ripwire-locator.md"
if [ "$r" = 0 ] && [ -f "$dest" ] && cmp -s "$dest" "$AGENT"; then ok "a Claude install puts it at ~/.claude/agents/ripwire-locator.md, content identical (rc $r)"; else no "not installed (rc $r): $( tail -n 3 "$TMP/i1" )"; fi
if grep -q 'ripwire-locator' "$TMP/i1"; then ok "the install output names what it put there"; else no "the install output does not disclose the agent"; fi
HOME="$H1" bash "$INST" >"$TMP/i2" 2>&1; r=$?
n="$( find "$H1/.claude/agents" -type f -o -type l | wc -l | tr -d ' ' )"
if [ "$r" = 0 ] && [ "$n" = 1 ] && cmp -s "$dest" "$AGENT"; then ok "a re-run is idempotent: one entry, same bytes"; else no "re-run: rc $r, $n entries"; fi
C1="$TMP/cfg"; H2="$TMP/h2"; mkdir -p "$H2"
CLAUDE_CONFIG_DIR="$C1" HOME="$H2" bash "$INST" >"$TMP/i3" 2>&1; r=$?
if [ "$r" = 0 ] && [ -f "$C1/agents/ripwire-locator.md" ] && [ ! -e "$H2/.claude/agents" ]; then ok "CLAUDE_CONFIG_DIR is honoured"; else no "CLAUDE_CONFIG_DIR: rc $r"; fi
H3="$TMP/h3"; mkdir -p "$H3/.claude/agents"; printf -- '---\nname: ripwire-locator\ndescription: mine\n---\nmy own\n' >"$H3/.claude/agents/ripwire-locator.md"
cp "$H3/.claude/agents/ripwire-locator.md" "$TMP/mine"
HOME="$H3" bash "$INST" >"$TMP/i4" 2>&1; r=$?
if [ "$r" = 0 ] && cmp -s "$H3/.claude/agents/ripwire-locator.md" "$TMP/mine" && grep -q 'kept.*ripwire-locator' "$TMP/i4"; then
    ok "a user's own file at that path is kept, and the output says so"
else
    no "a user's own file was not kept (rc $r): $( grep ripwire-locator "$TMP/i4" | head -2 )"
fi
H4="$TMP/h4"; mkdir -p "$H4/.claude/agents"; ln -s "$TMP/nonexistent/ripwire-locator.md" "$H4/.claude/agents/ripwire-locator.md"
HOME="$H4" bash "$INST" >"$TMP/i5" 2>&1; r=$?
if [ "$r" = 0 ] && cmp -s "$H4/.claude/agents/ripwire-locator.md" "$AGENT"; then ok "a dangling link at that path is replaced"; else no "a dangling link was not replaced (rc $r)"; fi
H5="$TMP/h5"; mkdir -p "$H5"
AGENTS_HOME="$H5/agentsroot" HOME="$H5" bash "$INST" --codex >"$TMP/i6" 2>&1; r=$?
if [ "$r" = 0 ] && [ ! -e "$H5/.claude" ] && ! grep -q 'ripwire-locator' "$TMP/i6"; then ok "--codex installs no Claude agent"; else no "--codex: rc $r or it touched ~/.claude"; fi
H6="$TMP/h6"; mkdir -p "$H6"
HOME="$H6" bash "$INST" "$TMP/explicit" >"$TMP/i7" 2>&1; r=$?
if [ "$r" = 0 ] && [ ! -e "$H6/.claude" ] && ! grep -q 'ripwire-locator' "$TMP/i7"; then ok "an explicit PATH install installs no Claude agent"; else no "explicit PATH: rc $r or it touched ~/.claude"; fi
STAGE="$TMP/stage/skills"; mkdir -p "$STAGE"; cp "$INST" "$STAGE/install.sh"; cp -R "$ROOT/skills/ripwire-router" "$STAGE/"
H7="$TMP/h7"; mkdir -p "$H7"
HOME="$H7" bash "$STAGE/install.sh" >"$TMP/i8" 2>&1; r=$?
if [ "$r" = 0 ] && [ -e "$H7/.claude/skills/ripwire-router" ] && [ ! -e "$H7/.claude/agents/ripwire-locator.md" ]; then
    ok "a checkout without the agent file still installs its skills, rc 0"
else
    no "a checkout without the agent file: rc $r: $( tail -n 2 "$TMP/i8" )"
fi

echo "(E) wrap claude: the delegation sentence"
body(){ sed -n '/^# --- paste into /,/^# --- end paste ---$/p' | sed '1d;$d'; }
"$BIN" wrap claude --force >"$TMP/w_on" 2>/dev/null
RIPWIRE_NO_LOCATOR_ROUTE=1 "$BIN" wrap claude --force >"$TMP/w_off" 2>/dev/null
body <"$TMP/w_on" >"$TMP/b_on"
c="$( grep -cF -- "$SENTENCE" "$TMP/b_on" )"
if [ "$c" = 1 ]; then ok "the paste block carries the sentence once"; else no "the sentence appears $c times in the paste block"; fi
if grep -F -- "$SENTENCE" "$TMP/b_on" | grep -q '^  signatures\. Paste symbol/file names'; then ok "it rides on the orient line (no new line)"; else no "it is not on the orient line"; fi
bl="$( wc -l <"$TMP/b_on" | tr -d ' ' )"
if [ "$bl" = 20 ]; then ok "the paste block is still 20 lines"; else no "the paste block is $bl lines"; fi
sb="$( printf '%s' "$SENTENCE" | wc -c | tr -d ' ' )"
if [ "$sb" -le 220 ]; then ok "the sentence is $sb B (cap 220: it rides every main-thread request)"; else no "the sentence is $sb B, over 220"; fi
leaked=""
for a in codex cursor windsurf gemini opencode openclaw hermes aider; do
    "$BIN" wrap "$a" --force 2>/dev/null | body >"$TMP/b_$a"
    [ -s "$TMP/b_$a" ] || leaked="$leaked $a(empty)"
    if grep -q 'ripwire-locator' "$TMP/b_$a"; then leaked="$leaked $a"; fi
done
if [ -z "$leaked" ]; then ok "none of the other 8 agents' paste blocks names the locator"; else no "leaked or empty:$leaked"; fi
offOrient="$( grep -c '^  signatures\. Paste symbol/file names' "$TMP/w_off" )"
offLocator="$( grep -c 'ripwire-locator' "$TMP/w_off" )"
if [ "$offOrient" = 1 ] && [ "$offLocator" = 0 ]; then
    ok "RIPWIRE_NO_LOCATOR_ROUTE=1: the orient line is printed and no locator text anywhere in wrap claude"
else
    no "RIPWIRE_NO_LOCATOR_ROUTE=1: orient line printed $offOrient times, locator named $offLocator times (want 1 and 0)"
fi
SENTENCE="$SENTENCE" python3 -I -c '
import os, sys
on, off = open(sys.argv[1], "rb").read(), open(sys.argv[2], "rb").read()
s = (" " + os.environ["SENTENCE"]).encode()
sys.exit(0 if on.count(s) == 1 and on.replace(s, b"") == off else 1)' "$TMP/w_on" "$TMP/w_off"
if [ $? -eq 0 ]; then ok "A/B: the off output is the on output minus exactly ' <sentence>', byte for byte"; else no "A/B: the off output differs from the on output by more than the sentence"; fi

echo "(F) the SessionStart primer"
REPO="$TMP/repo"; mkdir -p "$REPO"; printf 'def f():\n    return 1\n' >"$REPO/a.py"
git -C "$REPO" init -q && git -C "$REPO" add a.py && git -C "$REPO" -c user.name=t -c user.email=t@t commit -qm i || { echo "locatoragentcheck: fixture repo"; exit 2; }
PB="$TMP/pbin"; mkdir -p "$PB"; ln -s "$BIN" "$PB/ripwire"
FH="$TMP/fh"; mkdir -p "$FH" "$TMP/ss1" "$TMP/ss2"
ss(){ printf '{"session_id":"%s","cwd":"%s","source":"startup"}' "$1" "$REPO" \
      | env HOME="$FH" RIPWIRE_METER_ARM=treatment PATH="$PB:$PATH" TMPDIR="$2" "${@:3}" bash "$HOOK" --session-start \
      | "$JQ" -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
s_on="$( ss lc1on "$TMP/ss1" )"
s_off="$( ss lc1off "$TMP/ss2" RIPWIRE_NO_LOCATOR_ROUTE=1 )"
case "$s_on" in *"$SENTENCE"*) ok "the primer carries the sentence";; *) no "the primer lacks the sentence (len ${#s_on})";; esac
if [ -n "$s_off" ] && [ "${s_off#*ripwire-locator}" = "$s_off" ]; then ok "the primer drops it under RIPWIRE_NO_LOCATOR_ROUTE=1"; else no "the primer under RIPWIRE_NO_LOCATOR_ROUTE=1 is empty or still names the locator"; fi

echo "(G) subagent-facing texts do not carry it"
sa="$( "$JQ" -cn --arg c "$REPO" '{session_id:"s",transcript_path:"/x/s.jsonl",cwd:$c,hook_event_name:"SubagentStart",agent_id:"a",agent_type:"Explore"}' \
      | env HOME="$FH" PATH="$PB:$PATH" bash "$HOOK" --subagent-start )"
if [ -n "$sa" ] && [ "${sa#*ripwire-locator}" = "$sa" ]; then ok "the SubagentStart note does not name the locator"; else no "the SubagentStart note is empty or names the locator"; fi
if ! grep -q 'ripwire-locator' "$ROOT/skills/ripwire-orient/subagent-brief.md"; then ok "the three-moment brief block does not name the locator"; else no "subagent-brief.md names the locator"; fi

echo "(H) the orient skill"
if grep -q 'ripwire-locator' "$ROOT/skills/ripwire-orient/SKILL.md" && grep -q 'edit ranges' "$ROOT/skills/ripwire-orient/SKILL.md"; then
    ok "skills/ripwire-orient/SKILL.md routes a main-thread lookup to the locator for edit ranges"
else
    no "skills/ripwire-orient/SKILL.md does not name the locator route"
fi

echo "(I) the opt-out"
optout()
{
    # optout LABEL HOME [installer args...] -> the agent path must not exist, the skills must, rc 0, and the run says so
    _l="$1"; _h="$2"; shift 2
    mkdir -p "$_h"
    HOME="$_h" bash "$INST" "$@" >"$TMP/o_$_l" 2>&1; _r=$?
    if [ "$_r" = 0 ] && [ -e "$_h/.claude/skills/ripwire-orient" ] && [ ! -e "$_h/.claude/agents/ripwire-locator.md" ] \
       && grep -q 'skipped subagent ripwire-locator' "$TMP/o_$_l"; then
        ok "$_l: skills installed, no agent file written, the run says it skipped it"
    else
        no "$_l: rc $_r, or skills missing, or the agent was written: $( grep -m1 ripwire-locator "$TMP/o_$_l" )"
    fi
}
optout "--no-locator-agent" "$TMP/o1" --no-locator-agent
mkdir -p "$TMP/o2"
RIPWIRE_NO_LOCATOR_AGENT=1 optout "RIPWIRE_NO_LOCATOR_AGENT=1" "$TMP/o2"
O3="$TMP/o3"; mkdir -p "$O3/.claude/agents"; cp "$TMP/mine" "$O3/.claude/agents/ripwire-locator.md"
HOME="$O3" bash "$INST" --no-locator-agent >"$TMP/o_3" 2>&1; r=$?
if [ "$r" = 0 ] && cmp -s "$O3/.claude/agents/ripwire-locator.md" "$TMP/mine"; then ok "the opt-out leaves a user's own file at that path untouched"; else no "the opt-out changed a user's own file (rc $r)"; fi
if [ -f "$H1/.claude/agents/ripwire-locator.md" ]; then ok "the default (no flag, no variable) wrote it: arm (D)"; else no "the default install wrote no agent file"; fi
for d in INSTALL.md README.md; do
    if grep -q -- '--no-locator-agent' "$ROOT/$d" && grep -q 'RIPWIRE_NO_LOCATOR_AGENT=1' "$ROOT/$d"; then ok "$d documents --no-locator-agent and RIPWIRE_NO_LOCATOR_AGENT=1"; else no "$d does not document the opt-out"; fi
done
for d in scripts/install.sh install.sh; do
    if grep -q 'RIPWIRE_NO_LOCATOR_AGENT' "$ROOT/$d" && ! grep -q 'env -i\|-u RIPWIRE_NO_LOCATOR_AGENT' "$ROOT/$d"; then ok "$d names the variable and does not scrub it"; else no "$d does not name RIPWIRE_NO_LOCATOR_AGENT, or scrubs the environment"; fi
done

if [ "$fail" -eq 0 ]; then echo "locatoragentcheck: all arms PASS"; else echo "locatoragentcheck: FAILED"; fi
exit "$fail"
