#!/usr/bin/env python3
# Round-4 UNIFIED head-to-head worker — every competitor arm re-run against ONE ripwire binary and
# ONE evaluator, so all arms land in a single number-comparable table.
#
# WHY THIS EXISTS. r1 (2026-07-13/14) scored aider/cbm/graphify; r2 (2026-08-03) scored
# repowise/codeseek against a newer binary and evaluator. Each round is paired within itself and the
# two are NOT number-comparable, so the README had to publish two tables and tell the reader not to
# compare them. This worker re-runs all five competitors under one harness to retire that split.
#
# INHERITED UNMODIFIED from bench/headtohead/r2-2026-08-03/worker.py: the codeseek and repowise arm
# functions, the query construction (issue text, 1200 chars), the universe convention
# (`git ls-files` of the shared checkout), and the ranked-file convention (first appearance of a
# result's file path in the tool's own output order). The metric itself (file_ranks / first_hit) is
# imported from run_locbench.py and never reimplemented here — same discipline as r1 and r2.
#
# ARM INVOCATIONS are the ones r1/r2 recorded in their REPORT §(i), not reinvented:
#   aider           RepoMap(map_tokens=1e6, refresh="always").get_ranked_tags([], all, set(), idents)
#                   idents = aider's own Coder.get_ident_mentions(issue[:1200])
#   aider_noperson  the same call with mentioned_idents=set() — r1's no-personalization control
#   cbm             cli index_repository --repo-path=. ; cli search_graph --project=P --query=Q --limit=300
#   graphify        extract . --code-only --no-cluster --out D  (keyless local AST path)
#                   query "<issue>" --graph D/graphify-out/graph.json --budget 20000
#   codeseek        init ; search "<issue>" --limit 300 --json      (+ the ident-mention arm)
#   repowise        init --no-prose -y . ; MCP search_codebase(query, limit=300, mode=auto)
#
# ZERO SILENT SKIP: any arm failure raises. A missing result is never scored as a miss by omission.
import argparse, json, os, pathlib, re, subprocess, sys, time

HERE = pathlib.Path(__file__).resolve().parent
RIPWIRE_REPO = pathlib.Path(os.environ.get("RIPWIRE_REPO", HERE.parent.parent / "ripwire"))
sys.path.insert(0, str(RIPWIRE_REPO / "bench" / "locbench"))
import run_locbench as RL  # file_ranks, first_hit, checkout, norm_path — imported UNMODIFIED

TOOLS    = HERE / "tools"
CODESEEK = pathlib.Path.home() / ".codeseek" / "bin" / "codeseek"
REPOWISE = TOOLS / "repowise-venv" / "bin" / "repowise"
GRAPHIFY = TOOLS / "graphify-venv" / "bin" / "graphify"
AIDERPY  = TOOLS / "aider-venv" / "bin" / "python"
CBMJS    = TOOLS / "cbm-npm" / "node_modules" / "codebase-memory-mcp" / "bin.js"
# Each arm mutates the checkout it works in (git checkout per instance; .repowise / codeseek index
# dirs written in-tree), so concurrent arms need SEPARATE trees. H2H_REPOS gives each lane its own.
REPOS    = pathlib.Path( os.environ.get( "H2H_REPOS", HERE / "repos" ) )
RESULTS  = HERE / "results"
WORK     = HERE / "work"
QUERY_CHARS = 1200


def load_slice():
    d = json.load( open( RESULTS / "ripwire_for.json" ) )
    rows = json.load( open( WORK / "datasets" / "rows_czlll__Loc-Bench_V1_test_560.json" ) )
    meta = { r["instance_id"]: r for r in rows }
    out = []
    for inst in d["instances"]:
        m = meta[inst["instance_id"]]
        query = " ".join( m.get( "problem_statement", "" ).split() )[:QUERY_CHARS]
        out.append( dict( instance_id=inst["instance_id"], repo=inst["repo"],
                          base_commit=m["base_commit"], query=query,
                          primary_files=inst["primary_files"], gold_files=inst["gold_files"] ) )
    return out


def git_ls_files( repo_path ):
    r = subprocess.run( ["git", "ls-files"], capture_output=True, text=True, cwd=repo_path )
    return [ RL.norm_path( f ) for f in r.stdout.splitlines() if f ]


def timed( args, cwd, timeout=7200, stdin_data=None, env=None ):
    t0 = time.monotonic()
    r = subprocess.run( args, capture_output=True, text=True, cwd=cwd, timeout=timeout,
                        input=stdin_data, env=env )
    return r, time.monotonic() - t0


def dedup_files( paths, repo_path=None ):
    """The shared ranked-file convention: first appearance wins, order preserved."""
    files, seen = [], set()
    for p in paths:
        if not p:
            continue
        if repo_path is not None and os.path.isabs( p ):
            try:    p = os.path.relpath( p, repo_path )
            except ValueError: continue
        p = RL.norm_path( p )
        if p not in seen:
            seen.add( p ); files.append( p )
    return files


# ── codeseek (inherited from r2 worker.py) ───────────────────────────────────
def codeseek_index( repo_path ):
    r, wall = timed( [str( CODESEEK ), "init"], repo_path )
    if r.returncode != 0:
        raise RuntimeError( f"codeseek init failed: {r.stderr[-400:]}" )
    return wall


def codeseek_search( repo_path, query, limit=300 ):
    r, wall = timed( [str( CODESEEK ), "search", query, "--limit", str( limit ), "--json"], repo_path )
    if r.returncode != 0:
        raise RuntimeError( f"codeseek search failed: {r.stderr[-400:]}" )
    try:
        hits = json.loads( r.stdout )
    except json.JSONDecodeError as e:
        raise RuntimeError( f"codeseek search emitted non-JSON ({e}): {r.stdout[:200]!r}" )
    return dedup_files( [ h["file_path"] for h in hits ], repo_path ), wall, len( r.stdout )


IDENT_RE = re.compile( r"[A-Za-z_][A-Za-z0-9_]*" )
def issue_idents( query, cap=8 ):
    out, seen = [], set()
    for tok in IDENT_RE.findall( query ):
        if len( tok ) < 3 or tok in seen: continue
        codey = "_" in tok or ( tok[0].islower() and any( c.isupper() for c in tok[1:] ) )
        if codey:
            seen.add( tok ); out.append( tok )
        if len( out ) >= cap: break
    return out


def codeseek_idents_search( repo_path, query, per_ident_limit=50 ):
    idents = issue_idents( query )
    per, total_wall, total_bytes = [], 0.0, 0
    for ident in idents:
        files, wall, nbytes = codeseek_search( repo_path, ident, per_ident_limit )
        per.append( ( ident, files ) ); total_wall += wall; total_bytes += nbytes
    merged, seen, rank = [], set(), 0
    while True:
        emitted = False
        for _ident, files in per:
            if rank < len( files ):
                f = files[rank]
                if f not in seen:
                    seen.add( f ); merged.append( f )
                emitted = True
        if not emitted: break
        rank += 1
    return merged, total_wall, total_bytes, idents


# ── repowise (inherited from r2 worker.py) ───────────────────────────────────
def repowise_index( repo_path ):
    r, wall = timed( [str( REPOWISE ), "init", "--no-prose", "-y", "."], repo_path )
    if r.returncode != 0:
        raise RuntimeError( f"repowise init failed: {(r.stderr or r.stdout)[-600:]}" )
    return wall


def repowise_search( repo_path, query, limit=300 ):
    t0 = time.monotonic()
    p = subprocess.Popen( [str( REPOWISE ), "mcp", "."], stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, cwd=repo_path )
    def send( m ): p.stdin.write( json.dumps( m ) + "\n" ); p.stdin.flush()
    def recv():
        while True:
            line = p.stdout.readline()
            if not line: raise RuntimeError( "repowise mcp died" )
            try: return json.loads( line )
            except json.JSONDecodeError: continue
    send( {"jsonrpc": "2.0", "id": 1, "method": "initialize",
           "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                      "clientInfo": {"name": "h2h", "version": "0"}}} )
    recv()
    send( {"jsonrpc": "2.0", "method": "notifications/initialized"} )
    send( {"jsonrpc": "2.0", "id": 2, "method": "tools/call",
           "params": {"name": "search_codebase",
                      "arguments": {"query": query, "limit": limit, "mode": "auto"}}} )
    r = recv()
    p.kill()
    wall = time.monotonic() - t0
    txt = r["result"]["content"][0]["text"]
    data = json.loads( txt )
    raw = [ { k: res.get( k ) for k in ( "page_type", "target_path", "relevance_score" ) }
            for res in data.get( "results", [] ) ]
    files = dedup_files( [ ( res.get( "target_path", "" ) or "" ).split( "::" )[0]
                           for res in data.get( "results", [] ) ] )
    return files, wall, len( txt ), raw


# ── codebase-memory-mcp (r1 invocation) ──────────────────────────────────────
def cbm_index( repo_path ):
    r, wall = timed( ["node", str( CBMJS ), "cli", "index_repository", f"--repo-path={repo_path}"], repo_path )
    if r.returncode != 0:
        raise RuntimeError( f"cbm index failed: {(r.stderr or r.stdout)[-600:]}" )
    line = [ l for l in r.stdout.splitlines() if l.startswith( "{" ) ]
    if not line:
        raise RuntimeError( f"cbm index emitted no JSON: {r.stdout[-300:]!r}" )
    return json.loads( line[-1] )["project"], wall


def cbm_search( repo_path, project, query, limit=300 ):
    r, wall = timed( ["node", str( CBMJS ), "cli", "search_graph", f"--project={project}",
                      f"--query={query}", f"--limit={limit}"], repo_path )
    if r.returncode != 0:
        raise RuntimeError( f"cbm search failed: {(r.stderr or r.stdout)[-600:]}" )
    line = [ l for l in r.stdout.splitlines() if l.startswith( "{" ) ]
    if not line:
        raise RuntimeError( f"cbm search emitted no JSON: {r.stdout[-300:]!r}" )
    data = json.loads( line[-1] )
    results = data.get( "results", [] )
    # <python-builtins> and other synthetic paths are kept in output order and simply never match the
    # universe — the same treatment repowise's non-file wiki pages get. No arm gets its noise filtered.
    return dedup_files( [ res.get( "file_path", "" ) for res in results ], repo_path ), wall, len( r.stdout )


# ── graphify (r1 invocation, keyless local AST path) ─────────────────────────
GRAPHIFY_SRC_RE = re.compile( r"src=([^\s\]]+)" )
def graphify_extract( repo_path, out_dir ):
    env = dict( os.environ, PYTHONHASHSEED="0", GRAPHIFY_MAX_GRAPH_BYTES="2GB" )
    r, wall = timed( [str( GRAPHIFY ), "extract", ".", "--code-only", "--no-cluster",
                      "--out", str( out_dir )], repo_path, env=env )
    if r.returncode != 0:
        raise RuntimeError( f"graphify extract failed: {(r.stderr or r.stdout)[-600:]}" )
    graph = out_dir / "graphify-out" / "graph.json"
    if not graph.exists():
        raise RuntimeError( f"graphify extract wrote no graph at {graph}" )
    return graph, wall


def graphify_query( repo_path, graph, query, budget=20000 ):
    env = dict( os.environ, PYTHONHASHSEED="0", GRAPHIFY_MAX_GRAPH_BYTES="2GB" )
    r, wall = timed( [str( GRAPHIFY ), "query", query, "--graph", str( graph ),
                      "--budget", str( budget )], repo_path, env=env )
    if r.returncode != 0:
        raise RuntimeError( f"graphify query failed: {(r.stderr or r.stdout)[-600:]}" )
    # r1's imposed convention: first appearance of a node's src= file in BFS traversal order.
    # "No matching nodes found." is a real empty ranking (r1 saw 3/60) — scored as a miss, kept.
    return dedup_files( GRAPHIFY_SRC_RE.findall( r.stdout ), repo_path ), wall, len( r.stdout )


# ── aider repo-map (r1 invocation) ───────────────────────────────────────────
AIDER_DRIVER = r'''
import json, sys, time
from aider.repomap import RepoMap
from aider.io import InputOutput
from aider.coders.base_coder import Coder

repo_root, query, personalize, outp = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4]
files = json.load(sys.stdin)

class _M:                      # RepoMap only needs a token counter off main_model
    def token_count(self, text): return max(1, len(str(text)) // 4)

t0 = time.monotonic()
rm = RepoMap(map_tokens=int(1e6), root=repo_root, main_model=_M(),
             io=InputOutput(pretty=False, yes=True), refresh="always")
idents = Coder.get_ident_mentions(None, query) if personalize else set()
tags = rm.get_ranked_tags([], files, set(), idents) or []
out = []
for t in tags:
    rel = getattr(t, "rel_fname", None)
    if rel is None and isinstance(t, tuple) and t:
        rel = t[0]
    if rel: out.append(str(rel))
# Written to a FILE, never stdout: aider prints progress/warnings on stdout for some repos,
# which turned a good run into a JSONDecodeError at char 0. The transport must not share a channel
# with the tool under test.
json.dump({"ranked": out, "wall": time.monotonic() - t0, "n_idents": len(idents)}, open(outp, "w"))
'''


def aider_rank( repo_path, query, universe, personalize=True ):
    import tempfile
    abs_files = [ str( repo_path / f ) for f in universe ]
    with tempfile.NamedTemporaryFile( suffix=".json", delete=False ) as tf:
        outp = tf.name
    # cwd must NOT be the repo under test: aider imports numpy/pandas, and with the checkout as cwd
    # Python resolves those to the repository's own UNBUILT source tree ("please exit the numpy source
    # tree"). -P additionally keeps the script dir off sys.path. RepoMap gets an absolute root and
    # absolute file paths, so nothing about the ranking depends on cwd.
    r, wall = timed( [str( AIDERPY ), "-P", "-c", AIDER_DRIVER, str( repo_path ), query,
                      "1" if personalize else "0", outp],
                     HERE, stdin_data=json.dumps( abs_files ) )
    if r.returncode != 0:
        raise RuntimeError( f"aider repomap failed: {(r.stderr or r.stdout)[-800:]}" )
    # aider's transport is a FILE, not stdout (see the driver's own comment above), so its answer-bytes
    # analog of every other arm's `len(r.stdout)` is this file's serialized size — the same "full
    # response body crossing the process boundary" measure, just over a different channel.
    nbytes = os.path.getsize( outp )
    data = json.loads( pathlib.Path( outp ).read_text() )
    os.unlink( outp )
    return dedup_files( data["ranked"], repo_path ), wall, data["n_idents"], nbytes


# ── scoring helper: the SAME RL metric for every arm ─────────────────────────
def score_block( files, inst, universe, wall, nbytes=None, extra=None ):
    fr  = RL.file_ranks( files, inst["primary_files"], universe )
    afr = RL.file_ranks( files, inst["gold_files"], universe )
    blk = dict( ranked=files[:50], wall=wall, franks=fr, file_first=RL.first_hit( fr ),
                file_worst=max( fr ) if fr and all( r is not None for r in fr ) else None,
                all_file_worst=max( afr ) if afr and all( r is not None for r in afr ) else None )
    if nbytes is not None: blk["bytes"] = nbytes
    if extra: blk.update( extra )
    return blk


ARMS = ( "codeseek", "repowise", "cbm", "graphify", "aider" )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--arm", required=True, choices=ARMS )
    ap.add_argument( "--only", default="", help="comma-separated instance_ids (probe mode)" )
    ap.add_argument( "--limit", type=int, default=300 )
    # Shard tag. Concurrent shards of one arm MUST write separate files — two processes appending
    # multi-KB JSON lines to one file is not atomic, and a torn line is a silently lost instance.
    ap.add_argument( "--tag", default="", help="output suffix: results/r4_<arm><tag>.jsonl" )
    a = ap.parse_args()

    insts = load_slice()
    if a.only:
        keep = set( a.only.split( "," ) )
        insts = [ i for i in insts if i["instance_id"] in keep ]

    out_path = RESULTS / f"r4_{a.arm}{a.tag}.jsonl"
    done = set()
    for shard in RESULTS.glob( f"r4_{a.arm}*.jsonl" ):
        for line in shard.read_text().splitlines():
            try:    done.add( json.loads( line )["instance_id"] )
            except json.JSONDecodeError: pass
    REPOS.mkdir( exist_ok=True )
    scratch = HERE / "gscratch"; scratch.mkdir( exist_ok=True )

    for n, inst in enumerate( insts ):
        iid = inst["instance_id"]
        if iid in done:
            print( f"[{n+1}/{len(insts)}] {iid}: already done", flush=True ); continue
        repo_path = RL.checkout( inst["repo"], inst["base_commit"], REPOS )
        if not repo_path:
            raise SystemExit( f"{iid}: checkout FAILED (zero-silent-skip)" )
        universe = git_ls_files( repo_path )
        rec = dict( instance_id=iid, repo=inst["repo"], base_commit=inst["base_commit"],
                    n_universe=len( universe ), n_gold=len( inst["primary_files"] ) )
        try:
            if a.arm == "codeseek":
                subprocess.run( [str( CODESEEK ), "uninit", "--force"], capture_output=True, text=True, cwd=repo_path )
                rec["index_wall"] = codeseek_index( repo_path )
                f1, w1, b1 = codeseek_search( repo_path, inst["query"], a.limit )
                rec["raw"] = score_block( f1, inst, universe, w1, b1 )
                f2, w2, b2, idents = codeseek_idents_search( repo_path, inst["query"] )
                rec["idents"] = score_block( f2, inst, universe, w2, b2, {"idents": idents} )
                subprocess.run( [str( CODESEEK ), "uninit", "--force"], capture_output=True, text=True, cwd=repo_path )

            elif a.arm == "repowise":
                import shutil
                shutil.rmtree( repo_path / ".repowise", ignore_errors=True )
                rec["index_wall"] = repowise_index( repo_path )
                f, w, b, raw = repowise_search( repo_path, inst["query"], a.limit )
                rec["search"] = score_block( f, inst, universe, w, b, {"raw_top": raw[:20]} )
                shutil.rmtree( repo_path / ".repowise", ignore_errors=True )

            elif a.arm == "cbm":
                project, idx_wall = cbm_index( repo_path )
                rec["index_wall"] = idx_wall; rec["project"] = project
                f, w, b = cbm_search( repo_path, project, inst["query"], a.limit )
                rec["search"] = score_block( f, inst, universe, w, b )

            elif a.arm == "graphify":
                import shutil
                out_dir = scratch / iid
                shutil.rmtree( out_dir, ignore_errors=True ); out_dir.mkdir( parents=True )
                graph, idx_wall = graphify_extract( repo_path, out_dir )
                rec["index_wall"] = idx_wall
                rec["graph_bytes"] = graph.stat().st_size
                f, w, b = graphify_query( repo_path, graph, inst["query"] )
                rec["search"] = score_block( f, inst, universe, w, b )
                shutil.rmtree( out_dir, ignore_errors=True )

            elif a.arm == "aider":
                f, w, nid, b = aider_rank( repo_path, inst["query"], universe, personalize=True )
                rec["search"] = score_block( f, inst, universe, w, b, extra={"n_idents": nid} )
                f0, w0, _, b0 = aider_rank( repo_path, inst["query"], universe, personalize=False )
                rec["nopersona"] = score_block( f0, inst, universe, w0, b0 )
                rec["index_wall"] = 0.0     # aider builds its map inside the timed call
        except Exception as e:
            raise SystemExit( f"{iid}: ARM FAIL: {type(e).__name__}: {e} (zero-silent-skip)" )

        with open( out_path, "a" ) as fh:
            fh.write( json.dumps( rec ) + "\n" )
        blk = rec.get( "search" ) or rec.get( "raw" )
        print( f"[{n+1}/{len(insts)}] {iid}: idx={rec.get('index_wall',0):.1f}s "
               f"ff={blk['file_first']} worst={blk['file_worst']} wall={blk['wall']:.2f}s", flush=True )


if __name__ == "__main__":
    main()
