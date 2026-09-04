# Phase 5 fixture, the in-repo side of ext.py's import (`from .own import helper`).
#   sum()   a MODULE-LEVEL definition named like a builtin — same-file definition evidence for K.go's
#           bare `sum([1])` (gate arm E): the edge to this def stays, the veto never fires here.
#   helper  the target of ext.py's in-repo import (arm D).


def sum( xs ):
    return 0


def helper( x ):
    return x


class K:
    def go( self ):
        return sum( [ 1 ] )
