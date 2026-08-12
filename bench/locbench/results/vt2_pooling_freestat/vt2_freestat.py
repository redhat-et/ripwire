#!/usr/bin/env python3
# vt2_freestat.py — file-level evidence pooling: the FREE end-to-end statistic (docs/METHODOLOGY.md §7),
# computed BEFORE any mechanism was designed, on the A7 train split (n=254), routed --for arm.
#
# CONTEXT THIS ROUND INHERITS (read FREESTAT.md first): pooling was ALREADY pre-registered
# (../r5_pooling/PREREG.md, 2026-08-06), gridded, and REJECTED ON HELD-OUT at +0.00pp — as a
# CONSTRAINED mechanism (promote-only slot ladder, top-K-sum blend). This script measures the
# UNCONSTRAINED upper bound — full pooled file reordering, no ladder, no blend — for a small fixed
# family of pooling functions, as pure post-processing of the complete routed --for candidate export.
#
# POOLING FAMILY (fixed before any number was seen):
#   max      — control: today's behavior (file = best member). MUST reproduce the baseline run exactly
#              (presence guard: if it does not, the pipeline is wrong and no number may be read).
#   sum      — sum of ALL positive member scores (the file-size-confound end of the family)
#   top2sum  — sum of top-2 positive member scores
#   top3sum  — sum of top-3 positive member scores
#   cw       — count-weighted: max * (1 + log2(1 + n_positive_members))
#
# DECISION BAR (fixed before any number was seen, per r5_pooling's own defect note — thresholds in
# INSTANCES, floor >= 3): MATERIAL iff some non-control fn nets >= +3 multi-file strict@10 instances
# on train AND costs <= 2 single-file strict@10 instances. Otherwise STOP: publish the negative.
#
# Tie-breaking (deterministic): pooled score desc, then best-member export rank asc, then path asc.
#
# RUN:  RIPWIRE=<repo>/build/ripwire LOCBENCH_WORK=<work-dir> python3 vt2_freestat.py [base.json]
#   <work-dir> is the run_locbench.py --work-dir that produced base.json (repos/, datasets/, indexes/).
#   base.json defaults to vt2_train_base.json next to this script
#   (produced by: run_locbench.py --n 560 --split train --arms for --work-dir <work-dir>).
import json, math, os, pathlib, sys, xml.etree.ElementTree as ET

HERE = pathlib.Path( __file__ ).resolve().parent
WORK = pathlib.Path( os.environ.get( "LOCBENCH_WORK", "" ) or sys.exit( "set LOCBENCH_WORK=<work-dir>" ) )
sys.path.insert( 0, str( HERE.parents[1] ) )   # bench/locbench
import run_locbench as rl

def parse_cands_with_scores( xml, repo_path ):
    # Compose the harness's own parser (identity + rank + path normalization) with one score pass —
    # both iterate the same findall("cand") order, so the zip is 1:1 by construction.
    cands  = rl.parse_candidates( xml, repo_path )
    scores = [ float( c.attrib.get( "s", "0" ) ) for c in ET.fromstring( xml ).findall( "cand" ) ]
    return [ ( c["path"], s, c["rank"] ) for c, s in zip( cands, scores ) ]

def ranked_files_first_appearance( rows ):
    seen, out = set(), []
    for p, _, _ in rows:
        if p not in seen: seen.add( p ); out.append( p )
    return out

def pooled_order( rows, fn ):
    # rows: full export (score desc, id asc). Pool POSITIVE member scores per file.
    agg = {}
    for p, s, r in rows:
        e = agg.setdefault( p, dict( scores=[], best_rank=r ) )
        if s > 0.0: e["scores"].append( s )
        e["best_rank"] = min( e["best_rank"], r )
    scored = []
    for p, e in agg.items():
        v = sorted( e["scores"], reverse=True )
        if not v: continue          # a file with no positive evidence is never placed
        if   fn == "max":     sc = v[0]
        elif fn == "sum":     sc = sum( v )
        elif fn == "top2sum": sc = sum( v[:2] )
        elif fn == "top3sum": sc = sum( v[:3] )
        elif fn == "cw":      sc = v[0] * ( 1.0 + math.log2( 1.0 + len( v ) ) )
        else: raise ValueError( fn )
        scored.append( ( -sc, e["best_rank"], p ) )
    scored.sort()
    return [ p for _, _, p in scored ]

def strict10( ranked_files, gold, universe_files ):
    ranks = rl.file_ranks( ranked_files, gold, universe_files )
    return 1 if ranks and all( r is not None and r < 10 for r in ranks ) else 0

def main():
    base_path = pathlib.Path( sys.argv[1] ) if len( sys.argv ) > 1 else HERE / "vt2_train_base.json"
    base = json.loads( base_path.read_text() )
    rows_by_id = { r["instance_id"]: r for r in json.loads(
        ( WORK / "datasets" / "rows_czlll__Loc-Bench_V1_test_560.json" ).read_text() ) }
    fns = [ "max", "sum", "top2sum", "top3sum", "cw" ]
    res = { fn: dict( single=0, multi=0, gains=[], losses=[], sgains=[], slosses=[] ) for fn in fns }
    n_single = n_multi = 0
    control_mismatch = []
    for inst in base["instances"]:
        iid = inst["instance_id"]; row = rows_by_id[iid]
        repo_path = rl.checkout( row["repo"], row["base_commit"], WORK / "repos" )
        assert repo_path is not None, iid
        rich = WORK / "indexes" / ( iid.replace( "/", "__" ) + ".rich.ripwirecache" )
        assert rich.exists(), f"missing rich cache {iid}"
        query = " ".join( row.get( "problem_statement", "" ).split() )[:1200]
        xml, _, rc = rl.run_ctx( repo_path, [ f"--for={query}", "--format=candidates",
                                              "--top-k=1000000000", f"--cache={rich}" ] )
        assert rc == 0, f"ctx fail {iid} rc={rc}"
        rows = parse_cands_with_scores( xml, repo_path )
        universe_files = sorted( { p for p, _, _ in rows } )
        gold = inst["primary_files"]
        stratum = "single" if len( gold ) == 1 else "multi"
        if stratum == "single": n_single += 1
        else:                   n_multi  += 1
        # presence guard: the 200-row prefix must reproduce the recorded arm outcome exactly
        prefix_files = ranked_files_first_appearance( rows[:200] )
        base_hit_recorded = 1 if ( inst["arms"]["for"]["file_worst"] is not None
                                   and inst["arms"]["for"]["file_worst"] < 10 ) else 0
        base_hit_replayed = strict10( prefix_files, gold, universe_files )
        if base_hit_recorded != base_hit_replayed:
            control_mismatch.append( iid )
        for fn in fns:
            hit = strict10( pooled_order( rows, fn ), gold, universe_files )
            res[fn][stratum] += hit
            if hit and not base_hit_replayed:
                ( res[fn]["gains"] if stratum == "multi" else res[fn]["sgains"] ).append( iid )
            if base_hit_replayed and not hit:
                ( res[fn]["losses"] if stratum == "multi" else res[fn]["slosses"] ).append( iid )
    out = dict( n_single=n_single, n_multi=n_multi, control_mismatch=control_mismatch, res=res )
    ( base_path.parent / "vt2_freestat_out.json" ).write_text( json.dumps( out, indent=2 ) )
    print( f"train: single n={n_single}  multi n={n_multi}  control mismatches={len(control_mismatch)} {control_mismatch[:5]}" )
    print( f"{'fn':8} | {'multi@10':>9} | {'single@10':>9} | {'multi +/-':>12} | {'single +/-':>12}" )
    for fn in fns:
        r = res[fn]
        print( f"{fn:8} | {r['multi']:4d} ({100.0*r['multi']/max(1,n_multi):5.2f}%) | "
               f"{r['single']:4d} ({100.0*r['single']/max(1,n_single):5.2f}%) | "
               f"+{len(r['gains'])}/-{len(r['losses'])}          | +{len(r['sgains'])}/-{len(r['slosses'])}" )
    for fn in fns:
        r = res[fn]
        if r["gains"] or r["losses"] or r["slosses"]:
            print( f"{fn}: multi gains={r['gains']} losses={r['losses']} single losses={r['slosses']}" )

if __name__ == "__main__":
    main()
