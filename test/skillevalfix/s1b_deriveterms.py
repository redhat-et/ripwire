#!/usr/bin/env python3
# s1b_deriveterms.py — the S1b round's candidate-term derivation (docs/EVALS.md §4, registered 2026-08-19).
#
# Reads the 18 skills/*/SKILL.md files and NOTHING else. The eval corpus, its labels and the per-row
# miss lists are never opened here — deriving description vocabulary from the scoring set would be
# fitting, not measuring. The only thing this round takes from the instrument is the SET OF SKILL
# NAMES in the baseline desc-vs-body disagreement list, passed on the command line.
#
# Difference from s1_deriveterms.py (the round this one deliberately near-replicates): df ceiling
# tightened to <= 1 across the other candidate descriptions, and df is measured over DESCRIPTIONS
# (the bm25-desc arm's own document corpus) rather than over bodies — a term's discrimination in
# that arm is decided by how many sibling DESCRIPTIONS already spend it.
#
#   python3 test/skillevalfix/s1b_deriveterms.py . [skill-name ...] > s1b_terms_2026-08-19.txt
#
# The tokenizer below is a line-for-line transcription of subtokens() in src/lexical.h: split on any
# non-alphanumeric byte, flush at a camel boundary tested against the ALREADY-LOWERCASED accumulator,
# lowercase, drop anything shorter than 2 characters. That last pair is why an ALL-CAPS acronym
# ("MCP", "API", "CI") tokenizes to nothing at all — the defect this round exists to test.

import os
import sys
from collections import Counter


def subtokens( text ):
    out, cur = [], []

    def flush():
        if len( cur ) >= 2:
            out.append( ''.join( cur ) )
        cur.clear()

    for ch in text:
        upper = 'A' <= ch <= 'Z'
        if not ( upper or 'a' <= ch <= 'z' or '0' <= ch <= '9' ):
            flush()
            continue
        if upper and cur and not ( 'A' <= cur[ -1 ] <= 'Z' ):
            flush()                                  # camel boundary, tested post-lowercasing
        cur.append( ch.lower() if upper else ch )
    flush()
    return out


def parse_skill_md( path ):
    """{description, body} exactly as skilleval.h::parseSkillMd splits them."""
    lines = open( path, encoding = 'utf-8', errors = 'replace' ).read().split( '\n' )
    desc, i, in_desc = [], 0, False
    if lines and lines[ 0 ].strip() == '---':
        i = 1
        while i < len( lines ):
            line = lines[ i ]
            if line.strip() == '---':
                i += 1
                break
            if line.startswith( 'description:' ):
                in_desc = True
                rest = line[ len( 'description:' ): ].strip()
                if rest and rest not in ( '>', '|', '>-', '|-' ):
                    desc.append( rest )
            elif in_desc:
                if line[ :1 ] in ( ' ', '\t' ):
                    desc.append( line.strip() )
                else:
                    in_desc = False
            i += 1
    return ' '.join( desc ), '\n'.join( lines[ i: ] )


def main():
    root      = sys.argv[ 1 ] if len( sys.argv ) > 1 else '.'
    wanted    = set( sys.argv[ 2: ] )
    skills_dir = os.path.join( root, 'skills' )
    # ripwire-router is never a routing candidate (skilleval.h keeps it out-of-band), so it is neither
    # a target nor part of the df denominator.
    names = sorted( d for d in os.listdir( skills_dir )
                    if d.startswith( 'ripwire-' ) and d != 'ripwire-router'
                    and os.path.isdir( os.path.join( skills_dir, d ) ) )
    desc, body = {}, {}
    for n in names:
        d, b    = parse_skill_md( os.path.join( skills_dir, n, 'SKILL.md' ) )
        desc[ n ] = Counter( subtokens( d ) )
        body[ n ] = Counter( subtokens( b ) )
    df = Counter()
    for n in names:
        for t in desc[ n ]:
            df[ t ] += 1

    mean_desc_len = sum( sum( desc[ n ].values() ) for n in names ) / len( names )
    print( '# S1b candidate terms — tf >= 3 in own body, absent from own description, df <= 1 over the' )
    print( '# other %d candidate descriptions. %d candidate skills; mean description length %.0f tokens.'
           % ( len( names ) - 1, len( names ), mean_desc_len ) )
    print( '# Targets (baseline desc-vs-body disagreement list, minus descriptions > 1.4x mean): %s'
           % ( ' '.join( sorted( wanted ) ) if wanted else '(all)' ) )
    for n in names:
        if wanted and n not in wanted:
            continue
        cands = sorted( ( ( tf, df[ t ], t ) for t, tf in body[ n ].items()
                          if tf >= 3 and t not in desc[ n ] and df[ t ] <= 1 ),
                        key = lambda x: ( -x[ 0 ], x[ 1 ], x[ 2 ] ) )
        print( '\n== %s  (description %d tokens, body %d tokens, %d candidates)'
               % ( n, sum( desc[ n ].values() ), sum( body[ n ].values() ), len( cands ) ) )
        for tf, d, t in cands:
            print( '   %-16s tf=%-3d df=%d' % ( t, tf, d ) )


if __name__ == '__main__':
    main()
