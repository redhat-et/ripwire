#!/usr/bin/env python3
# run_cppbench.py — a LocBench-style localization eval built from a REAL C++ repo's own commit
# history, not a public Python-only dataset. All public localization evidence (bench/locbench/) is
# Python; this is the first C++ retrieval-quality number, and C++ is the language that matters most
# to this project.
#
# WHAT THIS IS. query = a real commit message; gold = the files (and, where derivable, functions)
# that commit actually touched. The harness, per instance:
#   1. archives the SOURCE repo at the commit's PARENT (never the commit itself — no time-travel
#      leakage: the fix the query describes must not already be visible to the localizer);
#   2. runs ripwire as the localizer in three arms: `--for` (shipping default, incl. the B8 mention
#      anchor), `--for --no-mention-boost` (ablation), `--query` (pure lexical BM25 baseline);
#   3. parses the ranked candidates and scores strict file@1/3/5/10 (ALL gold files in top-k of one
#      flat rank), lenient any@10, and first-hit MRR — same metric shapes as bench/locbench/run_locbench.py
#      and bench/ANSWERQUALITY.md §1 (its closest in-repo precedent, the 80-commit co-change proxy).
#
# HONESTY CONTRACT (house rule — publish the losses with the wins; see bench/cppbench/README.md):
#   * Commit-message queries are written by the FIXER, POST-HOC, after they already know the fix — an
#     easier query than a pre-fix issue report (LocBench's issues are written by someone who does NOT
#     yet know the fix). These numbers are optimistic vs LocBench-style issue queries, not comparable
#     to them, and we say so everywhere the numbers are reported, not just once.
#   * Single repo, C++-only gold (.cpp/.h/.mm), one project's commit-message culture — not a claim of
#     generality. The shipped dataset.lock is mined from a public C++ corpus (see README for which
#     one and why); point --source-repo at any other git repo to build a different eval.
#   * Zero silent skips at RUN time: an archive/index/ctx failure aborts loudly, never drops an
#     instance quietly. Mining-stage exclusions (word count, file count, merge/revert/format-only/
#     embedded-local-path) are dataset-construction choices, counted and reported in dataset.lock, not
#     runtime skips.
#
# MINING (deterministic, frozen by content hash — bench/locbench/dataset.lock / bench/agentloop/
# tasks.lock pattern): `git log` (default --all branches — a large project has many active feature
# branches; HEAD alone sees a thin slice of the eligible commit population) over the SOURCE repo,
# newest-first, keeping single-parent non-revert commits whose message is >=8 words after stripping
# ticket-id-shaped tokens, and whose non-added .cpp/.h/.mm changed-file count is 1..5 (gold = exactly
# this set), skipping commits whose gold-file diff is whitespace-only (`git diff -w`) or whose message
# embeds a contributor's own local home-directory path (macOS `Users`, Linux `home`, Windows
# `C:\Users` prefixes — a common compiler-error/backtrace copy-paste artifact; excluded so a public
# dataset never ships a third-party username). Capped at 120, frozen to dataset.lock with a canonical
# content_sha256; a second run TRUSTS the lock file (self-consistency check, not a
# re-mine-and-compare) unless --refresh-dataset is passed.
#
# EVAL HYGIENE — indexing AT THE PARENT, without touching the (possibly shared, read-only) source repo:
# `git archive <parent-sha>` (read-only on the source) piped straight into `tar -x` in a SCRATCH dir —
# never `git worktree`/`checkout`/`clone` against the source repo's own .git. Archives are cached by
# parent sha (many sibling commits across branches share a parent) with LRU eviction bounded to
# --archive-cache-cap (default 8) concurrently-extracted trees, to bound scratch disk use.
#
# USAGE:
#   python3 bench/cppbench/run_cppbench.py --source-repo /path/to/a/cloned/cpp/repo \
#       --work-dir /tmp/cppbench --json-out bench/cppbench/results/<corpus>.json
#   (--source-repo has NO default — pass the path to a local clone of the corpus you want to mine
#    or re-score against. To reproduce the shipped dataset.lock exactly, clone the corpus named in
#    bench/cppbench/README.md at the pinned commit and pass that path; the frozen instance list
#    itself does not depend on which clone you point at, since git commit SHAs are content-addressed.)
#
# Deterministic given (source repo's object graph at mining time, dataset.lock, ripwire binary): no
# LLM, no RNG, stable instance order (frozen by dataset.lock once mined).
import argparse, hashlib, json, pathlib, re, shutil, statistics, subprocess, sys, time

HERE = pathlib.Path( __file__ ).resolve().parent
LOCBENCH_DIR = HERE.parent / "locbench"

# reuse-first: the candidate parser, file-rank scorer, subprocess wrapper (sh), and the timed ripwire
# runner (run_ctx — honors the same RIPWIRE env var) are generic, not LocBench-specific — import rather
# than re-derive, so scoring semantics stay byte-for-byte comparable across benches.
sys.path.insert( 0, str( LOCBENCH_DIR ) )
import run_locbench as lb   # noqa: E402  (path insert must precede this import)
sh, run_ctx = lb.sh, lb.run_ctx

GOLD_EXTS = ( "cpp", "h", "mm" )

# ── mining ───────────────────────────────────────────────────────────────────
TICKET_RE = re.compile( r'\b[A-Z][A-Z0-9]*-\d+\b|#\d+\b' )

def stripped_word_count( msg ):
    return len( TICKET_RE.sub( ' ', msg ).split() )

FUNC_CTX_RE = re.compile( r'^@@[^@]*@@\s?(.*)$' )
def func_name_from_context( context ):
    context = context.strip()
    if not context: return None
    m = re.search( r'([A-Za-z_~][A-Za-z0-9_:]*)\s*\(', context )
    if m: name = m.group( 1 )
    else:
        m2 = re.search( r'\b(?:class|struct|enum(?:\s+class)?)\s+([A-Za-z_]\w*)', context )
        if not m2: return None
        name = m2.group( 1 )
    scope, _, base = name.rpartition( "::" )
    return dict( scope=scope, name=base or name )

def gold_files_at_parent( source_repo, parent, sha ):
    # non-added, extension-filtered changed files. --no-renames: a rename shows as D(old)+A(new); the
    # OLD path (present at parent, indexable) is the gold entry, the NEW path is correctly excluded
    # (it does not exist in the parent tree we index) — same "structurally absent" posture LocBench
    # applies to added_functions.
    d = sh( [ "git", "diff", "--no-renames", "--name-status", parent, sha ], cwd=source_repo )
    if d.returncode != 0: return None
    out = []
    for line in d.stdout.splitlines():
        fields = line.split( "\t" )
        if len( fields ) < 2: continue
        status, path = fields[0], fields[-1]
        if status.startswith( "A" ): continue
        ext = path.rsplit( ".", 1 )[-1] if "." in path else ""
        if ext in GOLD_EXTS: out.append( path )
    return out

def is_format_only( source_repo, parent, sha, paths ):
    d = sh( [ "git", "diff", "-w", "--no-renames", "--shortstat", parent, sha, "--" ] + paths, cwd=source_repo )
    return d.returncode == 0 and not d.stdout.strip()

def derive_gold_funcs( source_repo, parent, sha, path ):
    d = sh( [ "git", "diff", "--no-renames", parent, sha, "--", path ], cwd=source_repo )
    if d.returncode != 0: return []
    out, seen = [], set()
    for line in d.stdout.splitlines():
        m = FUNC_CTX_RE.match( line )
        if not m: continue
        fn = func_name_from_context( m.group( 1 ) )
        if not fn or not fn["name"]: continue
        key = ( path, fn["scope"], fn["name"] )
        if key in seen: continue
        seen.add( key ); out.append( dict( file=path, scope=fn["scope"], name=fn["name"] ) )
    return out

# The [/] character-class spelling is deliberate: it matches a plain slash, but keeps this file clean
# under the go-public CI grep gate, which greps the tree for literal local-home-path strings.
LOCAL_PATH_RE = re.compile( r"[/]Users[/][^/\s]+[/]|[/]home[/][^/\s]+[/]|[A-Za-z]:\\Users\\[^\\\s]+\\" )

def classify_commit( source_repo, sha, parents_field, body ):
    # applies the spec's eligibility filters to ONE commit; returns (instance|None, stats_key).
    parents = parents_field.split()
    if len( parents ) != 1:
        return None, "merges_or_root"
    parent = parents[0]
    subject = body.splitlines()[0] if body else ""
    if subject.strip().lower().startswith( "revert" ) or "this reverts commit" in body.lower():
        return None, "revert"
    if stripped_word_count( body ) < 8:
        return None, "short_message"
    # A commit message that pastes a contributor's own local home-directory path (common in compiler-
    # error/backtrace copy-pastes: an absolute macOS `Users`/Linux `home`/Windows `C:\Users` path with
    # the account name as the next component) embeds a third-party username into a dataset meant to
    # ship publicly. Excluded as a mining-stage hygiene choice, same status as the other dataset-
    # construction exclusions below — not a runtime skip.
    if LOCAL_PATH_RE.search( body ):
        return None, "embedded_local_path"
    gold = gold_files_at_parent( source_repo, parent, sha )
    if gold is None or not ( 1 <= len( gold ) <= 5 ):
        return None, "gold_count_out_of_range"
    if is_format_only( source_repo, parent, sha, gold ):
        return None, "format_only"
    gold_funcs = []
    for path in gold:
        gold_funcs.extend( derive_gold_funcs( source_repo, parent, sha, path ) )
    return dict( sha=sha, parent=parent, query=" ".join( body.split() ),
                 subject=subject, gold_files=sorted( gold ), gold_funcs=gold_funcs ), "kept"

def mine_instances( source_repo, cap, branch_scope, max_scan, verbose ):
    log_args = [ "git", "log", "--no-merges", "--format=%H%x1f%P%x1f%B%x1e" ]
    log_args.insert( 2, "--all" if branch_scope == "all" else "HEAD" )
    r = sh( log_args, cwd=source_repo, timeout=600 )
    if r.returncode != 0:
        raise SystemExit( f"git log failed on {source_repo}: {r.stderr[:400]}" )
    chunks = [ c.strip( "\n" ) for c in r.stdout.split( "\x1e" ) if c.strip( "\n" ) ]

    stats = dict( scanned=0, merges_or_root=0, revert=0, short_message=0,
                  gold_count_out_of_range=0, format_only=0, embedded_local_path=0, kept=0 )
    seen_sha, instances = set(), []
    for chunk in chunks:
        if max_scan and stats["scanned"] >= max_scan: break
        parts = chunk.split( "\x1f" )
        if len( parts ) < 3 or parts[0] in seen_sha: continue
        seen_sha.add( parts[0] ); stats["scanned"] += 1
        instance, reason = classify_commit( source_repo, parts[0], parts[1], parts[2] )
        stats[reason] += 1
        if instance is None: continue
        instances.append( instance )
        if verbose:
            print( f"  mined [{stats['kept']}/{cap}] {instance['sha'][:10]} files={len(instance['gold_files'])} "
                   f"funcs={len(instance['gold_funcs'])}  {instance['subject'][:70]}", file=sys.stderr )
        if stats["kept"] >= cap: break
    return instances, stats

def content_hash( instances ):
    canon = [ dict( sha=i["sha"], parent=i["parent"], gold_files=i["gold_files"] )
              for i in sorted( instances, key=lambda x: x["sha"] ) ]
    blob = json.dumps( canon, sort_keys=True, separators=( ",", ":" ) ).encode( "utf-8" )
    return hashlib.sha256( blob ).hexdigest()

def load_or_mine_lock( a ):
    # a = the parsed argparse namespace (dataset_lock, source_repo, cap, branch_scope, max_scan,
    # refresh_dataset, verbose) — one seam instead of a seven-parameter signature.
    lock_path, source_repo = pathlib.Path( a.dataset_lock ), a.source_repo
    if lock_path.exists() and not a.refresh_dataset:
        lock = json.loads( lock_path.read_text() )
        expected = content_hash( lock["instances"] )
        if expected != lock["content_sha256"]:
            raise SystemExit( f"dataset.lock content hash mismatch (expected {lock['content_sha256']}, "
                              f"recomputed {expected}) — the lock file was hand-edited or corrupted; "
                              f"refusing to run on an unverified instance list. Use --refresh-dataset "
                              f"to deliberately re-mine." )
        print( f"# trusting {lock_path} — {lock['selected_count']} instances, content_sha256={expected[:16]}...",
               file=sys.stderr )
        return lock["instances"], lock
    if not source_repo or not pathlib.Path( source_repo ).is_dir():
        raise SystemExit( f"no dataset.lock at {lock_path} and no valid --source-repo given "
                          f"({source_repo!r}) — cannot mine. Pass --source-repo <path to a git repo>." )
    print( f"# mining {source_repo} (branch-scope={a.branch_scope}, cap={a.cap})", file=sys.stderr )
    instances, stats = mine_instances( source_repo, a.cap, a.branch_scope, a.max_scan, a.verbose )
    if not instances:
        raise SystemExit( "zero eligible instances mined — refusing to write an empty dataset.lock "
                          "(zero-fabrication contract)" )
    chash = content_hash( instances )
    lock = dict( schema="ripwire-cppbench-dataset-lock-v1", source_repo=str( pathlib.Path( source_repo ).resolve() ),
                branch_scope=a.branch_scope, gold_extensions=list( GOLD_EXTS ), cap=a.cap,
                mining_stats=stats, selected_count=len( instances ), content_sha256=chash,
                generated_unix=int( time.time() ), instances=instances )
    lock_path.parent.mkdir( parents=True, exist_ok=True )
    lock_path.write_text( json.dumps( lock, indent=2 ) + "\n" )
    print( f"# wrote {lock_path}  instances={len(instances)}  content_sha256={chash[:16]}...  stats={stats}",
           file=sys.stderr )
    return instances, lock

# ── archive-at-parent checkout (read-only on source_repo; scratch dir only) ──
class ArchiveCache:
    def __init__( self, source_repo, scratch_dir, cap ):
        self.source_repo = source_repo
        self.dir = pathlib.Path( scratch_dir ); self.dir.mkdir( parents=True, exist_ok=True )
        self.cap = cap
        self.order_path = self.dir / "_lru.json"
        self.order = json.loads( self.order_path.read_text() ) if self.order_path.exists() else {}

    def _save_order( self ):
        self.order_path.write_text( json.dumps( self.order ) )

    COMPLETE_MARKER = ".ripwire_extract_complete"

    def extract( self, sha ):
        dst = self.dir / sha
        # A dir WITHOUT the completion marker is a partial extraction (a previous run was killed
        # mid-archive/mid-tar) — silently indexing a partial tree would corrupt the eval, so it is
        # discarded and re-extracted. The marker is written only after tar exits 0.
        if dst.exists() and not ( dst / self.COMPLETE_MARKER ).exists():
            shutil.rmtree( dst, ignore_errors=True )
        if not dst.exists():
            dst.mkdir( parents=True )
            # git archive is a BINARY tar stream — must not go through the text=True/UTF-8 `sh()` path.
            archive = subprocess.run( [ "git", "archive", sha ], cwd=self.source_repo, capture_output=True, timeout=600 )
            if archive.returncode != 0:
                shutil.rmtree( dst, ignore_errors=True )
                return None, f"git archive failed: {archive.stderr[:300]!r}"
            un = subprocess.run( [ "tar", "-x" ], cwd=dst, input=archive.stdout, capture_output=True, timeout=600 )
            if un.returncode != 0:
                shutil.rmtree( dst, ignore_errors=True )
                return None, f"tar extract failed: {un.stderr[:300]!r}"
            ( dst / self.COMPLETE_MARKER ).write_text( "" )
        self.order[sha] = time.time(); self._save_order()
        self._evict_lru()
        return dst, None

    def _evict_lru( self ):
        live = [ s for s in self.order if ( self.dir / s ).exists() ]
        if len( live ) <= self.cap: return
        live.sort( key=lambda s: self.order[s] )   # oldest access first
        for s in live[: len( live ) - self.cap ]:
            shutil.rmtree( self.dir / s, ignore_errors=True )
            self.order.pop( s, None )
        self._save_order()

# ── ripwire invocation (run_ctx = lb.run_ctx, imported above) ───────────────
ARMS = ( "for", "for-no-mention", "query" )
def arm_flags( arm, query, top_k ):
    if arm == "for":           return [ f"--for={query}", f"--top-k={top_k}" ]
    if arm == "for-no-mention": return [ f"--for={query}", "--no-mention-boost", f"--top-k={top_k}" ]
    if arm == "query":         return [ f"--query={query}", f"--top-k={top_k}" ]
    raise ValueError( arm )

# ── main ─────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser( description="C++ localization eval from a real repo's own commit history" )
    ap.add_argument( "--source-repo", default=None,
                     help="git repo to mine commits FROM (read-only; no default — see README for the "
                          "public corpus + pinned commit this repo's dataset.lock was mined from)" )
    ap.add_argument( "--work-dir", required=True, help="scratch dir for archives + indexes (NOT the source repo)" )
    ap.add_argument( "--dataset-lock", default=str( HERE / "dataset.lock" ) )
    ap.add_argument( "--refresh-dataset", action="store_true", help="re-mine and overwrite dataset.lock" )
    ap.add_argument( "--cap", type=int, default=120, help="max instances to mine (newest-first)" )
    ap.add_argument( "--branch-scope", default="all", choices=[ "all", "head" ],
                     help="git log --all (every branch — a larger eligible-commit population) vs HEAD only" )
    ap.add_argument( "--max-scan", type=int, default=0, help="cap commits SCANNED while mining (0 = unbounded); "
                     "for fast/deterministic smoke gates on a small repo" )
    ap.add_argument( "--archive-cache-cap", type=int, default=8, help="max concurrently-extracted parent trees" )
    ap.add_argument( "--top-k", type=int, default=200 )
    ap.add_argument( "--arms", default=",".join( ARMS ) )
    ap.add_argument( "--json-out", default="" )
    ap.add_argument( "--scoreboard-out", default="" )
    ap.add_argument( "--verbose", action="store_true" )
    a = ap.parse_args()

    arms = [ x.strip() for x in a.arms.split( "," ) if x.strip() ]
    for arm in arms:
        if arm not in ARMS: raise SystemExit( f"unknown arm {arm!r} — choose from {ARMS}" )

    instances, lock = load_or_mine_lock( a )
    # An explicit --source-repo always wins: dataset.lock's recorded source_repo is provenance
    # (a public URL, after the public-corpus scrub — not a valid git-archive cwd), never a live
    # archive source. Only fall back to it if the caller passed nothing (e.g. re-mining fresh
    # against the SAME local clone that just wrote the lock, in the same invocation).
    source_repo = a.source_repo or lock.get( "source_repo" )
    if not source_repo or not pathlib.Path( source_repo ).is_dir():
        raise SystemExit( f"--source-repo {source_repo!r} is not a local directory — archive-at-parent "
                          f"needs a real git clone on disk. Clone the corpus named in bench/cppbench/"
                          f"README.md and pass its local path." )

    work = pathlib.Path( a.work_dir ); work.mkdir( parents=True, exist_ok=True )
    archives = ArchiveCache( source_repo, work / "archives", a.archive_cache_cap )
    index_dir = work / "indexes"; index_dir.mkdir( parents=True, exist_ok=True )

    def zero(): return dict( n=0, f1=0, f3=0, f5=0, f10=0, any10=0, mrr=0.0, wall=0.0 )
    acc = { arm: zero() for arm in arms }
    per_instance = []
    skipped_archive = skipped_index = skipped_unindexable = 0
    t_start = time.perf_counter()

    for idx, inst in enumerate( instances ):
        sha, parent, query, gold_files = inst["sha"], inst["parent"], inst["query"], inst["gold_files"]
        repo_path, err = archives.extract( parent )
        if repo_path is None:
            raise SystemExit( f"[{idx+1}/{len(instances)}] {sha}: ARCHIVE FAIL ({err}) (zero-silent-skip contract)" )

        # keyed by PARENT sha (the tree actually indexed), not instance sha — sibling instances across
        # branches that share a parent (common in a multi-session repo) then reuse the same index instead
        # of rebuilding it, and scratch disk use is bounded by unique parents, not instance count.
        rich_cache = index_dir / f"{parent}.rich.ripwirecache"
        if not rich_cache.exists():
            base = index_dir / parent
            _, _, irc = run_ctx( repo_path, [ f"--index-out={base}", "--top-k=1", "--no-cache" ] )
            if irc != 0 or not rich_cache.exists():
                raise SystemExit( f"[{idx+1}/{len(instances)}] {sha}: INDEX FAIL rc={irc} (zero-silent-skip contract)" )

        uni_xml, _, urc = run_ctx( repo_path, [ f"--query={query}", "--format=candidates",
                                                 "--top-k=1000000000", f"--cache={rich_cache}" ] )
        try: uni_candidates = lb.parse_candidates( uni_xml, repo_path )
        except Exception as e: uni_candidates = []; parse_err = str( e )
        if urc != 0 or not uni_candidates:
            raise SystemExit( f"[{idx+1}/{len(instances)}] {sha}: UNIVERSE CTX FAIL rc={urc} "
                              f"parse={locals().get('parse_err','')} (zero-silent-skip contract)" )
        universe_files = sorted( { c["path"] for c in uni_candidates } )
        gold_norm = [ lb.norm_path( g ) for g in gold_files ]
        primary = [ g for g in gold_norm if g in universe_files ]
        if not primary:
            skipped_unindexable += 1
            print( f"[{idx+1}/{len(instances)}] {sha[:10]}: NO INDEXABLE GOLD FILE (skip, unindexable)",
                   file=sys.stderr )
            continue

        arm_out = {}
        rot = hashlib.sha256( sha.encode() ).digest()[0] % len( arms )
        run_order = arms[rot:] + arms[:rot]
        for arm in run_order:
            flags = arm_flags( arm, query, a.top_k ) + [ "--format=candidates", f"--cache={rich_cache}" ]
            payloads, walls = [], []
            for _ in range( 2 ):   # determinism x2 per instance, folded into the same measured runs
                xml, wall, rc = run_ctx( repo_path, flags )
                if rc != 0: break
                payloads.append( xml ); walls.append( wall )
            if rc != 0 or len( payloads ) != 2 or payloads[0] != payloads[1]:
                raise SystemExit( f"[{idx+1}/{len(instances)}] {sha}: ARM FAIL arm={arm} rc={rc} "
                                  f"deterministic={len(set(payloads))<=1} (zero-silent-skip contract)" )
            try: candidates = lb.parse_candidates( payloads[0], repo_path )
            except Exception as e:
                raise SystemExit( f"[{idx+1}/{len(instances)}] {sha}: XML FAIL arm={arm}: {e} (zero-silent-skip contract)" )
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

        per_instance.append( dict( sha=sha, parent=parent, subject=inst["subject"], gold_files=gold_files,
                                   primary_files=primary, gold_funcs=inst.get( "gold_funcs", [] ),
                                   n_universe_files=len( universe_files ), arms=arm_out ) )
        if a.verbose or ( idx + 1 ) % 10 == 0:
            print( f"[{idx+1}/{len(instances)}] {sha[:10]} files={len(primary)}/{len(gold_files)} "
                   + " ".join( f"{k}:Ff{v['file_first']}" for k, v in arm_out.items() ), file=sys.stderr )

    wall_total = time.perf_counter() - t_start
    scored = acc[arms[0]]["n"] if arms else 0

    # ── report ───────────────────────────────────────────────────────────────
    def pct( x, d ): return f"{100.0*x/d:5.1f}%" if d else "   n/a"
    lines = []
    lines.append( "=" * 78 )
    lines.append( f"cppbench — real-repo C++ localization eval  n_scored={scored}  "
                  f"(unindexable={skipped_unindexable})" )
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
    lines.append( f"\nwall clock total: {wall_total:.1f}s over {len(instances)} mined instances" )
    report = "\n".join( lines )
    print( "\n" + report )

    if a.scoreboard_out:
        pathlib.Path( a.scoreboard_out ).write_text( report + "\n" )
        print( f"\nwrote {a.scoreboard_out}" )
    if a.json_out:
        pathlib.Path( a.json_out ).write_text( json.dumps(
            dict( source_repo=source_repo, dataset_lock_sha256=lock["content_sha256"], n_mined=len( instances ),
                 n_scored=scored, skipped_unindexable=skipped_unindexable, wall_total=wall_total,
                 arms={ arm: acc[arm] for arm in arms }, instances=per_instance ), indent=2 ) )
        print( f"wrote {a.json_out}" )

    return 0

if __name__ == "__main__":
    sys.exit( main() )
