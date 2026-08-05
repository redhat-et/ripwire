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
        base_env, base_home = module.prepare_codex_environment( pathlib.Path( td ) / "runs", "task", "baseline", 1, ripwire )
        ctx_env, ctx_home = module.prepare_codex_environment( pathlib.Path( td ) / "runs", "task", "ripwire_cli", 1, ripwire )
    finally:
        if old_home is None: os.environ.pop( "CODEX_HOME", None )
        else: os.environ["CODEX_HOME"] = old_home
    assert pathlib.Path( base_env["CODEX_HOME"] ) == base_home
    assert ( base_home / "auth.json" ).is_symlink()
    assert not ( base_home / "skills" ).exists()
    assert any( ( ctx_home / "skills" ).iterdir() )
    assert ctx_env["PATH"].split( os.pathsep )[0] == str( pathlib.Path( ripwire ).parent )

find_bug = ( root / "skills" / "ripwire-find-bug" / "SKILL.md" ).read_text()
change_check = ( root / "skills" / "ripwire-change-check" / "SKILL.md" ).read_text()
quality_bar = ( root / "skills" / "ripwire-quality-bar" / "SKILL.md" ).read_text()
assert "Evidence-sufficiency stop" in find_bug
assert "Do not turn a focused fix" in change_check
assert "single-line leaf fix" in quality_bar

print( "agentloopcodexcheck: PASS — Codex arms are config-isolated and JSONL usage is captured" )
PY
