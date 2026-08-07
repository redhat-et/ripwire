#!/usr/bin/env python3
# r6 FEASIBILITY PROBE — run BEFORE pre-registering a structural-expansion round, to find out whether
# the mechanism could reach its targets at all. It measures nothing about ranking and decides nothing
# about shipping; it answers one question:
#
#   For the 7 held-out instances where ripwire found the primary gold file in the top 10 but a sibling
#   gold file never ranked at all — is that sibling STRUCTURALLY VISIBLE from the primary?
#
# "Visible" = the sibling's module name appears in the primary's source text (an import, a qualified
# call, an attribute path). That is the weakest form of the edge any expansion mechanism would need.
# If the edge is absent even under this permissive test, expansion cannot reach the target and r6
# should not be pre-registered at all — which is a cheaper finding than a rejected round.
import json, pathlib, subprocess, sys

ASSETS = pathlib.Path( __file__ ).resolve().parent
REPOS  = ASSETS / "repos_c"
rows   = json.load( open( ASSETS / "work/datasets/rows_czlll__Loc-Bench_V1_test_560.json" ) )
commit = { r["instance_id"]: r["base_commit"] for r in rows }
targets = json.load( open( ASSETS / "r6_targets.json" ) )

def modname( path ):
    """The token another file would use to name this one: its stem, minus package __init__ noise."""
    p = pathlib.Path( path )
    return p.parent.name if p.stem == "__init__" else p.stem

total_pairs = visible = 0
print( f"{'instance':46} {'sibling':34} visible-from-a-gold-peer" )
print( "-" * 104 )
for t in targets:
    repo = REPOS / t["repo"].replace( "/", "__" )
    if not repo.is_dir():
        print( f"{t['iid']:46} SKIP (no checkout)" ); continue
    subprocess.run( ["git", "checkout", "-q", "--force", commit[t["iid"]]], cwd=repo,
                    capture_output=True )
    texts = {}
    for g in t["gold"]:
        f = repo / g
        texts[g] = f.read_text( encoding="utf-8", errors="replace" ) if f.is_file() else ""
    for g in t["gold"]:
        mn = modname( g )
        if len( mn ) < 3:
            continue
        # is this file named inside ANY other gold file of the same instance?
        seen = any( mn in txt for other, txt in texts.items() if other != g )
        total_pairs += 1
        visible += bool( seen )
        print( f"{t['iid']:46} {g[-34:]:34} {'YES' if seen else 'no'}" )

if total_pairs:
    print( f"\n{visible}/{total_pairs} gold files are named inside a peer gold file "
           f"({100*visible/total_pairs:.0f}%)." )
    print( "A high number means an expansion step has an edge to walk; a low one means the siblings are"
           "\ninvisible to any structural mechanism and r6 should not be registered." )
