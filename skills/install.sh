#!/usr/bin/env bash
# Install ripwire's agent skills (symlinks back to this repo's skills/, so they stay version-controlled and
# edits here take effect immediately). Default: Claude. Codex: skills/install.sh --codex installs to the
# current cross-agent ~/.agents/skills discovery root; --codex-legacy retains the older CODEX_HOME/skills
# destination. An explicit path remains supported for CI and other clients: skills/install.sh PATH.
# Add --hook explicitly to install the advisory PreToolUse + SessionStart hook for the selected client:
# skills/install.sh --hook (Claude) or skills/install.sh --codex --hook (Codex).
set -eu
src="$( cd "$( dirname "$0" )" && pwd )"

# ── the PreToolUse matcher, in one place. It is not cosmetic: a matcher decides which tool calls the
#    hook is ever SHOWN. Read/Glob are here because the whole-file read is the largest token sink in an
#    agent loop and the one default a skill description cannot intercept; mcp__ripwire__ is here for the
#    hook's other job, the substitution meter (docs/SUBSTITUTION_METER.md), whose numerator would
#    otherwise miss every agent that prefers the MCP server to the CLI.
hookMatcher="Read|Glob|Grep|Bash|mcp__ripwire__"
codexHookMatcher="^(Bash|Read|Glob|Grep|mcp__ripwire__.*)$"

# ── refresh_hook_matcher SETTINGS HOOKSCRIPT — bring an ALREADY-registered entry's matcher up to date.
# An entry written by an older installer carries an older matcher, and a stale one undercounts forever,
# silently, in exactly the sessions that use the tool most. Still idempotent: a matcher that already
# agrees is left untouched, and this never adds, removes or reorders an entry.
refresh_hook_matcher()
{
    if ! jq -e --arg cmd "$2" --arg m "$3" \
        'any((.hooks.PreToolUse // [])[]?; (any(.hooks[]?; .command == $cmd)) and (.matcher != $m))' \
        "$1" >/dev/null 2>&1; then
        echo "ripwire PreToolUse hook already registered in $1 ($2) — nothing to do."
        return 0
    fi
    tmp="$( mktemp )"
    if jq --arg cmd "$2" --arg m "$3" \
        '.hooks.PreToolUse |= map( if any(.hooks[]?; .command == $cmd) then .matcher = $m else . end )' \
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

    if jq -e --arg cmd "$routeScript" \
        'any((.hooks.UserPromptSubmit // [])[]?.hooks[]?; .command == $cmd)' "$1" >/dev/null 2>&1; then
        echo "ripwire UserPromptSubmit router already registered in $1 ($routeScript) — nothing to do."
        return 0
    fi

    echo "skills/install.sh --hook will add this OPT-IN, advisory-only entry to $1:"
    echo "  hooks.UserPromptSubmit += [{ matcher: \"*\", hooks: [{ type: \"command\", command: \"$routeScript\" }] }]"
    echo "  behavior: asks ripwire --help-task before the first tool is chosen and, ONLY at high"
    echo "            confidence, adds one paste-ready command as context. It never blocks a prompt."
    echo "  counting: appends one row per prompt to ~/.ripwire/routing.jsonl carrying a CHECKSUM and"
    echo "            byte length of the prompt and a hashed session id — never the prompt text."
    echo "            RIPWIRE_ROUTE_METER=0 opts out of that without disabling routing."

    tmp="$( mktemp )"
    if jq --arg cmd "$routeScript" '
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

# ── --hook: register hooks/ripwire-nudge.sh as a PreToolUse hook in ~/.claude/settings.json ──
# Advisory-only (see the script's own header): never blocks/denies/rewrites a tool call, fires at most
# once per session per pattern. Idempotent — re-running does not duplicate the settings.json entry.
install_claude_hook()
{
    settings="$HOME/.claude/settings.json"
    hookScript="$( dirname "$src" )/hooks/ripwire-nudge.sh"
    chmod +x "$hookScript" 2>/dev/null || true

    if ! command -v jq >/dev/null 2>&1; then
        echo "skills/install.sh --hook needs jq on PATH to safely merge $settings (not found)." >&2
        echo "Add these by hand instead:" >&2
        echo "  hooks.PreToolUse  += [{\"matcher\":\"$hookMatcher\",\"hooks\":[{\"type\":\"command\",\"command\":\"$hookScript\"}]}]" >&2
        echo "  hooks.SessionStart += [{\"matcher\":\"startup|resume|clear\",\"hooks\":[{\"type\":\"command\",\"command\":\"$hookScript --session-start\"}]}]" >&2
        exit 1
    fi

    mkdir -p "$( dirname "$settings" )"
    [ -f "$settings" ] || echo '{}' >"$settings"

    if jq -e --arg cmd "$hookScript" \
        'any((.hooks.PreToolUse // [])[]?.hooks[]?; .command == $cmd)' \
        "$settings" >/dev/null 2>&1; then
        refresh_hook_matcher "$settings" "$hookScript" "$hookMatcher" || return $?
        install_claude_route "$settings"
        return $?
    fi

    # Read and Glob are in the matcher deliberately: the whole-file read is the largest token sink in
    # an agent loop and the one default a skill description cannot intercept (a skill fires only if the
    # agent first recognizes a moment AND spends a call to load it; Read needs neither). SessionStart
    # is the proactive half — the PreToolUse nudges only speak after a default has already been chosen.
    # mcp__ripwire__ is in the matcher for the OTHER job this hook does: the substitution meter counts
    # ripwire's own calls as the numerator, and an agent that prefers the MCP server to the CLI would
    # otherwise be a pure undercount (docs/SUBSTITUTION_METER.md). The hook never nudges those calls.
    echo "skills/install.sh --hook will add these OPT-IN, advisory-only entries to $settings:"
    echo "  hooks.PreToolUse  += [{ matcher: \"$hookMatcher\", hooks: [{ type: \"command\", command: \"$hookScript\" }] }]"
    echo "  hooks.SessionStart += [{ matcher: \"startup|resume|clear\", hooks: [{ type: \"command\", command: \"$hookScript --session-start\" }] }]"
    echo "  behavior: never blocks/denies/rewrites a tool call, and since 2026-09-02 never speaks on it"
    echo "            either — the advisory nudge was measured inert and retired (docs/EVALS.md §4)."
    echo "            What remains on PreToolUse is the substitution meter and the router's adoption"
    echo "            observation. The SessionStart entry still injects the use-when guidance."
    echo "  counting: appends one JSONL row per observed call to ~/.ripwire/substitution.jsonl, and that row"
    echo "            carries the RAW file path (Read), RAW grep/glob pattern, or the first 200 B of the RAW"
    echo "            command (Bash) you just ran, plus the absolute repo path and session id — in cleartext."
    echo "            Local-only: this file is never transmitted anywhere, but it has no automatic retention"
    echo "            limit and grows for as long as counting stays on. RIPWIRE_METER=0 opts out of counting"
    echo "            (the nudge itself keeps working). Details: docs/SUBSTITUTION_METER.md."
    echo "  remove:   delete those two entries from $settings (or re-run with the entries already absent)."

    tmp="$( mktemp )"
    if jq --arg cmd "$hookScript" --arg scmd "$hookScript --session-start" --arg m "$hookMatcher" '
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
    install_claude_route "$settings"
}

install_codex_hook()
{
    settings="${CODEX_HOME:-$HOME/.codex}/hooks.json"
    hookScript="$( dirname "$src" )/hooks/ripwire-codex-nudge.sh"
    sharedHook="$( dirname "$src" )/hooks/ripwire-nudge.sh"
    routeScript="$( dirname "$src" )/hooks/ripwire-codex-route.sh"
    [ -f "$hookScript" ] && [ -f "$sharedHook" ] && [ -f "$routeScript" ] || {
        echo "skills/install.sh: bundled Codex hooks are missing beside $src" >&2
        exit 1
    }
    chmod +x "$hookScript" "$sharedHook" "$routeScript" 2>/dev/null || true

    if ! command -v jq >/dev/null 2>&1; then
        echo "skills/install.sh --codex --hook needs jq on PATH to safely merge $settings (not found)." >&2
        exit 1
    fi

    mkdir -p "$( dirname "$settings" )"
    [ -f "$settings" ] || echo '{}' >"$settings"

    echo "skills/install.sh --codex --hook will add or refresh advisory-only entries in $settings."
    tmp="$( mktemp )"
    if jq --arg cmd "$hookScript" --arg scmd "$hookScript --session-start" --arg rcmd "$routeScript" --arg m "$codexHookMatcher" '
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
explicitPath=""
for arg in "$@"; do
    case "$arg" in
        --hook) wantHook=1 ;;
        --codex) mode="codex"; explicitMode=1 ;;
        --codex-legacy) mode="codex-legacy"; explicitMode=1 ;;
        --claude) mode="claude"; explicitMode=1 ;;
        --*) echo "skills/install.sh: unknown option $arg" >&2; exit 2 ;;
        *) [ -z "$explicitPath" ] || { echo "skills/install.sh: only one destination path is allowed" >&2; exit 2; }
           explicitPath="$arg"; mode="path"; explicitMode=1 ;;
    esac
done

# Preserve the established hook-only invocation: `--hook` changes settings but does not also install skills.
if [ "$wantHook" -eq 1 ] && [ "$explicitMode" -eq 0 ]; then
    install_claude_hook
    exit 0
fi

case "$mode" in
    codex) dst="${AGENTS_HOME:-$HOME/.agents}/skills" ;;
    codex-legacy) dst="${CODEX_HOME:-$HOME/.codex}/skills" ;;
    claude) dst="$HOME/.claude/skills" ;;
    path) dst="$explicitPath" ;;
esac
mkdir -p "$dst"

# PRUNE first: remove any installed ripwire-* skill that this repo no longer ships (deleted or renamed) —
# otherwise a dangling symlink (e.g. a skill removed in a consolidation) lingers forever and an agent
# routing to it hits an error and learns to distrust the whole family. `-L` also catches BROKEN symlinks
# (whose target dir was deleted), which `-e` alone would miss.
pruned=0
for existing in "$dst"/ripwire-*; do
    [ -e "$existing" ] || [ -L "$existing" ] || continue      # skip the literal glob when nothing matches
    name="$( basename "$existing" )"
    if [ ! -d "$src/$name" ]; then
        rm -f "$existing"
        echo "pruned stale $name (no longer shipped)"
        pruned=$(( pruned + 1 ))
    fi
done

count=0
for d in "$src"/ripwire-*/; do
    name="$( basename "$d" )"
    ln -sfn "$d" "$dst/$name"
    echo "installed $name -> $dst/$name"
    count=$(( count + 1 ))
done

# The active skill directory is an agent-facing API surface, not a bag of best-effort links. Record the
# exact shipped set only after every link succeeds so `ripwire --doctor --agent=codex` can distinguish a
# complete install from a stale/missing/extra skill without trusting the checkout it came from.
manifestTmp="$( mktemp "$dst/.ripwire-manifest-v1.tmp.XXXXXX" )"
{
    echo 'version=1'
    for d in "$src"/ripwire-*/; do
        echo "skill=$( basename "$d" )"
    done
} >"$manifestTmp"
mv "$manifestTmp" "$dst/.ripwire-manifest-v1"
echo "done. $count ripwire skills active in every session (${pruned} stale pruned) — every ripwire-* above."

if [ "$wantHook" -eq 1 ]; then
    case "$mode" in
        codex|codex-legacy) install_codex_hook ;;
        claude) install_claude_hook ;;
        path) echo "skills/install.sh: --hook needs --claude or --codex, not an explicit skill path" >&2; exit 2 ;;
    esac
fi
