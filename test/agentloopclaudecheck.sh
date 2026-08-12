#!/usr/bin/env bash
# agentloopclaudecheck.sh — the CONTROL-ARM ISOLATION contract for the default `claude -p` harness.
#
# THE HOLE THIS GATE GUARDS (E1 Phase-0 control-scrub F3). run_agentloop.py built an isolated
# environment for codex (`prepare_codex_environment`) and for opencode (`prepare_opencode_environment`,
# with test/agentloopopencodecheck.sh watching it) and, for `claude-code-p` — the DEFAULT --harness —
# passed `child_env = None`. That arm inherited the operator's `~/.claude` whole: CLAUDE.md, both
# ripwire hooks, all 18 installed skills, and the per-project auto-memory. On this project's own
# machine 81 of the 84 lines of the global CLAUDE.md are a ripwire use-when protocol, so the BASELINE
# arm was briefed by name, verb and reflex on the tool it exists to be a control for — and every such
# run still reported status=ok. Nothing else in the harness can detect that; a contaminated A/B is
# silent by construction, which is exactly why it needs a canary rather than a code review.
#
# Modelled line-for-line on test/agentloopopencodecheck.sh. Pure-python contract checks, no binary and
# no network, so it is meaningful on a developer machine and green in CI.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

command -v python3 >/dev/null 2>&1 || { echo "agentloopclaudecheck: python3 required"; exit 2; }
[ -f "$ROOT/bench/agentloop/run_agentloop.py" ] || { echo "agentloopclaudecheck: harness missing"; exit 2; }

python3 - "$ROOT" "$TMP" >"$TMP/out.txt" 2>&1 <<'PY'
import inspect, pathlib, sys

root, tmp = sys.argv[1], sys.argv[2]
sys.path.insert( 0, str( pathlib.Path( root ) / "bench" / "agentloop" ) )
import run_agentloop as R

def ok( m ):   print( "PASS " + m )
def no( m ):   print( "FAIL " + m )
def skip( m ): print( "SKIP " + m )

work = pathlib.Path( tmp ) / "work"

# ── 1. the runner no longer hands claude a bare inherited environment ───────────────────────────
src = inspect.getsource( R.run_one )
if "child_env = None" not in src:
    ok( "run_one no longer assigns child_env = None for any harness" )
else:
    no( "run_one still leaves child_env = None on some path — the claude arm inherits ~/.claude" )
dispatch = inspect.getsource( R.prepare_environment )
for harness in R.HARNESSES:
    if f'"{harness}"' in dispatch or harness == "claude-code-p":
        ok( "prepare_environment has a branch for %s" % harness )
    else:
        no( "prepare_environment has no branch for %s" % harness )
# Every harness must get a DIFFERENT home, or two arms of two harnesses collide in one directory.
homes = { h: str( R.prepare_environment( h, work, "i", "baseline", 1, "/bin/echo" )[ 1 ] )
          for h in R.HARNESSES }
if len( set( homes.values() ) ) == len( R.HARNESSES ):
    ok( "each harness gets its own ephemeral run home" )
else:
    no( "two harnesses share a run home: %r" % ( homes, ) )

# ── 2. the isolated CLAUDE_CONFIG_DIR ───────────────────────────────────────────────────────────
env, run_home, shim = R.prepare_claude_environment( work, "inst-1", "baseline", 1, "/bin/echo" )
cfg = env.get( "CLAUDE_CONFIG_DIR", "" )
if cfg and pathlib.Path( cfg ).resolve().is_relative_to( pathlib.Path( run_home ).resolve() ):
    ok( "CLAUDE_CONFIG_DIR is inside the ephemeral run home" )
else:
    no( "CLAUDE_CONFIG_DIR=%r escapes the ephemeral run home %r" % ( cfg, str( run_home ) ) )
if cfg != str( pathlib.Path.home() / ".claude" ):
    ok( "CLAUDE_CONFIG_DIR is not the operator's own ~/.claude" )
else:
    no( "CLAUDE_CONFIG_DIR still points at the operator's ~/.claude" )

# The four contaminants that live under that directory. Absence of the DIRECTORY is our promise;
# the flags below are Claude Code's. Belt as well as braces, same posture as the opencode canary.
for name, what in ( ( "CLAUDE.md", "the global ripwire use-when protocol" ),
                    ( "skills", "the 18 installed ripwire skills" ),
                    ( "projects", "the per-project auto-memory index" ),
                    ( "settings.json", "the SessionStart primer + PreToolUse nudge hooks" ) ):
    if not ( pathlib.Path( cfg ) / name ).exists():
        ok( "no %s under the run home (%s)" % ( name, what ) )
    else:
        no( "the run home contains %s — %s is reachable by the control arm" % ( name, what ) )

# ── 3. the meter must not write to the operator's live telemetry ────────────────────────────────
if env.get( "RIPWIRE_METER_FIXTURE" ) == "1":
    ok( "RIPWIRE_METER_FIXTURE=1 (a harness is driving this, not an operator)" )
else:
    no( "RIPWIRE_METER_FIXTURE is not set — benchmark runs would append to the live S4 telemetry" )
rhome = env.get( "RIPWIRE_HOME", "" )
if rhome and pathlib.Path( rhome ).resolve().is_relative_to( pathlib.Path( run_home ).resolve() ):
    ok( "RIPWIRE_HOME is a per-run scratch destination" )
else:
    no( "RIPWIRE_HOME=%r is not inside the run home; the arm flag also does not take effect without "
        "a NAMED destination (control-scrub F1)" % rhome )
if env.get( "RIPWIRE_METER_ARM" ) == "control":
    ok( "the baseline arm is labelled control to the meter" )
else:
    no( "baseline arm is labelled %r to the meter" % env.get( "RIPWIRE_METER_ARM" ) )

# ── 4. the command's scrub flags ────────────────────────────────────────────────────────────────
cmd = R.build_claude_command( "PROMPT", "claude-sonnet-4-5", "baseline" )
if cmd[ :2 ] == [ "claude", "-p" ]:
    ok( "build_claude_command invokes `claude -p`" )
else:
    no( "build_claude_command starts with %r" % ( cmd[ :2 ], ) )
for flag, why in ( ( "--strict-mcp-config", "drops the global repowise server and the repo-local .mcp.json" ),
                   ( "--disable-slash-commands", "removes the installed skills from the control arm" ),
                   ( "--setting-sources", "excludes the hook block and the env.PATH that re-adds ripwire" ) ):
    if flag in cmd:
        ok( "command carries %s (%s)" % ( flag, why ) )
    else:
        no( "command is missing %s — %s" % ( flag, why ) )
if "--setting-sources" in cmd and cmd[ cmd.index( "--setting-sources" ) + 1 ] == "":
    ok( "--setting-sources is the EMPTY value (user, project and local settings all excluded)" )
else:
    no( "--setting-sources does not carry an empty value" )
if cmd[ 2 ] == "PROMPT":
    ok( "the prompt is passed as an argument, not through a settings file" )
else:
    no( "prompt is not the -p argument" )
# the skills arm is the one arm that must KEEP its skills; disabling them there would erase the
# only difference between the second and third arms.
if "--disable-slash-commands" not in R.build_claude_command( "P", "", "ripwire_skills" ):
    ok( "the ripwire_skills arm keeps its skills (that IS the arm)" )
else:
    no( "ripwire_skills would run with skills disabled — the third arm measures nothing" )
if "--max-budget-usd" in R.build_claude_command( "P", "", "baseline", max_budget_usd=0.60 ):
    ok( "a per-tier budget cap is passed when the task source supplies one (protocol §8)" )
else:
    no( "the per-run cost ceiling is not plumbed through" )

# ── 5. arm separation: skills belong to exactly one arm ─────────────────────────────────────────
def skills_dir( arm ):
    _e, rh, _s = R.prepare_claude_environment( work, "inst-1", arm, 1, "/bin/echo" )
    return pathlib.Path( rh ) / "skills"
for arm in ( "baseline", "ripwire_cli" ):
    if not skills_dir( arm ).exists():
        ok( "%s arm gets no skills tree" % arm )
    else:
        no( "%s arm has a skills tree — that is the 2026-08-04 confound the arm split removed" % arm )
sk = skills_dir( "ripwire_skills" )
if sk.exists() and any( sk.iterdir() ):
    ok( "ripwire_skills arm gets the skills tree" )
else:
    no( "ripwire_skills arm has no skills tree" )

# ── 6. the shim: claude self-logs no shell commands, so this is the ONLY ripwire counter ────────
if pathlib.Path( shim ).parent.resolve().is_relative_to( pathlib.Path( run_home ).resolve() ):
    ok( "the ripwire shim lives in the run home" )
else:
    no( "the shim is outside the run home" )
if env[ "PATH" ].split( ":" )[ 0 ] == str( pathlib.Path( shim ).parent ):
    ok( "the shim directory is PREPENDED to PATH (settings.json's own PATH re-prepend is excluded "
        "by --setting-sources '' — the two together are what item 8 of the scrub requires)" )
else:
    no( "the shim directory is not first on PATH: %r" % env[ "PATH" ].split( ":" )[ :2 ] )

# ── 7. the transcript is retained — without it there is no ANSWER to grade ──────────────────────
retain = pathlib.Path( tmp ) / "events" / "x.json"
out = R._claude_metrics( '{"result":"hello","usage":{"input_tokens":5,"output_tokens":6}}', None, retain )
if out.get( "events_path" ) == str( retain ) and retain.exists():
    ok( "_claude_metrics retains the raw trailer and records events_path" )
else:
    no( "_claude_metrics did not retain the transcript: %r" % ( out, ) )
if out.get( "tokens_in" ) == 5 and out.get( "tokens_out" ) == 6:
    ok( "token accounting still parses from the retained trailer" )
else:
    no( "token accounting broke: %r" % ( out, ) )
if R._claude_metrics( "not json", None, pathlib.Path( tmp ) / "events" / "y.json" ).get( "events_path" ):
    ok( "an unparseable trailer is still retained (the file is the evidence of record)" )
else:
    no( "an unparseable trailer was discarded" )

# ── 8. the questions task source and its prompt ─────────────────────────────────────────────────
bank = pathlib.Path( root ) / "bench" / "agentloop" / "fixtures" / "grader" / "instances.tsv"
tasks = R.load_questions( str( bank ) )
if tasks and all( set( ( "instance_id", "repo", "base_commit", "question" ) ) <= set( t ) for t in tasks ):
    ok( "load_questions yields tasks that satisfy make_record's contract (%d rows)" % len( tasks ) )
else:
    no( "load_questions produced unusable tasks" )
if all( t[ "instance_id" ] != "F12" for t in tasks ):
    ok( "RETIRED rows never become tasks" )
else:
    no( "a RETIRED row became a runnable task" )

task = tasks[ 0 ]
p_base = R.build_question_prompt( task, 1, "baseline", "/shim/ripwire" )
p_cli  = R.build_question_prompt( task, 1, "ripwire_cli", "/shim/ripwire", "BLURB" )
if p_base.startswith( task[ "question" ].strip() ) :
    ok( "the question text is emitted VERBATIM and first (protocol §5: never re-worded)" )
else:
    no( "the question was rewritten or prefixed" )
for needle, why in ( ( "scored as a hallucination", "groundedness is stated (protocol §10.10)" ),
                     ( "READ-ONLY", "no admitted bank row is an edit instance" ),
                     ( "tool calls", "the tier budget is stated, not discovered as a timeout" ),
                     ( R.grade_answers.ANSWER_OPEN, "the grader's terminal-answer fence" ) ):
    if needle in p_base:
        ok( "scope fence carries %s" % why )
    else:
        no( "scope fence is missing %s" % why )
if "minimal fix" not in p_base and "ISSUE:" not in p_base:
    ok( "no SWE-bench 'make the minimal fix' framing leaks into a question prompt" )
else:
    no( "the question prompt still carries patch-task framing" )
if "ripwire" not in p_base.replace( "Do not use ripwire or ctxpack", "" ):
    ok( "baseline question prompt names ripwire only to forbid it" )
else:
    no( "baseline question prompt leaks ripwire guidance" )
if "/shim/ripwire" in p_cli and "BLURB" in p_cli:
    ok( "the ripwire arm's question prompt names the shim and carries the wrap blurb" )
else:
    no( "the ripwire arm's question prompt is missing the shim path or the blurb" )
if R.build_question_prompt( task, 1, "ripwire_cli", "/s/r", "B" ) == \
   R.build_question_prompt( task, 1, "ripwire_skills", "/s/r", "B" ):
    ok( "both ripwire arms share an identical question prompt (they differ only on disk)" )
else:
    no( "the two ripwire arms' question prompts differ — that confounds the skills comparison" )
# the arm contract is defined once and reused by both prompt shapes
if R.arm_suffix( "baseline", "/s/r" ) in R.build_prompt( { "problem_statement": "i" }, 1, "baseline", "/s/r" ):
    ok( "the SWE-bench prompt and the question prompt share one arm contract" )
else:
    no( "the two prompt shapes carry different arm contracts and will drift" )
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
