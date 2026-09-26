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
# ---- BEGIN MIRRORED BLOCK rw_is_ripwire_call (PR #215 review item 6) -------------------------------------
# KEEP BYTE-IDENTICAL in hooks/ripwire-claude-route.sh, hooks/ripwire-codex-route.sh and hooks/ripwire-nudge.sh.
# test/routehookcheck.sh extracts the three copies and diffs them, the kIngestParserVerMirror pattern: three
# files answering one question must answer it in one text, or the meter and the hooks disagree about the very
# same command line — which is exactly what happened, and it makes the adoption numbers unreadable.
#
# WHAT ROUND 1 REPLACED. A regex that looked for `ripwire` after a separator. It said NO to every WRAPPED
# invocation an agent actually types — `time ./build/ripwire .`, `sudo ripwire`, `env RIPWIRE_BIN=x ripwire`,
# `xargs ripwire`, `exec ripwire`, `nohup ripwire`, `if ripwire … ; then`, `{ ripwire … ; }` — and still said
# YES to `git commit -m "fix; ripwire hook"`, where the word sits inside a quoted string and no ripwire runs.
# Both errors corrupt the same measurement in opposite directions.
#
# WHAT ROUND 2 REPLACES (CodeRabbit, PR #215). Round 1 asked the SHELL to split the line — `set -- $1` with
# globbing off — and then walked the words. Word splitting is not lexing: it never separates a control
# operator from the word it is attached to. `true; ripwire .` split into `true;` and `ripwire`; `true;` was
# read as an ordinary command word, so the `ripwire` behind it was no longer in command position and the call
# was missed. Every `a; ripwire`, `a&&ripwire`, `a|ripwire`, `(ripwire .)` shape went the same way — and
# those are the shapes an agent's one-liner is actually made of. Round 1 also got the quoted-string case
# right for the WRONG reason (`-m "fix;` happened not to end a command), which is not a property to rest a
# published ratio on.
#
# WHAT IT DOES NOW. It LEXES the line itself, one character at a time, and never expands, evaluates or
# executes any part of it: backslash escapes, 'single' and "double" quotes, and the unquoted control
# operators `;` `&` `|` `(` `)` and newline, each of which ends the current word AND puts the next word in
# command position. An unquoted `#` starting a word ends the scan — the rest is a comment. `<` and `>` end a
# word and consume the next one as a redirection target, leaving command position where it was. On top of
# that sits the same command-position rule round 1 used: the wrapper words below do not consume the command,
# `cd DIR`, `rtk proxy` and `VAR=value` prefixes are stepped over with their operand, and the word is
# basename'd, so `./build/ripwire` and `/opt/rw/ripwire` count while `/opt/ripwire/bin/other` does not.
# Quoted text can no longer reach command position by construction, so `git commit -m "fix; ripwire hook"`
# and `grep -r 'ripwire;' src/` read as what they are: appearances that run nothing.
#
# KNOWN LIMIT, disclosed rather than papered over: a redirection written `2>&1` sends its `&` through the
# control-operator branch, so the digit behind it is read as a command word. That can only ever cost a
# MISSED call, in a line where `ripwire` sits in exactly that position, and never a false one.
#
# COST (issue #327). Each character read rebuilds the rest of the line (`${rw_line#?}`, and the suffix match
# around it), so the scan grows with the cube of the line's length: 20 s for a 4,000-character line under macOS
# bash 3.2, in front of the tool call it only counts. Two guards come first. A line that does not contain the
# word as written holds no call, and that check ends the scan for nearly every command. It reads the raw text,
# before quote removal, so a command word the shell assembles from quoted or escaped fragments (`'rip''wire'`,
# `rip\wire`, `"rip""wire"`) reads as no call: a MISSED call, never a false one. A line longer than 1,024
# characters is not scanned and reads as no call — a MISSED call, the same direction as the limit above; 1,024
# costs under half a second at worst. test/routehookcheck.sh O10 holds the cost, O9 pins the assembled words.
#
# POSIX sh only, no bashisms: routehookcheck.sh extracts this block and runs it under `sh`.
rw_cmd_word()
{
    # One completed word, offered to the command-position rule. Returns 0 only for a call.
    if [ "$rw_rtk" = 1 ]
    then
        rw_rtk=0
        if [ "$1" = "proxy" ]; then return 1; fi
    fi
    if [ "$rw_skip" -gt 0 ]
    then
        rw_skip=$(( rw_skip - 1 ))
        return 1
    fi
    if [ "$rw_at_cmd" != 1 ]
    then
        return 1
    fi
    case "$1" in
        if|while|until|do|then|else|elif|done|fi|esac|'!'|'{'|'}')  return 1 ;;
        *=*)                                                        return 1 ;;
        sudo|command|env|time|nice|nohup|exec|builtin|xargs)         return 1 ;;
        cd|pushd)                                        rw_skip=1; return 1 ;;
        rtk)                                             rw_rtk=1;  return 1 ;;
    esac
    rw_word="${1##*/}"
    if [ "$rw_word" = "ripwire" ]; then return 0; fi
    rw_at_cmd=0
    return 1
}

rw_is_ripwire_call()
{
    case "$1" in *ripwire*) ;; *) return 1 ;; esac
    [ "${#1}" -le 1024 ] || return 1
    rw_nl='
'
    rw_tab="$( printf '\t' )"
    rw_line="$1"
    rw_cur=''
    rw_quote=''
    rw_esc=0
    rw_at_cmd=1
    rw_skip=0
    rw_rtk=0
    while [ -n "$rw_line" ]
    do
        rw_c="${rw_line%"${rw_line#?}"}"
        rw_line="${rw_line#?}"
        if [ "$rw_esc" = 1 ]
        then
            rw_esc=0
            rw_cur="$rw_cur$rw_c"
            continue
        fi
        if [ "$rw_quote" = "'" ]
        then
            if [ "$rw_c" = "'" ]; then rw_quote=''; else rw_cur="$rw_cur$rw_c"; fi
            continue
        fi
        if [ "$rw_quote" = '"' ]
        then
            case "$rw_c" in
                '\') rw_esc=1 ;;
                '"') rw_quote='' ;;
                *)   rw_cur="$rw_cur$rw_c" ;;
            esac
            continue
        fi
        case "$rw_c" in
            '\')  rw_esc=1;      continue ;;
            "'")  rw_quote="'";  continue ;;
            '"')  rw_quote='"';  continue ;;
        esac
        case "$rw_c" in
            ' '|"$rw_tab")
                if [ -n "$rw_cur" ]
                then
                    if rw_cmd_word "$rw_cur"; then return 0; fi
                    rw_cur=''
                fi
                continue ;;
            ';'|'&'|'|'|'('|')'|"$rw_nl")
                if [ -n "$rw_cur" ]
                then
                    if rw_cmd_word "$rw_cur"; then return 0; fi
                    rw_cur=''
                fi
                rw_at_cmd=1
                rw_skip=0
                continue ;;
            '<'|'>')
                if [ -n "$rw_cur" ]
                then
                    if rw_cmd_word "$rw_cur"; then return 0; fi
                    rw_cur=''
                fi
                rw_skip=1
                continue ;;
            '#')
                if [ -z "$rw_cur" ]; then rw_line=''; continue; fi
                rw_cur="$rw_cur$rw_c"
                continue ;;
        esac
        rw_cur="$rw_cur$rw_c"
    done
    if [ -n "$rw_cur" ]
    then
        if rw_cmd_word "$rw_cur"; then return 0; fi
    fi
    return 1
}
# ---- END MIRRORED BLOCK rw_is_ripwire_call ---------------------------------------------------------------

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
            # Only a COMMAND-POSITION word counts as a ripwire call, wrappers and all: rw_is_ripwire_call, the
            # block mirrored in the three hooks (see its own comment). A token ending in /ripwire in ARGUMENT
            # position (`cd …/ripwire && git log`) does not count and never did burn a window slot since.
            # Gate: test/routehookcheck.sh O7/O9 / test/codexpromptroutecheck.sh.
            rw_is_ripwire_call "$command" || exit 0
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
        '{v:2,at:$at,agent:"claude",router:"prompt",event:"RouteObservation",session_hash:$route[0].session_hash,
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
# Route only inside a git work tree (issue #327). Outside one `--help-task` has no file list from git and
# walks the whole tree under cwd: a session started in $HOME measured over 30 s for one prompt, past the
# 8 s hook timeout the installer registers, on every prompt. The cost is routing in a small non-git
# project too; a missed recommendation is the direction this hook already takes on every doubt.
# The answer must be `true`, not only exit 0: a bare repository, or a cwd inside a `.git` directory, prints
# `false` with status 0, and routing there would walk git's own metadata.
# The hook answers for the JSON cwd, so git's repository-selection variables inherited from the caller are
# cleared first (git's own list, plus GIT_DIR/GIT_WORK_TREE if git cannot print it). With GIT_DIR exported,
# `git -C "$cwd"` answers for THAT repository: a non-git cwd reads `true` and routes, and the classifier,
# which runs git too, would read that repository's file list instead of the cwd's.
# shellcheck disable=SC2046 # word splitting is intended: one variable name per word
unset $( git rev-parse --local-env-vars 2>/dev/null ) GIT_DIR GIT_WORK_TREE
insideWorkTree="$( git -C "$cwd" rev-parse --is-inside-work-tree 2>/dev/null )" || exit 0
[ "$insideWorkTree" = true ] || exit 0
session="$( printf '%s' "$input" | jq -r '.session_id // .conversation_id // empty' 2>/dev/null )"

# A very long prompt is a paste, not a task description, and `--help-task` is not built to read one.
# Bailing keeps the classifier's measured precision meaningful rather than extrapolated.
promptBytes="$( printf '%s' "$prompt" | wc -c | tr -d ' ' )"
case "$promptBytes" in ''|*[!0-9]*) exit 0;; esac
[ "$promptBytes" -le 8192 ] || exit 0

# HARNESS/SYSTEM EVENT GUARD, checked before the classifier is ever invoked. Claude Code delivers a
# background-task completion (`<task-notification>…</task-notification>`) and an injected reminder
# (`<system-reminder>…</system-reminder>`) through this SAME UserPromptSubmit channel — they are not user
# input, but `--help-task` has no concept of "this names no task" and answers the report prose anyway
# (docs/EVALS.md, the routing-noise round: a background-task summary quoting words like "Summary:" and
# "Fix," minted `--connect='Split,A,Report'` out of text that never named a task). Narrow and POSITIONAL
# on purpose: only the prompt's own leading bytes, after whitespace, are tested, so a genuine user prompt
# that merely MENTIONS one of these markers mid-sentence ("what does <task-notification> mean in the
# hook?") is untouched — this is a shape test on the harness's own wake-up markers, not a guess at intent.
# The classifier is never called (there is nothing to classify), but the row IS still written — same
# posture as an ordinary abstain (R8 in test/routehookcheck.sh) — so coverage stays measurable from the
# log alone rather than silently undercounted.
# CodeRabbit PR #292 finding 4052087914: `sed 's/^[[:space:]]*//'` strips leading whitespace from EACH
# LINE of its input (sed's pattern space is one line at a time; `^` anchors per line, not per stream), so
# a prompt beginning with a BLANK LINE before the marker ("\n<task-notification>…") kept that leading
# newline in `rest` and missed the case match below — the guard then fell through to actually invoke the
# classifier (a real subprocess), log status="abstain" instead of status="skip-system", and delete an
# existing session's routing-pending file, none of which a harness/system event should ever cause. This
# bash parameter-expansion form strips the FULL leading run of [:space:] bytes (space/tab/newline/CR) from
# the whole string in one pass, not line by line.
lead="${prompt%%[![:space:]]*}"
rest="${prompt#"$lead"}"
case "$rest" in
    '<task-notification>'*|'<system-reminder>'*)
        if meter_home; then
            promptHash="$( hash_text "$prompt" )"
            [ -n "$session" ] || session="prompt:$promptHash"
            sessionHash="$( hash_text "$session" )"
            now="$( date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true )"
            jq -cn --arg at "$now" --arg hash "$promptHash" --arg sessionHash "$sessionHash" \
                --argjson bytes "$promptBytes" \
                '{v:2,at:$at,agent:"claude",router:"prompt",event:"UserPromptSubmit",status:"skip-system",
                  intent:"",recommended:"",arm:"",session_hash:$sessionHash,prompt_hash:$hash,
                  prompt_bytes:$bytes}' >>"$routingLog" 2>/dev/null || true
        fi
        exit 0
        ;;
esac

route="$( ripwire "$cwd" --help-task="$prompt" 2>/dev/null )" || exit 0
# The root's ATTRIBUTE, not a byte prefix: since the compact legend became the CLI default (L1) the root reads
# <task-route schema="ripwire.help-task/v1" status=…>, and an older binary still prints status= first. Both match.
status=abstain
[[ "$route" =~ \<task-route[^\>]*\ status=\"recommend\" ]] && status=recommend

resolve_arm "${session:-prompt}"

# Best-effort route meter. It records enough to evaluate coverage and adoption while deliberately
# making prompt recovery impossible from this log: a checksum and a byte length, never the text, and a
# hashed session id. RIPWIRE_ROUTE_METER=0 opts out of logging without disabling routing; an explicit
# RIPWIRE_HOME keeps fixture runs away from the operator's log.
#
# `agent` separates these rows from hooks/ripwire-codex-route.sh's, which share this file and carry no
# arm: an analysis that pooled them would put an un-armed population into the treatment side.
if meter_home; then
    # `router:"prompt"` (2026-09-03) distinguishes this row from hooks/ripwire-claude-toolroute.sh's
    # `router:"toolcall"` rows, the second router arm pre-registered in docs/EVALS.md -- both routers
    # share this same log (one file, one contamination surface), and bench/routing_ab_report.py reads
    # `router` and reports each SEPARATELY; the two are never pooled into one A/B readout.
    promptHash="$( hash_text "$prompt" )"
    [ -n "$session" ] || session="prompt:$promptHash"
    sessionHash="$( hash_text "$session" )"
    intent="$( printf '%s' "$route" | sed -n 's/.*<choice intent="\([^"]*\)".*/\1/p' | head -1 )"
    recommended="$( printf '%s' "$route" | grep -oE -- '--[a-z0-9-]+' | head -1 )"
    now="$( date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true )"
    jq -cn --arg at "$now" --arg status "$status" --arg intent "$intent" --arg hash "$promptHash" \
        --arg sessionHash "$sessionHash" --arg recommended "$recommended" --arg arm "$route_arm" \
        --argjson bytes "$promptBytes" \
        '{v:2,at:$at,agent:"claude",router:"prompt",event:"UserPromptSubmit",status:$status,intent:$intent,
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
context="$( printf '%s\n%s' 'Ripwire produced a confidence-gated CLI recommendation before tool selection. Prefer it when it answers the task (add --legend=full if a definition is unclear); continue beyond it when implementation or verification still needs more evidence.' "$route" )"
jq -cn --arg context "$context" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$context}}' 2>/dev/null || exit 0
