#!/usr/bin/env python3
"""Derive expected/<task>/<file>.expected from fixture/ and tasks.json with PLAIN STRING OPS — never ripwire.

The `.expected` suffix says what these are: byte-images of post-edit files, not translation units. Without it
test/ripwirepubliccheck.sh's include-closure arm swept them as C++ (a `#include "geometry.h"` that resolves in
fixture/ does not resolve beside a header-less copy). oracle.sh strips the suffix when it compares.

The oracle must be independent of the tool under test, so the expected post-edit bytes are produced by
str.replace over the committed fixture: a replace op swaps old_text for new_text once; an insert op puts
new_text before/after its anchor with the file's own definition separator (two blank lines in Python, one
in C++). Run `python3 gen_expected.py --check` to verify the committed expected/ tree still equals what this
script derives (test/agentloopeditsuitecheck.sh does)."""
import json, pathlib, sys

HERE = pathlib.Path( __file__ ).resolve().parent
FIXTURE, EXPECTED, TASKS = HERE / "fixture", HERE / "expected", HERE / "tasks.json"

def separator( rel ):
    """The blank-line convention between top-level definitions in that file (PEP 8 vs the C++ fixture)."""
    return "\n\n\n" if rel.endswith( ".py" ) else "\n\n"

def apply_op( text, op, rel ):
    kind = op.get( "op", op.get( "kind" ) )
    if kind == "replace":
        assert text.count( op["old_text"] ) == 1, "old_text must occur exactly once in %s (%s)" % ( rel, op["symbol"] )
        return text.replace( op["old_text"], op["new_text"], 1 )
    anchor = op["anchor_text"]
    assert text.count( anchor ) == 1, "anchor_text must occur exactly once in %s (%s)" % ( rel, op["symbol"] )
    if kind == "insert_before":
        return text.replace( anchor, op["new_text"] + separator( rel ) + anchor, 1 )
    if kind == "insert_after":
        return text.replace( anchor, anchor + separator( rel ) + op["new_text"], 1 )
    raise SystemExit( "unknown op kind %r" % kind )

def task_ops( task ):
    return task["ops"] if task["kind"] == "plan" else [ dict( task, op=task["kind"] ) ]

def expected_files( task ):
    """{relpath: bytes} for every file the task touches, derived from the pristine fixture."""
    out = {}
    for op in task_ops( task ):
        rel  = op["file"]
        text = out.get( rel ) or ( FIXTURE / rel ).read_text()
        out[rel] = apply_op( text, op, rel )
    return out

def main():
    tasks = json.loads( TASKS.read_text() )["tasks"]
    check = "--check" in sys.argv
    bad = 0
    for task in tasks:
        for rel, text in expected_files( task ).items():
            dest = EXPECTED / task["id"] / ( rel + ".expected" )
            if check:
                have = dest.read_text() if dest.exists() else None
                if have != text:
                    print( "MISMATCH %s" % dest ); bad += 1
            else:
                dest.parent.mkdir( parents=True, exist_ok=True )
                dest.write_text( text )
    if check:
        print( "expected/ %s tasks.json+fixture/" % ( "DIFFERS FROM" if bad else "matches" ) )
        sys.exit( 1 if bad else 0 )

if __name__ == "__main__":
    main()
