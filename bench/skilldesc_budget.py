#!/usr/bin/env python3
"""skilldesc_budget.py — measure every skill's frontmatter `description:` against a client character budget.

    python3 bench/skilldesc_budget.py [SKILLS_DIR] [--limit N]

Prints one row per skill (normalized length, overrun) and the totals a budgeted client sees: how many
characters survive a per-skill head cut at N and how many are lost. The length is the YAML *content* —
whitespace-normalized, the block-scalar introducer (`>` / `|`) excluded — which is what a client reads;
a regex that keeps the `>` marker over-counts every skill by two characters (issue #49's 18,455 vs the
naive 18,491). Exit 1 when any description exceeds --limit, so it doubles as a gate body.
"""
import pathlib, re, sys

def description_of( skill_md: pathlib.Path ) -> str:
    text = skill_md.read_text( encoding = "utf-8" )
    parts = text.split( "---", 2 )
    front = parts[1] if len( parts ) >= 3 else ""
    m = re.search( r'^description:[ \t]*(.*?)(?=\n[A-Za-z_-]+:|\Z)', front, re.S | re.M )
    if not m:
        return ""
    value = m.group( 1 )
    first, _, rest = value.partition( "\n" )
    if first.strip() in ( ">", ">-", "|", "|-" ):
        value = rest
    return " ".join( value.split() )

def main() -> int:
    args = [ a for a in sys.argv[1:] if not a.startswith( "--" ) ]
    limit = 350
    for a in sys.argv[1:]:
        if a.startswith( "--limit=" ):
            limit = int( a.split( "=", 1 )[1] )
    root = pathlib.Path( args[0] if args else "skills" )
    rows = []
    for d in sorted( root.iterdir() ):
        f = d / "SKILL.md"
        if f.is_file():
            rows.append( ( d.name, len( description_of( f ) ) ) )
    if not rows:
        print( f"skilldesc_budget: no SKILL.md under {root}", file = sys.stderr )
        return 2
    total = sum( n for _, n in rows )
    kept = sum( min( n, limit ) for _, n in rows )
    over = 0
    for name, n in sorted( rows, key = lambda r: -r[1] ):
        mark = f"-{n - limit}" if n > limit else "ok"
        over += n > limit
        print( f"{n:>6}  {mark:>7}  {name}" )
    lost = total - kept
    pct = ( 100.0 * lost / total ) if total else 0.0
    print( f"skills={len( rows )} total={total} kept@{limit}={kept} lost={lost} ({pct:.0f}%) over_budget={over}" )
    return 1 if over else 0

if __name__ == "__main__":
    sys.exit( main() )
