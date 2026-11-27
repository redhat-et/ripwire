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
# the same central estimate in tokens (PREREG "Live-round cost estimate": ~80K input, 3.2K output per episode)
PREREG_CENTRAL_TOKENS = dict( input=80_000, output=3_200 )

def cost_guard( records, model, multiple ):
    """-> (stop: bool, summary dict). The realised per-episode usage priced at the PREREG's own table (tokens x
    prereg prices, so a subscription run is judged on tokens, not on a bill) against multiple x the central
    $/episode. Unpriceable usage (a cell unreported) stops the run: an unmeasured cost is not a cheap one."""
    priced = [ r["cost_usd_prereg_prices"] for r in records ]
    n = len( records )
    ins = [ r["input_tokens"] for r in records if r["input_tokens"] is not None ]
    outs = [ r["output_tokens"] for r in records if r["output_tokens"] is not None ]
    summary = dict( episodes=n, mean_input_tokens=( sum( ins ) / len( ins ) if ins else None ),
                    mean_output_tokens=( sum( outs ) / len( outs ) if outs else None ),
                    central_input_tokens=PREREG_CENTRAL_TOKENS["input"], central_output_tokens=PREREG_CENTRAL_TOKENS["output"] )
    central = PREREG_CENTRAL_USD_PER_EPISODE.get( model )
    if not n or central is None or any( c is None for c in priced ):
        summary["reason"] = "usage not priceable for every check episode"
        return True, summary
    per = sum( priced ) / n
    summary.update( prereg_priced_usd_per_episode=per, central_usd_per_episode=central, multiple=per / central )
    return per > multiple * central, summary

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
    def __init__( self, model, effort="low", claude_bin="claude", timeout_s=600, credential=None ):
        self.model, self.effort, self.claude_bin, self.timeout_s = model, effort, claude_bin, timeout_s
        if credential:
            self.credential = credential
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

# ── held-out run discipline (PREREG_PLACEBO.md ADDENDUM, owner rulings 2026-11-26) ──
SECONDARY_ARMS = ( "A2s", "A1p" )
PILOT_MEAN_INPUT_TOKENS = 33_525          # the TRAIN pilot's realised mean input per episode
ROLLING_WINDOW = 50
EXIT_COST_GUARD, EXIT_ROLLING, EXIT_PROVIDER = 3, 4, 5

def plan_episodes( ids, arms, seeds, secondary_arms=(), secondary_seeds=1 ):
    """Instance-major list of (instance_id, arm, seed). Arms rotate by instance hash so no arm is always first."""
    plan = []
    for iid in ids:
        rot = hashlib.sha256( iid.encode() ).digest()[0] % len( arms )
        for seed in range( 1, seeds + 1 ):
            plan += [ ( iid, arm, seed ) for arm in arms[rot:] + arms[:rot] ]
        for seed in range( 1, secondary_seeds + 1 ):
            plan += [ ( iid, arm, seed ) for arm in secondary_arms ]
    return plan

def repo_groups( plan, repo_of ):
    """plan -> [(repo, [episodes...])], first-appearance order. One repo's episodes run in ONE worker, in order,
    because a checkout holds one base_commit at a time."""
    groups = {}
    for ep in plan:
        groups.setdefault( repo_of[ep[0]], [] ).append( ep )
    return list( groups.items() )

def rolling_stop( records, window=ROLLING_WINDOW, limit=2 * PILOT_MEAN_INPUT_TOKENS ):
    """-> (stop, mean) over the last `window` records' input tokens; never fires before `window` records.
    An unreported input total counts as over the limit (unmeasured is not cheap)."""
    if len( records ) < window:
        return False, None
    last = [ r.get( "input_tokens" ) for r in records[-window:] ]
    if any( v is None for v in last ):
        return True, None
    mean = sum( last ) / window
    return mean > limit, mean

def attempt_episode( run_once ):
    """Owner ruling: an episode that ends on a provider error is re-run ONCE and the error is never counted.
    -> (record, None) on success, or (None, last_error_record) when the re-run also failed (the caller stops)."""
    last = None
    for attempt in range( 2 ):
        rec = run_once()
        if rec["stop"] != "provider_error":
            rec["reruns"] = attempt
            return rec, None
        last = rec
    return None, last

class Runner:
    """Thread pool over repo groups. Appends each finished record to episodes.jsonl under a lock, applies the
    12-episode cost guard and the rolling token stop, and stops every worker after the episode in flight."""
    def __init__( self, out, model, cost_check_after=12, cost_stop_multiple=2.0, window=ROLLING_WINDOW,
                  rolling_limit=2 * PILOT_MEAN_INPUT_TOKENS ):
        import threading
        self.out, self.model = pathlib.Path( out ), model
        self.lock, self.stop_code = threading.Lock(), 0
        self.cost_check_after, self.cost_stop_multiple = cost_check_after, cost_stop_multiple
        self.window, self.rolling_limit = window, rolling_limit
        self.ep_path = self.out / "episodes.jsonl"
        self.records = [ json.loads( l ) for l in open( self.ep_path ) ] if self.ep_path.exists() else []
        self.finished = { ( r["instance_id"], r["arm"], r["seed"] ) for r in self.records }
        self.run_count = 0          # episodes finished in THIS invocation (the guards look at this run's records)
    def note( self, rec, err ):
        with self.lock:
            if err is not None:
                with open( self.out / "provider_errors.jsonl", "a" ) as fh:
                    fh.write( json.dumps( { k: err[k] for k in ( "instance_id", "arm", "seed", "stop", "turns" ) } ) + "\n" )
                self.stop_code = self.stop_code or EXIT_PROVIDER
                return
            with open( self.ep_path, "a" ) as fh:
                fh.write( json.dumps( rec ) + "\n" )
            self.records.append( rec ); self.run_count += 1
            print( f"# episode {len( self.records )}: arm={rec['arm']} seed={rec['seed']} turns={rec['turns']} stop={rec['stop']}", file=sys.stderr )
            mine = self.records[-self.run_count:]
            if self.run_count == self.cost_check_after:
                stop, summary = cost_guard( mine, self.model, self.cost_stop_multiple )
                ( self.out / "cost_guard.json" ).write_text( json.dumps( summary, indent=2 ) )
                print( f"# cost guard after {self.run_count} episodes: {json.dumps( summary )}", file=sys.stderr )
                if stop:
                    self.stop_code = self.stop_code or EXIT_COST_GUARD
            stop, mean = rolling_stop( mine, self.window, self.rolling_limit )
            if stop:
                ( self.out / "rolling_stop.json" ).write_text( json.dumps( dict( window=self.window, mean_input=mean, limit=self.rolling_limit ) ) )
                self.stop_code = self.stop_code or EXIT_ROLLING
    def run( self, groups, run_group_episode, workers=1 ):
        """run_group_episode(episode) -> (rec, err); called in order within a group."""
        from concurrent.futures import ThreadPoolExecutor
        def work( group ):
            for ep in group[1]:
                if self.stop_code:
                    return
                if ep in self.finished:
                    continue
                rec, err = run_group_episode( ep )
                self.note( rec, err )
        with ThreadPoolExecutor( max_workers=max( 1, workers ) ) as pool:
            list( pool.map( work, groups ) )
        return self.stop_code

# ── grading (the ONLY place gold is read) and the B1-B3 analysis ─────────────
BOOT_SEED = "ripwire-placebo-v1"

def grade_sidecar( inst, repo, rich_cache, dataset="locbench" ):
    """Gold + coverage universe for one instance, exactly as run_locbench scores it. Never printed."""
    query = " ".join( inst.get( "problem_statement", "" ).split() )[:1200]
    gold_files, gold_funcs, _ = rl.gold_for_instance( inst, dataset )
    uni_xml, _, rc = rl.run_ctx( repo, [ f"--query={query}", "--format=candidates", "--top-k=1000000000", f"--cache={rich_cache}" ] )
    uni = rl.parse_candidates( uni_xml, repo ) if rc == 0 and uni_xml else []
    if not uni:
        raise SystemExit( f"{inst['instance_id']}: grading universe failed (zero-silent-skip)" )
    universe_files = sorted( { c["path"] for c in uni } )
    primary = sorted( f for f in gold_files if rl.norm_path( f ) in universe_files )
    return dict( covered=rl.covered( uni, gold_funcs, universe_files ), primary_files=primary, universe_files=universe_files )

def seed_means( records, key="func_hit10" ):
    per = {}
    for r in records:
        per.setdefault( r["instance_id"], {} ).setdefault( r["arm"], [] ).append( r[key] )
    return { i: { arm: sum( v ) / len( v ) for arm, v in arms.items() } for i, arms in per.items() }

def cluster_bootstrap( diffs, repo_of, n_boot=10_000, seed=BOOT_SEED ):
    """Repository-clustered paired bootstrap (the compare_runs.py house pattern). diffs: {instance: value}.
    -> dict(mean, lb95_one_sided, ci95=(lo, hi)). Deterministic: one fixed-seed RNG, sorted repos."""
    import random
    ids = sorted( diffs )
    repos = sorted( { repo_of[i] for i in ids } )
    by_repo = { r: [ i for i in ids if repo_of[i] == r ] for r in repos }
    rng = random.Random( seed )
    boots = []
    for _ in range( n_boot ):
        vals = [ diffs[i] for r in ( rng.choice( repos ) for _ in repos ) for i in by_repo[r] ]
        boots.append( sum( vals ) / len( vals ) )
    boots.sort()
    q = lambda p: boots[ min( len( boots ) - 1, max( 0, int( p * len( boots ) ) ) ) ]
    return dict( mean=sum( diffs.values() ) / len( diffs ), lb95_one_sided=q( 0.05 ), ci95=( q( 0.025 ), q( 0.975 ) ),
                 n=len( ids ), clusters=len( repos ) )

def contrast( means, a, b, repo_of, subset=None, n_boot=10_000 ):
    ids = [ i for i in sorted( means ) if a in means[i] and b in means[i] and ( subset is None or i in subset ) ]
    return cluster_bootstrap( { i: means[i][a] - means[i][b] for i in ids }, repo_of, n_boot )

def majority_misses( records, a="A0", b="A1" ):
    """B3 counts: instances a hits in a seed-majority and b misses in a seed-majority, and the reverse."""
    per = {}
    for r in records:
        per.setdefault( r["instance_id"], {} ).setdefault( r["arm"], [] ).append( r["func_hit10"] )
    maj = lambda v: sum( v ) * 2 > len( v )
    ab = sum( 1 for v in per.values() if a in v and b in v and maj( v[a] ) and not maj( v[b] ) )
    ba = sum( 1 for v in per.values() if a in v and b in v and maj( v[b] ) and not maj( v[a] ) )
    return ab, ba

def analyze( records, repo_of, single_ids, n_boot=10_000 ):
    """PREREG bars B1-B3 for one model (Holm over one model = the unadjusted one-sided 95% bound)."""
    means = seed_means( records )
    multi_ids = set( means ) - set( single_ids )
    c = { f"{a}-{b}": contrast( means, a, b, repo_of, n_boot=n_boot )
          for a, b in ( ( "A1", "A2" ), ( "A1", "A3" ), ( "A1", "A0" ), ( "A2", "A0" ), ( "A1", "A2s" ), ( "A1", "A1p" ) )
          if any( a in m and b in m for m in means.values() ) }
    s1 = contrast( means, "A1", "A2", repo_of, set( single_ids ), n_boot )
    s2 = contrast( means, "A1", "A2", repo_of, multi_ids, n_boot )
    b1 = c["A1-A2"]
    b1_pass = b1["mean"] >= 0.03 and b1["lb95_one_sided"] > 0 and s1["lb95_one_sided"] > -0.02 and s2["lb95_one_sided"] > -0.02
    b2 = c["A1-A3"]["lb95_one_sided"]
    b2_verdict = "superior" if b2 > 0 else ( "non-inferior" if b2 > -0.03 else "loses" )
    ab, ba = majority_misses( records )
    b3_pass = ab <= ba and c["A1-A0"]["lb95_one_sided"] > -0.02
    return dict( contrasts=c, strata=dict( single=s1, multi=s2 ),
                 B1=dict( pass_=b1_pass, mean=b1["mean"], lb=b1["lb95_one_sided"], single_lb=s1["lb95_one_sided"], multi_lb=s2["lb95_one_sided"] ),
                 B2=dict( verdict=b2_verdict, lb=b2 ), B3=dict( pass_=b3_pass, a0_hits_a1_misses=ab, a1_hits_a0_misses=ba, lb=c["A1-A0"]["lb95_one_sided"] ) )

# ── CLI ──────────────────────────────────────────────────────────────────────
def load_rows( work_dir ):
    cache = pathlib.Path( work_dir ) / "datasets" / "rows_czlll__Loc-Bench_V1_test_560.json"
    return json.loads( cache.read_text() )

def parse_ids( spec ):
    text = pathlib.Path( spec[1:] ).read_text() if spec.startswith( "@" ) else spec
    return [ x.strip() for x in text.replace( ",", "\n" ).splitlines() if x.strip() ]

def cmd_run( a, rows ):
    by_id = { r["instance_id"]: r for r in rows }
    sidecar = { x["instance_id"]: x for x in json.loads( pathlib.Path( a.seal_json ).read_text() )["instances"] } if a.seal_json else None
    ids = parse_ids( a.instances ) if a.instances else sorted( p.parent.name for p in pathlib.Path( a.payloads ).glob( "*/manifest.json" ) )
    for iid in ids:
        if iid not in by_id:
            raise SystemExit( "refused: an instance id is not in the dataset (zero-silent-skip)" )
        if rl.frozen_partition( by_id[iid]["repo"] ) != "train" and not a.allow_heldout:
            raise SystemExit( "refused: a held-out instance in a run without --allow-heldout" )
        if sidecar is not None and iid not in sidecar:
            raise SystemExit( "refused: an instance has no seal row (zero-silent-skip)" )
    arms = [ x.strip() for x in a.arms.split( "," ) if x.strip() ]
    sec = [ x.strip() for x in a.secondary_arms.split( "," ) if x.strip() ]
    backend = ClaudeCLI( a.model, a.effort, a.claude_bin, credential=a.credential or None )
    out = pathlib.Path( a.out ); out.mkdir( parents=True, exist_ok=True )
    digest, n_manifests = seal_digest( a.payloads )
    ( out / "run_meta.json" ).write_text( json.dumps( dict( model=a.model, effort=a.effort, backend=a.backend, credential=backend.credential,
        tool_protocol=backend.tool_protocol, arms=arms, seeds=a.seeds, secondary_arms=sec, secondary_seeds=a.secondary_seeds,
        instances=len( ids ), scored_at_run_time=sidecar is not None, payload_seal_sha256=digest, payload_manifests=n_manifests,
        system_prompt_sha256=hashlib.sha256( SYSTEM_PROMPT.encode() ).hexdigest(), max_turns=MAX_TURNS, input_token_guard=INPUT_TOKEN_GUARD,
        tool_result_cap=TOOL_RESULT_CAP, workers=a.workers, call_retries=a.call_retries ), indent=2 ) )
    repo_of = { iid: by_id[iid]["repo"] for iid in ids }
    groups = repo_groups( plan_episodes( ids, arms, a.seeds, sec, a.secondary_seeds ), repo_of )
    runner = Runner( out, a.model, a.cost_check_after, a.cost_stop_multiple )
    current = {}
    def one( ep ):
        iid, arm, seed = ep
        inst = by_id[iid]
        if current.get( inst["repo"] ) != inst["base_commit"]:
            if rl.checkout( inst["repo"], inst["base_commit"], pathlib.Path( a.work_dir ) / "repos" ) is None:
                raise SystemExit( f"{iid}: CHECKOUT FAIL (zero-silent-skip)" )
            current[inst["repo"]] = inst["base_commit"]
        repo = pathlib.Path( a.work_dir ) / "repos" / inst["repo"].replace( "/", "__" )
        query = " ".join( inst.get( "problem_statement", "" ).split() )[:1200]
        gold = None
        if sidecar is not None:
            sc = sidecar[iid]; gold = dict( covered=sc["covered"], primary_files=sc["primary_files"], universe_files=sc["universe_files"] )
        return attempt_episode( lambda: run_episode( backend, dict( instance_id=iid, query=query ), arm, seed, a.payloads, repo,
                                                     out / "transcripts", gold, max_retries=a.call_retries ) )
    code = runner.run( groups, one, a.workers )
    if code:
        print( { EXIT_COST_GUARD: "COST GUARD STOP", EXIT_ROLLING: "ROLLING TOKEN STOP", EXIT_PROVIDER: "PROVIDER ERROR STOP (resume later)" }[code], file=sys.stderr )
    return code

def cmd_grade( a, rows ):
    """Score an unscored run: gold is read HERE only, written into scored.jsonl as hit flags (no gold content)."""
    by_id = { r["instance_id"]: r for r in rows }
    out = pathlib.Path( a.out )
    recs = [ json.loads( l ) for l in open( out / "episodes.jsonl" ) ]
    ids = sorted( { r["instance_id"] for r in recs } )
    single, side = [], {}
    for iid in sorted( ids, key=lambda i: ( by_id[i]["repo"], i ) ):
        inst = by_id[iid]
        repo = rl.checkout( inst["repo"], inst["base_commit"], pathlib.Path( a.work_dir ) / "repos" )
        cache = pathlib.Path( str( pathlib.Path( a.work_dir ) / "indexes" / iid.replace( "/", "__" ) ) + ".rich.ripwirecache" )
        side[iid] = grade_sidecar( inst, repo, cache )
        if len( side[iid]["primary_files"] ) == 1:
            single.append( iid )
    with open( out / "scored.jsonl", "w" ) as fh:
        for r in recs:
            g = side[r["instance_id"]]
            r = dict( r, **score_submission( r["submitted_list"], g["covered"], g["primary_files"], g["universe_files"] ) )
            fh.write( json.dumps( r ) + "\n" )
    unindexable = sorted( i for i in ids if not side[i]["primary_files"] )
    ( out / "strata.json" ).write_text( json.dumps( dict( single_file=single, unindexable=unindexable, n=len( ids ) ) ) )
    print( f"# graded {len( recs )} episodes over {len( ids )} instances; unindexable={len( unindexable )}", file=sys.stderr )
    return 0

def cmd_analyze( a, rows ):
    out = pathlib.Path( a.out )
    repo_of = { r["instance_id"]: r["repo"] for r in rows }
    strata = json.loads( ( out / "strata.json" ).read_text() )
    drop = set( strata["unindexable"] )      # the prereg's indexability filter, applied in the grader's output only
    recs = [ r for r in ( json.loads( l ) for l in open( out / "scored.jsonl" ) ) if r["instance_id"] not in drop ]
    res = analyze( recs, repo_of, [ i for i in strata["single_file"] if i not in drop ], a.n_boot )
    ( out / "analysis.json" ).write_text( json.dumps( res, indent=2 ) )
    print( json.dumps( dict( B1=res["B1"], B2=res["B2"], B3=res["B3"] ) ) )
    return 0

def main():
    ap = argparse.ArgumentParser( description="LocBench placebo round agent driver (PREREG_PLACEBO.md)" )
    ap.add_argument( "--work-dir", required=True, help="run_locbench.py work dir (dataset cache + repos + indexes)" )
    ap.add_argument( "--select-pilot", action="store_true", help="print the 24 pilot TRAIN instance ids and exit" )
    ap.add_argument( "--grade", action="store_true", help="score --out's episodes (the only step that reads gold)" )
    ap.add_argument( "--analyze", action="store_true", help="B1-B3 over --out's scored.jsonl" )
    ap.add_argument( "--payloads", default="", help="the --emit-payloads seal dir" )
    ap.add_argument( "--seal-json", default="", help="scoring sidecar for a TRAIN run; omit for held-out (graded after)" )
    ap.add_argument( "--instances", default="", help="@FILE or comma list; default: every instance in the seal" )
    ap.add_argument( "--arms", default=",".join( PRIMARY_ARMS ) )
    ap.add_argument( "--seeds", type=int, default=1 )
    ap.add_argument( "--secondary-arms", default="" )
    ap.add_argument( "--secondary-seeds", type=int, default=1 )
    ap.add_argument( "--workers", type=int, default=1, help="parallel repo groups (one repo never runs in two workers)" )
    ap.add_argument( "--call-retries", type=int, default=0, help="per-call retries inside an episode; the episode itself is re-run once" )
    ap.add_argument( "--backend", default="claude-cli", choices=[ "claude-cli" ] )
    ap.add_argument( "--model", default="claude-haiku-5-5" )
    ap.add_argument( "--effort", default="low" )
    ap.add_argument( "--claude-bin", default="claude" )
    ap.add_argument( "--credential", default="", help="the billed credential's NAME for the record (never a value)" )
    ap.add_argument( "--out", required=True, help="results dir: episodes.jsonl + transcripts/" )
    ap.add_argument( "--cost-check-after", type=int, default=12 )
    ap.add_argument( "--cost-stop-multiple", type=float, default=2.0 )
    ap.add_argument( "--n-boot", type=int, default=10_000 )
    ap.add_argument( "--allow-heldout", action="store_true", help="refused unless set; the pilot never sets it" )
    a = ap.parse_args()
    rows = load_rows( a.work_dir )
    if a.select_pilot:
        print( "\n".join( select_pilot( rows ) ) )
        return 0
    if a.grade:
        return cmd_grade( a, rows )
    if a.analyze:
        return cmd_analyze( a, rows )
    return cmd_run( a, rows )

if __name__ == "__main__":
    sys.exit( main() )
