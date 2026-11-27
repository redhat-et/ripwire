#!/usr/bin/env python3
"""skillsize.py — bytes and estimated tokens of every shipped skill, split by when an agent pays for them.

    python3 bench/skillsize.py [SKILLS_DIR] [--json]

Three tiers, after Anthropic's progressive-disclosure model for Agent Skills:
  desc  — the frontmatter `description:` as a client reads it (bench/skilldesc_budget.py's normalization):
          loaded into EVERY session, whether or not the skill fires.
  body  — SKILL.md after its closing `---`: loaded when the skill triggers.
  refs  — every other *.md file in the skill directory: loaded only when the body sends the agent there.
tok = bytes / 4, rounded half up — an estimate, not a tokenizer count; it is stated as such wherever it is quoted.
Bytes are UTF-8 bytes. Only directories that hold a SKILL.md are counted (install.sh, CONSOLIDATION.md, agents/
and hermes/ are not skills an agent routes to).
"""
import json, pathlib, sys

sys.path.insert( 0, str( pathlib.Path( __file__ ).resolve().parent ) )
from skilldesc_budget import description_of  # noqa: E402

def tok( b ):
    return ( b + 2 ) // 4

def measure( root ):
    rows = []
    for d in sorted( root.iterdir() ):
        f = d / "SKILL.md"
        if not f.is_file():
            continue
        text = f.read_text( encoding = "utf-8" )
        parts = text.split( "---", 2 )
        body = parts[2] if len( parts ) >= 3 else text
        desc = len( description_of( f ).encode( "utf-8" ) )
        bodyB = len( body.lstrip( "\n" ).encode( "utf-8" ) )
        refs = sorted( p for p in d.rglob( "*.md" ) if p.name != "SKILL.md" )
        refsB = sum( p.stat().st_size for p in refs )
        rows.append( dict( skill = d.name, desc = desc, body = bodyB, refs = refsB, nrefs = len( refs ) ) )
    return rows

def main():
    args = [ a for a in sys.argv[1:] if not a.startswith( "--" ) ]
    root = pathlib.Path( args[0] if args else "skills" )
    rows = measure( root )
    if "--json" in sys.argv:
        print( json.dumps( rows, indent = 1 ) )
        return 0
    print( f"{'skill':28} {'desc_B':>7} {'body_B':>7} {'refs_B':>8} {'nrefs':>5}" )
    for r in rows:
        print( f"{r['skill']:28} {r['desc']:7} {r['body']:7} {r['refs']:8} {r['nrefs']:5}" )
    t = { k: sum( r[k] for r in rows ) for k in ( "desc", "body", "refs", "nrefs" ) }
    print( f"{'TOTAL (' + str( len( rows ) ) + ' skills)':28} {t['desc']:7} {t['body']:7} {t['refs']:8} {t['nrefs']:5}" )
    print( f"est. tokens (bytes/4): desc {tok( t['desc'] )}  body {tok( t['body'] )}  refs {tok( t['refs'] )}"
           f"  all {tok( t['desc'] + t['body'] + t['refs'] )}" )
    return 0

if __name__ == "__main__":
    sys.exit( main() )
