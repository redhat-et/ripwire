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
`check` below: exactly at a refresh and by the release workflow (.github/workflows/release.yml refuses a tag
whose snapshot differs from the tree), and within a bound on every PR (`check --max-drift`, run by
test/gendocsmergecheck.sh in regression: red once the live tree is more than MAX_DRIFT away, so the totals
lag by at most that much before somebody refreshes). The rule: a refresh rides every train PR, and any PR
that turns the drift arm red carries one (a refresh touches only total lines and this file, which no feature
PR touches, so it conflicts with nobody).

Usage:
  python3 docs/counts_snapshot.py show       # snapshot vs live, one line per total (exit 0)
  python3 docs/counts_snapshot.py check      # exit 1 when any total differs from the live tree (release gate)
  python3 docs/counts_snapshot.py check --max-drift
                                             # exit 1 only when a bounded total drifted past MAX_DRIFT (per-PR gate)
  python3 docs/counts_snapshot.py refresh    # re-take every total from the live tree, then rewrite the docs
                                             # (a maintainer step: a release commit or a standalone PR)
File format: `#` comment lines, then `key<TAB>value` lines; `taken<TAB>YYYY-MM-DD` is required.
"""
import datetime, os, re, subprocess, sys

HERE = os.path.dirname( os.path.abspath( __file__ ) )
NAME = os.path.join( 'docs', 'counts.tsv' )
DATE = re.compile( r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' )
KEY  = re.compile( r'^[a-z][a-z0-9_.]*$' )

# How far the published totals may lag the tree before a regular gate goes red (check --max-drift): one
# constant per bounded total, so changing the rule is a one-number edit. Measured pace on main (2026-10-19 to
# 11-02): about 3.6 gates and 7 caps a day, so each bound is two to three days of landings.
MAX_DRIFT = { 'gates.scripts': 10, 'limits.caps': 20 }

# Every file a refresh rewrites (docs/counts.tsv plus the write-mode generators' outputs): a refresh that fails
# part-way restores all of them, so a failed refresh leaves no half-published snapshot.
WRITES = ( NAME, 'README.md', 'docs/EVALS.md', 'present/deck5_ripwire_build.js', 'docs/LIMITS.md', 'docs/TUNING.md' )

# Sums the published totals must satisfy whatever their date (a hand-edited snapshot that moved one total and
# not its parts is refused by every generator): ( total, [ parts ] ).
SUMS = ( ( 'limits.caps', ( 'limits.disclosing', 'limits.silent' ) ),
         ( 'limits.constants', ( 'limits.caps', 'limits.parameters' ) ) )

def isDate( s ):
    """A real calendar date spelled YYYY-MM-DD (2026-11-31 is refused, not just a malformed shape)."""
    if not DATE.match( s or '' ):
        return False
    try:
        datetime.date.fromisoformat( s )
    except ValueError:
        return False
    return True

def sumErrors( values ):
    """`total = a + b` lines for every SUMS rule the values break (empty: they add up). Keys a tree does not
    publish are skipped; a non-integer value in a summed key is an error."""
    out = []
    for total, parts in SUMS:
        if total not in values or any( p not in values for p in parts ):
            continue
        try:
            t, ps = int( values[ total ] ), [ int( values[ p ] ) for p in parts ]
        except ValueError:
            out.append( '%s or its parts are not integers' % total ); continue
        if t != sum( ps ):
            out.append( '%s %d != %s %s' % ( total, t, ' + '.join( parts ), ' + '.join( str( p ) for p in ps ) ) )
    return out

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
    if not isDate( out.get( 'taken', '' ) ):
        sys.exit( 'counts_snapshot: %s has no `taken<TAB>YYYY-MM-DD` line with a real date' % NAME )
    bad = sumErrors( out )
    if bad:
        sys.exit( 'counts_snapshot: %s does not add up (hand-edited?): %s — run: python3 docs/counts_snapshot.py refresh'
                  % ( NAME, '; '.join( bad ) ) )
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
    tmp = path( root ) + '.tmp'
    with open( tmp, 'w', encoding = 'utf-8' ) as fh:
        fh.write( body )
    os.replace( tmp, path( root ) )

def refresh( root, live ):
    """Write the snapshot, then every generator's documents from it. All or nothing: when a generator fails,
    every file in WRITES goes back to its bytes before the refresh (the snapshot included), so `check` cannot
    pass on a snapshot whose documents were never written."""
    taken = os.environ.get( 'COUNTS_TAKEN' ) or datetime.datetime.now( datetime.timezone.utc ).strftime( '%Y-%m-%d' )
    if not isDate( taken ):
        sys.exit( 'counts_snapshot: COUNTS_TAKEN=%r is not a real YYYY-MM-DD date' % taken )
    bad = sumErrors( live )
    if bad:
        sys.exit( 'counts_snapshot: the live totals do not add up (a generator bug): %s' % '; '.join( bad ) )
    saved = {}
    for rel in WRITES:
        p = os.path.join( root, rel )
        saved[ rel ] = open( p, 'rb' ).read() if os.path.exists( p ) else None
    def restore( why ):
        for rel, data in saved.items():
            p = os.path.join( root, rel )
            if data is None:
                if os.path.exists( p ):
                    os.remove( p )
            else:
                with open( p, 'wb' ) as fh:
                    fh.write( data )
        sys.exit( 'counts_snapshot: %s — restored %s as they were before the refresh' % ( why, ', '.join( WRITES ) ) )
    try:
        write( root, live, taken )
        for gen, _, writeArgv in GENERATORS:
            p = subprocess.run( [ sys.executable, '-B', os.path.join( root, gen ) ] + writeArgv, cwd = root )
            if p.returncode != 0:
                restore( '%s %s failed after the refresh (exit %d)' % ( gen, ' '.join( writeArgv ), p.returncode ) )
    except OSError as e:
        restore( 'a write failed during the refresh: %s' % e )
    print( 'counts_snapshot: took %d totals on %s and rewrote the docs from them' % ( len( live ), taken ) )
    return 0

def obsolete( snap, live ):
    """Snapshot keys no generator publishes any more (check refuses them; show lists them)."""
    return sorted( k for k in snap if k != 'taken' and k not in live )

def show( snap, live ):
    for k in sorted( live ):
        print( '%-28s snapshot %-12s live %s%s' % ( k, snap.get( k, '?' ), live[ k ], '' if snap.get( k ) == live[ k ] else '   (differs)' ) )
    gone = obsolete( snap, live )
    for k in gone:
        print( '%-28s snapshot %-12s live -   (no longer published)' % ( k, snap[ k ] ) )
    print( 'counts_snapshot: taken %s; %d of %d totals differ from the live tree%s'
           % ( snap[ 'taken' ], len( drift( snap, live ) ) + len( gone ), len( live ) + len( gone ),
               ( '; %d snapshot key(s) no longer published' % len( gone ) ) if gone else '' ) )
    return 0

def overDrift( snap, live ):
    """`key snapshot→live (bound B)` for every MAX_DRIFT total whose live value is more than B away from the
    snapshot, either way (empty: within bounds). A non-integer value in a bounded key is an error."""
    out = []
    for k, bound in sorted( MAX_DRIFT.items() ):
        if k not in live:
            continue
        try:
            d = abs( int( live[ k ] ) - int( snap[ k ] ) )
        except ( KeyError, ValueError ):
            sys.exit( 'counts_snapshot: %s is missing or not an integer in the snapshot or the tree' % k )
        if d > bound:
            out.append( '%s %s→%s (drift %d, bound %d)' % ( k, snap[ k ], live[ k ], d, bound ) )
    return out

def main( argv ):
    bounded = argv[ 1: ] == [ 'check', '--max-drift' ]
    if not bounded and ( len( argv ) != 2 or argv[ 1 ] not in ( 'show', 'check', 'refresh' ) ):
        sys.stderr.write( __doc__.split( 'Usage:' )[ 1 ] ); return 2
    root = os.path.dirname( HERE )
    live = live_counts( root )
    if argv[ 1 ] == 'refresh':
        return refresh( root, live )
    snap = read( root )
    if snap is None:
        sys.exit( 'counts_snapshot: no %s — run: python3 docs/counts_snapshot.py refresh' % NAME )
    stale = drift( snap, live )
    extra = obsolete( snap, live )
    if argv[ 1 ] == 'show':
        return show( snap, live )
    if bounded:
        over = overDrift( snap, live )
        if over or extra:
            print( 'counts_snapshot: the snapshot taken %s lags the tree past the bound: %s — run: python3 docs/counts_snapshot.py refresh '
                   '(in this PR; a refresh conflicts with no feature PR)' % ( snap[ 'taken' ], '; '.join( over + [ '%s no longer published' % k for k in extra ] ) ) )
            return 1
        print( 'counts_snapshot: the snapshot taken %s is within the drift bound (%s); %d of %d totals differ from the live tree'
               % ( snap[ 'taken' ], ', '.join( '%s ≤ %d' % kv for kv in sorted( MAX_DRIFT.items() ) ), len( stale ), len( live ) ) )
        return 0
    if stale or extra:
        print( 'counts_snapshot: the snapshot taken %s is STALE against the tree: %s — run: python3 docs/counts_snapshot.py refresh'
               % ( snap[ 'taken' ], '; '.join( stale + [ '%s no longer published' % k for k in extra ] ) ) )
        return 1
    print( 'counts_snapshot: all %d totals taken %s equal the live tree' % ( len( live ), snap[ 'taken' ] ) )
    return 0

if __name__ == '__main__':
    sys.exit( main( sys.argv ) )
