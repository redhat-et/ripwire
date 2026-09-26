#!/usr/bin/env python3
# runrepo.py — one repository end to end, in the §11 order: resolve T and the windows, build the population
# and run the health checks, compute the RANKING table, compute the LABEL table, hash both, and only then
# join and score (metrics.py). Nothing here reads a score before both tables are written and hashed.
#
#   python3 runrepo.py --clone DIR --full-name owner/name --stratum cpp --out OUTDIR
#       [--ref REF] [--route A|B|K] [--links-cache FILE] [--offline] [--windows main|pilot-ripwire]
#       [--grain file] [--seal]
#
# --grain file  is S5 (the only grain runnable today: the function grain needs the independent parser, see
#               README "Parser status"; this driver refuses --grain function rather than fall back to
#               ripwire's own parse).
# --seal        writes the scores to OUTDIR/scores.sealed.json and prints only its SHA-256 (the §12 pilot rule:
#               its Popt table is not read before the main verdict).
import argparse, json, os, subprocess, sys, time

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
import common, labels, maphunks, metrics, rankers


def product_units( repo, rev, stratum, blobs ):
    """{path: loc} of product source at rev (§1 path+name rule, plus the generated marker in the first 5
    lines), and the counts the health report needs."""
    out = common.git( repo, "ls-tree", "-r", "-z", "--full-tree", rev )
    units, gen, cand = {}, 0, 0
    for rec in out.split( "\x00" ):
        if not rec:
            continue
        meta, path = rec.split( "\t", 1 )
        mode, typ, sha = meta.split()
        if typ != "blob" or mode == "120000" or not common.is_product_path( path, stratum ):
            continue
        cand += 1
        data = blobs.get( sha ) or b""
        if common.is_generated_head( data[ :4096 ].decode( "utf-8", "replace" ) ):
            gen += 1
            continue
        units[ path ] = max( 1, maphunks.line_count( data ) )
    return units, dict( path_rule_files=cand, generated_dropped=gen, units=len( units ) )


def windows_for( kind, chain ):
    if kind == "main":
        return [ ( k, labels.iso_to_epoch( lo ), labels.iso_to_epoch( hi ) ) for k, lo, hi in common.WINDOWS ]
    if kind == "pilot-ripwire":                        # §12: T <= 2026-08-31, a one-month window
        return [ ( 1, labels.iso_to_epoch( "2026-08-31T23:59:59Z" ), labels.iso_to_epoch( "2026-09-30T23:59:59Z" ) ) ]
    raise ValueError( kind )


def label_window( repo, fixes_by_rule, path_chain, wincommits, t_index, t_sha ):
    """Walk the first-parent path from T; for every window commit that is a fix under a rule, record the
    T-files its hunks touch. Returns ({rule: {path_at_T: d}}, mechanics counters)."""
    tracker = maphunks.RenameTracker()
    fixed = { r: {} for r in fixes_by_rule }
    whole = lambda p: [ ( "", "<file>", 0, 1, 10 ** 12 ) ]          # file grain: the whole file is the unit
    t_paths = { k[ 0 ] for k in t_index }
    n = dict( fix_commits={ r: 0 for r in fixes_by_rule }, walked=0, hunks=dict( hunks=0, mapped=0, unmapped=0, born_after_t=0, out_of_population=0 ) )
    wins = set( wincommits )
    fixes = sorted( { s for s in wins if any( s in v for v in fixes_by_rule.values() ) } )
    # a fix needs its hunks; every other commit on the path only moves the rename map (two git processes total)
    diffs = maphunks.first_parent_diffs( repo, fixes )
    ns = maphunks.first_parent_name_status( repo, t_sha, path_chain[ -1 ] ) if path_chain else {}
    for sha in path_chain:
        rules = [ r for r, s in fixes_by_rule.items() if sha in s ] if sha in wins else []
        files = diffs[ sha ] if rules else ns[ sha ]
        n[ "walked" ] += 1
        if rules:
            hit, cnt = maphunks.touched_units( files, whole, tracker, t_index, t_paths )
            for k2, v in cnt.items():
                n[ "hunks" ][ k2 ] += v
            for r in rules:
                n[ "fix_commits" ][ r ] += 1
                for key in hit:
                    fixed[ r ][ key[ 0 ] ] = fixed[ r ].get( key[ 0 ], 0 ) + 1
        tracker.advance( files )
    return fixed, n


def sha_json( obj, path ):
    with open( path, "w" ) as fh:
        json.dump( obj, fh, indent=0, sort_keys=True )
    return common.sha256_file( path )


def main( argv ):
    ap = argparse.ArgumentParser()
    ap.add_argument( "--clone", required=True )
    ap.add_argument( "--full-name", required=True )
    ap.add_argument( "--stratum", required=True, choices=common.STRATUM_ORDER )
    ap.add_argument( "--out", required=True )
    ap.add_argument( "--ref", default="HEAD" )
    ap.add_argument( "--route", default="A", choices=( "A", "B", "K" ) )
    ap.add_argument( "--links-cache" )
    ap.add_argument( "--offline", action="store_true" )
    ap.add_argument( "--windows", default="main" )
    ap.add_argument( "--grain", default="file" )
    ap.add_argument( "--seal", action="store_true" )
    ap.add_argument( "--ripwire", default="ripwire" )
    a = ap.parse_args( argv )
    if a.grain != "file":
        sys.exit( "runrepo: --grain %s needs the independent tree-sitter parser (§4.3), which is not available; "
                  "refusing to fall back to ripwire's own parse" % a.grain )
    os.makedirs( a.out, exist_ok=True )
    clock = {}
    t0 = time.time()
    repo = a.clone
    manifest = dict( full_name=a.full_name, stratum=a.stratum, grain=a.grain, route=a.route, windows_kind=a.windows,
                     ripwire=rankers.ripwire_version( a.ripwire ), ref=common.git( repo, "rev-parse", a.ref ).strip(), windows=[] )
    if common.RIPWIRE_VERSION not in manifest[ "ripwire" ]:
        sys.exit( "runrepo: ripwire version is not %s: %s" % ( common.RIPWIRE_VERSION, manifest[ "ripwire" ] ) )
    chain = labels.first_parent_chain( repo, a.ref )
    blobs = maphunks.Blobs( repo )
    wt = os.path.join( a.out, "checkout" )
    ranking, label_table = {}, {}
    for k, lo, hi in windows_for( a.windows, chain ):
        w = dict( k=k )
        t_sha = labels.resolve_t( chain, lo )
        w[ "T" ] = t_sha
        if not t_sha:
            w[ "status" ] = "no_T"
            manifest[ "windows" ].append( w )
            continue
        ts = time.time()
        units, ucount = product_units( repo, t_sha, a.stratum, blobs )
        w[ "population" ] = ucount
        clock.setdefault( "population", 0 )
        clock[ "population" ] += time.time() - ts
        # ripwire on a clean detached checkout of T
        ts = time.time()
        if not os.path.exists( wt ):
            common.git( repo, "worktree", "add", "--detach", "-f", wt, t_sha )
        else:
            common.git( wt, "checkout", "-q", "--detach", "-f", t_sha )
        common.git( wt, "clean", "-q", "-fdx" )
        header, hot_rows = rankers.run_hotspots( wt, a.ripwire )
        clock[ "ripwire_hotspots" ] = clock.get( "ripwire_hotspots", 0 ) + time.time() - ts
        ts = time.time()
        mcounts, mrows = rankers.run_metrics( wt, a.ripwire )
        clock[ "ripwire_metrics" ] = clock.get( "ripwire_metrics", 0 ) + time.time() - ts
        skipped = rankers.run_skipped( wt, a.ripwire )
        dirty = common.git( wt, "status", "--porcelain", "--untracked-files=all" ).strip()
        health = rankers.health_hotspots( header, t_sha )
        read_frac, n_pruned, n_unread = rankers.ripwire_read_fraction( units, skipped )
        w[ "ripwire_read" ] = dict( fraction=round( read_frac, 4 ), pruned_dir_units=n_pruned, skipped_units=n_unread )
        if read_frac < common.PARSE_FLOOR:
            health.append( "ripwire read %.3f of product files < %.2f (pruned dirs %d, skipped %d)" % ( read_frac, common.PARSE_FLOOR, n_pruned, n_unread ) )
        if dirty:
            health.append( "checkout dirty after ripwire: %d paths" % len( dirty.split( "\n" ) ) )
        w[ "ripwire" ] = dict( hotspots_header={ k2: header.get( k2 ) for k2 in ( "window", "at", "files", "ranked", "unranked_no_churn",
                                                                                   "unranked_no_complexity", "unranked_extent_suspect" ) },
                               metrics_counts=mcounts, metrics_rows=len( mrows ), health_failures=health )
        # look-back predictors
        ts = time.time()
        lb, since = rankers.lookback_commits( repo, t_sha )
        clock[ "lookback" ] = clock.get( "lookback", 0 ) + time.time() - ts
        arms, diag = rankers.file_arms( units, hot_rows, mrows, lb )
        seen_by_rw = set( hot_rows ) | { r[ "p" ] for r in mrows }
        w[ "arms_diag" ] = dict( diag, lookback_commits=len( lb ), lookback_since=since,
                                 units_seen_by_ripwire=sum( 1 for p in units if p in seen_by_rw ) )
        ranking[ str( k ) ] = dict( loc=units, arms=arms )
        # labels (never joined to the ranking before both are hashed)
        ts = time.time()
        wincommits, path_chain = labels.window_commits( chain, t_sha, lo, hi )
        w[ "window_commits" ] = len( wincommits )
        links = None
        if a.route == "A":
            links = labels.GhLinks( a.full_name, a.links_cache, offline=a.offline )
        repo_labels = links.repo_labels() if links else []
        merged = labels.merged_messages_batch( repo, t_sha, path_chain[ -1 ], path_chain ) if path_chain else {}
        lab = labels.label_commits( repo, a.full_name, wincommits, repo_labels, links, merged )
        rules = { "keyword": { s for s, v in lab.items() if v[ "keyword" ] }, "B": { s for s, v in lab.items() if v[ "route_b" ] } }
        if a.route == "A":
            rules[ "A" ] = { s for s, v in lab.items() if v[ "route_a" ] }
        fixed, n = label_window( repo, rules, path_chain, wincommits, { ( p, "", "<file>", 0 ) for p in units }, t_sha )
        clock[ "labels" ] = clock.get( "labels", 0 ) + time.time() - ts
        w[ "label_mechanics" ] = dict( n, gh_graphql_calls=links.calls if links else 0 )
        w[ "fixed_units" ] = { r: len( v ) for r, v in fixed.items() }
        label_table[ str( k ) ] = dict( fixed=fixed, commits={ s: dict( A=v[ "route_a" ], B=v[ "route_b" ], K=v[ "keyword" ] ) for s, v in lab.items() } )
        manifest[ "windows" ].append( w )
    blobs.close()
    if os.path.exists( wt ):
        common.git( repo, "worktree", "remove", "--force", wt )
    manifest[ "ranking_sha256" ] = sha_json( ranking, os.path.join( a.out, "ranking_table.json" ) )
    manifest[ "label_sha256" ] = sha_json( label_table, os.path.join( a.out, "label_table.json" ) )
    # ── join and score, once ─────────────────────────────────────────────────────────────────────────────
    ts = time.time()
    primary = { "A": "A", "B": "B", "K": "keyword" }[ a.route ]
    scores = {}
    for w in manifest[ "windows" ]:
        k = str( w[ "k" ] )
        if k not in ranking:
            continue
        if w[ "ripwire" ][ "health_failures" ]:           # §4.3: a failed floor is a replacement, never a scored window
            scores[ k ] = dict( dropped="health", failures=w[ "ripwire" ][ "health_failures" ] )
            continue
        per = {}
        for rule in sorted( label_table[ k ][ "fixed" ] ):
            fx = label_table[ k ][ "fixed" ][ rule ]
            if len( fx ) < common.EVENT_FLOOR:
                per[ rule ] = dict( dropped="event_floor", fixed=len( fx ) )
                continue
            per[ rule ] = {}
            for arm in rankers.ARMS_FILE:
                R = ranking[ k ]
                units = [ ( R[ "arms" ][ p ][ arm ], R[ "loc" ][ p ], 1 if p in fx else 0 ) for p in sorted( R[ "loc" ] ) ]
                per[ rule ][ arm ] = metrics.score_arm( units )
        scores[ k ] = per
    clock[ "score" ] = time.time() - ts
    manifest[ "primary_rule" ] = primary
    manifest[ "runtime_s" ] = { k2: round( v, 1 ) for k2, v in clock.items() }
    manifest[ "runtime_s" ][ "total" ] = round( time.time() - t0, 1 )
    spath = os.path.join( a.out, "scores.sealed.json" if a.seal else "scores.json" )
    manifest[ "scores_sha256" ] = sha_json( scores, spath )
    manifest[ "scores_file" ] = os.path.basename( spath )
    with open( os.path.join( a.out, "manifest.json" ), "w" ) as fh:
        json.dump( manifest, fh, indent=1, sort_keys=True )
    print( json.dumps( { k2: manifest[ k2 ] for k2 in ( "full_name", "ranking_sha256", "label_sha256", "scores_sha256", "runtime_s" ) }, sort_keys=True ) )


if __name__ == "__main__":
    main( sys.argv[ 1: ] )
