#!/usr/bin/env python3
# agent_loc.py — the LocBench placebo round's agent driver (bench/locbench/PREREG_PLACEBO.md, "Agent driver
# contract"). One episode = one model localizing one issue with read-only grep/read tools over the checkout at
# base_commit, plus AT MOST one frozen payload in the first user message. ripwire is never on the child's PATH,
# so the sealed payload is the only ripwire exposure in any arm.
#
# THE CONTRACT, as frozen in the prereg (each line is gated by test/locbenchagentcheck.sh):
#   * payloads come only from a `run_locbench.py --emit-payloads` seal; every payload's sha256 and byte count is
#     checked against its instance manifest, and a mismatch REFUSES the episode (SealBroken), never runs it;
#   * tools: grep(pattern, path_glob), read(path, start, end) over git-tracked files of the checkout, each result
#     capped at 8,000 bytes with the cut disclosed; submit(up to 10 "path:function" strings);
#   * limits: 15 turns; a hard stop at 250,000 cumulative input tokens (the blow-up guard). An episode that ends
#     without submit scores as a miss and is COUNTED, never excluded;
#   * the record carries model requested and resolved_model read back from the provider's own output, arm, seed,
#     the billed credential's NAME (never its value), tokens split by cache category, tool calls by kind, turns,
#     submitted list, wall clock, and the transcript path. A cell the provider did not report is None, never 0.
#
# TOOL PROTOCOL. Every backend gets the same rendered text: a fixed system prompt (SYSTEM_PROMPT, its sha256 in
# every record) and one user prompt holding the issue, the payload block, and the turn history. The model answers
# with ONE JSON action per turn. The protocol is text, not provider-native tool_use, so the identical bytes reach
# every backend (the headless `claude -p` CLI has no custom-tool channel without an MCP server). It is a harness
# property recorded per episode as tool_protocol, not an arm difference: all arms share it.
#
# SEEDS. Neither the Anthropic API nor the claude CLI exposes a sampling seed. `seed` is therefore the replicate
# index (1..K) and is recorded as such; replicate variance is provider sampling noise, not a seeded draw.
#
# BACKENDS
#   stub        scripted replies + synthetic usage, no network: the gate's model.
#   claude-cli  `claude -p --model M --effort E --tools "" --setting-sources "" --strict-mcp-config ...` in an
#               empty cwd with ripwire stripped from PATH; credential = the locally logged-in CLI. Usage comes from
#               the `--output-format json` trailer (bench/agentloop/cost_accounting.py's claude-code-p cells).
#
# NEVER: read, print or store a key or token value; print gold; touch a held-out row in a pilot.
import argparse, fnmatch, hashlib, json, os, pathlib, re, subprocess, sys, tempfile, time

HERE = pathlib.Path( __file__ ).resolve().parent
sys.path.insert( 0, str( HERE ) )
import run_locbench as rl

try:   # one definition of the four-cell split when the shared module is present (lane/eval-accounting)
    sys.path.insert( 0, str( HERE.parent / "agentloop" ) )
    from cost_accounting import claude_trailer_accounting as _shared_trailer   # type: ignore
except Exception:
    _shared_trailer = None

MAX_TURNS = 15
INPUT_TOKEN_GUARD = 250_000
TOOL_RESULT_CAP = 8_000
SUBMIT_MAX = 10
GREP_TIMEOUT_S = 60

# arm id -> payload file stem in the seal (None = no payload). A0..A3 primary, A2s/A1p secondary (prereg "Arms").
ARMS = { "A0": None, "A1": "for-matched", "A2": "placebo", "A3": "lexical", "A2s": "placebo-shuffle", "A1p": "for-production" }
PRIMARY_ARMS = ( "A0", "A1", "A2", "A3" )

# Haiku 5.5 first-party price table cached 2026-11-03 (PREREG_PLACEBO.md): $0.10 in / $0.50 out per MTok. Cache
# write/read are NOT in that table: the standard 1.25x / 0.10x input multipliers are ASSUMED and named here.
PRICES = { "claude-haiku-5-5": dict( input=0.10, output=0.50, cache_write=0.125, cache_read=0.010 ) }
PREREG_CENTRAL_USD_PER_EPISODE = { "claude-haiku-5-5": 0.0096 }

SYSTEM_PROMPT = """You localize the code that must be edited to resolve a GitHub issue. The repository is checked out read-only at the commit the issue was filed against.

Each turn, reply with exactly ONE JSON object and nothing else. The available actions:
  {"tool": "grep", "pattern": "<Perl-compatible regex>", "path_glob": "<glob such as **/*.py, or empty for all files>"}
  {"tool": "read", "path": "<repo-relative path>", "start": <first line, 1-based>, "end": <last line>}
  {"tool": "submit", "locations": ["path/to/file.py:function", "path/to/file.py:Class.method", ...]}

Rules:
- Tool results are cut at 8000 bytes; a cut is marked.
- You have at most 15 turns in total. Submitting ends the episode.
- Submit up to 10 locations, most likely first. A location is a repo-relative file path, a colon, and the function name; prefix a method with its class name and a dot.
- If the last turn arrives without a submit, the episode scores as a miss."""

PAYLOAD_PREAMBLE = ( "A code-retrieval tool returned the ranked candidates below for this issue. "
                     "They may or may not be relevant.\n" )

class SealBroken( Exception ):
    pass

# ── the seal ─────────────────────────────────────────────────────────────────
def instance_dir( payload_root, instance_id ):
    return pathlib.Path( payload_root ) / instance_id.replace( "/", "__" )

def load_payload( payload_root, instance_id, arm ):
    """-> (text|None, sha256|None, bytes). Verifies the payload against its instance manifest; raises SealBroken."""
    stem = ARMS[arm]
    if stem is None:
        return None, None, 0
    d = instance_dir( payload_root, instance_id )
    try:
        manifest = json.loads( ( d / "manifest.json" ).read_text() )
        data = ( d / f"{stem}.xml" ).read_bytes()
    except ( OSError, ValueError ) as e:
        raise SealBroken( f"{instance_id}/{arm}: unreadable seal ({type( e ).__name__})" )
    entry = manifest.get( stem ) or {}
    digest = hashlib.sha256( data ).hexdigest()
    if entry.get( "sha256" ) != digest or entry.get( "bytes" ) != len( data ):
        raise SealBroken( f"{instance_id}/{arm}: payload does not match its manifest" )
    return data.decode( "utf-8" ), digest, len( data )

def seal_digest( payload_root ):
    """PREREG 'Payload seal': SHA-256 of the sorted concatenation of every per-instance manifest.json."""
    manifests = sorted( pathlib.Path( payload_root ).glob( "*/manifest.json" ), key=lambda p: p.parent.name )
    h = hashlib.sha256()
    for m in manifests:
        h.update( m.read_bytes() )
    return h.hexdigest(), len( manifests )

# ── isolation ────────────────────────────────────────────────────────────────
def clean_path( path_value ):
    """PATH with every directory that holds a `ripwire` entry removed (the agent never reaches the binary)."""
    keep = []
    for d in ( path_value or "" ).split( os.pathsep ):
        if d and not os.path.exists( os.path.join( d, "ripwire" ) ):
            keep.append( d )
    return os.pathsep.join( keep )

def child_env():
    env = dict( os.environ )
    env["PATH"] = clean_path( env.get( "PATH", "" ) )
    for k in ( "RIPWIRE", "RIPWIRE_BIN" ):
        env.pop( k, None )
    return env

# ── tools ────────────────────────────────────────────────────────────────────
def cap( text, limit=TOOL_RESULT_CAP ):
    data = text.encode( "utf-8" )
    if len( data ) <= limit:
        return text
    kept = data[:limit].decode( "utf-8", errors="ignore" )
    return kept + f"\n[cut: {len( data ) - len( kept.encode( 'utf-8' ) )} more bytes not shown]"

def tracked_files( repo ):
    r = subprocess.run( [ "git", "ls-files", "-z" ], cwd=repo, capture_output=True, timeout=GREP_TIMEOUT_S )
    return { p for p in r.stdout.decode( "utf-8", errors="replace" ).split( "\0" ) if p }

def tool_grep( repo, pattern, path_glob ):
    if not isinstance( pattern, str ) or not pattern:
        return "error: grep needs a non-empty pattern"
    args = [ "git", "grep", "-n", "-I", "-P", "--no-color", "-e", pattern ]   # Perl-compatible: \w and \b work
    if isinstance( path_glob, str ) and path_glob.strip():
        args += [ "--", f":(glob){path_glob.strip()}" ]
    try:
        r = subprocess.run( args, cwd=repo, capture_output=True, timeout=GREP_TIMEOUT_S )
    except subprocess.TimeoutExpired:
        return f"error: grep timed out after {GREP_TIMEOUT_S}s"
    out = r.stdout.decode( "utf-8", errors="replace" )
    if r.returncode == 1 and not out:
        return "no matches"
    if r.returncode not in ( 0, 1 ):
        return "error: " + r.stderr.decode( "utf-8", errors="replace" ).strip()[:500]
    return cap( out )

def tool_read( repo, path, start, end, tracked ):
    if not isinstance( path, str ) or not path:
        return "error: read needs a path"
    rel = rl.norm_path( path.strip() )
    if rel not in tracked:
        return f"error: {rel} is not a tracked file of this checkout"
    try:
        lines = ( pathlib.Path( repo ) / rel ).read_text( encoding="utf-8", errors="replace" ).splitlines()
    except OSError as e:
        return f"error: {type( e ).__name__}"
    s = start if isinstance( start, int ) and start >= 1 else 1
    e = end if isinstance( end, int ) and end >= s else len( lines )
    body = "\n".join( f"{i}: {lines[i - 1]}" for i in range( s, min( e, len( lines ) ) + 1 ) )
    return cap( f"{rel} lines {s}-{min( e, len( lines ) )} of {len( lines )}\n{body}" )

# ── protocol ─────────────────────────────────────────────────────────────────
def parse_action( text ):
    """First '{' at which a whole JSON object decodes -> that dict, or None (an invalid turn)."""
    text = text or ""
    dec = json.JSONDecoder()
    for i, ch in enumerate( text ):
        if ch == "{":
            try:
                obj, _ = dec.raw_decode( text, i )
            except ValueError:
                continue
            if isinstance( obj, dict ):
                return obj
    return None

def render_prompt( query, payload, history, turn ):
    parts = [ f"<issue>\n{query}\n</issue>\n" ]
    if payload is not None:
        parts.append( PAYLOAD_PREAMBLE + f"<retrieved>\n{payload}\n</retrieved>\n" )
    for h in history:
        parts.append( f"<turn n=\"{h['turn']}\">\n<you>{h['reply']}</you>\n<result>\n{h['result']}\n</result>\n</turn>\n" )
    left = MAX_TURNS - turn + 1
    parts.append( "This is your FINAL turn: reply with a submit action now." if left == 1
                  else f"Turn {turn} of {MAX_TURNS}. Reply with one JSON action." )
    return "".join( parts )

def normalize_locations( locs ):
    out = []
    if not isinstance( locs, list ):
        return out
    for x in locs:
        if isinstance( x, str ) and ":" in x and x.strip() not in out:
            out.append( x.strip() )
        if len( out ) == SUBMIT_MAX:
            break
    return out

# ── backends ─────────────────────────────────────────────────────────────────
def empty_usage():
    return dict( split_uncached_in=None, split_cache_write=None, split_cache_read=None, split_output=None )

class StubModel:
    """Scripted replies, synthetic usage. `script` is a list of reply strings, or a callable(prompt, turn)->str."""
    credential = "none (stub)"
    tool_protocol = "text-json"
    def __init__( self, script, model="stub-model", usage_per_call=( 1000, 0, 0, 50 ) ):
        self.script, self.model, self.prompts = script, model, []
        self.usage = dict( zip( empty_usage(), usage_per_call ) )   # synthetic, per call, in SPLIT order
    def call( self, system, prompt, turn ):
        self.prompts.append( prompt )
        reply = self.script( prompt, turn ) if callable( self.script ) else ( self.script[turn - 1] if turn <= len( self.script ) else "" )
        return dict( text=reply, usage=dict( self.usage ), cost_usd=None, resolved_models=[ self.model ], raw=json.dumps( dict( stub=True, reply=reply ) ), error=None )

class ClaudeCLI:
    """Headless `claude -p` with no tools, no settings, no MCP, no slash commands, an empty cwd and no ripwire on
    PATH. The credential is whatever the CLI is logged in with; it is named, never read."""
    credential = "claude-cli-login (headless claude -p)"
    tool_protocol = "text-json"
    def __init__( self, model, effort="low", claude_bin="claude", timeout_s=600 ):
        self.model, self.effort, self.claude_bin, self.timeout_s = model, effort, claude_bin, timeout_s
        self.cwd = tempfile.mkdtemp( prefix="plive_agentcwd_" )
    def argv( self, system ):
        return [ self.claude_bin, "-p", "--model", self.model, "--effort", self.effort, "--tools", "",
                 "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence",
                 "--exclude-dynamic-system-prompt-sections", "--system-prompt", system, "--output-format", "json" ]
    def call( self, system, prompt, turn ):
        try:
            r = subprocess.run( self.argv( system ), input=prompt, capture_output=True, text=True, errors="replace",
                                cwd=self.cwd, env=child_env(), timeout=self.timeout_s )
        except subprocess.TimeoutExpired:
            return dict( text="", usage=empty_usage(), cost_usd=None, resolved_models=[], raw="", error="timeout" )
        return parse_cli_trailer( r.stdout, r.returncode )

def parse_cli_trailer( stdout, returncode=0 ):
    try:
        d = json.loads( stdout or "" )
    except ValueError:
        d = None
    if not isinstance( d, dict ):
        return dict( text="", usage=empty_usage(), cost_usd=None, resolved_models=[], raw=stdout or "", error=f"unparseable trailer rc={returncode}" )
    if _shared_trailer is not None:
        acc = _shared_trailer( stdout )
        usage = { k: acc.get( k ) for k in empty_usage() }
    else:
        u = d.get( "usage" ) or {}
        num = lambda v: v if isinstance( v, int ) and not isinstance( v, bool ) else None
        usage = dict( split_uncached_in=num( u.get( "input_tokens" ) ), split_cache_write=num( u.get( "cache_creation_input_tokens" ) ),
                      split_cache_read=num( u.get( "cache_read_input_tokens" ) ), split_output=num( u.get( "output_tokens" ) ) )
    err = None
    if d.get( "is_error" ) or returncode != 0:
        err = f"provider error rc={returncode}: {str( d.get( 'result' ) )[:200]}"
    cost = d.get( "total_cost_usd" )
    return dict( text=d.get( "result" ) or "", usage=usage, cost_usd=cost if isinstance( cost, ( int, float ) ) else None,
                 resolved_models=sorted( ( d.get( "modelUsage" ) or {} ).keys() ), raw=stdout, error=err )

# ── scoring (the same file_ranks / func_ranks as the payload-only scorer) ────
def submission_candidates( locations ):
    out = []
    for loc in locations:
        path, _, fn = loc.partition( ":" )
        parts = [ p for p in re.split( r"\.|::", fn.strip() ) if p ]
        if not parts:
            continue
        out.append( dict( path=rl.norm_path( path.strip() ), name=parts[-1], canon="::".join( [ path.strip() ] + parts ), rank=len( out ) + 1 ) )
    return out

def score_submission( locations, covered, primary_files, universe_files ):
    cands = submission_candidates( locations )
    files = rl.ranked_files_from_candidates( cands )
    franks = rl.file_ranks( files, primary_files, universe_files )
    nranks = rl.func_ranks( cands, [ tuple( c ) for c in covered ], universe_files ) if covered else []
    ff, fh = rl.first_hit( franks ), rl.first_hit( nranks )
    return dict( func_hit10=int( fh is not None and fh < 10 ), file_hit5=int( ff is not None and ff < 5 ),
                 strict_file10=rl.acc_all_at( franks, 10 ), strict_func10=rl.acc_all_at( nranks, 10 ) )

def price_usd( model, usage ):
    p = PRICES.get( model )
    if not p or any( usage.get( k ) is None for k in usage ):
        return None
    return ( usage["split_uncached_in"] * p["input"] + usage["split_cache_write"] * p["cache_write"]
             + usage["split_cache_read"] * p["cache_read"] + usage["split_output"] * p["output"] ) / 1e6

# ── one episode ──────────────────────────────────────────────────────────────
def run_episode( backend, inst, arm, seed, payload_root, repo, transcript_dir, gold=None, max_retries=3 ):
    """inst: dict(instance_id, query). gold: dict(covered, primary_files, universe_files) or None (unscored)."""
    t0 = time.perf_counter()
    payload, payload_sha, payload_bytes = load_payload( payload_root, inst["instance_id"], arm )   # SealBroken propagates
    tracked = tracked_files( repo )
    totals = dict( split_uncached_in=0, split_cache_write=0, split_cache_read=0, split_output=0 )
    unreported = set()
    tools = dict( grep=0, read=0, submit=0, invalid=0, refused=0 )
    history, transcript, resolved, cost_cli = [], [], set(), 0.0
    cost_cli_known, submitted, stop, provider_errors = True, None, "turns", 0
    turn = 0
    for turn in range( 1, MAX_TURNS + 1 ):
        prompt = render_prompt( inst["query"], payload, history, turn )
        resp = None
        for attempt in range( max_retries + 1 ):
            resp = backend.call( SYSTEM_PROMPT, prompt, turn )
            if not resp["error"]:
                break
            provider_errors += 1
        transcript.append( dict( turn=turn, prompt_sha256=hashlib.sha256( prompt.encode() ).hexdigest(), prompt_bytes=len( prompt.encode() ),
                                 reply=resp["text"], usage=resp["usage"], resolved_models=resp["resolved_models"], error=resp["error"],
                                 raw=resp["raw"] ) )
        resolved.update( resp["resolved_models"] )
        for k, v in resp["usage"].items():
            if v is None:
                unreported.add( k )
            else:
                totals[k] += v
        if resp["cost_usd"] is None:
            cost_cli_known = False
        else:
            cost_cli += resp["cost_usd"]
        if resp["error"]:
            stop = "provider_error"
            break
        action = parse_action( resp["text"] )
        kind = action.get( "tool" ) if action else None
        final = turn == MAX_TURNS
        if kind == "submit":
            tools["submit"] += 1
            submitted = normalize_locations( action.get( "locations" ) )
            stop = "submit"
            break
        if final:
            result = "error: final turn ended without submit"
            tools["refused" if kind in ( "grep", "read" ) else "invalid"] += 1
        elif kind == "grep":
            tools["grep"] += 1
            result = tool_grep( repo, action.get( "pattern" ), action.get( "path_glob", "" ) )
        elif kind == "read":
            tools["read"] += 1
            result = tool_read( repo, action.get( "path" ), action.get( "start" ), action.get( "end" ), tracked )
        else:
            tools["invalid"] += 1
            result = 'error: reply was not one JSON action with "tool" set to grep, read or submit'
        history.append( dict( turn=turn, reply=resp["text"].strip(), result=result ) )
        transcript[-1]["tool_result"] = result
        cum_in = totals["split_uncached_in"] + totals["split_cache_write"] + totals["split_cache_read"]
        if cum_in >= INPUT_TOKEN_GUARD:
            stop = "input_token_guard"
            break
    usage = { k: ( None if k in unreported else v ) for k, v in totals.items() }
    rec = dict( instance_id=inst["instance_id"], arm=arm, payload_arm=ARMS[arm], seed=seed, seed_kind="replicate index (provider exposes no sampling seed)",
                model=getattr( backend, "model", None ), resolved_model=sorted( resolved ), credential=backend.credential,
                tool_protocol=backend.tool_protocol, system_prompt_sha256=hashlib.sha256( SYSTEM_PROMPT.encode() ).hexdigest(),
                payload_sha256=payload_sha, payload_bytes=payload_bytes, turns=turn, stop=stop, submitted=submitted is not None,
                submitted_list=submitted or [], tool_calls=tools, provider_errors=provider_errors, **usage,
                input_tokens=( None if unreported & { "split_uncached_in", "split_cache_write", "split_cache_read" }
                               else usage["split_uncached_in"] + usage["split_cache_write"] + usage["split_cache_read"] ),
                output_tokens=usage["split_output"],
                cost_usd_cli=round( cost_cli, 6 ) if cost_cli_known else None,
                cost_usd_prereg_prices=price_usd( getattr( backend, "model", None ), usage ),
                wall_s=round( time.perf_counter() - t0, 3 ) )
    if gold is not None:
        rec.update( score_submission( submitted or [], gold["covered"], gold["primary_files"], gold["universe_files"] ) )
    if transcript_dir:
        tp = pathlib.Path( transcript_dir ) / f"{inst['instance_id'].replace( '/', '__' )}.{arm}.s{seed}.json"
        tp.parent.mkdir( parents=True, exist_ok=True )
        tp.write_text( json.dumps( dict( record={ k: v for k, v in rec.items() if k not in ( "func_hit10", "file_hit5", "strict_file10", "strict_func10" ) },
                                         system_prompt=SYSTEM_PROMPT, turns=transcript ), indent=1 ) )
        rec["transcript"] = str( tp )
    return rec

# ── pilot selection and analysis ─────────────────────────────────────────────
def select_pilot( rows, n=24 ):
    """PREREG: 24 TRAIN instances, repo round-robin by instance_id order. Repos in sorted order, each repo's
    instances in instance_id order, one per repo per round. Never reads gold."""
    by_repo = {}
    for r in rows:
        if rl.frozen_partition( r["repo"] ) == "train":
            by_repo.setdefault( r["repo"], [] ).append( r["instance_id"] )
    queues = [ sorted( by_repo[k] ) for k in sorted( by_repo ) ]
    out, depth = [], 0
    while len( out ) < n and any( depth < len( q ) for q in queues ):
        for q in queues:
            if depth < len( q ) and len( out ) < n:
                out.append( q[depth] )
        depth += 1
    return out

def discordance( records, a="A1", b="A2" ):
    """d = share of instances whose seed-mean hit differs between arms a and b (the prereg's paired-discordance
    input). Returns (d, n_pairs). Uses only per-instance disagreement, never the signed difference."""
    per = {}
    for r in records:
        if r["arm"] in ( a, b ) and "func_hit10" in r:
            per.setdefault( r["instance_id"], {} ).setdefault( r["arm"], [] ).append( r["func_hit10"] )
    pairs = [ ( sum( v[a] ) / len( v[a] ), sum( v[b] ) / len( v[b] ) ) for v in per.values() if a in v and b in v ]
    if not pairs:
        return None, 0
    return sum( abs( x - y ) for x, y in pairs ) / len( pairs ), len( pairs )

def holm_mde_pp( d, k, seed_share=0.5, n=243, deff_sqrt=1.051, z_alpha=2.128, z_power=0.842 ):
    """PREREG power arithmetic with delta^2 dropped (the effect-free upper bound on d - delta^2)."""
    var = d * ( seed_share + ( 1.0 - seed_share ) / k )
    return 100.0 * ( z_alpha + z_power ) * ( var ** 0.5 ) * deff_sqrt / ( n ** 0.5 )

# ── CLI ──────────────────────────────────────────────────────────────────────
def load_rows( work_dir ):
    cache = pathlib.Path( work_dir ) / "datasets" / "rows_czlll__Loc-Bench_V1_test_560.json"
    return json.loads( cache.read_text() )

def main():
    ap = argparse.ArgumentParser( description="LocBench placebo round agent driver (PREREG_PLACEBO.md)" )
    ap.add_argument( "--work-dir", required=True, help="run_locbench.py work dir (dataset cache + repos)" )
    ap.add_argument( "--select-pilot", action="store_true", help="print the 24 pilot TRAIN instance ids and exit" )
    ap.add_argument( "--payloads", default="", help="the --emit-payloads seal dir" )
    ap.add_argument( "--seal-json", default="", help="run_locbench --json-out of the seal run (scoring sidecar)" )
    ap.add_argument( "--instances", default="", help="@FILE or comma list; default: every instance in --seal-json" )
    ap.add_argument( "--arms", default=",".join( PRIMARY_ARMS ) )
    ap.add_argument( "--seeds", type=int, default=1 )
    ap.add_argument( "--backend", default="claude-cli", choices=[ "claude-cli" ] )
    ap.add_argument( "--model", default="claude-haiku-5-5" )
    ap.add_argument( "--effort", default="low" )
    ap.add_argument( "--claude-bin", default="claude" )
    ap.add_argument( "--out", required=True, help="results dir: episodes.jsonl + transcripts/" )
    ap.add_argument( "--cost-check-after", type=int, default=12 )
    ap.add_argument( "--cost-stop-multiple", type=float, default=2.0 )
    ap.add_argument( "--allow-heldout", action="store_true", help="refused unless set; the pilot never sets it" )
    a = ap.parse_args()

    rows = load_rows( a.work_dir )
    if a.select_pilot:
        print( "\n".join( select_pilot( rows ) ) )
        return 0
    by_id = { r["instance_id"]: r for r in rows }
    seal = json.loads( pathlib.Path( a.seal_json ).read_text() )
    sidecar = { x["instance_id"]: x for x in seal["instances"] }
    if a.instances:
        spec = pathlib.Path( a.instances[1:] ).read_text() if a.instances.startswith( "@" ) else a.instances
        ids = [ x.strip() for x in spec.replace( ",", "\n" ).splitlines() if x.strip() ]
    else:
        ids = sorted( sidecar )
    for iid in ids:
        if rl.frozen_partition( by_id[iid]["repo"] ) != "train" and not a.allow_heldout:
            raise SystemExit( "refused: a held-out instance in a run without --allow-heldout" )
        if iid not in sidecar:
            raise SystemExit( f"refused: {len( [ i for i in ids if i not in sidecar ] )} instance(s) have no seal row (zero-silent-skip)" )
    arms = [ x.strip() for x in a.arms.split( "," ) if x.strip() ]
    backend = ClaudeCLI( a.model, a.effort, a.claude_bin )
    out = pathlib.Path( a.out ); out.mkdir( parents=True, exist_ok=True )
    digest, n_manifests = seal_digest( a.payloads )
    ( out / "run_meta.json" ).write_text( json.dumps( dict( model=a.model, effort=a.effort, backend=a.backend, credential=backend.credential,
        tool_protocol=backend.tool_protocol, arms=arms, seeds=a.seeds, instances=len( ids ), payload_seal_sha256=digest,
        payload_manifests=n_manifests, system_prompt_sha256=hashlib.sha256( SYSTEM_PROMPT.encode() ).hexdigest(),
        max_turns=MAX_TURNS, input_token_guard=INPUT_TOKEN_GUARD, tool_result_cap=TOOL_RESULT_CAP ), indent=2 ) )
    done = 0
    # episode order: instance-major, arms rotated by instance hash so no arm is always first (provider drift)
    with open( out / "episodes.jsonl", "a" ) as fh:
        for iid in ids:
            inst = by_id[iid]
            repo = rl.checkout( inst["repo"], inst["base_commit"], pathlib.Path( a.work_dir ) / "repos" )
            if repo is None:
                raise SystemExit( f"{iid}: CHECKOUT FAIL (zero-silent-skip)" )
            query = " ".join( inst.get( "problem_statement", "" ).split() )[:1200]
            sc = sidecar[iid]
            gold = dict( covered=sc["covered"], primary_files=sc["primary_files"], universe_files=sc["universe_files"] )
            rot = hashlib.sha256( iid.encode() ).digest()[0] % len( arms )
            for seed in range( 1, a.seeds + 1 ):
                for arm in arms[rot:] + arms[:rot]:
                    rec = run_episode( backend, dict( instance_id=iid, query=query ), arm, seed, a.payloads, repo, out / "transcripts", gold )
                    fh.write( json.dumps( rec ) + "\n" ); fh.flush()
                    done += 1
                    print( f"# episode {done}: arm={arm} turns={rec['turns']} stop={rec['stop']} cost_cli={rec['cost_usd_cli']}", file=sys.stderr )
                    if done == a.cost_check_after:
                        recs = [ json.loads( l ) for l in open( out / "episodes.jsonl" ) ]
                        costs = [ r["cost_usd_cli"] if r["cost_usd_cli"] is not None else r["cost_usd_prereg_prices"] for r in recs ]
                        known = [ c for c in costs if c is not None ]
                        central = PREREG_CENTRAL_USD_PER_EPISODE.get( a.model )
                        if not known or central is None:
                            raise SystemExit( "COST GUARD: no realised cost is measurable after the check episodes; stopping" )
                        per = sum( known ) / len( known )
                        print( f"# cost guard: {per:.5f} USD/episode over {len( known )} vs central {central}", file=sys.stderr )
                        if per > a.cost_stop_multiple * central:
                            raise SystemExit( f"COST GUARD STOP: {per:.5f} USD/episode > {a.cost_stop_multiple}x central {central}" )
    return 0

if __name__ == "__main__":
    sys.exit( main() )
