#!/usr/bin/env python3
"""prepare.py — build a BLIND rating packet for one arm of the description-budget round.

    python3 bench/skillrater/prepare.py ARM_SKILLS_DIR CORPUS_TSV OUT_DIR --arm=NAME [--seed=S]

Writes OUT_DIR/packet_NAME.md — the alphabetical skill list (name + description exactly as that arm
renders it, nothing else from the SKILL.md) followed by every corpus prompt in a seeded shuffle under
an opaque id — and OUT_DIR/key_NAME.tsv (id, permitted set, provenance) for score.py. The packet
never carries a label, a provenance, a split, or the corpus line; the rater never sees the key. The
same seed gives every arm the same id→prompt mapping, so paired scoring is exact.
"""
import hashlib, pathlib, random, sys

sys.path.insert( 0, str( pathlib.Path( __file__ ).resolve().parent.parent ) )
from skilldesc_budget import description_of  # noqa: E402

def main():
    opts = { a.split( "=", 1 )[0]: a.split( "=", 1 )[1] for a in sys.argv[1:] if a.startswith( "--" ) and "=" in a }
    pos = [ a for a in sys.argv[1:] if not a.startswith( "--" ) ]
    skills, corpus, out = pathlib.Path( pos[0] ), pathlib.Path( pos[1] ), pathlib.Path( pos[2] )
    arm = opts[ "--arm" ]
    seed = int( opts.get( "--seed", "20260907" ) )
    out.mkdir( parents = True, exist_ok = True )
    rows = []
    for line in corpus.read_text( encoding = "utf-8" ).splitlines():
        if line.startswith( "#" ) or not line.strip():
            continue
        cols = line.split( "\t" )
        rows.append( ( cols[0], cols[1], cols[2] ) )
    rng = random.Random( seed )
    order = list( range( len( rows ) ) )
    rng.shuffle( order )
    ids = [ "P%03d" % ( i + 1 ) for i in range( len( rows ) ) ]
    names = [ d.name for d in sorted( skills.iterdir() ) if ( d / "SKILL.md" ).is_file() and d.name != "ripwire-router" ]
    lines = [ "# Skill routing packet", "",
              "You are the skill router inside a coding agent. The agent has these skills installed; each",
              "line is exactly what the agent sees: the skill's name and its description. Nothing else.", "" ]
    for n in names:
        lines.append( f"- **{n}**: {description_of( skills / n / 'SKILL.md' )}" )
    lines += [ "", "For EACH prompt below, decide which ONE skill the agent should load first (`top1`), and the",
               "runner-up (`top2`). If no skill fits the prompt at all, answer `none` for top1 (top2 may still",
               "name the nearest skill). Judge from the descriptions above only.", "", "## Prompts", "" ]
    key = [ "id\tpermitted\tprovenance" ]
    for pid, idx in zip( ids, order ):
        prompt, label, prov = rows[idx]
        lines.append( f"{pid}: {prompt}" )
        key.append( f"{pid}\t{label}\t{prov}" )
    ( out / f"packet_{arm}.md" ).write_text( "\n".join( lines ) + "\n", encoding = "utf-8" )
    ( out / f"key_{arm}.tsv" ).write_text( "\n".join( key ) + "\n", encoding = "utf-8" )
    digest = hashlib.sha256( ( out / f"packet_{arm}.md" ).read_bytes() ).hexdigest()
    print( f"packet_{arm}.md prompts={len( rows )} skills={len( names )} sha256={digest[:16]}" )

if __name__ == "__main__":
    sys.exit( main() )
