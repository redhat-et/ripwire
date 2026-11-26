#!/usr/bin/env python3
"""
Fixture tests for bench/locbench/agent_loc.py, the placebo round's agent driver (PREREG_PLACEBO.md "Agent driver
contract"). No network, no model, no API token: the models are a scripted stub and a fake `claude` executable.

    python3 bench/locbench/test_agent_loc.py [RIPWIRE_BIN]

With RIPWIRE_BIN, its directory is put on PATH and the child environment must still not reach it.
"""
import hashlib, json, os, pathlib, shutil, stat, subprocess, sys, tempfile

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
import agent_loc as al
import run_locbench as rl

failures = []
def check( cond, msg ):
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond:
        failures.append( msg )

TMP = pathlib.Path( tempfile.mkdtemp( prefix="plive_agenttest_" ) )

# ── fixtures ─────────────────────────────────────────────────────────────────
def git( repo, *args ):
    subprocess.run( [ "git", *args ], cwd=repo, check=True, capture_output=True,
                    env=dict( os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t" ) )

REPO = TMP / "repo"
( REPO / "pkg" ).mkdir( parents=True )
( REPO / "pkg" / "config_parser.py" ).write_text( "class Parser:\n    def parse_section( self, text ):\n        return text.split( '=' )\n\ndef load( path ):\n    return Parser()\n" )
( REPO / "pkg" / "big.py" ).write_text( "".join( f"needle_{i} = {i}  # padding padding padding\n" for i in range( 600 ) ) )
git( REPO, "init", "-q" ); git( REPO, "add", "." ); git( REPO, "commit", "-q", "-m", "fixture" )
( REPO / "untracked_secret.txt" ).write_text( "not tracked\n" )
( TMP / "outside.txt" ).write_text( "outside\n" )

IID = "owner__proj-1"
PAYLOADS = TMP / "payloads"
PAYLOAD_TEXT = '<!-- legend --><candidates count="1"><cand r="1" s="0.9" n="parse_section" id="pkg/config_parser.py::Parser::parse_section" k="fn" p="pkg/config_parser.py" l="2"><sig>def parse_section( self, text )</sig></cand></candidates>'
# the fixture seal is written by run_locbench's own emit_payloads, so the driver is tested against the real format
rl.emit_payloads( PAYLOADS, IID, { "for-matched": PAYLOAD_TEXT, "placebo": PAYLOAD_TEXT.replace( "0.9", "0.8" ), "lexical": PAYLOAD_TEXT,
                                   "placebo-shuffle": PAYLOAD_TEXT }, PAYLOAD_TEXT + " " )
( PAYLOADS / "owner__proj-2" ).mkdir()
( PAYLOADS / "owner__proj-2" / "manifest.json" ).write_text( json.dumps( { "for-matched": dict( bytes=1, sha256="0" * 64 ) } ) )
GOLD = dict( covered=[ [ "pkg/config_parser.py", "Parser", "parse_section" ] ], primary_files=[ "pkg/config_parser.py" ],
             universe_files=[ "pkg/big.py", "pkg/config_parser.py" ] )
INST = dict( instance_id=IID, query="Parser.parse_section drops values after a second '=' sign" )

# ── 1. the seal ──────────────────────────────────────────────────────────────
print( "seal" )
text, sha, nb = al.load_payload( PAYLOADS, IID, "A1" )
check( text == PAYLOAD_TEXT and sha == hashlib.sha256( PAYLOAD_TEXT.encode() ).hexdigest() and nb == len( PAYLOAD_TEXT.encode() ),
       "A1 loads the for-matched payload with its manifest sha256 and byte count" )
check( al.load_payload( PAYLOADS, IID, "A0" ) == ( None, None, 0 ), "A0 (query floor) carries no payload" )
check( al.load_payload( PAYLOADS, IID, "A1p" )[0].endswith( " " ), "A1p reads the shipped for-production payload" )
tampered = TMP / "tampered"; shutil.copytree( PAYLOADS, tampered )
p = tampered / IID / "placebo.xml"; p.write_bytes( p.read_bytes().replace( b"0.8", b"0.7" ) )
try:
    al.load_payload( tampered, IID, "A2" ); check( False, "a payload edited after the seal is refused" )
except al.SealBroken:
    check( True, "a payload edited after the seal is refused (SealBroken)" )
try:
    al.load_payload( PAYLOADS, "owner__proj-2", "A2" ); check( False, "a payload missing from the seal is refused" )
except al.SealBroken:
    check( True, "a payload missing from the seal is refused (SealBroken)" )
stub = al.StubModel( [ '{"tool":"submit","locations":[]}' ] )
try:
    al.run_episode( stub, INST, "A2", 1, tampered, REPO, None, GOLD ); check( False, "a broken seal refuses the episode" )
except al.SealBroken:
    check( stub.prompts == [], "a broken seal refuses the episode BEFORE any model call" )
digest, n = al.seal_digest( PAYLOADS )
manual = hashlib.sha256( b"".join( ( PAYLOADS / d / "manifest.json" ).read_bytes() for d in sorted( [ IID, "owner__proj-2" ] ) ) ).hexdigest()
check( n == 2 and digest == manual, "seal digest = sha256 of the sorted concatenation of every manifest.json" )
check( al.seal_digest( tampered )[0] == digest, "seal digest covers manifests (a payload edit is caught by load_payload, not the digest)" )
( tampered / IID / "manifest.json" ).write_text( "{}" )
check( al.seal_digest( tampered )[0] != digest, "a manifest edit changes the seal digest" )

# ── 2. isolation ─────────────────────────────────────────────────────────────
print( "isolation" )
fakebin = TMP / "fakebin"; fakebin.mkdir()
( fakebin / "ripwire" ).write_text( "#!/bin/sh\necho reached\n" ); ( fakebin / "ripwire" ).chmod( 0o755 )
extra = [ str( fakebin ) ]
if len( sys.argv ) > 1 and os.path.exists( sys.argv[1] ):
    real_bin_dir = os.path.dirname( os.path.abspath( sys.argv[1] ) )
    if os.path.basename( sys.argv[1] ) == "ripwire":
        extra.append( real_bin_dir )
os.environ["PATH"] = os.pathsep.join( extra + [ os.environ.get( "PATH", "" ) ] )
os.environ["RIPWIRE"] = str( fakebin / "ripwire" )
env = al.child_env()
check( shutil.which( "ripwire", path=env["PATH"] ) is None, f"no ripwire on the child PATH ({len( extra )} planted dir(s) removed, incl. the gate's BIN dir)" )
check( "RIPWIRE" not in env and "RIPWIRE_BIN" not in env, "RIPWIRE / RIPWIRE_BIN are not passed to the child" )
check( shutil.which( "git", path=env["PATH"] ) is not None, "the child PATH still reaches ordinary tools (git)" )

# fake `claude`: records what the child saw, answers with a real-shaped -p JSON trailer
fake_claude = TMP / "fake_claude.sh"
probe = TMP / "probe.txt"
fake_claude.write_text( f"""#!/bin/sh
{{ echo "ripwire=$(command -v ripwire || echo none)"; echo "cwd_entries=$(ls -A | wc -l | tr -d ' ')"; echo "args=$*"; echo "stdin_bytes=$(wc -c | tr -d ' ')"; }} > {probe}
cat <<'JSON'
{{"type":"result","is_error":false,"result":"{{\\"tool\\":\\"submit\\",\\"locations\\":[\\"pkg/config_parser.py:Parser.parse_section\\"]}}","num_turns":1,"total_cost_usd":0.00042,"usage":{{"input_tokens":1200,"cache_creation_input_tokens":300,"cache_read_input_tokens":500,"output_tokens":40}},"modelUsage":{{"claude-haiku-5-5":{{}}}}}}
JSON
""" )
fake_claude.chmod( 0o755 )
cli = al.ClaudeCLI( "claude-haiku-5-5", "low", str( fake_claude ) )
argv = cli.argv( al.SYSTEM_PROMPT )
for flag in ( "--tools", "--setting-sources", "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence", "--system-prompt" ):
    check( flag in argv, f"claude -p argv carries {flag}" )
check( argv[argv.index( "--tools" ) + 1] == "" and argv[argv.index( "--setting-sources" ) + 1] == "", "built-in tools and setting sources are both empty" )
check( argv[argv.index( "--model" ) + 1] == "claude-haiku-5-5" and argv[argv.index( "--effort" ) + 1] == "low", "model and effort are the prereg's (Haiku 5.5, low)" )
rec = al.run_episode( cli, INST, "A1", 1, PAYLOADS, REPO, TMP / "tx_cli", GOLD )
seen = dict( l.split( "=", 1 ) for l in probe.read_text().splitlines() if "=" in l )
check( seen.get( "ripwire" ) == "none", "the fake claude child could not reach ripwire" )
check( seen.get( "cwd_entries" ) == "0", "the claude child runs in an empty cwd (no CLAUDE.md, no repo)" )
check( int( seen.get( "stdin_bytes", "0" ) ) > len( PAYLOAD_TEXT ), "the prompt (with payload) reaches the child on stdin" )
check( rec["resolved_model"] == [ "claude-haiku-5-5" ], "resolved_model is read back from the provider trailer" )
check( ( rec["split_uncached_in"], rec["split_cache_write"], rec["split_cache_read"], rec["split_output"] ) == ( 1200, 300, 500, 40 ),
       "usage is split by cache category from the -p trailer" )
check( rec["input_tokens"] == 2000 and rec["cost_usd_cli"] == 0.00042, "input total = uncached + write + read; CLI cost recorded" )
check( rec["credential"].startswith( "claude-cli-login" ), "the billed credential is NAMED in the record" )
check( abs( rec["cost_usd_prereg_prices"] - ( 1200 * 0.10 + 300 * 0.125 + 500 * 0.01 + 40 * 0.50 ) / 1e6 ) < 1e-12, "prereg-price cost from the split" )
check( rec["func_hit10"] == 1 and rec["file_hit5"] == 1, "a submitted Class.method scores a function hit with the run_locbench scorer" )
bad = al.parse_cli_trailer( '{"is_error":true,"result":"Not logged in","usage":{}}', 1 )
check( bad["error"] is not None and bad["usage"]["split_output"] is None, "a provider error is an error; an unreported cell is None, never 0" )

# ── 3. tools ─────────────────────────────────────────────────────────────────
print( "tools" )
tracked = al.tracked_files( REPO )
check( "untracked_secret.txt" not in tracked and "pkg/big.py" in tracked, "the read universe is git-tracked files only" )
g = al.tool_grep( REPO, r"def parse_\w+", "**/*.py" )
check( "pkg/config_parser.py:2:" in g, "grep returns path:line:text with a path glob" )
check( al.tool_grep( REPO, "zzz_absent_zzz", "" ) == "no matches", "grep with no match says so" )
big = al.tool_grep( REPO, "needle_", "" )
check( len( big.encode() ) < al.TOOL_RESULT_CAP + 100 and "[cut:" in big, "grep output is capped at 8,000 bytes and the cut is disclosed" )
check( al.tool_grep( REPO, "--version", "" ) == "no matches", "a pattern starting with '-' is a pattern (passed with -e), not a git flag" )
r = al.tool_read( REPO, "pkg/config_parser.py", 2, 3, tracked )
check( "2:     def parse_section" in r and "4:" not in r, "read returns the requested numbered line range" )
check( al.tool_read( REPO, "untracked_secret.txt", 1, 5, tracked ).startswith( "error" ), "read of an untracked file is refused" )
check( al.tool_read( REPO, "../outside.txt", 1, 5, tracked ).startswith( "error" ), "read outside the checkout is refused" )
check( "[cut:" in al.tool_read( REPO, "pkg/big.py", 1, 600, tracked ), "read output is capped and the cut is disclosed" )

# ── 4. episodes ──────────────────────────────────────────────────────────────
print( "episodes" )
script = [ 'I will search. {"tool": "grep", "pattern": "parse_section", "path_glob": "**/*.py"}',
           '{"tool": "read", "path": "pkg/config_parser.py", "start": 1, "end": 6}',
           '{"tool": "submit", "locations": ["pkg/config_parser.py:Parser.parse_section", "pkg/config_parser.py:load"]}' ]
s1 = al.StubModel( script, usage_per_call=( 1000, 0, 0, 50 ) )
rec = al.run_episode( s1, INST, "A1", 2, PAYLOADS, REPO, TMP / "tx", GOLD )
check( rec["submitted"] and rec["turns"] == 3 and rec["tool_calls"] == dict( grep=1, read=1, submit=1, invalid=0, refused=0 ),
       "grep -> read -> submit: 3 turns, tool calls counted by kind" )
check( rec["arm"] == "A1" and rec["seed"] == 2 and rec["model"] == "stub-model" and rec["payload_bytes"] == len( PAYLOAD_TEXT.encode() ),
       "record carries arm, seed, model and payload bytes" )
check( rec["input_tokens"] == 3000 and rec["output_tokens"] == 150, "tokens summed over every model call" )
check( rec["func_hit10"] == 1 and rec["strict_func10"] == 1 and rec["strict_file10"] == 1, "hit@10 and strict scores computed" )
tx = json.loads( pathlib.Path( rec["transcript"] ).read_text() )
check( len( tx["turns"] ) == 3 and tx["turns"][0]["tool_result"].startswith( "pkg/config_parser.py:2:" ), "transcript saved with every turn and tool result" )
check( "func_hit10" not in tx["record"], "the transcript file carries no score (no answer key beside the episode)" )
check( PAYLOAD_TEXT in s1.prompts[0] and "<retrieved>" in s1.prompts[0], "the payload is placed verbatim in the first user message" )
s0 = al.StubModel( script )
al.run_episode( s0, INST, "A0", 1, PAYLOADS, REPO, None, GOLD )
check( "<retrieved>" not in s0.prompts[0] and "parse_section( self" not in s0.prompts[0], "A0 gets no payload block" )
pa, pb = al.StubModel( script ), al.StubModel( script )
al.run_episode( pa, INST, "A1", 1, PAYLOADS, REPO, None, GOLD ); al.run_episode( pb, INST, "A2", 1, PAYLOADS, REPO, None, GOLD )
check( pa.prompts[0].replace( "0.9", "X" ) == pb.prompts[0].replace( "0.8", "X" ), "A1 and A2 prompts differ ONLY in the payload bytes" )

silent = al.StubModel( lambda prompt, turn: "I think it is in the parser." )
rec = al.run_episode( silent, INST, "A2", 1, PAYLOADS, REPO, None, GOLD )
check( not rec["submitted"] and rec["turns"] == al.MAX_TURNS and rec["func_hit10"] == 0 and rec["stop"] == "turns",
       "no submit in 15 turns: a counted miss, not an exclusion" )
check( "FINAL turn" in silent.prompts[-1] and len( silent.prompts ) == al.MAX_TURNS, "the 15th turn is announced as final; no 16th call" )
greedy = al.StubModel( lambda prompt, turn: '{"tool":"grep","pattern":"needle_1","path_glob":""}', usage_per_call=( 20_000, 0, 0, 10 ) )
rec = al.run_episode( greedy, INST, "A3", 1, PAYLOADS, REPO, None, GOLD )
check( rec["stop"] == "input_token_guard" and rec["turns"] == 13 and not rec["submitted"] and rec["input_tokens"] >= al.INPUT_TOKEN_GUARD,
       "the 250,000 cumulative-input-token guard stops the episode (turn 13 at 20,000/call) and scores a miss" )
lastgrep = al.StubModel( lambda prompt, turn: '{"tool":"grep","pattern":"x","path_glob":""}' )
rec = al.run_episode( lastgrep, INST, "A1", 1, PAYLOADS, REPO, None, GOLD )
check( rec["tool_calls"]["grep"] == 14 and rec["tool_calls"]["refused"] == 1, "a tool call on the final turn is refused (counted)" )
flaky_calls = []
class Flaky( al.StubModel ):
    def call( self, system, prompt, turn ):
        flaky_calls.append( turn )
        return dict( text="", usage=al.empty_usage(), cost_usd=None, resolved_models=[], raw="", error="provider error rc=1" )
rec = al.run_episode( Flaky( [] ), INST, "A1", 1, PAYLOADS, REPO, None, GOLD )
check( len( flaky_calls ) == 4 and rec["stop"] == "provider_error" and rec["func_hit10"] == 0 and rec["split_output"] is None,
       "a persistent provider error retries 3 times, then scores a counted miss with usage None (unmeasured)" )

# ── 5. protocol ──────────────────────────────────────────────────────────────
print( "protocol" )
check( al.parse_action( 'ok {"tool":"grep","pattern":"a{2}\\"}"} trailing' ) == { "tool": "grep", "pattern": 'a{2}"}' },
       "parse_action takes the first balanced JSON object, braces and quotes inside strings included" )
check( al.parse_action( "no json here" ) is None, "no JSON -> None (an invalid turn)" )
check( al.normalize_locations( [ "a.py:f" ] * 3 + [ f"b.py:f{i}" for i in range( 20 ) ] + [ 7 ] ) == [ "a.py:f" ] + [ f"b.py:f{i}" for i in range( 9 ) ],
       "submit keeps at most 10 unique path:function strings" )
sc = al.score_submission( [ "pkg/config_parser.py:OtherClass.parse_section" ], GOLD["covered"], GOLD["primary_files"], GOLD["universe_files"] )
check( sc["func_hit10"] == 0 and sc["file_hit5"] == 1, "a same-named method of ANOTHER class is not a function hit (scope-exact), but is a file hit" )

# ── 6. pilot selection and power arithmetic ──────────────────────────────────
print( "pilot" )
repos = [ f"org/repo{i}" for i in range( 60 ) ]
train = [ r for r in repos if rl.frozen_partition( r ) == "train" ]
held = [ r for r in repos if rl.frozen_partition( r ) == "heldout" ]
rows = [ dict( instance_id=f"{r.replace( '/', '__' )}-{j}", repo=r ) for r in repos for j in ( 2, 1 ) ]   # no gold fields at all
pick = al.select_pilot( rows, 24 )
check( len( pick ) == min( 24, 2 * len( train ) ) and all( rl.frozen_partition( p.split( "-" )[0].replace( "__", "/" ) ) == "train" for p in pick ),
       f"pilot = 24 TRAIN instances only ({len( train )} train / {len( held )} held-out fixture repos)" )
first_round = [ p for p in pick if p.endswith( "-1" ) ]
check( len( set( p.rsplit( "-", 1 )[0] for p in pick[:len( train )] ) ) == min( len( train ), 24 ) and pick[0].endswith( "-1" ),
       "round-robin: one instance per repo per round, each repo's lowest instance_id first" )
check( al.select_pilot( list( reversed( rows ) ), 24 ) == pick, "selection is independent of row order" )
recs = [ dict( instance_id=f"i{k}", arm=arm, func_hit10=h ) for k, ( a1, a2 ) in enumerate( [ ( 1, 0 ), ( 0, 0 ), ( 1, 1 ), ( 0, 1 ) ] )
         for arm, h in ( ( "A1", a1 ), ( "A2", a2 ) ) ]
check( al.discordance( recs ) == ( 0.5, 4 ), "d = share of instances where A1 and A2 disagree" )
mde = al.holm_mde_pp( 0.30, 3 )
check( 8.8 <= mde <= 9.1, f"prereg power arithmetic reproduces: d=0.30, K=3 -> Holm MDE {mde:.2f} pp (prereg 8.9)" )
check( al.holm_mde_pp( 0.30, 5 ) < mde, "K=5 lowers the MDE" )

# ── 7. cost guard and credential label ───────────────────────────────────────
print( "cost guard" )
cheap = [ dict( cost_usd_prereg_prices=0.009, input_tokens=78_000, output_tokens=3_000 ) ] * 12
dear = [ dict( cost_usd_prereg_prices=0.020, input_tokens=190_000, output_tokens=3_000 ) ] * 12
check( al.cost_guard( cheap, "claude-haiku-5-5", 2.0 )[0] is False, "cost guard passes at the central estimate (prereg-priced tokens)" )
stop, summ = al.cost_guard( dear, "claude-haiku-5-5", 2.0 )
check( stop and summ["multiple"] > 2.0 and summ["mean_input_tokens"] == 190_000, "cost guard STOPS above 2x the central estimate and reports tokens" )
check( al.cost_guard( cheap[:11] + [ dict( cost_usd_prereg_prices=None, input_tokens=None, output_tokens=None ) ], "claude-haiku-5-5", 2.0 )[0],
       "an unpriceable episode stops the run (unmeasured is not cheap)" )
check( al.ClaudeCLI( "claude-haiku-5-5", credential="claude.ai subscription (CLI)" ).credential == "claude.ai subscription (CLI)",
       "the run names its credential label" )

# ── 8. held-out refusal in main() ────────────────────────────────────────────
print( "held-out guard" )
work = TMP / "work"; ( work / "datasets" ).mkdir( parents=True )
hrow = dict( instance_id="h__x-1", repo=held[0], base_commit="0" * 40, problem_statement="q" )
( work / "datasets" / "rows_czlll__Loc-Bench_V1_test_560.json" ).write_text( json.dumps( [ hrow ] ) )
seal_json = TMP / "seal.json"; seal_json.write_text( json.dumps( dict( instances=[ dict( instance_id="h__x-1", covered=[], primary_files=[], universe_files=[] ) ] ) ) )
r = subprocess.run( [ sys.executable, os.path.join( HERE, "agent_loc.py" ), "--work-dir", str( work ), "--payloads", str( PAYLOADS ),
                      "--seal-json", str( seal_json ), "--out", str( TMP / "out" ), "--claude-bin", str( TMP / "no_such_claude" ) ],
                    capture_output=True, text=True )
check( r.returncode != 0 and "held-out" in ( r.stdout + r.stderr ) and not ( TMP / "out" / "episodes.jsonl" ).exists(),
       "main() refuses a held-out instance without --allow-heldout, before any episode" )

shutil.rmtree( TMP, ignore_errors=True )
print( f"\n{'FAILED' if failures else 'OK'}: {len( failures )} failure(s)" )
sys.exit( 1 if failures else 0 )
