#!/usr/bin/env bash
# Codex UserPromptSubmit router: ask the deterministic --help-task classifier before the first tool
# choice, inject one CLI recommendation only at high confidence, and instrument the decision without
# retaining prompt text. Advisory-only: any missing dependency/error/abstention degrades to silence.
set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v ripwire >/dev/null 2>&1 || exit 0
input="$( cat )" || exit 0
prompt="$( printf '%s' "$input" | jq -r '.prompt // .user_prompt // .input // empty' 2>/dev/null )"
cwd="$( printf '%s' "$input" | jq -r '.cwd // .workdir // empty' 2>/dev/null )"
[ -n "$prompt" ] && [ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

promptBytes="$( printf '%s' "$prompt" | wc -c | tr -d ' ' )"
case "$promptBytes" in ''|*[!0-9]*) exit 0;; esac
[ "$promptBytes" -le 8192 ] || exit 0

route="$( ripwire "$cwd" --help-task="$prompt" 2>/dev/null )" || exit 0
case "$route" in *'<task-route status="recommend"'*) status=recommend;; *) status=abstain;; esac

# Best-effort route meter. It records enough to evaluate coverage/adoption while deliberately making
# prompt recovery impossible from this log: checksum + byte length, never the text. RIPWIRE_ROUTE_METER=0
# opts out without disabling routing. An explicit RIPWIRE_HOME keeps fixtures away from the operator log.
if [ "${RIPWIRE_ROUTE_METER:-1}" != 0 ]; then
    meterHome="${RIPWIRE_HOME:-${HOME:+$HOME/.ripwire}}"
    if [ -n "$meterHome" ]; then
        mkdir -p "$meterHome" 2>/dev/null || true
        promptHash="$( printf '%s' "$prompt" | cksum 2>/dev/null | cut -d' ' -f1 )"
        intent="$( printf '%s' "$route" | sed -n 's/.*<choice intent="\([^"]*\)".*/\1/p' | head -1 )"
        now="$( date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true )"
        jq -cn --arg at "$now" --arg status "$status" --arg intent "$intent" --arg hash "$promptHash" \
            --argjson bytes "$promptBytes" \
            '{at:$at,event:"UserPromptSubmit",status:$status,intent:$intent,prompt_hash:$hash,prompt_bytes:$bytes}' \
            >>"$meterHome/routing.jsonl" 2>/dev/null || true
    fi
fi

[ "$status" = recommend ] || exit 0
context="Ripwire produced a confidence-gated CLI recommendation before tool selection. Prefer it when it answers the task; continue beyond it when implementation or verification still needs more evidence.\n$route"
jq -cn --arg context "$context" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$context}}' 2>/dev/null || exit 0
