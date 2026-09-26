#!/usr/bin/env python3
# labels.py — §3's T and windows, and §4.1's bug-fix commit rule: route A (issue-linked), route B
# (Conventional Commits `fix:`), and the keyword rule (sensitivity S1, and PRIOR's rule).
#
# The unit of fixing is a FIRST-PARENT commit c in W_k, judged by its diff against its first parent (the diff
# itself is maphunks.py's job; this module only decides WHICH commits are fixes). Route A needs issue data
# that only the GitHub API holds; `GhLinks` fetches it through `gh api graphql`, batched, and caches every
# answer in a JSON file so a re-run makes no API call and reads byte-identical inputs.
import datetime, json, os, re, subprocess, sys, time

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
import common

MERGE_PR_RE = re.compile( r"^Merge pull request #(\d+) from \S+" )


# ── T and windows ───────────────────────────────────────────────────────────────────────────────────────
def iso_to_epoch( iso ):
    return int( datetime.datetime.strptime( iso, "%Y-%m-%dT%H:%M:%SZ" ).replace( tzinfo=datetime.timezone.utc ).timestamp() )


def first_parent_chain( repo, ref ):
    """[(sha, committer_epoch)] along ref's first-parent chain, NEWEST first."""
    out = common.git( repo, "rev-list", "--first-parent", "--format=%H %ct", "--no-commit-header", ref )
    rows = []
    for line in out.split( "\n" ):
        if line:
            sha, ct = line.split()
            rows.append( ( sha, int( ct ) ) )
    return rows


def resolve_t( chain, cutoff_epoch ):
    """§3: the last first-parent commit with committer date <= cutoff (the first such one walking back)."""
    for sha, ct in chain:
        if ct <= cutoff_epoch:
            return sha
    return None


def window_commits( chain, t_sha, lo_epoch, hi_epoch ):
    """First-parent commits AFTER T on the chain (oldest first) whose committer date is in (lo, hi]; also
    returns the full first-parent path from T (exclusive) to the last window commit (inclusive), which the
    rename tracker walks."""
    idx = { sha: i for i, ( sha, _ ) in enumerate( chain ) }
    if t_sha not in idx:
        return [], []
    after_t = list( reversed( chain[ :idx[ t_sha ] ] ) )            # oldest first
    inwin = [ sha for sha, ct in after_t if lo_epoch < ct <= hi_epoch ]
    if not inwin:
        return [], []
    last = max( i for i, ( sha, _ ) in enumerate( after_t ) if sha == inwin[ -1 ] )
    return inwin, [ sha for sha, _ in after_t[ :last + 1 ] ]


# ── commit text ─────────────────────────────────────────────────────────────────────────────────────────
def commit_texts( repo, shas ):
    """sha -> (subject, full message, parent count). One git call for the whole list."""
    if not shas:
        return {}
    out = common.git( repo, "show", "-s", "--format=%x00%H%x01%P%x01%B", "--no-color", *shas )
    res = {}
    for rec in out.split( "\x00" )[ 1: ]:
        sha, parents, body = rec.split( "\x01", 2 )
        body = body.rstrip( "\n" )
        res[ sha ] = ( body.split( "\n", 1 )[ 0 ], body, len( parents.split() ) )
    return res


def pr_title_subject( subject, body, nparents ):
    """§4.1 route B: for a merge, the PR title (the first non-empty body line after a GitHub merge subject)."""
    if nparents > 1 and MERGE_PR_RE.match( subject ):
        for line in body.split( "\n" )[ 1: ]:
            if line.strip():
                return line.strip()
    return subject


def is_route_b( subject ):
    m = common.ROUTE_B_RE.match( subject )
    if not m:
        return False
    scope = ( m.group( 1 ) or "" )[ 1:-1 ].strip().lower()
    return scope not in common.ROUTE_B_SCOPE_VETO


def is_keyword_fix( subject ):
    return bool( common.KEYWORD_RE.search( subject ) ) and not common.KEYWORD_VETO_RE.search( subject )


def is_bug_label( label ):
    words = set( re.sub( r"[_:/\-]", " ", label.lower() ).split() )
    return bool( words & common.BUG_LABEL_WORDS ) and not ( words & common.BUG_LABEL_VETO )


def message_issue_refs( message, full_name ):
    """Issue numbers c's message links: `(close[sd]?|fix(e[sd])?|resolve[sd]?) #N`, or the issue's URL."""
    refs = { int( m.group( 1 ) ) for m in common.LINK_RE.finditer( message ) }
    url = re.compile( r"https?://github\.com/%s/issues/(\d+)\b" % re.escape( full_name ), re.I )
    refs |= { int( m.group( 1 ) ) for m in url.finditer( message ) }
    return refs


def merged_messages( repo, sha, nparents ):
    """Messages of every commit a merge brings in (c^1..c), for the route-A message link."""
    if nparents < 2:
        return []
    out = common.git( repo, "log", "--format=%x00%H%x01%B", "%s^1..%s" % ( sha, sha ) )
    recs = [ r.split( "\x01", 1 ) for r in out.split( "\x00" )[ 1: ] ]
    return sorted( m.strip() for h, m in recs if h != sha and m.strip() )           # c's own message is read by the caller


def merged_messages_batch( repo, t_sha, last_sha, first_parent_path ):
    """{merge sha: [messages of the commits it brings in (c^1..c)]} for every merge on the first-parent path,
    from ONE `git log T..last`: a commit off the first-parent chain belongs to the earliest first-parent merge
    whose second-parent side reaches it (walked oldest merge first), which is exactly c^1..c."""
    out = common.git( repo, "log", "--format=%x00%H%x01%P%x01%B", "%s..%s" % ( t_sha, last_sha ) )
    parents, msg = {}, {}
    for rec in out.split( "\x00" )[ 1: ]:
        sha, ps, body = rec.split( "\x01", 2 )
        parents[ sha ] = ps.split()
        msg[ sha ] = body
    seen = set( first_parent_path )
    res = {}
    for c in first_parent_path:                              # oldest first
        ps = parents.get( c, [] )
        if len( ps ) < 2:
            continue
        brought, stack = [], list( ps[ 1: ] )
        while stack:
            x = stack.pop()
            if x in seen or x not in parents:                 # already attributed, or an ancestor of T
                continue
            seen.add( x )
            brought.append( x )
            stack.extend( parents[ x ] )
        res[ c ] = [ msg[ x ].strip() for x in sorted( brought ) if msg[ x ].strip() ]
    return res


# ── route A: the GitHub side ────────────────────────────────────────────────────────────────────────────
class GhLinks:
    """PR closing references and issue labels, fetched once and cached (path) as JSON."""

    def __init__( self, full_name, cache_path, offline=False ):
        self.full_name, self.path, self.offline = full_name, cache_path, offline
        self.data = { "commit_prs": {}, "issues": {} }
        if cache_path and os.path.exists( cache_path ):
            with open( cache_path ) as fh:
                self.data = json.load( fh )
        self.calls = 0

    def save( self ):
        if self.path:
            tmp = self.path + ".tmp"
            with open( tmp, "w" ) as fh:
                json.dump( self.data, fh, indent=0, sort_keys=True )
            os.replace( tmp, self.path )

    def _gql( self, q ):
        attempt = 0
        while attempt < 6:
            p = subprocess.run( [ "gh", "api", "graphql", "-f", "query=" + q ], capture_output=True, text=True )
            self.calls += 1
            if p.returncode == 0:
                return json.loads( p.stdout )
            if "rate limit" in ( p.stderr + p.stdout ).lower():      # a budget wait, not a failed attempt
                time.sleep( self._reset_wait() )
                continue
            attempt += 1
            # partial data with per-field errors still returns JSON on stdout
            try:
                j = json.loads( p.stdout )
                if j.get( "data" ):
                    return j
            except ValueError:
                pass
            time.sleep( 20 * attempt )
        raise RuntimeError( "gh graphql failed: " + p.stderr[ :300 ] )

    @staticmethod
    def _reset_wait():
        try:
            p = subprocess.run( [ "gh", "api", "graphql", "-f", "query=query{ rateLimit{ remaining resetAt } }" ], capture_output=True, text=True )
            r = json.loads( p.stdout )[ "data" ][ "rateLimit" ]
            return max( 5, iso_to_epoch( r[ "resetAt" ] ) - int( time.time() ) + 10 ) if r[ "remaining" ] < 50 else 30
        except ( ValueError, KeyError, TypeError ):
            return 120

    def fetch_commits( self, shas ):
        todo = sorted( s for s in shas if s not in self.data[ "commit_prs" ] )
        if self.offline:
            return
        o, n = self.full_name.split( "/", 1 )
        for i in range( 0, len( todo ), 25 ):
            part = todo[ i:i + 25 ]
            fields = " ".join(
                'c%d: object(oid:"%s"){ ... on Commit { associatedPullRequests(first:5){ nodes{ number closingIssuesReferences(first:25){ nodes{ number '
                'repository{ nameWithOwner } labels(first:30){ nodes{ name } } } } } } } }' % ( j, s ) for j, s in enumerate( part ) )
            res = self._gql( "query{ repository(owner:%s, name:%s){ %s } }" % ( json.dumps( o ), json.dumps( n ), fields ) )
            repo = ( res.get( "data" ) or {} ).get( "repository" ) or {}
            for j, s in enumerate( part ):
                node = repo.get( "c%d" % j ) or {}
                prs = []
                for pr in ( ( node.get( "associatedPullRequests" ) or {} ).get( "nodes" ) or [] ):
                    closes = []
                    for iss in ( pr.get( "closingIssuesReferences" ) or {} ).get( "nodes" ) or []:
                        if ( iss.get( "repository" ) or {} ).get( "nameWithOwner", "" ).lower() != self.full_name.lower():
                            continue
                        closes.append( iss[ "number" ] )
                        self.data[ "issues" ][ str( iss[ "number" ] ) ] = sorted( l[ "name" ] for l in iss[ "labels" ][ "nodes" ] )
                    prs.append( dict( number=pr[ "number" ], closes=sorted( closes ) ) )
                self.data[ "commit_prs" ][ s ] = prs
            self.save()

    def fetch_issues( self, numbers ):
        todo = sorted( n for n in numbers if str( n ) not in self.data[ "issues" ] )
        if self.offline:
            return
        o, n = self.full_name.split( "/", 1 )
        for i in range( 0, len( todo ), 50 ):
            part = todo[ i:i + 50 ]
            fields = " ".join( 'i%d: issueOrPullRequest(number:%d){ __typename ... on Issue { labels(first:30){ nodes{ name } } } }' % ( k, num )
                               for k, num in enumerate( part ) )
            res = self._gql( "query{ repository(owner:%s, name:%s){ %s } }" % ( json.dumps( o ), json.dumps( n ), fields ) )
            repo = ( res.get( "data" ) or {} ).get( "repository" ) or {}
            for k, num in enumerate( part ):
                node = repo.get( "i%d" % k )
                if node and node.get( "__typename" ) == "Issue":
                    self.data[ "issues" ][ str( num ) ] = sorted( l[ "name" ] for l in node[ "labels" ][ "nodes" ] )
                else:
                    self.data[ "issues" ][ str( num ) ] = None      # a PR number, or no such issue
            self.save()

    def repo_labels( self ):
        """The repository's label set, read before any issue is (§4.1); cached."""
        if "repo_labels" in self.data or self.offline:
            return self.data.get( "repo_labels", [] )
        o, n = self.full_name.split( "/", 1 )
        names, after = [], None
        while True:
            res = self._gql( "query{ repository(owner:%s, name:%s){ labels(first:100%s){ nodes{ name } pageInfo{ hasNextPage endCursor } } } }"
                             % ( json.dumps( o ), json.dumps( n ), ( ", after:%s" % json.dumps( after ) ) if after else "" ) )
            lab = res[ "data" ][ "repository" ][ "labels" ]
            names += [ x[ "name" ] for x in lab[ "nodes" ] ]
            if not lab[ "pageInfo" ][ "hasNextPage" ]:
                break
            after = lab[ "pageInfo" ][ "endCursor" ]
        self.data[ "repo_labels" ] = sorted( names )
        self.save()
        return self.data[ "repo_labels" ]

    def linked_issues( self, sha, message_refs ):
        prs = self.data[ "commit_prs" ].get( sha ) or []
        return sorted( set( message_refs ) | { i for pr in prs for i in pr[ "closes" ] } )

    def issue_is_bug( self, number, bug_labels ):
        labels = self.data[ "issues" ].get( str( number ) )
        return bool( labels ) and any( l in bug_labels for l in labels )


# ── the per-window label table ──────────────────────────────────────────────────────────────────────────
def label_commits( repo, full_name, shas, repo_labels, links=None, merged=None ):
    """sha -> dict(route_a, route_b, keyword, subject). route_a is None when no GhLinks is given. `merged` is
    merged_messages_batch()'s map; without it each merge's messages are read one git call at a time."""
    texts = commit_texts( repo, shas )
    bug_labels = frozenset( l for l in repo_labels if is_bug_label( l ) )
    refs = {}
    for s in shas:
        subject, body, np_ = texts[ s ]
        r = message_issue_refs( body, full_name )
        for m in ( merged.get( s, [] ) if merged is not None else merged_messages( repo, s, np_ ) ):
            r |= message_issue_refs( m, full_name )
        refs[ s ] = r
    if links is not None:
        links.fetch_commits( shas )
        links.fetch_issues( sorted( { n for r in refs.values() for n in r } ) )
    out = {}
    for s in shas:
        subject, body, np_ = texts[ s ]
        title = pr_title_subject( subject, body, np_ )
        ra = None
        if links is not None:
            ra = any( links.issue_is_bug( n, bug_labels ) for n in links.linked_issues( s, refs[ s ] ) )
        out[ s ] = dict( subject=title, route_a=ra, route_b=is_route_b( title ), keyword=is_keyword_fix( title ) )
    return out
