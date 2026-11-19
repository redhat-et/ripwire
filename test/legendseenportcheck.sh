#!/usr/bin/env bash
# legendseenportcheck.sh — the Codex and opencode ports of the legend-seen hook, their installers, and the --doctor rows.
#
# The shared shell hook (hooks/ripwire-legend-seen.sh, gated by legendseenhookcheck.sh) owns every rule; the ports only
# translate a client's payload into it. So the arms here hold the translation and the posture, the same way:
#   (A) Codex: hooks/ripwire-codex-legend-seen.sh records what a Codex PostToolUse received (tool_response as a string
#       or as {output}), names the FILE on the next PreToolUse, never returns a permissionDecision, forgets on
#       SessionStart compact, keeps its state apart from Claude Code's, and honours RIPWIRE_LEGEND_SEEN=0
#   (B) the installers: plain --hook / --codex --hook install NO rewriting hook; --hook-legend-seen (Claude),
#       --codex --hook-legend-seen and --opencode --hook-legend-seen do, once each however often they run
#   (C) opencode: the plugin, loaded through the loader the installer writes, rewrites output.args.command of a bash
#       call once the session holds definitions, leaves other tools alone, records nothing from a truncated output,
#       and forgets on session.compacted
#   (D) --doctor --agent=claude|codex: the legend-seen row is ok and installed="0" when absent, installed="1" and ok
#       when installed, and ok="0" once its script is gone
#   (H) every rewritten call: rc 0, a smaller answer, rows byte-identical to the untouched call
# Usage: test/legendseenportcheck.sh [PATH_TO_RIPWIRE]. Never touches the real ~/.claude, ~/.codex, ~/.config or ~/.ripwire.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_LEGEND_SEEN RIPWIRE_LEGEND_STATE RIPWIRE_HOME BASH_MAX_OUTPUT_LENGTH CLAUDE_CONFIG_DIR CODEX_HOME XDG_CONFIG_HOME
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "legendseenportcheck: no ripwire binary at $BIN"; exit 2; }
JQ="$( command -v jq )" || { echo "legendseenportcheck: jq is required"; exit 2; }
NODE="$( command -v node || true )"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"; mkdir -p "$H"
PBIN="$TMP/pbin"; mkdir -p "$PBIN"; ln -s "$BIN" "$PBIN/ripwire"; ln -s "$JQ" "$PBIN/jq"; [ -n "$NODE" ] && ln -s "$NODE" "$PBIN/node"
HPATH="$PBIN:/usr/bin:/bin"
REPO="$TMP/repo"; mkdir -p "$REPO"
cat >"$REPO/app.py" <<'SRC'
def helper(x):
    return x + 1

def caller_one():
    return helper(1)

def caller_two():
    return helper(2) + caller_one()
SRC
strip(){ python3 -c 'import re,sys; d=open(sys.argv[1]).read(); d=re.sub(r"<!--.*?-->","",d,flags=re.S); print(re.sub(r"est_tokens=\"\d+\"","",d))' "$1"; }
( cd "$REPO" && env PATH="$HPATH" ripwire . --callers=helper ) >"$TMP/plain" 2>/dev/null
PLAINB=$( wc -c <"$TMP/plain" | tr -d ' ' )
[ "$PLAINB" -gt 0 ] || no "fixture: the plain --callers answer is empty"

# ═══ (A) Codex ═══════════════════════════════════════════════════════════════════════════════════════════════════
CX="$ROOT/hooks/ripwire-codex-legend-seen.sh"
[ -x "$CX" ] || no "(A) $CX missing or not executable"
cx(){ env HOME="$H" PATH="$HPATH" "$@" bash "$CX"; }
cxpre(){ jq -cn --arg c "$1" --arg cwd "$REPO" '{session_id:"cx1",hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Bash",tool_input:{command:$c}}'; }
cxpost(){ jq -cn --arg c "$1" --rawfile o "$2" --arg shape "$3" --arg cwd "$REPO" \
    '{session_id:"cx1",hook_event_name:"PostToolUse",cwd:$cwd,tool_name:"Bash",tool_input:{command:$c},
      tool_response:(if $shape=="string" then $o else {output:$o} end)}'; }
C1="ripwire . --callers=helper"
out="$( cxpre "$C1" | cx )"
if [ -z "$out" ]; then ok "(A) Codex first call: untouched"; else no "(A) Codex first call touched: $out"; fi
cxpost "$C1" "$TMP/plain" object | cx >/dev/null
SEEN="$H/.ripwire/legend-seen-codex/cx1/main/seen"
if [ -s "$SEEN" ] && [ ! -e "$H/.ripwire/legend-seen/cx1" ]; then ok "(A) a PostToolUse with tool_response {output} is recorded, under Codex's own state dir"
else no "(A) Codex PostToolUse not recorded where expected ($( ls -R "$H/.ripwire" 2>/dev/null | head -5 | tr '\n' ' ' ))"; fi
out="$( cxpre "$C1" | cx )"
got="$( printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // empty' )"
if [ "$got" = "ripwire --legend-seen=$SEEN . --callers=helper" ] && printf '%s' "$out" | jq -e '.hookSpecificOutput | has("permissionDecision") | not' >/dev/null; then
    ok "(A) Codex second call: updatedInput names the FILE after the binary word, no permissionDecision"
else no "(A) Codex rewrite wrong: $out"; fi
( cd "$REPO" && env PATH="$HPATH" bash -c "$got" ) >"$TMP/cx.out" 2>/dev/null; rc=$?
if [ "$rc" -eq 0 ] && [ "$( wc -c <"$TMP/cx.out" | tr -d ' ' )" -lt "$PLAINB" ] && [ "$( strip "$TMP/cx.out" )" = "$( strip "$TMP/plain" )" ]; then
    ok "(H) Codex rewritten call: rc 0, $( wc -c <"$TMP/cx.out" | tr -d ' ' ) B against $PLAINB B, rows byte-identical"
else no "(H) Codex rewritten call rc=$rc"; fi
rm -rf "$H/.ripwire"; cxpost "$C1" "$TMP/plain" string | cx >/dev/null
if [ -s "$SEEN" ]; then ok "(A) a PostToolUse with tool_response as a string is recorded too"; else no "(A) string tool_response not recorded"; fi
jq -cn '{session_id:"cx1",hook_event_name:"SessionStart",source:"compact"}' | cx >/dev/null
if [ ! -e "$SEEN" ]; then ok "(A) Codex SessionStart compact forgets the FILE"; else no "(A) SessionStart compact left the FILE"; fi
rm -rf "$H/.ripwire"; cxpost "$C1" "$TMP/plain" object | cx RIPWIRE_LEGEND_SEEN=0 >/dev/null
if [ ! -e "$H/.ripwire" ]; then ok "(A) RIPWIRE_LEGEND_SEEN=0: no state"; else no "(A) opt-out wrote state"; fi

# ═══ (B) installers: opt-in only ═════════════════════════════════════════════════════════════════════════════════
count(){ jq '[.. | objects | select(has("command")) | .command | select(test("legend-seen"))] | length' "$1" 2>/dev/null || echo x; }
IH="$TMP/ih"; mkdir -p "$IH"
HOME="$IH" PATH="$HPATH" bash "$ROOT/skills/install.sh" --hook >/dev/null 2>&1
HOME="$IH" PATH="$HPATH" bash "$ROOT/skills/install.sh" --codex --hook >/dev/null 2>&1
if [ "$( count "$IH/.claude/settings.json" )" = 0 ] && [ "$( count "$IH/.codex/hooks.json" )" = 0 ]; then ok "(B) plain --hook and --codex --hook install no rewriting hook"
else no "(B) a plain --hook installed the legend-seen hook"; fi
for i in 1 2; do
    HOME="$IH" PATH="$HPATH" bash "$ROOT/skills/install.sh" --hook-legend-seen >"$TMP/i.c$i" 2>&1 || no "(B) --hook-legend-seen run $i failed"
    HOME="$IH" PATH="$HPATH" bash "$ROOT/skills/install.sh" --codex --hook-legend-seen >"$TMP/i.x$i" 2>&1 || no "(B) --codex --hook-legend-seen run $i failed"
    HOME="$IH" PATH="$HPATH" bash "$ROOT/skills/install.sh" --opencode --hook-legend-seen >"$TMP/i.o$i" 2>&1 || no "(B) --opencode --hook-legend-seen run $i failed"
done
if [ "$( count "$IH/.claude/settings.json" )" = 4 ] && [ "$( count "$IH/.codex/hooks.json" )" = 3 ] && [ -f "$IH/.config/opencode/plugin/ripwire-legend-seen.js" ]; then
    ok "(B) --hook-legend-seen: Claude 4 entries, Codex 3, the opencode loader — once each after two runs"
else no "(B) counts after two runs: claude=$( count "$IH/.claude/settings.json" ) codex=$( count "$IH/.codex/hooks.json" )"; fi
if grep -q "REWRITES a ripwire" "$TMP/i.c1" && grep -q "REWRITES a ripwire" "$TMP/i.x1" && grep -q "REWRITES a ripwire" "$TMP/i.o1"; then ok "(B) every installer says it rewrites a command before it does"
else no "(B) an installer did not disclose the rewrite"; fi
HOME="$IH" bash "$ROOT/skills/install.sh" --opencode >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok "(B) --opencode alone refuses (it installs only the plugin)"; else no "(B) --opencode alone rc=$rc"; fi

# ═══ (C) opencode, through the loader the installer wrote ════════════════════════════════════════════════════════
if [ -z "$NODE" ]; then
    no "(C) node is not on PATH: the opencode plugin cannot be exercised here"
else
    cat >"$TMP/oc.mjs" <<'JS'
import { pathToFileURL } from "node:url";
import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
const [ loader, repo, plain ] = process.argv.slice( 2 );
const { RipwireLegendSeen } = await import( pathToFileURL( loader ).href );
const p = await RipwireLegendSeen( { directory: repo } );
const out = {};
const cmd = "ripwire . --callers=helper";
const before = async ( tool, command ) => { const o = { args: { command } }; await p[ "tool.execute.before" ]( { tool, sessionID: "ses_oc1", callID: "c" }, o ); return o.args.command; };
const after = async ( command, output, truncated ) => p[ "tool.execute.after" ]( { tool: "bash", sessionID: "ses_oc1", callID: "c", args: { command } }, { title: "", output, metadata: { truncated } } );
out.first = await before( "bash", cmd );
await after( cmd, readFileSync( plain, "utf8" ), true );
out.afterTruncated = await before( "bash", cmd );
await after( cmd, readFileSync( plain, "utf8" ), false );
out.second = await before( "bash", cmd );
out.otherTool = await before( "read", cmd );
out.ran = execSync( out.second, { cwd: repo, encoding: "utf8" } );
await p.event( { event: { type: "session.compacted", properties: { sessionID: "ses_oc1" } } } );
out.afterCompact = await before( "bash", cmd );
console.log( JSON.stringify( out ) );
JS
    OC="$( cd "$REPO" && env HOME="$IH" PATH="$HPATH" node "$TMP/oc.mjs" "$IH/.config/opencode/plugin/ripwire-legend-seen.js" "$REPO" "$TMP/plain" 2>"$TMP/oc.err" )"
    j(){ printf '%s' "$OC" | jq -r "$1" 2>/dev/null; }
    SEENO="$IH/.ripwire/legend-seen-opencode/ses_oc1/main/seen"
    if [ "$( j .first )" = "ripwire . --callers=helper" ] && [ "$( j .afterTruncated )" = "ripwire . --callers=helper" ]; then ok "(C) opencode: first call untouched, and a truncated output records nothing"
    else no "(C) opencode first/truncated: $( head -c 300 "$TMP/oc.err" ) $OC"; fi
    if [ "$( j .second )" = "ripwire --legend-seen=$SEENO . --callers=helper" ]; then ok "(C) opencode: the next bash call's args.command names the session FILE"
    else no "(C) opencode rewrite: [$( j .second )]"; fi
    if [ "$( j .otherTool )" = "ripwire . --callers=helper" ]; then ok "(C) opencode: another tool's args are left alone"; else no "(C) opencode touched a non-bash tool"; fi
    j .ran >"$TMP/oc.out"
    if [ "$( wc -c <"$TMP/oc.out" | tr -d ' ' )" -lt "$PLAINB" ] && [ "$( strip "$TMP/oc.out" )" = "$( strip "$TMP/plain" )" ]; then ok "(H) opencode rewritten call: a smaller answer, rows byte-identical"
    else no "(H) opencode rewritten call differs or did not shrink"; fi
    if [ "$( j .afterCompact )" = "ripwire . --callers=helper" ]; then ok "(C) opencode: session.compacted forgets the FILE"; else no "(C) compaction kept the FILE: [$( j .afterCompact )]"; fi
fi

# ═══ (D) --doctor rows ═══════════════════════════════════════════════════════════════════════════════════════════
row(){ ( cd "$REPO" && env HOME="$1" PATH="$HPATH" ripwire . --doctor --agent="$2" 2>/dev/null ) | grep -o "<c n=\"$2-legend-seen\"[^>]*>"; }
DH="$TMP/dh"; mkdir -p "$DH"
r="$( row "$DH" claude )"
if printf '%s' "$r" | grep -q 'ok="1"' && printf '%s' "$r" | grep -q 'installed="0"'; then ok "(D) claude-legend-seen absent: ok, installed=\"0\" (it is opt-in)"; else no "(D) claude row absent-case: [$r]"; fi
r="$( row "$IH" claude )"
if printf '%s' "$r" | grep -q 'ok="1"' && printf '%s' "$r" | grep -q 'installed="1"'; then ok "(D) claude-legend-seen installed: ok, installed=\"1\""; else no "(D) claude row installed-case: [$r]"; fi
r="$( row "$IH" codex )"
if printf '%s' "$r" | grep -q 'ok="1"' && printf '%s' "$r" | grep -q 'installed="1"'; then ok "(D) codex-legend-seen installed: ok, installed=\"1\""; else no "(D) codex row installed-case: [$r]"; fi
# a broken install: registered from a copy whose script is then removed
BR="$TMP/broken"; mkdir -p "$BR/home"; cp -R "$ROOT/skills" "$BR/skills"; cp -R "$ROOT/hooks" "$BR/hooks"
HOME="$BR/home" PATH="$HPATH" bash "$BR/skills/install.sh" --hook-legend-seen >/dev/null 2>&1
rm -f "$BR/hooks/ripwire-legend-seen.sh"
r="$( row "$BR/home" claude )"
if printf '%s' "$r" | grep -q 'ok="0"' && printf '%s' "$r" | grep -q 'hint='; then ok "(D) claude-legend-seen with its script gone: ok=\"0\" and a hint"; else no "(D) broken install not reported: [$r]"; fi

if [ "$fail" -eq 0 ]; then echo "legendseenportcheck: all arms PASS"; exit 0; fi
echo "legendseenportcheck: FAILURES"; exit 1
