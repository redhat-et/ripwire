#!/usr/bin/env python3
# exclusions.py — builds §2's exclusion list E: every repository the tool was developed or measured against.
#
# Two halves, merged into one sorted, lowercased `owner/name` list whose SHA-256 is printed (and, at freeze,
# committed):
#   mechanical — a scan of THIS tree's docs/EVALS.md, bench/** (locks, READMEs, scripts), every README and
#                every script under test/ for `github.com/owner/name` and `owner__name` (the SWE-bench /
#                Loc-Bench instance-id spelling), plus any extra dataset row files passed with --rows
#                (a JSON list of objects with a `repo` field, e.g. the Loc-Bench V1 560 rows), plus the
#                project tracker's issues and comments (read through `gh api`) when --tracker is given;
#   prose      — exclusions_hand.txt next to this file (SWE-bench Lite/Verified repositories, peer tools and
#                their eval corpora, ripwire itself), which also carries `name:<repo-name>` rows: a repository
#                whose NAME matches is excluded whatever its owner (peer tools re-hosted under a new owner).
#
# Usage: python3 bench/lookback/exclusions.py --out E.txt [--rows rows.json ...] [--tracker owner/name]
import argparse, json, os, re, subprocess, sys

HERE = os.path.dirname( os.path.abspath( __file__ ) )
ROOT = os.path.dirname( os.path.dirname( HERE ) )
sys.path.insert( 0, HERE )
import common

GH_URL_RE = re.compile( r"github\.com[/:]([A-Za-z0-9][A-Za-z0-9-]{0,38})/([A-Za-z0-9_.-]{1,100})" )
INSTANCE_RE = re.compile( r"\b([A-Za-z0-9][A-Za-z0-9-]{0,38})__([A-Za-z0-9_.-]{1,100}?)-\d+\b" )
# github.com/<x>/... paths that are not repositories
NOT_OWNERS = frozenset( ( "sponsors", "orgs", "settings", "apps", "features", "marketplace", "topics", "collections",
                          "login", "about", "pricing", "notifications", "user", "users", "en", "site", "search" ) )


def _norm( owner, name ):
    name = re.sub( r"\.git$", "", name ).rstrip( "." )
    if not name or owner.lower() in NOT_OWNERS:
        return None
    return ( owner + "/" + name ).lower()


def scan_text( text, out, instances=True ):
    for m in GH_URL_RE.finditer( text ):
        r = _norm( m.group( 1 ), m.group( 2 ) )
        if r:
            out.add( r )
    if instances:
        for m in INSTANCE_RE.finditer( text ):
            r = _norm( m.group( 1 ), m.group( 2 ) )
            if r:
                out.add( r )


def scan_tree( root ):
    """The mechanical scan over the tracked files §2 names. Returns (set, scanned file count)."""
    files = subprocess.run( [ "git", "-C", root, "ls-files" ], capture_output=True, text=True, check=True ).stdout.split( "\n" )
    out, n = set(), 0
    for f in sorted( files ):
        low = f.lower()
        if not f:
            continue
        pick = ( low == "docs/evals.md" or low.startswith( "bench/" ) or os.path.basename( low ).startswith( "readme" )
                 or ( low.startswith( "test/" ) and low.endswith( ( ".sh", ".py" ) ) ) )
        if not pick or low.startswith( "bench/lookback/" ):
            continue
        try:
            with open( os.path.join( root, f ), encoding="utf-8", errors="replace" ) as fh:
                scan_text( fh.read(), out )
            n += 1
        except ( IsADirectoryError, FileNotFoundError ):
            continue
    return out, n


def scan_rows( path ):
    with open( path, encoding="utf-8" ) as fh:
        rows = json.load( fh )
    return { r[ "repo" ].lower() for r in rows if isinstance( r, dict ) and "/" in r.get( "repo", "" ) }


def scan_tracker( repo ):
    """Issue bodies and issue comments (pull requests excluded) of the project's tracker."""
    out = set()
    def pages( endpoint ):
        res = subprocess.run( [ "gh", "api", "--paginate", endpoint ], capture_output=True, text=True, check=True ).stdout
        # --paginate concatenates JSON arrays: "][" joins pages
        return json.loads( "[" + res.strip()[ 1:-1 ].replace( "][", "," ) + "]" ) if res.strip() not in ( "", "[]" ) else []
    issues = pages( "repos/%s/issues?state=all&per_page=100" % repo )
    issue_urls = set()
    for it in issues:
        if "pull_request" in it:
            continue
        issue_urls.add( it[ "url" ] )
        scan_text( ( it.get( "title" ) or "" ) + "\n" + ( it.get( "body" ) or "" ), out, instances=False )
    for c in pages( "repos/%s/issues/comments?per_page=100" % repo ):
        if c.get( "issue_url" ) in issue_urls:
            scan_text( c.get( "body" ) or "", out, instances=False )
    return out, len( issue_urls )


def load_hand( path=os.path.join( HERE, "exclusions_hand.txt" ) ):
    repos, names = set(), set()
    with open( path, encoding="utf-8" ) as fh:
        for line in fh:
            line = line.split( "#", 1 )[ 0 ].strip().lower()
            if not line:
                continue
            if line.startswith( "name:" ):
                names.add( line[ 5: ] )
            else:
                repos.add( line )
    return repos, names


def is_excluded( full_name, repos, names ):
    low = full_name.lower()
    return low in repos or low.split( "/", 1 )[ 1 ] in names


def main( argv ):
    ap = argparse.ArgumentParser()
    ap.add_argument( "--out", required=True )
    ap.add_argument( "--rows", action="append", default=[] )
    ap.add_argument( "--tracker" )
    a = ap.parse_args( argv )
    mech, nfiles = scan_tree( ROOT )
    for r in a.rows:
        mech |= scan_rows( r )
    ntracker = 0
    if a.tracker:
        t, ntracker = scan_tracker( a.tracker )
        mech |= t
    hand, names = load_hand()
    allr = sorted( mech | hand )
    with open( a.out, "w", encoding="utf-8" ) as fh:
        for r in allr:
            fh.write( r + "\n" )
        for n in sorted( names ):
            fh.write( "name:" + n + "\n" )
    print( "exclusions: %d repos (%d mechanical from %d files + %d rows files + %d tracker issues, %d hand) + %d name rows; sha256=%s"
           % ( len( allr ), len( mech ), nfiles, len( a.rows ), ntracker, len( hand ), len( names ), common.sha256_file( a.out ) ) )


if __name__ == "__main__":
    main( sys.argv[ 1: ] )
