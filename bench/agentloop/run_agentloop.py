#!/usr/bin/env python3
# run_agentloop.py — Phase B4 agent-in-the-loop eval runner.
#
# WHAT THIS IS. The Phase B4 / R4 eval-methodology design: the
# stack currently measures retrieval quality (LocBench) but never the thing that actually matters —
# does giving an agent ripwire change whether it SOLVES the task. This script is the run matrix +
# record schema + orchestration skeleton for that experiment. It does NOT execute any agent or spend
# any money by itself: the actual exec step is a clearly marked NOT-IMPLEMENTED stub (see
# `run_one()` below) until a harness (Claude Code `-p` / SWE-agent / mini-swe-agent) is wired in and a
# human has explicitly approved a paid run.
#
# DESIGN (from R4-eval-methodology.md "Minimal agent-in-the-loop eval design"):
#   Arms:   baseline    = agent with grep/read/glob only (no ripwire)
#           ripwire_cli = same agent required to begin retrieval with ripwire's CLI
#   Seeds:  K=3 per (task, arm) — single-seed SWE-bench numbers are an unreliable "lucky pass"
#           (https://arxiv.org/pdf/2605.12925); vary only the RNG/sampling seed, hold model+prompt fixed
#           (Terminal-Bench "vary only the harness" template, https://arxiv.org/html/2601.11868v1).
#   Tasks:  bench/agentloop/tasks.lock (see select_tasks.py) — repo-disjoint from LocBench train.
#   Cost:   ~$0.30-$1.50/instance (arXiv 2412.21139) => len(tasks) * 2 arms * 3 seeds * that range.
#           At the locked task count this script prints the exact projected range in --dry-run output;
#           DO NOT run --live without reading bench/agentloop/README.md's safety note first.
#
# RECORD SCHEMA (one JSON object per (task, arm, seed) run — see `EMPTY_RESULT_SCHEMA` / `make_record`):
#   instance_id, repo, base_commit, arm, seed, harness, model,
#   status         — "not_implemented" | "ok" | "error" | "timeout"
#   resolved       — bool|null   (SWE-bench held-out test suite passed after the agent's patch)
#   localization_hit — bool|null (agent touched >=1 gold file from the reference patch)
#   tokens_in / tokens_out — int|null
#   wall_seconds   — float|null
#   cost_usd       — float|null
#   error          — str|null
#   started_unix / finished_unix
#
# EXEC HARNESSES — Claude Code and Codex are wired; SWE-agent remains deliberately unimplemented:
#   (A) `claude -p` (Claude Code print/non-interactive mode) with a tool allowlist — IMPLEMENTED below.
#       Both arms expose the same ordinary shell/read/edit tools and no MCP server. The treatment prompt
#       requires ripwire's CLI; retained command evidence is currently Codex-only.
#         claude -p "<task prompt built from problem_statement + seed suffix>" \
#           --permission-mode acceptEdits --output-format json --strict-mcp-config \
#           --allowedTools "Bash,Read,Glob,Grep,Edit,Write"
#       No Docker sandbox here: each run gets a plain git checkout (see checkout_repo(), adapted from
#       bench/locbench/run_locbench.py's checkout()) — the SWE-bench conda/dep environment is NOT
#       installed, so `resolved` scoring needs --evaluator=swebench (Docker, official harness) to be
#       meaningful; --evaluator=none lets the harness plumbing run/be smoke-tested without it.
#   (B) SWE-agent (https://github.com/SWE-agent/SWE-agent) or mini-swe-agent
#       (https://github.com/SWE-agent/mini-swe-agent): purpose-built SWE-bench harnesses with their own
#       Docker orchestration and scoring already wired to `swebench`'s evaluator. NOT implemented — (A)
#       was chosen; do not half-wire both.
#   (C) `codex exec --json --ephemeral` — IMPLEMENTED. Both arms ignore user config/rules, point
#       AGENTS_HOME at an empty per-run directory, and replace the MCP table with `{}`. The treatment
#       requires the absolute ripwire CLI before grep/read; retained JSONL proves whether Codex invoked it.
#
# USAGE:
#   python3 bench/agentloop/run_agentloop.py --dry-run --tasks-lock bench/agentloop/tasks.lock \
#       --results-out /tmp/agentloop/dry.json
#   python3 bench/agentloop/run_agentloop.py --live-one --limit 1 --arms baseline --seeds 1 \
#       --work-dir /tmp/agentloop --evaluator none      # ONE real claude -p call — cheapest live proof
#   python3 bench/agentloop/run_agentloop.py --live --work-dir /tmp/agentloop --evaluator swebench ...
import argparse, hashlib, json, os, pathlib, re, shlex, subprocess, sys, tempfile, time

sys.path.insert( 0, str( pathlib.Path( __file__ ).resolve().parent ) )
import select_tasks   # reuse fetch_rows()'s HF datasets-server fetch + cache — see load_gold_rows()

SCHEMA = "ripwire-agentloop-results-v3"
# THREE arms, because two could not tell ripwire's effect apart from the cost of shipping skills with
# it. The 2026-08-04 Codex pilot measured +80% tokens for `ripwire_cli` and the loss was diagnosed as
# skill-policy — full SKILL.md body reads re-billed every turn — not retrieval. That happened because
# the old two-arm `ripwire_cli` ALSO symlinked the whole skills/ tree on the codex harness, so the arm
# did not mean what its name said. It does now: `ripwire_cli` is the shipped wrap recipe (a CLI
# contract plus the rules-file blurb) and nothing else; the skills tree is its own labelled arm, and
# the ripwire_skills − ripwire_cli difference IS the skills tax, measured instead of assumed.
ARMS   = ( "baseline", "ripwire_cli", "ripwire_skills" )
RIPWIRE_ARMS = ( "ripwire_cli", "ripwire_skills" )   # arms that expose ripwire at all
HARNESSES = ( "claude-code-p", "codex-exec", "opencode" )
DEFAULT_SEEDS = ( 1, 2, 3 )
COST_LOW_PER_INSTANCE, COST_HIGH_PER_INSTANCE = 0.30, 1.50   # arXiv 2412.21139, per R4
DEFAULT_TIMEOUT_SECONDS = 900

ALLOWED_TOOLS_BASELINE = "Bash,Read,Glob,Grep,Edit,Write"

# ripwire binary path: same env-var convention bench/locbench/run_locbench.py uses (CTX), so a single
# RIPWIRE env var configures both harnesses; --ripwire-bin overrides it per-invocation.
RIPWIRE_BIN_DEFAULT = os.environ.get( "RIPWIRE", "ripwire" )

RECORD_FIELDS = (
    "instance_id", "repo", "base_commit", "arm", "seed", "harness", "model",
    "status", "resolved", "localization_hit", "tokens_in", "tokens_out",
    "wall_seconds", "cost_usd", "command_calls", "ripwire_calls", "ripwire_commands", "events_path",
    "error", "started_unix", "finished_unix",
    # v3 additions, both of them honesty fields rather than measurements:
    #   resolved_model  — the model the harness ACTUALLY used, read back from its own transcript.
    #                     opencode does not fail closed when no credential is configured: it silently
    #                     routes to its own free hosted model and completes the turn. A run whose
    #                     resolved_model disagrees with --model is not the run you think you paid for,
    #                     and without this field the substitution is invisible in the results.
    #   harness_version — pinned agent version per run; opencode ships releases multiple times a day.
    "resolved_model", "harness_version",
)

def load_tasks_lock( path ):
    lock = json.loads( pathlib.Path( path ).read_text() )
    if lock.get( "schema" ) != "ripwire-agentloop-tasks-lock-v1":
        raise SystemExit( f"{path}: unexpected schema {lock.get('schema')!r}; refusing (fail-closed)" )
    canon = [ dict( instance_id=i["instance_id"], repo=i["repo"], base_commit=i["base_commit"] )
              for i in sorted( lock["instances"], key=lambda x: x["instance_id"] ) ]
    blob = json.dumps( canon, sort_keys=True, separators=( ",", ":" ) ).encode( "utf-8" )
    actual = hashlib.sha256( blob ).hexdigest()
    expected = lock.get( "content_sha256" )
    if actual != expected:
        raise SystemExit( f"{path}: content hash mismatch (expected {expected}, computed {actual}); "
                           f"the lock file was hand-edited or corrupted — refusing (fail-closed, no "
                           f"silent re-derivation of the task list)" )
    return lock

def make_record( task, arm, seed, harness, model, status="not_implemented", **overrides ):
    now = time.time()
    rec = dict(
        instance_id=task["instance_id"], repo=task["repo"], base_commit=task["base_commit"],
        arm=arm, seed=seed, harness=harness, model=model,
        status=status, resolved=None, localization_hit=None,
        tokens_in=None, tokens_out=None, wall_seconds=None, cost_usd=None,
        command_calls=None, ripwire_calls=None, ripwire_commands=None, events_path=None,
        error=None, started_unix=now, finished_unix=now,
        resolved_model=None, harness_version=None,
    )
    rec.update( overrides )
    assert set( rec ) == set( RECORD_FIELDS ), f"record schema drift: {sorted(set(rec) ^ set(RECORD_FIELDS))}"
    return rec

def run_matrix( tasks, arms, seeds ):
    return [ ( t, arm, seed ) for t in tasks for arm in arms for seed in seeds ]

def limit_tasks_repo_round_robin( tasks, limit ):
    """Take a deterministic, repository-diverse prefix for pilots instead of N adjacent lock rows."""
    if not limit or limit >= len( tasks ):
        return list( tasks )
    by_repo = {}
    for task in tasks:
        by_repo.setdefault( task["repo"], [] ).append( task )
    selected = []
    row_index = 0
    repos = sorted( by_repo )
    while len( selected ) < limit:
        added = False
        for repo in repos:
            rows = by_repo[repo]
            if row_index < len( rows ):
                selected.append( rows[row_index] )
                added = True
                if len( selected ) == limit:
                    break
        if not added:
            break
        row_index += 1
    return selected

# ── shell + repo checkout (adapted from bench/locbench/run_locbench.py) ──────────────────────────────
def sh( args, cwd=None, timeout=1800, env=None ):
    return subprocess.run( args, capture_output=True, text=True, timeout=timeout, cwd=cwd, env=env )

def checkout_repo( repo, base_commit, repos_dir ):
    """Adapted from bench/locbench/run_locbench.py's checkout(): the same one-clone-per-repo shallow-
    fetch cache (24 instances across 6 repos need at most 6 clones total, reused across every arm/seed
    of that repo), BUT — unlike LocBench's read-only usage — the agent being tested WRITES to this
    workspace, so every call resets with a fresh `git checkout -f <base_commit> && git clean -qfdx`
    even when the sha was already fetched once, instead of trusting a "seen this sha before" marker to
    skip the reset (LocBench's marker check is correct for a read-only consumer; reusing it as-is here
    would leak a previous run's agent edits into the next run). Returns the workspace dir, or None on a
    checkout failure (fail-closed — caller must not silently score/execute against a stale tree)."""
    dst = repos_dir / repo.replace( "/", "__" )
    fetched_marker = dst / f".ripwire_fetched_{base_commit}"
    if not fetched_marker.exists():
        if not ( dst / ".git" ).exists():
            dst.mkdir( parents=True, exist_ok=True )
            sh( [ "git", "init", "-q" ], cwd=dst )
            sh( [ "git", "remote", "add", "origin", f"https://github.com/{repo}.git" ], cwd=dst )
        f = sh( [ "git", "fetch", "-q", "--depth", "1", "origin", base_commit ], cwd=dst )
        if f.returncode != 0:
            sh( [ "git", "fetch", "-q", "origin" ], cwd=dst )   # fallback: unshallow fetch of the ref
        fetched_marker.write_text( "" )
    co = sh( [ "git", "checkout", "-q", "-f", base_commit ], cwd=dst )
    if co.returncode != 0:
        co = sh( [ "git", "checkout", "-q", "-f", "FETCH_HEAD" ], cwd=dst )
    sh( [ "git", "clean", "-qfdx" ], cwd=dst )
    if co.returncode != 0:
        return None
    return dst

# ── gold row lookup (problem_statement / patch / test_patch / FAIL_TO_PASS / PASS_TO_PASS) ───────────
# tasks.lock deliberately carries ONLY instance_id/repo/base_commit in its content-hashed instances list
# (see select_tasks.py's content_hash()) — everything else about an instance is fetched here, on demand,
# reusing select_tasks.py's exact fetch_rows() cache file so a --work-dir already populated by
# `select_tasks.py --work-dir X` needs no re-fetch.
def load_gold_rows( work_dir ):
    rows = select_tasks.fetch_rows( 0, pathlib.Path( work_dir ) / "datasets" )
    return { r["instance_id"]: r for r in rows }

def patch_files( patch ):
    # identical parse to bench/locbench/run_locbench.py's patch_files() (gold/candidate FILES = the
    # files a unified diff touches). Duplicated rather than imported: bench/locbench modules aren't
    # meant to be imported cross-directory, and this is a two-line regex, not a maintenance burden.
    return sorted( set( re.findall( r'^\+\+\+ b/(.+)$', patch, re.M ) )
                 | set( re.findall( r'^--- a/(.+)$', patch, re.M ) ) )

def build_prompt( gold_row, seed, arm, ripwire_bin, rules_blurb="" ):
    stmt = ( gold_row.get( "problem_statement" ) or "" ).strip()
    prompt = (
        "You are working directly in a git checkout of this repository, at the commit the following "
        "issue was filed against. Read the issue, locate the responsible code, and make the minimal "
        "fix. Do not modify any test files. Stop once you believe the fix is complete.\n\n"
        f"ISSUE:\n{stmt}\n\n"
        # `claude -p` has no seed/temperature knob; K=3 seeded runs (README.md "Seeds") vary via this
        # deterministic prompt suffix instead. The seed is always recorded in the result record's `seed`
        # field regardless of whether this suffix measurably perturbs sampling.
        f"[run-seed:{seed}]"
    )
    if arm == "baseline":
        return prompt + ( "\n\nRETRIEVAL ARM — BASELINE: Do not use ripwire or ctxpack. Use the agent's "
                          "ordinary repository search and file-reading tools." )
    # Both ripwire arms get the SAME prompt contract. They differ only in what the environment puts
    # on disk (ripwire_skills adds the skills tree), so any prompt-level difference between them
    # would confound exactly the comparison the third arm exists to make.
    if arm in RIPWIRE_ARMS:
        suffix = ( "\n\nRETRIEVAL ARM — RIPWIRE CLI: Do not use a ripwire MCP server. Before "
                   "grep/find or opening implementation files, use the shell to run this exact CLI "
                   "binary at least once:\n"
                   f"  {ripwire_bin} . --for=\"<short issue description>\" --max-tokens=4000\n"
                   "Use its ranked output and any additional ripwire CLI verbs that help, then "
                   "continue with ordinary editing and validation tools." )
        # The rules blurb is the SHIPPED wrap recipe's body, read straight out of `ripwire wrap`
        # rather than restated here, so the eval cannot drift from what users are actually told.
        if rules_blurb:
            suffix += "\n\n" + rules_blurb.strip()
        return prompt + suffix
    raise ValueError( f"unknown arm {arm!r}; expected one of {ARMS}" )

def install_ripwire_shim( run_home, ripwire_bin ):
    """Return a path to a logging wrapper around ripwire, and the log file it appends to.

    Counting ripwire invocations by grepping an agent's transcript only works for agents that
    self-log every shell command. Codex does; opencode does; `claude -p` does NOT, which is why every
    claude-harness run in this file has recorded ripwire_calls=None since it was written. A shim is
    harness-agnostic: the arm's prompt names THIS path, so the call is counted no matter which agent
    ran it and no matter whether it was invoked via PATH or absolutely.

    The shim execs the real binary, so it cannot change what ripwire returns — only observe that it
    was asked. Cross-checking it against a transcript-derived count (where one exists) is a free
    consistency check on both mechanisms."""
    shim_dir = pathlib.Path( run_home ) / "shim"
    shim_dir.mkdir( parents=True, exist_ok=True )
    log = shim_dir / "ripwire-calls.log"
    shim = shim_dir / "ripwire"
    real = str( pathlib.Path( ripwire_bin ).resolve() ) if os.sep in str( ripwire_bin ) else str( ripwire_bin )
    shim.write_text(
        "#!/usr/bin/env bash\n"
        "# generated by run_agentloop.py — logs argv, then execs the real binary unchanged.\n"
        f"printf '%s\\n' \"$*\" >> {shlex.quote( str( log ) )}\n"
        f"exec {shlex.quote( real )} \"$@\"\n" )
    shim.chmod( 0o755 )
    return str( shim ), log

def read_shim_log( log_path ):
    """(call_count, commands) from the shim's log; ([],0) if it was never invoked."""
    try:
        lines = [ ln for ln in pathlib.Path( log_path ).read_text().splitlines() if ln.strip() ]
    except OSError:
        return 0, []
    return len( lines ), lines

def build_codex_command( prompt, model ):
    """Build an isolated Codex invocation; build_prompt() owns the arm-specific CLI contract."""
    cmd = [ "codex", "exec", "--json", "--ephemeral", "--ignore-user-config", "--ignore-rules",
            "--sandbox", "workspace-write", "-c", 'approval_policy="never"',
            "-c", 'web_search="disabled"', "-c", "mcp_servers={}" ]
    if model:
        cmd += [ "--model", model ]
    cmd.append( prompt )
    return cmd

def parse_codex_jsonl_usage( stdout ):
    """Return the final turn's (input_tokens, output_tokens), or nulls on schema drift."""
    tokens_in = tokens_out = None
    for line in stdout.splitlines():
        try:
            event = json.loads( line )
        except ValueError:
            continue
        if event.get( "type" ) != "turn.completed":
            continue
        usage = event.get( "usage" ) or {}
        tokens_in = usage.get( "input_tokens" )
        tokens_out = usage.get( "output_tokens" )
    return tokens_in, tokens_out

def parse_codex_jsonl_metrics( stdout, ripwire_bin ):
    """Return token usage plus explicit command/ripwire-CLI evidence from retained Codex JSONL."""
    tokens_in, tokens_out = parse_codex_jsonl_usage( stdout )
    command_calls = ripwire_calls = 0
    ripwire_commands = []
    for line in stdout.splitlines():
        try:
            event = json.loads( line )
        except ValueError:
            continue
        item = event.get( "item" ) or {}
        if event.get( "type" ) != "item.completed" or item.get( "type" ) != "command_execution":
            continue
        command_calls += 1
        command = item.get( "command" ) or ""
        if isinstance( command, list ):
            command = " ".join( str( part ) for part in command )
        command = str( command )
        if ripwire_bin and ripwire_bin in command:
            ripwire_calls += 1
            ripwire_commands.append( command )
    return tokens_in, tokens_out, command_calls, ripwire_calls, ripwire_commands

def build_opencode_command( prompt, model ):
    """Build a non-interactive opencode invocation.

    `--auto` approves permissions that are not explicitly denied — required for an unattended run and
    the reason this harness must only ever be pointed at a throwaway checkout.

    --model is NOT optional here, unlike the other two harnesses. opencode does not fail closed when
    no credential is configured: with an empty auth store it silently selects its own free hosted
    model and completes the turn (verified 2026-08-10, v1.18.16: providerID=opencode,
    modelID=big-pickle, cost=0). Every token, latency and resolution number from such a run belongs to
    a different model than the one under test, with no error anywhere. run_one() additionally reads
    the model back out of the transcript and refuses the record if it disagrees — passing the flag is
    not enough, because the flag is what gets silently overridden."""
    cmd = [ "opencode", "run", "--format", "json", "--auto" ]
    if model:
        cmd += [ "--model", model ]
    cmd.append( prompt )
    return cmd

def parse_opencode_ndjson_metrics( stdout, ripwire_bin ):
    """Token/command accounting from opencode's `--format json` NDJSON event stream.

    Every line is {"type":..,"timestamp":..,"sessionID":..,"part":{..}}. Tokens and cost arrive on
    `step_finish` (part.tokens.{input,output,reasoning,cache{read,write}} and part.cost); every shell
    command arrives as a `tool_use` whose part.tool == "bash", with the command in part.state.input.
    Returns nulls rather than raising on schema drift — opencode ships releases daily and the
    retained transcript is the evidence of record either way."""
    tokens_in = tokens_out = cost = model_id = None
    command_calls = ripwire_calls = 0
    ripwire_commands = []
    for line in ( stdout or "" ).splitlines():
        try:
            event = json.loads( line )
        except ValueError:
            continue
        part = event.get( "part" ) or {}
        etype = event.get( "type" )
        if etype == "step_finish":
            usage = part.get( "tokens" ) or {}
            # last step wins: these are cumulative per-turn totals, same convention as the codex parser
            tokens_in  = usage.get( "input", tokens_in )
            tokens_out = usage.get( "output", tokens_out )
            cost       = part.get( "cost", cost )
        if etype in ( "step_start", "step_finish" ):
            model_id = part.get( "modelID" ) or event.get( "modelID" ) or model_id
        if etype == "tool_use" and part.get( "tool" ) == "bash":
            command_calls += 1
            state   = part.get( "state" ) or {}
            payload = state.get( "input" ) or {}
            command = payload.get( "command" ) if isinstance( payload, dict ) else payload
            command = " ".join( map( str, command ) ) if isinstance( command, list ) else str( command or "" )
            if ripwire_bin and ripwire_bin in command:
                ripwire_calls += 1
                ripwire_commands.append( command )
    return tokens_in, tokens_out, cost, model_id, command_calls, ripwire_calls, ripwire_commands

def prepare_opencode_environment( work_dir, instance_id, arm, seed, ripwire_bin ):
    """Create a fully isolated opencode environment for one run, and return (env, run_home, shim).

    opencode has NO --ignore-user-config equivalent, and OPENCODE_CONFIG does not replace the global
    config — it is merged ON TOP of it (config.ts loads the global file first). The only lever that
    actually isolates is relocating the XDG dirs, because opencode derives every path from
    xdg-basedir at module load. HOME must be redirected independently: ~/.opencode and, critically,
    $HOME/.claude/CLAUDE.md are read off os.homedir(), and opencode loads that Claude rules file into
    every run unless OPENCODE_DISABLE_CLAUDE_CODE is set.

    That last one is not hypothetical here: this repository's own developers keep a ripwire usage
    protocol in ~/.claude/CLAUDE.md. Without this isolation the BASELINE arm is briefed on ripwire and
    the experiment measures nothing. test/opencodeisocheck.sh asserts the recipe still holds."""
    env = os.environ.copy()
    run_home = pathlib.Path( work_dir ) / "opencode-home" / arm / f"{instance_id}-{seed}"
    for sub in ( "home", "config", "data", "state", "cache" ):
        ( run_home / sub ).mkdir( parents=True, exist_ok=True )

    # auth: symlink the real credential store into the isolated data dir rather than copying it, so a
    # run can authenticate without the secret being duplicated into the work dir. Same posture as the
    # codex path. If no credential exists, the run must fail loudly rather than fall back to the free
    # hosted model — see build_opencode_command().
    source_auth = pathlib.Path( env.get( "XDG_DATA_HOME", pathlib.Path.home() / ".local/share" ) ) / "opencode" / "auth.json"
    if source_auth.exists():
        dest_dir = run_home / "data" / "opencode"
        dest_dir.mkdir( parents=True, exist_ok=True )
        link = dest_dir / "auth.json"
        if not link.exists():
            link.symlink_to( source_auth )

    # NOTE on the rules-file channel: opencode WOULD read an AGENTS.md from the project root, and that
    # is how a real user installs the blurb. It is delivered through the prompt instead (build_prompt),
    # because codex runs with --ignore-rules — needed to keep the developer's own rules out of the
    # baseline — and would silently drop a rules file. One channel that every harness honours keeps
    # the arms comparable ACROSS harnesses; the cost is that this measures the blurb's content, not
    # opencode's rules-file discovery. That trade is deliberate and belongs in the write-up.

    # the skills tree is the THIRD arm's only difference from the second
    if arm == "ripwire_skills":
        source_skills = pathlib.Path( __file__ ).resolve().parents[2] / "skills"
        run_skills = run_home / "config" / "opencode" / "skills"
        run_skills.mkdir( parents=True, exist_ok=True )
        for skill_dir in sorted( source_skills.iterdir() ):
            if skill_dir.is_dir() and ( skill_dir / "SKILL.md" ).is_file():
                link = run_skills / skill_dir.name
                if not link.exists():
                    link.symlink_to( skill_dir, target_is_directory=True )

    shim, _log = install_ripwire_shim( run_home, ripwire_bin )
    env.update(
        HOME                            = str( run_home / "home" ),
        XDG_CONFIG_HOME                 = str( run_home / "config" ),
        XDG_DATA_HOME                   = str( run_home / "data" ),
        XDG_STATE_HOME                  = str( run_home / "state" ),
        XDG_CACHE_HOME                  = str( run_home / "cache" ),
        OPENCODE_DISABLE_PROJECT_CONFIG = "1",
        OPENCODE_DISABLE_CLAUDE_CODE    = "1",
        OPENCODE_DISABLE_AUTOUPDATE     = "1",
    )
    env["PATH"] = str( pathlib.Path( shim ).parent ) + os.pathsep + env.get( "PATH", "" )
    return env, run_home, shim

def extract_wrap_blurb( wrap_stdout ):
    """Pull the pasteable rules body out of `ripwire wrap <agent>` output.

    The recipe fences it with `# --- paste into <file> ---` / `# --- end paste ---`; everything
    between the fences is the body a real user pastes, so that is exactly what the arm injects."""
    body, inside = [], False
    for line in ( wrap_stdout or "" ).splitlines():
        if line.startswith( "# --- paste into " ):
            inside = True
            continue
        if line.startswith( "# --- end paste ---" ):
            break
        if inside:
            body.append( line )
    return "\n".join( body ) + "\n" if body else ""

def agent_version( harness ):
    """Best-effort agent version string for the record; None if the binary will not say."""
    binary = { "opencode": "opencode", "codex-exec": "codex", "claude-code-p": "claude" }.get( harness )
    if not binary:
        return None
    try:
        out = subprocess.run( [ binary, "--version" ], capture_output=True, text=True, timeout=30 )
    except ( OSError, subprocess.SubprocessError ):
        return None
    return ( out.stdout or out.stderr or "" ).strip().splitlines()[ 0 ] if ( out.stdout or out.stderr ) else None

def prepare_codex_environment( work_dir, instance_id, arm, seed, ripwire_bin ):
    """Create an auth-preserving but skill-isolated CODEX_HOME for one benchmark run.

    Baseline gets no skills. The treatment gets only this checkout's ripwire skills, so globally
    installed skills cannot add hidden tools or retrieval steps to either arm."""
    env = os.environ.copy()
    source_home = pathlib.Path( env.get( "CODEX_HOME", pathlib.Path.home() / ".codex" ) )
    run_home = pathlib.Path( work_dir ) / "codex-home" / arm / f"{instance_id}-{seed}"
    run_home.mkdir( parents=True, exist_ok=True )
    source_auth = source_home / "auth.json"
    run_auth = run_home / "auth.json"
    if source_auth.exists() and not run_auth.exists():
        run_auth.symlink_to( source_auth )

    # v3 CHANGE: the skills tree moved off `ripwire_cli` and onto its own arm. It used to ride along
    # here, which is why the 2026-08-04 pilot's +80% token cost could not be attributed — see ARMS.
    if arm == "ripwire_skills":
        source_skills = pathlib.Path( __file__ ).resolve().parents[2] / "skills"
        run_skills = run_home / "skills"
        run_skills.mkdir( parents=True, exist_ok=True )
        for skill_dir in sorted( source_skills.iterdir() ):
            if skill_dir.is_dir() and ( skill_dir / "SKILL.md" ).is_file():
                link = run_skills / skill_dir.name
                if not link.exists():
                    link.symlink_to( skill_dir, target_is_directory=True )

    agents_home = pathlib.Path( work_dir ) / "agent-home" / arm / f"{instance_id}-{seed}"
    agents_home.mkdir( parents=True, exist_ok=True )
    env["CODEX_HOME"] = str( run_home )
    env["AGENTS_HOME"] = str( agents_home )
    shim, _log = install_ripwire_shim( run_home, ripwire_bin )
    env["PATH"] = str( pathlib.Path( shim ).parent ) + os.pathsep + env.get( "PATH", "" )
    return env, run_home, shim

# ── evaluation (--evaluator swebench|none) ─────────────────────────────────────────────────────────────
def run_swebench_harness( task, patch, run_id_prefix="ripwire-agentloop" ):
    """Score ONE candidate patch with the official SWE-bench evaluation harness (`swebench` PyPI
    package). Import-guarded: raises a clear, actionable SystemExit (not an ImportError traceback) if
    the package isn't installed, per --evaluator=swebench's contract. Requires Docker (the harness
    builds a per-instance image and runs FAIL_TO_PASS/PASS_TO_PASS inside it) — not checked here beyond
    letting the harness subprocess fail with its own error if Docker is unavailable.

    TODO-verify: shells out to the documented CLI entrypoint `python -m swebench.harness.run_evaluation`
    (https://github.com/princeton-nlp/SWE-bench#-usage) rather than importing internal functions, since
    the internal module layout has changed across swebench releases and the CLI is the stable, documented
    surface. NOT exercised in this change (no Docker / swebench install in this environment) — re-check
    before the first real --evaluator=swebench run:
      * the flag names below (--predictions_path/--run_id/--dataset_name/--instance_ids/--max_workers)
        against the installed package's `python -m swebench.harness.run_evaluation --help`;
      * the predictions file's expected schema (instance_id/model_patch/model_name_or_path) — this is
        the documented SWE-bench predictions format as of the 2024-2025 harness releases, but field
        names have shifted before (e.g. `model_patch` vs `patch`);
      * the report output filename/location (`<run_id_prefix>.<run_id>.json` in CWD is the documented
        convention; the glob fallback below is a hedge, not a substitute for checking) and the resolved-
        instances key (`resolved_ids` — some harness versions nest this under a per-instance report
        instead of a top-level list)."""
    try:
        import swebench  # noqa: F401 — import-guard only; the CLI subprocess below does the real work
    except ImportError:
        raise SystemExit(
            "--evaluator=swebench requires the official SWE-bench harness: `pip install swebench` "
            "(https://github.com/princeton-nlp/SWE-bench) plus a working Docker daemon (the harness "
            "builds a per-instance image and runs FAIL_TO_PASS/PASS_TO_PASS inside it). Neither is "
            "assumed to be present in this environment; pass --evaluator=none to proceed without it." )

    work = pathlib.Path( tempfile.mkdtemp( prefix="ripwire-agentloop-eval-" ) )
    run_id = f"{run_id_prefix}-{task['instance_id']}-{int(time.time())}"
    predictions_path = work / "predictions.json"
    predictions_path.write_text( json.dumps( [ dict(
        instance_id=task["instance_id"], model_patch=patch, model_name_or_path=run_id_prefix ) ] ) )

    cmd = [ sys.executable, "-m", "swebench.harness.run_evaluation",
            "--predictions_path", str( predictions_path ),
            "--run_id", run_id,
            "--dataset_name", "princeton-nlp/SWE-bench_Lite",
            "--instance_ids", task["instance_id"],
            "--report_dir", str( work ),      # else the report lands in the CALLER's cwd — 144 runs, 144 strays
            "--max_workers", "1" ]
    proc = sh( cmd, timeout=3600, cwd=str( work ) )
    if proc.returncode != 0:
        blob = ( ( proc.stderr or "" ) + ( proc.stdout or "" ) ).lower()
        # An infrastructure failure is NOT an unresolved patch, and conflating them silently poisons
        # the headline metric: every Docker/disk failure would read as "ripwire did not help". These
        # signatures are fatal for a batch (they do not fix themselves between instances), so they
        # stop the run instead of scoring it.
        for signature, hint in ( ( "no space left on device", "the SWE-bench images need ~120GB free" ),
                                 ( "cannot connect to the docker daemon", "start Docker/colima first" ),
                                 ( "docker: error", "the Docker daemon rejected the run" ),
                                 ( "error pulling image", "image pull failed — check network/registry" ) ):
            if signature in blob:
                raise SystemExit( f"swebench harness infrastructure failure ({signature}): {hint}. "
                                  f"Refusing to score — an infra failure is not an unresolved patch." )
        print( f"# swebench harness run failed for {task['instance_id']} (recording UNSCORED, not "
               f"unresolved): {(proc.stderr or '')[-2000:]}", file=sys.stderr )
        return None

    # Verified 2026-08-10 against SWE-bench/SWE-bench@main (run_evaluation.py, harness/reporting.py):
    # the report is "<model_name_or_path>.<run_id>.json" and resolved instances are under the
    # top-level "resolved_ids" key. model_name_or_path is set to run_id_prefix above, which contains
    # no "/" and so never takes reporting.py's "/"->"__" substitution path. The glob is a hedge for
    # a future rename, not a substitute for that check.
    report_path = work / f"{run_id_prefix}.{run_id}.json"
    if not report_path.exists():
        candidates = sorted( work.glob( f"*{run_id}*.json" ) )
        report_path = candidates[0] if candidates else None
    if not report_path or not report_path.exists():
        print( f"# swebench harness produced no report for {task['instance_id']}; recording UNSCORED",
               file=sys.stderr )
        return None
    report = json.loads( report_path.read_text() )
    return task["instance_id"] in set( report.get( "resolved_ids", report.get( "resolved", [] ) ) )

def evaluate_patch( task, gold_row, patch, evaluator ):
    """Return (resolved: bool|None, localization_hit: bool|None) for one candidate patch.

    evaluator='none'     -> resolved=None always (no Docker / swebench harness invoked, so runs can
                             proceed before that's set up); localization_hit is still computed locally
                             (cheap, no execution) whenever a gold patch is available.
    evaluator='swebench' -> resolved is computed via the official `swebench` harness (see
                             run_swebench_harness()); an empty candidate patch short-circuits to
                             resolved=False without spending a Docker run (it cannot pass any test)."""
    cand_files = set( patch_files( patch ) ) if patch.strip() else set()
    gold_files = set( patch_files( gold_row.get( "patch", "" ) ) )
    localization_hit = bool( cand_files & gold_files ) if gold_files else None

    if evaluator == "none":
        return None, localization_hit
    if evaluator == "swebench":
        if not patch.strip():
            return False, localization_hit
        return run_swebench_harness( task, patch ), localization_hit
    raise SystemExit( f"unknown --evaluator {evaluator!r}; expected 'swebench' or 'none'" )

# ── the one seam a real harness fills in ──────────────────────────────────────────────────────────
def _codex_metrics( stdout, work_dir, task, arm, seed, ripwire_bin, shim_log=None ):
    """Retain raw Codex JSONL under events/ and parse its token/command accounting into record fields.

    Accepts str, bytes (TimeoutExpired hands over undecoded partial output), or None; anything
    unparseable degrades field-by-field to nulls, never a crash — the retained file is the evidence."""
    if isinstance( stdout, bytes ):
        stdout = stdout.decode( "utf-8", errors="replace" )
    stdout = stdout or ""
    events_dir = pathlib.Path( work_dir ) / "events"
    events_dir.mkdir( parents=True, exist_ok=True )
    events_file = events_dir / f"{task['instance_id']}-{arm}-{seed}.jsonl"
    events_file.write_text( stdout )
    ( tokens_in, tokens_out, command_calls,
      ripwire_calls, ripwire_commands ) = parse_codex_jsonl_metrics( stdout, ripwire_bin )
    if shim_log is not None:
        shim_calls, shim_commands = read_shim_log( shim_log )
        if shim_calls != ripwire_calls:
            ripwire_commands = shim_commands
        ripwire_calls = shim_calls
    return dict( tokens_in=tokens_in, tokens_out=tokens_out, command_calls=command_calls,
                 ripwire_calls=ripwire_calls, ripwire_commands=ripwire_commands,
                 events_path=str( events_file ) )

def _opencode_metrics( stdout, work_dir, task, arm, seed, ripwire_bin, shim_log=None ):
    """Retain opencode's NDJSON transcript and parse it into record fields.

    Two independent counts of ripwire invocations are available here — the shim log (authoritative,
    harness-agnostic) and opencode's own `tool_use` events. The shim wins when they disagree, but the
    disagreement itself is recorded in `error`, because a silent divergence means one of the two
    instruments is broken and neither number should be trusted until it is understood."""
    if isinstance( stdout, bytes ):
        stdout = stdout.decode( "utf-8", errors="replace" )
    stdout = stdout or ""
    events_dir = pathlib.Path( work_dir ) / "events"
    events_dir.mkdir( parents=True, exist_ok=True )
    events_file = events_dir / f"{task['instance_id']}-{arm}-{seed}.jsonl"
    events_file.write_text( stdout )

    ( tokens_in, tokens_out, cost, model_id,
      command_calls, ripwire_calls, ripwire_commands ) = parse_opencode_ndjson_metrics( stdout, ripwire_bin )

    if shim_log is not None:
        shim_calls, shim_commands = read_shim_log( shim_log )
        if shim_calls != ripwire_calls:
            ripwire_commands = shim_commands
        ripwire_calls = shim_calls
    return dict( tokens_in=tokens_in, tokens_out=tokens_out, cost_usd=cost,
                 command_calls=command_calls, ripwire_calls=ripwire_calls,
                 ripwire_commands=ripwire_commands, events_path=str( events_file ),
                 resolved_model=model_id )

def _claude_metrics( stdout, shim_log=None ):
    """Parse the `claude -p --output-format json` single-result trailer into record fields.

    TODO-verify: field names match the documented schema (top-level total_cost_usd;
    usage.input_tokens/usage.output_tokens) as of the Claude Code CLI installed when this was written
    (2.1.209) — re-check against a real trailer (e.g. via --live-one) before trusting these numbers in
    an actual pilot; schema drift degrades accounting to nulls (make_record defaults), not a crash."""
    try:
        payload = json.loads( stdout )
    except ValueError:
        return {}
    usage = payload.get( "usage" ) or {}
    out = dict( tokens_in=usage.get( "input_tokens" ), tokens_out=usage.get( "output_tokens" ),
                cost_usd=payload.get( "total_cost_usd" ) )
    # `claude -p` does not log individual shell commands, so before the shim there was no
    # ripwire-invocation evidence for this harness at all — every claude run recorded
    # ripwire_calls=None. The shim closes that gap without depending on the agent's transcript.
    if shim_log is not None:
        calls, commands = read_shim_log( shim_log )
        out.update( ripwire_calls=calls, ripwire_commands=commands )
    return out

def _harness_metrics( harness, stdout, work_dir, task, arm, seed, ripwire_bin, shim_log ):
    """Route stdout to the right parser. Explicit per-harness dispatch, never a binary fallthrough:
    the two-branch ternaries this replaces silently gave any third harness claude's parser."""
    if harness == "codex-exec":
        return _codex_metrics( stdout, work_dir, task, arm, seed, ripwire_bin, shim_log )
    if harness == "opencode":
        return _opencode_metrics( stdout, work_dir, task, arm, seed, ripwire_bin, shim_log )
    return _claude_metrics( stdout if isinstance( stdout, str ) else ( stdout or b"" ).decode( "utf-8", "replace" ),
                            shim_log )

def run_one( task, arm, seed, harness, model, *, work_dir=".", ripwire_bin=RIPWIRE_BIN_DEFAULT,
             timeout_s=DEFAULT_TIMEOUT_SECONDS, evaluator="none", gold_rows=None, lane="" ):
    """Execute ONE (task, arm, seed) run through the selected harness and return a filled record.

    Steps: (a) checkout task["repo"]@task["base_commit"] into a cached, per-repo workspace, reset fresh
    for this run (checkout_repo()); (b) invoke the harness in that workspace with an arm-specific CLI
    retrieval contract and no MCP servers; (c) capture wall-clock, token/cost accounting
    (_codex_metrics()/_claude_metrics(), best-effort), and the workspace's final `git diff` as the
    candidate patch; (d) score it via evaluate_patch()."""
    started = time.time()
    def _fail( status, error, **overrides ):
        return make_record( task, arm, seed, harness, model, status=status, error=error,
                             started_unix=started, finished_unix=time.time(), **overrides )

    if harness not in HARNESSES:
        return _fail( "error", f"unsupported harness {harness!r}; expected one of {HARNESSES}" )
    if arm not in ARMS:
        return _fail( "error", f"unknown arm {arm!r}; expected one of {ARMS}" )

    gold_row = ( gold_rows or {} ).get( task["instance_id"] )
    if gold_row is None:
        return _fail( "error", f"no cached SWE-bench row for {task['instance_id']!r} — pass a --work-dir "
                                f"whose datasets cache load_gold_rows()/select_tasks.fetch_rows() can reach" )

    # Per-worker checkout root. checkout_repo() keeps ONE clone per repo and hard-resets it for every
    # run, so two concurrent runs touching the same repo would clobber each other's working tree
    # mid-agent. Sharding the root by worker is what makes --concurrency safe; the default lane
    # ("") is byte-identical to the old single-threaded path.
    repos_dir = pathlib.Path( work_dir ) / ( f"repos{lane}" if lane else "repos" )
    repo_dir = checkout_repo( task["repo"], task["base_commit"], repos_dir )
    if repo_dir is None:
        return _fail( "error", f"checkout failed for {task['repo']}@{task['base_commit']}" )

    # The environment is prepared BEFORE the prompt, because it installs the ripwire shim and the
    # prompt must name that shim rather than the bare binary — otherwise an agent invoking ripwire by
    # absolute path walks straight past the counter.
    child_env, run_home, shim_bin, shim_log = None, None, ripwire_bin, None
    if harness == "codex-exec":
        child_env, run_home, shim_bin = prepare_codex_environment( work_dir, task["instance_id"], arm, seed, ripwire_bin )
    elif harness == "opencode":
        child_env, run_home, shim_bin = prepare_opencode_environment( work_dir, task["instance_id"], arm, seed, ripwire_bin )
    if run_home is not None:
        shim_log = pathlib.Path( run_home ) / "shim" / "ripwire-calls.log"

    rules_blurb = ""
    if arm in RIPWIRE_ARMS:
        wrap_agent = { "opencode": "opencode", "codex-exec": "codex" }.get( harness, "claude" )
        wrapped = subprocess.run( [ str( ripwire_bin ), "wrap", wrap_agent, "--force" ],
                                  capture_output=True, text=True )
        rules_blurb = extract_wrap_blurb( wrapped.stdout )

    prompt = build_prompt( gold_row, seed, arm, shim_bin, rules_blurb )
    if harness == "claude-code-p":
        cmd = [ "claude", "-p", prompt,
                "--permission-mode", "acceptEdits",
                "--output-format", "json",
                "--strict-mcp-config", "--allowedTools", ALLOWED_TOOLS_BASELINE ]
        if model:
            cmd += [ "--model", model ]
    elif harness == "codex-exec":
        cmd = build_codex_command( prompt, model )
    else:
        cmd = build_opencode_command( prompt, model )

    t0 = time.perf_counter()
    try:
        proc = sh( cmd, cwd=repo_dir, timeout=timeout_s, env=child_env )
    except subprocess.TimeoutExpired as exc:
        diff = sh( [ "git", "diff" ], cwd=repo_dir ).stdout
        resolved, localization_hit = evaluate_patch( task, gold_row, diff, evaluator )
        metrics = _harness_metrics( harness, exc.stdout, work_dir, task, arm, seed, ripwire_bin, shim_log )
        return _fail( "timeout", f"{harness} exceeded {timeout_s}s", resolved=resolved,
                      localization_hit=localization_hit, wall_seconds=float( timeout_s ),
                      harness_version=agent_version( harness ), **metrics )
    wall = time.perf_counter() - t0

    diff = sh( [ "git", "diff" ], cwd=repo_dir ).stdout   # candidate patch: working tree vs base_commit

    if proc.returncode != 0:
        return _fail( "error", f"{harness} exit {proc.returncode}: {(proc.stderr or '')[:2000]}",
                       wall_seconds=wall )

    metrics = _harness_metrics( harness, proc.stdout, work_dir, task, arm, seed, ripwire_bin, shim_log )

    # The model-substitution guard. opencode silently falls back to its own free hosted model when no
    # credential resolves, so a run can succeed against a model nobody asked for. A record whose
    # resolved_model contradicts --model is not a usable datapoint and is marked as an error rather
    # than averaged into an arm.
    used = metrics.get( "resolved_model" )
    if model and used and used not in model:
        return _fail( "error",
                      f"model substitution: asked for {model!r}, harness actually used {used!r} — "
                      f"check credentials; opencode routes to its own free model when auth is absent",
                      wall_seconds=wall, harness_version=agent_version( harness ), **metrics )

    resolved, localization_hit = evaluate_patch( task, gold_row, diff, evaluator )
    return make_record( task, arm, seed, harness, model, status="ok",
                         resolved=resolved, localization_hit=localization_hit, wall_seconds=wall,
                         started_unix=started, finished_unix=time.time(),
                         harness_version=agent_version( harness ), **metrics )

def main():
    ap = argparse.ArgumentParser( description="Phase B4 agent-in-the-loop eval runner (scaffolding)" )
    ap.add_argument( "--tasks-lock", default=str( pathlib.Path( __file__ ).parent / "tasks.lock" ) )
    ap.add_argument( "--arms", default=",".join( ARMS ) )
    ap.add_argument( "--seeds", default=",".join( str( s ) for s in DEFAULT_SEEDS ) )
    ap.add_argument( "--harness", default="claude-code-p", choices=HARNESSES,
                     help="agent harness: Claude Code print mode, OpenAI Codex non-interactive mode, "
                          "or opencode `run --format json` (the only one of the three that is open "
                          "source and scriptable enough for an unattended matrix)" )
    ap.add_argument( "--concurrency", type=int, default=1, metavar="N",
                     help="run N cells at once, each in its own checkout lane (default 1 = sequential). "
                          "The matrix is otherwise a strictly serial walk: 216 runs at up to 900s each "
                          "is a multi-hour commitment." )
    ap.add_argument( "--resume", default="", metavar="RESULTS_JSON",
                     help="skip (instance,arm,seed) tuples already completed in this results file and "
                          "merge the new records into it. Without this, re-invoking --live after an "
                          "interruption restarts at run 1 and re-spends money on finished runs." )
    ap.add_argument( "--model", default="",
                     help="model id; omitted uses the selected harness's current default" )
    ap.add_argument( "--limit", type=int, default=0, help="cap tasks used to build the matrix (0=all); "
                     "use --limit 3 for the pilot run size named in README.md" )
    ap.add_argument( "--results-out", default="", help="where to write the results JSON" )
    ap.add_argument( "--work-dir", default="/tmp/agentloop",
                     help="scratch dir for repo checkouts, the SWE-bench gold-row cache (shared with "
                          "select_tasks.py's --work-dir), retained Codex JSONL, and isolated agent homes" )
    ap.add_argument( "--ripwire-bin", default=RIPWIRE_BIN_DEFAULT,
                     help="absolute ripwire binary the ripwire_cli arm is required to invoke "
                          "(default: $RIPWIRE env var, else 'ripwire' on PATH)" )
    ap.add_argument( "--evaluator", default="none", choices=( "swebench", "none" ),
                     help="'swebench' scores resolved= via the official swebench PyPI harness (Docker "
                          "required); 'none' (default) records resolved=None so the harness can run "
                          "before Docker/swebench are set up — see evaluate_patch()" )
    ap.add_argument( "--timeout-seconds", type=int, default=DEFAULT_TIMEOUT_SECONDS,
                     help="per-run wall-clock timeout for the `claude -p` subprocess" )
    mode = ap.add_mutually_exclusive_group( required=True )
    mode.add_argument( "--dry-run", action="store_true",
                       help="validate tasks.lock, print the run matrix + cost projection, write a "
                            "schema-valid EMPTY results file. Executes zero agent runs." )
    mode.add_argument( "--live-one", action="store_true",
                       help="execute exactly ONE real (task, arm, seed) run — the first entry of the run "
                            "matrix (combine with --limit 1 --arms=... --seeds=... to pin which one) — "
                            "and print its record. The cheapest end-to-end proof the harness works." )
    mode.add_argument( "--live", action="store_true",
                       help="execute every (task, arm, seed) run in the matrix through --harness. Real "
                            "money / real API calls — read README.md's SAFETY NOTE first." )
    a = ap.parse_args()

    lock = load_tasks_lock( a.tasks_lock )
    tasks = limit_tasks_repo_round_robin( lock["instances"], a.limit )
    arms = [ x.strip() for x in a.arms.split( "," ) if x.strip() ]
    seeds = [ int( x ) for x in a.seeds.split( "," ) if x.strip() ]
    for arm in arms:
        if arm not in ARMS: raise SystemExit( f"unknown arm {arm!r}; expected one of {ARMS}" )
    matrix = run_matrix( tasks, arms, seeds )

    print( f"# tasks.lock verified: content_sha256={lock['content_sha256'][:16]}... "
           f"({lock['selected_count']} instances, {lock['selected_repo_count']} repos)", file=sys.stderr )
    print( f"# run matrix: {len(tasks)} tasks x {len(arms)} arms x {len(seeds)} seeds = {len(matrix)} runs",
           file=sys.stderr )
    lo, hi = len( tasks ) * len( arms ) * len( seeds ) * COST_LOW_PER_INSTANCE, \
             len( tasks ) * len( arms ) * len( seeds ) * COST_HIGH_PER_INSTANCE
    print( f"# projected cost at ${COST_LOW_PER_INSTANCE:.2f}-${COST_HIGH_PER_INSTANCE:.2f}/instance "
           f"(arXiv 2412.21139): ${lo:.0f}-${hi:.0f}", file=sys.stderr )
    by_repo = {}
    for t in tasks: by_repo.setdefault( t["repo"], 0 ); by_repo[t["repo"]] += 1
    print( f"# repo distribution: {dict(sorted(by_repo.items()))}", file=sys.stderr )

    if a.dry_run:
        # Zero agent execution. Still exercises the FULL pipeline shape: build every record as the
        # "not_implemented" status a live run would start from, so downstream tooling (analyze.py)
        # can be developed and self-tested against a schema-valid, realistically-shaped file today.
        records = [ make_record( t, arm, seed, a.harness, a.model ) for t, arm, seed in matrix ]
        out = dict( schema=SCHEMA, tasks_lock_content_sha256=lock["content_sha256"],
                    arms=arms, seeds=seeds, harness=a.harness, model=a.model,
                    n_runs=len( records ), dry_run=True, records=records )
        if a.results_out:
            outp = pathlib.Path( a.results_out ); outp.parent.mkdir( parents=True, exist_ok=True )
            outp.write_text( json.dumps( out, indent=2 ) )
            print( f"# wrote schema-valid empty(-status) results file: {outp} ({len(records)} stub records)",
                   file=sys.stderr )
        print( "DRY-RUN OK: tasks.lock valid, run matrix built, zero agent calls made, zero dollars spent." )
        return 0

    if a.live_one:
        if not matrix:
            raise SystemExit( "empty run matrix under the given --limit/--arms/--seeds; nothing to smoke-test" )
        t, arm, seed = matrix[0]
        print( f"# --live-one: ONE real run — instance={t['instance_id']} repo={t['repo']} arm={arm} "
               f"seed={seed} harness={a.harness} model={a.model} evaluator={a.evaluator} "
               f"work_dir={a.work_dir}", file=sys.stderr )
        gold_rows = load_gold_rows( a.work_dir )
        rec = run_one( t, arm, seed, a.harness, a.model, work_dir=a.work_dir, ripwire_bin=a.ripwire_bin,
                        timeout_s=a.timeout_seconds, evaluator=a.evaluator, gold_rows=gold_rows )
        print( json.dumps( rec, indent=2 ) )
        return 0 if rec["status"] == "ok" else 1

    # a.live
    print( "LIVE RUN requested — this spends real money against a real API/agent harness.", file=sys.stderr )
    print( "Read bench/agentloop/README.md's safety note; a live run requires explicit human approval "
           "per task run, not just this flag.", file=sys.stderr )
    gold_rows = load_gold_rows( a.work_dir )
    records = []
    outp = pathlib.Path( a.results_out ) if a.results_out else None
    if outp:
        outp.parent.mkdir( parents=True, exist_ok=True )

    # ── resume ──────────────────────────────────────────────────────────────────────────────────
    # Only records that actually completed are carried forward. A `timeout` or `error` record is NOT
    # a completed run — resuming past one would silently bake a transient failure into the results,
    # so those tuples are re-run.
    done = set()
    if a.resume:
        prior = json.loads( pathlib.Path( a.resume ).read_text() )
        if prior.get( "schema" ) != SCHEMA:
            raise SystemExit( f"{a.resume}: schema {prior.get('schema')!r} != {SCHEMA!r}; refusing to merge" )
        if prior.get( "tasks_lock_content_sha256" ) != lock["content_sha256"]:
            raise SystemExit( f"{a.resume}: was produced against a DIFFERENT tasks.lock; refusing to merge" )
        for rec in prior.get( "records", [] ):
            if rec.get( "status" ) == "ok":
                records.append( rec )
                done.add( ( rec["instance_id"], rec["arm"], rec["seed"] ) )
        print( f"# resume: {len(done)} completed runs carried forward from {a.resume}", file=sys.stderr )

    pending = [ cell for cell in matrix if ( cell[0]["instance_id"], cell[1], cell[2] ) not in done ]
    if a.resume:
        print( f"# resume: {len(pending)} of {len(matrix)} runs still to do", file=sys.stderr )

    # ── execution ───────────────────────────────────────────────────────────────────────────────
    # Sequential by default. --concurrency N runs N cells at once, each in its own checkout lane and
    # its own ephemeral agent home; the runs are subprocess-bound, so threads are the right tool.
    # Records are appended under a lock and checkpointed after each completion exactly as before, so
    # an interrupted concurrent run resumes identically to a sequential one.
    def _execute( cell, lane ):
        t, arm, seed = cell
        return run_one( t, arm, seed, a.harness, a.model, work_dir=a.work_dir,
                        ripwire_bin=a.ripwire_bin, timeout_s=a.timeout_seconds,
                        evaluator=a.evaluator, gold_rows=gold_rows, lane=lane )

    def _emit( run_index, cell, rec ):
        t, arm, _seed = cell
        records.append( rec )
        print( f"# completed {run_index}/{len(pending)}: {t['instance_id']} {arm} "
               f"status={rec['status']}", file=sys.stderr )
        if outp:
            checkpoint = dict( schema=SCHEMA, tasks_lock_content_sha256=lock["content_sha256"],
                               arms=arms, seeds=seeds, harness=a.harness, model=a.model,
                               concurrency=a.concurrency,
                               n_runs=len( matrix ), completed_runs=len( records ),
                               complete=( run_index == len( pending ) ), dry_run=False, records=records )
            outp.write_text( json.dumps( checkpoint, indent=2 ) )
            print( f"# checkpoint: {outp} ({len(records)}/{len(matrix)} records)", file=sys.stderr )

    if a.concurrency > 1:
        import concurrent.futures, itertools, threading
        print( f"# concurrency: {a.concurrency} lanes, each with its own checkout root and agent home",
               file=sys.stderr )
        lanes = itertools.cycle( f"-w{i}" for i in range( a.concurrency ) )
        guard, done_n = threading.Lock(), 0
        with concurrent.futures.ThreadPoolExecutor( max_workers=a.concurrency ) as pool:
            futures = { pool.submit( _execute, cell, lane ): cell for cell, lane in zip( pending, lanes ) }
            for fut in concurrent.futures.as_completed( futures ):
                rec = fut.result()
                with guard:                      # records + checkpoint file are shared state
                    done_n += 1
                    _emit( done_n, futures[ fut ], rec )
    else:
        for run_index, cell in enumerate( pending, 1 ):
            _emit( run_index, cell, _execute( cell, "" ) )

    n_ok = sum( 1 for r in records if r["status"] == "ok" )
    print( f"LIVE RUN done: {n_ok}/{len(records)} status=ok", file=sys.stderr )
    return 0

if __name__ == "__main__":
    sys.exit( main() )
