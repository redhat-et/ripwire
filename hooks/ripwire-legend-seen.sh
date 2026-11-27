#!/usr/bin/env bash
# hooks/ripwire-legend-seen.sh — Claude Code hook that stops a CLI session re-receiving ripwire legend definitions.
#
# WHAT IT DOES. Every ripwire answer defines its attributes in a legend, and an agent calling ripwire through the
# Bash tool receives mostly the same definitions on every call (an answer-first --for page 1 is ~12 KB of rows plus
# ~4 KB of legend). `--legend-seen=FILE` tells the binary which definitions the reader already holds, by content
# hash, and the answer leaves exactly those out. The binary is stateless; this hook is the state (lane LS1):
#   PostToolUse  after a ripwire call, pipe the stdout the agent RECEIVED into `ripwire --legend-dict=seen` and add
#                the printed entry hashes to this session's FILE. Only output received whole counts: not interrupted,
#                not an image, not over the Bash display limit (the agent may have seen only part of it). A `| head`
#                is harvested after the pipe, because that is what the agent saw.
#   PreToolUse   before a ripwire call, insert `--legend-seen=FILE` right after the binary word when FILE holds
#                anything and the binary takes the flag.
#   SessionStart / PreCompact   forget FILE (startup, resume, clear, compact, fork): the agent no longer holds what it
#                read before. A `compact_boundary` in the transcript that the hook did not see also forgets it.
#
# WHY THIS IS SAFE WITHOUT A BREAKER FOR STALE STATE. FILE holds hashes of definition TEXT. A hash from another build
# names a definition only if its text is unchanged, so a binary upgraded mid-session leaves out only definitions the
# agent read word for word; FILE can never make the binary refuse (a corrupt FILE serves the whole answer and says so
# on stderr). The one refusal left is a binary too OLD to know the flag, so the hook asks the binary first
# (`--legend-dict=seen </dev/null` exits 0 only where the flag exists) and adds nothing otherwise.
#
# PERMISSIONS. `permissionDecision` is never returned: the rewritten call goes through the user's normal permission
# flow, and the binary word stays as typed so a `Bash(ripwire:*)` rule still matches.
#
# REWRITE. Only a command whose FIRST word is `ripwire` or a path ending in `/ripwire`. The first simple command
# (up to the first quote, escape or metacharacter) is inspected; ` --legend-seen=PATH` is inserted right after the
# binary word, and everything after it passes through byte for byte. Not rewritten: `--legend*` (a posture or the
# dictionary itself), `--json`, `--mcp`, `--lsp`, `--listen`, `--batch`, help/version, `wrap`, or a state path holding
# anything but [A-Za-z0-9._/+-] (nothing to quote, so nothing to get wrong).
#
# Opt-out: RIPWIRE_LEGEND_SEEN=0. State: ${RIPWIRE_LEGEND_STATE:-${RIPWIRE_HOME:-~/.ripwire}/legend-seen}/SESSION/AGENT/
# {seen,compacts}, keyed by agent_id too (a subagent shares session_id, not context). Dirs older than 2 days expire.
# Gate: test/legendseenhookcheck.sh. ON BY DEFAULT with a hook install since owner ruling 111 (2026-11-20) — it
# rewrites commands, so the installer discloses that before it writes and --no-hook-legend-seen skips it:
# skills/install.sh --hook (or --hook-legend-seen for this hook alone; PreToolUse/PostToolUse matcher Bash,
# SessionStart and PreCompact matcher *).
# Codex: hooks/ripwire-codex-legend-seen.sh; opencode: hooks/opencode/ripwire-legend-seen.js (test/legendseenportcheck.sh).
set -u

[ "${RIPWIRE_LEGEND_SEEN:-1}" = 0 ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
input="$( cat )" || exit 0

# One jq pass, NUL-separated (read straight from the pipe: a command substitution would drop the NULs).
{ IFS= read -r -d '' ev; IFS= read -r -d '' sid; IFS= read -r -d '' agent; IFS= read -r -d '' cwd
  IFS= read -r -d '' transcript; IFS= read -r -d '' tool; IFS= read -r -d '' cmd; } < <( printf '%s' "$input" | jq -j '
    [.hook_event_name, .session_id, (.agent_id // "main"), .cwd, .transcript_path, .tool_name, (.tool_input.command // "")]
    | map((. // "" | tostring) + "\u0000") | add' 2>/dev/null )
ev="${ev:-}"; sid="${sid:-}"; agent="${agent:-main}"; cwd="${cwd:-}"; transcript="${transcript:-}"; tool="${tool:-}"; cmd="${cmd:-}"

safe_id(){ case "$1" in ''|*[!A-Za-z0-9._-]*|.|..) return 1 ;; esac; return 0; }
safe_id "$sid" || exit 0
safe_id "$agent" || agent="main"
stateRoot="${RIPWIRE_LEGEND_STATE:-${RIPWIRE_HOME:-${HOME:+$HOME/.ripwire}}/legend-seen}"
case "$stateRoot" in /*) ;; *) exit 0 ;; esac
ses="$stateRoot/$sid"; ag="$ses/$agent"; seen="$ag/seen"

# ── events that only forget ──────────────────────────────────────────────────────────────────────────────────────
case "$ev" in
    SessionStart|PreCompact)
        rm -rf "$ses" 2>/dev/null
        [ -d "$stateRoot" ] && find "$stateRoot" -mindepth 1 -maxdepth 1 -type d -mtime +2 -exec rm -rf {} + 2>/dev/null
        exit 0 ;;
    PreToolUse|PostToolUse) ;;
    *) exit 0 ;;
esac
[ "$tool" = "Bash" ] || exit 0

# ── is this a ripwire command? ───────────────────────────────────────────────────────────────────────────────────
lead="${cmd%%[![:space:]]*}"
body="${cmd#"$lead"}"
word="${body%%[[:space:]]*}"
rest="${body#"$word"}"
[ -n "$rest" ] || exit 0
case "$word" in
    ripwire|*/ripwire) ;;
    *) exit 0 ;;
esac
case "$word" in *[!A-Za-z0-9_./~+-]*) exit 0 ;; esac
injected=0
case "$rest" in " --legend-seen=$seen "*|" --legend-seen=$seen") injected=1; rest="${rest# --legend-seen=$seen}" ;; esac
# the first simple command, cut at the first metacharacter, quote or escape (newline included)
seg="$( printf '%s' "$rest" | LC_ALL=C sed -n '1{s/[|;&<>()$`"'"'"'\\].*//;p;}' )"
case " $seg " in
    *" --legend"*|*" --json"*|*" --mcp"*|*" --lsp"*|*" --listen"*|*" --batch"*|*" --help"*|*" -h "*|*" --version"*|*" -v "*|*" wrap "*)
        exit 0 ;;
esac

# ── the binary the shell will run ────────────────────────────────────────────────────────────────────────────────
case "$word" in
    [~]/*) bin="${HOME:-}/${word#?/}" ;;
    /*) bin="$word" ;;
    */*) case "$cwd" in /*) bin="$cwd/$word" ;; *) exit 0 ;; esac ;;
    *) bin="$( command -v ripwire 2>/dev/null )" || exit 0 ;;
esac
[ -n "$bin" ] && [ -f "$bin" ] && [ -x "$bin" ] || exit 0

compact_count()
{
    if [ -n "$transcript" ] && [ -f "$transcript" ] && [ -r "$transcript" ]; then
        grep -c -F '"subtype":"compact_boundary"' "$transcript" 2>/dev/null || true
    else
        printf 'na\n'
    fi
}
# a FILE written under an earlier compaction count is not something the agent still holds
if [ -d "$ag" ] && [ "$( cat "$ag/compacts" 2>/dev/null )" != "$( compact_count )" ]; then
    rm -f "$seen" "$ag/compacts"
fi

# ═══ PreToolUse: name the FILE ═══════════════════════════════════════════════════════════════════════════════════
if [ "$ev" = "PreToolUse" ]; then
    [ "$injected" = 0 ] || exit 0
    [ -s "$seen" ] || exit 0
    case "$seen" in *[!A-Za-z0-9._/+-]*) exit 0 ;; esac
    "$bin" --legend-dict=seen </dev/null >/dev/null 2>&1 || exit 0     # a binary too old for the flag gets nothing
    newcmd="$lead$word --legend-seen=$seen$rest"
    printf '%s' "$input" | jq -c --arg c "$newcmd" '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:(.tool_input + {command:$c})}}' 2>/dev/null
    exit 0
fi

# ═══ PostToolUse: add what the agent received ════════════════════════════════════════════════════════════════════
work="$( mktemp -d "${TMPDIR:-/tmp}/rwseen.XXXXXX" 2>/dev/null )" || exit 0
trap 'rm -rf "$work"' EXIT
printf '%s' "$input" | jq -j '.tool_response.stdout // (if (.tool_response|type)=="string" then .tool_response else "" end)' >"$work/out" 2>/dev/null || exit 0
meta="$( printf '%s' "$input" | jq -r '[(.tool_response.interrupted // false), (.tool_response.isImage // false)] | map(tostring) | join(" ")' 2>/dev/null )"
[ "$meta" = "false false" ] || exit 0
limit="${BASH_MAX_OUTPUT_LENGTH:-30000}"
case "$limit" in ''|*[!0-9]*) limit=30000 ;; esac
[ "$limit" -gt 30000 ] && limit=30000
outBytes="$( wc -c <"$work/out" | tr -d ' ' )"
[ "$outBytes" -gt 0 ] && [ "$outBytes" -le "$limit" ] || exit 0
"$bin" --legend-dict=seen <"$work/out" >"$work/new" 2>/dev/null || exit 0
[ -s "$work/new" ] || exit 0
mkdir -p "$ag" 2>/dev/null || exit 0
[ -f "$ag/compacts" ] || compact_count >"$ag/compacts"
touch "$seen"
cat "$seen" "$work/new" | LC_ALL=C sort -u >"$work/seen.new" && mv "$work/seen.new" "$seen"
exit 0
