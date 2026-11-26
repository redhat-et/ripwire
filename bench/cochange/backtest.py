#!/usr/bin/env python3
"""Co-change partner backtest: does ripwire's --situ partner list name the file a real commit also touched?

The protocol is stated in bench/cochange/README.md, and this file implements exactly that. In brief, it
draws a seeded sample of multi-file commits and checks out each one's FIRST PARENT in a --shared clone. From
there it asks ripwire, and two independent baselines, to rank the files missing from the seed set. Every arm
sees only history reachable from that parent.

    backtest.py --repo R --tip SHA --since DATE [--until DATE] [--root SUBDIR] --n 200 --ripwire BIN --work DIR --out F.jsonl
    backtest.py --summarize F.jsonl [F2.jsonl ...]
    backtest.py --self-test

--leak-future is for the gate only. It reads history at the TIP instead of the parent, which is the exact
defect the time-order rule forbids. The gate runs it to prove the fixture can see a leak.
"""
import argparse
import datetime
import json
import os
import random
import re
import subprocess
import sys

KS = ( 1, 5, 10 )
TOP = 10
MAX_COMMIT_PATHS = 30      # ripwire's miner drops commits with more files than this (gitCommitFileSets(..., 30))
WINDOW_MONTHS = 18         # --situ's co-change window, "18mo@HEAD"
SUPPORT_FLOOR = 3          # cochangePartners' kSupport
SAMPLE_SEED = 1126
ARMS = ( "ripwire", "samedir", "cofreq", "cofreq3" )
PROTOCOLS = ( "L1O", "SEED1" )
REFUSE_RE = re.compile( r"--situ: '(.+?)' matches no indexed file" )


# ── metrics ──────────────────────────────────────────────────────────────────────────────────────────────
def hit_at( ranked, targets, k ):
    """1 if any target is among the first k ranked candidates, else 0."""
    tset = set( targets )
    return 1 if any( r in tset for r in ranked[:k] ) else 0


def recall_at( ranked, targets, k ):
    """|top-k ∩ targets| / |targets|. An empty target set is a caller bug, not a zero."""
    if not targets:
        raise ValueError( "recall_at: empty target set" )
    return len( set( ranked[:k] ) & set( targets ) ) / len( set( targets ) )


def rank_scores( scores, exclude ):
    """Score desc, then path asc; candidates with score < 1 and excluded paths are dropped."""
    rows = [ ( -s, p ) for p, s in scores.items() if s >= 1 and p not in exclude ]
    rows.sort()
    return [ p for _, p in rows ]


# ── git plumbing ─────────────────────────────────────────────────────────────────────────────────────────
def git( repo, *args ):
    r = subprocess.run( [ "git", "-C", repo, "-c", "core.quotepath=false", *args ], capture_output=True, text=True,
                        errors="replace" )
    if r.returncode != 0:
        raise RuntimeError( "git %s failed: %s" % ( " ".join( args ), r.stderr.strip() ) )
    return r.stdout


def months_before_epoch( epoch, months ):
    """Mirror of gitmine.h monthsBeforeEpoch: UTC calendar-month subtraction, day-of-month carried unclamped."""
    dt = datetime.datetime.fromtimestamp( epoch, datetime.timezone.utc )
    sec_of_day = dt.hour * 3600 + dt.minute * 60 + dt.second
    idx = dt.year * 12 + ( dt.month - 1 ) - months
    ny, nm = idx // 12, idx % 12 + 1
    day0 = datetime.date( ny, nm, 1 ) + datetime.timedelta( days=dt.day - 1 )
    return int( datetime.datetime( day0.year, day0.month, day0.day, tzinfo=datetime.timezone.utc ).timestamp() ) + sec_of_day


def under_root( path, root ):
    return root == "" or path.startswith( root )


def eligible_commits( repo, tip, since, until, root ):
    """Non-merge commits reachable from tip in [since, until], <=30 paths, >=2 'M' paths under root."""
    args = [ "log", tip, "--no-merges", "--no-renames", "--name-status", "--format=@@%H %P %ct", "--since=" + since ]
    if until:
        args.append( "--until=" + until )
    out = []
    cur = None

    def flush():
        if cur and len( cur[ "parents" ] ) == 1 and cur[ "npaths" ] <= MAX_COMMIT_PATHS:
            mods = sorted( p for p in cur[ "mods" ] if under_root( p, root ) )
            if len( mods ) >= 2:
                out.append( { "sha": cur[ "sha" ], "parent": cur[ "parents" ][0], "ct": cur[ "ct" ], "mods": mods } )

    for line in git( repo, *args ).splitlines():
        if line.startswith( "@@" ):
            flush()
            parts = line[2:].split()
            cur = { "sha": parts[0], "parents": parts[1:-1], "ct": int( parts[-1] ), "mods": [], "npaths": 0 }
        elif line.strip() and cur is not None:
            status, _, path = line.partition( "\t" )
            cur[ "npaths" ] += 1
            if status == "M":
                cur[ "mods" ].append( path )
    flush()
    return out


def sample_commits( commits, n, seed ):
    pool = sorted( commits, key=lambda c: c[ "sha" ] )
    picked = pool if len( pool ) <= n else random.Random( seed ).sample( pool, n )
    return sorted( picked, key=lambda c: ( c[ "ct" ], c[ "sha" ] ) )


def window_history( repo, ref, root ):
    """Per-commit path sets reachable from ref, in the 18-month window anchored on ref's committer date."""
    anchor = int( git( repo, "log", "-1", "--format=%ct", ref ).strip() )
    since = "@%d" % months_before_epoch( anchor, WINDOW_MONTHS )
    sets = []
    cur = None
    for line in git( repo, "log", ref, "-c", "--name-only", "--format=@@%H", "--since=" + since ).splitlines():
        if line.startswith( "@@" ):
            if cur:
                sets.append( cur )
            cur = set()
        elif line.strip() and cur is not None:
            cur.add( line )
    if cur:
        sets.append( cur )
    return [ { p for p in s if under_root( p, root ) } for s in sets if len( s ) <= MAX_COMMIT_PATHS ]


def tree_files( repo, ref, root ):
    return { p for p in git( repo, "ls-tree", "-r", "--name-only", ref ).splitlines() if under_root( p, root ) }


# ── the arms ─────────────────────────────────────────────────────────────────────────────────────────────
def arm_samedir( seeds, files ):
    dirs = {}
    for s in seeds:
        d = os.path.dirname( s )
        dirs[d] = dirs.get( d, 0 ) + 1
    scores = { f: dirs[ os.path.dirname( f ) ] for f in files if os.path.dirname( f ) in dirs }
    return rank_scores( scores, set( seeds ) )[:TOP]


def arm_cofreq( seeds, history, files, floor ):
    sset = set( seeds )
    scores = {}
    for s in history:
        if s & sset:
            for f in s:
                scores[f] = scores.get( f, 0 ) + 1
    scores = { f: v for f, v in scores.items() if v >= floor and f in files }
    return rank_scores( scores, sset )[:TOP]


def run_ripwire( binary, crawl, files ):
    r = subprocess.run( [ binary, crawl, "--situ=" + ",".join( files ), "--limit=%d" % TOP ], capture_output=True,
                        text=True, errors="replace" )
    return r.returncode, r.stdout, r.stderr


def parse_situ_partners( text ):
    """Rows of section [3]: '        <path>  (co-edited in N% of commits)'."""
    rows = []
    inside = False
    for line in text.splitlines():
        if line.startswith( "  [3] co-change" ):
            inside = True
            continue
        if inside:
            if not line.startswith( "        " ):
                break
            m = re.match( r"^\s+(\S.*?)  \(co-edited in \d+% of commits\)$", line )
            if m:
                rows.append( m.group( 1 ) )
    return rows


UNUSED_RE = re.compile( r"^  unused item=(.+?) reason=" )


def parse_situ_unused( text ):
    """Items of --situ's `unused:` block: listed files that resolved to no indexed file (AF5, situ.h)."""
    return [ m.group( 1 ) for m in ( UNUSED_RE.match( l ) for l in text.splitlines() ) if m ]


def probe_indexed( binary, crawl, files ):
    """The files ripwire indexes. A mixed list answers and names the rest in `unused:`; an all-unindexed list refuses."""
    if not files:
        return [], None
    rc, out, err = run_ripwire( binary, crawl, files )
    if rc == 0:
        unused = set( parse_situ_unused( out ) )
        return [ f for f in files if f not in unused ], None
    if REFUSE_RE.search( err ):
        return [], None
    return [], "unparsed probe failure rc=%d: %s" % ( rc, err.strip()[:200] )


def arm_ripwire( binary, crawl, seeds, root ):
    if not seeds:
        return [], None
    rel = [ s[len( root ):] for s in seeds ]
    rc, out, err = run_ripwire( binary, crawl, rel )
    if rc != 0:
        return [], "ripwire rc=%d: %s" % ( rc, err.strip()[:200] )
    return [ root + p for p in parse_situ_partners( out ) ][:TOP], None


# ── the run ──────────────────────────────────────────────────────────────────────────────────────────────
def prepare_clone( repo, work ):
    clone = os.path.join( work, "clone" )
    if not os.path.isdir( os.path.join( clone, ".git" ) ):
        os.makedirs( work, exist_ok=True )
        subprocess.run( [ "git", "clone", "-q", "--shared", "--no-checkout", repo, clone ], check=True )
    return clone


def score_task( ranked, targets ):
    row = { "hit@%d" % k: hit_at( ranked, targets, k ) for k in KS }
    row[ "recall@10" ] = recall_at( ranked, targets, TOP )
    return row


def run_commit( args, clone, c, binary ):
    ref = args.tip if args.leak_future else c[ "parent" ]
    subprocess.run( [ "git", "-C", clone, "checkout", "-q", "--detach", "-f", ref ], check=True )
    crawl = os.path.join( clone, args.root ) if args.root else clone
    files = tree_files( clone, ref, args.root )
    history = window_history( clone, ref, args.root )
    mods = c[ "mods" ]
    rel_indexed, perr = probe_indexed( binary, crawl, [ m[len( args.root ):] for m in mods ] )
    indexed = { args.root + p for p in rel_indexed }
    rng_l1o = random.Random( "l1o:%d:%s" % ( args.seed, c[ "sha" ] ) )
    rng_s1 = random.Random( "seed1:%d:%s" % ( args.seed, c[ "sha" ] ) )
    held = rng_l1o.choice( mods )
    one = rng_s1.choice( mods )
    tasks = { "L1O": ( [ m for m in mods if m != held ], [ held ] ), "SEED1": ( [ one ], [ m for m in mods if m != one ] ) }
    rows = []
    for proto, ( seeds, targets ) in tasks.items():
        rw_seeds = [ s for s in seeds if s in indexed ]
        ranked = {
            "samedir": arm_samedir( seeds, files ),
            "cofreq": arm_cofreq( seeds, history, files, 1 ),
            "cofreq3": arm_cofreq( seeds, history, files, SUPPORT_FLOOR ),
        }
        ranked[ "ripwire" ], rerr = arm_ripwire( binary, crawl, rw_seeds, args.root )
        rows.append( {
            "sha": c[ "sha" ], "parent": c[ "parent" ], "ref": ref, "protocol": proto, "seeds": seeds, "targets": targets,
            "seeds_dropped": len( seeds ) - len( rw_seeds ),
            "indexed": bool( rw_seeds ) and all( t in indexed for t in targets ),
            "history_commits": len( history ), "error": rerr or perr,
            "ranked": ranked, "scores": { a: score_task( ranked[a], targets ) for a in ARMS },
        } )
    return rows


def run( args ):
    binary = os.path.abspath( args.ripwire )
    commits = eligible_commits( args.repo, args.tip, args.since, args.until, args.root )
    picked = sample_commits( commits, args.n, args.seed )
    clone = prepare_clone( args.repo, args.work )
    meta = { "meta": { "repo": os.path.basename( os.path.abspath( args.repo ) ), "tip": git( args.repo, "rev-parse", args.tip ).strip(),
                       "since": args.since, "until": args.until, "root": args.root, "eligible": len( commits ),
                       "sampled": len( picked ), "seed": args.seed, "leak_future": args.leak_future,
                       "ripwire_version": subprocess.run( [ binary, "--version" ], capture_output=True, text=True ).stdout.strip() } }
    done = set()
    if args.resume and os.path.exists( args.out ):
        with open( args.out ) as fh:
            done = { json.loads( l ).get( "sha" ) for l in fh if l.strip() }
    with open( args.out, "a" if done else "w" ) as fh:
        if not done:
            fh.write( json.dumps( meta ) + "\n" )
        for i, c in enumerate( picked ):
            if c[ "sha" ] in done:
                continue
            if args.guard and subprocess.run( args.guard, shell=True ).returncode != 0:
                print( "guard tripped before %s: stopped at %d/%d; rerun with --resume" % ( c[ "sha" ][:9], i, len( picked ) ), file=sys.stderr )
                return 3
            for row in run_commit( args, clone, c, binary ):
                fh.write( json.dumps( row ) + "\n" )
            fh.flush()
            if args.progress:
                print( "[%d/%d] %s" % ( i + 1, len( picked ), c[ "sha" ][:9] ), file=sys.stderr )
    return 0


# ── summary ──────────────────────────────────────────────────────────────────────────────────────────────
def summarize( paths ):
    lines = []
    for path in paths:
        with open( path ) as fh:
            recs = [ json.loads( l ) for l in fh if l.strip() ]
        meta = recs[0].get( "meta", {} )
        rows = [ r for r in recs if "protocol" in r ]
        lines.append( "## %s @ %s root=%r eligible=%s sampled=%s errors=%d" % (
            meta.get( "repo" ), meta.get( "tip", "" )[:9], meta.get( "root", "" ), meta.get( "eligible" ), meta.get( "sampled" ),
            sum( 1 for r in rows if r.get( "error" ) ) ) )
        lines.append( "| protocol | population | n | arm | Hit@1 | Hit@5 | Hit@10 | Recall@10 |" )
        lines.append( "|---|---|---|---|---|---|---|---|" )
        for proto in PROTOCOLS:
            for pop in ( "all", "indexed" ):
                sel = [ r for r in rows if r[ "protocol" ] == proto and ( pop == "all" or r[ "indexed" ] ) ]
                for arm in ARMS:
                    if not sel:
                        lines.append( "| %s | %s | 0 | %s | - | - | - | - |" % ( proto, pop, arm ) )
                        continue
                    hits = { k: sum( r[ "scores" ][ arm ][ "hit@%d" % k ] for r in sel ) for k in KS }
                    rec = sum( r[ "scores" ][ arm ][ "recall@10" ] for r in sel ) / len( sel )
                    lines.append( "| %s | %s | %d | %s | %s | %s | %s | %.3f |" % (
                        proto, pop, len( sel ), arm, *( "%.3f (%d)" % ( hits[k] / len( sel ), hits[k] ) for k in KS ), rec ) )
    return "\n".join( lines )


# ── self-test: the metric arithmetic on hand-computed cases ──────────────────────────────────────────────
def self_test():
    fails = []

    def check( name, got, want ):
        if got != want:
            fails.append( "%s: got %r want %r" % ( name, got, want ) )

    ranked = [ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k" ]
    check( "hit@1 first", hit_at( ranked, [ "a" ], 1 ), 1 )
    check( "hit@1 second", hit_at( ranked, [ "b" ], 1 ), 0 )
    check( "hit@5 fifth", hit_at( ranked, [ "e" ], 5 ), 1 )
    check( "hit@5 sixth", hit_at( ranked, [ "f" ], 5 ), 0 )
    check( "hit@10 tenth", hit_at( ranked, [ "j" ], 10 ), 1 )
    check( "hit@10 eleventh", hit_at( ranked, [ "k" ], 10 ), 0 )
    check( "hit@10 empty ranking", hit_at( [], [ "a" ], 10 ), 0 )
    check( "hit any of many", hit_at( ranked, [ "zz", "c" ], 5 ), 1 )
    check( "recall 2 of 4", recall_at( ranked, [ "a", "j", "k", "zz" ], 10 ), 0.5 )
    check( "recall dup targets", recall_at( ranked, [ "a", "a" ], 10 ), 1.0 )
    check( "rank ties by path", rank_scores( { "b": 2, "a": 2, "c": 3, "z": 0 }, set() ), [ "c", "a", "b" ] )
    check( "rank excludes seeds", rank_scores( { "a": 5, "b": 1 }, { "a" } ), [ "b" ] )
    check( "samedir", arm_samedir( [ "x/a", "x/b", "y/c" ], { "x/a", "x/b", "x/d", "y/e", "z/f" } ), [ "x/d", "y/e" ] )
    hist = [ { "s", "t" }, { "s", "t" }, { "s", "u" }, { "v", "t" } ]
    check( "cofreq", arm_cofreq( [ "s" ], hist, { "s", "t", "u", "v" }, 1 ), [ "t", "u" ] )
    check( "cofreq3 floor", arm_cofreq( [ "s" ], hist + [ { "s", "t" } ], { "s", "t", "u" }, 3 ), [ "t" ] )
    check( "cofreq drops files not at parent", arm_cofreq( [ "s" ], hist, { "s", "u" }, 1 ), [ "u" ] )
    # 2026-03-31 minus 1 month: day 31 carried into an absent Feb 31 -> Mar 3 (gitmine.h's unclamped rule)
    e = int( datetime.datetime( 2026, 3, 31, 12, 0, tzinfo=datetime.timezone.utc ).timestamp() )
    check( "months_before_epoch unclamped", months_before_epoch( e, 1 ),
           int( datetime.datetime( 2026, 3, 3, 12, 0, tzinfo=datetime.timezone.utc ).timestamp() ) )
    check( "months_before_epoch 18", months_before_epoch( int( datetime.datetime( 2026, 11, 26, tzinfo=datetime.timezone.utc ).timestamp() ), 18 ),
           int( datetime.datetime( 2025, 5, 26, tzinfo=datetime.timezone.utc ).timestamp() ) )
    situ = ( "  [3] co-change — usually edited with these but NOT in your diff (2) window=\"18mo@HEAD\" commits=\"5\":\n"
             "        src/b.c  (co-edited in 80% of commits)\n"
             "        lib/x y.c  (co-edited in 7% of commits)\n"
             "  next: --test-gate\n" )
    check( "parse situ partners", parse_situ_partners( situ ), [ "src/b.c", "lib/x y.c" ] )
    check( "parse situ unused", parse_situ_unused( "unused: 1 listed item(s) not used\n  unused item=t/x y.tsv reason=not_indexed\n" ), [ "t/x y.tsv" ] )
    check( "parse situ empty", parse_situ_partners( "  [3] co-change (0):\n        (none, or no git history)\n" ), [] )
    try:
        recall_at( ranked, [], 10 )
        fails.append( "recall_at on empty targets did not raise" )
    except ValueError:
        pass
    for f in fails:
        print( "SELF-TEST FAIL " + f )
    print( "SELF-TEST PASS" if not fails else "SELF-TEST FAILED (%d)" % len( fails ) )
    return 0 if not fails else 1


def main():
    ap = argparse.ArgumentParser( description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter )
    ap.add_argument( "--repo" )
    ap.add_argument( "--tip", default="HEAD" )
    ap.add_argument( "--since" )
    ap.add_argument( "--until", default="" )
    ap.add_argument( "--root", default="", help="crawl subdirectory, with a trailing slash (e.g. pkg/)" )
    ap.add_argument( "--n", type=int, default=200 )
    ap.add_argument( "--seed", type=int, default=SAMPLE_SEED )
    ap.add_argument( "--ripwire" )
    ap.add_argument( "--work" )
    ap.add_argument( "--out" )
    ap.add_argument( "--progress", action="store_true" )
    ap.add_argument( "--resume", action="store_true", help="append to --out, skipping commits already in it" )
    ap.add_argument( "--guard", help="shell command run before each commit; non-zero stops the run (exit 3)" )
    ap.add_argument( "--leak-future", action="store_true", help="GATE ONLY: read history at the tip (the forbidden defect)" )
    ap.add_argument( "--summarize", nargs="+" )
    ap.add_argument( "--self-test", action="store_true" )
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    if args.summarize:
        print( summarize( args.summarize ) )
        return 0
    missing = [ n for n in ( "repo", "since", "ripwire", "work", "out" ) if not getattr( args, n ) ]
    if missing:
        ap.error( "missing --" + ", --".join( missing ) )
    if args.root and not args.root.endswith( "/" ):
        ap.error( "--root must end with '/'" )
    return run( args )


if __name__ == "__main__":
    sys.exit( main() )
