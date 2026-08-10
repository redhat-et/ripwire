#!/usr/bin/env bash
# agentloopcodexcheck.sh — Codex agent-loop harness isolation + JSONL accounting gate.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"

python3 - "$ROOT" <<'PY'
import importlib.util, os, pathlib, sys, tempfile

root = pathlib.Path( sys.argv[1] )
path = root / "bench" / "agentloop" / "run_agentloop.py"
spec = importlib.util.spec_from_file_location( "run_agentloop", path )
module = importlib.util.module_from_spec( spec )
spec.loader.exec_module( module )

ripwire = str( root / "build" / "ripwire" )
base_prompt = module.build_prompt( { "problem_statement": "fix the issue" }, 1, "baseline", ripwire )
ctx_prompt = module.build_prompt( { "problem_statement": "fix the issue" }, 1, "ripwire_cli", ripwire )
base = module.build_codex_command( base_prompt, "" )
ctx = module.build_codex_command( ctx_prompt, "gpt-test" )

def joined( cmd ): return "\n".join( cmd )

assert base[:2] == [ "codex", "exec" ]
assert "--json" in base and "--ephemeral" in base and "--ignore-user-config" in base
assert "--ignore-rules" in base and "workspace-write" in base
assert "mcp_servers={}" in base, base
assert "mcp_servers.ripwire" not in joined( base ), base
assert "--model" not in base
assert "Do not use ripwire" in base[-1], base[-1]

assert "--model" in ctx and ctx[ctx.index( "--model" ) + 1] == "gpt-test"
assert "mcp_servers={}" in ctx, ctx
assert "mcp_servers.ripwire" not in joined( ctx ), ctx
assert str( root / "build" / "ripwire" ) in ctx[-1], ctx[-1]
assert "CLI" in ctx[-1], ctx[-1]

events = "\n".join( (
    '{"type":"thread.started","thread_id":"fixture"}',
    '{"type":"item.completed","item":{"type":"command_execution","command":"/repo/build/ripwire . --for=issue"}}',
    '{"type":"turn.completed","usage":{"input_tokens":1234,"cached_input_tokens":234,"output_tokens":56}}',
) )
tokens_in, tokens_out = module.parse_codex_jsonl_usage( events )
assert tokens_in == 1234 and tokens_out == 56, ( tokens_in, tokens_out )
metrics = module.parse_codex_jsonl_metrics( events, "/repo/build/ripwire" )
assert metrics[2:] == ( 1, 1, [ "/repo/build/ripwire . --for=issue" ] ), metrics

tasks = [
    { "instance_id": "a1", "repo": "org/a" },
    { "instance_id": "a2", "repo": "org/a" },
    { "instance_id": "b1", "repo": "org/b" },
    { "instance_id": "b2", "repo": "org/b" },
    { "instance_id": "c1", "repo": "org/c" },
]
pilot = module.limit_tasks_repo_round_robin( tasks, 3 )
assert [ row["instance_id"] for row in pilot ] == [ "a1", "b1", "c1" ], pilot

with tempfile.TemporaryDirectory() as td:
    fake_home = pathlib.Path( td ) / "source-home"
    fake_home.mkdir()
    ( fake_home / "auth.json" ).write_text( "{}" )
    old_home = os.environ.get( "CODEX_HOME" )
    os.environ["CODEX_HOME"] = str( fake_home )
    try:
        base_env, base_home, base_shim = module.prepare_codex_environment( pathlib.Path( td ) / "runs", "task", "baseline", 1, ripwire )
        ctx_env, ctx_home, ctx_shim = module.prepare_codex_environment( pathlib.Path( td ) / "runs", "task", "ripwire_cli", 1, ripwire )
        sk_env, sk_home, sk_shim = module.prepare_codex_environment( pathlib.Path( td ) / "runs", "task", "ripwire_skills", 1, ripwire )
    finally:
        if old_home is None: os.environ.pop( "CODEX_HOME", None )
        else: os.environ["CODEX_HOME"] = old_home
    assert pathlib.Path( base_env["CODEX_HOME"] ) == base_home
    assert ( base_home / "auth.json" ).is_symlink()
    assert not ( base_home / "skills" ).exists()
    # v3: the skills tree belongs to ripwire_skills ALONE. It used to ride along on ripwire_cli,
    # which is why the 2026-08-04 pilot could not tell ripwire's cost from the skills tax.
    assert not ( ctx_home / "skills" ).exists(), "ripwire_cli must not inject skills any more"
    assert any( ( sk_home / "skills" ).iterdir() ), "ripwire_skills must inject skills"
    # PATH now leads with the logging shim, not the raw binary dir: `claude -p` never logged shell
    # commands, so a transcript grep could not count ripwire calls for that harness at all.
    assert ctx_env["PATH"].split( os.pathsep )[0] == str( pathlib.Path( ctx_shim ).parent )
    assert pathlib.Path( ctx_shim ).name == "ripwire" and os.access( ctx_shim, os.X_OK )

# ── run_one's extracted accounting helpers: same events + trailer behavior the inline code had ─────────
with tempfile.TemporaryDirectory() as td:
    task = { "instance_id": "x1" }
    m = module._codex_metrics( events, td, task, "baseline", 1, "/repo/build/ripwire" )
    events_file = pathlib.Path( td ) / "events" / "x1-baseline-1.jsonl"
    assert events_file.is_file() and events_file.read_text() == events, "raw Codex JSONL must be retained verbatim"
    assert ( m["tokens_in"], m["tokens_out"] ) == ( 1234, 56 ), m
    assert ( m["command_calls"], m["ripwire_calls"] ) == ( 1, 1 ), m
    assert m["ripwire_commands"] == [ "/repo/build/ripwire . --for=issue" ], m
    assert m["events_path"] == str( events_file ), m
    # TimeoutExpired hands over bytes (possibly invalid UTF-8) or None — both must degrade, not crash
    mb = module._codex_metrics( b"\xff" + events.encode( "utf-8" ), td, task, "baseline", 2, "/repo/build/ripwire" )
    assert ( mb["tokens_in"], mb["tokens_out"] ) == ( 1234, 56 ), mb
    mn = module._codex_metrics( None, td, task, "baseline", 3, "/repo/build/ripwire" )
    assert mn["tokens_in"] is None and pathlib.Path( mn["events_path"] ).read_text() == "", mn

trailer = '{"usage":{"input_tokens":10,"output_tokens":2},"total_cost_usd":0.05}'
cm = module._claude_metrics( trailer )
assert cm == dict( tokens_in=10, tokens_out=2, cost_usd=0.05 ), cm
assert module._claude_metrics( "not json" ) == {}, "trailer schema drift must degrade to nulls, not crash"

# ── analyze.py self-test: pins pairing, clustering, bootstrap sign, and the exact fixture ratios ───────
analyze_path = root / "bench" / "agentloop" / "analyze.py"
analyze_spec = importlib.util.spec_from_file_location( "agentloop_analyze", analyze_path )
analyze_module = importlib.util.module_from_spec( analyze_spec )
analyze_spec.loader.exec_module( analyze_module )
assert analyze_module.self_test() == 0, "analyze.py --self-test regressed"

find_bug = ( root / "skills" / "ripwire-find-bug" / "SKILL.md" ).read_text()
change_check = ( root / "skills" / "ripwire-change-check" / "SKILL.md" ).read_text()
quality_bar = ( root / "skills" / "ripwire-quality-bar" / "SKILL.md" ).read_text()
assert "Evidence-sufficiency stop" in find_bug
assert "Do not turn a focused fix" in change_check
assert "single-line leaf fix" in quality_bar

# The 2026-08-04 pilot showed the dominant treatment loss is skill-POLICY: the agent pays a full
# SKILL.md body read (2-6k tokens, replayed every later turn) to learn a scope guard that says the
# read was unnecessary. The guard must live in the FRONTMATTER the agent sees for free.
def frontmatter( text ):
    parts = text.split( "---" )
    fm = parts[1] if len( parts ) >= 3 else ""
    return " ".join( fm.split() )   # whitespace-normalized: guards must not depend on line-wrap positions
assert "is enough" in frontmatter( find_bug ), "find-bug: evidence-sufficiency stop must be advertised in frontmatter"
assert "single-line leaf fix" in frontmatter( quality_bar ), "quality-bar: scope guard must be advertised in frontmatter"
assert "one-line leaf fix" in frontmatter( change_check ), "change-check: scope guard must be advertised in frontmatter"

# Every skill whose body offers a MENU of verbs gets a one-sentence stop rule in frontmatter too —
# the pilot's ritual expansion (multiple calls where the first sufficed) is not find-bug-specific.
stop_guards = {
    "ripwire-reuse-first":      "at most",
    "ripwire-orient":           "first rung",
    "ripwire-navigate":         "one verb",
    "ripwire-before-you-build": "needs none of this",
    "ripwire-fresh-eyes":       "single call",
    "ripwire-write-tests":      "one target",
    "ripwire-perf-target":      "the profile names",
    "ripwire-security-scan":    "one scan pass",
    "ripwire-layers":           "one pass",
}
for skill_name, marker in stop_guards.items():
    text = ( root / "skills" / skill_name / "SKILL.md" ).read_text()
    assert marker in frontmatter( text ).lower(), f"{skill_name}: stop rule ({marker!r}) must be advertised in frontmatter"

print( "agentloopcodexcheck: PASS — Codex arms are config-isolated and JSONL usage is captured" )
PY
