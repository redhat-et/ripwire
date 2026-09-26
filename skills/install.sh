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

if [ "$wantHook" -eq 1 ]; then
    case "$mode" in
        codex|codex-legacy) install_codex_hook ;;
        claude) install_claude_hook ;;
                hermes) echo "skills/install.sh: --hook is not ported to the Hermes target yet (Hermes exposes hooks: pre_tool_call in config.yaml, but hooks/ripwire-nudge.sh still switches on Claude tool names); ripwire works via the CLI/MCP server there." >&2; exit 2 ;;
        openclaw) echo "skills/install.sh: --hook is not supported for the openclaw target (openclaw's before_tool_call is a plugin API, not a shell hook slot); ripwire works via the CLI/MCP server there." >&2; exit 2 ;;
        path) echo "skills/install.sh: --hook needs --claude or --codex, not an explicit skill path" >&2; exit 2 ;;
    esac
fi

# A skill that FAILED above makes the whole run fail, after everything else it was asked to do (#334).
[ "$failed" -eq 0 ] || exit 1
