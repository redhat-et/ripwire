#!/usr/bin/env bash
# hooks/ripwire-nudge.sh — OPT-IN, ADVISORY-ONLY Claude Code PreToolUse hook.
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
    command -v ripwire >/dev/null 2>&1 || exit 0

    dir=$( printf '%s' "$input" | tr '\n' ' ' | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 \
        | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//' )
    [ -n "$dir" ] || dir="$PWD"
    git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

    session=$( printf '%s' "$input" | tr '\n' ' ' | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 \
        | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//' )
    [ -n "$session" ] || session="ppid$PPID"
    marker="${TMPDIR:-/tmp}/ripwire-nudge.${session}.session-start"
    [ -e "$marker" ] && exit 0
    : > "$marker" 2>/dev/null || true

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
    Grep) category="grep" ;;
    Read) category="read" ;;
    Glob) category="glob" ;;
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

# ---- gates: git repo + ripwire on PATH, both required, both cheap ----
command -v ripwire >/dev/null 2>&1 || exit 0
git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# ---- dedup: at most once per session (or per-PPID if the payload carries no session_id) per category
session=$( field session_id )
[ -n "$session" ] || session="ppid$PPID"
marker="${TMPDIR:-/tmp}/ripwire-nudge.${session}.${category}"
[ -e "$marker" ] && exit 0
: > "$marker" 2>/dev/null || true

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
