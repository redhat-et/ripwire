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
# skills/install.sh --hook (Claude) or skills/install.sh --codex --hook (Codex). --openclaw installs to
# that same cross-agent root (openclaw's own "compatibility skill root"); it has no hook slot.
set -eu
src="$( cd "$( dirname "$0" )" && pwd )"

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
jqIsScript='def isScript($n): (.command // "") | split(" ")[0] | endswith("/hooks/" + $n);'

# ── refresh_hook_matcher SETTINGS HOOKSCRIPT — bring an ALREADY-registered entry's matcher up to date.
# An entry written by an older installer carries an older matcher, and a stale one undercounts forever,
# silently, in exactly the sessions that use the tool most. Still idempotent: a matcher that already
# agrees is left untouched, and this never adds, removes or reorders an entry.
refresh_hook_matcher()
{
    if ! jq -e --arg cmd "$2" --arg m "$3" --arg n "ripwire-nudge.sh" "$jqIsScript"'
        any((.hooks.PreToolUse // [])[]?; (any(.hooks[]?; isScript($n))) and ((.matcher != $m) or (any(.hooks[]?; isScript($n) and .command != $cmd))))' \
        "$1" >/dev/null 2>&1; then
        echo "ripwire PreToolUse hook already registered in $1 ($2) — nothing to do."
        return 0
    fi
    tmp="$( mktemp )"
    if jq --arg cmd "$2" --arg m "$3" --arg n "ripwire-nudge.sh" "$jqIsScript"'
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

    if jq -e --arg n "ripwire-claude-route.sh" "$jqIsScript"'
        any((.hooks.UserPromptSubmit // [])[]?.hooks[]?; isScript($n))' "$1" >/dev/null 2>&1; then
        tmp="$( mktemp )"
        if jq --arg cmd "$routeScript" --arg n "ripwire-claude-route.sh" "$jqIsScript"'
            .hooks.UserPromptSubmit |= map( .hooks |= map( if isScript($n) then .command = $cmd else . end ) )' \
            "$1" >"$tmp" && [ -s "$tmp" ] && mv "$tmp" "$1"; then
            echo "ripwire UserPromptSubmit router already registered in $1 — command refreshed to $routeScript."
        else
            rm -f "$tmp"
            echo "skills/install.sh: could not refresh the router command in $1 (is it valid JSON?); nothing changed." >&2
            return 1
        fi
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
    settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
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

    if jq -e --arg n "ripwire-nudge.sh" "$jqIsScript"'
        any((.hooks.PreToolUse // [])[]?.hooks[]?; isScript($n))' \
        "$settings" >/dev/null 2>&1; then
        refresh_hook_matcher "$settings" "$hookScript" "$hookMatcher" || return $?
        install_claude_route "$settings"
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
    echo "  hooks.PreToolUse  += [{ matcher: \"$hookMatcher\", hooks: [{ type: \"command\", command: \"$hookScript\" }] }]"
    echo "  hooks.SessionStart += [{ matcher: \"startup|resume|clear\", hooks: [{ type: \"command\", command: \"$hookScript --session-start\" }] }]"
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
wantContributor=0
explicitPath=""
for arg in "$@"; do
    case "$arg" in
        --hook) wantHook=1 ;;
        --contributor) wantContributor=1 ;;
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

# Preserve the established hook-only invocation: `--hook` changes settings but does not also install skills.
if [ "$wantHook" -eq 1 ] && [ "$explicitMode" -eq 0 ]; then
    install_claude_hook
    exit 0
fi

case "$mode" in
    codex) dst="${AGENTS_HOME:-$HOME/.agents}/skills" ;;
    # openclaw resolves to the SAME root Codex uses -- openclaw's docs call it a "compatibility skill
    # root". A repeated value, not a second code path. But it is conditional, and the condition is worth
    # a line of output rather than a support thread: openclaw skips this root entirely unless its state
    # dir is the default. Verified against docs.openclaw.ai, 2026-09-08.
    openclaw) dst="$HOME/.agents/skills"
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
    codex-legacy) dst="${CODEX_HOME:-$HOME/.codex}/skills" ;;
    claude) dst="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills" ;;
    hermes) dst="${HERMES_HOME:-$HOME/.hermes}/skills" ;;
    path) dst="$explicitPath" ;;
esac
mkdir -p "$dst"

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
for existing in "$dst"/ripwire-*; do
    [ -e "$existing" ] || [ -L "$existing" ] || continue      # skip the literal glob when nothing matches
    name="$( basename "$existing" )"
    if [ ! -d "$src/$name" ]; then
        # Hermes-native skills live at skills/hermes/<name>, not skills/<name>: a linked one is still
        # shipped, so it is kept — unless it stopped being wanted (contributor-only without
        # --contributor), in which case it is pruned like any other.
        if [ "$mode" = "hermes" ] && [ -d "$src/hermes/$name" ] && wanted_skill "$src/hermes/$name"; then
            continue
        fi
        rm -f "$existing"
        echo "pruned stale $name (no longer shipped)"
        pruned=$(( pruned + 1 ))
    elif ! wanted_skill "$src/$name"; then
        rm -f "$existing"
        echo "pruned $name (contributor-only; pass --contributor to activate it)"
        pruned=$(( pruned + 1 ))
    fi
done

count=0
skipped=0
for d in "$src"/ripwire-*/; do
    name="$( basename "$d" )"
    if ! wanted_skill "$d"; then
        echo "skipped $name (contributor-only: about working on ripwire itself; pass --contributor to activate it)"
        skipped=$(( skipped + 1 ))
        continue
    fi
    ln -sfn "$d" "$dst/$name"
    echo "installed $name -> $dst/$name"
    count=$(( count + 1 ))
done

# Hermes loads the flat Agent-Skills-standard set AND Hermes-native skills (skills/hermes/*, e.g. the
# ripwire-repo-map skill purpose-built for Hermes) side by side out of one directory — verified live:
# both formats index together, so --hermes deploys both and no prefer/fallback logic is needed.
if [ "$mode" = "hermes" ]; then
    for nd in "$src"/hermes/*/; do
        [ -d "$nd" ] || continue                                  # skip the literal glob when nothing matches
        [ -f "$nd/SKILL.md" ] || continue                        # a Hermes-native skill is a dir with SKILL.md
        nname="$( basename "$nd" )"
        [ -d "$src/$nname" ] && continue                         # flat set already linked it above; one link wins
        if ! wanted_skill "$nd"; then
            echo "skipped $nname (contributor-only: about working on ripwire itself; pass --contributor to activate it)"
            skipped=$(( skipped + 1 ))
            continue
        fi
        ln -sfn "$nd" "$dst/$nname"
        echo "installed $nname -> $dst/$nname (Hermes-native skill)"
        count=$(( count + 1 ))
    done
fi

# The active skill directory is an agent-facing API surface, not a bag of best-effort links. Record the
# exact shipped set only after every link succeeds so `ripwire --doctor --agent=codex` can distinguish a
# complete install from a stale/missing/extra skill without trusting the checkout it came from.
manifestTmp="$( mktemp "$dst/.ripwire-manifest-v1.tmp.XXXXXX" )"
{
    echo 'version=1'
    for d in "$src"/ripwire-*/; do
        wanted_skill "$d" && echo "skill=$( basename "$d" )"
    done
    if [ "$mode" = "hermes" ]; then
        for nd in "$src"/hermes/*/; do
            [ -d "$nd" ] || continue
            [ -f "$nd/SKILL.md" ] || continue
            nname="$( basename "$nd" )"
            [ -d "$src/$nname" ] && continue
            wanted_skill "$nd" && echo "skill=$nname"
        done
    fi
} >"$manifestTmp"
mv "$manifestTmp" "$dst/.ripwire-manifest-v1"
echo "done. $count ripwire skills active in every session (${pruned} pruned, ${skipped} contributor-only skipped) — every ripwire-* installed above."

if [ "$wantHook" -eq 1 ]; then
    case "$mode" in
        codex|codex-legacy) install_codex_hook ;;
        claude) install_claude_hook ;;
                hermes) echo "skills/install.sh: --hook is not ported to the Hermes target yet (Hermes exposes hooks: pre_tool_call in config.yaml, but hooks/ripwire-nudge.sh still switches on Claude tool names); ripwire works via the CLI/MCP server there." >&2; exit 2 ;;
        openclaw) echo "skills/install.sh: --hook is not supported for the openclaw target (openclaw's before_tool_call is a plugin API, not a shell hook slot); ripwire works via the CLI/MCP server there." >&2; exit 2 ;;
        path) echo "skills/install.sh: --hook needs --claude or --codex, not an explicit skill path" >&2; exit 2 ;;
    esac
fi
