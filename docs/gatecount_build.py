#!/usr/bin/env python3
# gatecount_build.py — the published gate count is a BUILD PRODUCT of the absorb loop in
# test/regression.sh. This script derives it and REWRITES every published site in place.
#
# WHY GENERATED. The number lived, hand-written, at eight sites across three files. Two lanes that each
# add one gate both write N+1; git auto-merges the IDENTICAL text CLEAN, and the tree then publishes N+1
# against a loop of N+2. Every check in the tree stays green through that: "my count equals my own loop"
# holds on each branch, "my loop equals main's loop" holds after the merge, and the member SETS differ at
# the same number. It collided seven times in one night on 2026-09-10 and forced every gate-adding lane
# to land strictly one at a time. So the number stops being written by hand, exactly the way
# docs/COMMANDS.md (docs_commands_build.py) and docs/LIMITS.md (limits_build.py) already did.
#
# THE MERGE RECIPE THIS BUYS. Union the `for _g in …` sets, run this script, done — the count is a
# function of the union, so two lanes can no longer agree on a stale number.
#
# THE MARKER. A published count sits on a line carrying a marker comment:
#     markdown/HTML   <!-- gatecount -->     (renders invisibly on GitHub)
#     JavaScript      // gatecount
# A marked line is a site this script OWNS and rewrites. A count claim on an UNMARKED line is a
# hand-written number, and this script REFUSES the tree rather than quietly leaving it behind — that
# refusal is the whole point, because "the sites I know about all agree" is exactly the assurance the
# eight-site sprawl kept providing while a ninth drifted. Symmetrically, a marked line that carries no
# recognizable count is a marker that has lost its claim, and is refused too (a claim deleted is a claim
# drifted). Do not spell the literal marker inside a site file except at a real site; document it in
# CONTRIBUTING.md, which is not a site.
#
# Usage: python3 docs/gatecount_build.py [--check] [--root DIR]
#   --check rewrites nothing and exits 1 if any site has drifted (this is what the gate runs).
#   --root retargets the whole tree. It exists so test/gatecountcheck.sh can prove this generator CAN go
#          red on a real loop change without editing the tree it is gating — a probe copy dropped into
#          this tree would perturb the very crawl other gates measure.
import re, sys, pathlib, argparse

ROOT = pathlib.Path( __file__ ).resolve().parent.parent

# The site list is declared ONCE, here, and drives both the rewrite and the refusal scan. A duplicated
# list is the bug test/manifestcheck.sh's sibling arm keeps being widened to fix.
SITES = ( 'README.md', 'docs/EVALS.md', 'present/deck5_ripwire_build.js' )

MARKER = re.compile( r'<!--\s*gatecount\s*-->|//\s*gatecount(?![A-Za-z0-9_])' )

# Every spelling the count is published in. The whole match IS the digits — everything identifying the
# claim sits in fixed-width lookaround — so re.sub() with the new number rewrites the number and nothing
# else, even on a line that carries other figures (docs/EVALS.md's §8 sentence also states 210 and 200+).
SPELLINGS = (
    # prose: "<N> gate scripts"
    re.compile( r'(?<![0-9])[0-9]+(?= gate scripts)' ),
    # the showcase deck's stat() call: stat(s, "<N>", "gate scripts …") — the number and its label are
    # SEPARATE ARGUMENTS, so the prose spelling cannot see it.
    re.compile( r'(?<=")[0-9]+(?="[ \t]*,[ \t]*"gate scripts)' ),
    # docs/EVALS.md §8: "the loop in `test/regression.sh` names <N>"
    re.compile( r'(?<=loop in `test/regression\.sh` names )[0-9]+' ),
)


def loopCount( root ):
    """The single `for _g in NAME NAME …; do` line in test/regression.sh is the authority.

    The four gates invoked individually above it are NOT part of "the loop" and are deliberately
    excluded, matching what every published sentence actually claims."""
    path = root / 'test' / 'regression.sh'
    if not path.is_file():
        sys.exit( 'gatecount_build: no test/regression.sh under %s' % root )
    text = path.read_text( errors = 'replace' )
    loops = re.findall( r'for _g in (.*?); do', text, re.S )
    if len( loops ) != 1:
        sys.exit( 'gatecount_build: expected exactly ONE `for _g in …; do` loop in test/regression.sh, '
                  'found %d — the absorb loop changed shape, refusing to publish a number' % len( loops ) )
    names = loops[ 0 ].split()
    if not names:
        sys.exit( 'gatecount_build: the absorb loop in test/regression.sh names 0 gates — refusing' )
    return len( names )


def rewrite_marked_sites( root, count ):
    """Return [ ( relPath, newText, [ (line, oldValue) … ] ) … ], refusing on any unmarked claim."""
    plans, unmarked, orphanMarkers, empty = [], [], [], []
    for rel in SITES:
        path = root / rel
        if not path.is_file():
            sys.exit( 'gatecount_build: site %s does not exist under %s' % ( rel, root ) )
        lines = path.read_text( errors = 'replace' ).split( '\n' )
        out, seen = [], []
        for i, line in enumerate( lines, 1 ):
            marked = MARKER.search( line ) is not None
            hits = [ v for rx in SPELLINGS for v in rx.findall( line ) ]
            if hits and not marked:
                unmarked.append( '%s:%d states %s and carries no marker' % ( rel, i, '/'.join( hits ) ) )
            elif marked and not hits:
                orphanMarkers.append( '%s:%d' % ( rel, i ) )
            if marked and hits:
                for rx in SPELLINGS:
                    line = rx.sub( str( count ), line )
                seen += [ ( i, v ) for v in hits ]
            out.append( line )
        if not seen:
            empty.append( rel )
        plans.append( ( rel, '\n'.join( out ), seen ) )
    if unmarked:
        sys.exit( 'gatecount_build: HAND-WRITTEN gate count(s) found — mark the line with the marker '
                  'comment (see CONTRIBUTING.md) so this generator owns it:\n  ' + '\n  '.join( unmarked ) )
    if orphanMarkers:
        sys.exit( 'gatecount_build: marker(s) on a line stating no gate count — a claim deleted is a '
                  'claim drifted; restore the claim or drop the marker:\n  ' + '\n  '.join( orphanMarkers ) )
    if empty:
        sys.exit( 'gatecount_build: site(s) with no marked gate count at all: %s' % ', '.join( empty ) )
    return plans


ap = argparse.ArgumentParser()
ap.add_argument( '--check', action = 'store_true' )
ap.add_argument( '--root', default = None )
# --sites prints the site list and exits. test/gatecountcheck.sh arm (F) uses it to assert that this
# tuple, the gate's own copy, and test/manifestcheck.sh's `gateCountSites` name the same files — three
# hand-kept copies of one list is the shape that let a site go unscanned in the first place.
ap.add_argument( '--sites', action = 'store_true' )
a = ap.parse_args()
if a.sites:
    print( '\n'.join( SITES ) )
    sys.exit( 0 )
if a.root:
    ROOT = pathlib.Path( a.root ).resolve()

count = loopCount( ROOT )
plans = rewrite_marked_sites( ROOT, count )
sites = sum( len( s ) for _, _, s in plans )

if a.check:
    drift = []
    for rel, newText, seen in plans:
        cur = ( ROOT / rel ).read_text( errors = 'replace' )
        if cur != newText:
            named = [ '%s:%d says %s' % ( rel, ln, v ) for ln, v in seen if v != str( count ) ]
            # a difference this scan cannot name is still a difference — never report clean on one
            drift += named or [ '%s differs from what this generator produces' % rel ]
    if drift:
        sys.exit( 'gatecount_build: the loop in test/regression.sh names %d, but %s — run: '
                  'python3 docs/gatecount_build.py' % ( count, '; '.join( drift ) ) )
    print( 'gatecount_build: %d marked site(s) in %d file(s) all state the loop in test/regression.sh '
           'names %d' % ( sites, len( SITES ), count ) )
else:
    changed = 0
    for rel, newText, _ in plans:
        path = ROOT / rel
        if path.read_text( errors = 'replace' ) != newText:
            path.write_text( newText )
            changed += 1
    print( 'gatecount_build: wrote %d to %d marked site(s) across %d file(s) (%d file(s) changed)' %
           ( count, sites, len( SITES ), changed ) )
