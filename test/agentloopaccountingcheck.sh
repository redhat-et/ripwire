#!/usr/bin/env bash
# agentloopaccountingcheck.sh — cache-split cost accounting, wall clock, tool-call counts and pass^k in the
# agent-loop eval (bench/agentloop/run_agentloop.py, bench/agentloop/analyze.py,
# bench/agentloop/cost_accounting.py).
#
# WHY THIS GATE EXISTS. A token total cannot price an agent run once the provider caches the prefix.
# "Context Has a Price ... under Prefix Caching" (arXiv 2611.22238) measured retrieved code that cut
# read/search commands by 18-34% and RAISED cost by 33-42% at a one-tenth cache price. tokens_in/tokens_out
# hide that: a cache read and an uncached input token are one number. So every run's tokens are split four
# ways (uncached input, cache write, cache read, output) from the usage fields of the run's own transcript,
# beside wall clock, tool-call and model-call counts. Separately, a single-trial rate cannot tell a task the
# agent always solves from one it solves by luck; pass^k (all k trials succeed, Anthropic's consistency
# metric) is reported beside it wherever a task has k >= 2 runs.
#
# FIXTURES (bench/agentloop/fixtures/cost/): one transcript per harness with HAND-SET usage. The expected
# split below was worked out by hand from those numbers, not by running the code:
#   claude   trailer usage: input 1234, cache_creation 20000, cache_read 150000, output 4321; num_turns 7;
#            the session transcript holds 5 tool_use blocks (Bash, Read, Grep, Bash, Edit) and one junk line.
#   codex    turn.completed usage: input 50000 of which cached 42000, output 3000 -> uncached 8000.
#            Codex reports no cache-write count, so that cell is None ("not reported"), never 0. Four tool
#            items (3 command_execution + 1 file_change); reasoning and agent_message items are not tools.
#   opencode two step_finish parts, PER-STEP usage (opencode 1.x adds part.cost into the message total
#            step by step): input 900+100, output 300+200 plus reasoning 100+0, cache read 10000+15000,
#            write 5000+0; 3 tool_use events; 2 model steps.
#
# ARMS
#   (C1) RECORD   run_agentloop's per-harness metric functions fill the split, tool_calls and model_calls.
#   (C2) REDERIVE analyze.py, given records that carry ONLY events_path, reproduces the same split exactly.
#   (C3) ROLLUP   per-arm and per-task rows: hand sums of the split beside the existing tokens_in/tokens_out/
#                 cost_usd totals, wall clock and tool calls.
#   (C4) NO SILENT SPLIT  a run with tokens_in but no transcript is counted as split-unmeasured and printed
#                 n/a; every printed line that shows tokens_in also shows cache_read.
#   (C5) HEADLINE every key the base analyze() returned on its self-test fixture keeps its value (pinned below
#                 from origin/main 5f4b50415), and --self-test still passes.
#   (P1) PASS^K   four tasks with known outcomes: [1,1,1] [1,0,1] [0,0] [1]. pass@1 = (1 + 2/3 + 0 + 1)/4;
#                 pass^2 = (1 + 1/3 + 0)/3 over 3 tasks; pass^3 = (1 + 0)/2 over 2 tasks; the n=1 task is in
#                 pass@1 only. Unbiased estimator C(c,k)/C(n,k).
#   (P2) PRINTED  the report prints pass^k beside pass@1, with each k's task count.
#
# Usage: bash test/agentloopaccountingcheck.sh [ripwire-binary]   (accepted for regression.sh's uniform call
# shape and unused: the subject is python over fixture transcripts.)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
command -v python3 >/dev/null 2>&1 || { echo "agentloopaccountingcheck: python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

PYTHONDONTWRITEBYTECODE=1 python3 -I - "$ROOT" "$TMP" <<'EOF'
import contextlib, io, json, pathlib, shutil, subprocess, sys
root, tmp = sys.argv[1], pathlib.Path( sys.argv[2] )
AL = pathlib.Path( root ) / "bench" / "agentloop"
FX = AL / "fixtures" / "cost"
sys.path.insert( 0, str( AL ) )
import analyze, run_agentloop

fails = 0
def verdict( name, problems ):
    global fails
    if problems:
        fails += 1
        print( f"  FAIL  {name}" )
        for p in problems: print( f"          - {p}" )
    else:
        print( f"  PASS  {name}" )

SPLIT = ( "split_uncached_in", "split_cache_write", "split_cache_read", "split_output" )
EXPECT = {
    "claude-code-p": dict( split_uncached_in=1234, split_cache_write=20000, split_cache_read=150000,
                           split_output=4321, tool_calls=5, model_calls=7 ),
    "codex-exec":    dict( split_uncached_in=8000, split_cache_write=None, split_cache_read=42000,
                           split_output=3000, tool_calls=4, model_calls=None ),
    "opencode":      dict( split_uncached_in=1000, split_cache_write=5000, split_cache_read=25000,
                           split_output=600, tool_calls=3, model_calls=2 ),
}
def diff( got, want, label ):
    return [ f"{label}: {k} = {got.get( k, '<missing>' )!r}, expected {v!r}" for k, v in want.items()
             if k not in got or got[k] != v or type( got[k] ) is not type( v ) ]

# ── (C1) the runner's metric functions fill the record ────────────────────────────────────────────────
probs = []
task = dict( instance_id="fx-1" )
try:
    work = tmp / "work"; work.mkdir()
    home = tmp / "home"; ( home / "projects" / "slug" ).mkdir( parents=True )
    shutil.copy( FX / "claude-trailer.transcript.jsonl", home / "projects" / "slug" / "fixture-session-1.jsonl" )
    got = run_agentloop._claude_metrics( ( FX / "claude-trailer.json" ).read_text(), None,
                                         work / "events" / "fx-1-baseline-1.json", run_home=home, ripwire_bin="ripwire" )
    probs += diff( got, EXPECT["claude-code-p"], "claude" )
    got = run_agentloop._codex_metrics( ( FX / "codex.jsonl" ).read_text(), work, task, "baseline", 1, "ripwire" )
    probs += diff( got, EXPECT["codex-exec"], "codex" )
    got = run_agentloop._opencode_metrics( ( FX / "opencode.ndjson" ).read_text(), work, task, "baseline", 2, "ripwire" )
    probs += diff( got, EXPECT["opencode"], "opencode" )
    missing = [ f for f in SPLIT + ( "tool_calls", "model_calls" ) if f not in run_agentloop.RECORD_FIELDS ]
    if missing: probs.append( f"RECORD_FIELDS lacks {missing}" )
except Exception as exc:
    probs.append( f"{type( exc ).__name__}: {exc}" )
verdict( "(C1) RECORD: per-harness metrics carry the four-way split, tool_calls and model_calls", probs )

# ── records as an OLD results file would carry them: events_path, no split fields ─────────────────────
def rec( inst, arm, seed, harness, events, **kw ):
    r = dict( instance_id=inst, repo="fx/repo", base_commit="deadbeef", arm=arm, seed=seed, harness=harness,
              model="m", status="ok", resolved=None, localization_hit=None, tokens_in=None, tokens_out=None,
              wall_seconds=None, cost_usd=None, command_calls=None, ripwire_calls=None, ripwire_commands=None,
              native_read_calls=None, events_path=str( events ) if events else None, error=None,
              started_unix=0, finished_unix=0, resolved_model=None, harness_version=None )
    r.update( kw ); return r
EV = { "claude-code-p": FX / "claude-trailer.json", "codex-exec": FX / "codex.jsonl", "opencode": FX / "opencode.ndjson" }

# ── (C2) analyze re-derives the split from the transcript alone ──────────────────────────────────────
probs = []
try:
    for h, path in EV.items():
        got = analyze.run_accounting( rec( "t", "baseline", 1, h, path ) )
        probs += diff( got, EXPECT[h], f"analyze[{h}]" )
except Exception as exc:
    probs.append( f"{type( exc ).__name__}: {exc}" )
verdict( "(C2) REDERIVE: analyze.py reproduces the hand-set split exactly from each transcript", probs )

# ── (C3) per-arm and per-task rollups ────────────────────────────────────────────────────────────────
records = [
    rec( "t1", "baseline",    1, "claude-code-p", EV["claude-code-p"], tokens_in=1234, tokens_out=4321, cost_usd=0.4321, wall_seconds=60.0 ),
    rec( "t1", "baseline",    2, "claude-code-p", EV["claude-code-p"], tokens_in=1234, tokens_out=4321, cost_usd=0.4321, wall_seconds=90.0 ),
    rec( "t1", "ripwire_cli", 1, "opencode",      EV["opencode"],      tokens_in=100,  tokens_out=200,  cost_usd=0.17,   wall_seconds=30.0 ),
    # a run with existing totals but NO transcript: its split is unmeasured and must say so
    rec( "t2", "ripwire_cli", 1, "codex-exec",    None,                tokens_in=777,  tokens_out=88,   cost_usd=None,   wall_seconds=12.5 ),
]
probs = []
out = None
try:
    out = analyze.analyze( records, n_boot=50 )
    arms = out["cost_by_arm"]
    b, r = arms["baseline"], arms["ripwire_cli"]
    want = { ( "baseline", "runs" ): 2, ( "ripwire_cli", "runs" ): 2,
             ( "baseline", "tokens_in" ): { "sum": 2468, "n": 2 }, ( "baseline", "tokens_out" ): { "sum": 8642, "n": 2 },
             ( "baseline", "split_uncached_in" ): { "sum": 2468, "n": 2 },
             ( "baseline", "split_cache_write" ): { "sum": 40000, "n": 2 },
             ( "baseline", "split_cache_read" ): { "sum": 300000, "n": 2 },
             ( "baseline", "split_output" ): { "sum": 8642, "n": 2 },
             ( "baseline", "wall_seconds" ): { "sum": 150.0, "n": 2 },
             ( "baseline", "tool_calls" ): { "sum": 10, "n": 2 },
             ( "baseline", "model_calls" ): { "sum": 14, "n": 2 },
             ( "ripwire_cli", "tokens_in" ): { "sum": 877, "n": 2 },
             ( "ripwire_cli", "split_cache_read" ): { "sum": 25000, "n": 1 },
             ( "ripwire_cli", "cost_usd" ): { "sum": 0.17, "n": 1 },
             ( "ripwire_cli", "wall_seconds" ): { "sum": 42.5, "n": 2 },
             ( "ripwire_cli", "n_split_unmeasured" ): 1, ( "baseline", "n_split_unmeasured" ): 0 }
    for ( arm, k ), v in want.items():
        g = arms[arm].get( k )
        if isinstance( v, dict ) and isinstance( g, dict ) and isinstance( v["sum"], float ):
            ok = g.get( "n" ) == v["n"] and g.get( "sum" ) is not None and abs( g["sum"] - v["sum"] ) < 1e-9
        else:
            ok = g == v
        if not ok: probs.append( f"cost_by_arm[{arm}][{k}] = {g!r}, expected {v!r}" )
    rows = { ( t["instance_id"], t["arm"] ): t for t in out["cost_by_task"] }
    t1b = rows.get( ( "t1", "baseline" ) )
    if not t1b or t1b["runs"] != 2 or t1b["wall_seconds"] != { "sum": 150.0, "n": 2 } or t1b["tool_calls"] != { "sum": 10, "n": 2 }:
        probs.append( f"cost_by_task[t1, baseline] wrong: {t1b!r}" )
    if len( rows ) != 3: probs.append( f"expected 3 (task, arm) rows, got {sorted( rows )}" )
except Exception as exc:
    probs.append( f"{type( exc ).__name__}: {exc}" )
verdict( "(C3) ROLLUP: per-arm and per-task split, wall clock and tool calls match hand sums", probs )

# ── (C4) no cost line without its cache split ─────────────────────────────────────────────────────────
probs = []
try:
    buf = io.StringIO()
    with contextlib.redirect_stdout( buf ):
        analyze.print_report( out )
    text = buf.getvalue()
    lines = [ l for l in text.splitlines() if "tokens_in=" in l ]
    if not lines: probs.append( "the report prints no tokens_in= line at all" )
    for l in lines:
        if "cache_read=" not in l or "cache_write=" not in l or "uncached_in=" not in l:
            probs.append( f"a cost line without its cache split: {l.strip()}" )
    rw = [ l for l in lines if "ripwire_cli" in l and "runs=2" in l ]
    if not rw or "1 of 2" not in rw[0]:
        probs.append( f"the ripwire_cli arm line must disclose its split as measured on 1 of 2 runs: {rw!r}" )
    if not any( "n/a" in l for l in lines if l.lstrip().startswith( "t2" ) or " t2 " in l ):
        probs.append( "the t2 per-task row (no transcript) must print its split as n/a, never 0" )
except Exception as exc:
    probs.append( f"{type( exc ).__name__}: {exc}" )
verdict( "(C4) NO SILENT SPLIT: every printed cost line carries its cache split; unmeasured reads n/a", probs )

# ── (C5) existing headline keys keep their values; self-test still passes ─────────────────────────────
PINNED = {  # analyze.analyze( analyze.synthetic_fixture(), n_boot=4000 ) at origin/main 5f4b50415
    "n_pairs": 27, "n_repos": 3, "n_incomplete": 2, "n_contaminated_baseline": 1, "n_resolved_pairs": 27,
    "resolved_delta_mean": 0.25925925925925924, "resolved_delta_bootstrap_95_lower": 0.1111111111111111,
    "localization_hit_delta_mean": 0.25925925925925924,
    "tokens_out_ratio_p50": 0.08000000000000007, "tokens_out_ratio_p95": 0.08000000000000007,
    "wall_seconds_ratio_p50": 0.07999999999999985, "wall_seconds_ratio_p95": 0.07999999999999985,
    "cost_usd_ratio_p50": 0.08000000000000007, "cost_usd_ratio_p95": 0.08000000000000007,
    "substitution_rate_baseline": 0.0, "n_substitution_baseline": 27,
    "substitution_rate_ripwire": 0.75, "n_substitution_ripwire": 27 }
probs = []
try:
    got = analyze.analyze( analyze.synthetic_fixture(), n_boot=4000 )
    for k, v in PINNED.items():
        g = got.get( k )
        if g is None or abs( g - v ) > 1e-12: probs.append( f"{k} = {g!r}, base had {v!r}" )
    st = subprocess.run( [ sys.executable, "-I", str( AL / "analyze.py" ), "--self-test" ], capture_output=True, text=True )
    if st.returncode != 0: probs.append( "analyze.py --self-test failed:\n" + st.stdout[-800:] )
except Exception as exc:
    probs.append( f"{type( exc ).__name__}: {exc}" )
verdict( "(C5) HEADLINE: every base headline key keeps its value; --self-test passes", probs )

# ── (P1) pass^k on known outcomes ─────────────────────────────────────────────────────────────────────
outcomes = { "k1": [ True, True, True ], "k2": [ True, False, True ], "k3": [ False, False ], "k4": [ True ] }
precs = []
for inst, res in outcomes.items():
    for seed, ok in enumerate( res, 1 ):
        precs.append( rec( inst, "ripwire_cli", seed, "fixture", None, resolved=ok ) )
# a non-ok run never counts as a trial
precs.append( rec( "k4", "ripwire_cli", 2, "fixture", None, resolved=False, status="timeout" ) )
probs = []
pout = None
try:
    pout = analyze.analyze( precs, n_boot=50 )
    c = pout["consistency"]["resolved"]["ripwire_cli"]
    def near( a, b ): return a is not None and abs( a - b ) < 1e-12
    if not near( c.get( "pass_at_1" ), ( 1 + 2/3 + 0 + 1 ) / 4 ) or c.get( "n_tasks" ) != 4:
        probs.append( f"pass@1 = {c.get( 'pass_at_1' )!r} over {c.get( 'n_tasks' )!r} tasks, expected {( 1 + 2/3 + 1 ) / 4!r} over 4" )
    pk = c.get( "pass_hat_k", {} )
    if not ( 2 in pk and near( pk[2]["value"], ( 1 + 1/3 + 0 ) / 3 ) and pk[2]["n_tasks"] == 3 ):
        probs.append( f"pass^2 = {pk.get( 2 )!r}, expected value 4/9 over 3 tasks" )
    if not ( 3 in pk and near( pk[3]["value"], 0.5 ) and pk[3]["n_tasks"] == 2 ):
        probs.append( f"pass^3 = {pk.get( 3 )!r}, expected value 0.5 over 2 tasks" )
    if 4 in pk or 1 in pk: probs.append( f"pass^k reported for k outside 2..max runs: {sorted( pk )}" )
    if c.get( "n_runs_excluded" ) != 1: probs.append( f"n_runs_excluded = {c.get( 'n_runs_excluded' )!r}, expected 1 (the timeout)" )
    if analyze.pass_hat_k( 2, 3, 2 ) != 1/3 or analyze.pass_hat_k( 3, 3, 3 ) != 1.0 or analyze.pass_hat_k( 1, 3, 2 ) != 0.0:
        probs.append( "pass_hat_k( c, n, k ) is not C(c,k)/C(n,k)" )
except Exception as exc:
    probs.append( f"{type( exc ).__name__}: {exc}" )
verdict( "(P1) PASS^K: consistency over k trials matches the hand-computed values", probs )

# ── (P2) printed beside pass@1 ────────────────────────────────────────────────────────────────────────
probs = []
try:
    buf = io.StringIO()
    with contextlib.redirect_stdout( buf ):
        analyze.print_report( pout )
    line = next( ( l for l in buf.getvalue().splitlines() if "pass@1" in l and "ripwire_cli" in l and "resolved" in l ), "" )
    if not line or "pass^2" not in line or "pass^3" not in line or "(n=3)" not in line or "(n=2)" not in line:
        probs.append( f"no resolved line printing pass^2 and pass^3 with their task counts beside pass@1: {line!r}" )
except Exception as exc:
    probs.append( f"{type( exc ).__name__}: {exc}" )
verdict( "(P2) PRINTED: pass^k is printed beside pass@1 with each k's task count", probs )

print( f"agentloopaccountingcheck: {'FAIL' if fails else 'PASS'} ({fails} of 7 arms red)" )
sys.exit( 1 if fails else 0 )
EOF
