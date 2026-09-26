#!/usr/bin/env python3
# rankers.py — every arm's score at T (§1), and the §4.3 health checks that run BEFORE any label is joined.
#
#   ripwire (the INSTALLED binary, version-pinned) supplies only ranker inputs: `--hotspots` (every page) and
#   `--metrics` (every symbol), run with --no-cache on a clean detached checkout of T.
#   git supplies CHURN and PRIOR (the look-back window, counted the way ripwire counts file churn:
#   `git log -c --since=@<T - 12 calendar months> --name-only`, every commit reachable from T, a merge
#   through its combined diff) and the effort (line counts).
#
# Scores are "higher = review first". HOT is a TUPLE (file score, function ccx) compared lexicographically;
# unranked files take file score -1, one tie block at the bottom.
import datetime, os, re, subprocess, sys, xml.etree.ElementTree as ET

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
import common, labels, maphunks

ARMS_FILE = ( "HOT", "CCX", "FANIN", "CHURN", "HOTFN", "PRIOR", "RANDOM", "SMALL", "BIG" )
FN_KINDS = frozenset( ( "fn", "method" ) )


# ── the look-back window, exactly as ripwire anchors it ─────────────────────────────────────────────────
def months_before_epoch( epoch, months ):
    """ripwire's monthsBeforeEpoch (src/gitmine.h): calendar-month subtraction in UTC; the day-of-month is
    added to the 1st of the target month, so it may overflow into the next month exactly as ripwire's does."""
    days, sec = divmod( epoch, 86400 )
    d0 = datetime.date( 1970, 1, 1 ) + datetime.timedelta( days=days )
    mi = d0.year * 12 + d0.month - 1 - months
    ny, nm = divmod( mi, 12 )
    target = datetime.date( ny, nm + 1, 1 ) + datetime.timedelta( days=d0.day - 1 )
    return ( target - datetime.date( 1970, 1, 1 ) ).days * 86400 + sec


def lookback_commits( repo, t_sha, months=common.LOOKBACK_MONTHS ):
    """[(sha, nparents, subject_or_pr_title, [paths])] for every commit reachable from T in ripwire's window."""
    t_epoch = int( common.git( repo, "show", "-s", "--format=%ct", t_sha ).strip() )
    since = months_before_epoch( t_epoch, months )
    out = common.git( repo, "log", "-c", "--since=@%d" % since, "--name-only", "--format=%x00%H%x01%P%x01%B%x02", t_sha )
    rows = []
    for rec in out.split( "\x00" )[ 1: ]:
        head, _, names = rec.partition( "\x02" )
        sha, parents, body = head.split( "\x01", 2 )
        body = body.rstrip( "\n" )
        np_ = len( parents.split() )
        subj = labels.pr_title_subject( body.split( "\n", 1 )[ 0 ], body, np_ )
        paths = [ maphunks.unquote_path( p ) for p in names.split( "\n" ) if p ]
        rows.append( ( sha, np_, subj, paths ) )
    return rows, since


# ── ripwire ─────────────────────────────────────────────────────────────────────────────────────────────
def ripwire_version( binary="ripwire" ):
    v = subprocess.run( [ binary, "--version" ], capture_output=True, text=True ).stdout.strip()
    return v


def _strip_comments( xml_text ):
    return re.sub( r"<!--.*?-->", "", xml_text, flags=re.S )


def run_hotspots( checkout, binary="ripwire", page=100000 ):
    """Every page of --hotspots. Returns (header attrs, {path: row attrs})."""
    rows, header, offset = {}, None, 0
    while True:
        p = subprocess.run( [ binary, checkout, "--hotspots", "--no-cache", "--limit=%d" % page, "--offset=%d" % offset ],
                            capture_output=True, text=True, errors="replace" )
        if p.returncode != 0:
            raise RuntimeError( "ripwire --hotspots rc=%d: %s" % ( p.returncode, p.stderr[ :300 ] ) )
        root = ET.fromstring( _strip_comments( p.stdout ) )
        el = root if root.tag == "hotspots" else root.find( ".//hotspots" )
        if el is None:
            raise RuntimeError( "no <hotspots> element" )
        if header is None:
            header = dict( el.attrib )
        for f in el.findall( "f" ):
            rows[ f.attrib[ "p" ] ] = dict( f.attrib )
        if el.attrib.get( "has_more" ) != "1":
            return header, rows
        offset = int( el.attrib[ "next_offset" ] )


def run_metrics( checkout, binary="ripwire", topk=10 ** 7 ):
    """--metrics over every symbol. Returns (header dict from the trailing counts comment, [row dicts])."""
    p = subprocess.run( [ binary, checkout, "--metrics", "--no-cache", "--top-k=%d" % topk, "--legend=compact" ],
                        capture_output=True, text=True, errors="replace" )
    if p.returncode != 0:
        raise RuntimeError( "ripwire --metrics rc=%d: %s" % ( p.returncode, p.stderr[ :300 ] ) )
    counts = {}
    for m in re.finditer( r"<!-- (files=\d+ symbols=\d+[^>]*?) -->", p.stdout ):
        for k, v in re.findall( r'(\w+)="?([^\s"]+)"?', m.group( 1 ) ):
            counts[ k ] = v
    root = ET.fromstring( _strip_comments( p.stdout ) )
    rows = []
    for f in root.iter( "f" ):
        path = f.attrib.get( "p" )
        for s in f.iter( "s" ):
            r = dict( s.attrib )
            r[ "p" ] = path
            rows.append( r )
    return counts, rows


def health_hotspots( header, t_sha ):
    """§4.3's two --hotspots floors. Returns a list of failure strings (empty = healthy)."""
    fails = []
    if header.get( "window" ) != "12mo@HEAD":
        fails.append( "window=%r" % header.get( "window" ) )
    at = header.get( "at", "" )
    if "+" in at or not at or not t_sha.startswith( at ):
        fails.append( "at=%r vs T=%s" % ( at, t_sha[ :12 ] ) )
    total = sum( int( header.get( k, 0 ) ) for k in ( "ranked", "unranked_no_churn", "unranked_no_complexity", "unranked_extent_suspect" ) )
    if total != int( header.get( "files", -1 ) ):
        fails.append( "ranked+unranked=%d != files=%s" % ( total, header.get( "files" ) ) )
    return fails


# ── file-grain arms (S5) ────────────────────────────────────────────────────────────────────────────────
def file_arms( units, hot_rows, metric_rows, lookback ):
    """units: {path: loc} at T (product source). Returns ({path: {arm: score}}, diagnostics)."""
    sccx, sin, has_fn = {}, {}, {}
    for r in metric_rows:
        if r.get( "t" ) not in FN_KINDS:
            continue
        p = r[ "p" ]
        has_fn[ p ] = True
        if "ccx" in r:
            sccx[ p ] = sccx.get( p, 0 ) + int( r[ "ccx" ] )
        if "in" in r:
            sin[ p ] = sin.get( p, 0 ) + int( r[ "in" ] )
    churn, prior = {}, {}
    for sha, np_, subj, paths in lookback:
        fix = labels.is_keyword_fix( subj )
        for p in set( paths ):
            churn[ p ] = churn.get( p, 0 ) + 1
            if fix:
                prior[ p ] = prior.get( p, 0 ) + 1
    out = {}
    for p, loc in units.items():
        h = hot_rows.get( p )
        c = sccx.get( p, 0 )
        out[ p ] = dict( HOT=int( h[ "score" ] ) if h else -1, CCX=c, FANIN=sin.get( p, 0 ), CHURN=churn.get( p, 0 ),
                         HOTFN=churn.get( p, 0 ) * c, PRIOR=prior.get( p, 0 ), RANDOM=0, SMALL=-loc, BIG=loc )
    diag = dict( units=len( units ), in_hotspots_ranked=sum( 1 for p in units if p in hot_rows ),
                 with_metrics_fn=sum( 1 for p in units if p in has_fn ), with_churn=sum( 1 for p in units if churn.get( p ) ) )
    return out, diag


# ── function-grain join (§4.3), ready for the independent parser ────────────────────────────────────────
def join_function_rows( parser_units, rw_rows, slack=common.JOIN_LINE_SLACK ):
    """parser_units: [(path, scope, name, ordinal, start, end)]; rw_rows: [dict(p, sc, n, l, ...)] where l is
    the start line (from --pack-signatures; --metrics rows carry none). Joined by path, scope and name, then
    start line within ±slack; a parser unit with zero or several candidates is dropped and counted.
    Returns ({unit_key: row}, counters)."""
    by_key = {}
    for r in rw_rows:
        by_key.setdefault( ( r[ "p" ], r.get( "sc", "" ), r[ "n" ] ), [] ).append( r )
    joined, amb, miss = {}, 0, 0
    for path, scope, name, ordinal, start, end in parser_units:
        cands = [ r for r in by_key.get( ( path, scope, name ), [] ) if "l" in r and abs( int( r[ "l" ] ) - start ) <= slack ]
        if len( cands ) == 1:
            joined[ ( path, scope, name, ordinal ) ] = cands[ 0 ]
        elif cands:
            amb += 1
        else:
            miss += 1
    return joined, dict( joined=len( joined ), ambiguous=amb, missing=miss, units=len( parser_units ) )
