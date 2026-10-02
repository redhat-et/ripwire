#!/usr/bin/env python3
"""run_cross_fn_reach.py — for gold lines a single-function slice cannot reach, is the enclosing
function reachable from the seed function through ripwire's own call graph, and at what hop depth?

Protocol: docs/research/slice-line-recall.md, section "ARISE rung 3 — cross-function reach, measured
before building it". Reuses the note's existing gold build (locbench_gold.py helpers) and the SAME
instance set (the LocBench V1 test-560 dataset at the pinned checkouts), so this composes with the
already-published 70.8%-out-of-reach ceiling (docs/research/slice-line-recall.md §R3): the population
here is exactly the 208 multi-function rows / 6,809 gold lines that number counts, restricted to rows
whose repository has a local checkout (same availability constraint as the rest of the note).

Unlike run_slice_linerecall.py's one-file trick (sound only because --slice is intra-procedural),
cross-function reach needs the WHOLE tree: a gold line's enclosing function can live in a different
file from the seed. The tree is materialized read-only with `git archive` (the checkout is never
written to, nothing is cloned) — the same technique probe_wholerepo_selector.py already uses to price
the one-file deviation, moved into _common.py so both scripts share it.

Per carried row:
  - seed = edit_functions[0] (the first-listed edited function — deterministic, and the convention
    locbench_gold.py's carry_row already uses for the single-function population). The selector is
    spelled with the FULL relative path, not the basename selector_for() uses for the one-file trick:
    on a whole tree a bare basename is exactly the ambiguity source §R6 priced (12.5% of real-checkout
    selectors), and the patch's own path is already a unique, unambiguous qualifier.
  - every gold line (pre-image rule, G2, reused verbatim from locbench_gold) across EVERY file the
    patch touches, not only the seed's file.
  - a gold line inside the seed's own resolved span is hop0: it was already reachable by today's
    single-function slice had it been pointed at this row at all — a footnote refining the ceiling,
    reported apart from the extension question.
  - every other gold line: --at=@FILE:LINE finds its true enclosing symbol (not the dataset's own
    edit_functions naming, which the task may list imprecisely) or refuses (no indexed definition —
    an import line, a decorator, a module constant, a comment) — reported as its own floor,
    no_enclosing_symbol, because extending call-graph reach cannot help a line with no enclosing call
    at all.
  - distinct enclosing symbols are deduped per row (one --path=SEED,@FILE:LINE call per symbol, not
    per gold line) and classified by hops= / reachable= into unreachable / 1 / 2 / 3+.
  - for an unreachable symbol, --callers=@FILE:LINE and --callees=@FILE:LINE with count="0" on BOTH
    flags it as reading like a leaf — the graph-limits disclosure the protocol requires (a dispatch
    hub reached only by dynamic dispatch/callbacks/macros reads exactly the same way).

--cache=PATH is passed on every call against one row's tree: the first call cold-parses and writes
it, every later call against the same unchanged tree reads it back instead of re-parsing.

Usage:
  python3 bench/slice/run_cross_fn_reach.py --assets DIR --bin build/ripwire --work DIR \
      [--json results.json] [--limit N]
"""

import argparse, json, re, statistics, subprocess, sys, time
from pathlib import Path

from _common import git, archive_tree                  # one definition, shared across bench/slice
from locbench_gold import index_checkouts, file_sections, gold_pre_lines

ATTR   = re.compile( r'(\w+)="([^"]*)"' )
S_ROW  = re.compile( r'<s\b([^>]*)/>' )
BODY_H = re.compile( r"<b\b([^>]*)><!\[CDATA\[(.*?)\]\]>", re.S )
HOP_BUCKETS = ( "hop1", "hop2", "hop3plus" )


def attrs( s ):
    return dict( ATTR.findall( s ) )


def run( binary, tree, args, cache ):
    t0 = time.perf_counter()
    r = subprocess.run( [ binary, str( tree ) ] + args + [ f"--cache={cache}", "--legend=compact" ],
                        capture_output=True, text=True, errors="replace" )
    ms = ( time.perf_counter() - t0 ) * 1000.0
    return r.returncode, r.stdout, r.stderr, ms


def full_path_selector( path, fn ):
    """PATH:FN -> a --expand/--path selector qualified by the FULL relative path (not the basename
    selector_for() uses), because on a whole tree the basename is exactly the ambiguity source."""
    return f"{path}::" + "::".join( fn.split( "." ) ) if "." in fn else f"{path}:{fn}"


def expand_span( binary, tree, sel, cache ):
    """(path, start, end) of SEL's body, or None if the selector refuses or serves no body."""
    rc, out, err, ms = run( binary, tree, [ f"--expand={sel}" ], cache )
    if rc != 0:
        return None, err, ms
    m = BODY_H.search( out )
    if not m:
        return None, "no <b> body in --expand output", ms
    a = attrs( m.group( 1 ) )
    start = int( a[ "l" ] )
    end = start + len( m.group( 2 ).splitlines() ) - 1
    return ( a[ "p" ], start, end ), None, ms


def at_symbol( binary, tree, path, line, cache ):
    """the innermost enclosing symbol at path:line — (path, start, end, name), or None if refused."""
    rc, out, err, ms = run( binary, tree, [ f"--at={path}:{line}" ], cache )    # --at itself takes a
    # bare FILE:LINE; the @ prefix is only how ITS OWN seed composes into OTHER verbs (path/callers/…)
    if rc != 0:
        return None, ms
    rows = [ a for a in ( attrs( m.group( 1 ) ) for m in S_ROW.finditer( out ) ) if "n" in a and "l" in a ]
    if not rows:
        return None, ms
    innermost = rows[ -1 ]
    return ( path, int( innermost[ "l" ] ), int( innermost.get( "el", innermost[ "l" ] ) ), innermost[ "n" ] ), ms


def hop_call( binary, tree, seed_sel, path, line, cache ):
    rc, out, err, ms = run( binary, tree, [ f"--path={seed_sel},@{path}:{line}" ], cache )
    if rc != 0:
        return None, ms
    a = attrs( re.search( r"<path\b([^>]*)>", out ).group( 1 ) )
    return a, ms


def edge_count( binary, tree, path, line, flag, cache ):
    rc, out, err, ms = run( binary, tree, [ f"--{flag}=@{path}:{line}" ], cache )
    if rc != 0:
        return None
    m = re.search( rf"<{flag}\b([^>]*)>", out )
    return int( attrs( m.group( 1 ) )[ "count" ] ) if m else None


def hop_bucket( a ):
    if a[ "reachable" ] == "0":
        return "unreachable"
    h = int( a[ "hops" ] )
    return "hop1" if h == 1 else "hop2" if h == 2 else "hop3plus"


def measure_row( binary, tree, r, cache, tag ):
    """one carried multi-function row -> its result dict, or None with a census bucket bumped."""
    efs = r[ "edit_functions" ]
    path0, _, fn0 = efs[ 0 ].rpartition( ":" )
    seed_sel = full_path_selector( path0, fn0 )
    seed_span, err, _ = expand_span( binary, tree, seed_sel, cache )
    if seed_span is None:
        return None, "seed_selector_refused"
    seed_path, seed_start, seed_end = seed_span

    gold_by_file = {}
    for path, sec in file_sections( r[ "patch" ] ).items():
        if not path.endswith( ".py" ):
            continue
        lines = gold_pre_lines( sec )[ 0 ]
        if lines:
            gold_by_file[ path ] = lines
    total_gold = sum( len( v ) for v in gold_by_file.values() )
    if total_gold == 0:
        return None, "no_gold_line"

    hop0, outside = [], []
    for path, lines in gold_by_file.items():
        for ln in lines:
            if path == seed_path and seed_start <= ln <= seed_end:
                hop0.append( ( path, ln ) )
            else:
                outside.append( ( path, ln ) )

    # ---- resolve each outside line's true enclosing symbol, dedup by symbol identity -----------
    sym_of, no_enclosing, group = {}, [], {}
    for path, ln in outside:
        sym, _ = at_symbol( binary, tree, path, ln, cache )
        if sym is None:
            no_enclosing.append( ( path, ln ) )
            continue
        sym_of[ ( path, ln ) ] = sym
        group.setdefault( sym, [] ).append( ( path, ln ) )

    # ---- one --path call per DISTINCT enclosing symbol, not per gold line -----------------------
    sym_result, ambiguous_seen, unresolved_seen = {}, [], []
    for ( spath, sstart, send, sname ) in group:
        a, _ = hop_call( binary, tree, seed_sel, spath, sstart, cache )
        if a is None:
            sym_result[ ( spath, sstart, send, sname ) ] = ( "path_refused", None )
            continue
        ambiguous_seen.append( int( a.get( "graph_ambiguous", 0 ) ) )
        unresolved_seen.append( int( a.get( "graph_unresolved", 0 ) ) )
        bucket = hop_bucket( a )
        leaf = None
        if bucket == "unreachable":
            c_in = edge_count( binary, tree, spath, sstart, "callers", cache )
            c_out = edge_count( binary, tree, spath, sstart, "callees", cache )
            leaf = ( c_in == 0 and c_out == 0 )
        sym_result[ ( spath, sstart, send, sname ) ] = ( bucket, leaf )

    per_line = {}
    for sym, pairs in group.items():
        bucket, leaf = sym_result[ sym ]
        for pl in pairs:
            per_line[ pl ] = ( bucket, leaf, sym )

    counts = { "hop0": len( hop0 ), "no_enclosing_symbol": len( no_enclosing ),
               "unreachable": 0, "hop1": 0, "hop2": 0, "hop3plus": 0, "path_refused": 0 }
    leaf_unreachable, total_unreachable = 0, 0
    for pl, ( bucket, leaf, sym ) in per_line.items():
        counts[ bucket ] = counts.get( bucket, 0 ) + 1
        if bucket == "unreachable":
            total_unreachable += 1
            if leaf:
                leaf_unreachable += 1

    max_needed = 0
    for pl, ( bucket, leaf, sym ) in per_line.items():
        if bucket in ( "unreachable", "path_refused" ):
            max_needed = 10 ** 6
        else:
            max_needed = max( max_needed, { "hop1": 1, "hop2": 2, "hop3plus": 3 }[ bucket ] )
    if no_enclosing:
        max_needed = 10 ** 6

    row = { "instance_id": r[ "instance_id" ], "repo": r[ "repo" ], "n_edit_functions": len( efs ),
            "total_gold": total_gold, "counts": counts,
            "distinct_enclosing_symbols": len( group ),
            "leaf_unreachable": leaf_unreachable, "total_unreachable": total_unreachable,
            "graph_ambiguous_max": max( ambiguous_seen ) if ambiguous_seen else None,
            "graph_unresolved_max": max( unresolved_seen ) if unresolved_seen else None,
            "fully_covered_at": { str( n ): ( max_needed <= n ) for n in ( 1, 2, 3 ) } }
    print( f"[{tag}] {r['instance_id']} n_fn={len(efs)} gold={total_gold} "
           f"hop0={counts['hop0']} unreach={counts['unreachable']} "
           f"h1={counts['hop1']} h2={counts['hop2']} h3+={counts['hop3plus']} "
           f"no_sym={counts['no_enclosing_symbol']}", file=sys.stderr )
    return row, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--assets", required=True )
    ap.add_argument( "--dataset", default=None )
    ap.add_argument( "--bin", default="build/ripwire" )
    ap.add_argument( "--work", required=True )
    ap.add_argument( "--json", default=None )
    ap.add_argument( "--limit", type=int, default=0 )
    a = ap.parse_args()

    assets = Path( a.assets ).resolve()
    binary = str( Path( a.bin ).resolve() )
    work = Path( a.work ).resolve(); work.mkdir( parents=True, exist_ok=True )
    ds = Path( a.dataset ) if a.dataset else sorted( ( assets / "datasets" ).glob( "*.json" ) )[ 0 ]
    rows = json.loads( Path( ds ).read_text() )
    idx = index_checkouts( assets )

    multi = [ r for r in rows if len( r[ "edit_functions" ] ) > 1 ]
    ds_gold_multi = sum( len( gold_pre_lines( sec )[ 0 ] )
                         for r in multi for sec in file_sections( r[ "patch" ] ).values() )

    census = { "dataset_multi_function_rows": len( multi ), "dataset_multi_function_gold_lines": ds_gold_multi,
               "no_checkout": 0, "no_commit": 0, "seed_selector_refused": 0, "no_gold_line": 0,
               "archive_failed": 0, "carried": 0 }
    carried_gold = 0
    candidates = []
    for r in multi:
        slug = r[ "repo" ].replace( "/", "__" )
        if slug not in idx:
            census[ "no_checkout" ] += 1; continue
        repo = idx[ slug ]
        if git( repo, "cat-file", "-e", r[ "base_commit" ] + "^{commit}", ok_fail=True ).returncode != 0:
            census[ "no_commit" ] += 1; continue
        candidates.append( ( r, repo ) )
    if a.limit:
        candidates = candidates[ :a.limit ]

    results = []
    for i, ( r, repo ) in enumerate( candidates ):
        tree = work / f"x{i:04d}"
        cache = work / f"x{i:04d}.ripwirecache"
        tree.mkdir( parents=True, exist_ok=True )
        ok = archive_tree( repo, r[ "base_commit" ], tree )
        if not ok:
            census[ "archive_failed" ] += 1; continue
        row, why = measure_row( binary, tree, r, cache, f"{i+1}/{len(candidates)}" )
        if row is None:
            census[ why ] += 1
            continue
        census[ "carried" ] += 1
        carried_gold += row[ "total_gold" ]
        results.append( row )

    # ---- summary: counts against BOTH the carried subset and the full 6,809-gold-line ceiling ---
    agg = { k: sum( x[ "counts" ].get( k, 0 ) for x in results )
           for k in ( "hop0", "unreachable", "hop1", "hop2", "hop3plus", "no_enclosing_symbol", "path_refused" ) }
    outside_seed = sum( agg[ k ] for k in ( "unreachable", "hop1", "hop2", "hop3plus", "no_enclosing_symbol", "path_refused" ) )
    not_measured_of_ceiling = census[ "dataset_multi_function_gold_lines" ] - carried_gold
    total_unreach = sum( x[ "total_unreachable" ] for x in results )
    total_leaf = sum( x[ "leaf_unreachable" ] for x in results )

    def cov_share( n ):
        rows_n = [ x for x in results if x[ "fully_covered_at" ][ str( n ) ] ]
        return len( rows_n ) / len( results ) if results else None

    summary = {
        "binary": binary, "assets": str( assets ), "dataset": str( ds ),
        "census": census, "carried_rows": census[ "carried" ], "carried_gold_lines": carried_gold,
        "gold_line_distribution_of_carried": agg,
        "gold_line_distribution_share_of_6809_ceiling": {
            k: agg[ k ] / census[ "dataset_multi_function_gold_lines" ] for k in agg },
        "not_measured_share_of_6809_ceiling": not_measured_of_ceiling / census[ "dataset_multi_function_gold_lines" ],
        "outside_seed_gold_lines": outside_seed,
        "instance_fully_covered_share": { str( n ): cov_share( n ) for n in ( 1, 2, 3 ) },
        "unreachable_symbols_total": total_unreach, "unreachable_symbols_leaf_looking": total_leaf,
        "unreachable_leaf_share": ( total_leaf / total_unreach ) if total_unreach else None,
        "graph_ambiguous_max_over_rows": max( ( x[ "graph_ambiguous_max" ] for x in results if x[ "graph_ambiguous_max" ] is not None ), default=None ),
        "graph_unresolved_max_over_rows": max( ( x[ "graph_unresolved_max" ] for x in results if x[ "graph_unresolved_max" ] is not None ), default=None ),
    }
    print( json.dumps( summary, indent=2 ) )
    if a.json:
        Path( a.json ).write_text( json.dumps( { "summary": summary, "rows": results }, indent=2 ) )
        print( f"wrote {a.json}", file=sys.stderr )


if __name__ == "__main__":
    main()
