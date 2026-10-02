#!/usr/bin/env python3
"""probe_wholerepo_selector.py — price the one deviation the main run makes.

run_slice_linerecall.py hands ripwire a ONE-FILE tree (sound, because --slice is intra-procedural by
declaration), which also removes whole-repository selector ambiguity. The selector-resolution rate it
reports is therefore an UPPER BOUND on what an agent sees on a real checkout. This probe measures the
gap on a sample: the same selector, same commit, against the WHOLE tree, materialized read-only with
`git archive` (the checkouts are never written to).

Usage:
  python3 bench/slice/probe_wholerepo_selector.py --gold gold.json --bin build/ripwire \
      --work DIR [--sample 12] [--max-mb 400]
"""

import argparse, json, shutil, subprocess, sys, time
from pathlib import Path

from _common import git, archive_tree                  # one definition, shared across bench/slice


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--gold", required=True )
    ap.add_argument( "--bin", default="build/ripwire" )
    ap.add_argument( "--work", required=True )
    ap.add_argument( "--sample", type=int, default=12 )
    ap.add_argument( "--json", default=None )
    a = ap.parse_args()

    binary = str( Path( a.bin ).resolve() )
    work = Path( a.work ).resolve(); work.mkdir( parents=True, exist_ok=True )
    rows = json.loads( Path( a.gold ).read_text() )[ "instances" ]
    # a deterministic, spread-out sample: every k-th carried row
    step = max( 1, len( rows ) // a.sample )
    sample = rows[ ::step ][ :a.sample ]

    out, resolved, ambiguous, other = [], 0, 0, 0
    for r in sample:
        tree = work / r[ "instance_id" ]
        shutil.rmtree( tree, ignore_errors=True )
        if not archive_tree( r[ "repo_dir" ], r[ "base_commit" ], tree ):
            continue
        t0 = time.perf_counter()
        p = subprocess.run( [ binary, str( tree ), f"--slice={r['selector']}" ],
                            capture_output=True, text=True, errors="replace" )
        ms = ( time.perf_counter() - t0 ) * 1000.0
        files = sum( 1 for _ in tree.rglob( "*.py" ) )
        verdict = "resolved" if p.returncode == 0 else ( "ambiguous" if "matches" in p.stderr else "other_refusal" )
        if verdict == "resolved": resolved += 1
        elif verdict == "ambiguous": ambiguous += 1
        else: other += 1
        out.append( { "instance_id": r[ "instance_id" ], "selector": r[ "selector" ], "scoped": r[ "scoped" ],
                      "py_files": files, "verdict": verdict, "ms": ms,
                      "stderr": p.stderr.strip()[ :200 ] } )
        print( f"{r['instance_id']:<48} py={files:<6} {verdict:<14} {ms:8.0f} ms", file=sys.stderr )
        shutil.rmtree( tree, ignore_errors=True )

    summary = { "sampled": len( out ), "resolved": resolved, "ambiguous": ambiguous,
                "other_refusal": other,
                "ms_mean": ( sum( x[ "ms" ] for x in out ) / len( out ) ) if out else None }
    print( json.dumps( summary, indent=2 ) )
    if a.json:
        Path( a.json ).write_text( json.dumps( { "summary": summary, "rows": out }, indent=2 ) )


if __name__ == "__main__":
    main()
