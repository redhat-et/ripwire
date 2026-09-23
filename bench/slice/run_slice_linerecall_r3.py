#!/usr/bin/env python3
"""run_slice_linerecall_r3.py — the ARISE-lane fork of run_slice_linerecall.py that actually produced
this lane's results.json (arise-result review Condition B: commit the code that produced the numbers
beside the numbers).

Base: `bench/slice/run_slice_linerecall.py` on `origin/lane/research-arise-slice` (unmerged; that
branch's own copy is unchanged by this lane). This fork adds exactly the R3 (def-primacy,
arise-line-ranking-prereg.md §3.1) arm the pre-reg's §8 names as a one-line extension: a new
`slice_hasdef_lines()` reads each row's `k=` attribute ("def"/"both" -> hasAnyDef=1), unioned across
every inventory variable's v1 rows (seed-free, same substrate `cover[]` already scans), and `r3` is
added to `rank_scores()`'s order table as `sorted(span, key=lambda n: (-hasdef[n], -cover[n], n))` —
otherwise byte-for-byte the same measurement arms as the base file. An independent reviewer
reconstructed an equivalent extension from the same pre-reg text and reproduced this lane's
`results.json` (173 rows) with 0 field differences and a byte-identical `verdict.json`
(`reports/rv-arise-line-ranking.md`, result-review section).

Protocol, fixed before this ran: docs/research/slice-line-recall.md §§2-5. Input is the gold file
produced by bench/slice/locbench_gold.py (which never invokes ripwire, so gold cannot move when the
binary does). Output is one json with every per-instance row plus the summary tables.

What it does per carried row:
  - materialize the ONE target file at base_commit into a scratch tree (`git show`, read-only on the
    checkout) — sound because --slice is intra-procedural by declaration;
  - resolve the selector: --slice=SEL (inventory, gives the definition's start line) and
    --expand=SEL (gives the body, hence the span);
  - restrict gold to the span; everything outside is reachability loss, not a slicer miss;
  - arms v1 (--slice=SEL:VAR) and v2 (--slice=SEL:VAR --slice-flow=both) for EVERY inventory
    variable (seed-free), so the ranking rules never look at the gold;
  - metrics (a) set recall, (b) Recall@k for R0 / R1 / R2 / R2-oracle / R3 / random control,
    (c) cost in bytes and wall-clock ms, (d) the §5 fixed-budget granularity comparison.

Usage:
  python3 bench/slice/run_slice_linerecall_r3.py --gold gold.json --bin build/ripwire \
      --work DIR [--json results.json] [--limit N]
"""

import argparse, json, random, re, statistics, subprocess, sys, time
from pathlib import Path

from _common import git, line_text, name_lines         # one definition, shared across bench/slice

S_ROW   = re.compile( r'<s\b([^>]*)>' )
ATTR    = re.compile( r'(\w+)="([^"]*)"' )
V_ROW   = re.compile( r'<v\b([^>]*)/>' )
SLICE_H = re.compile( r'<slice\b([^>]*)>' )
WORD    = re.compile( r"[A-Za-z_]\w*" )
BUDGETS = ( 512, 1024, 2048, 4096 )
KS      = ( 1, 3, 5, 10, 20 )
SEED    = 20260920
SHUFFLES = 200


def attrs( s ):
    return dict( ATTR.findall( s ) )


def run( binary, tree, args ):
    t0 = time.perf_counter()
    r = subprocess.run( [ binary, str( tree ) ] + args, capture_output=True, text=True, errors="replace" )
    ms = ( time.perf_counter() - t0 ) * 1000.0
    return r.returncode, r.stdout, len( r.stdout.encode() ), ms


def slice_rows( out ):
    """[(line, role, depth)] for every <s> row; a row without d= is a v1 (depth 0) row."""
    rows = []
    for a in ( attrs( m.group( 1 ) ) for m in S_ROW.finditer( out ) ):
        if "l" not in a:
            continue
        rows.append( ( int( a[ "l" ] ), a.get( "t", "" ), int( a.get( "d", "0" ) ) ) )
    return rows


def slice_hasdef_lines( out ):
    """{line: 1} for every <s> row whose k= is "def" or "both" -- ARISE R3 (def-primacy)'s own
    hasAnyDef(l) input, read straight off the same rows slice_rows() already parses (prereg §8's named
    one-line extension: k=, not t=)."""
    got = {}
    for a in ( attrs( m.group( 1 ) ) for m in S_ROW.finditer( out ) ):
        if "l" not in a:
            continue
        if a.get( "k", "" ) in ( "def", "both" ):
            got[ int( a[ "l" ] ) ] = 1
    return got


def recall_at_k( order, gold, k ):
    if not gold:
        return None
    return len( set( order[ :k ] ) & gold ) / len( gold )


def mrr( order, gold ):
    for i, ln in enumerate( order, 1 ):
        if ln in gold:
            return 1.0 / i
    return 0.0


def control_curve( pool, gold, rng ):
    """mean Recall@k and MRR of a uniform random permutation of the same candidate pool."""
    acc = { k: 0.0 for k in KS }; acc_mrr = 0.0
    pool = list( pool )
    for _ in range( SHUFFLES ):
        rng.shuffle( pool )
        for k in KS:
            acc[ k ] += recall_at_k( pool, gold, k )
        acc_mrr += mrr( pool, gold )
    return { k: acc[ k ] / SHUFFLES for k in KS }, acc_mrr / SHUFFLES


def pack( numbered, budget ):
    """line numbers delivered when `numbered` [(n, text)] is packed until budget bytes."""
    used, got = 0, []
    for n, text in numbered:
        piece = f"{n}: {text}\n".encode()
        if used + len( piece ) > budget:
            break
        used += len( piece ); got.append( n )
    return got


def rank_scores( span, gold, cover, depth, depth_o, rng, hasdef=None ):
    """§4(b): Recall@k and MRR for R0/R1/R2/R2-oracle/R3 and the random control, plus the R2 order.

    R0 is plain source order, R1 orders by how many inventory variables' flat slices cover the line,
    R2 by the flow depth that reached it, R2-oracle by the same depth restricted to the gold-touching
    seeds, R3 (arise-line-ranking-prereg.md §3.1, def-primacy) by (hasAnyDef desc, coverage desc, line
    asc) over the SAME whole-span pool R0/R1/CTL already use, and CTL is the mean over SHUFFLES
    permutations of the same candidate pool."""
    hasdef = hasdef or {}
    orders = { "r0": list( span ),
               "r1": sorted( span, key=lambda n: ( -cover[ n ], n ) ),
               "r2": sorted( span, key=lambda n: ( depth[ n ], -cover[ n ], n ) ),
               "oracle": sorted( span, key=lambda n: ( depth_o[ n ], -cover[ n ], n ) ),
               "r3": sorted( span, key=lambda n: ( -hasdef.get( n, 0 ), -cover[ n ], n ) ) }
    ctl, ctl_mrr = control_curve( span, gold, rng )
    out = { f"mrr_{t}": mrr( o, gold ) for t, o in orders.items() }
    out[ "mrr_ctl" ] = ctl_mrr
    for k in KS:
        for t, o in orders.items():
            out[ f"{t}@{k}" ] = recall_at_k( o, gold, k )
        out[ f"ctl@{k}" ] = ctl[ k ]
    return orders[ "r2" ], out


def budget_scores( span, gold, lines, r2_order, cover, span_bounds ):
    """§5: the share of gold lines delivered under each byte budget at each granularity.

    Every payload is line-numbered `N: text`, so the numbering costs the same in each arm and the
    score is an exact line-number match. `file_window` is the strongest fair file-level arm: it packs
    outward from the function's centre instead of from the file's first line."""
    start, span_end = span_bounds
    mid = ( start + span_end ) // 2
    txt = lambda n: line_text( lines, n )
    file_head   = [ ( n, txt( n ) ) for n in range( 1, len( lines ) + 1 ) ]
    file_window = sorted( file_head, key=lambda t: ( abs( t[ 0 ] - mid ), t[ 0 ] ) )
    symbol      = [ ( n, txt( n ) ) for n in span ]
    line_level  = [ ( n, txt( n ) ) for n in r2_order ]
    line_filt   = [ ( n, txt( n ) ) for n in
                    [ n for n in span if cover[ n ] > 0 ] + [ n for n in span if cover[ n ] == 0 ] ]
    arms = ( ( "file_head", file_head ), ( "file_window", file_window ), ( "symbol", symbol ),
             ( "line_filtered", line_filt ), ( "line", line_level ) )
    out = {}
    for b in BUDGETS:
        for name, payload in arms:
            out[ f"budget{b}_{name}" ] = len( set( pack( payload, b ) ) & gold ) / len( gold )
        out[ f"budget{b}_symbol_fits" ] = sum( len( f"{n}: {t}\n".encode() ) for n, t in symbol ) <= b
    return out


def measure_instance( binary, tree, r, sink, tag ):
    """measure ONE carried row; return its instance row, or None when a stage disqualifies it.

    `sink` carries everything that outlives one row: `skips` and `acc` are the disclosure counters
    (why a row dropped out, and the per-gold-line reachability cascade), `varinst` and `timings`
    collect the per-variable rows and the wall clock, and `rng` is the control's seeded generator.
    Every early return is a counted skip, never a silent one."""
    skips, varinst, timings, acc, rng = ( sink[ "skips" ], sink[ "varinst" ], sink[ "timings" ],
                                          sink[ "acc" ], sink[ "rng" ] )
    src = tree / Path( r[ "path" ] ).name
    show = git( r[ "repo_dir" ], "show", f"{r['base_commit']}:{r['path']}", ok_fail=True )
    if show.returncode != 0:
        skips[ "no_body" ] += 1; return None
    src.write_text( show.stdout )
    lines = show.stdout.splitlines()

    sel = r[ "selector" ]
    rc_inv, inv_out, inv_bytes, inv_ms = run( binary, tree, [ f"--slice={sel}" ] )
    if rc_inv != 0:
        skips[ "selector_scoped_refused" if r[ "scoped" ] else "selector_refused" ] += 1
        return None
    head = attrs( SLICE_H.search( inv_out ).group( 1 ) )
    start = int( head[ "p" ].rsplit( ":", 1 )[ 1 ] )
    invent = [ attrs( m.group( 1 ) )[ "n" ] for m in V_ROW.finditer( inv_out ) ]

    rc_exp, exp_out, exp_bytes, exp_ms = run( binary, tree, [ f"--expand={sel}" ] )
    # the body CDATA is followed by </b> only when the definition has no callees; with callees a
    # <calls> element sits between, so anchor on the CDATA close, never on </b>.
    body = re.search( r"<b\b[^>]*><!\[CDATA\[(.*?)\]\]>", exp_out, re.S )
    if rc_exp != 0 or not body:
        skips[ "no_body" ] += 1; return None
    span_end = start + len( body.group( 1 ).splitlines() ) - 1
    span = list( range( start, span_end + 1 ) )
    gold_all = set( r[ "gold" ] )
    acc[ "resolved" ] += len( gold_all )
    gold = { n for n in gold_all if start <= n <= span_end }
    acc[ "in_span" ] += len( gold )
    if not gold:
        skips[ "gold_all_outside_span" ] += 1; return None
    if not invent:
        skips[ "empty_inventory" ] += 1
        # still counted in the reachability cascade above; no v1/v2 arm exists for it
        return { "instance_id": r[ "instance_id" ], "empty_inventory": True,
                 "gold_total": len( gold_all ), "gold_in_span": len( gold ),
                 "span_lines": len( span ) }

    # ---- arms, seed-free: every inventory variable, v1 and v2 ------------------------------
    v1_by_var, v2_by_var, v1_bytes, v2_bytes = {}, {}, [], []
    hasdef = {}   # R3 (def-primacy): hasAnyDef(l), unioned across every inventory variable's v1 rows
    for var in invent:
        rc1, o1, b1, ms1 = run( binary, tree, [ f"--slice={sel}:{var}" ] )
        rc2, o2, b2, ms2 = run( binary, tree, [ f"--slice={sel}:{var}", "--slice-flow=both" ] )
        timings.append( ( "v1", ms1 ) ); timings.append( ( "v2", ms2 ) )
        if rc1 == 0:
            v1_by_var[ var ] = slice_rows( o1 ); v1_bytes.append( b1 )
            hasdef.update( slice_hasdef_lines( o1 ) )
        if rc2 == 0:
            v2_by_var[ var ] = slice_rows( o2 ); v2_bytes.append( b2 )
    timings.append( ( "inv", inv_ms ) ); timings.append( ( "expand", exp_ms ) )

    def text_of( n ): return line_text( lines, n )
    names = name_lines( show.stdout )
    touched = sorted( { v for n in gold for v in WORD.findall( text_of( n ) ) if v in v1_by_var } )
    if touched:
        acc[ "naming_local" ] += len( { n for n in gold
                                        if any( re.search( r"\b%s\b" % re.escape( v ), text_of( n ) ) for v in touched ) } )

    # (a) set recall, per (instance, variable)
    for var in touched:
        rel = [ n for n in sorted( gold ) if re.search( r"\b%s\b" % re.escape( var ), text_of( n ) ) ]
        if not rel:
            continue                                   # this variable contributes no (instance, var) pair
        l1 = { ln for ln, _, _ in v1_by_var[ var ] }
        l2 = { ln for ln, _, _ in v2_by_var.get( var, [] ) }
        hit1 = sum( 1 for n in rel if n in l1 )
        hit2 = sum( 1 for n in rel if n in l2 )
        rel_s = [ n for n in rel if n in names.get( var, () ) ] if names is not None else None
        varinst.append( {
            "instance_id": r[ "instance_id" ], "var": var, "relevant": len( rel ),
            "v1_line_recall": hit1 / len( rel ), "v1_hit_all": hit1 == len( rel ),
            "v2_line_recall": hit2 / len( rel ),
            "v1_overinclusion": len( l1 ) / len( rel ), "v2_overinclusion": len( l2 ) / len( rel ),
            "v1_missed": [ { "line": n, "text": text_of( n ).strip()[ :160 ] } for n in rel if n not in l1 ],
            "relevant_strict": ( len( rel_s ) if rel_s is not None else None ),
            "v1_line_recall_strict": ( ( sum( 1 for n in rel_s if n in l1 ) / len( rel_s ) ) if rel_s else None ),
            "v1_hit_all_strict": ( all( n in l1 for n in rel_s ) if rel_s else None ),
        } )

    # (b) rank: R1 coverage, R2 flow depth, R2-oracle, random control
    cover = { n: 0 for n in span }
    for var, rr in v1_by_var.items():
        for ln in { x[ 0 ] for x in rr }:
            if ln in cover:
                cover[ ln ] += 1
    depth = { n: 10 ** 6 for n in span }
    for var, rr in v2_by_var.items():
        for ln, _, d in rr:
            if ln in depth:
                depth[ ln ] = min( depth[ ln ], d )
    depth_o = { n: 10 ** 6 for n in span }
    for var in touched:
        for ln, _, d in v2_by_var.get( var, [] ):
            if ln in depth_o:
                depth_o[ ln ] = min( depth_o[ ln ], d )

    r2_order, rank = rank_scores( span, gold, cover, depth, depth_o, rng, hasdef )
    row = { "instance_id": r[ "instance_id" ], "repo": r[ "repo" ], "scoped": r[ "scoped" ],
            "span_lines": len( span ), "gold_total": len( gold_all ), "gold_in_span": len( gold ),
            "inventory": len( invent ), "touched_vars": len( touched ),
            "inv_bytes": inv_bytes, "expand_bytes": exp_bytes,
            "v1_bytes_mean": statistics.mean( v1_bytes ) if v1_bytes else None,
            "v2_bytes_mean": statistics.mean( v2_bytes ) if v2_bytes else None,
            "covered_lines": sum( 1 for n in span if cover[ n ] > 0 ),
            "flow_lines": sum( 1 for n in span if depth[ n ] < 10 ** 6 ),
            **rank,
            **budget_scores( span, gold, lines, r2_order, cover, ( start, span_end ) ) }

    print( f"[{tag}] {r['instance_id']} span={len(span)} gold={len(gold)}/{len(gold_all)} "
           f"inv={len(invent)} touched={len(touched)}", file=sys.stderr )
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--gold", required=True )
    ap.add_argument( "--bin", default="build/ripwire" )
    ap.add_argument( "--work", required=True, help="scratch directory for the one-file trees" )
    ap.add_argument( "--json", default=None )
    ap.add_argument( "--limit", type=int, default=0 )
    a = ap.parse_args()

    binary = str( Path( a.bin ).resolve() )
    work = Path( a.work ).resolve(); work.mkdir( parents=True, exist_ok=True )
    gold_doc = json.loads( Path( a.gold ).read_text() )
    rows = gold_doc[ "instances" ]
    if a.limit:
        rows = rows[ :a.limit ]

    skips = { "selector_refused": 0, "selector_scoped_refused": 0, "no_body": 0,
              "gold_all_outside_span": 0, "empty_inventory": 0 }
    inst, varinst, timings = [], [], []
    acc = { "resolved": 0, "in_span": 0, "naming_local": 0 }
    sink = { "skips": skips, "varinst": varinst, "timings": timings, "acc": acc,
             "rng": random.Random( SEED ) }
    gold_carried = sum( len( x[ "gold" ] ) for x in rows )

    for i, r in enumerate( rows ):
        tree = work / f"i{i:04d}"
        tree.mkdir( exist_ok=True )
        row = measure_instance( binary, tree, r, sink, f"{i+1}/{len(rows)}" )
        if row is not None:
            inst.append( row )
    # ---- summary -------------------------------------------------------------------------------
    scored = [ x for x in inst if not x.get( "empty_inventory" ) ]
    def m( key, src=None ):
        vals = [ x[ key ] for x in ( src if src is not None else scored ) if x.get( key ) is not None ]
        return statistics.mean( vals ) if vals else None
    tl = lambda tag: [ ms for t, ms in timings if t == tag ]
    summary = {
        "binary": binary, "gold_file": a.gold,
        "rows_in": len( rows ), "scored_instances": len( scored ), "skips": skips,
        "var_instances": len( varinst ),
        "gold_lines_carried": gold_carried, "gold_lines_after_resolve": acc[ "resolved" ],
        "gold_lines_in_span": acc[ "in_span" ],
        "gold_lines_naming_a_sliceable_local": acc[ "naming_local" ],
        "v1_line_recall_mean": statistics.mean( [ x[ "v1_line_recall" ] for x in varinst ] ) if varinst else None,
        "v1_hit_all_rate": ( sum( 1 for x in varinst if x[ "v1_hit_all" ] ) / len( varinst ) ) if varinst else None,
        "v1_line_recall_strict_mean": ( statistics.mean( [ x[ "v1_line_recall_strict" ] for x in varinst if x[ "v1_line_recall_strict" ] is not None ] )
                                        if any( x[ "v1_line_recall_strict" ] is not None for x in varinst ) else None ),
        "v1_hit_all_strict_rate": ( ( sum( 1 for x in varinst if x[ "v1_hit_all_strict" ] ) /
                                      sum( 1 for x in varinst if x[ "v1_hit_all_strict" ] is not None ) )
                                    if any( x[ "v1_hit_all_strict" ] is not None for x in varinst ) else None ),
        "var_instances_strict": sum( 1 for x in varinst if x[ "v1_line_recall_strict" ] is not None ),
        "v2_line_recall_mean": statistics.mean( [ x[ "v2_line_recall" ] for x in varinst ] ) if varinst else None,
        "v1_overinclusion_mean": statistics.mean( [ x[ "v1_overinclusion" ] for x in varinst ] ) if varinst else None,
        "v2_overinclusion_mean": statistics.mean( [ x[ "v2_overinclusion" ] for x in varinst ] ) if varinst else None,
        "span_lines_mean": m( "span_lines" ), "inventory_mean": m( "inventory" ),
        "covered_frac_mean": statistics.mean( [ x[ "covered_lines" ] / x[ "span_lines" ] for x in scored ] ) if scored else None,
        "flow_frac_mean": statistics.mean( [ x[ "flow_lines" ] / x[ "span_lines" ] for x in scored ] ) if scored else None,
        "mrr": { t: m( f"mrr_{t}" ) for t in ( "r0", "r1", "r2", "r3", "oracle", "ctl" ) },
        "bytes": { "inv": m( "inv_bytes" ), "v1": m( "v1_bytes_mean" ), "v2": m( "v2_bytes_mean" ), "expand": m( "expand_bytes" ) },
        "ms": { t: { "mean": statistics.mean( tl( t ) ), "median": statistics.median( tl( t ) ), "n": len( tl( t ) ) }
                for t in ( "inv", "v1", "v2", "expand" ) if tl( t ) },
    }
    summary[ "recall_at_k" ] = { t: { k: m( f"{t}@{k}" ) for k in KS } for t in ( "r0", "r1", "r2", "r3", "oracle", "ctl" ) }
    summary[ "budget" ] = { b: { name: m( f"budget{b}_{name}" ) for name in ( "file_head", "file_window", "symbol", "line_filtered", "line" ) }
                            for b in BUDGETS }
    fits = { b: [ x for x in scored if x.get( f"budget{b}_symbol_fits" ) ] for b in BUDGETS }
    summary[ "budget_symbol_does_not_fit" ] = {
        b: { "n": len( scored ) - len( fits[ b ] ),
             **{ name: ( statistics.mean( [ x[ f"budget{b}_{name}" ] for x in scored if not x.get( f"budget{b}_symbol_fits" ) ] )
                        if len( scored ) > len( fits[ b ] ) else None )
                 for name in ( "file_head", "file_window", "symbol", "line_filtered", "line" ) } }
        for b in BUDGETS }
    print( json.dumps( summary, indent=2 ) )
    if a.json:
        Path( a.json ).write_text( json.dumps( { "summary": summary, "instances": inst, "var_instances": varinst }, indent=2 ) )
        print( f"wrote {a.json}", file=sys.stderr )


if __name__ == "__main__":
    main()
