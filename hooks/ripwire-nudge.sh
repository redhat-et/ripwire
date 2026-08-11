#!/usr/bin/env bash
# hooks/ripwire-nudge.sh — OPT-IN Claude Code PreToolUse hook. Two jobs in one script: the
# ADVISORY-ONLY nudge (below), and the SUBSTITUTION METER (see the §METER block further down).
#
# Nudges an agent from raw grep/rg, from whole-file Read / candidate-Glob, and from raw `git diff`/
# `git log`/`git show --stat`, toward the matching ripwire verb. Ships INACTIVE — only registered via
# `skills/install.sh --hook`, never automatically (see the Phase B5.2 / R5 agent-context-science
# design: "with grep available, the agent defaults to it... a PreToolUse hook is the high-leverage
# lever" — passive skill-description triggering alone is measured ~30-50% reliable). Phase B9
# (Part 3) extends the trigger set to the git-information moments where raw
# output is weakest vs ripwire's structured answers: `git diff` → `--situ`/`--pr-context`, `git log` →
# `--rank-by=churn`/`--map-diff`, `git show --stat` → `--map-diff`. Deliberately excluded: `git status`
# and state-changing commands (add/commit/push/pull/checkout/branch) — nudging those is spam.
#
# 2026-08-10 (skill-orientation audit): Read and Glob added. They were previously excluded by the fast
# bail, which left the LARGEST token sink in the loop — the whole-file read — as the one default this
# hook could not see. A skill description only fires if the agent first RECOGNIZES a moment and then
# spends a call to load the skill; `Read` needs neither. The read nudge is therefore the one that
# matters most, and it is why the Read case is deliberately NOT deduped against the grep case: they
# are different habits and each gets its own one-time nudge.
#
# The read nudge fires ONCE per session and deliberately does NOT try to name the symbol involved:
# suggesting `--expand=<guess>` when the guess is wrong teaches an agent the tool is unreliable, which
# costs more than the nudge gains. It names the verb and lets the agent supply the argument.
#
# Design posture (non-negotiable — do not "improve" this into a blocker):
#   - NEVER blocks, denies, or rewrites the tool call. Always permissionDecision "allow" when it
#     speaks at all; never "deny"/"ask"; never "updatedInput". Any internal failure (missing jq,
#     malformed JSON, no git, no ripwire) degrades to silent allow — exit 0, no stdout.
#   - Fires at MOST once per session per pattern (Grep, Bash-grep, git-diff, git-log, and git-show-stat
#     are separate patterns), via a marker file under $TMPDIR keyed by session_id (falls back to PPID
#     if the payload has none) — an agent sees each nudge once, not on every call.
#   - Only fires when the target directory is inside a git repo AND a `ripwire` binary is on PATH.
#   - Exits fast: the common case (any tool other than Grep/Bash, or a Bash command that matches none
#     of recursive grep/rg / `git diff` / `git log` / `git show --stat`) bails after one or two greps
#     over stdin — no subprocess spawned.
#
# Contract (verified against https://code.claude.com/docs/en/hooks, 2026-07-13): PreToolUse JSON
# arrives on stdin with at least {session_id, cwd, tool_name, tool_input}. Advisory feedback that does
# NOT block the call = exit 0 + this JSON on stdout:
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow",
#    "additionalContext":"..."}}
#
# Usage (wired by the installer, not meant to be run by hand):
#   printf '%s' "$PRETOOLUSE_JSON" | hooks/ripwire-nudge.sh
set -u

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# §METER — THE SUBSTITUTION METER (Track B §S2, 2026-08-11)
#
# WHAT IT MEASURES, AND WHY THE UNIT IS A TOOL CALL. The question this project actually wants answered
# is "does an agent with ripwire installed reach for it instead of grep/read?". The task-success
# outcome eval cannot answer it: the power arithmetic puts the minimum detectable effect at 8.5-26pp
# against a pilot that measured parity, so that instrument is dead no matter how long it runs. A
# PreToolUse hook, on the other hand, sits at the exact decision point — the moment a default is
# chosen — and every session produces hundreds of those. So the unit of observation is one TOOL CALL,
# and the metric is a rate over calls: ripwire calls / (ripwire + native retrieval calls).
#
# ONE GLOBAL LOG. Rows append to $RIPWIRE_HOME/substitution.jsonl (default ~/.ripwire/), created
# lazily, one row per line, each tagged with the repo it came from. The hook is registered per-user
# but runs in whatever repo the session is in, so a single global file with a `tag`/`repo` field is
# what makes both cross-repo and per-repo analysis possible from the same data. bench/
# substitution_report.py reads it; docs/SUBSTITUTION_METER.md is the schema and the classifier's
# rule table.
#
# OBSERVE FIRST; THE A/B IS BUILT BUT DORMANT. Default behavior is always-on observation WITH nudges
# enabled — i.e. exactly what this hook did before, plus counting. The `arm` field and the
# RIPWIRE_METER_ARM / meter.conf toggle exist so that turning on a real control-vs-treatment
# alternation later costs one env var and no code; nothing here alternates on its own, and the arm is
# recorded on every row so the future analysis can trust the assignment it reads.
#
# THE NUDGE-CAUSES-THE-CALL CONFOUND. A nudge that says "use --grep" is itself a cause of the next
# ripwire call, so a naive rate would partly measure the hook talking to itself. Three fields keep
# that separable at analysis time: `nudged` (this call is the one a nudge fired on), `nudge` (why it
# did or did not: fired/dedup/gated/control/none) and `post_nudge` (a nudge had ALREADY fired earlier
# in this session, before this call). Pre-nudge calls in a session are the clean observations.
#
# SEQUENCES, NOT JUST CALLS. `session` + `seq` (a per-session monotonic counter) order the rows
# unambiguously even when several land in the same wall-clock second, so the analysis can reconstruct
# CHAINS (grep -> read -> read) and rank scenario bundles, not only single calls.
#
# NON-NEGOTIABLE: the meter is subordinate to the tool call it observes. Every write is best-effort —
# no HOME, an unwritable directory, no `date`, no `jq`, a full disk: each returns quietly and the
# hooked command proceeds untouched. Nothing in this block may change the hook's exit status or its
# stdout. `RIPWIRE_METER=0` (or `enabled=0` in meter.conf) turns counting off entirely and leaves the
# nudge working.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

# ---- meter state, resolved once per invocation: where the log is, whether counting is on, which arm.
#      Reading meter.conf uses a shell read loop rather than grep/sed — no subprocess on a path that
#      runs for every observed tool call. Env wins over the file; the file wins over the defaults. ----
meter_enabled=0
meter_file=""
meter_arm="treatment"
meter_post=0
meter_repo=""
meter_tag=""
meter_init()
{
    _mhome="${RIPWIRE_HOME:-}"
    [ -n "$_mhome" ] || { [ -n "${HOME:-}" ] && _mhome="$HOME/.ripwire"; }
    meter_file="${RIPWIRE_METER_LOG:-}"
    [ -n "$meter_file" ] || { [ -n "$_mhome" ] && meter_file="$_mhome/substitution.jsonl"; }
    [ -n "$meter_file" ] || return 0          # no HOME and no explicit log path — nothing to write to

    _conf_enabled=""
    _conf_arm=""
    if [ -n "$_mhome" ] && [ -f "$_mhome/meter.conf" ]
    then
        while IFS='=' read -r _ck _cv
        do
            case "$_ck" in
                enabled) _conf_enabled="$_cv" ;;
                arm)     _conf_arm="$_cv" ;;
            esac
        done < "$_mhome/meter.conf"
    fi

    case "${RIPWIRE_METER:-$_conf_enabled}" in
        0|off|no|false) meter_enabled=0 ;;
        *)              meter_enabled=1 ;;
    esac
    # Only the literal `control` selects the control arm. An unrecognized value must not silently
    # invent a third arm — it reads as the default, which is what the row then honestly records.
    case "${RIPWIRE_METER_ARM:-$_conf_arm}" in
        control) meter_arm="control" ;;
        *)       meter_arm="treatment" ;;
    esac
}

# ---- JSON string escape for the no-jq fallback. Control characters are DELETED rather than escaped:
#      it costs nothing here and it makes "one row is one line" true by construction. ----
meter_esc()
{
    printf '%s' "$1" | tr -d '\000-\037' | cut -c1-200 | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# ---- meter_log CLASS FAMILY NUDGED NUDGEREASON DETAIL — append one row. Silent, never fatal. ----
meter_log()
{
    [ "$meter_enabled" = "1" ] || return 0
    [ -n "$meter_file" ] || return 0
    _mclass="$1"; _mfamily="$2"; _mnudged="$3"; _mreason="$4"; _mdetail="$5"

    # Both directories in one call: the log's, and the one the per-session counter lives in. A TMPDIR
    # that does not exist is a real configuration in the wild, and it must cost neither a lost sequence
    # number nor a line of stderr.
    _mseqf="${TMPDIR:-/tmp}/ripwire-meter.${session}.seq"
    if [ ! -d "${meter_file%/*}" ] || [ ! -d "${_mseqf%/*}" ]
    then
        mkdir -p "${meter_file%/*}" "${_mseqf%/*}" 2>/dev/null || return 0
    fi

    _mts="$( date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null )" || _mts=""

    # per-session monotonic counter: one byte appended per row, the file's SIZE is the sequence number.
    # Append-of-one-byte is atomic, so two concurrent tool calls cannot land on the same number.
    # NOTE the brace form: in `cmd >>f 2>/dev/null` the shell opens `>>f` FIRST and reports its own
    # failure on the still-unredirected stderr, so the 2>/dev/null arrives too late to suppress it.
    # Wrapping the redirect in a group is what actually makes an unwritable path silent.
    { printf '.' >>"$_mseqf"; } 2>/dev/null || true
    _mseqraw="$( wc -c <"$_mseqf" 2>/dev/null )" || _mseqraw=0
    [ -n "$_mseqraw" ] || _mseqraw=0
    _mseq=$(( _mseqraw + 0 ))

    # `detail` is scrubbed and truncated INSIDE the row builder rather than by a printf|tr|cut pipeline:
    # jq already encodes control characters correctly and can slice, and three saved processes on a
    # path that runs before every Read is worth more than the symmetry.
    if command -v jq >/dev/null 2>&1
    then
        _mrow="$( jq -cn --arg ts "$_mts" --argjson seq "$_mseq" --arg session "$session" \
            --arg repo "$meter_repo" --arg tag "$meter_tag" --arg tool "$tool_name" \
            --arg class "$_mclass" --arg family "$_mfamily" --argjson nudged "$_mnudged" \
            --arg nudge "$_mreason" --argjson post_nudge "$meter_post" --arg arm "$meter_arm" \
            --arg detail "$_mdetail" \
            '{v:1,ts:$ts,seq:$seq,session:$session,repo:$repo,tag:$tag,tool:$tool,class:$class,family:$family,nudged:$nudged,nudge:$nudge,post_nudge:$post_nudge,arm:$arm,detail:($detail|.[0:200])}' \
            2>/dev/null )" || _mrow=""
    else
        _mrow="{\"v\":1,\"ts\":\"$( meter_esc "$_mts" )\",\"seq\":$_mseq,\"session\":\"$( meter_esc "$session" )\",\"repo\":\"$( meter_esc "$meter_repo" )\",\"tag\":\"$( meter_esc "$meter_tag" )\",\"tool\":\"$( meter_esc "$tool_name" )\",\"class\":\"$_mclass\",\"family\":\"$_mfamily\",\"nudged\":$_mnudged,\"nudge\":\"$_mreason\",\"post_nudge\":$meter_post,\"arm\":\"$meter_arm\",\"detail\":\"$( meter_esc "$_mdetail" )\"}"
    fi
    [ -n "$_mrow" ] || return 0
    { printf '%s\n' "$_mrow" >>"$meter_file"; } 2>/dev/null || true
    return 0
}

# ---- meter_lead CMD — the command's leading word (basename) and its second word, space-separated,
#      after stripping the things that stand between a command line and the verb it actually runs:
#      leading VAR=val assignments, transparent wrappers, and RTK'S REWRITE. `rtk grep …` is what a
#      Bash hook sees on a machine where rtk's own PreToolUse hook rewrites dev commands; scoring
#      that as "not a grep" would make this meter's rate an artifact of another tool's hook. Word
#      splitting runs under `set -f` so an unquoted glob in the command cannot expand against the
#      filesystem; quoting is not honored, which is fine for a classifier that reads two words. ----
#      Sets globals rather than echoing: a command substitution is a fork, and this runs on the fast-
#      bail path that every Bash tool call passes through. A function's positional parameters are its
#      own in bash, so `set --` here cannot disturb the script's; `set -f` is global and is restored.
meter_w1=""
meter_w2=""
meter_lead()
{
    set -f
    # shellcheck disable=SC2086
    set -- $1
    set +f
    while [ "$#" -gt 0 ]
    do
        case "$1" in
            *=*)                                           shift ;;
            sudo|command|env|time|nice|nohup|exec|builtin)  shift ;;
            rtk)                                           shift
                                                           if [ "${1:-}" = "proxy" ]; then shift; fi ;;
            *)                                             break ;;
        esac
    done
    meter_w1="${1:-}"
    meter_w1="${meter_w1##*/}"
    meter_w2="${2:-}"
}

# ---- meter_classify_bash CMD — the class of a Bash command line, or empty for "not an observation
#      this meter makes". Leading word first, then git's subcommand, then a vocabulary scan whose only
#      verdict is `unclassified` — ambiguity is logged, never dropped. Rules: docs/SUBSTITUTION_METER.md
meter_classify_bash()
{
    _bc="$1"
    meter_lead "$_bc"
    _blead="$meter_w1"
    _bsub="$meter_w2"
    mclass=""
    case "$_blead" in
        ripwire)
            mclass="ripwire-cli"; return 0 ;;
        grep|egrep|fgrep|zgrep|rg|ag|ack|ack-grep|ugrep)
            mclass="grep"; return 0 ;;
        find|fd|fdfind)
            mclass="find"; return 0 ;;
        cat|head|tail|less|more|bat|nl|tac)
            mclass="read"; return 0 ;;
        ls)
            # a tree walk, not a directory listing: -R (in any cluster) or --recursive
            if printf '%s' "$_bc" | grep -qE -- '(^|[[:space:]])-[A-Za-z]*R[A-Za-z]*([[:space:]]|$)|--recursive([[:space:]]|$)'
            then
                mclass="find"; return 0
            fi ;;
        awk|gawk|mawk)
            # only a PATTERN program is a search: awk '/needle/ …'. `awk '{print $1}' /tmp/x` is not,
            # which is why the test anchors on a quote immediately followed by the slash.
            if printf '%s' "$_bc" | grep -qE "['\"]/"
            then
                mclass="grep"; return 0
            fi ;;
        sed)
            # `sed -n '1,80p' f` is a whole-file read wearing a different hat; `sed -i …` is an edit.
            if printf '%s' "$_bc" | grep -qE -- '(^|[[:space:]])-[A-Za-z]*n([[:space:]]|$)'
            then
                mclass="read"; return 0
            fi ;;
        git)
            case "$_bsub" in
                grep) mclass="grep";     return 0 ;;
                diff) mclass="git-diff"; return 0 ;;
                log)  mclass="git-log";  return 0 ;;
                show)
                    case "$_bc" in
                        *--stat*) mclass="git-show-stat"; return 0 ;;
                    esac ;;
            esac ;;
    esac
    # The leading word is not a retrieval verb — but if the LINE names one anywhere (a pipeline, a
    # loop body, xargs, a subshell, a `cd x && grep …`), the call IS an observation and must not
    # vanish from the denominator just because this classifier cannot say which kind it is.
    if printf '%s' "$_bc" \
        | grep -qE '(^|[^A-Za-z0-9_.-])(ripwire|grep|egrep|fgrep|rg|ag|ack|ugrep|find|fd|cat|head|tail|less|more|bat|awk|sed)([^A-Za-z0-9_-]|$)'
    then
        mclass="unclassified"; return 0
    fi
    return 0
}

# ---- meter_family CLASS — the coarse bucket the substitution rate is computed over. ----
meter_family()
{
    case "$1" in
        ripwire-cli|ripwire-mcp)        printf 'ripwire' ;;
        grep|find|read|glob)            printf 'native' ;;
        git-diff|git-log|git-show-stat) printf 'git' ;;
        session-start)                  printf 'meta' ;;
        *)                              printf 'other' ;;
    esac
}

# ---- SessionStart mode (`--session-start`): inject the use-when blurb ONCE at session start ----
# The PreToolUse nudges above are reactive — they only speak after the agent has already reached for a
# default. This is the proactive half: a binary on PATH is invisible until the context says when to
# reach for it, and not every user has pasted the blurb into CLAUDE.md. The text is EXTRACTED from
# `ripwire wrap claude` rather than restated here, so it cannot drift from wrapUseWhenBlurbLines() in
# src/wrap.h (the single source of truth the wrap gate diffs across agents). If wrap refuses — e.g. a
# CRITICAL skill-scan finding — the fence is absent, the blurb is empty, and this degrades to silence.
if [ "${1:-}" = "--session-start" ]
then
    input="$( cat )"

    dir=$( printf '%s' "$input" | tr '\n' ' ' | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 \
        | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//' )
    [ -n "$dir" ] || dir="$PWD"

    session=$( printf '%s' "$input" | tr '\n' ' ' | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 \
        | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//' )
    [ -n "$session" ] || session="ppid$PPID"

    # §METER: a session boundary is the denominator's denominator — without it "12 ripwire calls" has
    # no per-session scale. Logged BEFORE the ripwire/git gates below, so a session that never
    # qualified for a nudge still counts as a session. This hook is registered for startup|resume|
    # clear, so a long session can legitimately produce more than one of these rows.
    tool_name="SessionStart"
    meter_repo=$( git -C "$dir" rev-parse --show-toplevel 2>/dev/null )
    [ -n "$meter_repo" ] || meter_repo="$dir"
    meter_tag="${meter_repo##*/}"
    meter_init
    meter_log "session-start" "meta" 0 "none" "${dir}"

    command -v ripwire >/dev/null 2>&1 || exit 0
    git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

    marker="${TMPDIR:-/tmp}/ripwire-nudge.${session}.session-start"
    [ -e "$marker" ] && exit 0
    { : > "$marker"; } 2>/dev/null || true

    blurb=$( ripwire wrap claude 2>/dev/null \
        | sed -n '/^# --- paste into/,/^# --- end paste ---$/p' | sed '1d;$d' )
    [ -n "$blurb" ] || exit 0

    if command -v jq >/dev/null 2>&1
    then
        jq -n --arg m "$blurb" \
            '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
    else
        esc=$( printf '%s' "$blurb" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk '{printf "%s\\n", $0}' )
        printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
    fi
    exit 0
fi

input="$( cat )"

# ---- fast bail: only Grep, Glob, Read and Bash can ever match; every other tool (Edit/Write/...)
#      exits here after a single grep over stdin, before spawning anything. ----
tool_name=$( printf '%s' "$input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 \
    | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//' )

case "$tool_name" in
    Grep) category="grep"; mclass="grep" ;;
    Read) category="read"; mclass="read" ;;
    Glob) category="glob"; mclass="glob" ;;
    Bash) category="";     mclass="" ;;    # both decided below, once the command text is available
    # §METER: ripwire's own MCP verbs. Never nudged (nudging a ripwire call toward ripwire is noise) —
    # they are here purely so the NUMERATOR is not silently missing every agent that prefers the MCP
    # server to the CLI. This only works for a settings.json whose matcher was written by the current
    # installer; see the disclosure in docs/SUBSTITUTION_METER.md for what stays invisible.
    mcp__ripwire__*) category=""; mclass="ripwire-mcp" ;;
    *) exit 0 ;;
esac

# ---- field extractor: jq if present (robust, handles escaping) else a flat grep/sed fallback that
#      is adequate for this payload's simple, non-repeating string keys (tool_name, cwd, session_id,
#      pattern, command, path never recur across nesting levels here). Degraded fallback never crashes
#      — worst case it returns empty and a caller-side guard skips the nudge. ----
field()
{
    if command -v jq >/dev/null 2>&1
    then
        printf '%s' "$input" | jq -r --arg k "$1" '(.tool_input[$k] // .[$k]) // empty' 2>/dev/null
    else
        printf '%s' "$input" | tr '\n' ' ' | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n1 \
            | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//'
    fi
}

# ---- fields3 KEY — cwd, session_id and one tool_input KEY in a SINGLE jq spawn, as three globals.
#      jq costs ~10 ms of process startup and this hook used to pay it once per field; the meter needs
#      a third field, so fetching all three at once is what keeps the metered hook CHEAPER on the
#      Read path than the unmetered one was, rather than 50% dearer. @tsv is the reason this is safe
#      to split on a tab: jq escapes any tab, newline or backslash inside a value, so the three fields
#      are guaranteed to be one line with exactly two separators. Falls back to the flat extractor. ----
f3_cwd=""
f3_session=""
f3_detail=""
fields3()
{
    if ! command -v jq >/dev/null 2>&1
    then
        f3_cwd="$( field cwd )"
        f3_session="$( field session_id )"
        [ -n "${1:-}" ] && f3_detail="$( field "$1" )"
        return 0
    fi
    _f3="$( printf '%s' "$input" \
        | jq -r --arg k "${1:-}" '[(.cwd // ""), (.session_id // ""), (.tool_input[$k] // "" | tostring)] | @tsv' \
        2>/dev/null )"
    _oIFS="$IFS"
    IFS="$( printf '\t' )"
    # shellcheck disable=SC2086
    read -r f3_cwd f3_session f3_detail <<EOF2
$_f3
EOF2
    IFS="$_oIFS"
    return 0
}

if [ "$tool_name" = "Bash" ]
then
    # `command` doubles as this tool's detail field, so one fetch serves the nudge AND the meter row.
    fields3 command
    cmd="$f3_detail"
    [ -n "$cmd" ] || exit 0
    # Only a RECURSIVE/tree-wide text search counts — a single-file grep or a filter on other output
    # (e.g. `ls | grep foo`) is not the "blind grep over the tree" case this hook targets. Checked
    # first since it is the highest-volume pattern.
    if printf '%s' "$cmd" | grep -qE '\brg\b'
    then
        category="bash-grep"   # ripgrep invocations are inherently tree-wide
    elif printf '%s' "$cmd" | grep -qE '\b(grep|egrep|fgrep)\b' \
        && printf '%s' "$cmd" | grep -qE -- '(-[A-Za-z]*[rR][A-Za-z]*\b|--recursive\b)'
    then
        category="bash-grep"   # grep/egrep/fgrep with an explicit recursive flag
    # `git show <sha> --stat` / `git show --stat` — a commit's stat summary; checked before the plain
    # `git diff`/`git log` patterns since "show" is a distinct subcommand from either.
    elif printf '%s' "$cmd" | grep -qE '\bgit[[:space:]]+show\b' \
        && printf '%s' "$cmd" | grep -qE -- '--stat\b'
    then
        category="git-show-stat"
    # `git diff` (HEAD, --stat, path-limited, ...) — deliberately NOT `git status`/add/commit/push/
    # pull/checkout/branch (state-changing or trivially cheap; nudging those is spam).
    elif printf '%s' "$cmd" | grep -qE '\bgit[[:space:]]+diff\b'
    then
        category="git-diff"
    # `git log` (-N, --oneline, path-limited, ...)
    elif printf '%s' "$cmd" | grep -qE '\bgit[[:space:]]+log\b'
    then
        category="git-log"
    else
        category=""
    fi

    # §METER: classification is INDEPENDENT of the nudge decision above, and deliberately wider — the
    # nudge only speaks where it has good advice, the meter has to see the whole denominator (a
    # single-file grep, a `cat`, a `find`, an `ls -R` are all the native retrieval this tool competes
    # with). Where the classifier declines but the nudge chain matched, the nudge's own verdict is the
    # class: that covers forms like `cd sub && git diff` that lead with neither.
    meter_classify_bash "$cmd"          # sets mclass, without a fork
    if [ -z "$mclass" ]
    then
        case "$category" in
            bash-grep)     mclass="grep" ;;
            git-diff)      mclass="git-diff" ;;
            git-log)       mclass="git-log" ;;
            git-show-stat) mclass="git-show-stat" ;;
        esac
    fi
    # A ripwire invocation is never nudged toward ripwire. This also closes a live false positive that
    # predates the meter: `ripwire . --grep=…` matched the recursive-grep regex above (`--grep` clears
    # \bgrep\b, and `-grep` clears the [rR]-flag test), so the tool nudged itself.
    [ "$mclass" = "ripwire-cli" ] && category=""

    # Not a retrieval call at all (`cmake --build`, `git status`, `npm test`): out of scope for both
    # jobs, and the fast bail stays fast — one grep more than before, no subprocess beyond it.
    [ -n "$mclass" ] || exit 0
fi

# ---- cwd, session_id, and this tool's own primary argument (the row's `detail`), in one fetch. The
#      Bash branch above already ran it; every other tool runs it here with its own detail key. ----
case "$tool_name" in
    Bash)      ;;                       # already fetched, with `command` as the detail key
    Read)      fields3 file_path ;;
    Grep|Glob) fields3 pattern ;;
    *)         fields3 ;;
esac
mdetail="$f3_detail"

dir="$f3_cwd"
[ -n "$dir" ] || dir="$PWD"

# ---- gates for the NUDGE: git repo + ripwire on PATH, both required, both cheap. One `rev-parse
#      --show-toplevel` does the git check AND yields the repo the row is tagged with.
#      The METER logs either way: an un-nudgeable call is still a call, and dropping those would bias
#      the denominator toward exactly the sessions the nudge can reach. ----
nudge_ok=1
meter_repo=$( git -C "$dir" rev-parse --show-toplevel 2>/dev/null )
if [ -z "$meter_repo" ]
then
    meter_repo="$dir"
    nudge_ok=0
fi
meter_tag="${meter_repo##*/}"
command -v ripwire >/dev/null 2>&1 || nudge_ok=0

session="$f3_session"
[ -n "$session" ] || session="ppid$PPID"
meter_init

# ---- did a nudge ALREADY fire earlier in this session? Read BEFORE this call's own marker is set, so
#      `post_nudge` means "this call happened in an already-nudged session", not "this call nudged". --
[ -e "${TMPDIR:-/tmp}/ripwire-nudge.${session}.anynudge" ] && meter_post=1

# ---- the nudge decision, recorded as both a boolean and a REASON. Dedup is per session per category
#      (or per-PPID if the payload carries no session_id); a deduped call is silent but still counted.
nudged=0
nudge="none"
if [ -z "$category" ]
then
    nudge="none"                                        # observed, but no nudge pattern applies
elif [ "$nudge_ok" != "1" ]
then
    nudge="gated"                                       # not a git repo, or no ripwire on PATH
elif [ "$meter_arm" = "control" ]
then
    nudge="control"                                     # A/B control arm: counted, never nudged
else
    marker="${TMPDIR:-/tmp}/ripwire-nudge.${session}.${category}"
    if [ -e "$marker" ]
    then
        nudge="dedup"
    else
        { : > "$marker"; } 2>/dev/null || true
        { : > "${TMPDIR:-/tmp}/ripwire-nudge.${session}.anynudge"; } 2>/dev/null || true
        nudged=1
        nudge="fired"
    fi
fi

meter_log "$mclass" "$( meter_family "$mclass" )" "$nudged" "$nudge" "$mdetail"

[ "$nudged" = "1" ] || exit 0

# ---- build the one-time suggestion (one short message per category; the git-diff/git-log/
#      git-show-stat messages each name a SINGLE best verb for the observed form, not a catalog) ----
case "$category" in
    grep)
        pattern=$( field pattern )
        [ -n "$pattern" ] || pattern="PATTERN"
        pattern=$( printf '%s' "$pattern" | cut -c1-60 )
        msg="ripwire tip: for text search across this repo, \`ripwire . --grep='${pattern}'\` returns each match WITH its enclosing function/class — often replacing the read-the-file-for-context step. Conceptual/multi-word task instead of a literal string? \`ripwire . --for=\"...\"\`. Symbol usage/call sites? \`ripwire . --callers=SYM\` / \`--uses=SYM\`. (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
    git-diff)
        msg="ripwire tip: for a diff, \`ripwire . --situ\` maps the mid-task blast radius, tests-to-run, and forgotten co-change partners in one pass (swap in \`--pr-context\` when reviewing a PR). (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
    git-log)
        msg="ripwire tip: for git log, \`ripwire . --rank-by=churn\` ranks who's actually churning that code (swap in \`--map-diff\` for what changed structurally). (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
    git-show-stat)
        msg="ripwire tip: for a commit's --stat summary, \`ripwire . --map-diff\` shows what changed structurally, not just line counts. (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
    read)
        msg="ripwire tip: reading whole files is the biggest token sink in an agent loop, and less context measures MORE accurate, not just cheaper (code-repair accuracy fell 29%->3% as context grew 32K->256K, LongCodeBench). To understand ONE symbol, \`ripwire . --expand=SYM\` returns its body plus its callees' signatures instead of the file around it. Don't yet know which file to open? \`ripwire . --for=\"<task in words>\"\` ranks them, or \`ripwire . --pack-task=\"<task>\"\` returns ranking + bodies + callers + tests in ONE budgeted call. (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
    glob)
        msg="ripwire tip: a filename glob finds files by NAME; \`ripwire . --for=\"<task in words>\"\` ranks them by what the code actually does (matching doc-comments and bodies, not just paths) and hands back signatures rather than a path list you still have to open. (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
    *)
        msg="ripwire tip: this looks like a recursive grep/rg over the tree. \`ripwire . --grep='PATTERN'\` (literal) or \`ripwire . --for=\"task in words\"\` (conceptual) often answers the same question with the enclosing symbol attached, in far fewer tokens than raw grep + file reads. (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
esac

if command -v jq >/dev/null 2>&1
then
    jq -n --arg m "$msg" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",additionalContext:$m}}'
else
    esc=$( printf '%s' "$msg" | tr '\n' ' ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' )
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"%s"}}\n' "$esc"
fi

exit 0
