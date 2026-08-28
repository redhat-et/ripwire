#!/usr/bin/env bash
# Convert the shared advisory hook's Claude-compatible output into Codex's native hook shape.
# Classification, deduplication, routing suggestions, and metering stay in ripwire-nudge.sh.
set -u

dir="$( cd "$( dirname "$0" )" && pwd )"
input="$( cat )" || exit 0
out="$( printf '%s' "$input" | "$dir/ripwire-nudge.sh" "$@" )"
rc=$?
[ "$rc" -eq 0 ] || exit "$rc"
[ "${1:-}" = "--session-start" ] || printf '%s' "$input" | "$dir/ripwire-codex-route.sh" --observe >/dev/null 2>&1 || true
[ -n "$out" ] || exit 0

if command -v jq >/dev/null 2>&1; then
    # Codex accepts additionalContext directly, but `permissionDecision: allow` is valid only when
    # accompanied by updatedInput. The hook is advisory, so remove that Claude compatibility field.
    printf '%s\n' "$out" | jq 'if .hookSpecificOutput.permissionDecision == "allow" and
        (.hookSpecificOutput.updatedInput | not) then del(.hookSpecificOutput.permissionDecision) else . end'
else
    # Never block the triggering tool merely because the optional output adapter is unavailable.
    exit 0
fi
