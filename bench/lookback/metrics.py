#!/usr/bin/env python3
# metrics.py — §5 exactly: the tie-block effort curve, Popt, recall@20% LOC and AUROC.
#
# Exact arithmetic. Every area is kept as an INTEGER (twice the trapezoid sum in units of effort × fixes),
# and every ratio as a fractions.Fraction, so a result does not depend on summation order or platform
# floating point; floats appear only at the very end (float(Fraction) is correctly rounded).
#
#   units: a list of (score, effort, y) — effort a positive int (span lines), y in {0, 1} (or a count d_f
#   for S3; the curve then accumulates counts). Higher score = review first.
#
# Ties: each run of equal scores is ONE straight segment — the exact expected curve of a uniformly random
# order within the block — so no tiebreak and no sampling exist anywhere. RANDOM is one block: the diagonal.
from fractions import Fraction


def _blocks( units, key ):
    """Group units into consecutive blocks of equal key after sorting by key descending."""
    order = sorted( units, key=lambda u: key( u ), reverse=True )
    blocks, cur, cur_k = [], None, object()
    for u in order:
        k = key( u )
        if cur is None or k != cur_k:
            cur = [ 0, 0 ]
            blocks.append( cur )
            cur_k = k
        cur[ 0 ] += u[ 1 ]
        cur[ 1 ] += u[ 2 ]
    return [ tuple( b ) for b in blocks ]


def curve_points( blocks ):
    """Block list [(effort, y)] -> cumulative integer points [(E_i, Y_i)] from (0, 0)."""
    pts, e, y = [ ( 0, 0 ) ], 0, 0
    for be, by in blocks:
        e += be
        y += by
        pts.append( ( e, y ) )
    return pts


def area2( pts ):
    """Twice the trapezoid area under integer points, in units of effort × y (an int)."""
    return sum( ( e1 - e0 ) * ( y0 + y1 ) for ( e0, y0 ), ( e1, y1 ) in zip( pts, pts[ 1: ] ) )


def _density_key( u ):
    return Fraction( u[ 2 ], u[ 1 ] )


def _check( units ):
    for s, e, y in units:
        if not isinstance( e, int ) or e < 1:
            raise ValueError( "effort must be a positive int, got %r" % ( e, ) )
        if y < 0:
            raise ValueError( "y must be >= 0" )


def popt( units ):
    """Popt = 1 - (A_opt - A_arm) / (A_opt - A_worst); None when undefined (no fixes, or every unit has
    the same fix density so optimal == worst)."""
    _check( units )
    Y = sum( u[ 2 ] for u in units )
    if Y == 0:
        return None
    a_arm = area2( curve_points( _blocks( units, key=lambda u: u[ 0 ] ) ) )
    a_opt = area2( curve_points( _blocks( units, key=_density_key ) ) )
    a_worst = area2( curve_points( list( reversed( _blocks( units, key=_density_key ) ) ) ) )
    if a_opt == a_worst:
        return None
    return Fraction( a_arm - a_worst, a_opt - a_worst )


def normalised_area( units ):
    """The arm's area A in [0, 1] (the curve runs from (0,0) to (1,1))."""
    E = sum( u[ 1 ] for u in units )
    Y = sum( u[ 2 ] for u in units )
    return Fraction( area2( curve_points( _blocks( units, key=lambda u: u[ 0 ] ) ) ), 2 * E * Y )


def recall_at( units, x=Fraction( 1, 5 ) ):
    """The curve's y at effort fraction x, linear within the segment that straddles x."""
    _check( units )
    E = sum( u[ 1 ] for u in units )
    Y = sum( u[ 2 ] for u in units )
    if Y == 0:
        return None
    target = Fraction( x ) * E
    pts = curve_points( _blocks( units, key=lambda u: u[ 0 ] ) )
    for ( e0, y0 ), ( e1, y1 ) in zip( pts, pts[ 1: ] ):
        if e1 >= target:
            return ( y0 + ( target - e0 ) * Fraction( y1 - y0, e1 - e0 ) ) / Y
    return Fraction( 1 )


def auroc( units ):
    """Effort-blind Mann-Whitney AUROC with midranks: P(score_pos > score_neg) + 0.5 P(tie). y > 0 is a
    positive. None when either class is empty."""
    pos = [ u[ 0 ] for u in units if u[ 2 ] > 0 ]
    neg = [ u[ 0 ] for u in units if u[ 2 ] <= 0 ]
    if not pos or not neg:
        return None
    allv = sorted( [ ( v, 1 ) for v in pos ] + [ ( v, 0 ) for v in neg ], key=lambda t: t[ 0 ] )
    # midranks (1-based), kept as 2×rank integers
    rank2_sum_pos, i, n = 0, 0, len( allv )
    while i < n:
        j = i
        while j + 1 < n and allv[ j + 1 ][ 0 ] == allv[ i ][ 0 ]:
            j += 1
        mid2 = ( i + 1 ) + ( j + 1 )                       # 2 × the midrank of ranks i+1..j+1
        rank2_sum_pos += mid2 * sum( 1 for t in allv[ i:j + 1 ] if t[ 1 ] )
        i = j + 1
    P, N = len( pos ), len( neg )
    return ( Fraction( rank2_sum_pos, 2 ) - Fraction( P * ( P + 1 ), 2 ) ) / ( P * N )


def score_arm( units ):
    """{popt, recall20, auroc, area} as floats (None where undefined)."""
    f = lambda v: None if v is None else float( v )
    Y = sum( u[ 2 ] for u in units )
    return dict( popt=f( popt( units ) ), recall20=f( recall_at( units ) ), auroc=f( auroc( units ) ),
                 area=f( normalised_area( units ) ) if Y else None, n=len( units ), fixed=sum( 1 for u in units if u[ 2 ] > 0 ),
                 effort=sum( u[ 1 ] for u in units ) )
