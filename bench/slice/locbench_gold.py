#!/usr/bin/env python3
"""locbench_gold.py — build line-level gold for the --slice line-recall round from a LocBench-shaped
dataset plus local repository checkouts. Downloads nothing; reads only what is already on disk.

Protocol: docs/research/slice-line-recall.md §2 (corpus and slice rule) and §1.1 G2 (the gold rule
for a pure-insertion hunk). This script does NOT invoke ripwire — every ripwire-dependent
qualification stage lives in run_slice_linerecall.py, so the gold is a function of the dataset and
the checkouts alone and cannot move when the binary does.

Gold is PRE-IMAGE: the round scores the localization setting (the agent holds the pre-fix tree and
must find the lines to change), so gold line numbers are numbered in the file at base_commit.
  - every '-' line of a hunk touching the target file contributes its pre-image line number;
  - a run of '+' lines with no '-' line of its own contributes ONE anchor: the pre-image line
    immediately preceding the insertion point, or the hunk's first pre-image line when the run
    opens the hunk.

Usage:
  python3 bench/slice/locbench_gold.py --assets DIR [--dataset FILE] [--json out.json]

--assets DIR must contain `datasets/` (the dataset json) and one or more sibling directories of
repository checkouts named `owner__repo`. Every directory directly under DIR is scanned for those.
"""

import argparse, json, os, re, sys
from pathlib import Path

from _common import git                                # one definition, shared across bench/slice

HUNK = re.compile( r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@" )


def index_checkouts( assets ):
    """every `owner__repo` directory one level under any direct subdirectory of assets."""
    idx = {}
    for top in sorted( os.listdir( assets ) ):
        p = Path( assets ) / top
        if not p.is_dir():
            continue
        for name in sorted( os.listdir( p ) ):
            q = p / name
            if "__" in name and q.is_dir():
                idx.setdefault( name, str( q ) )
    return idx


def file_sections( patch ):
    """split a unified diff into {post_path: [lines]} sections, keyed by the b/ path."""
    out, cur, path = {}, None, None
    for line in patch.splitlines():
        if line.startswith( "diff --git " ):
            cur, path = [], None
        elif line.startswith( "+++ b/" ) and cur is not None:
            path = line[ 6: ]
            out[ path ] = cur
        elif line.startswith( "+++ " ) and cur is not None:
            path = None
        elif cur is not None:
            cur.append( line )
    return out


def gold_pre_lines( section ):
    """pre-image gold line numbers for one file section — docs/research/slice-line-recall.md §1.1 G2."""
    deleted, anchors = set(), set()
    pre_ln, hunk_start, consumed, plus_run_open = None, None, False, False
    for line in section:
        m = HUNK.match( line )
        if m:
            hunk_start = int( m.group( 1 ) )
            pre_ln, consumed, plus_run_open = hunk_start, False, False
            continue
        if pre_ln is None:
            continue
        if line.startswith( "-" ) and not line.startswith( "---" ):
            deleted.add( pre_ln ); pre_ln += 1; consumed = True; plus_run_open = False
        elif line.startswith( "+" ) and not line.startswith( "+++" ):
            if not plus_run_open:
                # ONE anchor per '+' run: the pre-image line just before the insertion point,
                # or the hunk's first pre-image line when the run opens the hunk.
                anchors.add( pre_ln - 1 if consumed else hunk_start )
                plus_run_open = True
        elif line.startswith( "\\" ):
            continue
        else:                                              # context (leading space, or empty line)
            pre_ln += 1; consumed = True; plus_run_open = False
    # a line both deleted and used as an anchor is one gold line, not two
    return sorted( deleted | ( anchors - deleted ) ), sorted( deleted ), sorted( anchors - deleted )


def selector_for( path, fn ):
    """LocBench `PATH:FN` -> a --slice selector. `Class.method` uses ripwire's scoped `::` spelling."""
    base = Path( path ).name
    return f"{base}::" + "::".join( fn.split( "." ) ) if "." in fn else f"{base}:{fn}"


def carry_row( r, idx, census ):
    """the carried instance for one dataset row, or None — every None bumps a census counter.

    Qualification stages 1, 2, 4, 6 of docs/research/slice-line-recall.md §2; stages 3 (single
    function) and 5/7 (selector, inventory) are handled by the caller and by the runner, so that
    nothing here needs the binary."""
    efs = r[ "edit_functions" ]
    slug = r[ "repo" ].replace( "/", "__" )
    if slug not in idx:
        census[ "no_checkout" ] += 1; return None
    repo = idx[ slug ]
    if git( repo, "cat-file", "-e", r[ "base_commit" ] + "^{commit}", ok_fail=True ).returncode != 0:
        census[ "no_commit" ] += 1; return None
    path, _, fn_name = efs[ 0 ].rpartition( ":" )
    if not path.endswith( ".py" ):
        census[ "not_python" ] += 1; return None
    if git( repo, "show", f"{r['base_commit']}:{path}", ok_fail=True ).returncode != 0:
        census[ "file_missing_at_base" ] += 1; return None
    secs = file_sections( r[ "patch" ] )
    if path not in secs:
        census[ "no_patch_section" ] += 1; return None
    gold, deleted, anchors = gold_pre_lines( secs[ path ] )
    if not gold:
        census[ "no_gold_line" ] += 1; return None
    return {
        "instance_id": r[ "instance_id" ], "repo": r[ "repo" ], "repo_dir": repo,
        "base_commit": r[ "base_commit" ], "path": path, "fn": fn_name,
        "selector": selector_for( path, fn_name ), "scoped": "." in fn_name,
        "gold": gold, "gold_deleted": deleted, "gold_anchor": anchors,
        "patch_files": len( secs ), "category": r.get( "category" ),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--assets", required=True, help="directory holding datasets/ and the repo checkouts" )
    ap.add_argument( "--dataset", default=None, help="dataset json (default: the single file under <assets>/datasets)" )
    ap.add_argument( "--json", default=None )
    a = ap.parse_args()

    assets = Path( a.assets ).resolve()
    ds = Path( a.dataset ) if a.dataset else sorted( ( assets / "datasets" ).glob( "*.json" ) )[ 0 ]
    rows = json.loads( Path( ds ).read_text() )
    idx = index_checkouts( assets )

    census = { k: 0 for k in (
        "total", "multi_function", "zero_function", "no_checkout", "no_commit",
        "not_python", "file_missing_at_base", "no_patch_section", "no_gold_line", "carried" ) }
    census[ "total" ] = len( rows )
    carried, gold_lines_total, gold_lines_multi = [], 0, 0
    # dataset-level reachability, computed for ALL 560 rows independently of which repositories
    # happen to be checked out locally: how much of the corpus's gold an INTRA-PROCEDURAL primitive
    # can address at all. A multi-function row is out of reach by construction, not a miss.
    ds_gold_single = ds_gold_multi = ds_rows_single = ds_rows_multi = 0
    for r in rows:
        g = sum( len( gold_pre_lines( sec )[ 0 ] ) for sec in file_sections( r[ "patch" ] ).values() )
        if len( r[ "edit_functions" ] ) == 1:
            ds_rows_single += 1; ds_gold_single += g
        else:
            ds_rows_multi += 1; ds_gold_multi += g

    for r in rows:
        efs = r[ "edit_functions" ]
        if len( efs ) != 1:
            census[ "multi_function" if len( efs ) > 1 else "zero_function" ] += 1
            if len( efs ) > 1:
                for sec in file_sections( r[ "patch" ] ).values():
                    gold_lines_multi += len( gold_pre_lines( sec )[ 0 ] )
            continue
        got = carry_row( r, idx, census )
        if got is None:
            continue
        census[ "carried" ] += 1
        gold_lines_total += len( got[ "gold" ] )
        carried.append( got )

    out = { "dataset": str( ds ), "checkout_dirs": len( idx ), "census": census,
            "gold_lines_carried": gold_lines_total, "gold_lines_multi_function": gold_lines_multi,
            "dataset_reachability": { "rows_single_function": ds_rows_single, "rows_multi_function": ds_rows_multi,
                                      "gold_lines_single_function": ds_gold_single,
                                      "gold_lines_multi_function": ds_gold_multi },
            "instances": carried }
    print( json.dumps( { k: v for k, v in out.items() if k != "instances" }, indent=2 ) )
    if a.json:
        Path( a.json ).write_text( json.dumps( out, indent=2 ) )
        print( f"wrote {a.json} ({len(carried)} carried rows)", file=sys.stderr )


if __name__ == "__main__":
    main()
