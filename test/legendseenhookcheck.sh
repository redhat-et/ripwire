#!/usr/bin/env bash
# legendseenhookcheck.sh — gate for hooks/ripwire-legend-seen.sh, the Claude Code hook that keeps a session's
# --legend-seen=FILE: PostToolUse adds the entry hashes of the stdout the agent RECEIVED, PreToolUse names the file.
#
# What it must never do, and the arms that hold it:
#   (a) touch the session's first ripwire call (it holds nothing), or record output the agent did not receive whole
#       (over the display limit, interrupted, or cut by a pipe — a cut is harvested AFTER the pipe)
#   (b) rewrite anything but the binary word's tail: ` --legend-seen=FILE` right after it, every other byte and every
#       other tool_input field kept, and never a permissionDecision (the user's permission flow decides)
#   (c) keep a FILE across SessionStart (any source), PreCompact, or a compact_boundary it did not see
#   (d) hand a subagent its parent's FILE (same session_id, a different context)
#   (e) touch a command it must not: not ripwire, a posture or the dictionary itself, --json, a server, help, wrap
#   (f) act at all under RIPWIRE_LEGEND_SEEN=0
#   (g) name the flag to a binary too old to take it (rc 1 is the one failure a hook may never cause)
# and (h) the rewritten call is the point: rc 0, a smaller answer, rows byte-identical to the untouched call.
#
# Usage: test/legendseenhookcheck.sh [PATH_TO_RIPWIRE]. Never touches the real ~/.claude or ~/.ripwire.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_LEGEND_SEEN RIPWIRE_LEGEND_STATE BASH_MAX_OUTPUT_LENGTH
HOOK="$ROOT/hooks/ripwire-legend-seen.sh"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$HOOK" ] || { echo "legendseenhookcheck: $HOOK missing or not executable"; exit 2; }
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "legendseenhookcheck: no ripwire binary at $BIN"; exit 2; }
JQ="$( command -v jq )" || { echo "legendseenhookcheck: jq is required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
PBIN="$TMP/pbin"; mkdir -p "$PBIN"; ln -s "$BIN" "$PBIN/ripwire"; ln -s "$JQ" "$PBIN/jq"
HPATH="$PBIN:/usr/bin:/bin"
STATE="$TMP/state"
TRANSCRIPT="$TMP/transcript.jsonl"; : >"$TRANSCRIPT"
REPO="$TMP/repo"; mkdir -p "$REPO"
cat >"$REPO/app.py" <<'SRC'
def helper(x):
    return x + 1

def caller_one():
    return helper(1)

def caller_two():
    return helper(2) + caller_one()

def top():
    return caller_two()
SRC

hook()
{
    _j="$1"; shift
    HOUT="$( printf '%s' "$_j" | env HOME="$TMP/home" PATH="$HPATH" RIPWIRE_LEGEND_STATE="$STATE" "$@" bash "$HOOK" )"
    printf '%s' "$?" >"$TMP/hrc"
    printf '%s' "$HOUT"
}
prejson()
{
    jq -cn --arg s "$1" --arg a "$2" --arg c "$3" --arg cwd "$REPO" --arg t "$TRANSCRIPT" \
        '{session_id:$s,transcript_path:$t,cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",
          tool_input:{command:$c,description:"run ripwire",timeout:120000}} + (if $a=="" then {} else {agent_id:$a,agent_type:"Explore"} end)'
}
# postjson SESSION AGENT COMMAND STDOUTFILE [INTERRUPTED]
postjson()
{
    jq -cn --arg s "$1" --arg a "$2" --arg c "$3" --rawfile o "$4" --argjson i "${5:-false}" --arg cwd "$REPO" --arg t "$TRANSCRIPT" \
        '{session_id:$s,transcript_path:$t,cwd:$cwd,hook_event_name:"PostToolUse",tool_name:"Bash",
          tool_input:{command:$c,description:"run ripwire"},
          tool_response:{stdout:$o,stderr:"",interrupted:$i,isImage:false}} + (if $a=="" then {} else {agent_id:$a,agent_type:"Explore"} end)'
}
evjson(){ jq -cn --arg s "$1" --arg ev "$2" --arg src "${3:-}" --arg t "$TRANSCRIPT" '{session_id:$s,transcript_path:$t,cwd:"/",hook_event_name:$ev,source:$src,trigger:"auto"}'; }
# step SESSION AGENT COMMAND [VAR=VAL…] — PreToolUse, run the (possibly rewritten) command, PostToolUse
step()
{
    _s="$1"; _a="$2"; _c="$3"; shift 3
    PRE="$( hook "$( prejson "$_s" "$_a" "$_c" )" "$@" )"
    RUNCMD="$( printf '%s' "$PRE" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null )"
    [ -n "$RUNCMD" ] || RUNCMD="$_c"
    ( cd "$REPO" && env PATH="$HPATH" bash -c "$RUNCMD" ) >"$TMP/o" 2>"$TMP/e"; RC=$?
    OUTB="$( wc -c <"$TMP/o" | tr -d ' ' )"
    POST="$( hook "$( postjson "$_s" "$_a" "$RUNCMD" "$TMP/o" )" "$@" )"
}
injected(){ printf '%s' "$PRE" | jq -e '.hookSpecificOutput.updatedInput.command' >/dev/null 2>&1; }
seenfile(){ printf '%s/%s/%s/seen' "$STATE" "$1" "${2:-main}"; }
strip(){ python3 -c 'import re,sys; d=open(sys.argv[1]).read(); d=re.sub(r"<!--.*?-->","",d,flags=re.S); print(re.sub(r"est_tokens=\"\d+\"","",d))' "$1"; }

C1="ripwire . --callers=helper"
C2="ripwire . --impact=helper"

# ═══ (a) first call untouched; what it received is recorded ═══════════════════════════════════════════════════════
step S1 "" "$C1"
if [ -z "$PRE" ] && [ "$( cat "$TMP/hrc" )" -eq 0 ]; then ok "(a) first call: PreToolUse prints nothing"; else no "(a) first call touched: $PRE"; fi
if [ "$RC" -eq 0 ] && [ -s "$( seenfile S1 )" ]; then ok "(a) PostToolUse recorded $( wc -l <"$( seenfile S1 )" | tr -d ' ' ) entry hash(es) from the received answer"
else no "(a) no FILE after the first call (rc=$RC)"; fi
"$BIN" --legend-dict=seen <"$TMP/o" >"$TMP/want.seen"
if cmp -s "$TMP/want.seen" "$( seenfile S1 )"; then ok "(a) FILE is exactly --legend-dict=seen of the received stdout"; else no "(a) FILE differs from the binary's own scan"; fi

# ═══ (b)(h) the second call names FILE; the answer shrinks and its rows do not move ═══════════════════════════════
cp "$TMP/o" "$TMP/plain1"
step S1 "" "$C1"
WANT="ripwire --legend-seen=$( seenfile S1 ) . --callers=helper"
if [ "$RUNCMD" = "$WANT" ]; then ok "(b) second call rewritten to: ripwire --legend-seen=<state>/S1/main/seen . --callers=helper"; else no "(b) want [$WANT] got [$RUNCMD]"; fi
if printf '%s' "$PRE" | jq -e '(.hookSpecificOutput | has("permissionDecision") | not) and .hookSpecificOutput.updatedInput.description=="run ripwire" and .hookSpecificOutput.updatedInput.timeout==120000' >/dev/null 2>&1; then
    ok "(b) no permissionDecision; updatedInput keeps every other tool_input field"
else no "(b) permission or tool_input contract broken: $PRE"; fi
if [ "$RC" -eq 0 ] && [ "$OUTB" -gt 0 ] && [ "$OUTB" -lt "$( wc -c <"$TMP/plain1" | tr -d ' ' )" ] && [ "$( strip "$TMP/o" )" = "$( strip "$TMP/plain1" )" ]; then
    ok "(h) rewritten call: rc 0, $OUTB B against $( wc -c <"$TMP/plain1" | tr -d ' ' ) B, rows byte-identical"
else no "(h) rewritten call rc=$RC bytes=$OUTB"; fi
step S1 "" "$C2"
if injected && [ "$RC" -eq 0 ] && [ "$OUTB" -gt 0 ]; then ok "(b)(h) a different verb is rewritten too (no tiers: per definition), rc 0"; else no "(b) --impact: [$RUNCMD] rc=$RC"; fi
# quoting: everything after the binary word passes through byte for byte
for tail in " . --callers=helper | head -c 100000" " . --callers='helper' && echo done" ' . --grep="return x" | wc -c'; do
    PRE="$( hook "$( prejson S1 "" "ripwire$tail" )" )"
    got="$( printf '%s' "$PRE" | jq -r '.hookSpecificOutput.updatedInput.command // empty' )"
    if [ "$got" = "ripwire --legend-seen=$( seenfile S1 )$tail" ]; then ok "(b) passes through byte for byte:$tail"; else no "(b) mangled: [$got]"; fi
done

# ═══ (c) forgetting ═══════════════════════════════════════════════════════════════════════════════════════════════
for ev in "SessionStart startup" "SessionStart compact" "SessionStart resume" "SessionStart clear" "PreCompact "; do
    set -- $ev
    step S1 "" "$C1"; injected || no "(c) precondition: not injecting before $ev"
    hook "$( evjson S1 "$1" "${2:-}" )" >/dev/null
    if [ ! -e "$( seenfile S1 )" ]; then ok "(c) $ev forgets FILE"; else no "(c) $ev left FILE behind"; fi
    step S1 "" "$C1"
    if ! injected; then ok "(c) after $ev: the next call is untouched"; else no "(c) after $ev: [$RUNCMD]"; fi
done
step S1 "" "$C1"; injected || no "(c) precondition: not injecting before the transcript arm"
printf '%s\n' '{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}' >>"$TRANSCRIPT"
step S1 "" "$C1"
if ! injected; then ok "(c) a compact_boundary in transcript_path alone forgets FILE"; else no "(c) transcript compaction ignored"; fi
step S1 "" "$C1"
if injected; then ok "(c) ... and the next received answer starts a new FILE"; else no "(c) never resumed after the transcript compaction"; fi

# ═══ (d) a subagent has its own context ═══════════════════════════════════════════════════════════════════════════
step S1 "agent-7" "$C1"
if ! injected && [ -s "$( seenfile S1 agent-7 )" ]; then ok "(d) subagent: untouched first call, its own FILE"; else no "(d) subagent inherited the parent's FILE: [$RUNCMD]"; fi

# ═══ (e) commands it must not touch ═══════════════════════════════════════════════════════════════════════════════
for c in "echo ripwire . --callers=helper" "ripwire . --callers=helper --json" "ripwire . --callers=helper --legend=full" \
         "ripwire --legend-dict=seen" "ripwire . --mcp" "cd . && ripwire . --callers=helper" "env X=1 ripwire . --callers=helper" \
         "ripwire --help" "ripwire --version" "ripwire wrap claude" "ripwire"; do
    PRE="$( hook "$( prejson S1 "" "$c" )" )"
    if [ -z "$PRE" ]; then ok "(e) untouched: $c"; else no "(e) touched: $c -> $PRE"; fi
done

# ═══ (f) opt-out ══════════════════════════════════════════════════════════════════════════════════════════════════
rm -rf "$STATE"
step S2 "" "$C1" RIPWIRE_LEGEND_SEEN=0
step S2 "" "$C1" RIPWIRE_LEGEND_SEEN=0
if [ -z "$PRE" ] && [ -z "$POST" ] && [ ! -e "$STATE" ]; then ok "(f) RIPWIRE_LEGEND_SEEN=0: no output, no state"; else no "(f) opt-out leaked: pre=[$PRE] state=$( ls "$STATE" 2>/dev/null )"; fi

# ═══ (a) what was not received whole is not recorded ══════════════════════════════════════════════════════════════
rm -rf "$STATE"
( cd "$REPO" && env PATH="$HPATH" ripwire . --callers=helper ) >"$TMP/full" 2>/dev/null
head -c 40000 /dev/zero | tr '\0' 'x' >"$TMP/big"; cat "$TMP/full" >>"$TMP/big"
hook "$( postjson S3 "" "$C1" "$TMP/big" )" >/dev/null
if [ ! -s "$( seenfile S3 )" ]; then ok "(a) output over the display limit is not recorded"; else no "(a) recorded output the agent saw only part of"; fi
hook "$( postjson S3 "" "$C1" "$TMP/full" true )" >/dev/null
if [ ! -s "$( seenfile S3 )" ]; then ok "(a) interrupted output is not recorded"; else no "(a) recorded interrupted output"; fi
head -c 300 "$TMP/full" >"$TMP/cut"
hook "$( postjson S3 "" "$C1 | head -c 300" "$TMP/cut" )" >/dev/null
n_cut=$( { cat "$( seenfile S3 )" 2>/dev/null || true; } | wc -l | tr -d ' ' ); n_full=$( "$BIN" --legend-dict=seen <"$TMP/full" | wc -l | tr -d ' ' )
n_want=$( "$BIN" --legend-dict=seen <"$TMP/cut" | wc -l | tr -d ' ' )
if [ "$n_cut" -eq "$n_want" ] && [ "$n_cut" -lt "$n_full" ]; then ok "(a) a piped cut records exactly what it carried ($n_cut of the whole answer's $n_full hashes)"
else no "(a) a cut recorded $n_cut hashes, it carried $n_want, the whole answer $n_full"; fi

# ═══ (g) a binary too old for the flag gets nothing ═══════════════════════════════════════════════════════════════
OLD="$TMP/oldbin"; mkdir -p "$OLD"
printf '#!/bin/sh\ncase "$*" in *--legend-dict=seen*) echo "unknown form" >&2; exit 1 ;; esac\nexec %s "$@"\n' "$BIN" >"$OLD/ripwire"; chmod +x "$OLD/ripwire"
mkdir -p "$( dirname "$( seenfile S4 )" )"; cp "$TMP/want.seen" "$( seenfile S4 )"
CC="$( grep -c -F '"subtype":"compact_boundary"' "$TRANSCRIPT" )"; printf '%s\n' "$CC" >"$STATE/S4/main/compacts"
PRE="$( printf '%s' "$( prejson S4 "" "$OLD/ripwire . --callers=helper" )" | env HOME="$TMP/home" PATH="$HPATH" RIPWIRE_LEGEND_STATE="$STATE" bash "$HOOK" )"
if [ -z "$PRE" ]; then ok "(g) a binary that does not take --legend-dict=seen gets no --legend-seen="; else no "(g) injected into an old binary: $PRE"; fi
PRE="$( printf '%s' "$( prejson S4 "" "$BIN . --callers=helper" )" | env HOME="$TMP/home" PATH="$HPATH" RIPWIRE_LEGEND_STATE="$STATE" bash "$HOOK" )"
if printf '%s' "$PRE" | jq -e '.hookSpecificOutput.updatedInput.command' >/dev/null 2>&1; then ok "(g) control: the same FILE with this binary IS named"; else no "(g) control failed: the current binary was not given the flag"; fi
# a state path that would need quoting is never written into a command
SP="$TMP/sp ace"; mkdir -p "$SP/S5/main"; cp "$TMP/want.seen" "$SP/S5/main/seen"; printf '%s\n' "$CC" >"$SP/S5/main/compacts"
PRE="$( printf '%s' "$( prejson S5 "" "$C1" )" | env HOME="$TMP/home" PATH="$HPATH" RIPWIRE_LEGEND_STATE="$SP" bash "$HOOK" )"
if [ -z "$PRE" ]; then ok "(b) a state path holding a space is never spliced into a command"; else no "(b) spliced an unquotable path: $PRE"; fi

# ═══ (i) skills/install.sh --hook registers it on the four events, once, and a second run does not double it ═══════
IH="$TMP/ihome"; mkdir -p "$IH"
HOME="$IH" PATH="$HPATH" bash "$ROOT/skills/install.sh" --hook >"$TMP/i1" 2>&1; r1=$?
HOME="$IH" PATH="$HPATH" bash "$ROOT/skills/install.sh" --hook >"$TMP/i2" 2>&1; r2=$?
iset="$IH/.claude/settings.json"
counts="$( jq -r '[("PreToolUse","PostToolUse","SessionStart","PreCompact") as $k | [(.hooks[$k] // [])[] | .hooks[]? | select(.command | test("ripwire-legend-seen[.]sh"))] | length] | map(tostring) | join(" ")' "$iset" 2>/dev/null )"
if [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$counts" = "1 1 1 1" ]; then ok "(i) --hook registers PreToolUse/PostToolUse/SessionStart/PreCompact once each, twice run"
else no "(i) --hook registration: rc=$r1/$r2 counts=[$counts]"; fi
if jq -e '([.hooks.PreToolUse[] | select(any(.hooks[]?; .command | test("ripwire-legend-seen"))) | .matcher] == ["Bash"]) and ([.hooks.PreCompact[] | select(any(.hooks[]?; .command | test("ripwire-legend-seen"))) | .matcher] == ["*"])' "$iset" >/dev/null 2>&1 \
   && grep -q "REWRITES a ripwire Bash command" "$TMP/i1"; then
    ok "(i) matchers Bash / *, and the installer says it rewrites a command before it does"
else no "(i) matcher or disclosure wrong"; fi

if [ "$fail" -eq 0 ]; then echo "legendseenhookcheck: all arms PASS"; exit 0; fi
echo "legendseenhookcheck: FAILURES"; exit 1
