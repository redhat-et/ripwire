#!/usr/bin/env python3
"""gateregistry.py — the absorb list in test/regression.sh: its shape, and (given a listing) its membership.

    python3 test/lib/gateregistry.py test/regression.sh              # shape only
    python3 test/lib/gateregistry.py test/regression.sh LISTING      # shape + membership

SHAPE. `for _g in \\`, then one `    name \\` line per gate in byte (LC_ALL=C) order with no duplicate, then a
bare `    ; do` line, and exactly one such loop. One name per line is what lets two branches that each add a
gate merge without a conflict (they touch different lines); the old single-line list conflicted on every
gate added anywhere. A name parked after `; do` -- the old merge-resolution trap -- breaks the shape.

MEMBERSHIP. LISTING names every top-level test/*.sh that CI's test/pargates.py runs (no dotfile, not
regression.sh), one stem per line. It must equal the absorb list plus the gates regression.sh invokes by
name (`bash "$ROOT/test/NAME.sh"` on a non-comment line above the loop), and those two must not overlap.
Otherwise a gate file exists that regression.sh never runs, CI runs a script no list registers, or a
listed gate has no file. test/manifestcheck.sh runs this with mutation controls; scripts/merge_main.sh
runs both halves after a merge, with the same listing.

Prints PASS/FAIL lines; exit 0 when clean, 1 on any FAIL.
"""
import re, sys

LIST_LINE = re.compile( r'    ([A-Za-z0-9_.-]+) \\' )

def check( regPath, listingPath = None ):
    text = open( regPath, encoding = 'utf-8', errors = 'replace' ).read()
    bad  = []
    m = re.search( r'^for _g in \\\n(.*?)^    ; do\n', text, re.S | re.M )
    if m is None or len( re.findall( r'^for _g in ', text, re.M ) ) != 1:
        return [ 'test/regression.sh has no single absorb list in the one-name-per-line shape '
                 '(`for _g in \\`, `    name \\` lines, then `    ; do`)' ], None
    names = []
    for ln in m.group( 1 ).split( '\n' )[ :-1 ]:
        mm = LIST_LINE.fullmatch( ln )
        if mm is None:
            bad.append( 'absorb list line is not `    name \\`: %r' % ln )
        else:
            names.append( mm.group( 1 ) )
    if not names:
        bad.append( 'the absorb list names no gate at all' )
    seen, dups = set(), set()
    for n in names:
        ( dups if n in seen else seen ).add( n )
    if dups:
        bad.append( 'absorb list names a gate twice: %s' % ' '.join( sorted( dups ) ) )
    if names != sorted( names ):
        first = next( names[ i ] for i in range( 1, len( names ) ) if names[ i ] < names[ i - 1 ] )
        bad.append( 'absorb list is not in byte order (first out of place: %s) -- move the line, '
                    'or run scripts/merge_main.sh --sort-list' % first )
    summary = '%d listed' % len( names )
    if listingPath is not None:
        files = set( n for n in open( listingPath ).read().split() if n )
        if not files:
            bad.append( 'the listing of test/*.sh is empty -- the membership check would be vacuous' )
        code  = '\n'.join( re.sub( r'(^|\s)#.*$', '', ln ) for ln in text[ :m.start() ].split( '\n' ) )
        named = set( re.findall( r'bash "\$ROOT/test/([A-Za-z0-9_.-]+)\.sh"', code ) )
        both  = sorted( named & set( names ) )
        if both:
            bad.append( 'gate both invoked by name and listed in the absorb loop (it runs twice): %s' % ' '.join( both ) )
        registered = named | set( names )
        for n in sorted( files - registered ):
            bad.append( 'test/%s.sh exists (CI runs it) but test/regression.sh neither lists nor invokes it' % n )
        for n in sorted( registered - files ):
            bad.append( 'test/regression.sh registers %s but test/%s.sh does not exist' % ( n, n ) )
        summary = ( 'the %d top-level test/*.sh gates CI runs are exactly the %d in the absorb list plus the %d '
                    'regression.sh invokes by name' % ( len( files ), len( names ), len( named ) ) )
    return bad, summary

if __name__ == '__main__':
    if len( sys.argv ) not in ( 2, 3 ):
        sys.exit( 'usage: gateregistry.py REGRESSION_SH [LISTING]' )
    bad, summary = check( sys.argv[ 1 ], sys.argv[ 2 ] if len( sys.argv ) == 3 else None )
    for b in bad:
        print( 'FAIL: (REGISTRY) ' + b )
    if not bad:
        print( 'PASS: (REGISTRY) %s; the list is one name per line, byte-sorted, no duplicate' % summary )
    sys.exit( 1 if bad else 0 )
