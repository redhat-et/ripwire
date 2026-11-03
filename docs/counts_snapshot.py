#!/usr/bin/env python3
"""counts_snapshot.py — the dated snapshot of every TOTAL the generated docs publish.

WHY A SNAPSHOT. A total (the gate count, the cap inventory, LIMITS.md's class counts, TUNING.md's census) is
a function of the whole population. Two open PRs that each add one gate or one cap both recompute it, to
different values, on the same line, and GitHub marks every other open PR CONFLICTING after each landing
(measured 2026-11-02: #509, #512 and #505 against main, every hunk a total). No line layout lets git merge
two different values of one number. So the totals are not recomputed by a feature PR: the generators
render them from this one committed file, `docs/counts.tsv`, stamped with the date it was taken, and rewrite
only the per-item content (the absorb list, LIMITS.md's per-file tables, TUNING.md's per-cap tables), which
two PRs touch on different lines.

What still holds on every merge: each generator's --check proves its per-item content against the tree and
that every published total equals this snapshot (a hand-edited or half-merged total is red), and prints the
live value beside the snapshot one. What moves here: "the total equals the live tree" is asserted by
`check` below, at a refresh and at a release, instead of on every PR.

Usage:
  python3 docs/counts_snapshot.py show       # snapshot vs live, one line per total (exit 0)
  python3 docs/counts_snapshot.py check      # exit 1 when any total differs from the live tree (release gate)
  python3 docs/counts_snapshot.py refresh    # re-take every total from the live tree, then rewrite the docs
                                             # (a maintainer step: a release commit or a standalone PR)
File format: `#` comment lines, then `key<TAB>value` lines; `taken<TAB>YYYY-MM-DD` is required.
"""
import datetime, os, re, subprocess, sys

HERE = os.path.dirname( os.path.abspath( __file__ ) )
NAME = os.path.join( 'docs', 'counts.tsv' )
DATE = re.compile( r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' )
KEY  = re.compile( r'^[a-z][a-z0-9_.]*$' )

# The generators that own totals, each with the argv that prints its live totals as `key<TAB>value` lines
# and the argv that rewrites its documents from the snapshot. One list: refresh, show and check read it.
GENERATORS = (
    ( 'docs/gatecount_build.py',    [ '--live-counts' ],         [] ),
    ( 'docs/limits_build.py',       [ '--live-counts' ],         [] ),
    ( 'bench/capsweep/capsweep.py', [ 'emit', '--live-counts' ], [ 'emit' ] ),
)

def path( root ):
    return os.path.join( str( root ), NAME )

def read( root ):
    """The snapshot under root as { key: value-string }, or None when root has no docs/counts.tsv (a
    synthetic tree a gate built: its generators then render live totals). A malformed file is an error,
    never "no snapshot"."""
    p = path( root )
    if not os.path.exists( p ):
        return None
    out = {}
    try:
        lines = open( p, encoding = 'utf-8' ).read().split( '\n' )
    except OSError as e:
        sys.exit( 'counts_snapshot: cannot read %s: %s' % ( NAME, e ) )
    for i, line in enumerate( lines, 1 ):
        if not line or line.startswith( '#' ):
            continue
        parts = line.split( '\t' )
        if len( parts ) != 2 or not KEY.match( parts[ 0 ] ) or parts[ 1 ] == '' or parts[ 0 ] in out:
            sys.exit( 'counts_snapshot: %s:%d is not a unique `key<TAB>value` line: %r' % ( NAME, i, line ) )
        out[ parts[ 0 ] ] = parts[ 1 ]
    if not DATE.match( out.get( 'taken', '' ) ):
        sys.exit( 'counts_snapshot: %s has no `taken<TAB>YYYY-MM-DD` line' % NAME )
    return out

def published( snap, live, who ):
    """The totals a generator publishes: the snapshot's value for every key the generator computed live, or
    the live values when there is no snapshot. A key the snapshot lacks is an error (run refresh), never a
    silent fall-back to the live number, which is the number two PRs both change."""
    if snap is None:
        return dict( live )
    missing = sorted( k for k in live if k not in snap )
    if missing:
        sys.exit( '%s: docs/counts.tsv has no %s — run: python3 docs/counts_snapshot.py refresh' % ( who, ', '.join( missing ) ) )
    out = {}
    for k, v in live.items():
        out[ k ] = type( v )( snap[ k ] ) if isinstance( v, int ) else snap[ k ]
    return out

def drift( snap, live ):
    """`key snapshot→live` for every published total that differs from the live tree (empty: none)."""
    if snap is None:
        return []
    return [ '%s %s→%s' % ( k, snap.get( k, '?' ), v ) for k, v in sorted( live.items() ) if snap.get( k ) != str( v ) ]

def live_counts( root ):
    """{ key: value } from every generator's --live-counts. A generator that fails or prints no total is an
    error, never an empty population."""
    out = {}
    for gen, liveArgv, _ in GENERATORS:
        p = subprocess.run( [ sys.executable, '-B', os.path.join( root, gen ) ] + liveArgv,
                            capture_output = True, text = True, cwd = root )
        rows = [ l.split( '\t' ) for l in p.stdout.split( '\n' ) if l ]
        if p.returncode != 0 or not rows or any( len( r ) != 2 or not KEY.match( r[ 0 ] ) for r in rows ):
            sys.exit( 'counts_snapshot: %s %s failed (exit %d): %s' % ( gen, ' '.join( liveArgv ), p.returncode,
                                                                       ( p.stderr or p.stdout ).strip()[ :400 ] ) )
        for k, v in rows:
            if k in out:
                sys.exit( 'counts_snapshot: two generators both publish %s' % k )
            out[ k ] = v
    return out

HEADER = ( '# docs/counts.tsv — the dated snapshot of every total the generated docs publish (README.md, docs/EVALS.md,\n'
           '# docs/LIMITS.md, docs/TUNING.md, the deck). Generated, do not edit: `python3 docs/counts_snapshot.py refresh`\n'
           '# re-takes it from the tree; `check` compares it with the tree. A feature PR leaves it alone, which is what keeps\n'
           '# two open PRs that each add a gate or a cap from conflicting on a total.\n' )

def write( root, values, taken ):
    body = HEADER + 'taken\t%s\n' % taken + ''.join( '%s\t%s\n' % kv for kv in sorted( values.items() ) )
    with open( path( root ), 'w', encoding = 'utf-8' ) as fh:
        fh.write( body )

def refresh( root, live ):
    taken = os.environ.get( 'COUNTS_TAKEN' ) or datetime.datetime.now( datetime.timezone.utc ).strftime( '%Y-%m-%d' )
    if not DATE.match( taken ):
        sys.exit( 'counts_snapshot: COUNTS_TAKEN=%r is not YYYY-MM-DD' % taken )
    write( root, live, taken )
    for gen, _, writeArgv in GENERATORS:
        p = subprocess.run( [ sys.executable, '-B', os.path.join( root, gen ) ] + writeArgv, cwd = root )
        if p.returncode != 0:
            sys.exit( 'counts_snapshot: %s %s failed after the refresh (exit %d)' % ( gen, ' '.join( writeArgv ), p.returncode ) )
    print( 'counts_snapshot: took %d totals on %s and rewrote the docs from them' % ( len( live ), taken ) )
    return 0

def show( snap, live ):
    for k in sorted( live ):
        print( '%-28s snapshot %-12s live %s%s' % ( k, snap.get( k, '?' ), live[ k ], '' if snap.get( k ) == live[ k ] else '   (differs)' ) )
    print( 'counts_snapshot: taken %s; %d of %d totals differ from the live tree' % ( snap[ 'taken' ], len( drift( snap, live ) ), len( live ) ) )
    return 0

def main( argv ):
    if len( argv ) != 2 or argv[ 1 ] not in ( 'show', 'check', 'refresh' ):
        sys.stderr.write( __doc__.split( 'Usage:' )[ 1 ] ); return 2
    root = os.path.dirname( HERE )
    live = live_counts( root )
    if argv[ 1 ] == 'refresh':
        return refresh( root, live )
    snap = read( root )
    if snap is None:
        sys.exit( 'counts_snapshot: no %s — run: python3 docs/counts_snapshot.py refresh' % NAME )
    stale = drift( snap, live )
    extra = sorted( k for k in snap if k != 'taken' and k not in live )
    if argv[ 1 ] == 'show':
        return show( snap, live )
    if stale or extra:
        print( 'counts_snapshot: the snapshot taken %s is STALE against the tree: %s — run: python3 docs/counts_snapshot.py refresh'
               % ( snap[ 'taken' ], '; '.join( stale + [ '%s no longer published' % k for k in extra ] ) ) )
        return 1
    print( 'counts_snapshot: all %d totals taken %s equal the live tree' % ( len( live ), snap[ 'taken' ] ) )
    return 0

if __name__ == '__main__':
    sys.exit( main( sys.argv ) )
