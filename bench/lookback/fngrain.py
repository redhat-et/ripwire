#!/usr/bin/env python3
# fngrain.py — the FUNCTION grain (§1 primary): population at T from the independent parser (tsparse.py), the
# §4.3 join of parser units to ripwire rows, and the look-back predictors CHURN / PRIOR through the one mapper.
#
#   join      parser unit (path, scope, name, ordinal, start) -> the ONE `--graph-query=all` row with the same
#             path and name whose line is within ±3 of start (zero or several: dropped and counted); its ccx=/in=
#             come from the `--metrics` row with that (path, name) — disambiguated by scope when several. A unit
#             whose metrics row merged several same-name definitions (overloads=N>1), or that no single row
#             matches, is an AMBIGUOUS match: dropped and counted against the join floor (§4.3 "ambiguous matches
#             are dropped and counted"), never scored with another definition's ccx.
#   look-back every commit reachable from T in ripwire's 12-month window (merges through their combined diff, as
#             ripwire counts file churn); each commit's hunks are mapped at its parent and carried to T's paths by
#             a rename map built newest-to-oldest over the first-parent chain; a side-branch commit uses the map
#             of the first-parent merge that landed it.
import os, re, subprocess, sys, xml.etree.ElementTree as ET

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
import common, labels, maphunks, rankers

FN_KINDS = rankers.FN_KINDS


def keystr( key ):
    return "\t".join( str( x ) for x in key )


def population( cache, blobs_by_path, disk=None ):
    """{key: (start, end)} over every product file at T, and parse counts (the parser half of the parse floor)."""
    pop, st = {}, dict( files=len( blobs_by_path ), parsed=0, with_error=0, too_big=0, failed=0, unsupported=0 )
    for path in sorted( blobs_by_path ):
        units = cache.units_blob( blobs_by_path[ path ], path, disk )
        st[ cache.status( blobs_by_path[ path ], path ) ] += 1
        for scope, name, ordinal, s, e in units:
            pop[ ( path, scope, name, ordinal ) ] = ( s, e )
    st[ "read_fraction" ] = ( st[ "parsed" ] + st[ "with_error" ] ) / st[ "files" ] if st[ "files" ] else 0.0
    return pop, st


def run_graph_rows( checkout, binary="ripwire" ):
    """[(path, name, kind, line)] for every symbol `--graph-query=all` lists."""
    p = subprocess.run( [ binary, checkout, "--graph-query=all", "--limit=100000000", "--no-cache", "--legend=compact" ],
                        capture_output=True, text=True, errors="replace" )
    if p.returncode != 0:
        raise RuntimeError( "ripwire --graph-query rc=%d: %s" % ( p.returncode, p.stderr[ :300 ] ) )
    root = ET.fromstring( rankers.XML_COMMENT_RE.sub( "", p.stdout ) )
    q = root if root.tag == "query" else root.find( ".//query" )
    if q is not None and q.attrib.get( "has_more" ) == "1":
        raise RuntimeError( "graph-query was cut" )
    rows = []
    for s in root.iter( "s" ):
        path, _, line = s.attrib.get( "p", "" ).rpartition( ":" )
        if path and line.isdigit():
            rows.append( ( path, s.attrib.get( "n", "" ), s.attrib.get( "t", "" ), int( line ) ) )
    return rows


def join( pop, graph_rows, metric_rows, slack=common.JOIN_LINE_SLACK ):
    """{key: (ccx|None, fanin|None)} for joined units, and counters."""
    by_pn = {}
    for path, name, kind, line in graph_rows:
        if kind in FN_KINDS:
            by_pn.setdefault( ( path, name ), [] ).append( line )
    met = {}
    for r in metric_rows:
        if r.get( "t" ) in FN_KINDS:
            met.setdefault( ( r[ "p" ], r[ "n" ] ), [] ).append( r )
    out, c = {}, dict( units=len( pop ), joined=0, ambiguous=0, missing=0, ccx=0, overload_merged=0, metrics_ambiguous=0 )
    for key, ( s, e ) in pop.items():
        path, scope, name, _ = key
        cands = [ l for l in by_pn.get( ( path, name ), [] ) if abs( l - s ) <= slack ]
        if len( cands ) != 1:
            c[ "ambiguous" if cands else "missing" ] += 1
            continue
        rows = met.get( ( path, name ), [] )
        if len( rows ) > 1:
            rows = [ r for r in rows if r.get( "sc", "" ) == scope ]
        if len( rows ) != 1:
            c[ "metrics_ambiguous" ] += 1
            continue
        if int( rows[ 0 ].get( "overloads", "1" ) ) > 1:
            c[ "overload_merged" ] += 1
            continue
        c[ "joined" ] += 1
        ccx = int( rows[ 0 ][ "ccx" ] ) if "ccx" in rows[ 0 ] else None
        fanin = int( rows[ 0 ].get( "in", 0 ) )
        if ccx is not None:
            c[ "ccx" ] += 1
        out[ key ] = ( ccx, fanin )
    return out, c


class _Snap:
    def __init__( self, m ):
        self.m = m

    def path_at_t( self, p ):
        return self.m.get( p, p )


def lookback_fn( repo, t_sha, since, t_index, units_fn ):
    """({key: CHURN}, {key: PRIOR}, counters) over every commit reachable from T since `since`."""
    fp = maphunks._split_log( common.git( repo, "log", "--first-parent", "--since=@%d" % since, "-M", "--no-ext-diff",
                                          "--format=%x00%H", "--name-status", t_sha ) )          # newest first
    fp = [ ( sha, maphunks._parse_name_status_lines( text ) ) for sha, text in fp ]
    snaps, m = {}, {}
    for sha, files in fp:
        snaps[ sha ] = dict( m )
        adds = []
        for old, new, *_ in files:
            if old is not None and new is not None and old != new:
                m[ old ] = m.get( new, new )
            elif old is None and new is not None:
                adds.append( new )
            elif new is None:
                m[ old ] = None
        for a in adds:
            m[ a ] = None
    oldest = fp[ -1 ][ 0 ] if fp else None
    # landing first-parent commit of every commit in the window
    allc = {}
    for line in common.git( repo, "log", "--since=@%d" % since, "--format=%H %P", t_sha ).split( "\n" ):
        if line:
            h, *ps = line.split()
            allc[ h ] = ps
    landing = { sha: sha for sha, _ in fp }
    for sha, _ in reversed( fp ):                              # oldest first
        stack = list( allc.get( sha, [] )[ 1: ] )
        while stack:
            x = stack.pop()
            if x in landing or x not in allc:
                continue
            landing[ x ] = sha
            stack.extend( allc[ x ] )
    recs = maphunks.parse_log_patch( common.git( repo, "log", "-c", "-p", "-U0", "-M", "--full-index", "--no-color", "--no-ext-diff",
                                                 "--since=@%d" % since, "--format=%x00%H%x01%P%x01%B%x02", t_sha ) )
    churn, prior = {}, {}
    t_paths = { k[ 0 ] for k in t_index }
    c = dict( commits=len( recs ), unlanded=0, hunks=0, mapped=0 )
    for sha, npar, body, files in recs:
        land = landing.get( sha )
        if land is None:
            c[ "unlanded" ] += 1
            land = oldest
        snap = _Snap( snaps.get( land, {} ) )
        hit, n = maphunks.touched_units( files, units_fn, snap, t_index, t_paths )
        c[ "hunks" ] += n[ "hunks" ]
        c[ "mapped" ] += n[ "mapped" ]
        subject = labels.pr_title_subject( body.split( "\n", 1 )[ 0 ], body, npar )
        fix = labels.is_keyword_fix( subject )
        for k in hit:
            churn[ k ] = churn.get( k, 0 ) + 1
            if fix:
                prior[ k ] = prior.get( k, 0 ) + 1
    return churn, prior, c


def fn_arms( scored, pop, hot_rows, churn, prior ):
    """{keystr: arm scores} over the scored population (joined units with a ccx)."""
    out = {}
    for key, ( ccx, fanin ) in scored.items():
        s, e = pop[ key ]
        loc = e - s + 1
        h = hot_rows.get( key[ 0 ] )
        ch = churn.get( key, 0 )
        out[ keystr( key ) ] = dict( HOT=( int( h[ "score" ] ) if h else -1, ccx ), CCX=ccx, FANIN=fanin or 0, CHURN=ch, HOTFN=ch * ccx,
                                     PRIOR=prior.get( key, 0 ), RANDOM=0, SMALL=-loc, BIG=loc )
    return out


def excerpt( data, rec, units_near, before=25, after=2, max_hunk=8 ):
    """A hand-check card for one fix hunk: the parent's lines around it (hunk lines marked '>'), and the parser's
    units near it with their spans."""
    lines = data.decode( "utf-8", "replace" ).split( "\n" )
    lo, hi = maphunks.old_lines( rec[ "start" ], rec[ "length" ] )
    a, b = max( 1, lo - before ), min( len( lines ), hi + after )
    out = []
    for i in range( a, b + 1 ):
        if lo + max_hunk // 2 <= i <= hi - max_hunk // 2:
            if i == lo + max_hunk // 2:
                out.append( "      ... %d hunk lines elided" % ( hi - lo + 1 - max_hunk ) )
            continue
        out.append( "%s%5d %s" % ( ">" if lo <= i <= hi else " ", i, lines[ i - 1 ][ :140 ] ) )
    near = [ "%s::%s#%d [%d-%d]" % ( u[ 0 ], u[ 1 ], u[ 2 ], u[ 3 ], u[ 4 ] ) for u in units_near if u[ 4 ] >= lo - 60 and u[ 3 ] <= hi + 60 ]
    return "\n".join( out ), near
