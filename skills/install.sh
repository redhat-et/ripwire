#!/usr/bin/env bash
# Install ripwire's agent skills (symlinks back to this repo's skills/, so they stay version-controlled and
# edits here take effect immediately). Default: Claude. Codex: skills/install.sh --codex installs to the
# current cross-agent ~/.agents/skills discovery root; --codex-legacy retains the older CODEX_HOME/skills
# destination. Hermes: skills/install.sh --hermes installs to ${HERMES_HOME:-~/.hermes}/skills (the same
# Agent-Skills-standard SKILL.md files Hermes loads natively, plus the Hermes-native skills under
# skills/hermes/; no `--hook` support there yet — Hermes exposes hooks: pre_tool_call in config.yaml
# but hooks/ripwire-nudge.sh still switches on Claude tool names, so the port has not landed). An explicit path remains supported for CI and other clients:
# skills/install.sh PATH.
# Add --hook explicitly to install the advisory PreToolUse + SessionStart hook for the selected client:
# (for Claude, --hook also registers the SubagentStart routing note: `ripwire-nudge.sh --subagent-start`, a short
# factual note for the Explore and Plan subagents, which do not load CLAUDE.md; RIPWIRE_SUBAGENT_ROUTE=0 turns it off)
# skills/install.sh --hook (Claude) or skills/install.sh --codex --hook (Codex). --openclaw installs to
# that same cross-agent root (openclaw's own "compatibility skill root"); it has no hook slot.
# The legend-seen hook REWRITES ripwire commands (it adds --legend-seen=<session file>). It is ON BY DEFAULT with a
# --hook install, and with --opencode, whose only hook it is (owner ruling 111, 2026-11-20) — a plain skills install
# still touches no settings.json, and --hook-subagent-primer alone still installs only its own hook. --no-hook-legend-seen installs the advisory entries without it, RIPWIRE_LEGEND_SEEN=0 turns it off at
# run time, and it keeps its own flag for a hook-only install:
# skills/install.sh --hook-legend-seen (Claude), --codex --hook-legend-seen, or --opencode --hook-legend-seen.
# The subagent primer (a SubagentStart hook: the two-line ripwire brief in every subagent's context) is its own opt-in
# too, Claude only: skills/install.sh --hook-subagent-primer.
# A Claude skills install also installs the ripwire-locator subagent into ${CLAUDE_CONFIG_DIR:-~/.claude}/agents/ (lane LC1,
# owner rulings 185/189): --no-locator-agent, or RIPWIRE_NO_LOCATOR_AGENT=1 in the environment (which the curl installers
# pass through when they activate the skills), skips it; a copy installed earlier is left where it is.
set -eu
src="$( cd "$( dirname "$0" )" && pwd )"

# ── HARDENING ported from PR #293 (2026-10, thanks @s0undt3ch). #293 proposed moving this installer into the
#    ripwire binary; that was declined (2026-10-07), but its four review rounds produced a list of ways an installer
#    can be talked into writing or deleting the wrong thing, and every item that applies to a shell installer lives
#    here: absolute roots only, nothing created group/world-writable, a symlinked settings.json written through (not
#    replaced), its mode kept (CWE-732), a quoted hook command, jq found only through absolute PATH entries
#    (CWE-426), temp files removed on a normal exit and on HUP, INT and TERM (not on SIGKILL, which no script can catch),
#    and a prune that removes only what it can show is ours.
#    test/skillinstallcheck.sh sections (J)-(Q) drive each one; every arm was red against the script before this.

# A file or directory this script CREATES must not be group/world-writable, whatever the caller's umask: under
# `umask 000` a first-time settings.json, hooks.json or skills directory came out 0666/0777. Only TIGHTENS: OR 022
# into the current mask, so a stricter user umask (077) stays stricter and the common 022 is unchanged.
umask "$( printf '%04o' $(( 0$( umask ) | 022 )) )"

# The temp files this run created are removed on a normal exit and on HUP/INT/TERM. A SIGKILL cannot be trapped: it can
# leave one `.tmp.*` file beside the file being written, and a later run does not sweep it. A temp file renamed into
# place no longer exists, so the removal is then a no-op. `exit N` in the signal traps runs the EXIT trap. At most one
# settings temp ($tmp) and one manifest temp ($manifestTmp) are live at a time, so there is no list to split: a list
# of paths cut at newlines would `rm` a piece of a root that itself holds a newline.
tmp=""
manifestTmp=""
cleanup_tmps()
{
    [ -z "$tmp" ] || rm -f -- "$tmp" 2>/dev/null || true
    [ -z "$manifestTmp" ] || rm -f -- "$manifestTmp" 2>/dev/null || true
    return 0
}
trap cleanup_tmps EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# is_abs_path P — absolute on POSIX, or a Windows drive/UNC path (Git Bash hands those through unchanged). The drive and
# UNC forms are accepted on every platform: on POSIX a root spelled `x:/y` is therefore taken as absolute and created
# under the current directory (a known gap; the Windows arms pin the drive form).
is_abs_path()
{
    case "$1" in
        /*) return 0 ;;
        [A-Za-z]:[/\\]*) return 0 ;;
        \\\\*) return 0 ;;
    esac
    return 1
}
# abs_home / abs_root VALUE OVERRIDE — a destination root taken from the ENVIRONMENT must be absolute. A relative
# CLAUDE_CONFIG_DIR / AGENTS_HOME / CODEX_HOME / HERMES_HOME used to install into ./relcfg, wherever the shell was,
# and an empty HOME turned `$HOME/.claude` into `/.claude`. Refuse (status 2) instead of guessing. An explicit PATH
# argument is typed on the command line and keeps resolving against the current directory.
abs_home()
{
    _h="${HOME-}"
    if [ -z "$_h" ]; then
        echo "skills/install.sh: HOME is unset or empty; refusing to guess a destination. Set HOME, name the destination (an explicit PATH argument), or set CLAUDE_CONFIG_DIR / AGENTS_HOME / CODEX_HOME / HERMES_HOME to an absolute path." >&2
        return 1
    fi
    if ! is_abs_path "$_h"; then
        echo "skills/install.sh: HOME must be an absolute path (got '$_h'); refusing to install relative to the current directory." >&2
        return 1
    fi
    printf '%s\n' "$_h"
}
abs_root()
{
    # $1 = the root as resolved (`${VAR:-$HOME/.sub}`, spelled exactly as before so the census gates still read it);
    # $2 = the override variable's own value, "" when the HOME fallback was taken (then HOME itself must be usable)
    if [ -z "$2" ]; then abs_home >/dev/null || return 1; fi
    if [ -z "$1" ] || ! is_abs_path "$1"; then
        echo "skills/install.sh: the destination root '$1' is not an absolute path (HOME, CLAUDE_CONFIG_DIR, AGENTS_HOME, CODEX_HOME and HERMES_HOME must be absolute); refusing to install relative to the current directory." >&2
        return 1
    fi
    printf '%s\n' "$1"
}

# find_jq — set $jqBin to an ABSOLUTE path to jq, or "" when there is none. An empty or relative PATH entry means
# "the current directory", i.e. whatever repository the user happens to be standing in: a planted ./jq would run
# with the user's rights (CWE-426). Only absolute entries are searched. (The final `command -v` is for hosts, such
# as Git Bash, whose PATH can hold forms this walk does not recognise; its answer is used only if it is absolute.)
jqBin=""
find_jq()
{
    jqBin=""
    set -f; _oifs="$IFS"; IFS=:
    for _d in $PATH; do
        IFS="$_oifs"
        is_abs_path "$_d" || continue
        for _n in jq jq.exe; do
            if [ -f "$_d/$_n" ] && [ -x "$_d/$_n" ]; then jqBin="$_d/$_n"; break 2; fi
        done
    done
    IFS="$_oifs"; set +f
    if [ -z "$jqBin" ]; then
        _c="$( command -v jq 2>/dev/null )" || _c=""
        if [ -n "$_c" ] && is_abs_path "$_c"; then jqBin="$_c"; fi
    fi
    return 0
}

# resolve_link FILE — FILE with symbolic links followed to the real file, so a dotfiles setup (settings.json ->
# ~/dotfiles/claude/settings.json) has the hook written INTO the real file and the link kept. A temp-then-rename onto
# the link itself would replace the link with a regular file and the dotfiles copy would never get the hook.
resolve_link()
{
    _p="$1"; _n=0
    while [ -L "$_p" ]; do
        _n=$(( _n + 1 ))
        if [ "$_n" -gt 40 ]; then
            echo "skills/install.sh: too many levels of symbolic links resolving $1" >&2
            return 1
        fi
        _l="$( readlink "$_p" )" || return 1
        case "$_l" in
            /*|[A-Za-z]:[/\\]*) _p="$_l" ;;
            *) _p="$( dirname "$_p" )/$_l" ;;
        esac
    done
    printf '%s\n' "$_p"
}

# mk_tmp FILE — set $tmp to a fresh temp file BESIDE FILE, tracked for removal. Beside, not in $TMPDIR, so the final
# `mv` is a rename within one filesystem (atomic) and not a copy across two that a kill can leave half-written. It
# starts as a copy of FILE's mode, so rewriting a 0640 config does not change it (CWE-732; mktemp alone makes 0600).
# A read-only original (0444) ends up owner-writable. Falls back to a plain `mktemp` if the template is unusable.
mk_tmp()
{
    tmp="$( mktemp "$1.tmp.XXXXXX" 2>/dev/null )" || tmp="$( mktemp )" || {
        echo "skills/install.sh: could not create a temporary file for $1" >&2
        exit 1
    }
    if [ -f "$1" ]; then
        cp -p "$1" "$tmp" 2>/dev/null || true
        chmod u+w "$tmp" 2>/dev/null || true
    fi
}

# hook_cmd PATH — PATH as a hook `command` string. Written bare when it holds only characters a shell leaves alone
# (so the ordinary install is byte-for-byte what it was); otherwise single-quoted, because the agent runs the string
# through a shell and a checkout under a path with a space gave a hook that could not run. A path holding a single
# quote cannot be both quoted here and recognised again on the next run, so it is refused.
hook_cmd()
{
    case "$1" in
        *[!A-Za-z0-9_./:@%+=,-]*)
            case "$1" in
                *\'*) echo "skills/install.sh: --hook cannot register a hook script whose path contains a single quote: $1" >&2; return 1 ;;
            esac
            printf "'%s'\n" "$1" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# ── the PreToolUse matcher, in one place. It is not cosmetic: a matcher decides which tool calls the
#    hook is ever SHOWN. Read/Glob are here because the whole-file read is the largest token sink in an
#    agent loop and the one default a skill description cannot intercept; mcp__ripwire__.* is here for
#    the hook's other job, the substitution meter (docs/SUBSTITUTION_METER.md), whose numerator would
#    otherwise miss every agent that prefers the MCP server to the CLI; Edit/Write/MultiEdit/
#    NotebookEdit are the `native-edit` class the EDIT band needs (never nudged, never in the rate).
#
#    THE SHAPE IS LOAD-BEARING (2026-09-05, terminality round A, lane T). Claude Code reads a matcher
#    made only of letters, digits, `_`, `-`, spaces, `,` and `|` as a LIST OF EXACT TOOL NAMES; only a
#    matcher holding any other character is a (JavaScript, unanchored) regular expression. The
#    2026-09-04 form `Read|Glob|Grep|Bash|mcp__ripwire__` therefore compared `mcp__ripwire__` as a
#    whole tool name and matched NO MCP call, ever — 0 MCP rows in 51,002 on the frozen snapshot, and
#    a live tee on the installed hook saw the Bash and Read calls around an mcp__ripwire__whereis and
#    never the call itself. The `.*` puts the matcher on the regex path; the `^(...)$` keeps it a
#    whole-name match there, so `Edit` cannot also fire for NotebookEdit through the unanchored test.
#    test/hookcheck.sh section (14) evaluates this string exactly as Claude Code does.
hookMatcher="^(Read|Glob|Grep|Bash|Edit|Write|MultiEdit|NotebookEdit|mcp__ripwire__.*)$"
codexHookMatcher="^(Bash|Read|Glob|Grep|Edit|Write|MultiEdit|NotebookEdit|mcp__ripwire__.*)$"

# ── IDENTIFYING AN EXISTING REGISTRATION: BY SCRIPT, NEVER BY WHICH COPY REGISTERED IT (2026-09-05).
# Every test below used to be `.command == $cmd`, an EXACT absolute path. A machine with the Homebrew
# copy registered (/opt/homebrew/share/ripwire/hooks/ripwire-nudge.sh) that then ran this installer
# out of a git checkout compared two different paths, concluded "not registered", and APPENDED a
# second entry. Both entries fire on every matching call, so the substitution meter counts every row
# TWICE — and the entry left behind keeps its old matcher, so the duplicate does not even buy the fix
# the operator ran the installer for. That happened on this project's own machine while closing the
# terminality round: PreToolUse, SessionStart and UserPromptSubmit all ended up doubled.
#
# `jqIsScript` matches the hook by its SCRIPT NAME, so any copy's registration is recognised. The
# command's first word is taken before the suffix test, because the SessionStart entry carries a
# trailing ` --session-start` argument. When an entry is found, both its matcher AND its command are
# brought to the current values: refreshing one and not the other is how the stale half survives.
# test/skillinstallcheck.sh arm (D) drives the exact scenario and counts the entries.
# A command registered from a path with a space is single-quoted (hook_cmd above): its script is what lies between the
# quotes. \u0027 is the single quote, which cannot appear inside this single-quoted shell string.
jqIsScript='def cmdWord: (.command // "") | if startswith("\u0027") then (.[1:] | split("\u0027")[0]) else split(" ")[0] end;
def isScript($n): cmdWord | endswith("/hooks/" + $n);'

# ── refresh_hook_matcher SETTINGS HOOKSCRIPT — bring an ALREADY-registered entry's matcher up to date.
# An entry written by an older installer carries an older matcher, and a stale one undercounts forever,
# silently, in exactly the sessions that use the tool most. Still idempotent: a matcher that already
# agrees is left untouched, and this never adds, removes or reorders an entry.
refresh_hook_matcher()
{
    if ! "$jqBin" -e --arg cmd "$2" --arg m "$3" --arg n "ripwire-nudge.sh" "$jqIsScript"'
        any((.hooks.PreToolUse // [])[]?; (any(.hooks[]?; isScript($n))) and ((.matcher != $m) or (any(.hooks[]?; isScript($n) and .command != $cmd))))' \
        "$1" >/dev/null 2>&1; then
        echo "ripwire PreToolUse hook already registered in $1 ($2) — nothing to do."
        return 0
    fi
    mk_tmp "$1"
    if "$jqBin" --arg cmd "$2" --arg m "$3" --arg n "ripwire-nudge.sh" "$jqIsScript"'
        .hooks.PreToolUse |= map( if any(.hooks[]?; isScript($n))
                                  then .matcher = $m | .hooks |= map( if isScript($n) then .command = $cmd else . end )
                                  else . end )' \
        "$1" >"$tmp" && [ -s "$tmp" ] && mv "$tmp" "$1"; then
        echo "ripwire PreToolUse hook already registered in $1 — refreshed its matcher to \"$3\"."
    else
        rm -f "$tmp"
        echo "skills/install.sh: could not refresh the matcher in $1 (is it valid JSON?); nothing changed." >&2
        return 1
    fi
}

# ── install_claude_route SETTINGS — register hooks/ripwire-claude-route.sh as a UserPromptSubmit hook.
# SEPARATE FROM the PreToolUse merge below, and called from BOTH of its paths, deliberately: that
# function returns early when the nudge entry already exists, so folding the router into its "add"
# branch would mean every machine that ran --hook before 2026-09-02 never gets the router, silently,
# forever. Idempotent the same way refresh_hook_matcher is — an entry that already names this command
# is refreshed in place, never appended a second time.
#
# The D1 lesson, applied: the success echo is inside the `&& mv` chain, so a jq failure or an empty
# temp file prints the failure line and leaves settings.json untouched. An installer that announces a
# change it did not make is worse than one that fails loudly.
install_claude_route()
{
    routeScript="$( dirname "$src" )/hooks/ripwire-claude-route.sh"
    [ -f "$routeScript" ] || {
        echo "skills/install.sh: hooks/ripwire-claude-route.sh is missing beside $src; router not registered." >&2
        return 1
    }
    chmod +x "$routeScript" 2>/dev/null || true
    routeCmd="$( hook_cmd "$routeScript" )" || return 1

    if "$jqBin" -e --arg n "ripwire-claude-route.sh" "$jqIsScript"'
        any((.hooks.UserPromptSubmit // [])[]?.hooks[]?; isScript($n))' "$1" >/dev/null 2>&1; then
        mk_tmp "$1"
        if "$jqBin" --arg cmd "$routeCmd" --arg n "ripwire-claude-route.sh" "$jqIsScript"'
            .hooks.UserPromptSubmit |= map( .hooks |= map( if isScript($n) then .command = $cmd else . end ) )' \
            "$1" >"$tmp" && [ -s "$tmp" ] && mv "$tmp" "$1"; then
            echo "ripwire UserPromptSubmit router already registered in $1 — command refreshed to $routeCmd."
        else
            rm -f "$tmp"
            echo "skills/install.sh: could not refresh the router command in $1 (is it valid JSON?); nothing changed." >&2
            return 1
        fi
        return 0
    fi

    echo "skills/install.sh --hook will add this OPT-IN, advisory-only entry to $1:"
    echo "  hooks.UserPromptSubmit += [{ matcher: \"*\", hooks: [{ type: \"command\", command: \"$routeCmd\" }] }]"
    echo "  behavior: asks ripwire --help-task before the first tool is chosen and, ONLY at high"
    echo "            confidence, adds one paste-ready command as context. It never blocks a prompt."
    echo "  counting: appends one row per prompt to ~/.ripwire/routing.jsonl carrying a CHECKSUM and"
    echo "            byte length of the prompt and a hashed session id — never the prompt text."
    echo "            RIPWIRE_ROUTE_METER=0 opts out of that without disabling routing."

    mk_tmp "$1"
    if "$jqBin" --arg cmd "$routeCmd" '
        .hooks //= {} |
        .hooks.UserPromptSubmit //= [] |
        .hooks.UserPromptSubmit += [{ matcher: "*", hooks: [{ type: "command", command: $cmd, timeout: 8 }] }]
    ' "$1" >"$tmp" && [ -s "$tmp" ] && mv "$tmp" "$1"; then
        echo "done. Registered ripwire's UserPromptSubmit prompt router in $1."
    else
        rm -f "$tmp"
        echo "skills/install.sh: could not merge the router into $1 (is it valid JSON?); nothing changed." >&2
        return 1
    fi
}

# ── The two SubagentStart registrations (the routing note below, the opt-in primer further down) and the primer's PreToolUse
# task stash share one test and one merge. subagent_start_names SETTINGS SCRIPT: is an entry naming SCRIPT, from any copy,
# registered under SubagentStart? merge_script_hook SETTINGS EVENT MATCHER SCRIPT CMD WHAT WAS [TIMEOUT] [MATCHER_ON_REFRESH]:
# refresh that event's entry naming SCRIPT in place (its command; its timeout only when TIMEOUT is given; its matcher only
# when MATCHER_ON_REFRESH is 1), or add exactly one (MATCHER, timeout TIMEOUT, default 5); print "ripwire WHAT WAS" only once
# the file is really written (the D1 lesson at install_claude_route). It touches no other event and no other script's entry.
subagent_start_names()
{
    "$jqBin" -e --arg n "$2" "$jqIsScript"'
        any((.hooks.SubagentStart // [])[]?.hooks[]?; isScript($n))' "$1" >/dev/null 2>&1
}

merge_script_hook()
{
    mk_tmp "$1"
    setTo=false; [ -n "${8:-}" ] && setTo=true
    setMatcher=false; [ "${9:-0}" = 1 ] && setMatcher=true
    if "$jqBin" --arg ev "$2" --arg m "$3" --arg n "$4" --arg cmd "$5" --argjson to "${8:-5}" --argjson setTo "$setTo" \
        --argjson setM "$setMatcher" "$jqIsScript"'
        .hooks //= {} |
        if any((.hooks[$ev] // [])[]?.hooks[]?; isScript($n))
        then .hooks[$ev] |= map( if any(.hooks[]?; isScript($n))
                                 then ( (if $setM then .matcher = $m else . end)
                                        | .hooks |= map( if isScript($n) then (.command = $cmd | if $setTo then .timeout = $to else . end) else . end ) )
                                 else . end )
        else .hooks[$ev] = ((.hooks[$ev] // []) + [{ matcher: $m, hooks: [{ type: "command", command: $cmd, timeout: $to }] }])
        end
    ' "$1" >"$tmp" && [ -s "$tmp" ] && mv "$tmp" "$1"; then
        echo "ripwire $6 $7"
    else
        rm -f "$tmp"
        echo "skills/install.sh: could not merge the $6 into $1 (is it valid JSON?); nothing changed." >&2
        return 1
    fi
}

# ── install_claude_subagent_route SETTINGS HOOKCMD — register `ripwire-nudge.sh --subagent-start` as a SubagentStart
# hook (lane HK2, 2026-11-21). Claude Code's Explore and Plan subagents do not load CLAUDE.md, so the routing a user
# pasted there never reaches the agent that searches the codebase; this entry puts a short factual note into those two
# (and only those two: the script decides by agent_type, so the matcher stays "*" and the decision stays in one place).
# SEPARATE FROM the PreToolUse merge and called from BOTH of its paths, for install_claude_route's reason: a machine
# that ran --hook before this mode existed has the nudge entry already, and would otherwise never gain this one.
# Idempotent the same way: an entry that names the nudge script under SubagentStart, from any copy, has its command
# refreshed in place; otherwise exactly one is added. It never touches another SubagentStart entry — not a user's own,
# not the opt-in primer's (hooks/ripwire-subagent-primer.sh, --hook-subagent-primer).
install_claude_subagent_route()
{
    subRouteCmd="$2 --subagent-start"
    if subagent_start_names "$1" "ripwire-nudge.sh"; then
        subRouteWas="already registered in $1 — command refreshed to $subRouteCmd."
    else
        subRouteWas="registered in $1."
        echo "skills/install.sh --hook will add this OPT-IN, advisory-only entry to $1:"
        echo "  hooks.SubagentStart += [{ matcher: \"*\", hooks: [{ type: \"command\", command: \"$subRouteCmd\" }] }]"
        echo "  behavior: adds a routing note of under 400 B to the context of each new Explore or Plan subagent, the two"
        echo "            built-in types that do not load CLAUDE.md (which call ranks files for a task, which prints one"
        echo "            symbol, which names the tests). Every other subagent type gets nothing. Cannot block a subagent;"
        echo "            silent outside a git work tree and without ripwire or jq on PATH. It does not follow the meter's"
        echo "            arm: a control-arm session's subagents get it too."
        echo "  switch:   RIPWIRE_SUBAGENT_ROUTE=0 turns it off; =all sends it to every subagent type."
        echo "  counting: none. It writes no row and no file unless RIPWIRE_SUBAGENT_ROUTE_LOG names one."
        echo "  remove:   delete the SubagentStart entry whose command ends in \"ripwire-nudge.sh --subagent-start\" from $1."
    fi

    merge_script_hook "$1" SubagentStart "*" "ripwire-nudge.sh" "$subRouteCmd" "SubagentStart routing note" "$subRouteWas"
}

# ── install_claude_legend_seen SETTINGS — register hooks/ripwire-legend-seen.sh (lane LS1, 2026-11-18).
# The one hook this installer registers that REWRITES a tool call: before a `ripwire` Bash command it inserts
# --legend-seen=<this session's file>, so the answer leaves out legend definitions the agent already received; after
# it, it records which definitions the received stdout carried. Four events: PreToolUse + PostToolUse on Bash, and
# SessionStart + PreCompact on every source, which forget the file (a compacted or resumed context no longer holds what
# it read). Called from BOTH paths of install_claude_hook for the reason install_claude_route gives, and idempotent the
# same way: an event that already names this script has its command refreshed in place, never a second entry.
install_claude_legend_seen()
{
    seenScript="$( dirname "$src" )/hooks/ripwire-legend-seen.sh"
    [ -f "$seenScript" ] || {
        echo "skills/install.sh: hooks/ripwire-legend-seen.sh is missing beside $src; legend-seen hook not registered." >&2
        return 1
    }
    chmod +x "$seenScript" 2>/dev/null || true
    seenCmd="$( hook_cmd "$seenScript" )" || return 1

    if "$jqBin" -e --arg n "ripwire-legend-seen.sh" "$jqIsScript"'
        . as $root | all(("PreToolUse","PostToolUse","SessionStart","PreCompact"); . as $k | any(($root.hooks[$k] // [])[]?.hooks[]?; isScript($n)))' \
        "$1" >/dev/null 2>&1; then
        seenWas="already registered in $1 — command refreshed to $seenCmd."
    else
        seenWas="registered in $1."
        echo "skills/install.sh will add the legend-seen entries to $1 (ON BY DEFAULT, ruling 111; --no-hook-legend-seen skips it):"
        echo "  hooks.PreToolUse / PostToolUse += [{ matcher: \"Bash\", hooks: [{ type: \"command\", command: \"$seenCmd\" }] }]"
        echo "  hooks.SessionStart / PreCompact += [{ matcher: \"*\", hooks: [{ type: \"command\", command: \"$seenCmd\" }] }]"
        echo "  behavior: REWRITES a ripwire Bash command, only by inserting --legend-seen=<session file> after the binary"
        echo "            word, so its answer leaves out legend definitions this session already received (rows unchanged)."
        echo "            Never a permission decision: the rewritten call goes through your normal permission flow."
        echo "  state:    entry hashes only, under ~/.ripwire/legend-seen/<session>/; forgotten on resume/clear/compact."
        echo "            RIPWIRE_LEGEND_SEEN=0 turns it off."
    fi

    # One pass: refresh the command of every entry that names this script, add the events that have none.
    mk_tmp "$1"
    if "$jqBin" --arg n "ripwire-legend-seen.sh" --arg cmd "$seenCmd" "$jqIsScript"'
        .hooks //= {} |
        .hooks |= with_entries( .value |= map( .hooks |= map( if isScript($n) then .command = $cmd else . end ) ) ) |
        reduce (["PreToolUse","Bash"], ["PostToolUse","Bash"], ["SessionStart","*"], ["PreCompact","*"]) as [$k, $m] (.;
            if any((.hooks[$k] // [])[]?.hooks[]?; isScript($n)) then .
            else .hooks[$k] = ((.hooks[$k] // []) + [{ matcher: $m, hooks: [{ type: "command", command: $cmd, timeout: 10 }] }]) end )
    ' "$1" >"$tmp" && [ -s "$tmp" ] && mv "$tmp" "$1"; then
        echo "ripwire legend-seen hook $seenWas"
    else
        rm -f "$tmp"
        echo "skills/install.sh: could not merge the legend-seen hook into $1 (is it valid JSON?); nothing changed." >&2
        return 1
    fi
}

# ── install_claude_subagent_primer SETTINGS — register hooks/ripwire-subagent-primer.sh (lane AR1, 2026-11-19).
# A SubagentStart hook: it puts the two-line ripwire brief (orient with --for; --quality-delta then --test-gate before
# done) into every subagent's context at spawn. Its own opt-in, NOT part of --hook: it is the instrument of a registered
# A/B (docs/EVALS.md, "Subagent primer"), and an operator must be able to install the main-session hooks without it.
# Idempotent the way install_claude_legend_seen is: an entry that names this script, from any copy, has its command
# refreshed in place; otherwise exactly one entry is added. Never touches another event.
install_claude_subagent_primer()
{
    primerScript="$( dirname "$src" )/hooks/ripwire-subagent-primer.sh"
    [ -f "$primerScript" ] || {
        echo "skills/install.sh: hooks/ripwire-subagent-primer.sh is missing beside $src; subagent primer not registered." >&2
        return 1
    }
    chmod +x "$primerScript" 2>/dev/null || true
    primerCmd="$( hook_cmd "$primerScript" )" || return 1

    if subagent_start_names "$1" "ripwire-subagent-primer.sh"; then
        primerWas="already registered in $1 — command refreshed to $primerCmd."
    else
        primerWas="registered in $1."
        echo "skills/install.sh --hook-subagent-primer will add this OPT-IN, advisory-only entry to $1:"
        echo "  hooks.SubagentStart += [{ matcher: \"*\", hooks: [{ type: \"command\", command: \"$primerCmd\" }] }]"
        echo "  hooks.PreToolUse   += [{ matcher: \"Agent|Task\", hooks: [{ type: \"command\", command: \"$primerCmd\" }] }]"
        echo "  behavior: adds ~660 B of context to each new subagent (orient with --for first; after the last edit, commit,"
        echo "            --quality-delta=BASE..HEAD, --test-gate). When the spawn's task is known (the PreToolUse entry keeps it"
        echo "            for 120 s, readable by you only), the subagent gets \`ripwire --brief=<its task>\` (3.5-7 KB) instead."
        echo "            Cannot block a subagent; silent outside a git work tree or without ripwire."
        echo "            RIPWIRE_SUBAGENT_BRIEF=0 (or subagent_brief=off in meter.conf) keeps the two-step text only."
        echo "  switch:   RIPWIRE_SUBAGENT_PRIMER=0 (or subagent_primer=off in ~/.ripwire/meter.conf) turns it off;"
        echo "            =auto randomizes per subagent for the registered A/B."
        echo "  counting: one row per subagent start in ~/.ripwire/subagent_primer.jsonl (session id, agent id and type,"
        echo "            arm, delivered) — never the brief or any text. RIPWIRE_SUBAGENT_METER=0 opts out of counting."
    fi

    merge_script_hook "$1" SubagentStart "*" "ripwire-subagent-primer.sh" "$primerCmd" "subagent primer hook" "$primerWas" 15 || return 1
    # The primer's second entry (lane SUBAGENT-PRIMER, 2026-11-27): the same script as a PreToolUse hook on Agent|Task, which keeps
    # the spawn's task for the SubagentStart half (a SubagentStart payload carries no prompt). It prints nothing and never decides
    # a permission. A refresh also restores its matcher.
    merge_script_hook "$1" PreToolUse "Agent|Task" "ripwire-subagent-primer.sh" "$primerCmd" "subagent primer task stash:" \
        "PreToolUse Agent|Task entry in $1." "" 1
}

install_claude_subagent_primer_hook()
{
    settings="$( abs_root "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "${CLAUDE_CONFIG_DIR:-}" )/settings.json" || exit 2
    find_jq
    [ -n "$jqBin" ] || { echo "skills/install.sh --hook-subagent-primer needs jq on PATH to safely merge $settings (not found)." >&2; exit 1; }
    mkdir -p "$( dirname "$settings" )"
    [ -f "$settings" ] || ( umask 077; echo '{}' >"$settings" )
    settings="$( resolve_link "$settings" )" || exit 1
    install_claude_subagent_primer "$settings" || exit 1
}

# ── --hook: register hooks/ripwire-nudge.sh as a PreToolUse hook in ~/.claude/settings.json ──
# Advisory-only (see the script's own header): never blocks/denies/rewrites a tool call, fires at most
# once per session per pattern. Idempotent — re-running does not duplicate the settings.json entry.
install_claude_hook()
{
    settings="$( abs_root "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "${CLAUDE_CONFIG_DIR:-}" )/settings.json" || exit 2
    hookScript="$( dirname "$src" )/hooks/ripwire-nudge.sh"
    chmod +x "$hookScript" 2>/dev/null || true
    hookCmd="$( hook_cmd "$hookScript" )" || exit 1

    find_jq
    if [ -z "$jqBin" ]; then
        echo "skills/install.sh --hook needs jq on PATH to safely merge $settings (not found)." >&2
        echo "Add these by hand instead:" >&2
        echo "  hooks.PreToolUse  += [{\"matcher\":\"$hookMatcher\",\"hooks\":[{\"type\":\"command\",\"command\":\"$hookCmd\"}]}]" >&2
        echo "  hooks.SessionStart += [{\"matcher\":\"startup|resume|clear\",\"hooks\":[{\"type\":\"command\",\"command\":\"$hookCmd --session-start\"}]}]" >&2
        echo "  hooks.SubagentStart += [{\"matcher\":\"*\",\"hooks\":[{\"type\":\"command\",\"command\":\"$hookCmd --subagent-start\",\"timeout\":5}]}]" >&2
        exit 1
    fi

    mkdir -p "$( dirname "$settings" )"
    [ -f "$settings" ] || ( umask 077; echo '{}' >"$settings" )   # a first-time config stays owner-only, as it always was
    settings="$( resolve_link "$settings" )" || exit 1

    if "$jqBin" -e --arg n "ripwire-nudge.sh" "$jqIsScript"'
        any((.hooks.PreToolUse // [])[]?.hooks[]?; isScript($n))' \
        "$settings" >/dev/null 2>&1; then
        refresh_hook_matcher "$settings" "$hookCmd" "$hookMatcher" || return $?
        install_claude_route "$settings" || return $?
        install_claude_subagent_route "$settings" "$hookCmd"
        return $?
    fi

    # Read and Glob are in the matcher deliberately: the whole-file read is the largest token sink in
    # an agent loop and the one default a skill description cannot intercept (a skill fires only if the
    # agent first recognizes a moment AND spends a call to load it; Read needs neither). SessionStart
    # is the proactive half — the PreToolUse nudges only speak after a default has already been chosen.
    # mcp__ripwire__.* is in the matcher for the OTHER job this hook does: the substitution meter counts
    # ripwire's own calls as the numerator, and an agent that prefers the MCP server to the CLI would
    # otherwise be a pure undercount (docs/SUBSTITUTION_METER.md). The hook never nudges those calls,
    # nor the native edit tools, which are metered only so the EDIT band can see them.
    echo "skills/install.sh --hook will add these OPT-IN, advisory-only entries to $settings:"
    echo "  hooks.PreToolUse  += [{ matcher: \"$hookMatcher\", hooks: [{ type: \"command\", command: \"$hookCmd\" }] }]"
    echo "  hooks.SessionStart += [{ matcher: \"startup|resume|clear\", hooks: [{ type: \"command\", command: \"$hookCmd --session-start\" }] }]"
    echo "  behavior: never blocks/denies/rewrites a tool call, and since 2026-09-02 never speaks on it"
    echo "            either — the advisory nudge was measured inert and retired (docs/EVALS.md §4)."
    echo "            What remains on PreToolUse is the substitution meter and the router's adoption"
    echo "            observation. The SessionStart entry still injects the use-when guidance."
    echo "  counting: appends one JSONL row per observed call to ~/.ripwire/substitution.jsonl, and that row"
    echo "            carries the RAW file path (Read, and the Edit/Write/MultiEdit/NotebookEdit target), RAW"
    echo "            grep/glob pattern, the first 200 B of the RAW command (Bash), or an MCP verb's symbol/file"
    echo "            arguments you just passed, plus the absolute repo path and session id — in cleartext."
    echo "            Local-only: this file is never transmitted anywhere, but it has no automatic retention"
    echo "            limit and grows for as long as counting stays on. RIPWIRE_METER=0 opts out of counting"
    echo "            (the nudge itself keeps working). Details: docs/SUBSTITUTION_METER.md."
    echo "  remove:   delete those two entries from $settings (or re-run with the entries already absent)."
    if [ "${wantLegendSeen:-0}" -eq 1 ]; then
        echo "  also:     --hook registers the legend-seen hook too (ON BY DEFAULT, owner ruling 111). That one DOES"
        echo "            REWRITE a ripwire Bash command — it announces itself below, before it writes. Pass"
        echo "            --no-hook-legend-seen for the advisory entries alone."
    fi

    mk_tmp "$settings"
    if "$jqBin" --arg cmd "$hookCmd" --arg scmd "$hookCmd --session-start" --arg m "$hookMatcher" '
        .hooks //= {} |
        .hooks.PreToolUse //= [] |
        .hooks.PreToolUse += [{ matcher: $m, hooks: [{ type: "command", command: $cmd }] }] |
        .hooks.SessionStart //= [] |
        .hooks.SessionStart += [{ matcher: "startup|resume|clear", hooks: [{ type: "command", command: $scmd }] }]
    ' "$settings" >"$tmp" && [ -s "$tmp" ] && mv "$tmp" "$settings"; then
        echo "done. Registered ripwire's PreToolUse meter + SessionStart primer hooks in $settings."
    else
        rm -f "$tmp"
        echo "skills/install.sh: could not merge $settings (is it valid JSON?); nothing changed." >&2
        exit 1
    fi
    install_claude_route "$settings" || return $?
    install_claude_subagent_route "$settings" "$hookCmd"
}

# ── the legend-seen hook, ON BY DEFAULT with a --hook install (owner ruling 111, 2026-11-20) ───────────────────────
# It is the one hook here that REWRITES a tool call (it inserts --legend-seen=FILE after the binary word of a ripwire
# command). That is why it was opt-in until 111: lane LG1 then MEASURED what it saves (~3,184 B/call, a ~19 % cut in
# total answer bytes from call 2, results/LG1_LEGEND_1120/READOUT.md §1.3) and the ruling turned the default over. What
# the default does NOT change: the hook's behaviour, the disclosure printed before anything is written, and the two
# ways off (--no-hook-legend-seen here, RIPWIRE_LEGEND_SEEN=0 at run time). A plain skills install still never touches
# settings.json — the default rides on a hook install, not on every run. One function per client.
install_claude_legend_seen_hook()
{
    settings="$( abs_root "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "${CLAUDE_CONFIG_DIR:-}" )/settings.json" || exit 2
    find_jq
    [ -n "$jqBin" ] || { echo "skills/install.sh --hook-legend-seen needs jq on PATH to safely merge $settings (not found)." >&2; exit 1; }
    mkdir -p "$( dirname "$settings" )"
    [ -f "$settings" ] || ( umask 077; echo '{}' >"$settings" )
    settings="$( resolve_link "$settings" )" || exit 1
    install_claude_legend_seen "$settings" || exit 1
}

install_codex_legend_seen_hook()
{
    settings="$( abs_root "${CODEX_HOME:-$HOME/.codex}" "${CODEX_HOME:-}" )/hooks.json" || exit 2
    adapter="$( dirname "$src" )/hooks/ripwire-codex-legend-seen.sh"
    shared="$( dirname "$src" )/hooks/ripwire-legend-seen.sh"
    [ -f "$adapter" ] && [ -f "$shared" ] || { echo "skills/install.sh: hooks/ripwire-codex-legend-seen.sh or its shared hook is missing beside $src" >&2; exit 1; }
    chmod +x "$adapter" "$shared" 2>/dev/null || true
    cmd="$( hook_cmd "$adapter" )" || exit 1
    find_jq
    [ -n "$jqBin" ] || { echo "skills/install.sh --codex --hook-legend-seen needs jq on PATH to safely merge $settings (not found)." >&2; exit 1; }
    mkdir -p "$( dirname "$settings" )"
    [ -f "$settings" ] || ( umask 077; echo '{}' >"$settings" )
    settings="$( resolve_link "$settings" )" || exit 1
    echo "skills/install.sh --codex --hook-legend-seen will add or refresh these entries in $settings:"
    echo "  PreToolUse / PostToolUse (^Bash\$) and SessionStart (startup|resume|clear|compact) -> $cmd"
    echo "  behavior: REWRITES a ripwire Bash command, only by inserting --legend-seen=<session file> after the binary"
    echo "            word, so its answer leaves out legend definitions this session already received (rows unchanged)."
    echo "            Never a permission decision. RIPWIRE_LEGEND_SEEN=0 turns it off."
    mk_tmp "$settings"
    if "$jqBin" --arg cmd "$cmd" --arg n "ripwire-codex-legend-seen.sh" "$jqIsScript"'
        .hooks //= {} |
        .hooks |= with_entries( .value |= map( .hooks |= map( if isScript($n) then .command = $cmd else . end ) ) ) |
        reduce (["PreToolUse","^Bash$"], ["PostToolUse","^Bash$"], ["SessionStart","^(startup|resume|clear|compact)$"]) as [$k, $m] (.;
            if any((.hooks[$k] // [])[]?.hooks[]?; isScript($n)) then .
            else .hooks[$k] = ((.hooks[$k] // []) + [{ matcher: $m, hooks: [{ type: "command", command: $cmd, timeout: 10,
                statusMessage: "Ripwire legend-seen" }] }]) end )
    ' "$settings" >"$tmp" && [ -s "$tmp" ] && mv "$tmp" "$settings"; then
        echo "done. Registered ripwire's legend-seen hook in $settings. Open /hooks in Codex to review and trust it."
    else
        rm -f "$tmp"
        echo "skills/install.sh: could not merge $settings (is it valid JSON?); nothing changed." >&2
        exit 1
    fi
}

# opencode loads plugin modules, not shell hooks: write ONE loader file into its global plugin dir that imports this
# checkout's plugin (hooks/opencode/ripwire-legend-seen.js), so the plugin and the shell hook it calls stay version-
# controlled here. Rewriting the loader is idempotent.
install_opencode_legend_seen_hook()
{
    plugin="$( dirname "$src" )/hooks/opencode/ripwire-legend-seen.js"
    [ -f "$plugin" ] && [ -f "$( dirname "$src" )/hooks/ripwire-legend-seen.sh" ] || {
        echo "skills/install.sh: hooks/opencode/ripwire-legend-seen.js or its shared hook is missing beside $src" >&2; exit 1; }
    chmod +x "$( dirname "$src" )/hooks/ripwire-legend-seen.sh" 2>/dev/null || true
    pdir="$( abs_root "${XDG_CONFIG_HOME:-$HOME/.config}" "${XDG_CONFIG_HOME:-}" )/opencode/plugin" || exit 2
    find_jq
    [ -n "$jqBin" ] || { echo "skills/install.sh --opencode --hook-legend-seen needs jq on PATH to quote the plugin path (not found)." >&2; exit 1; }
    mkdir -p "$pdir"
    loader="$pdir/ripwire-legend-seen.js"
    quoted="$( printf '%s' "$plugin" | "$jqBin" -Rs . )" || exit 1
    echo "skills/install.sh --opencode --hook-legend-seen will write $loader, a loader for $plugin:"
    echo "  behavior: REWRITES a ripwire bash command, only by inserting --legend-seen=<session file> after the binary"
    echo "            word, so its answer leaves out legend definitions this session already received (rows unchanged)."
    echo "            RIPWIRE_LEGEND_SEEN=0 turns it off; delete $loader to remove it."
    mk_tmp "$loader"
    {
        echo "// ripwire legend-seen loader — written by skills/install.sh --opencode --hook-legend-seen; delete this file to remove it."
        echo "import { pathToFileURL } from \"node:url\";"
        echo "export const { RipwireLegendSeen } = await import( pathToFileURL( $quoted ).href );"
    } >"$tmp" && [ -s "$tmp" ] && mv "$tmp" "$loader" || { rm -f "$tmp"; echo "skills/install.sh: could not write $loader" >&2; exit 1; }
    echo "done. Registered ripwire's legend-seen plugin for opencode in $loader."
}

install_codex_hook()
{
    settings="$( abs_root "${CODEX_HOME:-$HOME/.codex}" "${CODEX_HOME:-}" )/hooks.json" || exit 2
    hookScript="$( dirname "$src" )/hooks/ripwire-codex-nudge.sh"
    sharedHook="$( dirname "$src" )/hooks/ripwire-nudge.sh"
    routeScript="$( dirname "$src" )/hooks/ripwire-codex-route.sh"
    [ -f "$hookScript" ] && [ -f "$sharedHook" ] && [ -f "$routeScript" ] || {
        echo "skills/install.sh: bundled Codex hooks are missing beside $src" >&2
        exit 1
    }
    chmod +x "$hookScript" "$sharedHook" "$routeScript" 2>/dev/null || true
    hookCmd="$( hook_cmd "$hookScript" )" || exit 1
    routeCmd="$( hook_cmd "$routeScript" )" || exit 1

    find_jq
    if [ -z "$jqBin" ]; then
        echo "skills/install.sh --codex --hook needs jq on PATH to safely merge $settings (not found)." >&2
        exit 1
    fi

    mkdir -p "$( dirname "$settings" )"
    [ -f "$settings" ] || ( umask 077; echo '{}' >"$settings" )   # a first-time config stays owner-only, as it always was
    settings="$( resolve_link "$settings" )" || exit 1

    echo "skills/install.sh --codex --hook will add or refresh advisory-only entries in $settings."
    mk_tmp "$settings"
    if "$jqBin" --arg cmd "$hookCmd" --arg scmd "$hookCmd --session-start" --arg rcmd "$routeCmd" --arg m "$codexHookMatcher" '
        .hooks //= {} |
        .hooks.PreToolUse //= [] |
        .hooks.SessionStart //= [] |
        .hooks.UserPromptSubmit //= [] |
        if any(.hooks.PreToolUse[]?.hooks[]?; .command == $cmd) then
            .hooks.PreToolUse |= map(if any(.hooks[]?; .command == $cmd) then .matcher = $m else . end)
        else
            .hooks.PreToolUse += [{ matcher: $m, hooks: [{ type: "command", command: $cmd,
                timeout: 3, statusMessage: "Checking for a cheaper Ripwire CLI query" }] }]
        end |
        if any(.hooks.SessionStart[]?.hooks[]?; .command == $scmd) then
            .hooks.SessionStart |= map(if any(.hooks[]?; .command == $scmd) then .matcher = "^(startup|resume|clear|compact)$" else . end)
        else
            .hooks.SessionStart += [{ matcher: "^(startup|resume|clear|compact)$", hooks: [{ type: "command",
                command: $scmd, timeout: 3, statusMessage: "Loading Ripwire CLI-first guidance",
                additionalContextLimit: 2000 }] }]
        end |
        if any(.hooks.UserPromptSubmit[]?.hooks[]?; .command == $rcmd) then
            .hooks.UserPromptSubmit |= map(if any(.hooks[]?; .command == $rcmd) then .matcher = ".*" else . end)
        else
            .hooks.UserPromptSubmit += [{ matcher: ".*", hooks: [{ type: "command", command: $rcmd,
                timeout: 6, statusMessage: "Selecting a focused Ripwire CLI route",
                additionalContextLimit: 3000 }] }]
        end
    ' "$settings" >"$tmp" && [ -s "$tmp" ] && mv "$tmp" "$settings"; then
        echo "done. Registered Ripwire's Codex prompt router + PreToolUse nudge + SessionStart primer in $settings."
        echo "Open /hooks in Codex to review and trust the installed command hooks."
    else
        rm -f "$tmp"
        echo "skills/install.sh: could not merge $settings (is it valid JSON?); nothing changed." >&2
        exit 1
    fi
}

mode="claude"
explicitMode=0
wantHook=0
wantLegendSeen=1          # owner ruling 111 (2026-11-20): the legend-seen hook is ON BY DEFAULT with a hook install
legendSeenOnly=0          # --hook-legend-seen: install THAT hook and nothing else (the pre-111 invocation, kept)
wantSubagentPrimer=0
wantContributor=0
wantLocatorAgent=1        # owner ruling 189 (2026-11-22): ON BY DEFAULT for Claude; --no-locator-agent / RIPWIRE_NO_LOCATOR_AGENT opt out
[ -z "${RIPWIRE_NO_LOCATOR_AGENT:-}" ] || wantLocatorAgent=0
explicitPath=""
for arg in "$@"; do
    case "$arg" in
        --hook) wantHook=1 ;;
        --hook-legend-seen) legendSeenOnly=1; wantLegendSeen=1 ;;
        --no-hook-legend-seen) wantLegendSeen=0 ;;
        --hook-subagent-primer) wantSubagentPrimer=1 ;;
        --opencode) mode="opencode"; explicitMode=1 ;;
        --contributor) wantContributor=1 ;;
        --no-locator-agent) wantLocatorAgent=0 ;;
        --codex) mode="codex"; explicitMode=1 ;;
        --openclaw) mode="openclaw"; explicitMode=1 ;;
        --codex-legacy) mode="codex-legacy"; explicitMode=1 ;;
        --claude) mode="claude"; explicitMode=1 ;;
        --hermes) mode="hermes"; explicitMode=1 ;;
        --*) echo "skills/install.sh: unknown option $arg" >&2; exit 2 ;;
        *) [ -z "$explicitPath" ] || { echo "skills/install.sh: only one destination path is allowed" >&2; exit 2; }
           explicitPath="$arg"; mode="path"; explicitMode=1 ;;
    esac
done

if [ "$legendSeenOnly" -eq 1 ] && [ "$wantLegendSeen" -eq 0 ]; then
    echo "skills/install.sh: --hook-legend-seen and --no-hook-legend-seen contradict each other; pass one" >&2
    exit 2
fi

# ── RULING 111: the default, applied where this installer registers the --hook entries. Called from every --hook
#    path and from --opencode (whose only hook IS this one). NOT from a plain skills install, which touches no
#    settings file, and NOT from --hook-subagent-primer alone, which is its own narrow single-hook installer.
install_legend_seen_default()
{
    [ "$wantLegendSeen" -eq 1 ] || return 0
    case "$1" in
        claude)             install_claude_legend_seen_hook ;;
        codex|codex-legacy) install_codex_legend_seen_hook ;;
        opencode)           install_opencode_legend_seen_hook ;;
    esac
}

# --hook-subagent-primer is hook-only and Claude-only (SubagentStart is a Claude Code event): it never installs skills.
# It composes with --hook and --hook-legend-seen in one run.
if [ "$wantSubagentPrimer" -eq 1 ]; then
    case "$mode" in
        # RULING 111 applies to a --hook install, so it reaches here only WITH --hook: this flag is its own narrow
        # single-hook installer and subagentprimercheck (N) asserts that footprint ("registers no other event").
        # --hook-legend-seen beside it still installs that hook alone, exactly as it did before the default.
        claude) if [ "$wantHook" -eq 1 ]; then
                    install_claude_hook
                    install_legend_seen_default claude
                elif [ "$legendSeenOnly" -eq 1 ]; then
                    install_claude_legend_seen_hook
                fi
                install_claude_subagent_primer_hook ;;
        *) echo "skills/install.sh: --hook-subagent-primer is a Claude Code hook (SubagentStart); it takes --claude (the default) only" >&2; exit 2 ;;
    esac
    exit 0
fi
# --hook-legend-seen is hook-only too, for the client named (Claude by default): it never installs skills.
if [ "$legendSeenOnly" -eq 1 ]; then
    case "$mode" in
        claude)              [ "$wantHook" -eq 0 ] || install_claude_hook; install_claude_legend_seen_hook ;;
        codex|codex-legacy)  [ "$wantHook" -eq 0 ] || install_codex_hook; install_codex_legend_seen_hook ;;
        opencode)            install_opencode_legend_seen_hook ;;
        *) echo "skills/install.sh: --hook-legend-seen takes --claude (the default), --codex or --opencode" >&2; exit 2 ;;
    esac
    exit 0
fi
if [ "$mode" = "opencode" ]; then
    # opencode has no advisory hook slot: the legend-seen plugin is the ONLY thing this installer has for it, and
    # ruling 111 makes it the default — so --opencode alone now installs it instead of refusing and naming the flag.
    if [ "$wantLegendSeen" -eq 1 ]; then
        install_opencode_legend_seen_hook
        exit 0
    fi
    echo "skills/install.sh: --opencode --no-hook-legend-seen leaves nothing to install (the legend-seen plugin is the only thing this installer has for opencode); opencode reads ripwire's skills through AGENTS.md (ripwire wrap opencode)" >&2
    exit 2
fi

# Preserve the established hook-only invocation: `--hook` changes settings but does not also install skills.
if [ "$wantHook" -eq 1 ] && [ "$explicitMode" -eq 0 ]; then
    install_claude_hook
    install_legend_seen_default claude
    exit 0
fi

case "$mode" in
    codex) dst="$( abs_root "${AGENTS_HOME:-$HOME/.agents}" "${AGENTS_HOME:-}" )/skills" || exit 2 ;;
    # openclaw resolves to the SAME root Codex uses -- openclaw's docs call it a "compatibility skill
    # root". A repeated value, not a second code path. But it is conditional, and the condition is worth
    # a line of output rather than a support thread: openclaw skips this root entirely unless its state
    # dir is the default. Verified against docs.openclaw.ai, 2026-09-08.
    openclaw) dst="$( abs_home )/.agents/skills" || exit 2
              # NOT ${AGENTS_HOME:-...}: that is Codex's variable. openclaw honours no such override, so a
              # user who relocated AGENTS_HOME for Codex would be told to install where openclaw never looks.
              if [ -n "${AGENTS_HOME:-}" ] && [ "${AGENTS_HOME}" != "$HOME/.agents" ]; then
                  echo "skills/install.sh: note — AGENTS_HOME is set to '${AGENTS_HOME}', but openclaw does not read it." >&2
                  echo "  Installing to $dst, which is where openclaw actually looks." >&2
              fi
              if [ -n "${OPENCLAW_STATE_DIR:-}" ] && [ "${OPENCLAW_STATE_DIR}" != "$HOME/.openclaw" ]; then
                  echo "skills/install.sh: WARNING — OPENCLAW_STATE_DIR is set to '${OPENCLAW_STATE_DIR}'." >&2
                  echo "  openclaw only reads $dst when its state dir is the default $HOME/.openclaw." >&2
                  echo "  Installing there anyway; openclaw will not discover these skills until that is unset." >&2
              fi ;;
    codex-legacy) dst="$( abs_root "${CODEX_HOME:-$HOME/.codex}" "${CODEX_HOME:-}" )/skills" || exit 2 ;;
    claude) dst="$( abs_root "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "${CLAUDE_CONFIG_DIR:-}" )/skills" || exit 2 ;;
    hermes) dst="$( abs_root "${HERMES_HOME:-$HOME/.hermes}" "${HERMES_HOME:-}" )/skills" || exit 2 ;;
    path) dst="$explicitPath" ;;
esac
mkdir -p "$dst"

# ── WHAT COUNTS AS OURS, AND WHY A LINK IS VERIFIED (issue #334, 2026-09-25). On Windows without symlink
#    privilege (Developer Mode off), Git Bash's `ln -sfn DIR DEST` EXITS 0 and leaves an EMPTY DIRECTORY, even
#    under MSYS=winsymlinks:nativestrict. This installer used to trust that exit status: it printed `installed`
#    sixteen times, wrote all sixteen names to the manifest and announced "16 ripwire skills active" over sixteen
#    empty directories. So a link is now checked by its RESULT (a symlink whose SKILL.md reads back); when it
#    did not take, the skill is COPIED (`cp -R`) and reported as `copied`; when the copy fails too, it is
#    reported as `FAILED`, left out of the count and the manifest, and the run exits 1.
#    A copy is a real directory, so the prune/install paths below must recognise it as ours without ever
#    touching a user's own directory that happens to share a shipped ripwire-* name.
#
#    CODERABBIT C4 (train 20, reproduced 2026-09-25): the first cut of this clause trusted the PREVIOUS
#    MANIFEST alone — any name that installer had once written was "ours" forever after, even once the user
#    had deleted the link and dropped their own directory of files there. `rm -rf`, no message, rc 0. A
#    manifest entry records what THIS installer once put at a path; it is not evidence about what is at that
#    path NOW, so it must never by itself justify removing a real directory.
#
#    A real directory is ours ONLY when it is provably ours, checked in this order:
#    1. MARKED: it carries the copy marker this installer writes at copy time, and the marker NAMES THIS
#       DIRECTORY (B2, train 20 review). The marker holds the skill name it was copied as, so a marked copy the
#       user renamed to another ripwire-* name to keep their edits (the marker then names a different skill) is
#       theirs and is kept; before, an empty marker proved "some ripwire copy", not "this path", and the renamed
#       copy was pruned as stale with the edits in it. The contract: a copied skill is ours (edits made inside it
#       are replaced on re-run); edit your own copy under a different name.
#       A NAMELESS (empty) marker, written by 0.6.4 candidates before B2, proves nothing about the path: such a
#       directory is ours only when its name is a shipped skill and its contents, the marker aside, are
#       byte-identical to that skill. Otherwise it is kept.
#    2. EMPTY TREE: it holds no non-directory entry at ANY depth (B1). This is #334's actual shape. On Windows
#       without symlink privilege every 0.6.0-0.6.3 installer's unverified `ln -sfn DIR DEST` left an empty
#       directory, and on the SECOND run DEST was already a real directory, so coreutils/MSYS `ln` resolved the
#       target to DEST/basename(DIR) and left an empty ripwire-x/ripwire-x inside it. A tree of empty
#       directories holds no user bytes. `find` failing anywhere (an unreadable subdirectory, no find at all)
#       means the tree is NOT provably empty, so its errors are handled explicitly and never read as "empty".
#    3. BYTE-IDENTICAL: its contents are identical (`diff -rq`) to the skill this checkout ships under that name
#       right now: an unmarked deep copy holding nothing but ripwire's own bytes. Residual gap, deliberately on
#       the safe side: an unmarked copy of a skill whose bytes have changed since is kept as the user's.
#    Byte comparison needs no extra bookkeeping and degrades safely (no shipped skill left under that name =>
#    no match => left alone). Anything that fails every check is left untouched, reported with a one-line
#    `kept` note, and never added to the manifest's ours set: the manifest is written from what this run
#    itself verified, never from what a past run once claimed.
#    test/skillinstallcheck.sh sections (F)-(I) drive all of it with an `ln` that behaves like that Git Bash.
copyMarker=".ripwire-installed-copy"
# shipped_src_for NAME — the skill directory this checkout would install under NAME right now, or nothing if
# this checkout ships no such skill (a stale/renamed name, or a Hermes-native one outside non-hermes modes).
shipped_src_for()
{
    if [ -d "$src/$1" ]; then
        printf '%s\n' "$src/$1"
    elif [ "$mode" = "hermes" ] && [ -d "$src/hermes/$1" ]; then
        printf '%s\n' "$src/hermes/$1"
    fi
}
# tree_holds_no_files DIR: true only when `find` read the WHOLE tree cleanly and found no non-directory entry
# in it. find's own failure (rc != 0: an unreadable subdirectory, find missing) returns false: not provably
# empty, so the directory is kept rather than removed.
tree_holds_no_files()
{
    _files="$( find "$1" ! -type d 2>/dev/null )" || return 1
    [ -z "$_files" ]
}
dir_is_ours()
{
    # $1 = the real directory found at the destination; $2 = the shipped skill dir to byte-compare it
    # against, or "" when this checkout ships nothing under that name.
    if [ -f "$1/$copyMarker" ]; then
        _marked="$( cat "$1/$copyMarker" 2>/dev/null )" || return 1
        [ "$_marked" = "$( basename "$1" )" ] && return 0           # our copy, of this very skill
        [ -z "$_marked" ] || return 1                                 # a copy of ANOTHER skill: the user's
        # a nameless marker (pre-B2 candidate): ours only if byte-identical to the skill shipped under this name
        [ -n "${2:-}" ] && [ -d "$2" ] && diff -rq -x "$copyMarker" "$2" "$1" >/dev/null 2>&1
        return
    fi
    tree_holds_no_files "$1" \
        || { [ -n "${2:-}" ] && [ -d "$2" ] && diff -rq "$2" "$1" >/dev/null 2>&1; }
}
# a real directory this installer cannot prove it created — the one shape it must never remove
foreign_dir() { [ -d "$1" ] && [ ! -L "$1" ] && ! dir_is_ours "$1" "${2:-}"; }
remove_ours() { if [ -d "$1" ] && [ ! -L "$1" ]; then rm -rf "$1"; else rm -f "$1"; fi; }

# PRUNE first: remove any installed ripwire-* skill that this repo no longer ships (deleted or renamed) —
# otherwise a dangling symlink (e.g. a skill removed in a consolidation) lingers forever and an agent
# routing to it hits an error and learns to distrust the whole family. `-L` also catches BROKEN symlinks
# (whose target dir was deleted), which `-e` alone would miss.
# 2026-09-06 (stranger audit): a skill whose SKILL.md front matter says `audience: contributor` is about
# working ON ripwire (ripwire-opt-remarks: clang optimization remarks while editing this tree's C++). It is
# shipped so a contributor can activate it, but it is NOT activated for a user of the tool — the release
# installer runs this script for every agent it detects on a stranger's machine. Pass --contributor to link
# those too; without it a previously linked contributor skill is pruned, so a checkout that stops being a
# contributor setup does not keep one forever.
is_contributor_skill() { grep -q '^audience: contributor' "$1/SKILL.md" 2>/dev/null; }
wanted_skill() { [ "$wantContributor" -eq 1 ] || ! is_contributor_skill "$1"; }

pruned=0
kept=0
# link_is_ours LINK NAME — may the prune remove this SYMLINK? Only one it can show ripwire made: dangling (nothing of the
# user's is behind it), recorded by the previous manifest, or pointing into THIS checkout (compared by whole path
# components: "$src"/*, never a string prefix, so a sibling directory sharing the checkout's name does not match).
# A live link anywhere else is the user's own asset that merely happens to be named ripwire-* (#293 review).
oldManifest="$dst/.ripwire-manifest-v1"
link_is_ours()
{
    if [ ! -e "$1" ]; then return 0; fi
    if [ -f "$oldManifest" ] && grep -qxF "skill=$2" "$oldManifest" 2>/dev/null; then return 0; fi
    _t="$( readlink "$1" 2>/dev/null )" || return 1
    case "$_t" in
        /*|[A-Za-z]:[/\\]*) ;;
        *) _t="$( dirname "$1" )/$_t" ;;
    esac
    case "$_t" in */..|*/../*) return 1 ;; esac                # a `..` can leave the checkout after the prefix matched
    case "$_t" in "$src"/*) return 0 ;; esac
    return 1
}
for existing in "$dst"/ripwire-*; do
    [ -e "$existing" ] || [ -L "$existing" ] || continue      # skip the literal glob when nothing matches
    name="$( basename "$existing" )"
    why=""
    if [ ! -d "$src/$name" ]; then
        # Hermes-native skills live at skills/hermes/<name>, not skills/<name>: a linked one is still
        # shipped, so it is kept — unless it stopped being wanted (contributor-only without
        # --contributor), in which case it is pruned like any other.
        if [ "$mode" = "hermes" ] && [ -d "$src/hermes/$name" ] && wanted_skill "$src/hermes/$name"; then
            continue
        fi
        why="stale $name (no longer shipped)"
    elif ! wanted_skill "$src/$name"; then
        why="$name (contributor-only; pass --contributor to activate it)"
    fi
    [ -n "$why" ] || continue
    if [ -L "$existing" ]; then
        if ! link_is_ours "$existing" "$name"; then
            echo "kept $name: a symlink ripwire did not create (yours) — remove it yourself if it is stale"
            kept=$(( kept + 1 ))
            continue
        fi
    elif [ ! -d "$existing" ]; then
        # a regular file is never something this installer made (it creates links, and copied directories)
        echo "kept $name: not installed by ripwire (your own file) — remove it yourself if it is stale"
        kept=$(( kept + 1 ))
        continue
    fi
    if foreign_dir "$existing" "$( shipped_src_for "$name" )"; then
        # Before #334 this was `rm -f` on a directory, which failed and aborted the whole install under set -e.
        # C4: a name this run once wrote to the manifest is not by itself proof this directory is still ours —
        # it may now be the user's own, so it is kept, never removed, on a manifest entry alone.
        echo "kept $name: not installed by ripwire (your own directory) — remove it yourself if it is stale"
        kept=$(( kept + 1 ))
        continue
    fi
    remove_ours "$existing"
    echo "pruned $why"
    pruned=$(( pruned + 1 ))
done

# install_skill SRC NAME [NOTE] — link SRC into $dst/NAME, verify the link by its result, fall back to a
# copy, and say which of the three happened. Returns 1 only when the skill is not usable at all.
count=0
copied=0
failed=0
installedNames=""
install_skill()
{
    target="$dst/$2"
    if foreign_dir "$target" "$1"; then
        # `ln -sfn` onto a real directory links INSIDE it and reports success, so this is checked before
        # attempting either. It is not a FAILURE (nothing this run was asked to do went wrong) — it is the
        # user's own directory (C4), so it is left exactly as it is and not counted as installed.
        echo "kept $2: not installed by ripwire (your own directory)"
        kept=$(( kept + 1 ))
        return 0
    fi
    if [ -f "$target" ] && [ ! -L "$target" ]; then
        # a regular file is never something this installer made (it creates links, and copied directories): the user's
        # own file at a shipped skill's name is kept, like a foreign directory, not replaced (#293: refuse foreign files)
        echo "kept $2: not installed by ripwire (your own file)"
        kept=$(( kept + 1 ))
        return 0
    fi
    if [ -e "$target" ] || [ -L "$target" ]; then
        remove_ours "$target"
    fi
    if ln -sfn "$1" "$target" 2>/dev/null && [ -L "$target" ] && [ -f "$target/SKILL.md" ]; then
        echo "installed $2 -> $target${3:-}"
    else
        [ -e "$target" ] || [ -L "$target" ] && remove_ours "$target"
        if cp -R "${1%/}" "$target" 2>/dev/null && cmp -s "$1/SKILL.md" "$target/SKILL.md" \
           && printf '%s\n' "$2" >"$target/$copyMarker" 2>/dev/null; then
            echo "copied $2 -> $target${3:-} (a symlink did not take here, e.g. Windows without Developer Mode; re-run after updating ripwire to refresh the copy)"
            copied=$(( copied + 1 ))
        else
            [ -e "$target" ] || [ -L "$target" ] && remove_ours "$target"
            echo "FAILED $2: neither a symlink nor a copy produced a readable $target/SKILL.md" >&2
            failed=$(( failed + 1 ))
            return 1
        fi
    fi
    count=$(( count + 1 ))
    installedNames="$installedNames$2
"
}

skipped=0
for d in "$src"/ripwire-*/; do
    name="$( basename "$d" )"
    if ! wanted_skill "$d"; then
        echo "skipped $name (contributor-only: about working on ripwire itself; pass --contributor to activate it)"
        skipped=$(( skipped + 1 ))
        continue
    fi
    install_skill "$d" "$name" || true
done

# Hermes loads the flat Agent-Skills-standard set AND Hermes-native skills (skills/hermes/ripwire-*, e.g.
# the ripwire-repo-map skill purpose-built for Hermes) side by side out of one directory — verified live:
# both formats index together, so --hermes deploys both and no prefer/fallback logic is needed.
# The ripwire-* glob is the SAME name scope the flat install loop and the prune loop above use, and it is
# load-bearing: this loop `ln -sfn`s each entry into the user's skill home under its own name, `ln -sfn`
# unlinks an existing regular file first, and the prune loop only ever looks at ripwire-*. A hermes/ entry
# without the prefix would therefore delete a same-named USER skill and then be impossible to prune. Only
# ripwire-repo-map lives there today, so this is the asymmetry being closed, not a bug being observed.
# Gate: test/hermesinstallcheck.sh arm 7.
if [ "$mode" = "hermes" ]; then
    for nd in "$src"/hermes/ripwire-*/; do
        [ -d "$nd" ] || continue                                  # skip the literal glob when nothing matches
        [ -f "$nd/SKILL.md" ] || continue                        # a Hermes-native skill is a dir with SKILL.md
        nname="$( basename "$nd" )"
        [ -d "$src/$nname" ] && continue                         # flat set already linked it above; one link wins
        if ! wanted_skill "$nd"; then
            echo "skipped $nname (contributor-only: about working on ripwire itself; pass --contributor to activate it)"
            skipped=$(( skipped + 1 ))
            continue
        fi
        install_skill "$nd" "$nname" " (Hermes-native skill)" || true
    done
fi

# The active skill directory is an agent-facing API surface, not a bag of best-effort links. The manifest
# records exactly the skills that were VERIFIED usable above (linked or copied), so `ripwire --doctor
# --agent=codex` can distinguish a complete install from a stale/missing/extra skill without trusting the
# checkout it came from. A skill that FAILED is not in it: listing it is the #334 lie in another file.
manifestTmp="$( mktemp "$dst/.ripwire-manifest-v1.tmp.XXXXXX" )"
{
    echo 'version=1'
    printf '%s' "$installedNames" | while IFS= read -r n; do echo "skill=$n"; done
} >"$manifestTmp"
mv "$manifestTmp" "$dst/.ripwire-manifest-v1"
if [ "$failed" -gt 0 ]; then
    # Not `exit 1` here: a requested --hook is still registered below, and the status is set at the very end.
    echo "skills/install.sh: $failed ripwire skill(s) FAILED to install into $dst (listed above); $count usable, ${copied} of them copied, ${kept} kept as yours." >&2
else
    echo "done. $count ripwire skills active in every session (${copied} copied, ${pruned} pruned, ${skipped} contributor-only skipped, ${kept} kept as yours) — every ripwire-* installed above."
fi

# ── THE LOCATOR SUBAGENT (lane LC1, 2026-11-22, owner ruling 185). A Claude Code subagent file installed beside the skills, for
#    Claude only: skills/agents/ripwire-locator.md -> ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents/ (the user scope of
#    code.claude.com/docs/en/sub-agents). It runs ripwire in its own context and hands the main thread back only edit ranges,
#    so a ~7K-token --for answer does not ride every later main-thread request. Ownership as for a skill: a symlink into this
#    checkout, verified by its result, a copy when a link does not take; a dangling link, a link into this checkout, or a
#    byte-identical file is ours and refreshed; anything else there is the user's and is kept. A checkout or staged release
#    without the file installs its skills exactly as before. Never fails the run. test/locatoragentcheck.sh (D) drives it.
install_claude_locator_agent()
{
    agentSrc="$src/agents/ripwire-locator.md"
    [ -f "$agentSrc" ] || return 0
    agentDir="$( dirname "$dst" )/agents"
    agentDst="$agentDir/ripwire-locator.md"
    if [ -L "$agentDst" ]; then
        if [ -e "$agentDst" ] && ! cmp -s "$agentDst" "$agentSrc"; then
            agentLink="$( readlink "$agentDst" 2>/dev/null )" || agentLink=""
            case "$agentLink" in
                "$src"/*) ;;
                *) echo "kept ripwire-locator: $agentDst is a symlink ripwire did not create (yours)"; return 0 ;;
            esac
        fi
        rm -f "$agentDst"
    elif [ -e "$agentDst" ]; then
        if [ ! -f "$agentDst" ] || ! cmp -s "$agentDst" "$agentSrc"; then
            echo "kept ripwire-locator: $agentDst is not ripwire's (your own file); the locator subagent was not installed"
            return 0
        fi
        rm -f "$agentDst"
    fi
    mkdir -p "$agentDir"
    if ln -s "$agentSrc" "$agentDst" 2>/dev/null && [ -L "$agentDst" ] && cmp -s "$agentDst" "$agentSrc"; then
        echo "installed subagent ripwire-locator -> $agentDst (Claude Code: delegate a code lookup to it; it returns edit ranges)"
    elif rm -f "$agentDst" && cp "$agentSrc" "$agentDst" 2>/dev/null && cmp -s "$agentDst" "$agentSrc"; then
        echo "copied subagent ripwire-locator -> $agentDst (a symlink did not take here; re-run after updating ripwire to refresh it)"
    else
        rm -f "$agentDst"
        echo "skills/install.sh: could not install the ripwire-locator subagent at $agentDst; the skills are unaffected." >&2
    fi
    return 0
}
if [ "$mode" = "claude" ]; then
    if [ "$wantLocatorAgent" -eq 1 ]; then
        install_claude_locator_agent
    else
        echo "skipped subagent ripwire-locator (--no-locator-agent / RIPWIRE_NO_LOCATOR_AGENT); a copy installed earlier is left as it is"
    fi
fi

if [ "$wantHook" -eq 1 ]; then
    case "$mode" in
        codex|codex-legacy) install_codex_hook; install_legend_seen_default codex ;;
        claude) install_claude_hook; install_legend_seen_default claude ;;
                hermes) echo "skills/install.sh: --hook is not ported to the Hermes target yet (Hermes exposes hooks: pre_tool_call in config.yaml, but hooks/ripwire-nudge.sh still switches on Claude tool names); ripwire works via the CLI/MCP server there." >&2; exit 2 ;;
        openclaw) echo "skills/install.sh: --hook is not supported for the openclaw target (openclaw's before_tool_call is a plugin API, not a shell hook slot); ripwire works via the CLI/MCP server there." >&2; exit 2 ;;
        path) echo "skills/install.sh: --hook needs --claude or --codex, not an explicit skill path" >&2; exit 2 ;;
    esac
fi

# A skill that FAILED above makes the whole run fail, after everything else it was asked to do (#334).
[ "$failed" -eq 0 ] || exit 1
