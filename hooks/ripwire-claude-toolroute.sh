#!/usr/bin/env bash
# hooks/ripwire-claude-toolroute.sh — OPT-IN Claude Code PreToolUse SECOND ROUTER ARM, pre-registered
# in docs/EVALS.md ("A second router arm — route on the agent's FIRST TOOL CALL, not the prompt",
# 2026-09-03). Routes on the SHAPE of the tool call itself rather than the prompt that led to it:
# a recursive grep/rg on a source path names `--grep=<pattern>`; a Read of a source file names
# `--expand=<symbol>` (only when the symbol resolves on the root) or `--for` with the file already
# known. Advisory-only, exactly like hooks/ripwire-claude-route.sh (the prompt arm) and the retired
# hooks/ripwire-nudge.sh nudge tiers: never blocks, never denies, degrades to silence on any error.
#
# WHY A SECOND ARM. hooks/ripwire-claude-route.sh's own instrument (docs/EVALS.md §4) found the prompt
# classifier blind to 98% of labelled ripwire moments — most tasks never say what they need in the
# words `--help-task` reads. The agent's first `Bash`/`Read` call is a cleaner signal: `grep -rn NAME
# src/` already names the verb (`--grep`) and its argument; a `Read` of a source file already names
# the file `--for` would take, or the symbol `--expand` would take once it resolves. The retired nudge
# (hooks/ripwire-nudge.sh, §RETIRED) fired on the same moment with generic text and no argument; this
# arm pastes the exact command instead — the same difference the prompt router made over grep, applied
# one moment earlier.
#
# THE ARM IS THE METER'S ARM, NOT A SECOND COIN FLIP. `resolve_arm` below reimplements the exact rule
# meter_init() (hooks/ripwire-nudge.sh) and hooks/ripwire-claude-route.sh's own `resolve_arm` apply —
# env over `meter.conf` over the `treatment` default, `auto` selecting the same stable session-id hash
# — so a session lands on the same side across all three instruments. A control session runs the same
# classification and writes the identical row; it injects nothing. Reimplemented rather than sourced:
# sourcing either sibling script would run its own top-level PreToolUse/UserPromptSubmit body.
#
# ROUTER=TOOLCALL, NEVER POOLED WITH router=prompt. Both routers append to the SAME
# ~/.ripwire/routing.jsonl (one file, one contamination surface, matching the substitution meter's own
# "one global log" posture) but every row here carries `router:"toolcall"`; hooks/ripwire-claude-route.sh
# was updated in the same round to carry `router:"prompt"` on its own rows so the two populations are
# distinguishable by a single field rather than by absence-of-field. bench/routing_ab_report.py reads
# `router` and reports each router SEPARATELY — the pre-registered n>=40-per-arm floor applies per
# router per arm, and a reader that pooled them would be comparing two different questions.
#
# WHAT THIS ROW DOES NOT DO: adoption tracking. Unlike the prompt router's `RouteObservation` (which
# needs hooks/ripwire-nudge.sh's PreToolUse path to see the NEXT tool call after a prompt), this hook
# sees every tool call already — but a live adoption-within-two loop for THIS arm was deliberately left
# out of THIS build (see LANE_REPORT.md): the substitution meter (hooks/ripwire-nudge.sh's §METER,
# ~/.ripwire/substitution.jsonl) already logs every observed tool call in session+seq order, so the
# control arm's counterfactual ("how often does a routable event get followed by a ripwire call
# anyway", measured at 0.086 from the local meter) is computable by correlating THIS log's decision
# rows against THAT log after the fact, without this hook needing its own pending-file chain. Building
# that correlator is follow-up work, named as such in docs/SUBSTITUTION_METER.md and LANE_REPORT.md.
#
# ONE ROW PER DECISION, NEVER RAW TEXT. A row is written for every ROUTABLE EVENT — a Bash command that
# looks like a recursive grep/rg, a `Grep` tool call, or a `Read` tool call — in BOTH arms, with
# `status` (`recommend`/`abstain`), `reason` (why an abstain happened), and `recommended` (the bare
# verb, e.g. `--grep`, never the argument). Anything else (Edit/Write/Task/Glob/mcp__*, or a Bash
# command that is not a recursive grep — `cat`, `sed`, `ps`, `tail -f`, a build/test invocation, a
# plain `git` command) is not a routable event at all and exits before any row is written or any
# subprocess is spawned, mirroring hooks/ripwire-nudge.sh's own fast-bail discipline.
#
# NOTIFICATION-SHAPED INPUT NEVER ROUTES. A command, pattern, or path carrying the literal substrings
# `[SYSTEM NOTIFICATION` or `<task-notification>` (the harness's own wake-up markers, per
# bench/mine_traces.py's §2.1 origin-kind filter) is treated as instrumentation noise, not a real
# retrieval need, and abstains with reason="notification" before any other classification runs.
#
# PER-SESSION CAP OF THREE RECOMMENDATIONS, same reasoning as the retired nudge's own design note: an
# uncapped hint on every grep is noise. A marker file under $TMPDIR, keyed by the raw session id,
# counts recommendations already made (one byte appended per recommend, same atomic-append trick
# hooks/ripwire-nudge.sh's meter_log uses for `seq`). The 4th-and-later routable event in a session
# still gets a row — `status="abstain" reason="cap"` — but injects nothing, in either arm.
#
# THE RESOLVED_SYMBOLS GUARD (unchanged from the prompt router / --help-task's own rule): a `Read` of a
# source file is recommended as `--expand=<symbol>` only when a guessed symbol name actually resolves
# on the root (`ripwire <root> --expand=<candidate>` exits 0). It almost always will not — most files
# are not named exactly after the one symbol inside them — and the deliberate, honest fallback is
# `--for="<file>"`, which never needs a resolved symbol and is always a sound thing to ask for a known
# file. Guessing a symbol that does not resolve and recommending it anyway is exactly the harmful shape
# this arm's own gate (test/toolcallroutecheck.sh) is written to catch.
#
# PROMPT-INJECTION / PRIVACY POSTURE, same contract as hooks/ripwire-claude-route.sh: the injected
# context is assembled from a fixed framing string and the recommended command line, built ONLY from
# fields the CALLER'S OWN tool_input supplied (the pattern/path/file it was already about to use) —
# never from repository content. The log never retains prompt/command/pattern/path text: only a
# session hash and (optionally) a detail hash, exactly the substitution-recovery-is-impossible posture
# documented for routing.jsonl in docs/SUBSTITUTION_METER.md.
#
# NEVER EXIT 2. For PreToolUse, exit 2 blocks the tool call. This hook is advisory and has no business
# doing that under any condition, including its own bugs — every path below exits 0.
#
# Contract (verified against https://code.claude.com/docs/en/hooks, 2026-09-03): PreToolUse JSON
# arrives on stdin with at least {session_id, cwd, tool_name, tool_input}. Advisory feedback that does
# NOT block the call = exit 0 plus this JSON on stdout:
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow",
#    "additionalContext":"..."}}
# Malformed input (no jq, unparseable JSON, missing fields) degrades to exit 0 with EMPTY stdout —
# valid per the same contract, and never a blocked call.
set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$( cat )" || exit 0

tool_name="$( printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null )"
case "$tool_name" in
    Bash|Grep|Read) ;;
    *) exit 0 ;;    # fast bail: every other tool is out of scope, no row, no subprocess
esac

cwd="$( printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null )"
session="$( printf '%s' "$input" | jq -r '.session_id // .conversation_id // empty' 2>/dev/null )"
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

command=""
pattern=""
gpath=""
file_path=""
case "$tool_name" in
    Bash) command="$( printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null )" ;;
    Grep) pattern="$( printf '%s' "$input" | jq -r '.tool_input.pattern // empty' 2>/dev/null )"
          gpath="$( printf '%s' "$input" | jq -r '.tool_input.path // empty' 2>/dev/null )"
          [ -n "$gpath" ] || gpath="." ;;
    Read) file_path="$( printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null )" ;;
esac

# ---- notification guard, checked before ANY other classification. A poll (`ps`, `tail -f`, a
#      build/gate invocation) never reaches here at all for Bash: it is not a recursive-grep shape, so
#      the classification below never sets `shape`, and the fast "no shape, no row" exit further down
#      handles it identically to `cat`/`sed`. This block only needs to catch the marker literally
#      appearing inside one of the fields we DO act on. ----
case "$command$pattern$gpath$file_path" in
    *'[SYSTEM NOTIFICATION'*|*'<task-notification>'*) notif=1 ;;
    *) notif=0 ;;
esac

hash_text()
{
    printf '%s' "$1" | cksum 2>/dev/null | cut -d' ' -f1
}

# ---- resolve_arm SESSION — reimplemented from hooks/ripwire-claude-route.sh's own copy of
#      meter_init()'s rule (hooks/ripwire-nudge.sh). Kept in sync by hand across all three; see that
#      script's header for why sourcing is not an option. ----
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

# ---- shape classification. `shape` empty means "not a routable event" -- no row, no output. ----
shape=""
grepPattern=""
grepPath=""
grepReason=""     # set on an abstain that a grep-shaped command still deserves a row for

if [ "$tool_name" = "Grep" ]
then
    shape="grep"
    grepPattern="$pattern"
    grepPath="$gpath"
elif [ "$tool_name" = "Read" ]
then
    shape="read"
elif [ "$tool_name" = "Bash" ]
then
    [ -n "$command" ] || exit 0
    cmdx="${command//$'\n'/ ; }"
    isGrepShape=0
    if printf '%s' "$cmdx" | grep -qE '\brg\b'
    then
        isGrepShape=1
    elif printf '%s' "$cmdx" | grep -qE '\b(grep|egrep|fgrep)\b' \
        && printf '%s' "$cmdx" | grep -qE -- '(-[A-Za-z]*[rR][A-Za-z]*\b|--recursive\b)'
    then
        isGrepShape=1
    fi
    [ "$isGrepShape" = 1 ] || exit 0     # cat/sed/ps/tail/build/git/etc: not routable, no row
    shape="grep"

    # ---- tokenize with xargs -n1: it splits on shell-style quoting WITHOUT ever executing anything
    #      (no command substitution, no globbing -- confirmed: `$(...)`, backticks and `*` all come
    #      back as literal text). Safe to run on fully untrusted command text for exactly that reason.
    #      Built with a plain while-read loop, not `mapfile` -- this hook must run under macOS's
    #      shipped /bin/bash 3.2, which has neither `mapfile`/`readarray` nor negative array indices
    #      (both bash-4+), the same constraint hooks/ripwire-nudge.sh and ripwire-claude-route.sh
    #      already write around.
    xargsOut="$( printf '%s' "$cmdx" | xargs -n1 2>/dev/null )"
    xargsRc=$?
    toks=()
    if [ "$xargsRc" = 0 ]
    then
        while IFS= read -r _tokline
        do
            toks+=("$_tokline")
        done < <( printf '%s\n' "$xargsOut" )
    fi
    binIdx=-1
    tokN=${#toks[@]}
    _i=0
    while [ "$_i" -lt "$tokN" ]
    do
        case "${toks[$_i]}" in
            grep|egrep|fgrep|rg) binIdx=$_i; break ;;
        esac
        _i=$(( _i + 1 ))
    done
    if [ "$xargsRc" != 0 ] || [ "$binIdx" -lt 0 ]
    then
        grepReason="unparseable"
    fi
    if [ -z "$grepReason" ]
    then
        bareTokens=()
        eFlagCount=0
        skipNext=0
        i=$(( binIdx + 1 ))
        while [ "$i" -lt "$tokN" ]
        do
            t="${toks[$i]}"
            case "$t" in
                '|'|'&&'|'||'|';') break ;;                 # command boundary -- stop, ignore the rest
                -e) eFlagCount=$(( eFlagCount + 1 )); skipNext=1 ;;
                -*) : ;;                                    # any other flag, self-contained
                *)
                    if [ "$skipNext" = 1 ]
                    then
                        skipNext=0                          # the value belonging to a standalone -e
                    else
                        bareTokens+=("$t")
                    fi
                    ;;
            esac
            i=$(( i + 1 ))
        done
        bareN=${#bareTokens[@]}
        if [ "$eFlagCount" -ge 2 ]
        then
            grepReason="multi-pattern"                      # ambiguous -- which -e is THE pattern?
        elif [ "$bareN" -eq 0 ]
        then
            grepReason="no-pattern"
        else
            grepPattern="${bareTokens[0]}"
            if [ "$bareN" -ge 2 ]
            then
                grepPath="${bareTokens[$(( bareN - 1 ))]}"
            else
                grepPath="."
            fi
        fi
    fi
fi

[ -n "$shape" ] || exit 0

# ---- source/non-source. Grep targets a DIRECTORY (usually) -- denylist known non-source trees.
#      Read targets one FILE with a definite extension -- allowlist the languages ripwire indexes
#      (mirrors src/taskroute.h's kCodeExtensions, plus bash/json per this repo's own language list). --
is_denylisted_dir()
{
    case "/${1#./}/" in
        */node_modules/*|*/vendor/*|*/third_party/*|*/.git/*|*/dist/*|*/build/*|*/target/*| \
        */venv/*|*/.venv/*|*/__pycache__/*|*/.cache/*|*/coverage/*|*/bench/external/*| \
        */docs/*|*/doc/*)
            return 0 ;;
        *) return 1 ;;
    esac
}
is_source_ext()
{
    case "$1" in
        *.cpp|*.cc|*.cxx|*.h|*.hpp|*.hh|*.hxx|*.c|*.py|*.pyi|*.ts|*.tsx|*.mts|*.cts|*.js|*.jsx|*.mjs| \
        *.cjs|*.go|*.rs|*.java|*.rb|*.swift|*.cs|*.m|*.mm|*.cu|*.cuh|*.metal|*.sh|*.bash|*.json)
            return 0 ;;
        *) return 1 ;;
    esac
}

status="abstain"
reason=""
recommended=""
detailForHash=""

if [ "$notif" = 1 ]
then
    reason="notification"
elif [ "$shape" = "grep" ]
then
    detailForHash="$grepPattern $grepPath"
    if [ -n "$grepReason" ]
    then
        reason="$grepReason"
    elif is_denylisted_dir "$grepPath"
    then
        reason="non-source"
    else
        status="recommend"
        recommended="--grep"
    fi
elif [ "$shape" = "read" ]
then
    detailForHash="$file_path"
    if [ -z "$file_path" ]
    then
        reason="no-path"
    elif ! is_source_ext "$file_path"
    then
        reason="non-source"
    elif ! command -v ripwire >/dev/null 2>&1
    then
        reason="no-tool"
    elif ! git -C "$cwd" rev-parse --show-toplevel >/dev/null 2>&1
    then
        reason="no-repo"
    else
        # ---- resolved_symbols guard: try the bare stem, then a PascalCase-of-stem guess (two probes,
        #      bounded cost). Neither resolving is the COMMON case by design -- most files are not
        #      named exactly after the one symbol inside them -- and the honest fallback is --for. ----
        stem="${file_path##*/}"; stem="${stem%.*}"
        pascal="$( printf '%s' "$stem" | awk -F'[-_]' '{ o=""; for(i=1;i<=NF;i++){ w=$i; if(length(w)>0){ o = o toupper(substr(w,1,1)) substr(w,2) } } print o }' 2>/dev/null )"
        resolvedSym=""
        for cand in "$stem" "$pascal"
        do
            [ -n "$cand" ] || continue
            if ripwire "$cwd" --expand="$cand" >/dev/null 2>/dev/null
            then
                resolvedSym="$cand"
                break
            fi
        done
        status="recommend"
        if [ -n "$resolvedSym" ]
        then
            recommended="--expand"
        else
            recommended="--for"
        fi
    fi
fi

resolve_arm "${session:-toolroute}"

# ---- per-session cap: 3 recommendations. Checked and (on a genuine recommend) incremented AFTER the
#      decision above, so an event that would have abstained never touches the counter. ----
if [ "$status" = "recommend" ]
then
    capFile="${TMPDIR:-/tmp}/ripwire-toolroute.${session:-nosession}.count"
    capCount=0
    if [ -e "$capFile" ]
    then
        capCount="$( wc -c <"$capFile" 2>/dev/null | tr -d ' ' )"
        case "$capCount" in ''|*[!0-9]*) capCount=0 ;; esac
    fi
    if [ "$capCount" -ge 3 ]
    then
        status="abstain"
        reason="cap"
    else
        { printf '.' >>"$capFile"; } 2>/dev/null || true
    fi
fi

# ---- best-effort log. Never the operator's log during a gate run: RIPWIRE_HOME must be named
#      explicitly by a harness (same posture as hooks/ripwire-nudge.sh's §FIXTURE guard) or this
#      degrades to $HOME/.ripwire, exactly like the prompt router. RIPWIRE_ROUTE_METER=0 opts out of
#      logging without disabling routing. ----
if [ "${RIPWIRE_ROUTE_METER:-1}" != 0 ]
then
    _home="${RIPWIRE_HOME:-${HOME:+$HOME/.ripwire}}"
    if [ -n "$_home" ] && mkdir -p "$_home" 2>/dev/null
    then
        routingLog="$_home/routing.jsonl"
        [ -n "$session" ] || session="toolroute:$( hash_text "$detailForHash$tool_name" )"
        sessionHash="$( hash_text "$session" )"
        detailHash="$( hash_text "$detailForHash" )"
        now="$( date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true )"
        jq -cn --arg at "$now" --arg tool "$tool_name" --arg shape "$shape" --arg status "$status" \
            --arg reason "$reason" --arg recommended "$recommended" --arg arm "$route_arm" \
            --arg sessionHash "$sessionHash" --arg detailHash "$detailHash" \
            '{v:2,at:$at,agent:"claude",router:"toolcall",event:"ToolCallRoute",tool:$tool,
              shape:$shape,status:$status,reason:$reason,recommended:$recommended,arm:$arm,
              session_hash:$sessionHash,detail_hash:$detailHash}' \
            >>"$routingLog" 2>/dev/null || true
    fi
fi

[ "$status" = "recommend" ] || exit 0
[ "$route_arm" = "control" ] && exit 0

# ---- build the ONE runnable command line, from fields the caller's own tool_input already supplied --
#      never from repository content. Quoting is for DISPLAY only; nothing here is ever executed. ----
runCmd=""
case "$recommended" in
    --grep)   runCmd="ripwire $cwd --grep=$grepPattern" ;;
    --expand) runCmd="ripwire $cwd --expand=$resolvedSym" ;;
    --for)    runCmd="ripwire $cwd --for=\"$file_path\"" ;;
esac
[ -n "$runCmd" ] || exit 0

context="$( printf '%s\n%s' 'Ripwire produced a confidence-gated CLI recommendation from the shape of this tool call, before it ran. Prefer it when it answers the need; continue with the original call when more evidence is still required.' "$runCmd" )"
jq -cn --arg context "$context" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",additionalContext:$context}}' \
    2>/dev/null || exit 0
