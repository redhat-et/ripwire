#!/usr/bin/env bash
# hooks/ripwire-subagent-primer.sh — OPT-IN Claude Code SubagentStart hook. Puts the two-line ripwire brief into the
# context of every subagent the session spawns: orient with `--for` before reading, run `--quality-delta` then
# `--test-gate` before calling it done. Advisory-only; it cannot block a subagent and degrades to silence on any error.
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
# reason, bytes}. session and agent_id are raw because the readout joins them to subagents/agent-<id>.jsonl. A harness
# that sets RIPWIRE_METER_FIXTURE=1 without naming RIPWIRE_SUBAGENT_LOG writes nothing (the nudge's §FIXTURE rule).
#
# Contract (verified against https://code.claude.com/docs/en/hooks, 2026-11-19): SubagentStart JSON arrives on stdin with
# the common fields plus {agent_id, agent_type}; context = exit 0 plus
#   {"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"..."}}
# Every path exits 0. Gate: test/subagentprimercheck.sh. Install: skills/install.sh --hook-subagent-primer.
set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$( cat )" || exit 0

event="$( printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null )" || exit 0
[ "$event" = "SubagentStart" ] || exit 0
dir="$( printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null )"
session="$( printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null )"
agentId="$( printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null )"
agentType="$( printf '%s' "$input" | jq -r '.agent_type // empty' 2>/dev/null )"
[ -n "$dir" ] || dir="$PWD"

# ---- the arm: env over meter.conf over the default. A shell read loop, no subprocess, as meter_init does. ----
mode="${RIPWIRE_SUBAGENT_PRIMER:-}"
conf="${HOME:-}/.ripwire/meter.conf"
if [ -z "$mode" ] && [ -n "${HOME:-}" ] && [ -f "$conf" ]
then
    while IFS='=' read -r key value
    do
        case "$key" in
            subagent_primer) mode="$( printf '%s' "$value" | tr -d '[:space:]' )" ;;
        esac
    done <"$conf"
fi
[ -n "$mode" ] || mode="on"
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
        --arg arm "$arm" --argjson d "$1" --arg r "$2" --argjson b "$3" \
        '{v:1, ts:$ts, session:$s, agent_id:$a, agent_type:$t, arm:$arm, delivered:$d, reason:$r, bytes:$b}' \
        >>"$dest" 2>/dev/null || true
}

# The control arm is counted and never spoken to.
[ "$arm" = "control" ] && { logRow 0 control 0; exit 0; }

# The commands must be runnable where the subagent starts: a ripwire binary on PATH, and a git work tree. The answer
# must be `true`, not only exit 0 (a bare repository or a cwd inside .git prints `false` with status 0, #327).
command -v ripwire >/dev/null 2>&1 || { logRow 0 no-ripwire 0; exit 0; }
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX
insideWorkTree="$( git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null )" || { logRow 0 not-git 0; exit 0; }
[ "$insideWorkTree" = true ] || { logRow 0 not-git 0; exit 0; }

# THE TEXT. A constant; <dir> and <task> are for the subagent to fill. Keep it to the two steps: its whole hypothesis
# is that a short, specific instruction is acted on where a long catalogue is not.
primer='ripwire — your user installed this for every subagent. Two steps, in this order:
1. Orient first: `ripwire <dir> --for="<your task; paste paths and symbols from the brief verbatim>" --legend=compact` (<dir> = the tree you will change). Read only the files it ranks, before any grep or whole-file read.
2. Before you call it done: `ripwire <dir> --quality-delta --legend=compact`, then `ripwire <dir> --test-gate`. Fix what they flag, or say in your report why not.'

out="$( jq -cn --arg m "$primer" '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:$m}}' 2>/dev/null )" \
    || { logRow 0 jq-failed 0; exit 0; }
[ -n "$out" ] || { logRow 0 jq-failed 0; exit 0; }
logRow 1 delivered "$( printf '%s' "$primer" | wc -c | tr -d ' ' )"
printf '%s\n' "$out"
exit 0
