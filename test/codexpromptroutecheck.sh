#!/usr/bin/env bash
# codexpromptroutecheck.sh — route before the first Read/Grep/Bash choice. A confident --help-task
# recommendation becomes advisory Codex context; abstain is silent. Telemetry stores only a prompt hash
# and length, never prompt text, and hook installation stays idempotent.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
HOOK="$ROOT/hooks/ripwire-codex-route.sh"
ADAPTER="$ROOT/hooks/ripwire-codex-nudge.sh"
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
# The preamble/route seam must be a REAL newline. A \n written inside shell double quotes stays two
# literal characters and Codex renders "...evidence.\n<task-route" — assert the break, refuse the literal.
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("evidence.\n<task-route") and (contains("\\n") | not)' >/dev/null 2>&1 \
    && ok "injected context separates preamble and route with a real newline" \
    || no "injected context carries a literal backslash-n instead of a newline"

QUIET="$( printf '%s\n' "{\"prompt\":\"please abstain\",\"cwd\":\"$TMP/repo\"}" | \
    PATH="$TMP/bin:$PATH" RIPWIRE_HOME="$TMP/meter" "$HOOK" )"
[ -z "$QUIET" ] && ok "abstention is silent" || no "abstention emitted context: $QUIET"

LOG="$TMP/meter/routing.jsonl"
[ -s "$LOG" ] && [ "$( jq -s '[.[] | select(.event == "UserPromptSubmit")] | length' "$LOG" )" = 2 ] \
    && ok "recommend + abstain decisions are both instrumented" \
    || no "routing telemetry does not contain two decisions"
if grep -q 'SECRET_PROMPT_TEXT' "$LOG"; then
    no "routing telemetry stored raw prompt text"
else
    ok "routing telemetry stores no raw prompt text"
fi
jq -e -s 'all(.[] | select(.event == "UserPromptSubmit");
    (.prompt_hash | length) > 0 and (.session_hash | length) > 0 and
    (.prompt_bytes | type) == "number" and (.status == "recommend" or .status == "abstain")) and
    any(.[]; .event == "UserPromptSubmit" and .status == "recommend" and .recommended == "--for")' "$LOG" >/dev/null 2>&1 \
    && ok "routing telemetry has privacy-safe decision and recommended-verb fields" \
    || no "routing telemetry schema is incomplete"
grep -R -q 'SECRET_PROMPT_TEXT' "$TMP/meter/routing-pending" 2>/dev/null \
    && no "pending routing state stored raw prompt text" \
    || ok "pending routing state stores no raw prompt text"

# The next two RIPWIRE calls, rather than arbitrary tool calls, close the recommendation. A different
# first verb stays pending; the recommended second verb records position=2 and clears the state.
for command in 'ripwire . --grep=SECRET_COMMAND_TEXT' 'ripwire . --for=alpha'; do
    payload="$( jq -cn --arg cwd "$TMP/repo" --arg command "$command" \
        '{session_id:"route-test",cwd:$cwd,tool_name:"Bash",tool_input:{command:$command}}' )"
    printf '%s' "$payload" | PATH="$TMP/bin:$PATH" RIPWIRE_HOME="$TMP/meter" "$ADAPTER" >/dev/null
done
jq -e -s 'any(.[]; .event == "RouteObservation" and .outcome == "continued" and .position == 1 and .observed == "--grep") and
          any(.[]; .event == "RouteObservation" and .outcome == "adopted" and .position == 2 and
                   .recommended == "--for" and .observed == "--for")' "$LOG" >/dev/null 2>&1 \
    && ok "routing feedback records recommendation adoption within two Ripwire calls" \
    || no "routing feedback did not close the position-2 adoption loop"
grep -q 'SECRET_COMMAND_TEXT' "$LOG" \
    && no "routing feedback stored a full shell command" \
    || ok "routing feedback stores verb names, never full shell commands"
[ -z "$( find "$TMP/meter/routing-pending" -type f -print -quit 2>/dev/null )" ] \
    && ok "completed route feedback leaves no pending session state" \
    || no "completed route feedback left stale pending state"

# A second recommendation ignored by two Ripwire calls closes as missed. The report keeps the small
# fixture honest: 1/2 adopted is shown, but n=2 is explicitly underpowered against the registered n=30.
printf '%s\n' "{\"prompt\":\"$PROMPT\",\"cwd\":\"$TMP/repo\",\"session_id\":\"route-miss\"}" | \
    PATH="$TMP/bin:$PATH" RIPWIRE_HOME="$TMP/meter" "$HOOK" >/dev/null
for command in 'ripwire . --grep=needle' 'ripwire . --impact=alpha'; do
    payload="$( jq -cn --arg cwd "$TMP/repo" --arg command "$command" \
        '{session_id:"route-miss",cwd:$cwd,tool_name:"Bash",tool_input:{command:$command}}' )"
    printf '%s' "$payload" | PATH="$TMP/bin:$PATH" RIPWIRE_HOME="$TMP/meter" "$ADAPTER" >/dev/null
done
REPORT="$( python3 "$ROOT/bench/routing_report.py" "$LOG" --json 2>/dev/null )"; RRC=$?
printf '%s' "$REPORT" | jq -e '.schema == "ripwire.routing-feedback/v1" and .decisions == 3 and
    .recommendations == 2 and .abstentions == 1 and .completed == 2 and .adopted == 1 and
    .missed == 1 and .adoption_rate == 0.5 and .underpowered == true and
    (.intents[] | select(.intent == "understand-symbol") | .completed == 2 and .adopted == 1)' >/dev/null 2>&1 \
    && [ "$RRC" = 0 ] && ok "routing report exposes honest aggregate and per-intent feedback" \
    || no "routing report is missing or misstates the adoption evidence: $REPORT"

# routing.jsonl is SHARED with hooks/ripwire-claude-route.sh, whose rows carry agent="claude" and an
# arm= field. The Codex report is a Codex-only readout: a Claude decision plus a Claude adopted
# observation appended to the same log must leave every Codex count untouched (3/2/1 above), while
# the original Codex rows — written before the agent field existed, so they carry none — still count.
cat >>"$LOG" <<'JSONL'
{"v":2,"at":"2026-09-03T00:00:00Z","agent":"claude","event":"UserPromptSubmit","status":"recommend","intent":"understand-symbol","recommended":"--for","arm":"treatment","session_hash":"claudesess","prompt_hash":"claudeprompt","prompt_bytes":40}
{"v":2,"at":"2026-09-03T00:00:01Z","agent":"claude","event":"RouteObservation","session_hash":"claudesess","prompt_hash":"claudeprompt","intent":"understand-symbol","recommended":"--for","arm":"treatment","observed":"--for","position":1,"outcome":"adopted"}
{"v":2,"at":"2026-09-03T00:00:02Z","agent":"claude","event":"UserPromptSubmit","status":"abstain","intent":"","recommended":"","arm":"control","session_hash":"claudesess2","prompt_hash":"claudeprompt2","prompt_bytes":12}
JSONL
REPORT="$( python3 "$ROOT/bench/routing_report.py" "$LOG" --json 2>/dev/null )"; RRC=$?
printf '%s' "$REPORT" | jq -e '.decisions == 3 and .recommendations == 2 and .abstentions == 1 and
    .completed == 2 and .adopted == 1 and .missed == 1 and .adoption_rate == 0.5 and .invalid_rows == 0 and
    (.intents[] | select(.intent == "understand-symbol") | .completed == 2 and .adopted == 1)' >/dev/null 2>&1 \
    && [ "$RRC" = 0 ] && ok "routing report excludes agent=\"claude\" rows from the Codex readout" \
    || no "routing report counted Claude-router rows into the Codex adoption numbers: $REPORT"

# observed= must name the verb the adoption verdict was decided on. A modifier flag ahead of the
# recommended verb (--no-cache before --for) must not become the observed verb on an adopted row.
printf '%s\n' "{\"prompt\":\"$PROMPT\",\"cwd\":\"$TMP/repo\",\"session_id\":\"route-mod\"}" | \
    PATH="$TMP/bin:$PATH" RIPWIRE_HOME="$TMP/meter" "$HOOK" >/dev/null
payload="$( jq -cn --arg cwd "$TMP/repo" --arg command 'ripwire . --no-cache --for=alpha' \
    '{session_id:"route-mod",cwd:$cwd,tool_name:"Bash",tool_input:{command:$command}}' )"
printf '%s' "$payload" | PATH="$TMP/bin:$PATH" RIPWIRE_HOME="$TMP/meter" "$ADAPTER" >/dev/null
jq -e -s 'any(.[]; .event == "RouteObservation" and .outcome == "adopted" and .position == 1 and .observed == "--for")' "$LOG" >/dev/null 2>&1 \
    && ok "adopted rows record the recommended verb as observed, not a leading modifier flag" \
    || no "adopted row recorded a modifier flag as the observed verb"

OFF="$( printf '%s\n' "{\"prompt\":\"$PROMPT\",\"cwd\":\"$TMP/repo\",\"session_id\":\"route-off\"}" | \
    PATH="$TMP/bin:$PATH" RIPWIRE_HOME="$TMP/off" RIPWIRE_ROUTE_METER=0 "$HOOK" )"
[ -n "$OFF" ] && [ ! -e "$TMP/off" ] \
    && ok "routing-meter opt-out keeps advice but writes no log or pending state" \
    || no "routing-meter opt-out suppressed advice or wrote state"

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
