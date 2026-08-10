#!/usr/bin/env bash
# agentloopopencodecheck.sh — the opencode harness contract in bench/agentloop/run_agentloop.py.
#
# The assertion this gate exists for is §5: ARM ISOLATION. opencode reads $HOME/.claude/CLAUDE.md
# into every run unless OPENCODE_DISABLE_CLAUDE_CODE is set, and this project's own developers keep a
# ripwire usage protocol in exactly that file. An unguarded baseline arm is therefore briefed on the
# tool it is supposed to be a control for, and the whole experiment measures nothing — silently, with
# every run still reporting status=ok. Nothing else in the harness can detect that.
#
# opencode is an OPTIONAL dependency: the pure-python contract checks always run, and the live
# `opencode debug paths` confirmation is skipped (not failed) where the binary is absent, so this
# gate is meaningful on a developer machine and green in CI.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "agentloopopencodecheck: no binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "agentloopopencodecheck: python3 required"; exit 2; }
[ -f "$ROOT/bench/agentloop/run_agentloop.py" ] || { echo "agentloopopencodecheck: harness missing"; exit 2; }

python3 - "$ROOT" "$BIN" "$TMP" >"$TMP/out.txt" 2>&1 <<'PY'
import json, os, pathlib, subprocess, sys

root, ripwire_bin, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
sys.path.insert( 0, str( pathlib.Path( root ) / "bench" / "agentloop" ) )
import run_agentloop as R

def ok( m ):   print( "PASS " + m )
def no( m ):   print( "FAIL " + m )
def skip( m ): print( "SKIP " + m )

# ── 1. the harness is registered everywhere it must be ──────────────────────────────────────────
if "opencode" in R.HARNESSES:
    ok( "opencode is in HARNESSES" )
else:
    no( "opencode missing from HARNESSES" )

if R.ARMS == ( "baseline", "ripwire_cli", "ripwire_skills" ):
    ok( "three arms declared (skills split out of ripwire_cli)" )
else:
    no( "unexpected ARMS %r" % ( R.ARMS, ) )

# ── 2. the command carries the unattended + model flags ─────────────────────────────────────────
cmd = R.build_opencode_command( "PROMPT", "anthropic/claude-sonnet-4-5" )
if cmd[ :2 ] == [ "opencode", "run" ]:
    ok( "build_opencode_command invokes `opencode run`" )
else:
    no( "build_opencode_command starts with %r" % ( cmd[ :2 ], ) )
for flag in ( "--format", "--auto", "--model" ):
    if flag in cmd:
        ok( "command carries %s" % flag )
    else:
        no( "command is missing %s" % flag )
if cmd[ cmd.index( "--format" ) + 1 ] == "json":
    ok( "output format is json (NDJSON events are the only token source)" )
else:
    no( "--format is not json" )
if cmd[ -1 ] == "PROMPT":
    ok( "prompt is the trailing positional" )
else:
    no( "prompt is not the last argument" )

# ── 3. NDJSON parsing: tokens, cost, model, and every bash command ──────────────────────────────
events = [
    { "type": "step_start",  "part": { "modelID": "claude-sonnet-4-5" } },
    { "type": "tool_use",    "part": { "tool": "bash",
                                       "state": { "status": "completed",
                                                  "input": { "command": "/shim/ripwire . --for=x" } } } },
    { "type": "tool_use",    "part": { "tool": "bash",
                                       "state": { "status": "completed",
                                                  "input": { "command": "grep -r foo ." } } } },
    { "type": "tool_use",    "part": { "tool": "read", "state": { "status": "completed", "input": {} } } },
    { "type": "step_finish", "part": { "modelID": "claude-sonnet-4-5", "cost": 0.42,
                                       "tokens": { "input": 1234, "output": 56, "reasoning": 0,
                                                   "cache": { "read": 7, "write": 8 } } } },
]
stream = "\n".join( json.dumps( e ) for e in events ) + "\n"
ti, to, cost, model, ncmd, nrip, rips = R.parse_opencode_ndjson_metrics( stream, "/shim/ripwire" )
checks = [ ( ti == 1234, "tokens_in from step_finish (%r)" % ti ),
           ( to == 56,   "tokens_out from step_finish (%r)" % to ),
           ( cost == 0.42, "cost from step_finish (%r)" % cost ),
           ( model == "claude-sonnet-4-5", "resolved model read back (%r)" % model ),
           ( ncmd == 2,  "counts only bash tool_use events, not every tool (%r)" % ncmd ),
           ( nrip == 1,  "counts the ripwire invocation (%r)" % nrip ) ]
for good, msg in checks:
    ( ok if good else no )( msg )

if R.parse_opencode_ndjson_metrics( "not json\n{\"type\":\"junk\"}\n", "x" )[ 0 ] is None:
    ok( "schema drift / garbage degrades to nulls instead of raising" )
else:
    no( "garbage input did not degrade cleanly" )

# ── 4. the shim: counts invocations AND stays transparent ───────────────────────────────────────
home = pathlib.Path( tmp ) / "shimtest"
home.mkdir( parents=True, exist_ok=True )
shim, log = R.install_ripwire_shim( home, "/bin/echo" )
subprocess.run( [ shim, "hello", "world" ], capture_output=True, text=True )
out = subprocess.run( [ shim, "second" ], capture_output=True, text=True )
calls, commands = R.read_shim_log( log )
if calls == 2:
    ok( "shim logged both invocations (%d)" % calls )
else:
    no( "shim logged %d invocations, expected 2" % calls )
if out.stdout.strip() == "second":
    ok( "shim execs the real binary unchanged (output passes through)" )
else:
    no( "shim altered the wrapped binary's output: %r" % out.stdout )
if commands and "hello world" in commands[ 0 ]:
    ok( "shim records the argv it was called with" )
else:
    no( "shim did not record argv: %r" % ( commands, ) )
if R.read_shim_log( home / "nope.log" ) == ( 0, [] ):
    ok( "absent shim log reads as zero calls, not a crash" )
else:
    no( "absent shim log did not degrade" )

# ── 5. ISOLATION — the reason this gate exists ──────────────────────────────────────────────────
work = pathlib.Path( tmp ) / "work"
env, run_home, shim_bin = R.prepare_opencode_environment( work, "inst-1", "baseline", 1, ripwire_bin )

for var in ( "HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME" ):
    val = env.get( var, "" )
    if val and pathlib.Path( val ).resolve().is_relative_to( pathlib.Path( run_home ).resolve() ):
        ok( "%s is inside the ephemeral run home" % var )
    else:
        no( "%s=%r escapes the ephemeral run home %r" % ( var, val, str( run_home ) ) )

if env.get( "OPENCODE_DISABLE_CLAUDE_CODE" ) == "1":
    ok( "OPENCODE_DISABLE_CLAUDE_CODE=1 (blocks $HOME/.claude/CLAUDE.md)" )
else:
    no( "OPENCODE_DISABLE_CLAUDE_CODE is not set — the baseline arm would read the developer's "
        "own CLAUDE.md, which on this project describes ripwire" )
if env.get( "OPENCODE_DISABLE_PROJECT_CONFIG" ) == "1":
    ok( "OPENCODE_DISABLE_PROJECT_CONFIG=1" )
else:
    no( "OPENCODE_DISABLE_PROJECT_CONFIG is not set" )

# the redirected HOME must not contain a .claude at all — belt as well as braces, because the env
# var is opencode's promise and the empty directory is ours.
if not ( pathlib.Path( env["HOME"] ) / ".claude" ).exists():
    ok( "the ephemeral HOME has no .claude directory" )
else:
    no( "the ephemeral HOME contains .claude — contamination is reachable" )

# OPENCODE_CONFIG is NOT a replacement for global config (it merges on top), so it must not be the
# isolation mechanism. Assert we are not relying on it.
if "OPENCODE_CONFIG" not in env:
    ok( "isolation does not rely on OPENCODE_CONFIG (which merges, not replaces)" )
else:
    no( "OPENCODE_CONFIG is set — that merges on top of global config and does not isolate" )

# ── 6. arm separation: skills belong to exactly one arm ─────────────────────────────────────────
def skills_dir( arm ):
    _e, rh, _s = R.prepare_opencode_environment( work, "inst-1", arm, 1, ripwire_bin )
    return pathlib.Path( rh ) / "config" / "opencode" / "skills"

if not skills_dir( "baseline" ).exists():
    ok( "baseline arm gets no skills tree" )
else:
    no( "baseline arm has a skills tree" )
if not skills_dir( "ripwire_cli" ).exists():
    ok( "ripwire_cli arm gets NO skills tree (the 2026-08-04 confound is fixed)" )
else:
    no( "ripwire_cli still injects skills — that is the confound this arm split exists to remove" )
sk = skills_dir( "ripwire_skills" )
if sk.exists() and any( sk.iterdir() ):
    ok( "ripwire_skills arm gets the skills tree" )
else:
    no( "ripwire_skills arm has no skills tree" )

# ── 7. prompt contract: the blurb comes from the shipped wrap recipe, not a benchmark restatement ─
wrapped = subprocess.run( [ ripwire_bin, "wrap", "opencode", "--force" ], capture_output=True, text=True )
blurb = R.extract_wrap_blurb( wrapped.stdout )
if blurb and "ripwire" in blurb and "--- paste into" not in blurb:
    ok( "extract_wrap_blurb pulls the fenced body out of `wrap opencode`" )
else:
    no( "extract_wrap_blurb returned %r" % ( blurb[ :80 ], ) )

gold = { "problem_statement": "an issue" }
p_base  = R.build_prompt( gold, 1, "baseline",       "/shim/ripwire", blurb )
p_cli   = R.build_prompt( gold, 1, "ripwire_cli",    "/shim/ripwire", blurb )
p_skill = R.build_prompt( gold, 1, "ripwire_skills", "/shim/ripwire", blurb )
if "ripwire" not in p_base.replace( "Do not use ripwire or ctxpack", "" ):
    ok( "baseline prompt names ripwire only to forbid it" )
else:
    no( "baseline prompt leaks ripwire guidance" )
if "/shim/ripwire" in p_cli:
    ok( "ripwire arm's prompt names the SHIM path (so absolute-path calls are still counted)" )
else:
    no( "ripwire arm's prompt does not name the shim" )
if p_cli == p_skill:
    ok( "both ripwire arms share an identical prompt (they differ only on disk)" )
else:
    no( "ripwire_cli and ripwire_skills prompts differ — that confounds the skills comparison" )

# ── 8. metrics dispatch is explicit, never a two-way fallthrough ────────────────────────────────
m = R._harness_metrics( "opencode", stream, str( work ), { "instance_id": "i" }, "baseline", 1, "/shim/ripwire", None )
if m.get( "tokens_in" ) == 1234 and m.get( "resolved_model" ) == "claude-sonnet-4-5":
    ok( "_harness_metrics routes opencode to the NDJSON parser" )
else:
    no( "_harness_metrics misrouted opencode: %r" % ( m, ) )
if "resolved_model" in R.RECORD_FIELDS and "harness_version" in R.RECORD_FIELDS:
    ok( "record schema carries resolved_model + harness_version" )
else:
    no( "record schema is missing the v3 honesty fields" )

# ── 9. live confirmation, when opencode is actually installed ───────────────────────────────────
try:
    ver = subprocess.run( [ "opencode", "--version" ], capture_output=True, text=True, timeout=60 )
    installed = ver.returncode == 0
except ( OSError, subprocess.SubprocessError ):
    installed = False

if not installed:
    skip( "opencode not installed — live `debug paths` isolation confirmation not run" )
else:
    ok( "opencode present (%s)" % ( ver.stdout or "" ).strip() )
    probe = subprocess.run( [ "opencode", "debug", "paths" ], capture_output=True, text=True,
                            env=env, cwd=str( run_home ), timeout=120 )
    text = ( probe.stdout or "" ) + ( probe.stderr or "" )
    if probe.returncode != 0 or not text.strip():
        skip( "`opencode debug paths` unavailable in this build — static env assertions stand" )
    else:
        root_s = str( pathlib.Path( run_home ).resolve() )
        real_home = str( pathlib.Path.home() )
        escaped = [ ln for ln in text.splitlines()
                    if real_home in ln and root_s not in ln ]
        if escaped:
            no( "opencode resolved paths OUTSIDE the ephemeral root: %s" % escaped[ :2 ] )
        else:
            ok( "every path opencode resolved stays inside the ephemeral root" )
PY

while IFS= read -r line; do
    case "$line" in
        PASS*) ok   "${line#PASS }" ;;
        SKIP*) skip "${line#SKIP }" ;;
        FAIL*) no   "${line#FAIL }" ;;
        *)     [ -n "$line" ] && printf '        %s\n' "$line" ;;
    esac
done < "$TMP/out.txt"

grep -q 'Traceback' "$TMP/out.txt" && no "python contract checks raised"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
