#!/usr/bin/env python3
"""Shared history reader for the two co-change backtests (cochange_backtest.py, cochange_followup.py).

`load_commits` parses `git log --format='COMMIT %H %ad %s' --date=short --name-only`, keeps commits with
1..cap files (the Code Maat bulk-commit rule every --cochange walk applies) and returns them OLDEST FIRST.
`PairCounter` is the sliding-window pair/commit counter both backtests score from: `slide` drops commits
older than the window, `push` adds one, `together` reads a pair's joint-commit count."""
import collections, datetime

def load_commits( path, cap = 30 ):
    commits = []; cur = None
    for line in open( path, errors = 'replace' ):
        line = line.rstrip( '\n' )
        if line.startswith( 'COMMIT ' ):
            p = line.split( ' ', 3 ); cur = [ datetime.date.fromisoformat( p[ 2 ] ), [] ]; commits.append( cur )
        elif line.strip() and cur is not None:
            cur[ 1 ].append( line.strip() )
    return [ c for c in reversed( commits ) if 1 <= len( c[ 1 ] ) <= cap ]

class PairCounter:
    def __init__( self, window_days = 548 ):
        self.pair = collections.Counter(); self.cnt = collections.Counter()
        self.hist = collections.deque(); self.window = datetime.timedelta( days = window_days )
    def add( self, files, sign ):
        fs = sorted( set( files ) )
        for f in fs:
            self.cnt[ f ] += sign
        for i in range( len( fs ) ):
            for j in range( i + 1, len( fs ) ):
                self.pair[ ( fs[ i ], fs[ j ] ) ] += sign
    def slide( self, date ):
        while self.hist and self.hist[ 0 ][ 0 ] < date - self.window:
            self.add( self.hist.popleft()[ 1 ], -1 )
    def push( self, date, files ):
        self.add( files, +1 ); self.hist.append( ( date, files ) )
    def together( self, a, b ):
        return self.pair[ ( a, b ) if a < b else ( b, a ) ]
