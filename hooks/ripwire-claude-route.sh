#!/usr/bin/env bash
# hooks/ripwire-claude-route.sh — OPT-IN Claude Code UserPromptSubmit router. Ask the deterministic
# --help-task classifier BEFORE the first tool is chosen, inject ONE paste-ready command only when that
# classifier says `recommend`, and instrument the decision without ever retaining prompt text. The
# --observe arm is called by hooks/ripwire-nudge.sh on PreToolUse and closes the adoption-within-two
# loop pre-registered in docs/EVALS.md §4. Advisory-only: any missing dependency or error degrades to
# silence, never to a blocked prompt.
#
# WHY THIS EXISTS, AND WHY IT IS NOT THE RETIRED NUDGE WEARING A HAT (2026-09-02). The PreToolUse nudge
# in hooks/ripwire-nudge.sh was measured inert by a randomized A/B and retired — see §RETIRED there and
# the readout in docs/EVALS.md §4. Three things differ here, and they are the hypothesis under test:
#   1. THE MOMENT. This runs before the agent has chosen a tool, not after it already reached for one.
#   2. THE PAYLOAD. A runnable command with its arguments already filled in from the prompt, not a verb
#      name and an ellipsis the agent has to finish.
#   3. THE GATE. `--help-task` has a measured precision (1.000 / harmful 0.000 on its corpus,
#      test/taskroutecheck.sh), so this is silent on the prompts it cannot route rather than firing on
#      everything. Silence is the common case and is not a failure.
# The round cannot separate the three, and the registration says so.
#
# THE ARM IS THE METER'S ARM, NOT A SECOND COIN FLIP. It resolves `arm` exactly as meter_init() in
# hooks/ripwire-nudge.sh does — env over `meter.conf` over the `treatment` default, with the literal
# `auto` selecting the same stable session-id hash — so a session lands on the SAME side in both
# instruments and the two logs join on session_hash. A control session runs the classifier, writes the
# identical row and the identical pending file, and injects NOTHING; its adoption-within-two number is
# "how often would the agent have run that verb anyway", which is the quantity the retired nudge never
# had and the reason its readouts were uninterpretable.
#
# PROMPT-INJECTION POSTURE (a contract, gated by test/routehookcheck.sh). The injected context is
# assembled from exactly two sources: the compile-time constant framing string below, and the
# classifier's own XML, whose intent/skill/reason strings come from the binary's route table and whose
# only variable parts are a symbol or literal taken FROM THE USER'S OWN PROMPT and XML-escaped by the
# binary. NO REPOSITORY CONTENT REACHES THE OUTPUT — not a file name, not a match, not a body. The
# whole thing is then passed through `jq --arg`, so a prompt carrying XML or JSON structure breakers
# produces well-formed JSON with the breakers inert inside a string. A router steerable by the thing it
# is reading would be a worse failure than a router that does not work.
#
# NEVER EXIT 2. For UserPromptSubmit, exit 2 BLOCKS the prompt and erases it. This hook is advisory and
# has no business doing that under any condition, including its own bugs — every path below exits 0.
#
# Contract (verified against https://code.claude.com/docs/en/hooks, 2026-09-02): UserPromptSubmit JSON
# arrives on stdin with {session_id, transcript_path, cwd, permission_mode, hook_event_name, prompt}.
# Advisory context = exit 0 plus this JSON on stdout:
#   {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"..."}}
# Plain stdout would also be added as context; JSON is used because it is unambiguous and because the
# codex sibling already emits this exact shape.
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
    # A session that ends before two ripwire calls leaves its pending file behind; expire the strays so
    # routing-pending/ never accumulates unboundedly. Best-effort, like everything else here.
    find "$meterHome/routing-pending" -type f -name '*.json' -mtime +7 -delete 2>/dev/null || true
}

hash_text()
{
    printf '%s' "$1" | cksum 2>/dev/null | cut -d' ' -f1
}

# ---- resolve_arm SESSION — the meter's arm resolution, reimplemented here rather than sourced.
#      hooks/ripwire-nudge.sh is a hook, not a library: sourcing it would run its whole PreToolUse path.
#      The rules are the ones meter_init() applies and they must not drift — `control` and `treatment`
#      force an arm, `auto` selects the stable cksum split (low two decimal digits, <50 is control), and
#      ANY other value, including a hash that does not come back as a plain integer, reads as
#      `treatment`. That last clause is why a broken `cksum` cannot silently invent a third population.
route_arm="treatment"
resolve_arm()
{
    _ra_conf=""
    _ra_home="${RIPWIRE_HOME:-${HOME:+$HOME/.ripwire}}"
    if [ -n "$_ra_home" ] && [ -f "$_ra_home/meter.conf" ]
    then
        while IFS='=' read -r _ra_k _ra_v
        do
            case "$_ra_k" in arm) _ra_conf="$_ra_v" ;; esac
        done < "$_ra_home/meter.conf"
    fi
    case "${RIPWIRE_METER_ARM:-$_ra_conf}" in
        control) route_arm="control" ;;
        auto)
            _ra_h="$( printf '%s' "$1" | cksum 2>/dev/null | cut -d' ' -f1 )"
            case "$_ra_h" in
                ''|*[!0-9]*) route_arm="treatment" ;;
                *) if [ "$(( _ra_h % 100 ))" -lt 50 ]; then route_arm="control"; else route_arm="treatment"; fi ;;
            esac ;;
        *) route_arm="treatment" ;;
    esac
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# --observe — the PreToolUse arm, invoked by hooks/ripwire-nudge.sh. It closes adoption-within-two:
# after a `recommend` the next TWO ripwire-family calls in that session are inspected, and the first
# one that carries the recommended verb makes the outcome `adopted`. Two, because a longer window
# collects verbs the agent would have reached anyway — that choice is registered, not tuned.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
if [ "${1:-}" = "--observe" ]; then
    meter_home || exit 0
    session="$( printf '%s' "$input" | jq -r '.session_id // .conversation_id // empty' 2>/dev/null )"
    [ -n "$session" ] || exit 0
    sessionHash="$( hash_text "$session" )"
    pending="$meterHome/routing-pending/$sessionHash.json"
    [ -s "$pending" ] || exit 0
    # WHOSE PENDING FILE IS THIS? Both routers share $RIPWIRE_HOME/routing-pending, and on a machine
    # with both installed the Codex adapter chains ripwire-nudge.sh -> this --observe AND
    # ripwire-codex-route.sh --observe, so one tool call would consume TWO window slots and every
    # `continued` would arrive as `missed`. The pending file names the router that wrote it; a file
    # with no `agent` predates this field and belongs to the Codex router, which never wrote one.
    [ "$( jq -r '.agent // "codex"' "$pending" 2>/dev/null )" = "claude" ] || exit 0

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
        # observed= must name the verb the adoption verdict was decided on, not whichever modifier flag
        # happened to come first in the command line (--no-cache before --for read as observed=--no-cache).
        [ "$adopted" = 1 ] && observed="$recommended"
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
        '{v:2,at:$at,agent:"claude",event:"RouteObservation",session_hash:$route[0].session_hash,
          prompt_hash:$route[0].prompt_hash,intent:$route[0].intent,recommended:$route[0].recommended,
          arm:($route[0].arm // "treatment"),observed:$observed,position:$position,outcome:$outcome}' \
        >>"$routingLog" 2>/dev/null || true
    if [ "$outcome" = continued ]; then
        tmp="$pending.$$.tmp"
        jq '.remaining = 1' "$pending" >"$tmp" 2>/dev/null && mv "$tmp" "$pending"
    else
        rm -f "$pending"
    fi
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# The UserPromptSubmit arm.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
command -v ripwire >/dev/null 2>&1 || exit 0
prompt="$( printf '%s' "$input" | jq -r '.prompt // .user_prompt // .input // empty' 2>/dev/null )"
cwd="$( printf '%s' "$input" | jq -r '.cwd // .workdir // empty' 2>/dev/null )"
[ -n "$prompt" ] && [ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
session="$( printf '%s' "$input" | jq -r '.session_id // .conversation_id // empty' 2>/dev/null )"

# A very long prompt is a paste, not a task description, and `--help-task` is not built to read one.
# Bailing keeps the classifier's measured precision meaningful rather than extrapolated.
promptBytes="$( printf '%s' "$prompt" | wc -c | tr -d ' ' )"
case "$promptBytes" in ''|*[!0-9]*) exit 0;; esac
[ "$promptBytes" -le 8192 ] || exit 0

route="$( ripwire "$cwd" --help-task="$prompt" 2>/dev/null )" || exit 0
case "$route" in *'<task-route status="recommend"'*) status=recommend;; *) status=abstain;; esac

resolve_arm "${session:-prompt}"

# Best-effort route meter. It records enough to evaluate coverage and adoption while deliberately
# making prompt recovery impossible from this log: a checksum and a byte length, never the text, and a
# hashed session id. RIPWIRE_ROUTE_METER=0 opts out of logging without disabling routing; an explicit
# RIPWIRE_HOME keeps fixture runs away from the operator's log.
#
# `agent` separates these rows from hooks/ripwire-codex-route.sh's, which share this file and carry no
# arm: an analysis that pooled them would put an un-armed population into the treatment side.
if meter_home; then
    promptHash="$( hash_text "$prompt" )"
    [ -n "$session" ] || session="prompt:$promptHash"
    sessionHash="$( hash_text "$session" )"
    intent="$( printf '%s' "$route" | sed -n 's/.*<choice intent="\([^"]*\)".*/\1/p' | head -1 )"
    recommended="$( printf '%s' "$route" | grep -oE -- '--[a-z0-9-]+' | head -1 )"
    now="$( date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true )"
    jq -cn --arg at "$now" --arg status "$status" --arg intent "$intent" --arg hash "$promptHash" \
        --arg sessionHash "$sessionHash" --arg recommended "$recommended" --arg arm "$route_arm" \
        --argjson bytes "$promptBytes" \
        '{v:2,at:$at,agent:"claude",event:"UserPromptSubmit",status:$status,intent:$intent,
          recommended:$recommended,arm:$arm,session_hash:$sessionHash,prompt_hash:$hash,
          prompt_bytes:$bytes}' >>"$routingLog" 2>/dev/null || true

    # The pending file is written in BOTH arms. That is the whole design: the control arm's
    # adoption-within-two is the counterfactual the band is measured against, and it cannot exist if
    # only treatment sessions are observed.
    pending="$meterHome/routing-pending/$sessionHash.json"
    rm -f "$pending"
    if [ "$status" = recommend ] && [ -n "$recommended" ]; then
        tmp="$pending.$$.tmp"
        jq -cn --arg sessionHash "$sessionHash" --arg promptHash "$promptHash" --arg intent "$intent" \
            --arg recommended "$recommended" --arg arm "$route_arm" \
            '{v:2,agent:"claude",session_hash:$sessionHash,prompt_hash:$promptHash,intent:$intent,
              recommended:$recommended,arm:$arm,remaining:2}' \
            >"$tmp" 2>/dev/null && mv "$tmp" "$pending"
    fi
fi

[ "$status" = recommend ] || exit 0
[ "$route_arm" = control ] && exit 0

# printf, not an inline \n: inside double quotes the shell keeps \n as two literal characters, and the
# injected context then carries a visible backslash-n instead of a line break.
context="$( printf '%s\n%s' 'Ripwire produced a confidence-gated CLI recommendation before tool selection. Prefer it when it answers the task; continue beyond it when implementation or verification still needs more evidence.' "$route" )"
jq -cn --arg context "$context" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$context}}' 2>/dev/null || exit 0
