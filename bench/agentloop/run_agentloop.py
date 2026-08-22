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
#   status         — "not_implemented" | "ok" | "error" | "timeout" | "contaminated" (baseline arm
#                    invoked ripwire despite the no-ripwire contract — see baseline_contamination_note())
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
import argparse, hashlib, json, os, pathlib, platform, re, shlex, shutil, subprocess, sys, tempfile, time

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

# B2 fix (2026-08-20 outcome-harness-fixes lane): select_tasks.py / load_gold_rows() need
# princeton-nlp/SWE-bench_Lite — it has problem_statement/patch/test_patch/FAIL_TO_PASS, everything the
# GOLD row and the prompt need, and swebench's own doc dataset for that purpose. The SCORER needs a
# different, schema-incompatible dataset: swebench >=5.0 evaluates against SWE-bench/SWE-bench_Lite,
# whose rows are a strict superset adding image/eval_script/log_parser/eval_type/difficulty that
# harness/utils.py dereferences unconditionally (KeyError under the old name). The two names are pinned
# SEPARATELY and explicitly here rather than one constant reused for both purposes.
SWEBENCH_SCORE_DATASET_DEFAULT = "SWE-bench/SWE-bench_Lite"

ALLOWED_TOOLS_BASELINE = "Bash,Read,Glob,Grep,Edit,Write"

# ripwire binary path: same env-var convention bench/locbench/run_locbench.py uses (CTX), so a single
# RIPWIRE env var configures both harnesses; --ripwire-bin overrides it per-invocation.
RIPWIRE_BIN_DEFAULT = os.environ.get( "RIPWIRE", "ripwire" )

RECORD_FIELDS = (
    "instance_id", "repo", "base_commit", "arm", "seed", "harness", "model",
    "status", "resolved", "localization_hit", "tokens_in", "tokens_out",
    "wall_seconds", "cost_usd", "command_calls", "ripwire_calls", "ripwire_commands", "events_path",
    # native_read_calls — the DENOMINATOR for ripwire_calls: the agent's own read/search calls that
    # went somewhere other than ripwire. Without it "ripwire_calls=3" cannot distinguish a run that
    # used the tool for everything from one that used it once and then read twenty files.
    "native_read_calls",
    # trace_path — the run's REAL per-tool-call transcript, copied into events/ beside the trailer
    # (claude harness: the main projects/*/<session_id>.jsonl; codex/opencode already retain theirs
    # as events_path). Added after the 2026-08-22 Lane-AA mine found the archive's events/ held only
    # result trailers and every tool-call sequence had to be recovered from machine-ephemeral /tmp
    # session logs (bodyuse-memo §1). None ⇒ no main session file was identified, never a guess.
    "trace_path",
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
    # HASH-OF-LIST IS NECESSARY BUT NOT SUFFICIENT (found 2026-08-20, twice, independently). The
    # content_sha256 above proves only that the file was not hand-edited AFTER selection; it says
    # nothing about whether the SPLIT CONTRACT the lock claims to honor — "repo-disjoint from LocBench
    # train" — still yields this set. A lock generated under a stale copy of the rule hashes perfectly
    # clean over a contract-violating task list: that is exactly how a LocBench-TRAIN repo
    # (pydata/xarray) sat frozen in tasks.lock and one of its instances got run in the 2026-08-05
    # pilot. So re-derive the contract on EVERY load, through the imported rule in select_tasks (never
    # a local copy of it — the two could then drift, which is the very failure being fixed), and fail
    # closed on the CONTRACT rather than only on the bytes.
    train_locked = select_tasks.train_contaminated_repos( i["repo"] for i in lock["instances"] )
    if train_locked:
        raise SystemExit( f"{path}: {len(train_locked)} locked repo(s) re-derive to LocBench TRAIN "
                           f"under the current split rule, not heldout: {train_locked}. The "
                           f"repo-disjointness contract (sha256({select_tasks.SPLIT_SALT!r} + "
                           f"repo.lower()), byte0<128 => train) forbids them. content_sha256 matching "
                           f"only proves the file was not hand-edited; it does NOT prove the split "
                           f"contract still yields this set — refusing (fail-closed on the contract, "
                           f"not just the hash). Regenerate with select_tasks.py; do not hand-edit "
                           f"the lock." )
    return lock

def make_record( task, arm, seed, harness, model, status="not_implemented", **overrides ):
    now = time.time()
    rec = dict(
        instance_id=task["instance_id"], repo=task["repo"], base_commit=task["base_commit"],
        arm=arm, seed=seed, harness=harness, model=model,
        status=status, resolved=None, localization_hit=None,
        tokens_in=None, tokens_out=None, wall_seconds=None, cost_usd=None,
        command_calls=None, ripwire_calls=None, ripwire_commands=None, events_path=None,
        native_read_calls=None, trace_path=None,
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

# ── the local/questions task source (E1 scenario bank) ──────────────────────────────────────────────
# tasks.lock + load_gold_rows() assume SWE-bench-Lite: an instance is an ISSUE and the outcome is a
# PATCH. The E1 bank is neither — it is a question at a pinned commit whose outcome is an ANSWER, and
# 19 of its 28 rows live in private local trees that no clone URL can reach. This source bypasses
# SWE-bench selection entirely and reuses grade_answers.py's fail-closed schema loader rather than
# restating the column list, so the runner and the grader can never disagree about what a row is.
import grade_answers

TIER_BUDGET_USD = { "A": 0.60, "B": 1.50 }   # protocol §8, pre-registered per TIER, never per chain

def load_questions( path ):
    """[task] from the graded TSV. instance_id/repo/base_commit keep make_record()'s contract; the
    question, tier and caps ride along for the prompt builder and the per-run budget."""
    tasks = []
    for row in grade_answers.load_instances( path ):
        tasks.append( dict( instance_id=row[ "id" ], repo=row[ "repo" ], base_commit=row[ "pin_ref" ],
                            pin_ref=row[ "pin_ref" ], question=row[ "question" ], tier=row[ "tier" ],
                            scenario_class=row[ "scenario_class" ],
                            cap_calls=row[ "cap_calls" ], cap_wall_s=row[ "cap_wall_s" ] ) )
    return tasks

def checkout_local_pin( task, dest_root, local_corpus ):
    """Materialize a questions instance's pinned tree(s) from a LOCAL source repo, via git worktree.

    Returns the PARENT directory holding one checkout per repo — never the repo dir itself — because
    that is the shape every gt_command in the bank is written against (`ctxpack/src/x.h`), and the
    multi-root row needs two sibling checkouts in one cwd. None on any failure (fail-closed)."""
    dest = pathlib.Path( dest_root ) / task[ "instance_id" ]
    for repo, sha in grade_answers.pin_pairs( dict( repo=task[ "repo" ], pin_ref=task[ "pin_ref" ] ) ):
        source, tree = pathlib.Path( local_corpus ) / repo, dest / repo
        if tree.exists():
            continue
        if not ( source / ".git" ).exists():
            return None
        dest.mkdir( parents=True, exist_ok=True )
        if sh( [ "git", "-C", str( source ), "worktree", "add", "--detach", str( tree ), sha ] ).returncode != 0:
            return None
    return dest

# The SCOPE FENCE, assembled from the protocol's own rules rather than invented here: §1 (one
# self-contained question at one pinned commit), §10.10 (groundedness is scored on every instance,
# so the agent is told the rule it is being scored against), §2 (no admitted row is an edit
# instance), §8 (the tier cap, stated as a budget rather than discovered as a timeout). The last
# paragraph is the grader's own contract: without the sentinels there is no answer to grade.
SCOPE_FENCE = (
    "SCOPE — read this before answering:\n"
    "* Answer only about THIS repository as it exists at THIS commit. Do not reason from other "
    "versions, other branches, or your own recollection of the project.\n"
    "* Every file path and every symbol you name must exist here. A name that does not exist is "
    "scored as a hallucination and fails the whole answer, however good the rest of it is.\n"
    "* This is a READ-ONLY question. Do not modify, create or delete any file.\n"
    "* Budget: at most {calls} tool calls and {wall}s. If you run out, answer with what you have — a "
    "partial answer inside the fence is scored; an unfinished exploration is not.\n\n"
    "Finish your final message with exactly this block, nothing else inside it, one item per line:\n"
    "{open}\n<your answer>\n{close}" )

def build_question_prompt( task, seed, arm, ripwire_bin, rules_blurb="" ):
    """The question VERBATIM plus the scope fence — no 'make the minimal fix' framing.

    The question text is never rewritten, paraphrased or prefixed with a hint: protocol §5 says the
    observed chain must not define the question, and §10.8 says the text names no tool and no arm.
    Anything arm-specific lives in the suffix, exactly as it does for the SWE-bench prompt."""
    fence = SCOPE_FENCE.format( calls=task.get( "cap_calls" ) or "20",
                                wall=task.get( "cap_wall_s" ) or "300",
                                open=grade_answers.ANSWER_OPEN, close=grade_answers.ANSWER_CLOSE )
    return ( f"{task['question'].strip()}\n\n{fence}\n\n[run-seed:{seed}]"
             + arm_suffix( arm, ripwire_bin, rules_blurb ) )

def arm_suffix( arm, ripwire_bin, rules_blurb="" ):
    """The arm contract, shared by both prompt shapes so they cannot drift apart."""
    if arm == "baseline":
        return ( "\n\nRETRIEVAL ARM — BASELINE: Do not use ripwire or ctxpack. Use the agent's "
                 "ordinary repository search and file-reading tools." )
    # Both ripwire arms get the SAME contract. They differ only in what the environment puts on disk
    # (ripwire_skills adds the skills tree), so any prompt-level difference between them would
    # confound exactly the comparison the third arm exists to make.
    if arm in RIPWIRE_ARMS:
        # B3 fix (2026-08-20 outcome-harness-fixes lane): --max-tokens is not read by --for — verified
        # against the pinned binary, it warns on stderr and emits the full UNBUDGETED result (a
        # harness that discards stderr, as this one does, never sees the warning). Every ripwire-arm
        # run before this fix received an unbounded bundle, which is a prompt-length confound sitting
        # directly inside the treatment arm. --token-budget is the flag --for actually reads and
        # reports fit against in its own header (`est_tokens`): --for=... --token-budget=2000 ->
        # est_tokens="1638" on the pinned binary. See test/agentloopclaudecheck.sh's flag-probe check,
        # which shells out to the pinned binary's --help so this cannot silently drift again.
        suffix = ( "\n\nRETRIEVAL ARM — RIPWIRE CLI: Do not use a ripwire MCP server. Before "
                   "grep/find or opening implementation files, use the shell to run this exact CLI "
                   "binary at least once:\n"
                   f"  {ripwire_bin} . --for=\"<short issue description>\" --token-budget=4000\n"
                   "Use its ranked output and any additional ripwire CLI verbs that help, then "
                   "continue with ordinary editing and validation tools." )
        # The rules blurb is the SHIPPED wrap recipe's body, read straight out of `ripwire wrap`
        # rather than restated here, so the eval cannot drift from what users are actually told.
        return suffix + ( "\n\n" + rules_blurb.strip() if rules_blurb else "" )
    raise ValueError( f"unknown arm {arm!r}; expected one of {ARMS}" )

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
    return prompt + arm_suffix( arm, ripwire_bin, rules_blurb )

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

# ── native-read accounting (2026-08-10 skill-orientation audit) ──────────────────────────────────────
# ripwire_calls answers "did it reach for the tool"; it cannot answer "how often did it default
# INSTEAD", which is the question every skill/hook/primer change is actually trying to move. That needs
# the denominator: the agent's own read+search calls.
#
# Two honest limits, both of which the reported metric must carry rather than hide:
#   - Codex has NO native read tool — every read is a shell command — while opencode has both a native
#     `read`/`grep`/`glob` and a `bash`. So this counts BOTH channels, and the number is comparable
#     WITHIN a harness, never across harnesses.
#   - `claude -p` self-logs neither, so its native_read_calls stays None (same known gap that has kept
#     ripwire_calls None for that harness since this file was written). None, never 0 — a missing
#     measurement that reads as "never defaulted" would invert the conclusion.
NATIVE_READ_TOOLS = frozenset( { "read", "grep", "glob", "list", "ls", "search", "find" } )

# Shell forms of the same habit. Anchored at a command boundary (start, pipe, ;, &&, ||) so that a
# `--for="cat the file"` argument or a path containing "less" cannot count as a read.
SHELL_READ_RE = re.compile(
    r"(?:^|[|;&]|&&|\|\|)\s*(?:sudo\s+)?"
    r"(cat|head|tail|less|more|nl|sed|awk|rg|ag|ack|grep|egrep|fgrep|find|ls|tree)\b" )

def classify_native_read( tool_name=None, command=None ):
    """True when this call is the agent reading/searching source by a NON-ripwire route.

    A command that invokes ripwire is never a native read even if it also pipes through grep — the
    ripwire call is the behavior under test, and the pipe is just how its output was consumed."""
    if tool_name and tool_name.strip().lower() in NATIVE_READ_TOOLS:
        return True
    if not command:
        return False
    text = command if isinstance( command, str ) else " ".join( map( str, command ) )
    if "ripwire" in text:
        return False
    return bool( SHELL_READ_RE.search( text ) )

# ── contamination gate (2026-08-20 outcome-harness-fixes lane, arm-isolation fix) ─────────────────────
# The isolated per-harness environments (prepare_claude_environment / prepare_codex_environment /
# prepare_opencode_environment) keep the baseline arm from being PRIMED to use ripwire — no CLAUDE.md,
# no skills, no settings.json hooks. They deliberately do NOT remove "ripwire" from PATH outright:
# ephemeral_run_home() prepends the logging shim for every arm, including baseline, so that if the
# agent disobeys the prompt's "Do not use ripwire or ctxpack" instruction anyway, the attempt is
# evidence (a shim-log line / a transcript-parsed ripwire_calls count) instead of a silent, unrecorded
# success. What was still missing is the other half: NOTHING converted that evidence into a verdict.
# A baseline run that quietly used ripwire kept reporting status="ok" and paired normally in
# analyze.py — a contaminated A/B, indistinguishable from a clean one, exactly the failure class
# described in memory (opencode-round-recon's "~/.claude/CLAUDE.md baseline-contamination trap").
def baseline_contamination_note( arm, metrics ):
    """None if this run is clean; otherwise the evidence string. Only ever fires for the baseline arm —
    a ripwire call from a RIPWIRE_ARMS run is the arm working as intended, not contamination.

    Standalone and metrics-only (no subprocess, no filesystem) so it is unit-testable without running a
    harness: see test/agentloopclaudecheck.sh's contamination-gate assertions."""
    if arm != "baseline":
        return None
    calls = metrics.get( "ripwire_calls" )
    if not calls:
        return None
    commands = metrics.get( "ripwire_commands" ) or []
    return ( f"CONTAMINATED: baseline arm invoked ripwire {calls} time(s) despite the "
             f"'Do not use ripwire or ctxpack' contract — evidence: {commands[:3]!r}" )

def parse_codex_jsonl_metrics( stdout, ripwire_bin ):
    """Return token usage plus explicit command/ripwire-CLI evidence from retained Codex JSONL."""
    tokens_in, tokens_out = parse_codex_jsonl_usage( stdout )
    command_calls = ripwire_calls = native_read_calls = 0
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
        elif classify_native_read( command=command ):
            native_read_calls += 1
    return tokens_in, tokens_out, command_calls, ripwire_calls, ripwire_commands, native_read_calls

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
    command_calls = ripwire_calls = native_read_calls = 0
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
        if etype == "tool_use":
            tool = str( part.get( "tool" ) or "" )
            if tool == "bash":
                command_calls += 1
                state   = part.get( "state" ) or {}
                payload = state.get( "input" ) or {}
                command = payload.get( "command" ) if isinstance( payload, dict ) else payload
                command = " ".join( map( str, command ) ) if isinstance( command, list ) else str( command or "" )
                if ripwire_bin and ripwire_bin in command:
                    ripwire_calls += 1
                    ripwire_commands.append( command )
                elif classify_native_read( command=command ):
                    native_read_calls += 1
            # opencode's NATIVE read/grep/glob tools — the channel codex does not have at all, and the
            # one a shim on PATH can never see, since no subprocess is spawned.
            elif classify_native_read( tool_name=tool ):
                native_read_calls += 1
    return tokens_in, tokens_out, cost, model_id, command_calls, ripwire_calls, ripwire_commands, native_read_calls

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
    env, run_home, shim = ephemeral_run_home( work_dir, "opencode-home", instance_id, arm, seed,
                                              ripwire_bin, "config/opencode/skills" )
    for sub in ( "home", "config", "data", "state", "cache" ):
        ( run_home / sub ).mkdir( parents=True, exist_ok=True )

    # auth: symlink the real credential store into the isolated data dir rather than copying it, so a
    # run can authenticate without the secret being duplicated into the work dir. Same posture as the
    # codex path. If no credential exists, the run must fail loudly rather than fall back to the free
    # hosted model — see build_opencode_command().
    link_credential( pathlib.Path( os.environ.get( "XDG_DATA_HOME", pathlib.Path.home() / ".local/share" ) )
                     / "opencode", run_home / "data" / "opencode", "auth.json" )

    # NOTE on the rules-file channel: opencode WOULD read an AGENTS.md from the project root, and that
    # is how a real user installs the blurb. It is delivered through the prompt instead (build_prompt),
    # because codex runs with --ignore-rules — needed to keep the developer's own rules out of the
    # baseline — and would silently drop a rules file. One channel that every harness honours keeps
    # the arms comparable ACROSS harnesses; the cost is that this measures the blurb's content, not
    # opencode's rules-file discovery. That trade is deliberate and belongs in the write-up.

    # the skills tree is the THIRD arm's only difference from the second — ephemeral_run_home() owns it
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

def ephemeral_run_home( work_dir, kind, instance_id, arm, seed, ripwire_bin, skills_subdir ):
    """The scaffolding all three per-run environments share: an ephemeral home directory, the skills
    tree for EXACTLY ONE arm, and the logging ripwire shim first on PATH. Returns (env, run_home, shim).

    Factored out rather than copied a third time: the skills-for-one-arm rule is the whole reason the
    third arm exists (the 2026-08-04 pilot could not attribute its +80% token cost because the skills
    tree rode along on `ripwire_cli`), and a rule that matters that much should have one implementation,
    not one per harness."""
    env = os.environ.copy()
    run_home = pathlib.Path( work_dir ) / kind / arm / f"{instance_id}-{seed}"
    run_home.mkdir( parents=True, exist_ok=True )
    if arm == "ripwire_skills":
        source_skills = pathlib.Path( __file__ ).resolve().parents[2] / "skills"
        run_skills = run_home / skills_subdir
        run_skills.mkdir( parents=True, exist_ok=True )
        for skill_dir in sorted( source_skills.iterdir() ):
            if skill_dir.is_dir() and ( skill_dir / "SKILL.md" ).is_file():
                link = run_skills / skill_dir.name
                if not link.exists():
                    link.symlink_to( skill_dir, target_is_directory=True )
    shim, _log = install_ripwire_shim( run_home, ripwire_bin )
    env["PATH"] = str( pathlib.Path( shim ).parent ) + os.pathsep + env.get( "PATH", "" )
    return env, run_home, shim

def link_credential( source_dir, dest_dir, *names ):
    """Symlink a harness's credential store into its ephemeral home rather than copying it, so a run
    can authenticate without the secret being duplicated into the work dir. Missing sources are
    skipped silently — an unauthenticated harness must fail at its own login check with its own
    message, not here with a confusing one about symlinks."""
    dest = pathlib.Path( dest_dir )
    dest.mkdir( parents=True, exist_ok=True )
    for name in names:
        source, link = pathlib.Path( source_dir ) / name, dest / name
        if source.exists() and not link.exists():
            link.symlink_to( source )

def build_harness_command( harness, prompt, model, arm, tier="" ):
    """Explicit per-harness command dispatch. `tier` is only ever non-empty for a questions instance,
    and it is what turns the protocol's pre-registered per-tier ceiling into an enforced one."""
    if harness == "codex-exec":
        return build_codex_command( prompt, model )
    if harness == "opencode":
        return build_opencode_command( prompt, model )
    return build_claude_command( prompt, model, arm, max_budget_usd=TIER_BUDGET_USD.get( tier ) )

def question_timeout( task, default_s ):
    """The row's own wall cap (protocol §8), or the harness default when the row does not state one."""
    stated = str( task.get( "cap_wall_s", "" ) ).strip()
    return int( stated ) if stated.isdigit() else default_s

def prepare_environment( harness, work_dir, instance_id, arm, seed, ripwire_bin ):
    """Explicit per-harness dispatch to the right preparer — never a lookup table, never a
    fallthrough. A dict of callables hides these call sites from a name-based resolver, which reports
    the two unselected preparers as dead code; a two-branch ternary silently hands a third harness
    somebody else's environment. Both mistakes have been made in this file already."""
    if harness == "codex-exec":
        return prepare_codex_environment( work_dir, instance_id, arm, seed, ripwire_bin )
    if harness == "opencode":
        return prepare_opencode_environment( work_dir, instance_id, arm, seed, ripwire_bin )
    return prepare_claude_environment( work_dir, instance_id, arm, seed, ripwire_bin )

def build_claude_command( prompt, model, arm, allowed_tools=ALLOWED_TOOLS_BASELINE, max_budget_usd=None ):
    """Build an ISOLATED `claude -p` invocation. The three scrub flags are not optional.

    `--setting-sources ''` excludes the user/project/local settings files. On this project's own
    machine those files register the ripwire SessionStart primer and PreToolUse nudge hooks, a
    competitor MCP server, and an `env.PATH` that re-prepends /opt/homebrew/bin — which would put
    ripwire back on the baseline arm's PATH after the shim was prepended. `--strict-mcp-config` drops
    both the global and the repo-local `.mcp.json`. `--disable-slash-commands` removes the 18 installed
    skills from every arm that is not the skills arm — their DESCRIPTIONS alone sit in the system
    prompt and name ripwire verbs, so leaving them in briefs the control on the tool it controls for."""
    cmd = [ "claude", "-p", prompt,
            "--permission-mode", "acceptEdits",
            "--output-format", "json",
            "--strict-mcp-config",
            "--setting-sources", "",
            "--allowedTools", allowed_tools ]
    if arm != "ripwire_skills":
        cmd.append( "--disable-slash-commands" )
    if max_budget_usd:
        # The only directly enforceable per-run cost ceiling of the three harnesses (verified present
        # in Claude Code 2.1.209). codex/opencode have none; for those the wall timeout is the cap.
        cmd += [ "--max-budget-usd", str( max_budget_usd ) ]
    if model:
        cmd += [ "--model", model ]
    return cmd

def prepare_claude_environment( work_dir, instance_id, arm, seed, ripwire_bin ):
    """Create an isolated CLAUDE_CONFIG_DIR for one benchmark run, and return (env, run_home, shim).

    THE HOLE THIS CLOSES. codex and opencode have had isolated environments since they were wired;
    `claude-code-p` — the DEFAULT --harness — ran with `child_env = None` and inherited the operator's
    `~/.claude` whole: CLAUDE.md, the two ripwire hooks, all 18 skills, and the per-project auto-memory.
    On this machine 81 of the 84 lines of the global CLAUDE.md are a ripwire use-when protocol, so the
    baseline arm was briefed by name, verb and reflex on the tool it exists to be a control for — and
    every such run still reported status=ok. It was the largest control-arm hole on the machine and it
    was in the instrument, not the environment. test/agentloopclaudecheck.sh asserts the recipe holds.

    Credentials are symlinked, not copied, exactly as the codex path does. NOTE (unresolved, and a
    Phase-1 blocker rather than a bug here): Claude Code's `--bare` is the cleanest isolation switch
    but forces ANTHROPIC_API_KEY and never reads OAuth/keychain. This recipe deliberately keeps
    CLAUDE_CONFIG_DIR + flags instead, on the expectation that OAuth survives a redirected config dir;
    confirm that with one live --live-one run before funding a matrix."""
    env, run_home, shim = ephemeral_run_home( work_dir, "claude-home", instance_id, arm, seed,
                                              ripwire_bin, "skills" )
    link_credential( os.environ.get( "CLAUDE_CONFIG_DIR", pathlib.Path.home() / ".claude" ),
                     run_home, ".credentials.json", "credentials.json" )
    # macOS keychain auth: the OAuth token never lives in a file, so the symlink above links nothing
    # and a fresh CLAUDE_CONFIG_DIR reports "Not logged in" (measured live 2026-08-20, exit 1 in
    # 0.8s). The CLI only consults the keychain when its config carries the account markers, so copy
    # exactly those two identifier fields -- never a token -- from the operator's real config.
    # Owner-applied 2026-08-20.
    operator_config = pathlib.Path.home() / ".claude.json"
    run_config = run_home / ".claude.json"
    if operator_config.exists() and run_config.exists():
        operator = json.loads( operator_config.read_text() )
        merged = json.loads( run_config.read_text() )
        for marker in ( "oauthAccount", "userID" ):
            if marker in operator:
                merged[marker] = operator[marker]
        run_config.write_text( json.dumps( merged, indent=2 ) )
    env["CLAUDE_CONFIG_DIR"] = str( run_home )
    # Benchmark runs must never append to the operator's live substitution telemetry: that log is a
    # running two-week measurement clock, and poisoning it corrupts the very class weights this round
    # consumes. Naming a scratch destination is also what makes the hook's arm flag take effect at all.
    env["RIPWIRE_METER_FIXTURE"] = "1"
    env["RIPWIRE_HOME"] = str( run_home / "rhome" )
    env["RIPWIRE_METER_ARM"] = "control" if arm == "baseline" else "treatment"
    return env, run_home, shim

def prepare_codex_environment( work_dir, instance_id, arm, seed, ripwire_bin ):
    """Create an auth-preserving but skill-isolated CODEX_HOME for one benchmark run.

    Baseline gets no skills. The treatment gets only this checkout's ripwire skills, so globally
    installed skills cannot add hidden tools or retrieval steps to either arm."""
    env, run_home, shim = ephemeral_run_home( work_dir, "codex-home", instance_id, arm, seed,
                                              ripwire_bin, "skills" )
    link_credential( os.environ.get( "CODEX_HOME", pathlib.Path.home() / ".codex" ), run_home,
                     "auth.json" )

    # v3 CHANGE: the skills tree moved off `ripwire_cli` and onto its own arm (ephemeral_run_home()
    # owns that rule now). It used to ride along here, which is why the 2026-08-04 pilot's +80% token
    # cost could not be attributed — see ARMS.
    agents_home = pathlib.Path( work_dir ) / "agent-home" / arm / f"{instance_id}-{seed}"
    agents_home.mkdir( parents=True, exist_ok=True )
    env["CODEX_HOME"] = str( run_home )
    env["AGENTS_HOME"] = str( agents_home )
    return env, run_home, shim

# ── evaluation (--evaluator swebench|none) ─────────────────────────────────────────────────────────────
def run_swebench_harness( task, patch, run_id_prefix="ripwire-agentloop", dataset_name=SWEBENCH_SCORE_DATASET_DEFAULT ):
    """Score ONE candidate patch with the official SWE-bench evaluation harness (`swebench` PyPI
    package). Import-guarded: raises a clear, actionable SystemExit (not an ImportError traceback) if
    the package isn't installed, per --evaluator=swebench's contract. Requires Docker (the harness
    builds a per-instance image and runs FAIL_TO_PASS/PASS_TO_PASS inside it) — not checked here beyond
    letting the harness subprocess fail with its own error if Docker is unavailable.

    B2 fix (2026-08-20 outcome-harness-fixes lane): `dataset_name` used to be hardcoded to
    `princeton-nlp/SWE-bench_Lite`, which crashes under swebench>=5 (see SWEBENCH_SCORE_DATASET_DEFAULT's
    comment) — it is now a parameter, threaded from --swebench-dataset, defaulting to the working name.

    VERIFIED against swebench 5.0.2 (2026-08-20, see PLAN_HARVEST_REPORTS_2026-08-20/outcome-prereg.md
    I.2): the CLI entrypoint `python -m swebench.harness.run_evaluation` exists with exactly the flags
    below (`--help` confirmed); the predictions schema is instance_id/model_patch/model_name_or_path;
    the report filename is `<model_name_or_path>.<run_id>.json` under `--report_dir` (model_name_or_path
    is set to run_id_prefix below, which contains no "/" and so never takes reporting.py's "/"->"__"
    substitution); and the resolved-instances key is the top-level `resolved_ids`
    (harness/reporting.py:154). The glob fallback below is a hedge for a future rename, not a substitute
    for that verification.

    KNOWN UNFIXED GAP (surfaced, not fixed, here — see the --swebench-dataset help text and the
    startup warning main() prints when --evaluator=swebench is selected on a non-x86_64 host): the
    published eval images are x86_64-only (`swebench/task/checks.py:68` hardcodes
    `sweb.eval.x86_64.{instance_id}`). On an aarch64 Docker daemon (e.g. colima on Apple Silicon) this
    harness will try to build local arm64 images instead of pulling the official ones, and a locally
    rebuilt scientific-Python environment (different compiler/BLAS) is a known source of results that
    are not comparable to published numbers. `--modal True` runs the official images remotely instead."""
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

    # sys.executable, not a bare "python"/"python3": run_swebench_harness() must be invoked from the
    # same interpreter (venv) that has `swebench` installed, or the import-guard above already fired.
    # This is documented as a runbook precondition (README.md / the prereg's Part V), not auto-detected
    # here, because there is no reliable way to re-exec into "the venv with swebench" from inside a
    # process that already imported the stdlib without it.
    cmd = [ sys.executable, "-m", "swebench.harness.run_evaluation",
            "--predictions_path", str( predictions_path ),
            "--run_id", run_id,
            "--dataset_name", dataset_name,
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

def swebench_arch_warning( machine=None ):
    """B2b (surfaced, not fixed): None on x86_64/amd64; else the startup warning naming --modal as the
    alternative backend. A standalone, no-argument-default function so main() can print it once at
    startup (before spending any time on checkouts) and a test can call it with a forced platform
    string without needing to run on aarch64 hardware to exercise the aarch64 branch."""
    machine = ( machine if machine is not None else platform.machine() ).lower()
    if machine in ( "x86_64", "amd64" ):
        return None
    return (
        f"# WARNING: this host's Docker daemon architecture is {machine!r}, not x86_64. The published "
        f"SWE-bench eval images are x86_64-only (swebench/task/checks.py hardcodes "
        f"sweb.eval.x86_64.{{instance_id}}); on this machine the harness will build LOCAL arm64 images "
        f"instead of pulling the official ones, and a locally rebuilt scientific-Python environment "
        f"(different compiler/BLAS) is a known source of results that are not comparable to published "
        f"numbers. Pass `python -m swebench.harness.run_evaluation --modal True` (or use "
        f"run_swebench_harness()'s --evaluator=swebench on an x86_64 host / cloud box) to score against "
        f"the official images instead. Both arms of a paired comparison must be scored on the SAME "
        f"backend, always." )

def evaluate_patch( task, gold_row, patch, evaluator, swebench_dataset=SWEBENCH_SCORE_DATASET_DEFAULT ):
    """Return (resolved: bool|None, localization_hit: bool|None) for one candidate patch.

    evaluator='none'     -> resolved=None always (no Docker / swebench harness invoked, so runs can
                             proceed before that's set up); localization_hit is still computed locally
                             (cheap, no execution) whenever a gold patch is available.
    evaluator='swebench' -> resolved is computed via the official `swebench` harness (see
                             run_swebench_harness()); an empty candidate patch short-circuits to
                             resolved=False without spending a Docker run (it cannot pass any test)."""
    # A questions instance (the E1 bank) has no gold patch and no patch outcome at all: its answer is
    # scored by grade_answers.py from the transcript. Both fields stay None — never a fabricated False,
    # which would read as "the agent failed" for a task that was never a patch task.
    if gold_row is None:
        return None, None
    cand_files = set( patch_files( patch ) ) if patch.strip() else set()
    gold_files = set( patch_files( gold_row.get( "patch", "" ) ) )
    localization_hit = bool( cand_files & gold_files ) if gold_files else None

    if evaluator == "none":
        return None, localization_hit
    if evaluator == "swebench":
        if not patch.strip():
            return False, localization_hit
        return run_swebench_harness( task, patch, dataset_name=swebench_dataset ), localization_hit
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
      ripwire_calls, ripwire_commands, native_read_calls ) = parse_codex_jsonl_metrics( stdout, ripwire_bin )
    if shim_log is not None:
        shim_calls, shim_commands = read_shim_log( shim_log )
        if shim_calls != ripwire_calls:
            ripwire_commands = shim_commands
        ripwire_calls = shim_calls
    return dict( tokens_in=tokens_in, tokens_out=tokens_out, command_calls=command_calls,
                 ripwire_calls=ripwire_calls, ripwire_commands=ripwire_commands,
                 native_read_calls=native_read_calls, events_path=str( events_file ) )

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
      command_calls, ripwire_calls, ripwire_commands,
      native_read_calls ) = parse_opencode_ndjson_metrics( stdout, ripwire_bin )

    if shim_log is not None:
        shim_calls, shim_commands = read_shim_log( shim_log )
        if shim_calls != ripwire_calls:
            ripwire_commands = shim_commands
        ripwire_calls = shim_calls
    return dict( tokens_in=tokens_in, tokens_out=tokens_out, cost_usd=cost,
                 command_calls=command_calls, ripwire_calls=ripwire_calls,
                 ripwire_commands=ripwire_commands, native_read_calls=native_read_calls,
                 events_path=str( events_file ), resolved_model=model_id )

def _claude_metrics( stdout, shim_log=None, retain=None, run_home=None ):
    """Parse the `claude -p --output-format json` single-result trailer into record fields.

    `retain` is the path the raw trailer is written to and recorded as events_path. codex and opencode
    have always retained their transcripts; claude did not, which meant the run's terminal ANSWER —
    the only thing grade_answers.py can score — was parsed for tokens and then thrown away.

    `run_home` is the run's ephemeral CLAUDE_CONFIG_DIR: the REAL per-tool-call transcript lives
    under it (projects/*/<session_id>.jsonl), and _retain_claude_trace() copies it into events/
    beside the trailer. Before that copy existed, the trailer was the only thing events/ kept, and
    the 2026-08-22 Lane-AA transcript mine (bodyuse-memo §1) had to recover every tool-call sequence
    from /private/tmp session logs that only still existed because the machine had not rebooted —
    "the archive named events does not contain events". The trace copy (and the counts derived from
    it) is what makes a rerun of that mine possible from the archive alone.

    TODO-verify: field names match the documented schema (top-level total_cost_usd;
    usage.input_tokens/usage.output_tokens) as of the Claude Code CLI installed when this was written
    (2.1.209) — re-check against a real trailer (e.g. via --live-one) before trusting these numbers in
    an actual pilot; schema drift degrades accounting to nulls (make_record defaults), not a crash."""
    out = {}
    if retain is not None:
        pathlib.Path( retain ).parent.mkdir( parents=True, exist_ok=True )
        pathlib.Path( retain ).write_text( stdout or "" )
        out[ "events_path" ] = str( retain )
    # `claude -p` does not log individual shell commands, so before the shim there was no
    # ripwire-invocation evidence for this harness at all — every claude run recorded
    # ripwire_calls=None. The shim closes that gap without depending on the agent's transcript.
    # Read OUTSIDE the trailer-parse guard: the shim log is a file of our own making, independent of
    # whether the trailer parsed (a timeout hands over partial stdout but the shim log is intact).
    if shim_log is not None:
        calls, commands = read_shim_log( shim_log )
        out.update( ripwire_calls=calls, ripwire_commands=commands )
    payload = None
    try:
        payload = json.loads( stdout ) if stdout else None
    except ValueError:
        payload = None
    if isinstance( payload, dict ):
        usage = payload.get( "usage" ) or {}
        out.update( tokens_in=usage.get( "input_tokens" ), tokens_out=usage.get( "output_tokens" ),
                    cost_usd=payload.get( "total_cost_usd" ) )
    # Trace persistence runs even when the trailer did not parse (timeout / crash): those are exactly
    # the runs whose evidence is otherwise lost, and the session files exist regardless of how the
    # child exited. session_id (when the trailer has one) names the MAIN session among the sidechains.
    if run_home is not None and retain is not None:
        session_id = payload.get( "session_id" ) if isinstance( payload, dict ) else None
        out.update( _retain_claude_trace( run_home, retain, session_id ) )
    return out

def _retain_claude_trace( run_home, retain, session_id ):
    """Copy the run's Claude Code session transcripts out of the ephemeral run home into events/.

    Copies EVERY projects/**/*.jsonl (the main session plus any Task-tool sidechains) into a
    `<trailer-stem>-trace/` directory beside the retained trailer, so the per-tool-call record
    survives the ephemeral CLAUDE_CONFIG_DIR (which lives under a possibly-/tmp work_dir and dies
    with it). When `session_id` identifies the main session file, the record additionally gets:
      trace_path        — the copied main transcript (the file a mining pass reads),
      command_calls     — Bash tool_use blocks in it (the codex parser's command_execution analogue),
      native_read_calls — Read/Grep/Glob-family tool_use blocks plus Bash commands that
                          classify_native_read() recognizes, same rule as the codex/opencode parsers.
    Without a session_id the files are still copied but the three fields stay None — an honest null,
    never a count over a file this function only guessed was the right one."""
    out = {}
    projects = pathlib.Path( run_home ) / "projects"
    if not projects.is_dir():
        return out
    retain_str = str( retain )
    stem = retain_str[: -len( ".json" )] if retain_str.endswith( ".json" ) else retain_str
    trace_dir = pathlib.Path( stem + "-trace" )
    main_copy = None
    for source in sorted( projects.rglob( "*.jsonl" ) ):
        trace_dir.mkdir( parents=True, exist_ok=True )
        dest = trace_dir / source.name
        shutil.copyfile( source, dest )
        if session_id and source.stem == session_id:
            main_copy = dest
    if main_copy is None:
        return out
    command_calls = native_read_calls = 0
    with open( main_copy, encoding="utf-8" ) as handle:
        for line in handle:
            try:
                msg = json.loads( line )
            except ValueError:
                continue
            content = ( msg.get( "message" ) or {} ).get( "content" )
            if not isinstance( content, list ):
                continue
            for block in content:
                if not isinstance( block, dict ) or block.get( "type" ) != "tool_use":
                    continue
                name = block.get( "name" ) or ""
                if name == "Bash":
                    command_calls += 1
                    command = ( block.get( "input" ) or {} ).get( "command" )
                    if classify_native_read( command=command ):
                        native_read_calls += 1
                elif classify_native_read( tool_name=name ):
                    native_read_calls += 1
    out.update( trace_path=str( main_copy ), command_calls=command_calls,
                native_read_calls=native_read_calls )
    return out

def _harness_metrics( harness, stdout, work_dir, task, arm, seed, ripwire_bin, shim_log, run_home=None ):
    """Route stdout to the right parser. Explicit per-harness dispatch, never a binary fallthrough:
    the two-branch ternaries this replaces silently gave any third harness claude's parser."""
    if harness == "codex-exec":
        return _codex_metrics( stdout, work_dir, task, arm, seed, ripwire_bin, shim_log )
    if harness == "opencode":
        return _opencode_metrics( stdout, work_dir, task, arm, seed, ripwire_bin, shim_log )
    retain = pathlib.Path( work_dir ) / "events" / f"{task['instance_id']}-{arm}-{seed}.json"
    return _claude_metrics( stdout if isinstance( stdout, str ) else ( stdout or b"" ).decode( "utf-8", "replace" ),
                            shim_log, retain, run_home )

def _child_failure_detail( proc ):
    """The best 2000 chars of evidence for a nonzero-exit harness child.

    `--output-format json` puts the CLI's own error report on STDOUT; a record that kept only stderr
    could say `exit 1: ` and nothing else (measured live 2026-08-20, claude-code-p). Fall back to
    stdout only when stderr is genuinely empty — a real stderr message still wins outright."""
    detail = ( proc.stderr or "" )[:2000]
    if not detail.strip():
        detail = "(stderr empty) stdout: " + ( proc.stdout or "" )[:2000]
    return detail

def run_one( task, arm, seed, harness, model, *, work_dir=".", ripwire_bin=RIPWIRE_BIN_DEFAULT,
             timeout_s=DEFAULT_TIMEOUT_SECONDS, evaluator="none", gold_rows=None, lane="",
             local_corpus="", swebench_dataset=SWEBENCH_SCORE_DATASET_DEFAULT ):
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

    # A QUESTIONS row (the E1 bank) carries its own prompt and is scored by grade_answers.py from the
    # retained transcript, so it needs neither a SWE-bench gold row nor patch evaluation.
    is_question = bool( task.get( "question" ) )
    gold_row = None
    if not is_question:
        gold_row = ( gold_rows or {} ).get( task["instance_id"] )
        if gold_row is None:
            return _fail( "error", f"no cached SWE-bench row for {task['instance_id']!r} — pass a --work-dir "
                                    f"whose datasets cache load_gold_rows()/select_tasks.fetch_rows() can reach" )
    if is_question:
        timeout_s = question_timeout( task, timeout_s )

    # Per-worker checkout root. checkout_repo() keeps ONE clone per repo and hard-resets it for every
    # run, so two concurrent runs touching the same repo would clobber each other's working tree
    # mid-agent. Sharding the root by worker is what makes --concurrency safe; the default lane
    # ("") is byte-identical to the old single-threaded path.
    repos_dir = pathlib.Path( work_dir ) / ( f"repos{lane}" if lane else "repos" )
    repo_dir = ( checkout_local_pin( task, repos_dir, local_corpus ) if is_question and local_corpus
                 else checkout_repo( task["repo"], task["base_commit"], repos_dir ) )
    if repo_dir is None:
        return _fail( "error", f"checkout failed for {task['repo']}@{task['base_commit']}" )

    # The environment is prepared BEFORE the prompt, because it installs the ripwire shim and the
    # prompt must name that shim rather than the bare binary — otherwise an agent invoking ripwire by
    # absolute path walks straight past the counter.
    child_env, run_home, shim_bin = prepare_environment( harness, work_dir, task["instance_id"],
                                                         arm, seed, ripwire_bin )
    shim_log = pathlib.Path( run_home ) / "shim" / "ripwire-calls.log"

    rules_blurb = ""
    if arm in RIPWIRE_ARMS:
        wrap_agent = { "opencode": "opencode", "codex-exec": "codex" }.get( harness, "claude" )
        wrapped = subprocess.run( [ str( ripwire_bin ), "wrap", wrap_agent, "--force" ],
                                  capture_output=True, text=True )
        rules_blurb = extract_wrap_blurb( wrapped.stdout )

    prompt = ( build_question_prompt( task, seed, arm, shim_bin, rules_blurb ) if is_question
               else build_prompt( gold_row, seed, arm, shim_bin, rules_blurb ) )
    cmd = build_harness_command( harness, prompt, model, arm,
                                 task.get( "tier", "" ).strip() if is_question else "" )

    t0 = time.perf_counter()
    try:
        proc = sh( cmd, cwd=repo_dir, timeout=timeout_s, env=child_env )
    except subprocess.TimeoutExpired as exc:
        diff = sh( [ "git", "diff" ], cwd=repo_dir ).stdout
        resolved, localization_hit = evaluate_patch( task, gold_row, diff, evaluator, swebench_dataset )
        metrics = _harness_metrics( harness, exc.stdout, work_dir, task, arm, seed, ripwire_bin, shim_log, run_home )
        return _fail( "timeout", f"{harness} exceeded {timeout_s}s", resolved=resolved,
                      localization_hit=localization_hit, wall_seconds=float( timeout_s ),
                      harness_version=agent_version( harness ), **metrics )
    wall = time.perf_counter() - t0

    diff = sh( [ "git", "diff" ], cwd=repo_dir ).stdout   # candidate patch: working tree vs base_commit

    if proc.returncode != 0:
        return _fail( "error", f"{harness} exit {proc.returncode}: {_child_failure_detail( proc )}",
                       wall_seconds=wall )

    metrics = _harness_metrics( harness, proc.stdout, work_dir, task, arm, seed, ripwire_bin, shim_log, run_home )

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

    # Persist the candidate patch unconditionally: with --evaluator none the diff used to be computed
    # and then dropped, which made deferred scoring impossible — an agent run is the expensive half,
    # so its product must survive the process regardless of which evaluator runs tonight.
    patch_dir = pathlib.Path( work_dir ) / "patches"
    patch_dir.mkdir( parents=True, exist_ok=True )
    ( patch_dir / f"{task['instance_id']}-{arm}-{seed}.patch" ).write_text( diff or "" )

    resolved, localization_hit = evaluate_patch( task, gold_row, diff, evaluator, swebench_dataset )
    # The contamination gate: a baseline run that actually reached for ripwire is not a usable control
    # datapoint. status != "ok" is enough on its own to keep it out of analyze.py's paired set
    # (pair_by_task_seed() only pairs status=="ok" on both arms) — no analyze.py change needed for
    # exclusion, only for counting it (see analyze.py's n_contaminated_baseline).
    contamination = baseline_contamination_note( arm, metrics )
    return make_record( task, arm, seed, harness, model,
                         status="contaminated" if contamination else "ok",
                         resolved=resolved, localization_hit=localization_hit, wall_seconds=wall,
                         started_unix=started, finished_unix=time.time(),
                         harness_version=agent_version( harness ), error=contamination, **metrics )

def main():
    ap = argparse.ArgumentParser( description="Phase B4 agent-in-the-loop eval runner (scaffolding)" )
    ap.add_argument( "--tasks-lock", default=str( pathlib.Path( __file__ ).parent / "tasks.lock" ) )
    ap.add_argument( "--questions", default="", metavar="TSV",
                     help="grade a QUESTIONS bank (the E1 graded TSV) instead of SWE-bench: bypasses "
                          "tasks.lock and the HuggingFace gold-row fetch entirely. Answers are scored "
                          "afterwards by bench/agentloop/grade_answers.py, not by this script." )
    ap.add_argument( "--local-corpus", default="", metavar="DIR",
                     help="parent dir of the local source repos a --questions bank pins into; each "
                          "instance gets `git worktree add --detach` checkouts at its pinned sha. "
                          "Required for bank rows whose repo is a private local tree." )
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
    ap.add_argument( "--swebench-dataset", default=SWEBENCH_SCORE_DATASET_DEFAULT,
                     help="dataset name passed to `swebench.harness.run_evaluation`'s --dataset_name "
                          f"(default: {SWEBENCH_SCORE_DATASET_DEFAULT!r}, required by swebench>=5's "
                          "schema — image/eval_script/log_parser fields the harness dereferences "
                          "unconditionally; the older princeton-nlp/SWE-bench_Lite name still works for "
                          "gold rows via select_tasks.py/load_gold_rows() but raises KeyError here)" )
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

    # B2b (surfaced, not fixed — see swebench_arch_warning()'s docstring): a real scoring backend
    # mismatch is expensive to discover after a live matrix has already run, so it prints once here,
    # at parse time, before any checkout or agent call — not buried inside run_swebench_harness()
    # where it would only fire per-instance after real work was already done.
    if a.evaluator == "swebench":
        warning = swebench_arch_warning()
        if warning:
            print( warning, file=sys.stderr )

    if a.questions:
        lock = dict( content_sha256=f"questions:{pathlib.Path( a.questions ).name}",
                     selected_count=0, selected_repo_count=0 )
        all_tasks = load_questions( a.questions )
        lock.update( selected_count=len( all_tasks ),
                     selected_repo_count=len( { t["repo"] for t in all_tasks } ) )
    else:
        lock = load_tasks_lock( a.tasks_lock )
        all_tasks = lock["instances"]
    tasks = limit_tasks_repo_round_robin( all_tasks, a.limit )
    arms = [ x.strip() for x in a.arms.split( "," ) if x.strip() ]
    seeds = [ int( x ) for x in a.seeds.split( "," ) if x.strip() ]
    for arm in arms:
        if arm not in ARMS: raise SystemExit( f"unknown arm {arm!r}; expected one of {ARMS}" )
    matrix = run_matrix( tasks, arms, seeds )

    print( f"# task source verified: content_sha256={lock['content_sha256'][:16]}... "
           f"({lock['selected_count']} instances, {lock['selected_repo_count']} repos)", file=sys.stderr )
    print( f"# run matrix: {len(tasks)} tasks x {len(arms)} arms x {len(seeds)} seeds = {len(matrix)} runs",
           file=sys.stderr )
    lo, hi = len( tasks ) * len( arms ) * len( seeds ) * COST_LOW_PER_INSTANCE, \
             len( tasks ) * len( arms ) * len( seeds ) * COST_HIGH_PER_INSTANCE
    print( f"# projected cost at ${COST_LOW_PER_INSTANCE:.2f}-${COST_HIGH_PER_INSTANCE:.2f}/instance "
           f"(arXiv 2412.21139): ${lo:.0f}-${hi:.0f}", file=sys.stderr )
    # THIS PROJECTION UNDER-REPORTS, and README.md's SAFETY note makes it the human approval gate.
    # It is a per-instance literature envelope; this harness's own pilot (results/pilot-6run.json)
    # recorded a single run at 1,249,026 in + 13,779 out = $3.96 at $3/$15 per Mtok — 2.6x the TOP of
    # the envelope, on one run. A gate that under-reports the number a human approves is worse than no
    # gate, so the disclosure travels with the number rather than living only in a memo.
    print( "# WARNING the line above is a LITERATURE envelope, not this harness's measured cost. The "
           "recorded pilot exceeded its per-instance top by 2.6x on a single run; the fitted token "
           "model puts the pre-registered E1 design at 2-5x this range. Do not approve a spend on it "
           "alone — price the design from a smoke matrix first.", file=sys.stderr )
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
        gold_rows = {} if a.questions else load_gold_rows( a.work_dir )
        rec = run_one( t, arm, seed, a.harness, a.model, work_dir=a.work_dir, ripwire_bin=a.ripwire_bin,
                        timeout_s=a.timeout_seconds, evaluator=a.evaluator, gold_rows=gold_rows,
                        local_corpus=a.local_corpus, swebench_dataset=a.swebench_dataset )
        print( json.dumps( rec, indent=2 ) )
        return 0 if rec["status"] == "ok" else 1

    # a.live
    print( "LIVE RUN requested — this spends real money against a real API/agent harness.", file=sys.stderr )
    print( "Read bench/agentloop/README.md's safety note; a live run requires explicit human approval "
           "per task run, not just this flag.", file=sys.stderr )
    gold_rows = {} if a.questions else load_gold_rows( a.work_dir )
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
                        evaluator=a.evaluator, gold_rows=gold_rows, lane=lane,
                        local_corpus=a.local_corpus, swebench_dataset=a.swebench_dataset )

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
