#!/usr/bin/env python3
# selectrepos.py — §2's metadata screen: candidate search, eligibility columns, the per-stratum eligibility
# census, and the salted hash order. Reads NO clone; every fact comes from the GitHub API through `gh api`.
#
# (Named selectrepos.py, not the draft's select.py: a module called `select` next to a script shadows the
# stdlib `select` module that `subprocess` imports on POSIX, and the whole harness shells out to git.)
#
# Stages (a funnel; each stage runs only on candidates the earlier ones kept, and every verdict is cached
# per repository so an interrupted screen resumes where it stopped):
#   0  search fields: stars / created / archived / fork (the query), template, mirror, OSI licence, ≤ 2 GB,
#      not in E
#   1  GraphQL: ≥ 3,000 default-branch commits, a commit on or before 2019-12-31, ≥ 1 commit in each window
#   2  GraphQL: ≥ 20 distinct non-bot commit authors in 2024–2025 (paged, stops at the 20th)
#   3  REST git tree at the default-branch head: 100–20,000 product-source files (§1 path rule; the
#      generated-marker half needs blobs and is applied after clone — so this count is an UPPER bound)
#   4  label routes, BOTH evaluated (the census reports each): route A (≥ 50 bug-labelled issues closed in
#      2025, ≥ 30% closed by a PR or commit) and route B (≥ 70% of 2025 non-merge commit subjects parse as
#      Conventional Commits)
#
# Usage:
#   python3 selectrepos.py census --cache DIR --exclusions E.txt [--strata cpp,python,...]
#       -> DIR/census_<stratum>.json (every candidate with its columns) and a printed per-stratum table
#   python3 selectrepos.py order --cache DIR --salt SALT      (prints the eligible pool in SALT's hash order)
import argparse, datetime, json, os, re, subprocess, sys, time

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
import common, exclusions

BOT_RE = re.compile( r"(\[bot\]$|^dependabot|^renovate|^github-actions|^greenkeeper|^snyk-bot|bot@|noreply@github\.com$)", re.I )


# ── the API layer ───────────────────────────────────────────────────────────────────────────────────────
class Api:
    def __init__( self, log ):
        self.log, self.calls = log, { "rest": 0, "search": 0, "graphql": 0 }
        self.last_search = 0.0

    def _run( self, args, kind ):
        attempt = 0
        while attempt < 8:
            p = subprocess.run( [ "gh", "api", *args ], capture_output=True, text=True )
            self.calls[ kind ] += 1
            if p.returncode == 0:
                return json.loads( p.stdout ) if p.stdout.strip() else None
            err = ( p.stderr + p.stdout )[ :600 ]
            if "Not Found" in err or "HTTP 404" in err or "HTTP 409" in err or "Git Repository is empty" in err:
                return { "__error__": "notfound", "detail": err[ :200 ] }
            if "HTTP 451" in err:
                return { "__error__": "blocked", "detail": err[ :200 ] }
            if "rate limit" in err.lower() or "HTTP 429" in err:
                # a budget wait is not a failed attempt: sleep to the bucket's reset and try again
                wait = self._reset_wait( kind )
                self.log( "rate limit (%s): sleeping %ds" % ( kind, wait ) )
                time.sleep( wait )
                continue
            attempt += 1
            wait = 30 * attempt
            self.log( "api retry %d (%s) in %ds: %s" % ( attempt, kind, wait, err.replace( "\n", " " )[ :200 ] ) )
            time.sleep( wait )
        return { "__error__": "failed", "detail": err[ :200 ] }

    def _reset_wait( self, kind ):
        """Seconds to the bucket's reset. GraphQL's own rateLimit object is authoritative for GraphQL (the REST
        /rate_limit view of that bucket disagreed with it during the census)."""
        try:
            if kind == "graphql":
                p = subprocess.run( [ "gh", "api", "graphql", "-f", "query=query{ rateLimit{ remaining resetAt } }" ], capture_output=True, text=True )
                r = json.loads( p.stdout )[ "data" ][ "rateLimit" ]
                reset = datetime.datetime.strptime( r[ "resetAt" ], "%Y-%m-%dT%H:%M:%SZ" ).replace( tzinfo=datetime.timezone.utc ).timestamp()
                return max( 5, int( reset - time.time() ) + 10 ) if r[ "remaining" ] < 50 else 30
            p = subprocess.run( [ "gh", "api", "rate_limit" ], capture_output=True, text=True )
            r = json.loads( p.stdout )[ "resources" ][ { "rest": "core", "search": "search" }[ kind ] ]
            return max( 5, int( r[ "reset" ] - time.time() ) + 5 ) if r[ "remaining" ] < 5 else 30
        except ( ValueError, KeyError, TypeError ):
            return 120

    def rest( self, endpoint ):
        return self._run( [ "-X", "GET", endpoint ], "rest" )

    def search( self, q, page ):
        gap = time.time() - self.last_search
        if gap < 2.2:                         # 30 search requests per minute
            time.sleep( 2.2 - gap )
        self.last_search = time.time()
        return self._run( [ "-X", "GET", "search/repositories", "-f", "q=" + q, "-f", "sort=stars", "-f", "order=desc",
                            "-f", "per_page=100", "-f", "page=%d" % page ], "search" )

    def graphql( self, query ):
        res = self._run( [ "graphql", "-f", "query=" + query ], "graphql" )
        rl = ( ( res or {} ).get( "data" ) or {} ).get( "rateLimit" ) if isinstance( res, dict ) else None
        if rl and rl.get( "remaining", 5000 ) < 200:
            self.log( "graphql budget low (%s); sleeping to reset" % rl )
            time.sleep( 60 * 15 )
        return res


def _q( s ):
    return json.dumps( s )


# ── stage 0: candidates ─────────────────────────────────────────────────────────────────────────────────
def search_stratum( api, stratum ):
    rows = {}
    for lang in common.STRATA[ stratum ]:
        q = 'language:"%s" stars:>=%d created:<=%s archived:false fork:false' % ( lang, common.MIN_STARS, common.CREATED_ON_OR_BEFORE )
        for page in range( 1, 11 ):
            res = api.search( q, page )
            items = ( res or {} ).get( "items", [] ) if isinstance( res, dict ) else []
            for it in items:
                rows.setdefault( it[ "full_name" ], dict(
                    full_name=it[ "full_name" ], stars=it[ "stargazers_count" ], created_at=it[ "created_at" ],
                    archived=it[ "archived" ], fork=it[ "fork" ], is_template=it.get( "is_template", False ),
                    mirror_url=it.get( "mirror_url" ), license=( it.get( "license" ) or {} ).get( "spdx_id" ),
                    size_kb=it[ "size" ], default_branch=it[ "default_branch" ], language=it.get( "language" ),
                    search_language=lang ) )
            if len( items ) < 100:
                break
    # a pooled stratum keeps its top 1,000 by stars (ties by name), the same cap a single-language one has
    ranked = sorted( rows.values(), key=lambda r: ( -r[ "stars" ], r[ "full_name" ].lower() ) )
    return ranked[ :1000 ]


def stage0( c, excl_repos, excl_names ):
    reasons = []
    if c[ "archived" ] or c[ "fork" ]:
        reasons.append( "archived_or_fork" )
    if c[ "is_template" ]:
        reasons.append( "template" )
    if c[ "mirror_url" ]:
        reasons.append( "mirror" )
    if c[ "license" ] not in common.OSI_SPDX:
        reasons.append( "licence" )
    if c[ "size_kb" ] > common.MAX_REPO_KB:
        reasons.append( "over_2gb" )
    if exclusions.is_excluded( c[ "full_name" ], excl_repos, excl_names ):
        reasons.append( "in_E" )
    return reasons


# ── stage 1: history counts, batched ────────────────────────────────────────────────────────────────────
def _hist_fields():
    w = [ "w%d: history(first:1, since:%s, until:%s){totalCount}" % ( k, _q( _after( lo ) ), _q( hi ) ) for k, lo, hi in common.WINDOWS ]
    return ( "all: history(first:1){totalCount} pre: history(first:1, until:%s){totalCount} " % _q( common.FIRST_COMMIT_ON_OR_BEFORE )
             + " ".join( w ) )


def _after( iso_2359 ):
    """(D, …] -> since = the next second after D 23:59:59Z."""
    day = iso_2359[ :10 ]
    y, m, d = ( int( x ) for x in day.split( "-" ) )
    nxt = datetime.date( y, m, d ) + datetime.timedelta( days=1 )
    return nxt.isoformat() + "T00:00:00Z"


def stage1_batch( api, names ):
    parts = []
    for i, n in enumerate( names ):
        o, r = n.split( "/", 1 )
        parts.append( 'r%d: repository(owner:%s, name:%s){ nameWithOwner isMirror isTemplate diskUsage licenseInfo{spdxId} '
                      'labels(first:100){ totalCount nodes{ name } } '
                      'defaultBranchRef{ name target{ ... on Commit { oid %s } } } }' % ( i, _q( o ), _q( r ), _hist_fields() ) )
    res = api.graphql( "query{ rateLimit{ remaining resetAt cost } " + " ".join( parts ) + " }" )
    out = {}
    data = ( res or {} ).get( "data" ) or {} if isinstance( res, dict ) else {}
    for i, n in enumerate( names ):
        out[ n ] = data.get( "r%d" % i )
    return out, res


def stage1_eval( node ):
    if not node or not node.get( "defaultBranchRef" ) or not node[ "defaultBranchRef" ].get( "target" ):
        return None, [ "no_default_branch" ]
    t = node[ "defaultBranchRef" ][ "target" ]
    cols = dict( commits=t[ "all" ][ "totalCount" ], pre2020=t[ "pre" ][ "totalCount" ], head=t[ "oid" ],
                 default_branch=node[ "defaultBranchRef" ][ "name" ],
                 windows=[ t[ "w%d" % k ][ "totalCount" ] for k, _, _ in common.WINDOWS ],
                 labels=[ l[ "name" ] for l in node[ "labels" ][ "nodes" ] ], labels_total=node[ "labels" ][ "totalCount" ] )
    reasons = []
    if cols[ "commits" ] < common.MIN_COMMITS:
        reasons.append( "commits" )
    if cols[ "pre2020" ] < 1:
        reasons.append( "age" )
    if min( cols[ "windows" ] ) < 1:
        reasons.append( "window_activity" )
    return cols, reasons


def more_labels( api, name ):
    o, r = name.split( "/", 1 )
    labels, after = [], None
    while True:
        res = api.graphql( "query{ repository(owner:%s, name:%s){ labels(first:100%s){ nodes{name} pageInfo{hasNextPage endCursor} } } }"
                           % ( _q( o ), _q( r ), ( ", after:%s" % _q( after ) ) if after else "" ) )
        lab = res[ "data" ][ "repository" ][ "labels" ]
        labels += [ n[ "name" ] for n in lab[ "nodes" ] ]
        if not lab[ "pageInfo" ][ "hasNextPage" ]:
            return labels
        after = lab[ "pageInfo" ][ "endCursor" ]


# ── stage 2: distinct authors 2024–2025 ─────────────────────────────────────────────────────────────────
def author_key( node ):
    a = node.get( "author" ) or {}
    login = ( a.get( "user" ) or {} ).get( "login" )
    email = ( a.get( "email" ) or "" ).lower()
    name = a.get( "name" ) or ""
    for s in ( login or "", email, name ):
        if s and BOT_RE.search( s ):
            return None
    return ( "u:" + login.lower() ) if login else ( "e:" + email ) if email else None


def stage2( api, name ):
    o, r = name.split( "/", 1 )
    seen, after, pages = set(), None, 0
    while True:
        q = ( "query{ repository(owner:%s, name:%s){ defaultBranchRef{ target{ ... on Commit { history(first:100, since:%s, until:%s%s)"
              "{ pageInfo{hasNextPage endCursor} nodes{ author{ email name user{ login } } } } } } } } }"
              % ( _q( o ), _q( r ), _q( common.AUTHORS_SINCE ), _q( common.AUTHORS_UNTIL ), ( ", after:%s" % _q( after ) ) if after else "" ) )
        res = api.graphql( q )
        pages += 1
        try:
            h = res[ "data" ][ "repository" ][ "defaultBranchRef" ][ "target" ][ "history" ]
        except ( KeyError, TypeError ):
            return None, pages
        for n in h[ "nodes" ]:
            k = author_key( n )
            if k:
                seen.add( k )
        if len( seen ) >= common.MIN_AUTHORS_2024_2025 or not h[ "pageInfo" ][ "hasNextPage" ]:
            return len( seen ), pages
        after = h[ "pageInfo" ][ "endCursor" ]


# ── stage 3: product-source file count at head ──────────────────────────────────────────────────────────
def stage3( api, name, head, stratum ):
    res = api.rest( "repos/%s/git/trees/%s?recursive=1" % ( name, head ) )
    if not isinstance( res, dict ) or "__error__" in res:
        return None, None
    n = sum( 1 for e in res.get( "tree", [] ) if e.get( "type" ) == "blob" and common.is_product_path( e[ "path" ], stratum ) )
    return n, bool( res.get( "truncated" ) )


# ── stage 4: label routes ───────────────────────────────────────────────────────────────────────────────
def is_bug_label( label ):
    words = set( re.sub( r"[_:/\-]", " ", label.lower() ).split() )
    return bool( words & common.BUG_LABEL_WORDS ) and not ( words & common.BUG_LABEL_VETO )


def route_a_decide( counts, seen, linked ):
    """Route A's verdict from partial data, or None while undecided. counts: {label: issueCount}; seen: distinct
    issues read so far; linked: how many of them a PR or commit closed. The union of the label sets lies in
    [max(max(counts), seen), sum(counts)], so the verdict is EXACT whenever it is returned early."""
    upper = sum( counts.values() )
    lower = max( [ seen ] + list( counts.values() ) )
    if upper < common.ROUTE_A_MIN_BUG_ISSUES_2025:
        return False
    if lower >= common.ROUTE_A_MIN_BUG_ISSUES_2025 and linked >= common.ROUTE_A_MIN_LINKED_FRACTION * upper:
        return True
    if linked + ( upper - seen ) < common.ROUTE_A_MIN_LINKED_FRACTION * upper:
        return False
    return None


def route_a( api, name, bug_labels ):
    """Union over the matched labels of issues closed in 2025; closer type of each issue's last ClosedEvent.
    Pages round-robin over the labels and stops as soon as route_a_decide() settles the verdict."""
    issues, counts, cursors, got = {}, {}, {}, {}
    capped = False
    def page( lab ):
        after = cursors.get( lab )
        q = ( "query{ search(type:ISSUE, first:100%s, query:%s){ issueCount pageInfo{hasNextPage endCursor} nodes{ ... on Issue { number "
              "timelineItems(itemTypes:[CLOSED_EVENT], last:1){ nodes{ ... on ClosedEvent { closer{ __typename } } } } } } } }"
              % ( ( ", after:%s" % _q( after ) ) if after else "",
                  _q( 'repo:%s is:issue is:closed closed:2025-01-01..2025-12-31 label:"%s"' % ( name, lab.replace( '"', '' ) ) ) ) )
        res = api.graphql( q )
        s = res[ "data" ][ "search" ]
        counts[ lab ] = s[ "issueCount" ]
        for n in s[ "nodes" ]:
            if not n:
                continue
            ev = n[ "timelineItems" ][ "nodes" ]
            issues[ n[ "number" ] ] = ( ( ev[ -1 ] or {} ).get( "closer" ) or {} ).get( "__typename" ) if ev else None
            got[ lab ] = got.get( lab, 0 ) + 1
        cursors[ lab ] = s[ "pageInfo" ][ "endCursor" ] if s[ "pageInfo" ][ "hasNextPage" ] and got[ lab ] < 1000 else None
        return s[ "pageInfo" ][ "hasNextPage" ]
    try:
        live = []
        for lab in sorted( bug_labels ):
            if page( lab ) and cursors[ lab ]:
                live.append( lab )
            elif counts[ lab ] > 1000:
                capped = True
        decided = None
        while True:
            linked = sum( 1 for v in issues.values() if v in ( "PullRequest", "Commit" ) )
            decided = route_a_decide( counts, len( issues ), linked )
            if decided is not None or not live:
                break
            lab = live.pop( 0 )
            if page( lab ) and cursors[ lab ]:
                live.append( lab )
            elif counts[ lab ] > got.get( lab, 0 ):
                capped = True
    except ( KeyError, TypeError ):
        return None
    linked = sum( 1 for v in issues.values() if v in ( "PullRequest", "Commit" ) )
    if decided is None:                                    # every page read (or the 1,000 cap reached)
        decided = len( issues ) >= common.ROUTE_A_MIN_BUG_ISSUES_2025 and linked >= common.ROUTE_A_MIN_LINKED_FRACTION * len( issues )
    return dict( bug_issues_2025=len( issues ), issue_count_upper=sum( counts.values() ), issue_count_lower=max( [ len( issues ) ] + list( counts.values() ) ),
                 linked=linked, linked_frac=( linked / len( issues ) ) if issues else 0.0, capped=capped, ok=bool( decided ),
                 complete=not any( cursors.get( l ) for l in counts ) )


def route_b( api, name, total_hint ):
    """Fraction of 2025 non-merge commit subjects that parse as Conventional Commits; stops once decided."""
    o, r = name.split( "/", 1 )
    cc = non = 0
    after = None
    while True:
        q = ( "query{ repository(owner:%s, name:%s){ defaultBranchRef{ target{ ... on Commit { history(first:100, since:%s, until:%s%s)"
              "{ totalCount pageInfo{hasNextPage endCursor} nodes{ messageHeadline parents(first:1){ totalCount } } } } } } } }"
              % ( _q( o ), _q( r ), _q( common.YEAR_2025[ 0 ] ), _q( common.YEAR_2025[ 1 ] ), ( ", after:%s" % _q( after ) ) if after else "" ) )
        res = api.graphql( q )
        try:
            h = res[ "data" ][ "repository" ][ "defaultBranchRef" ][ "target" ][ "history" ]
        except ( KeyError, TypeError ):
            return None
        total = h[ "totalCount" ]
        for n in h[ "nodes" ]:
            if n[ "parents" ][ "totalCount" ] > 1:
                continue
            if common.CONVENTIONAL_RE.match( n[ "messageHeadline" ] or "" ):
                cc += 1
            else:
                non += 1
        # decided early: even if every unseen commit went the other way the verdict cannot change
        if non > ( 1 - common.ROUTE_B_MIN_CC_FRACTION ) * total:
            return dict( cc=cc, non_cc=non, total_2025=total, cc_frac_seen=cc / max( 1, cc + non ), decided="early_fail" )
        if cc >= common.ROUTE_B_MIN_CC_FRACTION * total:          # the non-merge denominator is at most total
            return dict( cc=cc, non_cc=non, total_2025=total, cc_frac_seen=cc / max( 1, cc + non ), decided="early_pass" )
        if not h[ "pageInfo" ][ "hasNextPage" ]:
            frac = cc / max( 1, cc + non )
            return dict( cc=cc, non_cc=non, total_2025=total, cc_frac_seen=frac, decided="complete" )
        after = h[ "pageInfo" ][ "endCursor" ]


# ── the census driver ───────────────────────────────────────────────────────────────────────────────────
def census( a ):
    os.makedirs( a.cache, exist_ok=True )
    logf = open( os.path.join( a.cache, "census.log" ), "a" )
    def log( msg ):
        logf.write( time.strftime( "%H:%M:%S " ) + msg + "\n" )
        logf.flush()
    api = Api( log )
    excl_repos, excl_names = set(), set()
    with open( a.exclusions ) as fh:
        for line in fh:
            line = line.strip()
            if line.startswith( "name:" ):
                excl_names.add( line[ 5: ] )
            elif line:
                excl_repos.add( line )
    strata = a.strata.split( "," ) if a.strata else list( common.STRATUM_ORDER )
    for st in strata:
        state_path = os.path.join( a.cache, "census_%s.json" % st )
        S = json.load( open( state_path ) ) if os.path.exists( state_path ) else {}
        def save():
            tmp = state_path + ".tmp"
            with open( tmp, "w" ) as fh:
                json.dump( S, fh, indent=1, sort_keys=True )
            os.replace( tmp, state_path )
        if "candidates" not in S:
            S[ "candidates" ] = { c[ "full_name" ]: c for c in search_stratum( api, st ) }
            log( "%s: %d candidates" % ( st, len( S[ "candidates" ] ) ) )
            save()
        C = S[ "candidates" ]
        # stage 0
        for n, c in C.items():
            if "s0" not in c:
                c[ "s0" ] = stage0( c, excl_repos, excl_names )
        save()
        # stage 1, batches of 10
        todo = sorted( ( n for n, c in C.items() if not c[ "s0" ] and "s1" not in c ), key=_pilot_order )
        for i in range( 0, len( todo ), 10 ):
            batch = todo[ i:i + 10 ]
            got, raw = stage1_batch( api, batch )
            for n in batch:
                node, answered = got.get( n ), isinstance( raw, dict ) and raw.get( "data" ) is not None
                if node is None and len( batch ) > 1:
                    g1, raw1 = stage1_batch( api, [ n ] )
                    node, answered = g1.get( n ), isinstance( raw1, dict ) and raw1.get( "data" ) is not None
                if node is None and not answered:
                    log( "%s stage1 %s: no answer, left uncached" % ( st, n ) )
                    continue
                cols, reasons = stage1_eval( node )
                if cols and node and node.get( "labels" ) and node[ "labels" ][ "totalCount" ] > 100:
                    cols[ "labels" ] = more_labels( api, n )
                C[ n ][ "s1" ] = dict( cols=cols, reasons=reasons )
            log( "%s stage1 %d/%d calls=%s" % ( st, min( i + 10, len( todo ) ), len( todo ), api.calls ) )
            save()
        # stage 2
        for n in sorted( ( n for n, c in C.items() if not c[ "s0" ] and c.get( "s1" ) and not c[ "s1" ][ "reasons" ] and "s2" not in c ), key=_pilot_order ):
            k, pages = stage2( api, n )
            if k is None:
                log( "%s stage2 %s: no answer, left uncached" % ( st, n ) )
                continue
            C[ n ][ "s2" ] = dict( authors=k, pages=pages, reasons=[] if ( k or 0 ) >= common.MIN_AUTHORS_2024_2025 else [ "authors" ] )
            save()
        log( "%s stage2 done calls=%s" % ( st, api.calls ) )
        # stage 3
        for n in sorted( ( n for n, c in C.items() if c.get( "s2" ) and not c[ "s2" ][ "reasons" ] and "s3" not in c ), key=_pilot_order ):
            cnt, trunc = stage3( api, n, C[ n ][ "s1" ][ "cols" ][ "head" ], st )
            rs = []
            if cnt is None:
                log( "%s stage3 %s: no answer, left uncached" % ( st, n ) )
                continue
            elif cnt < common.MIN_PRODUCT_FILES:
                rs = [ "too_few_files" ]
            elif cnt > common.MAX_PRODUCT_FILES:
                rs = [ "too_many_files" ]
            C[ n ][ "s3" ] = dict( product_files=cnt, truncated=trunc, reasons=rs )
            save()
        log( "%s stage3 done calls=%s" % ( st, api.calls ) )
        # stage 4
        for n in sorted( ( n for n, c in C.items() if c.get( "s3" ) and not c[ "s3" ][ "reasons" ] and "s4" not in c ), key=_pilot_order ):
            labels = C[ n ][ "s1" ][ "cols" ][ "labels" ]
            bug = sorted( l for l in labels if is_bug_label( l ) )
            ra = route_a( api, n, bug ) if bug else dict( bug_issues_2025=0, linked=0, linked_frac=0.0, capped=False )
            rb = route_b( api, n, C[ n ][ "s1" ][ "cols" ][ "windows" ] )
            if ra is None or rb is None:
                log( "%s stage4 %s: no answer, left uncached" % ( st, n ) )
                continue
            a_ok = bool( ra ) and ra.get( "ok", ra[ "bug_issues_2025" ] >= common.ROUTE_A_MIN_BUG_ISSUES_2025 and ra[ "linked_frac" ] >= common.ROUTE_A_MIN_LINKED_FRACTION )
            b_ok = bool( rb ) and ( rb[ "decided" ] == "early_pass" or ( rb[ "decided" ] == "complete" and rb[ "cc_frac_seen" ] >= common.ROUTE_B_MIN_CC_FRACTION ) )
            C[ n ][ "s4" ] = dict( bug_labels=bug, route_a=ra, route_b=rb, a_ok=a_ok, b_ok=b_ok,
                                   route=( "A" if a_ok else "B" if b_ok else None ) )
            save()
        log( "%s stage4 done calls=%s" % ( st, api.calls ) )
        save()
    print_table( load_state( a.cache ) )


def load_state( cache ):
    state = { "strata": {} }
    for st in common.STRATUM_ORDER:
        p = os.path.join( cache, "census_%s.json" % st )
        if os.path.exists( p ):
            state[ "strata" ][ st ] = json.load( open( p ) )
    return state


def _pilot_order( name ):
    return common.salted_rank( common.SD_PILOT_SALT, name )


def resolved( c ):
    """True once a candidate's eligibility is final (failed some stage, or all four stages done)."""
    if c.get( "s0" ):
        return True
    for st in ( "s1", "s2", "s3" ):
        if st not in c:
            return False
        if c[ st ][ "reasons" ]:
            return True
    return "s4" in c


def sd_pilot_picks( state, k=3 ):
    """The logged SD-pilot rule: all eligible repositories across strata in SD_PILOT_SALT hash order, one per
    stratum, the first k. Returns (picks, complete): complete is False while an unresolved candidate sits
    ahead of the k-th pick (the walk cannot be finished yet)."""
    allc = sorted( ( _pilot_order( n ), st, n, c ) for st, S in state[ "strata" ].items() for n, c in S[ "candidates" ].items() )
    picks, taken = [], set()
    for h, st, n, c in allc:
        if not resolved( c ):
            return picks, False
        if eligible( c ) and st not in taken:
            picks.append( ( st, n, c[ "s4" ][ "route" ], h ) )
            taken.add( st )
            if len( picks ) == k:
                return picks, True
    return picks, True


def eligible( c ):
    return bool( c.get( "s4" ) and c[ "s4" ][ "route" ] )


def funnel( C ):
    f = dict( candidates=len( C ) )
    f[ "s0_pass" ] = sum( 1 for c in C.values() if not c.get( "s0" ) )
    for r in ( "archived_or_fork", "template", "mirror", "licence", "over_2gb", "in_E" ):
        f[ "s0_fail_" + r ] = sum( 1 for c in C.values() if r in ( c.get( "s0" ) or [] ) )
    s1 = [ c for c in C.values() if c.get( "s1" ) ]
    for r in ( "commits", "age", "window_activity", "no_default_branch", "api_error" ):
        f[ "s1_fail_" + r ] = sum( 1 for c in s1 if r in c[ "s1" ][ "reasons" ] )
    f[ "s1_pass" ] = sum( 1 for c in s1 if not c[ "s1" ][ "reasons" ] )
    f[ "s2_pass" ] = sum( 1 for c in C.values() if c.get( "s2" ) and not c[ "s2" ][ "reasons" ] )
    s3 = [ c for c in C.values() if c.get( "s3" ) ]
    f[ "s3_fail_too_few" ] = sum( 1 for c in s3 if "too_few_files" in c[ "s3" ][ "reasons" ] )
    f[ "s3_fail_too_many" ] = sum( 1 for c in s3 if "too_many_files" in c[ "s3" ][ "reasons" ] )
    f[ "s3_truncated_tree" ] = sum( 1 for c in s3 if c[ "s3" ].get( "truncated" ) )
    f[ "s3_pass" ] = sum( 1 for c in s3 if not c[ "s3" ][ "reasons" ] )
    s4 = [ c for c in C.values() if c.get( "s4" ) ]
    f[ "routeA_has_bug_label" ] = sum( 1 for c in s4 if c[ "s4" ][ "bug_labels" ] )
    f[ "routeA_ge50_issues" ] = sum( 1 for c in s4 if max( ( c[ "s4" ][ "route_a" ] or {} ).get( "bug_issues_2025", 0 ),
                                                           ( c[ "s4" ][ "route_a" ] or {} ).get( "issue_count_lower", 0 ) ) >= common.ROUTE_A_MIN_BUG_ISSUES_2025 )
    f[ "routeA_pass" ] = sum( 1 for c in s4 if c[ "s4" ][ "a_ok" ] )
    f[ "routeB_pass" ] = sum( 1 for c in s4 if c[ "s4" ][ "b_ok" ] )
    f[ "both_routes" ] = sum( 1 for c in s4 if c[ "s4" ][ "a_ok" ] and c[ "s4" ][ "b_ok" ] )
    f[ "eligible" ] = sum( 1 for c in C.values() if eligible( c ) )
    return f


def print_table( state ):
    for st, S in sorted( state[ "strata" ].items(), key=lambda kv: common.STRATUM_ORDER.index( kv[ 0 ] ) ):
        print( st, json.dumps( funnel( S[ "candidates" ] ), sort_keys=True ) )


def order( a ):
    state = load_state( a.cache )
    drop = set( x.lower() for x in ( a.drop.split( "," ) if a.drop else [] ) )
    for st in common.STRATUM_ORDER:
        S = state[ "strata" ].get( st )
        if not S:
            continue
        pool = sorted( ( common.salted_rank( a.salt, n ), n ) for n, c in S[ "candidates" ].items() if eligible( c ) and n.lower() not in drop )
        for h, n in pool:
            print( st, h, n, S[ "candidates" ][ n ][ "s4" ][ "route" ] )


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers( dest="cmd", required=True )
    c = sub.add_parser( "census" )
    c.add_argument( "--cache", required=True )
    c.add_argument( "--exclusions", required=True )
    c.add_argument( "--strata" )
    o = sub.add_parser( "order" )
    o.add_argument( "--cache", required=True )
    o.add_argument( "--salt", required=True )
    o.add_argument( "--drop" )
    pp = sub.add_parser( "pilot" )
    pp.add_argument( "--cache", required=True )
    t = sub.add_parser( "table" )
    t.add_argument( "--cache", required=True )
    a = ap.parse_args()
    if a.cmd == "census":
        census( a )
    elif a.cmd == "order":
        order( a )
    elif a.cmd == "pilot":
        picks, complete = sd_pilot_picks( load_state( a.cache ) )
        print( json.dumps( dict( complete=complete, picks=picks ), indent=1 ) )
    else:
        print_table( load_state( a.cache ) )
