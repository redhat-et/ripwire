#!/usr/bin/env bash
# Install ripwire's agent skills (symlinks back to this repo's skills/, so they stay version-controlled and
# edits here take effect immediately). Default: Claude. Codex: skills/install.sh --codex. An explicit path
# remains supported for CI and other clients: skills/install.sh PATH. OPT-IN PreToolUse hook (advisory
# grep->ripwire nudge, PLAN_researchImprove2026.md B5.2): skills/install.sh --hook — a SEPARATE action,
# never bundled into the flags above, so it only ever runs on explicit invocation.
set -eu
src="$( cd "$( dirname "$0" )" && pwd )"

# ── --hook: register skills/hooks/ripwire-nudge.sh as a PreToolUse hook in ~/.claude/settings.json ──
# Advisory-only (see the script's own header): never blocks/denies/rewrites a tool call, fires at most
# once per session per pattern. Idempotent — re-running does not duplicate the settings.json entry.
install_hook()
{
    settings="$HOME/.claude/settings.json"
    hookScript="$src/hooks/ripwire-nudge.sh"
    chmod +x "$hookScript" 2>/dev/null || true

    if ! command -v jq >/dev/null 2>&1; then
        echo "skills/install.sh --hook needs jq on PATH to safely merge $settings (not found)." >&2
        echo "Add this by hand instead: hooks.PreToolUse += [{\"matcher\":\"Grep|Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"$hookScript\"}]}]" >&2
        exit 1
    fi

    mkdir -p "$( dirname "$settings" )"
    [ -f "$settings" ] || echo '{}' >"$settings"

    if jq -e --arg cmd "$hookScript" \
        'any((.hooks.PreToolUse // [])[]?.hooks[]?; .command == $cmd)' \
        "$settings" >/dev/null 2>&1; then
        echo "ripwire PreToolUse hook already registered in $settings ($hookScript) — nothing to do."
        return 0
    fi

    echo "skills/install.sh --hook will add this OPT-IN, advisory-only entry to $settings:"
    echo "  hooks.PreToolUse += [{ matcher: \"Grep|Bash\", hooks: [{ type: \"command\", command: \"$hookScript\" }] }]"
    echo "  behavior: never blocks/denies/rewrites a tool call; at most one suggestion per session per pattern."
    echo "  remove:   delete that PreToolUse entry from $settings (or re-run with the entry already absent)."

    tmp="$( mktemp )"
    jq --arg cmd "$hookScript" '
        .hooks //= {} |
        .hooks.PreToolUse //= [] |
        .hooks.PreToolUse += [{ matcher: "Grep|Bash", hooks: [{ type: "command", command: $cmd }] }]
    ' "$settings" >"$tmp" && mv "$tmp" "$settings"

    echo "done. Registered ripwire's PreToolUse nudge hook in $settings."
}

case "${1:-}" in
    --hook)   install_hook; exit 0 ;;
    --codex)  dst="${CODEX_HOME:-$HOME/.codex}/skills" ;;
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
