#!/usr/bin/env python3
# select_tasks.py — deterministic SWE-bench-Lite task selection for Phase B4 (agent-in-the-loop eval).
#
# WHAT THIS DOES. Phase B4 (PLAN_researchImprove2026.md, R4-eval-methodology.md) needs 30-40
# SWE-bench-Lite instances that are REPOSITORY-DISJOINT from the LocBench train split, so a task the
# agent solves here was never "seen" by any train-side ablation of the retrieval ranker. This script:
#   1. fetches SWE-bench-Lite instance METADATA ONLY (repo, instance_id, base_commit) from the public
#      HuggingFace datasets-server JSON API — the same stdlib-only urllib pattern as
#      bench/locbench/run_locbench.py's fetch_rows. It does NOT clone any task repo.
#   2. applies ripwire's EXACT LocBench train/held-out split rule (bench/locbench/run_locbench.py
#      frozen_partition: sha256("ripwire-a7-v2\0" + lowercase(repo)), byte0<128 => train) directly to
#      each SWE-bench-Lite instance's repo. This is a pure function of the repo string, so it does not
#      require re-fetching LocBench: any repo that WOULD land in LocBench's train partition is excluded.
#   3. deterministically samples up to 40 instances, seeded, stratified round-robin by repo so no single
#      repo dominates (cap 4 instances/repo).
#   4. writes bench/agentloop/tasks.lock — a JSON lock file (instance ids + repos + base commits + a
#      content hash) mirroring bench/locbench/dataset.lock's fail-closed pattern: run_agentloop.py and
#      analyze.py MUST verify the content hash before trusting the file, and must refuse (not silently
#      re-derive) on mismatch.
#
# HONESTY / FAIL-CLOSED CONTRACT:
#   * No fabricated instance ids, ever. If the network fetch is unavailable, this script FAILS with a
#     clear message and points at --from-file (a local JSON dump of the same HF row shape) as the only
#     sanctioned fallback — it does not invent or hardcode a task list.
#   * The split salt ("ripwire-a7-v2\0") and rule (byte0<128) are copied verbatim from
#     bench/locbench/run_locbench.py's frozen_partition(); if that salt ever changes, this file's
#     SPLIT_SALT constant must change with it (checked at review time, not automatically — see the
#     assertion in --verify-split-const below).
#
# USAGE:
#   python3 bench/agentloop/select_tasks.py --work-dir /tmp/agentloop
#   python3 bench/agentloop/select_tasks.py --from-file rows.json --work-dir /tmp/agentloop   # offline
#   python3 bench/agentloop/select_tasks.py --verify-split-const   # prints the salted hash rule, no I/O
#
# Deterministic given (dataset row content, seed): no LLM, no non-seeded RNG.
import argparse, hashlib, json, pathlib, sys, time, urllib.error, urllib.parse, urllib.request

ROWS_API = "https://datasets-server.huggingface.co/rows"
DATASET  = "princeton-nlp/SWE-bench_Lite"
CONFIG   = "default"
SPLIT    = "test"

# ── the split rule, copied verbatim from bench/locbench/run_locbench.py frozen_partition() ──────────
# DO NOT diverge from that function's salt/algorithm; this is what "repo-disjoint from LocBench train"
# means for the whole B4 harness. If run_locbench.py's salt ever changes, update SPLIT_SALT here too.
SPLIT_SALT = "ripwire-a7-v2\0"

def frozen_partition( repo ):
    digest = hashlib.sha256( ( SPLIT_SALT + repo.lower() ).encode( "utf-8" ) ).digest()
    return "train" if digest[0] < 128 else "heldout"

# ── dataset access (metadata only — repo/instance_id/base_commit; no clone, no patch fetch needed) ──
def fetch_rows( n_max, cache_dir ):
    cache = cache_dir / f"rows_{DATASET.replace('/','__')}_{SPLIT}.json"
    if cache.exists():
        return json.loads( cache.read_text() )
    rows, off, length = [], 0, 100
    while True:
        url = ( f"{ROWS_API}?dataset={urllib.parse.quote(DATASET)}&config={CONFIG}&split={SPLIT}"
                f"&offset={off}&length={length}" )
        page = None
        for attempt in range( 5 ):
            try:
                req = urllib.request.Request( url, headers={ "User-Agent": "ripwire-agentloop/1.0" } )
                with urllib.request.urlopen( req, timeout=120 ) as r:
                    page = json.load( r )
                break
            except Exception as e:
                print( f"# fetch retry {attempt+1}/5 (offset={off}): {e}", file=sys.stderr )
                time.sleep( 3 * ( attempt + 1 ) )
        if page is None:
            raise RuntimeError(
                f"datasets-server fetch failed after retries: {url}\n"
                f"NETWORK FETCH IS NOT OPTIONAL FOR A FRESH SELECTION. Use --from-file <rows.json> with a "
                f"locally-obtained dump of the same row shape (fields: repo, instance_id, base_commit) if "
                f"you have one; this script refuses to fabricate an instance list." )
        batch = [ x["row"] for x in page.get( "rows", [] ) ]
        if not batch: break
        rows.extend( batch ); off += len( batch )
        if n_max and len( rows ) >= n_max: break
    cache.parent.mkdir( parents=True, exist_ok=True )
    cache.write_text( json.dumps( rows ) )
    return rows

def load_from_file( path ):
    rows = json.loads( pathlib.Path( path ).read_text() )
    for f in ( "repo", "instance_id", "base_commit" ):
        if rows and f not in rows[0]:
            raise SystemExit( f"--from-file rows are missing required field {f!r}; refusing to proceed "
                               f"(zero-fabrication contract — this must be real SWE-bench-Lite row data)" )
    return rows

# ── deterministic stratified sample: round-robin by repo, capped, seeded ─────────────────────────────
def stratified_sample( eligible, target, cap_per_repo, seed ):
    import random
    rng = random.Random( seed )
    by_repo = {}
    for r in eligible:
        by_repo.setdefault( r["repo"], [] ).append( r )
    repos = sorted( by_repo )                         # deterministic base order before shuffling
    rng.shuffle( repos )
    for repo in repos:
        # deterministic within-repo order (instance_id) before the seeded shuffle
        by_repo[repo].sort( key=lambda r: r["instance_id"] )
        rng.shuffle( by_repo[repo] )

    selected, taken = [], { r: 0 for r in repos }
    round_idx = 0
    while len( selected ) < target:
        progressed = False
        for repo in repos:
            if len( selected ) >= target: break
            if taken[repo] >= cap_per_repo: continue
            if round_idx < len( by_repo[repo] ):
                selected.append( by_repo[repo][round_idx] )
                taken[repo] += 1
                progressed = True
        round_idx += 1
        if not progressed: break                      # exhausted every repo's supply under the cap
    return selected

def content_hash( instances ):
    # canonical form: sorted by instance_id, only the locked fields, stable key order.
    canon = [ dict( instance_id=i["instance_id"], repo=i["repo"], base_commit=i["base_commit"] )
              for i in sorted( instances, key=lambda x: x["instance_id"] ) ]
    blob = json.dumps( canon, sort_keys=True, separators=( ",", ":" ) ).encode( "utf-8" )
    return hashlib.sha256( blob ).hexdigest()

def main():
    ap = argparse.ArgumentParser( description=__doc__.split( "\n\n" )[0] if __doc__ else "" )
    ap.add_argument( "--work-dir", default=".", help="scratch dir for the HF row cache (NOT the ripwire repo)" )
    ap.add_argument( "--from-file", default="", help="offline fallback: local JSON dump of HF rows "
                     "(list of {repo, instance_id, base_commit, ...}) instead of a network fetch" )
    ap.add_argument( "--n-fetch", type=int, default=0, help="cap rows fetched from the API (0 = all test rows)" )
    ap.add_argument( "--target", type=int, default=40, help="instances to select" )
    ap.add_argument( "--cap-per-repo", type=int, default=4 )
    ap.add_argument( "--seed", default="ripwire-b4-agentloop-v1", help="seed string for the stratified sample" )
    ap.add_argument( "--out", default=str( pathlib.Path( __file__ ).parent / "tasks.lock" ) )
    ap.add_argument( "--verify-split-const", action="store_true",
                     help="print the split salt/rule and exit 0, no network/file I/O (review aid)" )
    a = ap.parse_args()

    if a.verify_split_const:
        print( f"SPLIT_SALT={SPLIT_SALT!r}  rule=sha256(SPLIT_SALT + repo.lower()).digest()[0] < 128 => train" )
        print( "Compare this by hand against frozen_partition() in bench/locbench/run_locbench.py." )
        return 0

    work = pathlib.Path( a.work_dir ); work.mkdir( parents=True, exist_ok=True )

    if a.from_file:
        print( f"# offline mode: loading rows from {a.from_file}", file=sys.stderr )
        rows = load_from_file( a.from_file )
    else:
        print( f"# fetching {DATASET} ({CONFIG}/{SPLIT}) metadata via datasets-server", file=sys.stderr )
        rows = fetch_rows( a.n_fetch, work / "datasets" )
    print( f"# {len(rows)} raw instances", file=sys.stderr )

    seen_repos = sorted( { r["repo"] for r in rows } )
    train_repos = sorted( r for r in seen_repos if frozen_partition( r ) == "train" )
    heldout_repos = sorted( r for r in seen_repos if r not in train_repos )
    eligible = [ r for r in rows if r["repo"] not in train_repos ]
    print( f"# {len(seen_repos)} distinct repos: {len(train_repos)} LocBench-train (excluded), "
           f"{len(heldout_repos)} held-out-eligible", file=sys.stderr )
    print( f"# {len(eligible)}/{len(rows)} instances survive the repo-disjoint exclusion", file=sys.stderr )

    if not eligible:
        raise SystemExit( "zero eligible instances after excluding LocBench-train repos; refusing to write "
                           "a lock file with a fabricated or empty task list" )

    selected = stratified_sample( eligible, a.target, a.cap_per_repo, a.seed )
    if len( selected ) < a.target:
        print( f"# WARNING: only {len(selected)}/{a.target} instances available under cap={a.cap_per_repo}/repo",
               file=sys.stderr )

    instances = [ dict( instance_id=r["instance_id"], repo=r["repo"], base_commit=r["base_commit"] )
                  for r in selected ]
    chash = content_hash( instances )
    lock = dict(
        schema="ripwire-agentloop-tasks-lock-v1",
        dataset=DATASET, config=CONFIG, split=SPLIT,
        split_contract=f"repo-disjoint from LocBench train: sha256({SPLIT_SALT!r} + lowercase(repo)), byte0<128=train (excluded)",
        seed=a.seed, cap_per_repo=a.cap_per_repo, target=a.target,
        raw_rows_fetched=len( rows ), distinct_repos_seen=len( seen_repos ),
        train_repos_excluded=train_repos, heldout_repos_eligible=len( heldout_repos ),
        eligible_after_exclusion=len( eligible ),
        selected_count=len( instances ), selected_repo_count=len( { i["repo"] for i in instances } ),
        content_sha256=chash,
        generated_unix=int( time.time() ),   # provenance only; NOT part of content_sha256, so re-running
                                              # with the same seed/data on a different day still verifies clean
        instances=sorted( instances, key=lambda x: x["instance_id"] ),
    )
    outp = pathlib.Path( a.out )
    outp.parent.mkdir( parents=True, exist_ok=True )
    outp.write_text( json.dumps( lock, indent=2 ) + "\n" )
    print( f"# wrote {outp}  instances={len(instances)}  repos={lock['selected_repo_count']}  "
           f"content_sha256={chash[:16]}...", file=sys.stderr )
    return 0

if __name__ == "__main__":
    sys.exit( main() )
