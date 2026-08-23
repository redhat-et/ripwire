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
import hashlib, inspect, json, pathlib, subprocess, sys

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

# ── 6. the shim: the AUTHORITATIVE ripwire counter (the session transcript, section 7b, is the
# secondary witness — the shim also sees invocations a transcript parse could misclassify) ───────
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

# ── 7b. the SESSION transcript is retained and parsed — the trailer alone is not tool-call evidence ──
# The trailer `claude -p` prints is a 20-key summary object (cost, usage, result text, session_id) —
# it records NO tool calls. The CLI self-logs the real per-message stream into
# $CLAUDE_CONFIG_DIR/projects/<cwd-slug>/<session_id>.jsonl, which on a benchmark run lives inside the
# ephemeral run home and dies with /tmp. Found the hard way (2026-08-22 Lane AA transcript mining):
# an archived events/ directory that held only trailers, plus command_calls/native_read_calls frozen
# at null on every claude record. This section is the contract that the transcript is (a) copied into
# events/ next to the trailer and (b) parsed into the two formerly-null accounting fields.
sid = "11111111-2222-3333-4444-555555555555"
t_home = pathlib.Path( tmp ) / "t-run-home"
t_proj = t_home / "projects" / "-tmp-fake-repo"
t_proj.mkdir( parents=True, exist_ok=True )
_fixture_lines = [
    json.dumps( { "type": "user", "message": { "role": "user", "content": "fix it" } } ),
    json.dumps( { "type": "assistant", "message": { "content": [
        { "type": "tool_use", "name": "Bash", "input": { "command": 'ripwire . --for="query" --token-budget=4000' } } ] } } ),
    json.dumps( { "type": "assistant", "message": { "content": [
        { "type": "text", "text": "reading" },
        { "type": "tool_use", "name": "Read", "input": { "file_path": "a.py" } } ] } } ),
    json.dumps( { "type": "assistant", "message": { "content": [
        { "type": "tool_use", "name": "Bash", "input": { "command": "cat setup.py" } } ] } } ),
    json.dumps( { "type": "assistant", "message": { "content": [
        { "type": "tool_use", "name": "Grep", "input": { "pattern": "foo" } } ] } } ),
    json.dumps( { "type": "assistant", "message": { "content": [
        { "type": "tool_use", "name": "Edit", "input": { "file_path": "a.py" } } ] } } ),
    "this line is not json and must be skipped, never a crash",
]
( t_proj / ( sid + ".jsonl" ) ).write_text( "\n".join( _fixture_lines ) + "\n" )
t_retain = pathlib.Path( tmp ) / "events" / "t.json"
t_stdout = json.dumps( { "result": "done", "session_id": sid,
                         "usage": { "input_tokens": 1, "output_tokens": 2 } } )
t_out = R._claude_metrics( t_stdout, None, t_retain, run_home=t_home, ripwire_bin="ripwire" )
t_copy = t_retain.parent / "t.transcript.jsonl"
if t_copy.exists() and t_copy.read_text() == ( t_proj / ( sid + ".jsonl" ) ).read_text():
    ok( "the session transcript is copied byte-for-byte into events/ next to the trailer" )
else:
    no( "the session transcript was not retained at %s" % t_copy )
if t_out.get( "events_path" ) == str( t_retain ):
    ok( "events_path still names the trailer (grade_answers.py's answer source is unchanged)" )
else:
    no( "events_path moved off the trailer: %r" % ( t_out.get( "events_path" ), ) )
if t_out.get( "command_calls" ) == 2:
    ok( "command_calls counts the transcript's Bash tool_use blocks (2)" )
else:
    no( "command_calls=%r, expected 2 from the fixture transcript" % ( t_out.get( "command_calls" ), ) )
if t_out.get( "native_read_calls" ) == 3:
    ok( "native_read_calls counts Read + Grep tools plus the `cat` shell read (3), never the Edit" )
else:
    no( "native_read_calls=%r, expected 3 (Read, Grep, cat)" % ( t_out.get( "native_read_calls" ), ) )
if t_out.get( "ripwire_calls" ) == 1 and "ripwire ." in ( t_out.get( "ripwire_commands" ) or [ "" ] )[ 0 ]:
    ok( "transcript-parsed ripwire evidence fills in when no shim log exists (the shim still wins when it does)" )
else:
    no( "transcript ripwire accounting broke: calls=%r commands=%r"
        % ( t_out.get( "ripwire_calls" ), t_out.get( "ripwire_commands" ) ) )
# a session_id the run home does not contain must attach NOTHING — a guessed transcript is worse
# than a missing one (it would attribute another run's tool calls to this record)
t_out2 = R._claude_metrics( json.dumps( { "result": "x", "session_id": "not-there" } ), None,
                            pathlib.Path( tmp ) / "events" / "t2.json", run_home=t_home, ripwire_bin="ripwire" )
if t_out2.get( "command_calls" ) is None and not ( pathlib.Path( tmp ) / "events" / "t2.transcript.jsonl" ).exists():
    ok( "an unmatched session_id attaches no transcript and leaves the counts null (never a guess)" )
else:
    no( "an unmatched session_id still attached evidence: %r" % ( t_out2, ) )
# an unparseable trailer (the timeout path) falls back to the newest session file — for a timed-out
# run the transcript is the ONLY evidence, and the fallback is disclosed in the docstring
t_out3 = R._claude_metrics( "not json (timeout partial)", None,
                            pathlib.Path( tmp ) / "events" / "t3.json", run_home=t_home, ripwire_bin="ripwire" )
if t_out3.get( "command_calls" ) == 2 and ( pathlib.Path( tmp ) / "events" / "t3.transcript.jsonl" ).exists():
    ok( "an unparseable trailer still retains+parses the newest session transcript (timeout evidence)" )
else:
    no( "the timeout path lost the session transcript: %r" % ( t_out3, ) )

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

# ── 9. B1 — a stale/hand-assembled lock fails CLOSED on the split CONTRACT, not just the hash ───
# content_sha256 alone proves the file wasn't hand-edited; it does not prove the split rule still
# yields that set. pydata/xarray is a known-train repo under the CURRENT frozen_partition() rule
# (the exact contamination the committed tasks.lock as of 2026-08-20 carries); psf/requests is
# known-heldout. Both derived from R.select_tasks.frozen_partition(), never hand-copied, so this
# check cannot silently disagree with the rule it is testing.
def _lock_from( instances ):
    canon = [ dict( instance_id=i["instance_id"], repo=i["repo"], base_commit=i["base_commit"] )
              for i in sorted( instances, key=lambda x: x["instance_id"] ) ]
    blob = json.dumps( canon, sort_keys=True, separators=( ",", ":" ) ).encode( "utf-8" )
    return dict( schema="ripwire-agentloop-tasks-lock-v1",
                content_sha256=hashlib.sha256( blob ).hexdigest(), instances=instances )

assert R.select_tasks.frozen_partition( "pydata/xarray" ) == "train", "fixture assumption broke: re-check the salt"
assert R.select_tasks.frozen_partition( "psf/requests" ) == "heldout", "fixture assumption broke: re-check the salt"

bad_instances = [ dict( instance_id="pydata__xarray-1", repo="pydata/xarray", base_commit="deadbeef" ),
                  dict( instance_id="psf__requests-1", repo="psf/requests", base_commit="deadbeef" ) ]
bad_path = pathlib.Path( tmp ) / "bad.lock"
bad_path.write_text( json.dumps( _lock_from( bad_instances ) ) )
try:
    R.load_tasks_lock( str( bad_path ) )
    no( "load_tasks_lock accepted a lock containing pydata/xarray, which re-derives to LocBench TRAIN" )
except SystemExit as e:
    if "pydata/xarray" in str( e ) and "TRAIN" in str( e ):
        ok( "load_tasks_lock refuses (fail-closed) a lock whose repo re-derives to TRAIN, naming it" )
    else:
        no( "load_tasks_lock raised SystemExit but without naming the contaminated repo: %r" % ( str( e ), ) )

good_instances = [ i for i in bad_instances if i["repo"] != "pydata/xarray" ]
good_path = pathlib.Path( tmp ) / "good.lock"
good_path.write_text( json.dumps( _lock_from( good_instances ) ) )
try:
    R.load_tasks_lock( str( good_path ) )
    ok( "load_tasks_lock accepts a lock whose every repo re-derives to heldout" )
except SystemExit as e:
    no( "load_tasks_lock rejected an honest, all-heldout lock: %r" % ( str( e ), ) )

# ── 10. B2 — the scorer's dataset name is a parameter with a swebench>=5-compatible default ─────
if R.SWEBENCH_SCORE_DATASET_DEFAULT == "SWE-bench/SWE-bench_Lite":
    ok( "SWEBENCH_SCORE_DATASET_DEFAULT is the swebench>=5-compatible dataset name" )
else:
    no( "SWEBENCH_SCORE_DATASET_DEFAULT is %r, expected SWE-bench/SWE-bench_Lite"
        % R.SWEBENCH_SCORE_DATASET_DEFAULT )
sig = inspect.signature( R.run_swebench_harness )
if "dataset_name" in sig.parameters and sig.parameters["dataset_name"].default == "SWE-bench/SWE-bench_Lite":
    ok( "run_swebench_harness's dataset_name is a parameter, not a hardcoded princeton-nlp literal" )
else:
    no( "run_swebench_harness has no configurable dataset_name parameter: %r" % ( sig, ) )
if "swebench_dataset" in inspect.signature( R.evaluate_patch ).parameters:
    ok( "evaluate_patch threads a configurable swebench_dataset through to the scorer" )
else:
    no( "evaluate_patch does not expose a configurable dataset name" )

w_arm64 = R.swebench_arch_warning( machine="arm64" )
w_x86   = R.swebench_arch_warning( machine="x86_64" )
if w_arm64 and "--modal" in w_arm64:
    ok( "swebench_arch_warning names --modal as the alternative backend on a non-x86_64 host" )
else:
    no( "swebench_arch_warning did not fire or did not name --modal on arm64: %r" % ( w_arm64, ) )
if w_x86 is None:
    ok( "swebench_arch_warning is silent on an x86_64 host" )
else:
    no( "swebench_arch_warning fired on x86_64: %r" % ( w_x86, ) )

# ── 11. B3 — the ripwire arm's CLI invocation uses --token-budget, never --max-tokens ────────────
# --max-tokens is not read by --for (verified against the pinned binary — see the live flag-probe
# below, run outside this heredoc); every ripwire-arm run before this fix received an unbudgeted
# bundle. --token-budget is the flag --for actually reads and reports fit against.
suf = R.arm_suffix( "ripwire_cli", "/shim/ripwire" )
if "--token-budget=4000" in suf:
    ok( "ripwire arm's CLI invocation uses --token-budget=4000 (the flag --for actually reads)" )
else:
    no( "ripwire arm's CLI invocation is missing --token-budget=4000: %r" % ( suf, ) )
if "--max-tokens" in suf:
    no( "ripwire arm's CLI invocation still names --max-tokens, which --for silently ignores" )
else:
    ok( "ripwire arm's CLI invocation no longer names --max-tokens" )

# ── 13. arm-isolation fix (item 4) — the contamination gate closes the shim's detection loop ────
# The isolated environments (section 2 above) keep the baseline arm from being PRIMED to use
# ripwire; they deliberately still put the logging shim on baseline's PATH too, so a DISOBEYED
# instruction is evidence, not a silent success. This is the other half: converting that evidence
# into a status the pairing logic (analyze.py's pair_by_task_seed, status=="ok" required on BOTH
# arms) actually excludes.
clean = R.baseline_contamination_note( "baseline", dict( ripwire_calls=0, ripwire_commands=[] ) )
if clean is None:
    ok( "baseline_contamination_note is None for a clean baseline run" )
else:
    no( "baseline_contamination_note fired on a clean baseline run: %r" % ( clean, ) )
dirty = R.baseline_contamination_note(
    "baseline", dict( ripwire_calls=2, ripwire_commands=[ "ripwire . --for=x" ] ) )
if dirty and "2" in dirty:
    ok( "baseline_contamination_note fires with evidence when the baseline arm invoked ripwire" )
else:
    no( "baseline_contamination_note did not fire on a contaminated baseline run: %r" % ( dirty, ) )
treatment = R.baseline_contamination_note( "ripwire_cli", dict( ripwire_calls=5, ripwire_commands=[ "x" ] ) )
if treatment is None:
    ok( "baseline_contamination_note never fires for a RIPWIRE_ARMS run (that arm is working as intended)" )
else:
    no( "baseline_contamination_note incorrectly fired for the treatment arm: %r" % ( treatment, ) )
rec = R.make_record( dict( instance_id="i", repo="r", base_commit="c" ), "baseline", 1, "claude-code-p", "m",
                     status="contaminated", ripwire_calls=1, ripwire_commands=[ "x" ],
                     error="CONTAMINATED: x" )
if rec["status"] == "contaminated" and rec["error"]:
    ok( "make_record accepts status=\"contaminated\" (record schema was extended, not narrowed)" )
else:
    no( "make_record mishandled a contaminated record: %r" % ( rec, ) )

# ── 14/15 — an end-to-end run_one() drive with the harness faked out, real git underneath ───────
# Both sections below drive the ACTUAL run_one(), not a reimplementation of its logic: checkout_repo
# and prepare_environment are stubbed (no network, no real CLAUDE_CONFIG_DIR), but `sh()` for every
# non-`claude` argv (git init/diff/etc.) still hits the real subprocess, so the diff run_one persists
# and scores is a real `git diff` of a real working tree — only the harness invocation itself is canned.
class _FakeProc:
    def __init__( self, returncode, stdout, stderr ):
        self.returncode, self.stdout, self.stderr = returncode, stdout, stderr

def _fake_sh_claude( result ):
    def fake_sh( args, cwd=None, timeout=1800, env=None ):
        if args and args[ 0 ] == "claude":
            return result
        return subprocess.run( args, capture_output=True, text=True, timeout=timeout, cwd=cwd, env=env )
    return fake_sh

_fake_repo = pathlib.Path( tmp ) / "fakerepo"
_fake_repo.mkdir( parents=True, exist_ok=True )
subprocess.run( [ "git", "init", "-q" ], cwd=_fake_repo )
subprocess.run( [ "git", "config", "user.email", "t@example.com" ], cwd=_fake_repo )
subprocess.run( [ "git", "config", "user.name", "t" ], cwd=_fake_repo )
( _fake_repo / "a.txt" ).write_text( "orig\n" )
subprocess.run( [ "git", "add", "a.txt" ], cwd=_fake_repo )
subprocess.run( [ "git", "commit", "-q", "-m", "init" ], cwd=_fake_repo )
( _fake_repo / "a.txt" ).write_text( "changed\n" )   # the agent's (faked) edit — this IS the candidate patch

_real_sh = R.sh
R.checkout_repo = lambda repo, base_commit, repos_dir: _fake_repo
R.prepare_environment = ( lambda harness, work_dir, instance_id, arm, seed, ripwire_bin:
                          ( {}, pathlib.Path( work_dir ) / "home", "shim" ) )
R.evaluate_patch = lambda *a, **k: ( None, None )
_fake_task = dict( instance_id="fake-1", repo="fake/repo", base_commit="deadbeef" )
_fake_gold_rows = { "fake-1": dict( problem_statement="fix the bug" ) }

# ── 14. error-capture keep-both-streams — stdout detail must survive an empty-stderr failure ────
# `claude -p --output-format json` puts the CLI's own error report on STDOUT (measured live
# 2026-08-20); a record that kept only stderr used to read `claude-code-p exit 1: ` and nothing else.
_MARKER = "RIPWIRE_SELFTEST_STDOUT_ONLY_DETAIL_9f2c"
_err_stdout = json.dumps( { "type": "result", "is_error": True, "result": _MARKER } )
R.sh = _fake_sh_claude( _FakeProc( 1, _err_stdout, "" ) )
work1 = pathlib.Path( tmp ) / "work1"
rec1 = R.run_one( _fake_task, "baseline", 1, "claude-code-p", "", work_dir=str( work1 ),
                  gold_rows=_fake_gold_rows )
if rec1[ "status" ] == "error":
    ok( "run_one reports status=error for a nonzero-exit claude-code-p child" )
else:
    no( "run_one did not report status=error for a nonzero-exit child: %r" % ( rec1, ) )
if _MARKER in ( rec1[ "error" ] or "" ):
    ok( "an empty-stderr failure record's error field still carries the stdout detail" )
else:
    no( "the stdout detail was dropped from an empty-stderr failure record: %r" % ( rec1[ "error" ], ) )
if "stderr empty" in ( rec1[ "error" ] or "" ):
    ok( "the record discloses that stderr was empty, rather than implying stdout was the CLI's stderr" )
else:
    no( "the record does not disclose the empty-stderr / stdout-fallback substitution: %r"
        % ( rec1[ "error" ], ) )
if not ( work1 / "patches" ).exists():
    ok( "an error run writes no patch file (unconditional persistence is for scored/scorable runs only)" )
else:
    no( "an error run unexpectedly created a patches/ directory" )

# stderr still wins when it actually carries something — this is not "always prefer stdout".
R.sh = _fake_sh_claude( _FakeProc( 1, _err_stdout, "a real stderr message" ) )
rec1b = R.run_one( _fake_task, "baseline", 1, "claude-code-p", "", work_dir=str( pathlib.Path( tmp ) / "work1b" ),
                   gold_rows=_fake_gold_rows )
if "a real stderr message" in ( rec1b[ "error" ] or "" ) and "stdout:" not in ( rec1b[ "error" ] or "" ):
    ok( "a nonempty stderr is still used as-is, without the stdout fallback" )
else:
    no( "a nonempty stderr was not used as-is: %r" % ( rec1b[ "error" ], ) )

# ── 15. unconditional candidate-patch persistence — the run's product survives regardless of scoring ──
# Before this fix, with --evaluator none (the default) the `git diff` was computed, scored (a no-op),
# and then discarded — deferred scoring of a completed run was impossible. Now every run that reaches
# the harness successfully writes work_dir/patches/{instance}-{arm}-{seed}.patch, byte-for-byte the
# same diff that gets scored.
_ok_stdout = json.dumps( { "result": "ok", "usage": { "input_tokens": 10, "output_tokens": 20 },
                          "total_cost_usd": 0.01 } )
R.sh = _fake_sh_claude( _FakeProc( 0, _ok_stdout, "" ) )
work2 = pathlib.Path( tmp ) / "work2"
rec2 = R.run_one( _fake_task, "baseline", 2, "claude-code-p", "", work_dir=str( work2 ),
                  gold_rows=_fake_gold_rows, evaluator="none" )
if rec2[ "status" ] == "ok":
    ok( "run_one reports status=ok for a zero-exit claude-code-p child" )
else:
    no( "run_one did not report status=ok: %r" % ( rec2, ) )
patch_path = work2 / "patches" / ( "%s-%s-%s.patch" % ( _fake_task[ "instance_id" ], "baseline", 2 ) )
if patch_path.exists():
    ok( "the candidate patch is persisted to work_dir/patches/{instance}-{arm}-{seed}.patch" )
else:
    no( "no patch file was written at %s" % patch_path )
_expected_diff = subprocess.run( [ "git", "diff" ], cwd=_fake_repo, capture_output=True, text=True ).stdout
if patch_path.exists() and patch_path.read_text() == _expected_diff:
    ok( "the persisted patch is byte-identical to the git diff run_one scored (evaluator=none)" )
else:
    no( "the persisted patch does not match the scored git diff" )

R.sh = _real_sh
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

# ── 12. B3 live flag-probe — the exact flags this file's prompts/wrap invocations use, shot at a
# REAL ripwire binary, not just asserted in strings. Optional: a missing binary SKIPs rather than
# FAILs, so this stays meaningful on a bench-only checkout with no C++ build and green once one
# exists (this repo's own build, or RIPWIRE_BIN naming a pinned worktree binary explicitly).
PROBE_BIN="${1:-${RIPWIRE_BIN:-}}"
if [ -z "$PROBE_BIN" ] && [ -x "$ROOT/build/ripwire" ]; then
    PROBE_BIN="$ROOT/build/ripwire"
fi
if [ -n "$PROBE_BIN" ] && [ -x "$PROBE_BIN" ]; then
    PROBE_DIR="$TMP/probecorpus"; mkdir -p "$PROBE_DIR"
    printf 'int f(){return 1;}\n' > "$PROBE_DIR/a.c"
    if "$PROBE_BIN" "$PROBE_DIR" --for="probe query" --token-budget=4000 >/dev/null 2>"$TMP/probe1.err"; then
        ok "pinned binary ($PROBE_BIN) accepts --for=... --token-budget=4000 (exit 0)"
    else
        no "pinned binary rejected --for=... --token-budget=4000: $( cat "$TMP/probe1.err" )"
    fi
    if "$PROBE_BIN" wrap claude --force >/dev/null 2>"$TMP/probe2.err"; then
        ok "pinned binary accepts wrap claude --force (exit 0)"
    else
        no "pinned binary rejected wrap claude --force: $( cat "$TMP/probe2.err" )"
    fi
else
    skip "no ripwire binary resolvable (build $ROOT/build/ripwire, or set RIPWIRE_BIN=<path>) — B3 live flag-probe not run"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
