#!/usr/bin/env python3
"""skilldesc_arms.py — build the measurement copies of skills/ for the description-budget round
(docs/EVALS.md "Skill descriptions under a client budget", 2026-09-07).

    python3 bench/skilldesc_arms.py SRC DST --mode=full|head|window [--n=350] [--seed=S] [--fold=OLD:NEW]
    python3 bench/skilldesc_arms.py --heldout CORPUS OUT [--label-map=OLD:NEW]

Arm copies: `head` keeps the first N normalized characters of each description (what a round-robin
client budget leaves), `window` keeps a seeded random contiguous N-character window (the matched-cost
placebo), `full` rewrites nothing but normalizes the block scalar. `--fold=OLD:NEW` removes skill OLD
from the copy and appends its body to NEW's body (a measurement-only merge; the real merge, if it ever
lands, is a content edit). `--heldout` writes the frozen held-out corpus: split=test rows whose
provenance is judged or neg, header comments preserved; `--label-map` rewrites labels mechanically
(every permitted-set member OLD becomes NEW; duplicates collapse) so a folded arm scores on the same
rows. Bodies and other frontmatter keys are copied verbatim; nothing here reads a prompt's text.
"""
import pathlib, random, re, shutil, sys

sys.path.insert( 0, str( pathlib.Path( __file__ ).resolve().parent ) )
from skilldesc_budget import description_of  # noqa: E402

def split_skill( text ):
    parts = text.split( "---", 2 )
    return parts[1], parts[2]

def rewrite_front( front, new_desc ):
    m = re.search( r'^description:[ \t]*(.*?)(?=\n[A-Za-z_-]+:|\Z)', front, re.S | re.M )
    return front[:m.start()] + "description: >\n  " + new_desc + "\n" + front[m.end():].lstrip( "\n" )

def build_arm( src, dst, mode, n, seed, fold ):
    if dst.exists():
        shutil.rmtree( dst )
    rng = random.Random( seed )
    old_name = new_name = None
    if fold:
        old_name, new_name = fold.split( ":", 1 )
    folded_body = ""
    if old_name:
        folded_body = split_skill( ( src / old_name / "SKILL.md" ).read_text( encoding = "utf-8" ) )[1]
    for d in sorted( src.iterdir() ):
        f = d / "SKILL.md"
        if not f.is_file() or d.name == old_name:
            continue
        front, body = split_skill( f.read_text( encoding = "utf-8" ) )
        desc = description_of( f )
        if mode == "head":
            new = desc[:n]
        elif mode == "window":
            start = rng.randint( 0, max( 0, len( desc ) - n ) )
            new = desc[start:start + n]
        else:
            new = desc
        if d.name == new_name:
            body = body.rstrip( "\n" ) + "\n\n" + folded_body
        ( dst / d.name ).mkdir( parents = True )
        for p in d.iterdir():
            if p.name != "SKILL.md":
                ( shutil.copytree if p.is_dir() else shutil.copy2 )( p, dst / d.name / p.name )
        ( dst / d.name / "SKILL.md" ).write_text( "---" + rewrite_front( front, new ) + "---" + body, encoding = "utf-8" )
    if old_name:
        for p in ( src / old_name ).iterdir():
            if p.name != "SKILL.md" and not ( dst / new_name / p.name ).exists():
                ( shutil.copytree if p.is_dir() else shutil.copy2 )( p, dst / new_name / p.name )

def write_heldout( corpus, out, label_map ):
    old_name = new_name = None
    if label_map:
        old_name, new_name = label_map.split( ":", 1 )
    lines = []
    for line in corpus.read_text( encoding = "utf-8" ).splitlines():
        if line.startswith( "#" ) or line == "":
            lines.append( line ); continue
        cols = line.split( "\t" )
        if len( cols ) < 4 or cols[3] != "test" or cols[2] not in ( "judged", "neg" ):
            continue
        if old_name and cols[1] != "none":
            members = []
            for s in cols[1].split( "," ):
                s = new_name if s == old_name else s
                if s not in members:
                    members.append( s )
            cols[1] = ",".join( members )
        lines.append( "\t".join( cols ) )
    out.write_text( "\n".join( lines ) + "\n", encoding = "utf-8" )

def main():
    opts = { a.split( "=", 1 )[0]: ( a.split( "=", 1 )[1] if "=" in a else "" ) for a in sys.argv[1:] if a.startswith( "--" ) }
    pos = [ a for a in sys.argv[1:] if not a.startswith( "--" ) ]
    if "--heldout" in opts:
        write_heldout( pathlib.Path( pos[0] ), pathlib.Path( pos[1] ), opts.get( "--label-map" ) )
        return 0
    build_arm( pathlib.Path( pos[0] ), pathlib.Path( pos[1] ), opts.get( "--mode", "full" ),
               int( opts.get( "--n", "350" ) ), int( opts.get( "--seed", "20260907" ) ), opts.get( "--fold" ) )
    return 0

if __name__ == "__main__":
    sys.exit( main() )
