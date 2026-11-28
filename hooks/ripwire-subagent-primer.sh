#!/usr/bin/env bash
# hooks/ripwire-subagent-primer.sh — OPT-IN Claude Code SubagentStart hook. Puts the two-line ripwire brief into the
# context of every subagent the session spawns: orient with `--for` before reading; after the LAST edit, commit and run
# `--quality-delta=BASE..HEAD` then `--test-gate` before reporting. Advisory-only; it cannot block a subagent and degrades to silence on any error.
#
# WHY THIS EXISTS (lane AR1, 2026-11-19). Lane SUB1 mined the 25 product-implementing subagents of one orchestrator
# session: orientation was 40.6% of their input tokens and each orientation token was re-read ~165 times, yet they
# made a median of ONE ripwire navigation call before their first edit (12 of 25 none). AR1 then checked what reached
# those contexts (83 subagent transcripts of that session, counts only):
#   - no hook output at all. SessionStart does not fire for a subagent (2 session-start meter rows for 83 subagents)
#     and UserPromptSubmit fires on the PARENT side only. PreToolUse DOES fire inside subagents (7,882 meter rows
#     for 433 eligible main-session calls), but its advice path was retired on 2026-09-02, so it says nothing there.
#   - the GENERIC guidance did reach them and was not acted on: the ripwire use-when protocol from CLAUDE.md (81/83),
#     the MCP server's instructions (83/83), and 33 ripwire MCP tools listed as deferred (83/83; 0 of them loaded).
#   - 4 of the 83 briefs carried a sentence telling the subagent to orient with ripwire.
# The owner's prior evidence (11-19, an unrecorded earlier run): when the orchestrator was TOLD to tell its subagents
# "orient with ripwire, check with --quality-delta", the run used "about half the tokens". So the hypothesis is a
# short, specific instruction from the user at the start of a fresh context, not more catalogue text.
#
# WHY THIS IS NOT THE RETIRED NUDGE (hooks/ripwire-nudge.sh §RETIRED). The nudge spoke MID-TASK, after the agent had
# already chosen grep or Read, with a verb name and no argument, and a randomized A/B found it inert. This speaks ONCE,
# at the start of an EMPTY context, before the first tool is chosen, with two runnable commands and the order to run
# them in. That moment is the one the 2026-08-10 finding credited (concentration at the start of a context), and the
# one the main-session SessionStart primer already uses. It is still a hypothesis: docs/EVALS.md registers the A/B.
#
# WHY SubagentStart AND NOT A REWRITE OF THE Agent TOOL'S PROMPT. A PreToolUse hook on `Agent` could append the same
# lines to `tool_input.prompt` through `updatedInput`, but (verified against code.claude.com/docs/en/hooks, 11-19):
# `updatedInput` replaces the whole input; with no permissionDecision, auto mode can DENY the changed call ("a hook
# changed this call's input after auto mode reviewed it") and `Agent` is not among the tools exempt from that; with
# "allow" the hook would be approving every subagent launch, which no ripwire hook does. SubagentStart is the
# documented context-only event: it "can't block subagent creation, but [it] can inject context into the subagent",
# added "at the start of its conversation, before its first prompt", and a re-run does not duplicate it or break the
# subagent's prompt cache. If the A/B finds that the text works only when it is IN the brief, the rewrite is the next
# arm, built then, with its permission behaviour measured.
#
# PROMPT-INJECTION POSTURE. The injected text is a compile-time constant below. Nothing from the payload, the
# repository or the brief reaches it: not the cwd, not a file name, not the agent type. jq --arg does the quoting.
#
# OFF SWITCH AND ARMS. RIPWIRE_SUBAGENT_PRIMER (env) wins over `subagent_primer=` in ~/.ripwire/meter.conf, which wins
# over the default `on` (installing the hook is the opt-in):
#   on | 1        every subagent gets the primer
#   off | 0       the hook does nothing: no text, no row
#   auto          randomized per SUBAGENT: cksum(agent_id) even -> treatment, odd -> control. Per subagent, not per
#                 session: subagents inherit their parent's session_id, and the session-hashed meter arm put the
#                 whole SUB1 session (all 83 subagents) in control — a per-session split cannot compare subagents
#                 within one orchestrator run.
# Anything else is read as `off`: an unknown value is a typo, and a typo must not start an experiment.
#
# ONE ROW PER DECISION, NEVER TEXT. With counting on (RIPWIRE_SUBAGENT_METER != 0) each SubagentStart appends one row to
# ${RIPWIRE_SUBAGENT_LOG:-~/.ripwire/subagent_primer.jsonl}: {v, ts, session, agent_id, agent_type, arm, delivered,
# reason, bytes, brief, brief_reason} (v 2: brief = 1 when the task brief was delivered; brief_reason = why or why not). session and agent_id are raw because the readout joins them to subagents/agent-<id>.jsonl. A harness
# that sets RIPWIRE_METER_FIXTURE=1 without naming RIPWIRE_SUBAGENT_LOG writes nothing (the nudge's §FIXTURE rule).
#
# THE TASK BRIEF (lane SUBAGENT-PRIMER, 2026-11-27; BRIEF-LESSONS 3). When the hook can see the subagent's task, the
# subagent gets `ripwire <toplevel> --brief=<task>` (layout, build commands quoted from manifests, entries, the task's act
# ranges, edges, where-else, conventions, the three-moment block: 3.5/5/7 KB by size class) instead of the two steps,
# so it starts oriented instead of being told to orient. ABSTAIN-ONLY: whenever the task is not known for certain, the
# answer is the two-step text below, byte for byte, as before this lane.
#   - WHERE THE TASK COMES FROM. A SubagentStart payload carries no prompt (code.claude.com/docs/en/hooks.md, read
#     11-27: common fields + agent_id, agent_type), and its transcript_path is the parent's, which "may lag". So the
#     installer also registers this script as a PreToolUse hook on Agent|Task, which fires in the PARENT before the
#     spawn: it stashes {ts, type, prompt} under ${TMPDIR}/ripwire-subagent-task-<uid>/<session>/<tool_use_id> (umask
#     077), prints nothing and writes no row. The subagent's own hooks carry its parent's session_id (AR1, above).
#   - WHICH STASH IS THIS SUBAGENT'S. The stashes of this session younger than 120 s whose subagent_type equals the
#     payload's agent_type. Exactly one -> claimed (removed) and used. None (a resume, a teammate message, a spawn the
#     PreToolUse half never saw) or two or more (a parallel fan-out of one type: which is which is unknowable) -> the
#     two-step text, and nothing is claimed. A prompt over 4096 B, or one that already carries a <brief> page, is
#     stashed as INELIGIBLE, so it still counts as a candidate and can never lend its slot to another spawn.
#   - THE ALLOW-LIST SHAPE. The brief is used only when ripwire exits 0 inside the deadline and stdout is ONE
#     `<brief ...>...</brief>` document with a <next> section, at most 9000 B. Anything else -> the two-step text.
#   - THE DEADLINE. RIPWIRE_SUBAGENT_BRIEF_MS (default 8000, clamped to 500..12000); the installer registers the
#     SubagentStart entry with a 15 s timeout so the fallback still lands. On overrun the ripwire child is killed.
#   - THE KILL SWITCH. RIPWIRE_SUBAGENT_BRIEF=0|off (or subagent_brief=off in meter.conf; the env wins; any value but
#     on|1 reads as off) -> no stash is written and every subagent gets the two-step text: today's behaviour exactly.
#   - POSTURE. The two-step text stays a constant. The brief is ripwire's own answer for the task the orchestrator wrote,
#     the same bytes the subagent would get by running the command itself; the task text reaches ripwire as one argv
#     element and is never evaluated by the shell. The stash holds the prompt for at most 120 s, readable by the user only.
#   - CLI, MCP and this hook share one composer: this runs the CLI `--brief`, whose page the MCP `brief` tool also prints.
#
# Contract (verified against https://code.claude.com/docs/en/hooks, 2026-11-19): SubagentStart JSON arrives on stdin with
# the common fields plus {agent_id, agent_type}; context = exit 0 plus
#   {"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"..."}}
# PreToolUse (the stash half): tool_name, tool_input.{prompt, subagent_type}, tool_use_id; it prints nothing.
# Every path exits 0. Gate: test/subagentprimercheck.sh. Install: skills/install.sh --hook-subagent-primer.
set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$( cat )" || exit 0

event="$( printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null )" || exit 0
case "$event" in
    SubagentStart) ;;
    PreToolUse)
        printf '%s' "$input" | jq -e '(.tool_name == "Agent" or .tool_name == "Task") and (.tool_input.prompt | type == "string")'             >/dev/null 2>&1 || exit 0 ;;
    *) exit 0 ;;
esac
dir="$( printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null )"
session="$( printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null )"
agentId="$( printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null )"
agentType="$( printf '%s' "$input" | jq -r '.agent_type // empty' 2>/dev/null )"
[ -n "$dir" ] || dir="$PWD"

# ---- the arm: env over meter.conf over the default. A shell read loop, no subprocess, as meter_init does. ----
mode="${RIPWIRE_SUBAGENT_PRIMER:-}"
briefMode="${RIPWIRE_SUBAGENT_BRIEF:-}"
conf="${HOME:-}/.ripwire/meter.conf"
if { [ -z "$mode" ] || [ -z "$briefMode" ]; } && [ -n "${HOME:-}" ] && [ -f "$conf" ]
then
    confMode=""; confBrief=""
    while IFS='=' read -r key value
    do
        case "$key" in
            subagent_primer) confMode="$( printf '%s' "$value" | tr -d '[:space:]' )" ;;
            subagent_brief)  confBrief="$( printf '%s' "$value" | tr -d '[:space:]' )" ;;
        esac
    done <"$conf"
    [ -n "$mode" ] || mode="$confMode"
    [ -n "$briefMode" ] || briefMode="$confBrief"
fi
[ -n "$mode" ] || mode="on"
[ -n "$briefMode" ] || briefMode="on"
case "$briefMode" in on|1) briefOn=1 ;; *) briefOn=0 ;; esac

# ---- the stash half (PreToolUse on Agent|Task, in the parent): remember the task for the spawn that follows ----
stashRoot="${TMPDIR:-/tmp}"; stashRoot="${stashRoot%/}/ripwire-subagent-task-$( id -u 2>/dev/null || echo 0 )"
sessKey="$( printf '%s' "$session" | tr -cd 'A-Za-z0-9._-' )"; sessKey="${sessKey:0:128}"   # no cut: the hook needs only bash, tr, jq
case "$sessKey" in ''|.|..) sessKey="" ;; esac
stashDir="$stashRoot/$sessKey"
# stashOk: the stash dirs exist, are real dirs (not symlinks) and are OURS. On a shared /tmp another user could pre-create the
# root; a prompt must never be written into, or a task read out of, a dir someone else controls.
stashOk()
{
    [ -d "$stashRoot" ] && [ ! -L "$stashRoot" ] && [ -O "$stashRoot" ] && [ -d "$stashDir" ] && [ ! -L "$stashDir" ] && [ -O "$stashDir" ]
}
kStashTtl=120
kTaskBytes=4096
if [ "$event" = "PreToolUse" ]
then
    case "$mode" in on|1|auto) ;; *) exit 0 ;; esac
    [ "$briefOn" = 1 ] || exit 0
    [ -n "$sessKey" ] || exit 0
    useKey="$( printf '%s' "$input" | jq -r '.tool_use_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9._-' )"; useKey="${useKey:0:128}"
    case "$useKey" in ''|.|..) exit 0 ;; esac
    # The root is checked BEFORE mkdir creates anything under it: a symlinked or foreign root must not even get a dir.
    if [ -e "$stashRoot" ] || [ -L "$stashRoot" ]; then { [ -d "$stashRoot" ] && [ ! -L "$stashRoot" ] && [ -O "$stashRoot" ]; } || exit 0; fi
    ( umask 077; mkdir -p "$stashDir" ) 2>/dev/null || exit 0
    stashOk || exit 0
    now="$( date +%s )"
    umask 077   # the stash file is the user's alone (the PreToolUse half writes nothing else)
    printf '%s' "$input" | jq -c --argjson ts "$now" --argjson cap "$kTaskBytes" '
        .tool_input as $i | ($i.prompt) as $p |
        { ts: $ts, type: (($i.subagent_type // "") | if . == "" then "general-purpose" else . end),
          eligible: (($p | utf8bytelength) > 0 and ($p | utf8bytelength) <= $cap and ($p | test("<brief ") | not)),
          prompt: $p }' >"$stashDir/.$useKey.tmp" 2>/dev/null \
        && mv -f "$stashDir/.$useKey.tmp" "$stashDir/$useKey" 2>/dev/null
    rm -f "$stashDir/.$useKey.tmp" 2>/dev/null
    exit 0
fi
case "$mode" in
    on|1) arm="treatment" ;;
    auto)
        [ -n "$agentId" ] || exit 0          # no id to randomize on: an `auto` window must not guess an arm
        sum="$( printf '%s' "$agentId" | cksum | awk '{print $1}' )"
        if [ $(( sum % 2 )) -eq 0 ]; then arm="treatment"; else arm="control"; fi ;;
    *) exit 0 ;;
esac

# ---- the row. Written before the delivery gates, so a subagent the primer could not reach still counts. ----
logRow()
{
    [ "${RIPWIRE_SUBAGENT_METER:-1}" = "0" ] && return 0
    dest="${RIPWIRE_SUBAGENT_LOG:-}"
    if [ -z "$dest" ]
    then
        [ -n "${RIPWIRE_METER_FIXTURE:-}" ] && return 0
        [ -n "${HOME:-}" ] || return 0
        dest="$HOME/.ripwire/subagent_primer.jsonl"
    fi
    mkdir -p "$( dirname "$dest" )" 2>/dev/null || return 0
    jq -cn --arg ts "$( date -u +%Y-%m-%dT%H:%M:%SZ )" --arg s "$session" --arg a "$agentId" --arg t "$agentType" \
        --arg arm "$arm" --argjson d "$1" --arg r "$2" --argjson b "$3" --argjson bf "${4:-0}" --arg br "${5:-n/a}" \
        '{v:2, ts:$ts, session:$s, agent_id:$a, agent_type:$t, arm:$arm, delivered:$d, reason:$r, bytes:$b, brief:$bf, brief_reason:$br}' \
        >>"$dest" 2>/dev/null || true
}

# ---- claim this subagent's stash (both arms claim it, so a control spawn never lends its task to a later one) ----
# Sets task (the prompt) and taskWhy: "" when the task is known and eligible, else the reason the brief abstains.
task=""; taskWhy="no-task"
if [ "$briefOn" != 1 ]
then
    taskWhy="off"
elif [ -n "$sessKey" ] && stashOk
then
    now="$( date +%s )"; picked=""; nPicked=0
    for f in "$stashDir"/*
    do
        [ -f "$f" ] || continue
        rec="$( cat "$f" 2>/dev/null )"
        ts="$( printf '%s' "$rec" | jq -r '.ts // 0' 2>/dev/null )"
        case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
        if [ $(( now - ts )) -gt "$kStashTtl" ]; then rm -f "$f" 2>/dev/null; continue; fi
        [ "$( printf '%s' "$rec" | jq -r '.type // empty' 2>/dev/null )" = "$agentType" ] || continue
        picked="$f"; nPicked=$(( nPicked + 1 ))
    done
    if [ "$nPicked" -gt 1 ]
    then
        taskWhy="ambiguous"
    elif [ "$nPicked" -eq 1 ]
    then
        rec="$( cat "$picked" 2>/dev/null )"; rm -f "$picked" 2>/dev/null
        if [ "$( printf '%s' "$rec" | jq -r '.eligible' 2>/dev/null )" = "true" ]
        then
            task="$( printf '%s' "$rec" | jq -r '.prompt // empty' 2>/dev/null )"
            [ -n "$task" ] && taskWhy="" || taskWhy="ineligible"
        else
            taskWhy="ineligible"
        fi
    fi
fi

# The control arm is counted and never spoken to.
[ "$arm" = "control" ] && { logRow 0 control 0 0 "${taskWhy:-control}"; exit 0; }

# The commands must be runnable where the subagent starts: a ripwire binary on PATH, and a git work tree. The answer
# must be `true`, not only exit 0 (a bare repository or a cwd inside .git prints `false` with status 0, #327).
command -v ripwire >/dev/null 2>&1 || { logRow 0 no-ripwire 0 0 "${taskWhy:-n/a}"; exit 0; }
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX
insideWorkTree="$( git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null )" || { logRow 0 not-git 0 0 "${taskWhy:-n/a}"; exit 0; }
[ "$insideWorkTree" = true ] || { logRow 0 not-git 0 0 "${taskWhy:-n/a}"; exit 0; }

# THE TEXT. A constant; <dir> and <task> are for the subagent to fill. Keep it to the two steps: its whole hypothesis
# is that a short, specific instruction is acted on where a long catalogue is not.
primer='ripwire — your user installed this for every subagent. Two steps, in this order:
1. Orient first: `ripwire <dir> --for="<your task; paste paths and symbols from the brief verbatim>"` (<dir> = the tree you will change). Read only the files it ranks, before any grep or whole-file read.
2. Before you report, after your LAST edit: commit, then run `ripwire <dir> --quality-delta=BASE..HEAD --legend=compact` (BASE = where your branch started; the range catches a regression made in two steps) and then `ripwire <dir> --test-gate --legend=compact`, and run the gates it names. A check followed by another edit proves nothing about that edit.'

# ---- the task brief, when the task is known: ripwire's own --brief page, allow-listed, inside the deadline ----
context="$primer"; briefDelivered=0
if [ -z "$taskWhy" ]
then
    taskWhy="no-toplevel"
    top="$( git -C "$dir" rev-parse --show-toplevel 2>/dev/null )"
    if [ -n "$top" ] && [ -d "$top" ]
    then
        deadline="${RIPWIRE_SUBAGENT_BRIEF_MS:-8000}"
        case "$deadline" in ''|*[!0-9]*) deadline=8000 ;; esac
        [ "$deadline" -lt 500 ] && deadline=500
        [ "$deadline" -gt 12000 ] && deadline=12000
        outFile="$stashDir/.brief.$$"
        umask 077
        ripwire "$top" --brief="$task" </dev/null >"$outFile" 2>/dev/null &
        child=$!
        # Two clocks, the stricter wins: 100 ms steps (sleep may oversleep on a loaded host) and bash's wall-clock SECONDS.
        waited=0; started=$SECONDS; wallCap=$(( ( deadline + 999 ) / 1000 ))
        while kill -0 "$child" 2>/dev/null && [ "$waited" -lt "$deadline" ] && [ $(( SECONDS - started )) -lt "$wallCap" ]
        do
            sleep 0.1; waited=$(( waited + 100 ))
        done
        if kill -0 "$child" 2>/dev/null
        then
            kill "$child" 2>/dev/null; wait "$child" 2>/dev/null
            taskWhy="timeout"
        elif wait "$child"
        then
            page="$( cat "$outFile" 2>/dev/null )"
            pageBytes="$( printf '%s' "$page" | LC_ALL=C wc -c | tr -d ' ' )"
            nOpen="$( printf '%s' "$page" | grep -o '<brief ' | wc -l | tr -d ' ' )"
            case "$page" in
                '<brief '*'<next>'*'</brief>')
                    if [ "$nOpen" = 1 ] && [ "$pageBytes" -le 9000 ]
                    then
                        context="ripwire — your user installed this for every subagent. Below is \`ripwire <root> --brief=\"<your task>\"\`, run at spawn for the task you were given: Read its act ranges in one turn before any grep or whole-file read; its <next> line says what to run before you report.
$page"
                        briefDelivered=1; taskWhy="delivered"
                    else
                        taskWhy="shape"
                    fi ;;
                *) taskWhy="shape" ;;
            esac
        else
            taskWhy="rc"
        fi
        rm -f "$outFile" 2>/dev/null
    fi
fi

out="$( jq -cn --arg m "$context" '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:$m}}' 2>/dev/null )" \
    || { logRow 0 jq-failed 0 0 "${taskWhy:-n/a}"; exit 0; }
[ -n "$out" ] || { logRow 0 jq-failed 0 0 "${taskWhy:-n/a}"; exit 0; }
logRow 1 delivered "$( printf '%s' "$context" | LC_ALL=C wc -c | tr -d ' ' )" "$briefDelivered" "${taskWhy:-n/a}"
printf '%s\n' "$out"
exit 0
