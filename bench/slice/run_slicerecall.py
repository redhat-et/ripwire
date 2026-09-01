#!/usr/bin/env python3
"""run_slicerecall.py — the --slice line-recall measurement, exactly as registered in docs/EVALS.md
(§ "The --slice def-use primitive" registered the v1 shape 2026-08-28; § "--slice-flow — ARISE rung 2"
registered the corpus, mining rule, arms and cap 2026-08-30, BEFORE this harness first ran).

Corpus: fix-shaped commits from THIS repository's own history (family: cpp), newest first, capped at
the newest 40 qualifying. "Fix-shaped" is operationalized as a subject containing 'fix' (case-
insensitive). A commit QUALIFIES when:
  - `git diff -U0` against its first parent confines every ADDED line to cpp-family files
    (.h/.hpp/.cpp/.cc/.cxx) and to ONE function per git's own C/C++ hunk funcnames (one file, one
    funcname across all added-line hunks);
  - that function resolves uniquely in the index at that commit (--slice=file:fn answers);
  - at least one added line names a sliceable local from the function's own --slice inventory.

Instances are (commit, function, variable) triples. Arms, all on the SAME instances at the commit's
own tree (a detached git worktree; nothing in the live checkout is touched):
  (a) v1  --slice=file:fn:var          per-variable line-recall (hit = every added line naming var
                                       appears among its rows) + rows-emitted/lines-relevant
                                       over-inclusion — the v1 registration's own metrics;
  (b) v2  ... --slice-flow=both        FUNCTION-level added-line recall (|added ∩ slice lines| /
                                       |added|) for the v1 rows vs the v2 rows — the rung-2 delta;
  (c) --expand=file:fn                 the whole-body baseline: recall 1.0 by construction, priced in
                                       raw output bytes (recall and cost reported together, §5);
  (d) v3  ... --slice-flow=both --slice-guards
                                       the rung-3 arm: the same function-level added-line recall with
                                       the control-dependence <g> rows counted as slice lines, plus
                                       the share of instances the mechanism itself declares degraded.
                                       Registered in docs/EVALS.md 2026-08-31 BEFORE any feature code
                                       existed; the v3-v2 delta is PAIRED (both arms run per instance
                                       inside one invocation, on one binary, at one pinned tree).

Deterministic given the commit list. Usage:
  python3 bench/slice/run_slicerecall.py [--bin build/ripwire] [--repo .] [--cap 40] [--json out.json]

`--repo` may be ANY git tree, which is how the 2026-08-31 wider-corpus extension runs it: point it at
a throwaway copy of a D4-pinned external corpus checked out DETACHED at its pin (the mine walks the
log from HEAD, so the pin alone fixes the commit list) while `--bin` stays this tree's binary. The
cap applies PER REPO. Neither the qualification rules nor any metric changed for that extension; the
external path needed only byte-tolerant subprocess decoding and per-reason skip counters, both below.

Known mining limits, stated rather than discovered later: git's funcname heuristic names the nearest
PRECEDING function header, so a hunk that INSERTS a whole new function attributes to its neighbor —
such commits either fail unique resolution or measure the neighbor honestly; deletion-only commits
never qualify (added lines are the anchor, and they must exist in the post-commit tree).
"""

import argparse, json, re, subprocess, sys, tempfile, shutil, os
from pathlib import Path

CPP_EXT = { ".h", ".hpp", ".cpp", ".cc", ".cxx" }
WORD    = re.compile( r"[A-Za-z_]\w*" )
# every LINE-BEARING row the invocation emits. <g> joined <s> when --slice-guards shipped
# (2026-08-31): docs/EVALS.md's registration fixes the counting rule as "guard rows count as slice
# lines", and requires this regex to be extended in the SAME commit as any new element tag — a v3 arm
# reading an <s>-only regex would silently re-measure v2. <g> never appears in the v1/v2 arms' output,
# so widening it here leaves their numbers byte-identical.
ROW_L   = re.compile( r'<[sg] l="(\d+)"' )
V_ROW   = re.compile( r'<v n="([^"]+)"' )
# the ROOT ELEMENT's open tag. Both guard readers below go through it rather than searching the whole
# document: the guards LEGEND spells guards_degraded="1" in its own prose in order to define it, so a
# substring search over stdout calls every instance degraded (found 2026-08-31 on the first v3 run —
# degraded_share came back 1.00 against a probe showing the attribute absent on that very instance).
ROOT_EL = re.compile( r'<slice [^>]*>' )

def guards_n( out ):
    root = ROOT_EL.search( out )
    m    = re.search( r'guards="(\d+)"', root.group( 0 ) ) if root else None
    return int( m.group( 1 ) ) if m else None

def guards_degraded( out ):
    root = ROOT_EL.search( out )
    return ( 'guards_degraded="1"' in root.group( 0 ) ) if root else None

def sh( args, cwd=None, ok_fail=False ):
    # errors="replace": external corpora carry non-UTF-8 bytes (ugrep's own test fixtures are
    # deliberately latin-1/binary), and a diff that touches one must not abort the mine. Only
    # content bytes are ever mangled — hunk headers and funcnames are ASCII by git's own format —
    # so qualification is unaffected.
    r = subprocess.run( args, cwd=cwd, capture_output=True, text=True, errors="replace" )
    if r.returncode != 0 and not ok_fail:
        raise RuntimeError( f"{args}: rc={r.returncode}\n{r.stderr[:500]}" )
    return r

def fn_name_from_sig( sig ):
    """the identifier before the last '(' of a git funcname line, or the last identifier."""
    cut = sig.rfind( "(" )
    ids = WORD.findall( sig[:cut] if cut > 0 else sig )
    ids = [ i for i in ids if i not in ( "inline", "static", "const", "constexpr", "struct", "class", "template", "typename", "void", "int", "bool", "auto", "std" ) ]
    return ids[-1] if ids else None

def mine( repo, cap, subject_filter ):
    # every non-merge commit, newest first — NOT --first-parent: this repository lands work through
    # merged lanes, so the fix commits overwhelmingly live on the second-parent chains
    log = sh( [ "git", "log", "--no-merges", "--pretty=%H\x01%s" ], cwd=repo ).stdout
    picked = []
    for line in log.splitlines():
        sha, _, subject = line.partition( "\x01" )
        if not re.search( subject_filter, subject, re.I ):
            continue
        d = sh( [ "git", "diff", "-U0", f"{sha}^", sha ], cwd=repo, ok_fail=True )
        if d.returncode != 0:
            continue
        file_cur, funcs, added, bad = None, set(), [], False
        for dl in d.stdout.splitlines():
            if dl.startswith( "+++ b/" ):
                file_cur = dl[6:]
            elif dl.startswith( "@@" ):
                m = re.match( r"@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@ ?(.*)", dl )
                if not m: continue
                start, count, sig = int( m.group( 1 ) ), int( m.group( 2 ) or "1" ), m.group( 3 )
                if count == 0: continue                       # pure deletion hunk
                if file_cur is None or Path( file_cur ).suffix not in CPP_EXT:
                    bad = True; break
                fn = fn_name_from_sig( sig ) if sig else None
                if not fn:
                    bad = True; break
                funcs.add( ( file_cur, fn ) )
                added.extend( range( start, start + count ) )
        if bad or not added or len( funcs ) != 1:
            continue
        ( path, fn ) = next( iter( funcs ) )
        picked.append( { "sha": sha, "subject": subject, "file": path, "fn": fn, "added": sorted( set( added ) ) } )
        if len( picked ) >= cap * 3:                          # over-mine; unique-resolution prunes below
            break
    return picked

def run_ripwire( bin_, tree, args ):
    return subprocess.run( [ bin_, str( tree ) ] + args, capture_output=True, text=True, errors="replace" )

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--bin", default="build/ripwire" )
    ap.add_argument( "--repo", default="." )
    ap.add_argument( "--cap", type=int, default=40 )
    ap.add_argument( "--subject-filter", default=r"\bfix" )
    ap.add_argument( "--json", default=None )
    a = ap.parse_args()

    repo = Path( a.repo ).resolve()
    bin_ = str( Path( a.bin ).resolve() )
    cand = mine( repo, a.cap, a.subject_filter )
    print( f"mined {len(cand)} single-function fix-shaped candidates (pre-resolution)", file=sys.stderr )

    wt = Path( tempfile.mkdtemp( prefix="slicerecall-wt-" ) ) / "tree"
    instances, commits_used = [], 0
    # WHY a candidate did not become an instance — disclosure only, no qualification rule is read
    # from these counters. On a large tree the basename selector is ambiguous far more often than in
    # a small one, and a thin result must be able to say WHICH rule thinned it.
    skips = { "selector_unserved": 0, "empty_inventory": 0, "no_touched_var": 0, "no_rows": 0 }
    try:
        for c in cand:
            if commits_used >= a.cap:
                break
            # A blob-filtered external clone materializes missing blobs from its promisor remote at
            # checkout time, and that fetch can fail transiently (observed once on duckdb: "could not
            # fetch ... from promisor remote", succeeding on the immediate retry). Retry a bounded
            # number of times; a commit that still cannot be checked out raises, so the commit list
            # stays exactly the mine's — never silently shortened.
            for attempt in range( 3 ):
                w = sh( [ "git", "worktree", "add", "--detach", "--force", str( wt ), c["sha"] ], cwd=repo, ok_fail=( attempt < 2 ) )
                if w.returncode == 0:
                    break
                sh( [ "git", "worktree", "remove", "--force", str( wt ) ], cwd=repo, ok_fail=True )
                sh( [ "git", "worktree", "prune" ], cwd=repo, ok_fail=True )
            try:
                base = Path( c["file"] ).name
                sel  = f"{base}:{c['fn']}"
                inv  = run_ripwire( bin_, wt, [ f"--slice={sel}" ] )
                if inv.returncode != 0:
                    skips[ "selector_unserved" ] += 1
                    continue                                   # ambiguous / not found / unserved: skip, disclosed by count
                locals_ = set( V_ROW.findall( inv.stdout ) )
                if not locals_:
                    skips[ "empty_inventory" ] += 1
                    continue
                # the added lines, in the file at THIS commit
                src_lines = ( wt / c["file"] ).read_text( errors="replace" ).splitlines()
                def line_text( n ): return src_lines[ n-1 ] if 0 < n <= len( src_lines ) else ""
                touched_vars = sorted( { v for n in c["added"] for v in WORD.findall( line_text( n ) ) if v in locals_ } )
                if not touched_vars:
                    skips[ "no_touched_var" ] += 1
                    continue
                exp = run_ripwire( bin_, wt, [ f"--expand={sel}" ] )
                expand_bytes = len( exp.stdout.encode() ) if exp.returncode == 0 else None
                commit_rows = []
                for var in touched_vars:
                    v1 = run_ripwire( bin_, wt, [ f"--slice={sel}:{var}" ] )
                    if v1.returncode != 0:
                        continue
                    v1_lines = { int( x ) for x in ROW_L.findall( v1.stdout ) }
                    relevant = [ n for n in c["added"] if re.search( r"\b%s\b" % re.escape( var ), line_text( n ) ) ]
                    if not relevant:
                        continue
                    v2 = run_ripwire( bin_, wt, [ f"--slice={sel}:{var}", "--slice-flow=both" ] )
                    v2_lines = { int( x ) for x in ROW_L.findall( v2.stdout ) } if v2.returncode == 0 else set()
                    v3 = run_ripwire( bin_, wt, [ f"--slice={sel}:{var}", "--slice-flow=both", "--slice-guards" ] )
                    v3_ok    = v3.returncode == 0
                    v3_lines = { int( x ) for x in ROW_L.findall( v3.stdout ) } if v3_ok else set()
                    inter1 = sum( 1 for n in relevant if n in v1_lines )
                    added_in = c["added"]
                    commit_rows.append( {
                        "sha": c["sha"][:9], "fn": c["fn"], "var": var,
                        "v1_line_recall": inter1 / len( relevant ),
                        "v1_hit_all": inter1 == len( relevant ),
                        "v1_overinclusion": ( len( v1_lines ) / len( relevant ) ) if relevant else None,
                        "fn_added_recall_v1": sum( 1 for n in added_in if n in v1_lines ) / len( added_in ),
                        "fn_added_recall_v2": sum( 1 for n in added_in if n in v2_lines ) / len( added_in ),
                        "fn_added_recall_v3": ( sum( 1 for n in added_in if n in v3_lines ) / len( added_in ) ) if v3_ok else None,
                        # the registration's validity precondition (iii), checked per instance rather
                        # than asserted: guards ADD rows, so a v3 line set that is not a superset of
                        # v2's is a mechanism or harness bug, never a result
                        "v3_superset_of_v2": ( v2_lines <= v3_lines ) if v3_ok else None,
                        "v3_guards": guards_n( v3.stdout ) if v3_ok else None,
                        "v3_degraded": guards_degraded( v3.stdout ) if v3_ok else None,
                        "v1_bytes": len( v1.stdout.encode() ),
                        "v2_bytes": len( v2.stdout.encode() ) if v2.returncode == 0 else None,
                        "v3_bytes": len( v3.stdout.encode() ) if v3_ok else None,
                        "expand_bytes": expand_bytes,
                        "added_lines": len( added_in ), "relevant_lines": len( relevant ),
                    } )
                if commit_rows:
                    instances.extend( commit_rows )
                    commits_used += 1
                else:
                    skips[ "no_rows" ] += 1
            finally:
                sh( [ "git", "worktree", "remove", "--force", str( wt ) ], cwd=repo, ok_fail=True )
    finally:
        shutil.rmtree( wt.parent, ignore_errors=True )
        sh( [ "git", "worktree", "prune" ], cwd=repo, ok_fail=True )

    n = len( instances )
    def mean( k ):
        vals = [ r[k] for r in instances if r[k] is not None ]
        return sum( vals ) / len( vals ) if vals else None
    summary = {
        "repo": str( repo ), "candidates_mined": len( cand ), "skips": skips,
        "commits_used": commits_used, "instances": n,
        "v1_line_recall_mean": mean( "v1_line_recall" ),
        "v1_hit_all_rate": ( sum( 1 for r in instances if r["v1_hit_all"] ) / n ) if n else None,
        "v1_overinclusion_mean": mean( "v1_overinclusion" ),
        "fn_added_recall_v1_mean": mean( "fn_added_recall_v1" ),
        "fn_added_recall_v2_mean": mean( "fn_added_recall_v2" ),
        "fn_added_recall_v3_mean": mean( "fn_added_recall_v3" ),
        # the PAIRED statistic the registration banded: computed per instance, then averaged — never
        # as a difference of two independently-averaged arms
        "paired_delta_v3_v2_mean": ( sum( r["fn_added_recall_v3"] - r["fn_added_recall_v2"] for r in instances if r["fn_added_recall_v3"] is not None )
                                     / sum( 1 for r in instances if r["fn_added_recall_v3"] is not None ) )
                                   if any( r["fn_added_recall_v3"] is not None for r in instances ) else None,
        "instances_improved": sum( 1 for r in instances if r["fn_added_recall_v3"] is not None and r["fn_added_recall_v3"] > r["fn_added_recall_v2"] ),
        "instances_worsened": sum( 1 for r in instances if r["fn_added_recall_v3"] is not None and r["fn_added_recall_v3"] < r["fn_added_recall_v2"] ),
        "additivity_violations": sum( 1 for r in instances if r["v3_superset_of_v2"] is False ),
        "degraded_share": ( sum( 1 for r in instances if r["v3_degraded"] ) / n ) if n else None,
        "v1_bytes_mean": mean( "v1_bytes" ), "v2_bytes_mean": mean( "v2_bytes" ), "v3_bytes_mean": mean( "v3_bytes" ),
        "expand_bytes_mean": mean( "expand_bytes" ),
    }
    if summary[ "v2_bytes_mean" ] and summary[ "v3_bytes_mean" ]:
        summary[ "v3_over_v2_bytes" ] = summary[ "v3_bytes_mean" ] / summary[ "v2_bytes_mean" ]
    print( json.dumps( summary, indent=2 ) )
    if a.json:
        Path( a.json ).write_text( json.dumps( { "summary": summary, "instances": instances }, indent=2 ) )
        print( f"wrote {a.json}", file=sys.stderr )

if __name__ == "__main__":
    main()
