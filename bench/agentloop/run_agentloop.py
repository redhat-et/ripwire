#!/usr/bin/env python3
# run_agentloop.py — Phase B4 agent-in-the-loop eval RUNNER (SKELETON — no paid LLM calls yet).
#
# WHAT THIS IS. PLAN_researchImprove2026.md Phase B4 / research/2026-07/R4-eval-methodology.md: the
# stack currently measures retrieval quality (LocBench) but never the thing that actually matters —
# does giving an agent ripwire change whether it SOLVES the task. This script is the run matrix +
# record schema + orchestration skeleton for that experiment. It does NOT execute any agent or spend
# any money by itself: the actual exec step is a clearly marked NOT-IMPLEMENTED stub (see
# `run_one()` below) until a harness (Claude Code `-p` / SWE-agent / mini-swe-agent) is wired in and a
# human has explicitly approved a paid run.
#
# DESIGN (from R4-eval-methodology.md "Minimal agent-in-the-loop eval design"):
#   Arms:   baseline    = agent with grep/read/glob only (no ripwire)
#           ripwire_mcp = same agent + ripwire wired in as an MCP server
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
# EXEC STUB — candidate (A) is now WIRED (see run_one()); (B) documented but not implemented:
#   (A) `claude -p` (Claude Code print/non-interactive mode) with a tool allowlist — IMPLEMENTED below.
#       The exact invocation per arm (see ALLOWED_TOOLS_BASELINE/ALLOWED_TOOLS_RIPWIRE and run_one()):
#         claude -p "<task prompt built from problem_statement + seed suffix>" \
#           --permission-mode acceptEdits --output-format json --strict-mcp-config \
#           --allowedTools "Bash,Read,Glob,Grep,Edit,Write"                              # baseline arm
#           --allowedTools "Bash,Read,Glob,Grep,Edit,Write,mcp__ripwire__*" \
#           --mcp-config <generated ripwire-mcp.json>                                    # ripwire_mcp arm
#       The MCP config registers `ripwire --mcp` (verified against skills/ripwire-mcp/SKILL.md +
#       src/cli.h — NOT `ripwire --mcp <workspace>`; the server is stdio with no positional root, each
#       MCP verb call carries its own path/paths per request — see write_mcp_config()).
#       No Docker sandbox here: each run gets a plain git checkout (see checkout_repo(), adapted from
#       bench/locbench/run_locbench.py's checkout()) — the SWE-bench conda/dep environment is NOT
#       installed, so `resolved` scoring needs --evaluator=swebench (Docker, official harness) to be
#       meaningful; --evaluator=none lets the harness plumbing run/be smoke-tested without it.
#   (B) SWE-agent (https://github.com/SWE-agent/SWE-agent) or mini-swe-agent
#       (https://github.com/SWE-agent/mini-swe-agent): purpose-built SWE-bench harnesses with their own
#       Docker orchestration and scoring already wired to `swebench`'s evaluator. NOT implemented — (A)
#       was chosen; do not half-wire both.
#
# USAGE:
#   python3 bench/agentloop/run_agentloop.py --dry-run --tasks-lock bench/agentloop/tasks.lock \
#       --results-out /tmp/agentloop/dry.json
#   python3 bench/agentloop/run_agentloop.py --live-one --limit 1 --arms baseline --seeds 1 \
#       --work-dir /tmp/agentloop --evaluator none      # ONE real claude -p call — cheapest live proof
#   python3 bench/agentloop/run_agentloop.py --live --work-dir /tmp/agentloop --evaluator swebench ...
import argparse, hashlib, json, os, pathlib, re, subprocess, sys, tempfile, time

sys.path.insert( 0, str( pathlib.Path( __file__ ).resolve().parent ) )
import select_tasks   # reuse fetch_rows()'s HF datasets-server fetch + cache — see load_gold_rows()

SCHEMA = "ripwire-agentloop-results-v1"
ARMS   = ( "baseline", "ripwire_mcp" )
DEFAULT_SEEDS = ( 1, 2, 3 )
COST_LOW_PER_INSTANCE, COST_HIGH_PER_INSTANCE = 0.30, 1.50   # arXiv 2412.21139, per R4
DEFAULT_TIMEOUT_SECONDS = 900

# tool allowlists per arm (module docstring EXEC STUB) — ripwire_mcp adds the MCP server's tools only;
# everything else about the two arms is identical (Terminal-Bench "vary only the harness" template).
ALLOWED_TOOLS_BASELINE = "Bash,Read,Glob,Grep,Edit,Write"
ALLOWED_TOOLS_RIPWIRE  = ALLOWED_TOOLS_BASELINE + ",mcp__ripwire__*"

# ripwire binary path: same env-var convention bench/locbench/run_locbench.py uses (CTX), so a single
# RIPWIRE env var configures both harnesses; --ripwire-bin overrides it per-invocation.
RIPWIRE_BIN_DEFAULT = os.environ.get( "RIPWIRE", "ripwire" )

RECORD_FIELDS = (
    "instance_id", "repo", "base_commit", "arm", "seed", "harness", "model",
    "status", "resolved", "localization_hit", "tokens_in", "tokens_out",
    "wall_seconds", "cost_usd", "error", "started_unix", "finished_unix",
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
        error=None, started_unix=now, finished_unix=now,
    )
    rec.update( overrides )
    assert set( rec ) == set( RECORD_FIELDS ), f"record schema drift: {sorted(set(rec) ^ set(RECORD_FIELDS))}"
    return rec

def run_matrix( tasks, arms, seeds ):
    return [ ( t, arm, seed ) for t in tasks for arm in arms for seed in seeds ]

# ── shell + repo checkout (adapted from bench/locbench/run_locbench.py) ──────────────────────────────
def sh( args, cwd=None, timeout=1800 ):
    return subprocess.run( args, capture_output=True, text=True, timeout=timeout, cwd=cwd )

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

# ── MCP wiring for the ripwire_mcp arm ────────────────────────────────────────────────────────────────
def write_mcp_config( ripwire_bin, out_path ):
    """Write a --mcp-config JSON file registering ripwire as an MCP server for `claude -p`.

    Verified (not guessed) against this repo: `ripwire wrap claude` (skills/ripwire-mcp/SKILL.md) prints
    exactly `claude mcp add ripwire -- ripwire --mcp` — the server is `ripwire --mcp` over STDIO with NO
    positional workspace/root argument. src/cli.h confirms: "--mcp may run without a path ... stdio
    --mcp does not [need a root] — its clients name a path per request" (each MCP verb call carries its
    own `path`/`paths`). This corrects the task brief's assumed `ripwire --mcp <workspace>` form, which
    is not what the binary implements."""
    out_path.parent.mkdir( parents=True, exist_ok=True )
    out_path.write_text( json.dumps( { "mcpServers": { "ripwire": { "command": ripwire_bin, "args": [ "--mcp" ] } } } ) )
    return out_path

def build_prompt( gold_row, seed ):
    stmt = ( gold_row.get( "problem_statement" ) or "" ).strip()
    return (
        "You are working directly in a git checkout of this repository, at the commit the following "
        "issue was filed against. Read the issue, locate the responsible code, and make the minimal "
        "fix. Do not modify any test files. Stop once you believe the fix is complete.\n\n"
        f"ISSUE:\n{stmt}\n\n"
        # `claude -p` has no seed/temperature knob; K=3 seeded runs (README.md "Seeds") vary via this
        # deterministic prompt suffix instead. The seed is always recorded in the result record's `seed`
        # field regardless of whether this suffix measurably perturbs sampling.
        f"[run-seed:{seed}]"
    )

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
            "--max_workers", "1" ]
    proc = sh( cmd, timeout=3600 )
    if proc.returncode != 0:
        print( f"# swebench harness run failed for {task['instance_id']}: {(proc.stderr or '')[-2000:]}",
               file=sys.stderr )
        return False

    report_path = pathlib.Path( f"{run_id_prefix}.{run_id}.json" )   # TODO-verify: exact name/location
    if not report_path.exists():
        candidates = list( pathlib.Path( "." ).glob( f"*{run_id}*.json" ) )
        report_path = candidates[0] if candidates else None
    if not report_path or not report_path.exists():
        print( f"# swebench harness produced no report for {task['instance_id']}; treating as unresolved",
               file=sys.stderr )
        return False
    report = json.loads( report_path.read_text() )
    resolved_ids = set( report.get( "resolved_ids", report.get( "resolved", [] ) ) )   # TODO-verify key
    return task["instance_id"] in resolved_ids

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
def run_one( task, arm, seed, harness, model, *, work_dir=".", ripwire_bin=RIPWIRE_BIN_DEFAULT,
             timeout_s=DEFAULT_TIMEOUT_SECONDS, evaluator="none", gold_rows=None ):
    """Execute ONE (task, arm, seed) run through candidate harness (A) — `claude -p` — and return a
    filled record (RECORD_FIELDS schema). See the module docstring's EXEC STUB section for the exact
    invocation per arm and write_mcp_config()'s docstring for the verified ripwire MCP wiring.

    Steps: (a) checkout task["repo"]@task["base_commit"] into a cached, per-repo workspace, reset fresh
    for this run (checkout_repo()); (b) invoke `claude -p` in that workspace with a tool allowlist per
    arm, plus a generated --mcp-config for the ripwire_mcp arm only; (c) capture wall-clock, the
    --output-format json trailer's token/cost accounting (best-effort — see TODO-verify below), and the
    workspace's final `git diff` as the candidate patch; (d) score it via evaluate_patch()."""
    started = time.time()
    def _fail( status, error, **overrides ):
        return make_record( task, arm, seed, harness, model, status=status, error=error,
                             started_unix=started, finished_unix=time.time(), **overrides )

    if harness != "claude-code-p":
        return _fail( "error", f"unsupported harness {harness!r}; only 'claude-code-p' (candidate A) is wired" )
    if arm not in ARMS:
        return _fail( "error", f"unknown arm {arm!r}; expected one of {ARMS}" )

    gold_row = ( gold_rows or {} ).get( task["instance_id"] )
    if gold_row is None:
        return _fail( "error", f"no cached SWE-bench row for {task['instance_id']!r} — pass a --work-dir "
                                f"whose datasets cache load_gold_rows()/select_tasks.fetch_rows() can reach" )

    repos_dir = pathlib.Path( work_dir ) / "repos"
    repo_dir = checkout_repo( task["repo"], task["base_commit"], repos_dir )
    if repo_dir is None:
        return _fail( "error", f"checkout failed for {task['repo']}@{task['base_commit']}" )

    allowed_tools = ALLOWED_TOOLS_BASELINE
    cmd = [ "claude", "-p", build_prompt( gold_row, seed ),
            "--permission-mode", "acceptEdits",
            "--output-format", "json",
            "--strict-mcp-config" ]   # baseline arm: no --mcp-config passed => zero MCP servers, even if
                                      # the target repo/user config would otherwise register one ambiently
    if arm == "ripwire_mcp":
        allowed_tools = ALLOWED_TOOLS_RIPWIRE
        cfg_dir = pathlib.Path( work_dir ) / "mcp-config"
        mcp_config_path = write_mcp_config( ripwire_bin, cfg_dir / f"{task['instance_id']}-{seed}.json" )
        cmd += [ "--mcp-config", str( mcp_config_path ) ]
    cmd += [ "--allowedTools", allowed_tools ]
    if model:
        cmd += [ "--model", model ]

    t0 = time.perf_counter()
    try:
        proc = sh( cmd, cwd=repo_dir, timeout=timeout_s )
    except subprocess.TimeoutExpired:
        return _fail( "timeout", f"claude -p exceeded {timeout_s}s", wall_seconds=float( timeout_s ) )
    wall = time.perf_counter() - t0

    diff = sh( [ "git", "diff" ], cwd=repo_dir ).stdout   # candidate patch: working tree vs base_commit

    if proc.returncode != 0:
        return _fail( "error", f"claude -p exit {proc.returncode}: {(proc.stderr or '')[:2000]}",
                       wall_seconds=wall )

    # TODO-verify: field names below match the documented `claude -p --output-format json` single-result
    # schema (top-level total_cost_usd; usage.input_tokens/usage.output_tokens) as of the Claude Code CLI
    # installed when this was written (2.1.209) — re-check against a real trailer (e.g. via --live-one)
    # before trusting these numbers in an actual pilot; a schema drift here degrades to nulls, not a crash.
    tokens_in = tokens_out = cost_usd = None
    try:
        payload = json.loads( proc.stdout )
        usage = payload.get( "usage" ) or {}
        tokens_in = usage.get( "input_tokens" )
        tokens_out = usage.get( "output_tokens" )
        cost_usd = payload.get( "total_cost_usd" )
    except ValueError:
        pass   # non-JSON stdout — non-fatal, tokens/cost stay null; the patch + resolved status still stand

    resolved, localization_hit = evaluate_patch( task, gold_row, diff, evaluator )
    return make_record( task, arm, seed, harness, model, status="ok",
                         resolved=resolved, localization_hit=localization_hit,
                         tokens_in=tokens_in, tokens_out=tokens_out,
                         wall_seconds=wall, cost_usd=cost_usd,
                         started_unix=started, finished_unix=time.time() )

def main():
    ap = argparse.ArgumentParser( description="Phase B4 agent-in-the-loop eval runner (scaffolding)" )
    ap.add_argument( "--tasks-lock", default=str( pathlib.Path( __file__ ).parent / "tasks.lock" ) )
    ap.add_argument( "--arms", default=",".join( ARMS ) )
    ap.add_argument( "--seeds", default=",".join( str( s ) for s in DEFAULT_SEEDS ) )
    ap.add_argument( "--harness", default="claude-code-p",
                     help="which candidate harness runs the task; only 'claude-code-p' (candidate A, "
                          "`claude -p`) is wired — any other value fails each run's record with status=error" )
    ap.add_argument( "--model", default="claude-sonnet-5" )
    ap.add_argument( "--limit", type=int, default=0, help="cap tasks used to build the matrix (0=all); "
                     "use --limit 3 for the pilot run size named in README.md" )
    ap.add_argument( "--results-out", default="", help="where to write the results JSON" )
    ap.add_argument( "--work-dir", default="/tmp/agentloop",
                     help="scratch dir for repo checkouts, the SWE-bench gold-row cache (shared with "
                          "select_tasks.py's --work-dir), and generated --mcp-config files" )
    ap.add_argument( "--ripwire-bin", default=RIPWIRE_BIN_DEFAULT,
                     help="ripwire binary path the ripwire_mcp arm's --mcp-config points at "
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
    tasks = lock["instances"]
    if a.limit: tasks = tasks[: a.limit]
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
    records = [ run_one( t, arm, seed, a.harness, a.model, work_dir=a.work_dir, ripwire_bin=a.ripwire_bin,
                          timeout_s=a.timeout_seconds, evaluator=a.evaluator, gold_rows=gold_rows )
                for t, arm, seed in matrix ]
    out = dict( schema=SCHEMA, tasks_lock_content_sha256=lock["content_sha256"],
                arms=arms, seeds=seeds, harness=a.harness, model=a.model,
                n_runs=len( records ), dry_run=False, records=records )
    if a.results_out:
        outp = pathlib.Path( a.results_out ); outp.parent.mkdir( parents=True, exist_ok=True )
        outp.write_text( json.dumps( out, indent=2 ) )
        print( f"# wrote results: {outp} ({len(records)} records)", file=sys.stderr )
    n_ok = sum( 1 for r in records if r["status"] == "ok" )
    print( f"LIVE RUN done: {n_ok}/{len(records)} status=ok", file=sys.stderr )
    return 0

if __name__ == "__main__":
    sys.exit( main() )
