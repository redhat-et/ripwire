#!/usr/bin/env bash
# codexpromptroutecheck.sh — route before the first Read/Grep/Bash choice. A confident --help-task
# recommendation becomes advisory Codex context; abstain is silent. Telemetry stores only a prompt hash
# and length, never prompt text, and hook installation stays idempotent.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
HOOK="$ROOT/hooks/ripwire-codex-route.sh"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 2; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
"$BIN" --help 2>&1 | grep -q -- '--help-task=' \
    || { echo "codexpromptroutecheck: supplied binary does not expose --help-task"; exit 1; }

mkdir -p "$TMP/bin" "$TMP/repo/.git" "$TMP/home"
cat >"$TMP/bin/ripwire" <<'SH'
#!/bin/sh
case "$*" in
  *abstain*) printf '%s\n' '<task-route status="abstain" confidence="none" score="0" margin="0"><facts git="1" dirty="0" trace="0" resolved_symbols="0"/></task-route>' ;;
  *) printf '%s\n' '<task-route status="recommend" confidence="high" score="9" margin="4"><facts git="1" dirty="0" trace="0" resolved_symbols="1"/><choice intent="understand-symbol" skill="ripwire-navigate" reason="one exact symbol" score="9"><run>ripwire . --for=&quot;parseArgs&quot;</run></choice></task-route>' ;;
esac
SH
chmod +x "$TMP/bin/ripwire"

PROMPT='understand parseArgs without broad reads SECRET_PROMPT_TEXT'
OUT="$( printf '%s\n' "{\"prompt\":\"$PROMPT\",\"cwd\":\"$TMP/repo\",\"session_id\":\"route-test\"}" | \
    PATH="$TMP/bin:$PATH" RIPWIRE_HOME="$TMP/meter" "$HOOK" )"
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("task-route status=\"recommend")' >/dev/null 2>&1 \
    && ok "recommendation becomes advisory additionalContext" \
    || no "recommendation was not emitted as Codex additionalContext: $OUT"
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == null' >/dev/null 2>&1 \
    && ok "prompt router never grants/denies permission" \
    || no "prompt router emitted a permission decision"

QUIET="$( printf '%s\n' "{\"prompt\":\"please abstain\",\"cwd\":\"$TMP/repo\"}" | \
    PATH="$TMP/bin:$PATH" RIPWIRE_HOME="$TMP/meter" "$HOOK" )"
[ -z "$QUIET" ] && ok "abstention is silent" || no "abstention emitted context: $QUIET"

LOG="$TMP/meter/routing.jsonl"
[ -s "$LOG" ] && [ "$( wc -l <"$LOG" | tr -d ' ' )" = 2 ] \
    && ok "recommend + abstain decisions are both instrumented" \
    || no "routing telemetry does not contain two decisions"
if grep -q 'SECRET_PROMPT_TEXT' "$LOG"; then
    no "routing telemetry stored raw prompt text"
else
    ok "routing telemetry stores no raw prompt text"
fi
jq -e -s 'all(.[]; (.prompt_hash | length) > 0 and (.prompt_bytes | type) == "number" and (.status == "recommend" or .status == "abstain"))' "$LOG" >/dev/null 2>&1 \
    && ok "routing telemetry has hash/length/status fields" \
    || no "routing telemetry schema is incomplete"

HOME="$TMP/home" CODEX_HOME="$TMP/home/.codex" AGENTS_HOME="$TMP/home/.agents" \
    bash "$ROOT/skills/install.sh" --codex --hook >/dev/null
HOME="$TMP/home" CODEX_HOME="$TMP/home/.codex" AGENTS_HOME="$TMP/home/.agents" \
    bash "$ROOT/skills/install.sh" --codex --hook >/dev/null
SETTINGS="$TMP/home/.codex/hooks.json"
jq -e --arg cmd "$HOOK" '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command == $cmd)] | length == 1' "$SETTINGS" >/dev/null 2>&1 \
    && ok "Codex installer registers exactly one prompt router after two runs" \
    || no "Codex installer did not idempotently register UserPromptSubmit"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
