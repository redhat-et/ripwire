#!/usr/bin/env python3
"""inspect_slice_misses.py — read run_slice_linerecall.py's results json and say, per missed line,
whether the miss is the RELEVANCE ORACLE's noise or a real drop by the slicer.

The registered oracle is a word regex over the changed line's text, so it counts a variable's name
inside a docstring, a comment, a string literal or an f-string prefix as an occurrence. The strict
oracle (AMENDMENT 2026-09-20 (b)) is Python's own tokenizer: an occurrence counts only when it is a
NAME token. This script prints the census both ways and lists every miss that survives the strict
oracle in full, because that residue is the only part that is evidence about the slicer.

Usage: python3 bench/slice/inspect_slice_misses.py --results results.json --gold gold.json
"""

import argparse, json
from pathlib import Path

from _common import git, name_lines                    # one definition, shared across bench/slice


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--results", required=True )
    ap.add_argument( "--gold", required=True )
    a = ap.parse_args()

    res = json.loads( Path( a.results ).read_text() )
    gold = { g[ "instance_id" ]: g for g in json.loads( Path( a.gold ).read_text() )[ "instances" ] }
    src_cache = {}

    def source_of( iid ):
        if iid not in src_cache:
            g = gold[ iid ]
            r = git( g[ "repo_dir" ], "show", f"{g['base_commit']}:{g['path']}", ok_fail=True )
            src_cache[ iid ] = r.stdout if r.returncode == 0 else ""
        return src_cache[ iid ]

    total_miss, noise, real, untokenizable = 0, 0, [], 0
    for x in res[ "var_instances" ]:
        if not x[ "v1_missed" ]:
            continue
        names = name_lines( source_of( x[ "instance_id" ] ) )
        for m in x[ "v1_missed" ]:
            total_miss += 1
            if names is None:
                untokenizable += 1
            elif m[ "line" ] in names.get( x[ "var" ], set() ):
                real.append( ( x[ "instance_id" ], x[ "var" ], m ) )
            else:
                noise += 1

    print( f"missed lines under the registered (word-regex) oracle : {total_miss}" )
    print( f"  the name is not a NAME token on that line (oracle noise): {noise}" )
    print( f"  file not tokenizable, unclassified                      : {untokenizable}" )
    print( f"  survives the strict oracle — evidence about the slicer  : {len(real)}" )
    for iid, var, m in real:
        print( f"    {iid} var={var} L{m['line']}: {m['text']}" )


if __name__ == "__main__":
    main()
