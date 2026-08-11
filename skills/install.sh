#!/usr/bin/env bash
# Install ripwire's agent skills (symlinks back to this repo's skills/, so they stay version-controlled and
# edits here take effect immediately). Default: Claude. Codex: skills/install.sh --codex installs to the
# current cross-agent ~/.agents/skills discovery root; --codex-legacy retains the older CODEX_HOME/skills
# destination. An explicit path remains supported for CI and other clients: skills/install.sh PATH. OPT-IN PreToolUse hook (advisory
# grep->ripwire nudge B5.2): skills/install.sh --hook — a SEPARATE action,
# never bundled into the flags above, so it only ever runs on explicit invocation.
set -eu
src="$( cd "$( dirname "$0" )" && pwd )"

# ── the PreToolUse matcher, in one place. It is not cosmetic: a matcher decides which tool calls the
#    hook is ever SHOWN. Read/Glob are here because the whole-file read is the largest token sink in an
#    agent loop and the one default a skill description cannot intercept; mcp__ripwire__ is here for the
#    hook's other job, the substitution meter (docs/SUBSTITUTION_METER.md), whose numerator would
#    otherwise miss every agent that prefers the MCP server to the CLI.
hookMatcher="Read|Glob|Grep|Bash|mcp__ripwire__"

# ── refresh_hook_matcher SETTINGS HOOKSCRIPT — bring an ALREADY-registered entry's matcher up to date.
# An entry written by an older installer carries an older matcher, and a stale one undercounts forever,
# silently, in exactly the sessions that use the tool most. Still idempotent: a matcher that already
# agrees is left untouched, and this never adds, removes or reorders an entry.
refresh_hook_matcher()
{
    if ! jq -e --arg cmd "$2" --arg m "$hookMatcher" \
        'any((.hooks.PreToolUse // [])[]?; (any(.hooks[]?; .command == $cmd)) and (.matcher != $m))' \
        "$1" >/dev/null 2>&1; then
        echo "ripwire PreToolUse hook already registered in $1 ($2) — nothing to do."
        return 0
    fi
    tmp="$( mktemp )"
    jq --arg cmd "$2" --arg m "$hookMatcher" \
        '.hooks.PreToolUse |= map( if any(.hooks[]?; .command == $cmd) then .matcher = $m else . end )' \
        "$1" >"$tmp" && mv "$tmp" "$1"
    echo "ripwire PreToolUse hook already registered in $1 — refreshed its matcher to \"$hookMatcher\"."
}

# ── --hook: register hooks/ripwire-nudge.sh as a PreToolUse hook in ~/.claude/settings.json ──
# Advisory-only (see the script's own header): never blocks/denies/rewrites a tool call, fires at most
# once per session per pattern. Idempotent — re-running does not duplicate the settings.json entry.
install_hook()
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
        refresh_hook_matcher "$settings" "$hookScript"
        return 0
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
    echo "  behavior: never blocks/denies/rewrites a tool call; at most one suggestion per session per pattern."
    echo "  counting: appends one JSONL row per observed call to ~/.ripwire/substitution.jsonl (RIPWIRE_METER=0 opts out)."
    echo "  remove:   delete those two entries from $settings (or re-run with the entries already absent)."

    tmp="$( mktemp )"
    jq --arg cmd "$hookScript" --arg scmd "$hookScript --session-start" --arg m "$hookMatcher" '
        .hooks //= {} |
        .hooks.PreToolUse //= [] |
        .hooks.PreToolUse += [{ matcher: $m, hooks: [{ type: "command", command: $cmd }] }] |
        .hooks.SessionStart //= [] |
        .hooks.SessionStart += [{ matcher: "startup|resume|clear", hooks: [{ type: "command", command: $scmd }] }]
    ' "$settings" >"$tmp" && mv "$tmp" "$settings"

    echo "done. Registered ripwire's PreToolUse nudge + SessionStart primer hooks in $settings."
}

case "${1:-}" in
    --hook)   install_hook; exit 0 ;;
    --codex)  dst="${AGENTS_HOME:-$HOME/.agents}/skills" ;;
    --codex-legacy) dst="${CODEX_HOME:-$HOME/.codex}/skills" ;;
    --claude) dst="$HOME/.claude/skills" ;;
    "")       dst="$HOME/.claude/skills" ;;
    *)        dst="$1" ;;
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
echo "done. $count ripwire skills active in every session (${pruned} stale pruned) — every ripwire-* above."
