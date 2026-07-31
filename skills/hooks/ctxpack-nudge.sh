#!/usr/bin/env bash
# skills/hooks/ctxpack-nudge.sh — OPT-IN, ADVISORY-ONLY Claude Code PreToolUse hook.
#
# Nudges an agent from raw grep/rg, and from raw `git diff`/`git log`/`git show --stat`, toward the
# matching ctxpack verb. Ships INACTIVE — only registered via `skills/install.sh --hook`, never
# automatically (see PLAN_phases.md Phase B5.2 / research/2026-07/R5-agent-context-science.md: "with
# grep available, the agent defaults to it... a PreToolUse hook is the high-leverage lever" — passive
# skill-description triggering alone is measured ~30-50% reliable). Phase B9
# (PLAN_researchImprove2026.md Part 3) extends the trigger set to the git-information moments where raw
# output is weakest vs ctxpack's structured answers: `git diff` → `--situ`/`--pr-context`, `git log` →
# `--rank-by=churn`/`--map-diff`, `git show --stat` → `--map-diff`. Deliberately excluded: `git status`
# and state-changing commands (add/commit/push/pull/checkout/branch) — nudging those is spam.
#
# Design posture (non-negotiable — do not "improve" this into a blocker):
#   - NEVER blocks, denies, or rewrites the tool call. Always permissionDecision "allow" when it
#     speaks at all; never "deny"/"ask"; never "updatedInput". Any internal failure (missing jq,
#     malformed JSON, no git, no ctxpack) degrades to silent allow — exit 0, no stdout.
#   - Fires at MOST once per session per pattern (Grep, Bash-grep, git-diff, git-log, and git-show-stat
#     are separate patterns), via a marker file under $TMPDIR keyed by session_id (falls back to PPID
#     if the payload has none) — an agent sees each nudge once, not on every call.
#   - Only fires when the target directory is inside a git repo AND a `ctxpack` binary is on PATH.
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
#   printf '%s' "$PRETOOLUSE_JSON" | skills/hooks/ctxpack-nudge.sh
set -u

input="$( cat )"

# ---- fast bail: only Grep and Bash can ever match; every other tool (Edit/Write/Read/...) exits
#      here after a single grep over stdin, before spawning anything. ----
tool_name=$( printf '%s' "$input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 \
    | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//' )

case "$tool_name" in
    Grep) category="grep" ;;
    Bash) category="" ;;   # decided below, once the command text is available
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

if [ "$tool_name" = "Bash" ]
then
    cmd=$( field command )
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
        exit 0
    fi
fi

# ---- target dir: cwd from the payload, else this process's cwd ----
dir=$( field cwd )
[ -n "$dir" ] || dir="$PWD"

# ---- gates: git repo + ctxpack on PATH, both required, both cheap ----
command -v ctxpack >/dev/null 2>&1 || exit 0
git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# ---- dedup: at most once per session (or per-PPID if the payload carries no session_id) per category
session=$( field session_id )
[ -n "$session" ] || session="ppid$PPID"
marker="${TMPDIR:-/tmp}/ctxpack-nudge.${session}.${category}"
[ -e "$marker" ] && exit 0
: > "$marker" 2>/dev/null || true

# ---- build the one-time suggestion (one short message per category; the git-diff/git-log/
#      git-show-stat messages each name a SINGLE best verb for the observed form, not a catalog) ----
case "$category" in
    grep)
        pattern=$( field pattern )
        [ -n "$pattern" ] || pattern="PATTERN"
        pattern=$( printf '%s' "$pattern" | cut -c1-60 )
        msg="ctxpack tip: for text search across this repo, \`ctxpack . --grep='${pattern}'\` returns each match WITH its enclosing function/class — often replacing the read-the-file-for-context step. Conceptual/multi-word task instead of a literal string? \`ctxpack . --for=\"...\"\`. Symbol usage/call sites? \`ctxpack . --callers=SYM\` / \`--uses=SYM\`. (One-time tip this session; \`ctxpack --help\` lists everything.)"
        ;;
    git-diff)
        msg="ctxpack tip: for a diff, \`ctxpack . --situ\` maps the mid-task blast radius, tests-to-run, and forgotten co-change partners in one pass (swap in \`--pr-context\` when reviewing a PR). (One-time tip this session; \`ctxpack --help\` lists everything.)"
        ;;
    git-log)
        msg="ctxpack tip: for git log, \`ctxpack . --rank-by=churn\` ranks who's actually churning that code (swap in \`--map-diff\` for what changed structurally). (One-time tip this session; \`ctxpack --help\` lists everything.)"
        ;;
    git-show-stat)
        msg="ctxpack tip: for a commit's --stat summary, \`ctxpack . --map-diff\` shows what changed structurally, not just line counts. (One-time tip this session; \`ctxpack --help\` lists everything.)"
        ;;
    *)
        msg="ctxpack tip: this looks like a recursive grep/rg over the tree. \`ctxpack . --grep='PATTERN'\` (literal) or \`ctxpack . --for=\"task in words\"\` (conceptual) often answers the same question with the enclosing symbol attached, in far fewer tokens than raw grep + file reads. (One-time tip this session; \`ctxpack --help\` lists everything.)"
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
