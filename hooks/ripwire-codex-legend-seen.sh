#!/usr/bin/env bash
# hooks/ripwire-codex-legend-seen.sh — the Codex adapter for hooks/ripwire-legend-seen.sh (lane LS1).
# The shared hook keeps the per-session FILE of legend-entry hashes and decides every rewrite; this wrapper only puts
# Codex's payload in front of it and Codex's output shape behind it, as ripwire-codex-nudge.sh does for the nudge.
#   PreToolUse   (Bash)  -> updatedInput with --legend-seen=FILE after the binary word, or nothing
#   PostToolUse  (Bash)  -> records the entry hashes of the stdout Codex received
#   SessionStart (startup|resume|clear|compact) -> forgets the FILE (Codex has no PreCompact; its compact source is it)
# Codex's own state dir keeps its sessions apart from Claude Code's: ${RIPWIRE_LEGEND_STATE:-${RIPWIRE_HOME:-~/.ripwire}/legend-seen-codex}.
# Never a permissionDecision: Codex runs the rewritten call through its own approval flow. Any surprise -> silence, exit 0.
set -u

dir="$( cd "$( dirname "$0" )" && pwd )"
[ "${RIPWIRE_LEGEND_SEEN:-1}" = 0 ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
input="$( cat )" || exit 0
export RIPWIRE_LEGEND_STATE="${RIPWIRE_LEGEND_STATE:-${RIPWIRE_HOME:-${HOME:+$HOME/.ripwire}}/legend-seen-codex}"
# Codex may hand the tool result as a string or as an object with an output field; the shared hook reads stdout.
input="$( printf '%s' "$input" | jq -c 'if (.tool_response | type) == "string" then .tool_response = { stdout: .tool_response }
                                        elif (.tool_response | type) == "object" and (.tool_response.stdout | not) and (.tool_response.output | type) == "string"
                                        then .tool_response.stdout = .tool_response.output else . end' 2>/dev/null )" || exit 0
out="$( printf '%s' "$input" | "$dir/ripwire-legend-seen.sh" )" || exit 0
[ -n "$out" ] || exit 0
# the shared hook never sets one; strip it anyway so no future change can widen Codex's permissions through here
printf '%s\n' "$out" | jq -c 'del(.hookSpecificOutput.permissionDecision)' 2>/dev/null || exit 0
