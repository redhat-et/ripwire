#!/usr/bin/env python3
# run_multiswe.py — the first public C++ localization eval mined from Multi-SWE-bench (task #R3).
#
# WHAT THIS IS. Multi-SWE-bench (arXiv 2504.02605, ByteDance-Seed, NeurIPS 2025) is a multilingual
# issue-resolving benchmark, human-verified, spanning 8 languages incl. C and C++. Unlike
# bench/cppbench (commit-message queries mined from ONE repo's own history) and bench/locbench
# (Python-only public data), this harness mines the dataset's OWN C/C++ splits: query = the linked
# GitHub ISSUE's title+body (not the PR description — closer to LocBench's issue-report shape, and
# less leakage-prone than a post-hoc commit/PR message that already names the fix), gold = the files
# (and, where derivable from git's own hunk-header function context, the functions) the verified
# `fix_patch` touches. The harness, per instance:
#   1. shallow-checkout the SOURCE repo at `base.sha` (never the fix commit — the issue query must
#      not have the fix already visible);
#   2. run ctxpack as the localizer in three arms — `--for` (shipping default, incl. the B8 mention
#      anchor), `--for --no-mention-boost` (ablation), `--query` (pure lexical BM25);
#   3. parse the flat `--format=candidates` export;
#   4. score strict file@1/3/5/10 (LocAgent's ALL-gold-in-top-k, arXiv 2503.09089 §4.1), lenient
#      any-gold@10, and first-hit MRR — same metric shapes as bench/cppbench and bench/locbench.
#
# REUSE (not reinvention): the candidate parser, file-rank scorer, subprocess wrapper, and timed
# ctxpack runner are bench/locbench's (imported, not re-derived, so scoring stays byte-for-byte
# comparable across all three benches); the git-hunk-header function-name extractor is bench/cppbench's
# (same reasoning — no LLM, no heuristic beyond git's own xfuncname patterns).
#
# LICENSE (recorded here, not just in the lock — task #R3 asks that this be checked and stated): the
# Multi-SWE-bench dataset card's license section reads "The dataset is licensed under CC0, subject to
# any intellectual property rights in the dataset owned by Bytedance. The data is adapted from the
# listed open source projects; your use of that data must comply with their respective licenses."
# (the HF repo METADATA tag shows "other" — the card's own prose above is the operative statement).
# This harness therefore does NOT commit the raw per-repo JSONL files it downloads (some are tens of
# MB; cachable per license, but repo-weight is a separate concern, see CLAUDE.md's independence
# stance) — only the derived, compact `dataset.lock` (instance ids, query hashes, gold sets, base
# SHAs) is committed, exactly as bench/cppbench does with git-log mining.
#
# HONESTY CONTRACT (house rule — same as cppbench/locbench):
#   * Issue-report queries are the SAME shape LocBench uses (written by someone who does NOT yet know
#     the fix) — these numbers ARE comparable in spirit to LocBench, though repo population, gold
#     granularity, and curation process (human-verified PRs vs mined commits) still differ; say so.
#   * Zero silent skips at RUN time: a checkout/index/ctxpack failure aborts loudly. Mining-stage
#     exclusions (no linked issue, no indexable gold file, local-path hygiene) are dataset-construction
#     choices, counted in dataset.lock's mining_stats, not runtime skips.
#   * `--offline` mode (used by test/multiswecheck.sh) never touches the network; it requires the
#     caller to pre-populate --raw-dir and pass --repo-map for every org/repo an instance names, and
#     fails loudly (never silently drops an instance) if either is missing.
#
# USAGE:
#   # one-command reproduction: mine + score the shipped dataset.lock (network: HF + GitHub)
#   CTXPACK=./build/ctxpack python3 bench/multiswe/run_multiswe.py --work-dir /tmp/multiswe \
#       --lang cpp --json-out bench/multiswe/results/cpp.json \
#       --scoreboard-out bench/multiswe/results/cpp_scoreboard.md
#   # re-mine from scratch (both languages, capped)
#   python3 bench/multiswe/run_multiswe.py --languages=c,cpp --refresh-dataset --cap-per-lang=0 \
#       --work-dir /tmp/multiswe --raw-dir /tmp/multiswe-raw
#   # offline smoke gate — see test/multiswecheck.sh
#
# Deterministic given (dataset.lock, ctxpack binary): no LLM, no RNG, frozen instance order.
import argparse, hashlib, json, os, pathlib, re, statistics, sys, time, urllib.request, urllib.error

HERE = pathlib.Path( __file__ ).resolve().parent
LOCBENCH_DIR = HERE.parent / "locbench"
CPPBENCH_DIR = HERE.parent / "cppbench"

# reuse-first: sh/run_ctx/parse_candidates/ranked_files_from_candidates/file_ranks/func_ranks/
# acc_all_at/first_hit/norm_path come from bench/locbench (generic, not LocBench-specific — the same
# import bench/cppbench already does); the hunk-header function-name extractor + local-home-path
# hygiene regex come from bench/cppbench (same reasoning, one seam, not re-derived).
sys.path.insert( 0, str( LOCBENCH_DIR ) )
import run_locbench as lb   # noqa: E402
sys.path.insert( 0, str( CPPBENCH_DIR ) )
import run_cppbench as cb   # noqa: E402  (cb.lb is the same run_locbench module, re-imported harmlessly)

DATASET_ID = "ByteDance-Seed/Multi-SWE-bench"
HF_API = f"https://huggingface.co/api/datasets/{DATASET_ID}"
HF_RESOLVE = f"https://huggingface.co/datasets/{DATASET_ID}/resolve/main"
LICENSE_NOTE = ( "CC0-1.0 dataset compilation (dataset card: \"licensed under CC0, subject to any "
                 "intellectual property rights in the dataset owned by Bytedance\"); underlying code "
                 "changes remain under each project's own OSS license — see bench/multiswe/README.md." )

GOLD_EXTS = { "c": ( "c", "h" ), "cpp": ( "cpp", "cc", "cxx", "hpp", "hh", "h", "ipp", "tpp", "mm" ) }
LANGS = ( "c", "cpp" )

# ── mining: discover + download the per-repo JSONL files (network; skipped under --offline) ────────
def discover_repos( lang, timeout=60 ):
    req = urllib.request.Request( HF_API, headers={ "User-Agent": "ctxpack-multiswe/1.0" } )
    with urllib.request.urlopen( req, timeout=timeout ) as r:
        meta = json.load( r )
    sibs = [ s["rfilename"] for s in meta.get( "siblings", [] ) ]
    prefix = lang + "/"
    out = []
    for s in sibs:
        if not s.startswith( prefix ) or not s.endswith( "_dataset.jsonl" ): continue
        base = s[ len( prefix ) : -len( "_dataset.jsonl" ) ]
        org, _, repo = base.partition( "__" )
        if org and repo: out.append( ( org, repo ) )
    return sorted( out ), meta.get( "sha", "" )

def download_raw( lang, raw_dir, offline, verbose ):
    lang_dir = raw_dir / lang; lang_dir.mkdir( parents=True, exist_ok=True )
    existing = sorted( lang_dir.glob( "*.jsonl" ) )
    if offline:
        if not existing:
            raise SystemExit( f"--offline: no cached raw JSONL under {lang_dir} — pre-populate --raw-dir "
                              f"(see test/multiswecheck.sh for the fixture pattern)" )
        return existing, ""
    repos, revision = discover_repos( lang )
    if not repos:
        raise SystemExit( f"discover_repos({lang!r}) returned zero repos — dataset layout changed?" )
    paths = []
    for org, repo in repos:
        dst = lang_dir / f"{org}__{repo}_dataset.jsonl"
        if not dst.exists():
            url = f"{HF_RESOLVE}/{lang}/{org}__{repo}_dataset.jsonl"
            if verbose: print( f"# downloading {url}", file=sys.stderr )
            req = urllib.request.Request( url, headers={ "User-Agent": "ctxpack-multiswe/1.0" } )
            with urllib.request.urlopen( req, timeout=300 ) as r:
                dst.write_bytes( r.read() )
        paths.append( dst )
    return paths, revision

# ── mining: filter raw rows -> canonical instances ───────────────────────────────────────────────
DIFF_HDR_RE = re.compile( r'^diff --git a/(.+) b/(.+)$' )

def parse_fix_patch_blocks( fix_patch ):
    # one block per `diff --git` hunk group; 'added' = the file did not exist at base (new file mode),
    # 'hunk_ctx' = git's own @@ ... @@ function-context strings (reuse cb.FUNC_CTX_RE, same regex
    # bench/cppbench already uses for the identical purpose on the identical diff format).
    blocks, cur = [], None
    for line in fix_patch.splitlines():
        m = DIFF_HDR_RE.match( line )
        if m:
            cur = dict( old=m.group( 1 ), new=m.group( 2 ), added=False, hunk_ctx=[] )
            blocks.append( cur ); continue
        if cur is None: continue
        if line.startswith( "new file mode" ): cur["added"] = True
        m2 = cb.FUNC_CTX_RE.match( line )
        if m2: cur["hunk_ctx"].append( m2.group( 1 ) )
    return blocks

def gold_from_fix_patch( fix_patch, lang ):
    blocks = parse_fix_patch_blocks( fix_patch )
    exts = GOLD_EXTS[lang]
    gold_files_all = sorted( { b["old"] for b in blocks if not b["added"] } )
    def keep_ext( p ): return "." in p and p.rsplit( ".", 1 )[-1] in exts
    gold_files = sorted( { f for f in gold_files_all if keep_ext( f ) } )
    gold_funcs, seen = [], set()
    for b in blocks:
        if b["added"] or not keep_ext( b["old"] ): continue
        for ctx in b["hunk_ctx"]:
            fn = cb.func_name_from_context( ctx )
            if not fn or not fn["name"]: continue
            key = ( b["old"], fn["scope"], fn["name"] )
            if key in seen: continue
            seen.add( key ); gold_funcs.append( dict( file=b["old"], scope=fn["scope"], name=fn["name"] ) )
    return gold_files_all, gold_files, gold_funcs

def issue_query( resolved_issues ):
    parts = []
    for iss in resolved_issues or []:
        t = ( iss.get( "title" ) or "" ).strip()
        b = ( iss.get( "body" ) or "" ).strip()
        if t or b: parts.append( ( t + "\n" + b ).strip() )
    return " ".join( " ".join( "\n\n".join( parts ).split() ).split() )   # single-line, whitespace-normalized

def classify_row( row, lang ):
    resolved = row.get( "resolved_issues" ) or []
    if not resolved: return None, "no_resolved_issue"
    query = issue_query( resolved )
    if not query or len( query.split() ) < 4: return None, "issue_too_short"
    if cb.LOCAL_PATH_RE.search( query ): return None, "embedded_local_path"
    fix_patch = row.get( "fix_patch" ) or ""
    if not fix_patch.strip(): return None, "empty_fix_patch"
    gold_all, gold_files, gold_funcs = gold_from_fix_patch( fix_patch, lang )
    if not gold_files: return None, "no_gold_of_language"
    base = row.get( "base" ) or {}
    base_sha = base.get( "sha" )
    if not base_sha: return None, "no_base_sha"
    inst = dict( instance_id=row.get( "instance_id" ) or f"{row['org']}__{row['repo']}-{row['number']}",
                lang=lang, org=row["org"], repo=row["repo"], number=row.get( "number" ),
                base_sha=base_sha, query=query, subject=( resolved[0].get( "title" ) or "" )[:200],
                gold_files_all=gold_all, gold_files=gold_files, gold_funcs=gold_funcs )
    return inst, "kept"

def mine_lang( lang, raw_paths, cap ):
    stats = dict( scanned=0, no_resolved_issue=0, issue_too_short=0, embedded_local_path=0,
                 empty_fix_patch=0, no_gold_of_language=0, no_base_sha=0, kept=0 )
    instances = []
    for path in raw_paths:
        for line in path.read_text( encoding="utf-8" ).splitlines():
            line = line.strip()
            if not line: continue
            row = json.loads( line )
            stats["scanned"] += 1
            inst, reason = classify_row( row, lang )
            stats[reason] += 1
            if inst is None: continue
            instances.append( inst )
    instances.sort( key=lambda i: i["instance_id"] )   # deterministic, source-order-independent
    if cap > 0: instances = instances[ :cap ]
    stats["kept"] = len( instances )
    return instances, stats

def content_hash( instances ):
    canon = [ dict( instance_id=i["instance_id"], base_sha=i["base_sha"], gold_files=i["gold_files"],
                    query_sha256=hashlib.sha256( i["query"].encode( "utf-8" ) ).hexdigest() )
             for i in sorted( instances, key=lambda x: x["instance_id"] ) ]
    blob = json.dumps( canon, sort_keys=True, separators=( ",", ":" ) ).encode( "utf-8" )
    return hashlib.sha256( blob ).hexdigest()

def load_or_mine_lock( a ):
    lock_path = pathlib.Path( a.dataset_lock )
    if lock_path.exists() and not a.refresh_dataset:
        lock = json.loads( lock_path.read_text() )
        all_inst = [ i for lang_insts in lock["instances_by_lang"].values() for i in lang_insts ]
        expected = content_hash( all_inst )
        if expected != lock["content_sha256"]:
            raise SystemExit( f"dataset.lock content hash mismatch (expected {lock['content_sha256']}, "
                              f"recomputed {expected}) — hand-edited or corrupted; refusing to run on an "
                              f"unverified instance list. Use --refresh-dataset to deliberately re-mine." )
        print( f"# trusting {lock_path} — {lock['selected_count']} instances, "
               f"content_sha256={expected[:16]}...", file=sys.stderr )
        return lock
    langs = [ x.strip() for x in a.languages.split( "," ) if x.strip() ]
    for l in langs:
        if l not in LANGS: raise SystemExit( f"unknown language {l!r} — choose from {LANGS}" )
    raw_dir = pathlib.Path( a.raw_dir )
    instances_by_lang, mining_stats, revision = {}, {}, ""
    for lang in langs:
        print( f"# mining lang={lang} (offline={a.offline}, cap={a.cap_per_lang})", file=sys.stderr )
        raw_paths, rev = download_raw( lang, raw_dir, a.offline, a.verbose )
        revision = revision or rev
        insts, stats = mine_lang( lang, raw_paths, a.cap_per_lang )
        instances_by_lang[lang] = insts; mining_stats[lang] = stats
        print( f"# {lang}: kept {stats['kept']} of {stats['scanned']} scanned  stats={stats}", file=sys.stderr )
    all_inst = [ i for insts in instances_by_lang.values() for i in insts ]
    if not all_inst:
        raise SystemExit( "zero eligible instances mined across requested languages — refusing to write "
                          "an empty dataset.lock (zero-fabrication contract)" )
    chash = content_hash( all_inst )
    lock = dict( schema="ctxpack-multiswe-dataset-lock-v1", source_dataset=DATASET_ID,
                source_dataset_url=f"https://huggingface.co/datasets/{DATASET_ID}",
                source_dataset_revision=revision, license=LICENSE_NOTE, languages=langs,
                gold_extensions={ l: list( GOLD_EXTS[l] ) for l in langs }, cap_per_lang=a.cap_per_lang,
                mining_stats=mining_stats,
                selected_count={ l: len( instances_by_lang[l] ) for l in langs } | { "total": len( all_inst ) },
                content_sha256=chash, generated_unix=int( time.time() ),
                instances_by_lang=instances_by_lang )
    lock_path.parent.mkdir( parents=True, exist_ok=True )
    lock_path.write_text( json.dumps( lock, indent=2 ) + "\n" )
    print( f"# wrote {lock_path}  total_instances={len(all_inst)}  content_sha256={chash[:16]}...",
           file=sys.stderr )
    return lock

# ── checkout: shallow fetch a (possibly remapped) repo at a pinned sha ───────────────────────────────
def parse_repo_map( spec ):
    out = {}
    for item in ( spec or "" ).split( "," ):
        item = item.strip()
        if not item: continue
        key, _, val = item.partition( "=" )
        if not key or not val: raise SystemExit( f"malformed --repo-map entry {item!r} (want ORG/REPO=path)" )
        out[key] = val
    return out

def checkout( org, repo, sha, repos_dir, repo_map, offline ):
    key = f"{org}/{repo}"
    dst = repos_dir / f"{org}__{repo}"
    marker = dst / f".ctxpack_at_{sha}"
    if marker.exists(): return dst
    origin = repo_map.get( key )
    if origin is None and offline:
        raise SystemExit( f"--offline: no --repo-map entry for {key} (zero-silent-skip contract)" )
    if origin is None: origin = f"https://github.com/{key}.git"
    if not ( dst / ".git" ).exists():
        dst.mkdir( parents=True, exist_ok=True )
        lb.sh( [ "git", "init", "-q" ], cwd=dst )
        lb.sh( [ "git", "remote", "add", "origin", origin ], cwd=dst )
    else:
        lb.sh( [ "git", "remote", "set-url", "origin", origin ], cwd=dst )
    f = lb.sh( [ "git", "fetch", "-q", "--depth", "1", "origin", sha ], cwd=dst, timeout=600 )
    if f.returncode != 0:
        if offline: return None
        lb.sh( [ "git", "fetch", "-q", "origin" ], cwd=dst, timeout=600 )
    co = lb.sh( [ "git", "checkout", "-q", "-f", sha ], cwd=dst )
    if co.returncode != 0:
        co = lb.sh( [ "git", "checkout", "-q", "-f", "FETCH_HEAD" ], cwd=dst )
    lb.sh( [ "git", "clean", "-qfdx" ], cwd=dst )
    if co.returncode != 0: return None
    for old in dst.glob( ".ctxpack_at_*" ): old.unlink()
    marker.write_text( "" )
    return dst

# ── ctxpack arms (reuse lb.run_ctx / lb.parse_candidates / lb.file_ranks / lb.acc_all_at / lb.first_hit) ─
ARMS = ( "for", "for-no-mention", "query" )
def arm_flags( arm, query, top_k ):
    if arm == "for":           return [ f"--for={query}", f"--top-k={top_k}" ]
    if arm == "for-no-mention": return [ f"--for={query}", "--no-mention-boost", f"--top-k={top_k}" ]
    if arm == "query":         return [ f"--query={query}", f"--top-k={top_k}" ]
    raise ValueError( arm )

# ── main ──────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser( description="C++ (and C) localization eval mined from Multi-SWE-bench" )
    ap.add_argument( "--languages", default="cpp", help="languages to MINE into the lock (comma list, c and/or cpp)" )
    ap.add_argument( "--lang", default="cpp", choices=LANGS, help="which language's instances to SCORE this run" )
    ap.add_argument( "--raw-dir", default=str( HERE / ".raw-cache" ), help="scratch cache for downloaded per-repo JSONL (never committed — see README license note)" )
    ap.add_argument( "--dataset-lock", default=str( HERE / "dataset.lock" ) )
    ap.add_argument( "--refresh-dataset", action="store_true" )
    ap.add_argument( "--cap-per-lang", type=int, default=0, help="0 = no cap (take all eligible instances)" )
    ap.add_argument( "--offline", action="store_true", help="never touch the network; requires --raw-dir pre-populated and --repo-map covering every referenced org/repo" )
    ap.add_argument( "--repo-map", default="", help="ORG/REPO=local_path[,ORG2/REPO2=path2,...] — offline checkout override" )
    ap.add_argument( "--work-dir", required=True, help="scratch dir for repo checkouts + indexes (NOT the ctxpack repo)" )
    ap.add_argument( "--top-k", type=int, default=200 )
    ap.add_argument( "--query-chars", type=int, default=1200, help="deterministic prefix of the issue query used for --for/--query" )
    ap.add_argument( "--arms", default=",".join( ARMS ) )
    ap.add_argument( "--max-instances", type=int, default=0, help="stop scoring after this many (0 = all in the selected lang)" )
    ap.add_argument( "--json-out", default="" )
    ap.add_argument( "--scoreboard-out", default="" )
    ap.add_argument( "--verbose", action="store_true" )
    a = ap.parse_args()

    arms = [ x.strip() for x in a.arms.split( "," ) if x.strip() ]
    for arm in arms:
        if arm not in ARMS: raise SystemExit( f"unknown arm {arm!r} — choose from {ARMS}" )
    repo_map = parse_repo_map( a.repo_map )

    lock = load_or_mine_lock( a )
    if a.lang not in lock["instances_by_lang"]:
        raise SystemExit( f"dataset.lock has no instances for --lang={a.lang!r} "
                          f"(mined languages: {list(lock['instances_by_lang'])}) — re-mine with "
                          f"--refresh-dataset --languages including {a.lang!r}" )
    instances = lock["instances_by_lang"][a.lang]
    if a.max_instances > 0: instances = instances[ :a.max_instances ]

    work = pathlib.Path( a.work_dir ); work.mkdir( parents=True, exist_ok=True )
    repos_dir = work / "repos"; index_dir = work / "indexes"
    repos_dir.mkdir( parents=True, exist_ok=True ); index_dir.mkdir( parents=True, exist_ok=True )

    def zero(): return dict( n=0, f1=0, f3=0, f5=0, f10=0, any10=0, mrr=0.0, wall=0.0 )
    acc = { arm: zero() for arm in arms }
    per_instance = []
    skipped_checkout = skipped_unindexable = 0
    t_start = time.perf_counter()

    for idx, inst in enumerate( instances ):
        iid = inst["instance_id"]; query = inst["query"][ : a.query_chars ]
        repo_path = checkout( inst["org"], inst["repo"], inst["base_sha"], repos_dir, repo_map, a.offline )
        if repo_path is None:
            if a.offline:
                skipped_checkout += 1
                print( f"[{idx+1}/{len(instances)}] {iid}: OFFLINE CHECKOUT UNAVAILABLE (skip)", file=sys.stderr )
                continue
            raise SystemExit( f"[{idx+1}/{len(instances)}] {iid}: CHECKOUT FAIL (zero-silent-skip contract)" )

        cache_key = f"{inst['org']}__{inst['repo']}__{inst['base_sha']}"
        rich_cache = index_dir / f"{cache_key}.rich.ctxpackcache"
        if not rich_cache.exists():
            base = index_dir / cache_key
            _, _, irc = lb.run_ctx( repo_path, [ f"--index-out={base}", "--top-k=1", "--no-cache" ] )
            if irc != 0 or not rich_cache.exists():
                raise SystemExit( f"[{idx+1}/{len(instances)}] {iid}: INDEX FAIL rc={irc} (zero-silent-skip contract)" )

        uni_xml, _, urc = lb.run_ctx( repo_path, [ f"--query={query}", "--format=candidates",
                                                    "--top-k=1000000000", f"--cache={rich_cache}" ] )
        try: uni_candidates = lb.parse_candidates( uni_xml, repo_path )
        except Exception as e: uni_candidates = []; parse_err = str( e )
        if urc != 0 or not uni_candidates:
            raise SystemExit( f"[{idx+1}/{len(instances)}] {iid}: UNIVERSE CTX FAIL rc={urc} "
                              f"parse={locals().get('parse_err','')} (zero-silent-skip contract)" )
        universe_files = sorted( { c["path"] for c in uni_candidates } )
        gold_norm = [ lb.norm_path( g ) for g in inst["gold_files"] ]
        primary = [ g for g in gold_norm if g in universe_files ]
        if not primary:
            skipped_unindexable += 1
            print( f"[{idx+1}/{len(instances)}] {iid}: NO INDEXABLE GOLD FILE (skip, unindexable)", file=sys.stderr )
            continue

        arm_out = {}
        rot = hashlib.sha256( iid.encode() ).digest()[0] % len( arms )
        run_order = arms[rot:] + arms[:rot]
        for arm in run_order:
            flags = arm_flags( arm, query, a.top_k ) + [ "--format=candidates", f"--cache={rich_cache}" ]
            payloads, walls = [], []
            for _ in range( 2 ):
                xml, wall, rc = lb.run_ctx( repo_path, flags )
                if rc != 0: break
                payloads.append( xml ); walls.append( wall )
            if rc != 0 or len( payloads ) != 2 or payloads[0] != payloads[1]:
                raise SystemExit( f"[{idx+1}/{len(instances)}] {iid}: ARM FAIL arm={arm} rc={rc} "
                                  f"deterministic={len(set(payloads))<=1} (zero-silent-skip contract)" )
            try: candidates = lb.parse_candidates( payloads[0], repo_path )
            except Exception as e:
                raise SystemExit( f"[{idx+1}/{len(instances)}] {iid}: XML FAIL arm={arm}: {e} (zero-silent-skip contract)" )
            rf = lb.ranked_files_from_candidates( candidates )
            franks = lb.file_ranks( rf, primary, universe_files )
            wall_med = statistics.median( walls )
            m = acc[arm]; m["n"] += 1; m["wall"] += wall_med
            m["f1"]  += lb.acc_all_at( franks, 1 );  m["f3"]  += lb.acc_all_at( franks, 3 )
            m["f5"]  += lb.acc_all_at( franks, 5 );  m["f10"] += lb.acc_all_at( franks, 10 )
            fh = lb.first_hit( franks )
            m["any10"] += ( fh is not None and fh < 10 )
            if fh is not None: m["mrr"] += 1.0 / ( fh + 1 )
            arm_out[arm] = dict( file_first=fh, file_worst=( max( franks ) if franks and all( r is not None for r in franks ) else None ),
                                 wall=round( wall_med, 4 ) )

        per_instance.append( dict( instance_id=iid, org=inst["org"], repo=inst["repo"], base_sha=inst["base_sha"],
                                   subject=inst["subject"], gold_files=inst["gold_files"], primary_files=primary,
                                   gold_funcs=inst["gold_funcs"], n_universe_files=len( universe_files ), arms=arm_out ) )
        if a.verbose or ( idx + 1 ) % 10 == 0:
            print( f"[{idx+1}/{len(instances)}] {iid} files={len(primary)}/{len(inst['gold_files'])} "
                   + " ".join( f"{k}:Ff{v['file_first']}" for k, v in arm_out.items() ), file=sys.stderr )

    wall_total = time.perf_counter() - t_start
    scored = acc[arms[0]]["n"] if arms else 0

    def pct( x, d ): return f"{100.0*x/d:5.1f}%" if d else "   n/a"
    lines = []
    lines.append( "=" * 78 )
    lines.append( f"multiswe — Multi-SWE-bench {a.lang} localization eval  n_scored={scored}  "
                  f"(unindexable={skipped_unindexable} offline-skip={skipped_checkout})" )
    lines.append( "=" * 78 )
    lines.append( "Acc@k = STRICT (all gold files within top-k of one flat rank), per LocAgent's metric shape." )
    hdr = f"{'arm':14} | {'file@1':>7} {'file@3':>7} {'file@5':>7} {'file@10':>7} | {'any@10':>7} {'MRR':>7} | {'wall/inst':>9}"
    lines.append( hdr ); lines.append( "-" * len( hdr ) )
    for arm in arms:
        m = acc[arm]; n = m["n"] or 1
        lines.append( f"{arm:14} | {pct(m['f1'],n):>7} {pct(m['f3'],n):>7} {pct(m['f5'],n):>7} {pct(m['f10'],n):>7} | "
                      f"{pct(m['any10'],n):>7} {m['mrr']/n:7.3f} | {m['wall']/n:8.2f}s" )
    if "for" in acc and "for-no-mention" in acc and acc["for"]["n"] and acc["for-no-mention"]["n"]:
        d10 = 100.0 * acc["for"]["f10"] / acc["for"]["n"] - 100.0 * acc["for-no-mention"]["f10"] / acc["for-no-mention"]["n"]
        lines.append( f"\nmention-anchor ablation: for.file@10 - for-no-mention.file@10 = {d10:+.1f}pp" )
    single = [ r for r in per_instance if len( r["primary_files"] ) == 1 ]
    multi  = [ r for r in per_instance if len( r["primary_files"] ) > 1 ]
    for stratum, rows_s in ( ( "single-file", single ), ( "multi-file", multi ) ):
        if not rows_s: continue
        lines.append( f"\n{stratum} primary stratum n={len(rows_s)}:" )
        for arm in arms:
            strict = sum( r["arms"][arm]["file_worst"] is not None and r["arms"][arm]["file_worst"] < 10 for r in rows_s )
            lines.append( f"  {arm:14} strict@10 {pct(strict,len(rows_s))}" )
    lines.append( f"\nwall clock total: {wall_total:.1f}s over {len(instances)} selected instances" )
    report = "\n".join( lines )
    print( "\n" + report )

    if a.scoreboard_out:
        pathlib.Path( a.scoreboard_out ).write_text( report + "\n" )
        print( f"\nwrote {a.scoreboard_out}" )
    if a.json_out:
        pathlib.Path( a.json_out ).write_text( json.dumps(
            dict( dataset=DATASET_ID, license=LICENSE_NOTE, lang=a.lang, dataset_lock_sha256=lock["content_sha256"],
                 n_selected=len( instances ), n_scored=scored, skipped_unindexable=skipped_unindexable,
                 skipped_checkout=skipped_checkout, wall_total=wall_total,
                 arms={ arm: acc[arm] for arm in arms }, instances=per_instance ), indent=2 ) )
        print( f"wrote {a.json_out}" )

    return 0

if __name__ == "__main__":
    sys.exit( main() )
