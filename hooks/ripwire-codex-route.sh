#!/usr/bin/env bash
# Codex UserPromptSubmit router: ask the deterministic --help-task classifier before the first tool
# choice, inject one CLI recommendation only at high confidence, and instrument the decision without
# retaining prompt text. The --observe arm is called by ripwire-codex-nudge.sh on PreToolUse and closes
# the registered adoption-within-two loop. Advisory-only: any missing dependency/error degrades to silence.
set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$( cat )" || exit 0

meter_home()
{
    [ "${RIPWIRE_ROUTE_METER:-1}" != 0 ] || return 1
    meterHome="${RIPWIRE_HOME:-${HOME:+$HOME/.ripwire}}"
    [ -n "$meterHome" ] || return 1
    mkdir -p "$meterHome/routing-pending" 2>/dev/null || return 1
    routingLog="$meterHome/routing.jsonl"
}

hash_text()
{
    printf '%s' "$1" | cksum 2>/dev/null | cut -d' ' -f1
}

if [ "${1:-}" = "--observe" ]; then
    meter_home || exit 0
    session="$( printf '%s' "$input" | jq -r '.session_id // .conversation_id // empty' 2>/dev/null )"
    [ -n "$session" ] || exit 0
    sessionHash="$( hash_text "$session" )"
    pending="$meterHome/routing-pending/$sessionHash.json"
    [ -s "$pending" ] || exit 0

    tool="$( printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null )"
    command="$( printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null )"
    observed=""
    case "$tool" in
        Bash)
            printf '%s' "$command" | grep -Eq '(^|[;&|[:space:]])([^[:space:]]*/)?ripwire([[:space:]]|$)' || exit 0
            observed="$( printf '%s' "$command" | grep -oE -- '--[a-z0-9-]+' | head -1 )"
            [ -n "$observed" ] || observed="<map>"
            ;;
        mcp__ripwire__*)
            observed="--$( printf '%s' "${tool#mcp__ripwire__}" | tr '_' '-' )"
            ;;
        *) exit 0 ;;
    esac

    lock="$pending.lock"
    mkdir "$lock" 2>/dev/null || exit 0
    trap 'rmdir "$lock" 2>/dev/null || true' EXIT HUP INT TERM
    [ -s "$pending" ] || exit 0
    recommended="$( jq -r '.recommended // empty' "$pending" 2>/dev/null )"
    remaining="$( jq -r '.remaining // 0' "$pending" 2>/dev/null )"
    case "$remaining" in 1|2) ;; *) exit 0 ;; esac
    position=$(( 3 - remaining ))
    adopted=0
    if [ "$tool" = Bash ]; then
        printf '%s' "$command" | grep -Eq -- "(^|[[:space:]])${recommended}(=|[[:space:]]|$)" && adopted=1
    elif [ "$observed" = "$recommended" ]; then
        adopted=1
    fi
    if [ "$adopted" = 1 ]; then outcome=adopted
    elif [ "$remaining" = 1 ]; then outcome=missed
    else outcome=continued
    fi
    now="$( date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true )"
    jq -cn --arg at "$now" --argjson position "$position" --arg outcome "$outcome" \
        --arg observed "$observed" --slurpfile route "$pending" \
        '{v:2,at:$at,event:"RouteObservation",session_hash:$route[0].session_hash,
          prompt_hash:$route[0].prompt_hash,intent:$route[0].intent,recommended:$route[0].recommended,
          observed:$observed,position:$position,outcome:$outcome}' >>"$routingLog" 2>/dev/null || true
    if [ "$outcome" = continued ]; then
        tmp="$pending.$$.tmp"
        jq '.remaining = 1' "$pending" >"$tmp" 2>/dev/null && mv "$tmp" "$pending"
    else
        rm -f "$pending"
    fi
    exit 0
fi

command -v ripwire >/dev/null 2>&1 || exit 0
prompt="$( printf '%s' "$input" | jq -r '.prompt // .user_prompt // .input // empty' 2>/dev/null )"
cwd="$( printf '%s' "$input" | jq -r '.cwd // .workdir // empty' 2>/dev/null )"
[ -n "$prompt" ] && [ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
session="$( printf '%s' "$input" | jq -r '.session_id // .conversation_id // empty' 2>/dev/null )"

promptBytes="$( printf '%s' "$prompt" | wc -c | tr -d ' ' )"
case "$promptBytes" in ''|*[!0-9]*) exit 0;; esac
[ "$promptBytes" -le 8192 ] || exit 0

route="$( ripwire "$cwd" --help-task="$prompt" 2>/dev/null )" || exit 0
case "$route" in *'<task-route status="recommend"'*) status=recommend;; *) status=abstain;; esac

# Best-effort route meter. It records enough to evaluate coverage/adoption while deliberately making
# prompt recovery impossible from this log: checksum + byte length, never the text. RIPWIRE_ROUTE_METER=0
# opts out without disabling routing. An explicit RIPWIRE_HOME keeps fixtures away from the operator log.
if meter_home; then
    promptHash="$( hash_text "$prompt" )"
    [ -n "$session" ] || session="prompt:$promptHash"
    sessionHash="$( hash_text "$session" )"
    intent="$( printf '%s' "$route" | sed -n 's/.*<choice intent="\([^"]*\)".*/\1/p' | head -1 )"
    recommended="$( printf '%s' "$route" | grep -oE -- '--[a-z0-9-]+' | head -1 )"
    now="$( date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true )"
    jq -cn --arg at "$now" --arg status "$status" --arg intent "$intent" --arg hash "$promptHash" \
        --arg sessionHash "$sessionHash" --arg recommended "$recommended" --argjson bytes "$promptBytes" \
        '{v:2,at:$at,event:"UserPromptSubmit",status:$status,intent:$intent,recommended:$recommended,
          session_hash:$sessionHash,prompt_hash:$hash,prompt_bytes:$bytes}' >>"$routingLog" 2>/dev/null || true

    pending="$meterHome/routing-pending/$sessionHash.json"
    rm -f "$pending"
    if [ "$status" = recommend ] && [ -n "$recommended" ]; then
        tmp="$pending.$$.tmp"
        jq -cn --arg sessionHash "$sessionHash" --arg promptHash "$promptHash" --arg intent "$intent" \
            --arg recommended "$recommended" \
            '{v:2,session_hash:$sessionHash,prompt_hash:$promptHash,intent:$intent,recommended:$recommended,remaining:2}' \
            >"$tmp" 2>/dev/null && mv "$tmp" "$pending"
    fi
fi

[ "$status" = recommend ] || exit 0
context="Ripwire produced a confidence-gated CLI recommendation before tool selection. Prefer it when it answers the task; continue beyond it when implementation or verification still needs more evidence.\n$route"
jq -cn --arg context "$context" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$context}}' 2>/dev/null || exit 0
