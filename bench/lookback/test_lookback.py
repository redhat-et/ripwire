#!/usr/bin/env python3
"""
Unit tests for the M1 look-back harness (bench/lookback/). SYNTHETIC ONLY: every fixture is built here — tiny
git repositories created in a temporary directory, hand-computed curves, invented label names. Nothing reads a
corpus, runs the ripwire binary, or touches the network.

    python3 bench/lookback/test_lookback.py          # runs every test_* below; exit 0 = all pass

Each test_* is a self-contained assert-based case (the same convention as bench/locbench/test_compare_gate.py).
"""
import itertools, json, os, shutil, subprocess, sys, tempfile
from fractions import Fraction

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
import common, labels, maphunks, metrics, rankers, selectrepos, exclusions


# ── helpers ─────────────────────────────────────────────────────────────────────────────────────────────
def brute_area( units ):
    """Mean normalised area over EVERY order consistent with the score (ties permuted) — the definition the
    tie-block rule must equal exactly."""
    E = sum( u[ 1 ] for u in units )
    Y = sum( u[ 2 ] for u in units )
    groups = {}
    for u in units:
        groups.setdefault( u[ 0 ], [] ).append( u )
    keys = sorted( groups, reverse=True )
    total, count = Fraction( 0 ), 0
    for perm in itertools.product( *[ list( itertools.permutations( groups[ k ] ) ) for k in keys ] ):
        order = [ u for block in perm for u in block ]
        e = y = 0
        area = Fraction( 0 )
        for _, ue, uy in order:
            area += Fraction( ue, E ) * ( Fraction( y, Y ) + Fraction( y + uy, Y ) ) / 2
            e += ue
            y += uy
        total += area
        count += 1
    return total / count


class GitRepo:
    def __init__( self ):
        self.dir = tempfile.mkdtemp( prefix="lookback-test-" )
        self.t = 1700000000
        self.git( "init", "-q", "-b", "main" )

    def git( self, *args, env=None ):
        e = dict( os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid", GIT_COMMITTER_NAME="t",
                  GIT_COMMITTER_EMAIL="t@example.invalid", GIT_CONFIG_NOSYSTEM="1", HOME=self.dir )
        if env:
            e.update( env )
        return subprocess.run( [ "git", "-C", self.dir, "-c", "commit.gpgsign=false", *args ], capture_output=True, text=True, check=True, env=e ).stdout

    def write( self, path, text ):
        full = os.path.join( self.dir, path )
        os.makedirs( os.path.dirname( full ), exist_ok=True )
        with open( full, "w" ) as fh:
            fh.write( text )

    def commit( self, msg, when=None ):
        self.t = when if when is not None else self.t + 86400
        d = "@%d +0000" % self.t
        self.git( "add", "-A" )
        self.git( "commit", "-q", "--allow-empty", "-m", msg, env=dict( GIT_AUTHOR_DATE=d, GIT_COMMITTER_DATE=d ) )
        return self.git( "rev-parse", "HEAD" ).strip()

    def close( self ):
        shutil.rmtree( self.dir, ignore_errors=True )


class ToyFunctions:
    """A test-only unit provider for a toy language: a unit starts at `def NAME` (scope from a preceding
    `class NAME` line at column 0) and ends at the line before the next def/class or at EOF. It exists to
    exercise maphunks' mapping rules; it is not a parser for any real language."""
    grain = "function"

    def units( self, path, data ):
        lines = data.decode().split( "\n" )
        if lines and lines[ -1 ] == "":
            lines.pop()
        out, cur, scope = [], None, ""
        for i, line in enumerate( lines, 1 ):
            if line.startswith( "class " ):
                if cur:
                    out.append( ( cur[ 0 ], cur[ 1 ], cur[ 2 ], i - 1 ) )
                    cur = None
                scope = line.split()[ 1 ]
            elif line.lstrip().startswith( "def " ):
                if cur:
                    out.append( ( cur[ 0 ], cur[ 1 ], cur[ 2 ], i - 1 ) )
                cur = ( scope if line.startswith( " " ) else "", line.split()[ 1 ], i )
        if cur:
            out.append( ( cur[ 0 ], cur[ 1 ], cur[ 2 ], len( lines ) ) )
        return out


# ── metrics ─────────────────────────────────────────────────────────────────────────────────────────────
def test_curve_hand_computed():
    # three units, effort 10 each, fixes on the 1st and 3rd by score. Curve: (0,0)->(1/3,1/2)->(2/3,1/2)->(1,1)
    u = [ ( 3, 10, 1 ), ( 2, 10, 0 ), ( 1, 10, 1 ) ]
    # area = 1/3*(0+1/2)/2 + 1/3*(1/2+1/2)/2 + 1/3*(1/2+1)/2 = 1/12 + 1/6 + 1/4 = 1/2
    assert metrics.normalised_area( u ) == Fraction( 1, 2 )
    # optimal: density 1/10,1/10,0 -> (0,0)->(2/3,1)->(1,1): area = 2/3*1/2 + 1/3 = 2/3; worst: (1/3,0)->(1,1) = 1/3
    assert metrics.popt( u ) == Fraction( Fraction( 1, 2 ) - Fraction( 1, 3 ), Fraction( 2, 3 ) - Fraction( 1, 3 ) ) == Fraction( 1, 2 )
    assert metrics.recall_at( u ) == Fraction( 3, 10 )          # x=0.2 within the first segment: 0.2/(1/3) * 1/2


def test_tie_block_equals_mean_over_permutations():
    cases = [
        [ ( 1, 3, 1 ), ( 1, 5, 0 ), ( 1, 2, 1 ), ( 0, 4, 0 ), ( 0, 1, 1 ) ],
        [ ( 2, 1, 0 ), ( 2, 7, 1 ), ( 1, 3, 1 ), ( 1, 3, 0 ), ( 1, 2, 0 ) ],
        [ ( 5, 2, 1 ), ( 5, 2, 1 ), ( 5, 9, 0 ) ],
    ]
    for u in cases:
        assert metrics.normalised_area( u ) == brute_area( u ), u


def test_random_is_the_diagonal_and_bounds():
    u = [ ( 0, e, y ) for e, y in ( ( 4, 1 ), ( 9, 0 ), ( 1, 1 ), ( 6, 0 ), ( 3, 1 ) ) ]
    assert metrics.normalised_area( u ) == Fraction( 1, 2 )
    assert metrics.recall_at( u ) == Fraction( 1, 5 )
    opt = [ ( Fraction( y, e ), e, y ) for _, e, y in u ]
    worst = [ ( -Fraction( y, e ), e, y ) for _, e, y in u ]
    assert metrics.popt( opt ) == 1 and metrics.popt( worst ) == 0


def test_popt_undefined_cases():
    assert metrics.popt( [ ( 1, 5, 0 ), ( 0, 5, 0 ) ] ) is None                 # no fixes
    assert metrics.popt( [ ( 1, 5, 1 ), ( 0, 5, 1 ) ] ) is None                 # equal density: opt == worst
    try:
        metrics.popt( [ ( 1, 0, 1 ) ] )
        raise AssertionError( "zero effort accepted" )
    except ValueError:
        pass


def test_auroc_midranks_match_pairwise():
    u = [ ( 3, 1, 1 ), ( 3, 1, 0 ), ( 2, 1, 1 ), ( 1, 1, 0 ), ( 1, 1, 0 ), ( 2, 1, 0 ), ( 5, 1, 1 ) ]
    pos = [ s for s, _, y in u if y ]
    neg = [ s for s, _, y in u if not y ]
    pw = sum( Fraction( 1 ) if p > n else Fraction( 1, 2 ) if p == n else 0 for p in pos for n in neg ) / ( len( pos ) * len( neg ) )
    assert metrics.auroc( u ) == pw
    assert metrics.auroc( [ ( 1, 1, 1 ) ] ) is None


def test_tuple_scores_order_lexicographically():
    # HOT's (file score, ccx) tuple: file score first; the unranked -1 block sits at the bottom
    u = [ ( ( 10, 1 ), 5, 0 ), ( ( 10, 9 ), 5, 1 ), ( ( -1, 50 ), 5, 0 ), ( ( 3, 2 ), 5, 1 ) ]
    b = metrics._blocks( u, key=lambda x: x[ 0 ] )
    assert b == [ ( 5, 1 ), ( 5, 0 ), ( 5, 1 ), ( 5, 0 ) ]


def test_score_arm_is_deterministic_under_input_order():
    u = [ ( i % 3, 1 + i % 5, 1 if i % 4 == 0 else 0 ) for i in range( 40 ) ]
    a = metrics.score_arm( u )
    b = metrics.score_arm( list( reversed( u ) ) )
    assert a == b


# ── labels ──────────────────────────────────────────────────────────────────────────────────────────────
def test_route_b_rule():
    assert labels.is_route_b( "fix: null deref in parser" )
    assert labels.is_route_b( "fix(core)!: overflow" )
    assert not labels.is_route_b( "fix(docs): typo" )
    assert not labels.is_route_b( "fix(CI): flaky job" )                  # scope compared lowercased
    assert not labels.is_route_b( "feat: add x" )
    assert not labels.is_route_b( "Fix: capitalised type" )               # the registered regex is case-sensitive
    assert not labels.is_route_b( "fix:no space" )


def test_keyword_rule():
    assert labels.is_keyword_fix( "Fix crash when input is empty" )
    assert labels.is_keyword_fix( "bugfix for regression in loader" )
    assert not labels.is_keyword_fix( "Fix typo in README" )
    assert not labels.is_keyword_fix( "fix lint warnings" )
    assert not labels.is_keyword_fix( "prefix handling" )                 # \b word boundary
    assert not labels.is_keyword_fix( "debug output" )


def test_bug_label_rule():
    yes = [ "bug", "type: bug", "kind/bug", "C-bug", "I-crash", "regression", "Type: Defect", "bug_report" ]
    no = [ "not a bug", "feature", "bug-feature", "question", "docs bug", "invalid-bug", "enhancement", "debugger" ]
    for l in yes:
        assert labels.is_bug_label( l ), l
        assert selectrepos.is_bug_label( l ), l
    for l in no:
        assert not labels.is_bug_label( l ), l
        assert not selectrepos.is_bug_label( l ), l


def test_issue_links():
    msg = "Handle empty input\n\nFixes #12, closes #7 and resolved #3.\nSee #99. https://github.com/o/n/issues/41 and https://github.com/x/y/issues/5"
    assert labels.message_issue_refs( msg, "o/n" ) == { 12, 7, 3, 41 }


def test_pr_title_for_merges():
    body = "Merge pull request #5 from someone/fix-branch\n\nfix: real title here"
    assert labels.pr_title_subject( body.split( "\n" )[ 0 ], body, 2 ) == "fix: real title here"
    assert labels.pr_title_subject( "fix: squash", "fix: squash", 1 ) == "fix: squash"


def test_t_and_windows():
    D = labels.iso_to_epoch
    chain = [ ( "c5", D( "2025-02-02T00:00:00Z" ) ), ( "c4", D( "2025-01-15T00:00:00Z" ) ), ( "c3", D( "2025-01-01T00:00:00Z" ) ),
              ( "c2", D( "2024-12-31T23:59:59Z" ) ), ( "c1", D( "2024-06-01T00:00:00Z" ) ) ]
    t = labels.resolve_t( chain, D( "2024-12-31T23:59:59Z" ) )
    assert t == "c2"                                                    # <= D 23:59:59 inclusive
    win, path = labels.window_commits( chain, t, D( "2024-12-31T23:59:59Z" ), D( "2025-01-31T23:59:59Z" ) )
    assert win == [ "c3", "c4" ] and path == [ "c3", "c4" ]
    assert labels.window_commits( chain, "zz", 0, 1 ) == ( [], [] )


# ── common ──────────────────────────────────────────────────────────────────────────────────────────────
def test_product_source_rule():
    P = common.is_product_path
    assert P( "src/core/parse.cc", "cpp" ) and P( "include/x.h", "cpp" )
    assert not P( "tests/parse_test.cc", "cpp" ) and not P( "src/parse_test.cc", "cpp" ) and not P( "third_party/z/a.c", "cpp" )
    assert P( "pkg/mod.py", "python" ) and not P( "pkg/test_mod.py", "python" ) and not P( "pkg/conftest.py", "python" )
    assert not P( "docs/conf.py", "python" ) and not P( "examples/a.py", "python" )
    assert P( "src/a.ts", "typescript" ) and not P( "src/a.d.ts", "typescript" ) and not P( "src/a.spec.ts", "typescript" )
    assert P( "cmd/x/main.go", "go" ) and not P( "cmd/x/main_test.go", "go" ) and not P( "vendor/a/b.go", "go" )
    assert P( "src/main/java/A.java", "java" ) and not P( "src/test/java/ATest.java", "java" )
    assert P( "src/lib.rs", "rust" ) and not P( "benches/b.rs", "rust" ) and not P( "src/a.py", "rust" )
    assert common.is_generated_head( "// Code generated by protoc-gen-go. DO NOT EDIT.\npackage x\n" )
    assert not common.is_generated_head( "a\nb\nc\nd\ne\n// generated by hand on line 6\n" )


def test_frozen_constants_pinned():
    """Any change to a frozen constant changes this digest — an amendment must update it on purpose."""
    frozen = dict(
        salt=common.SELECTION_SALT, pilot_salt=common.SD_PILOT_SALT, strata=common.STRATA, stars=common.MIN_STARS,
        created=common.CREATED_ON_OR_BEFORE, first=common.FIRST_COMMIT_ON_OR_BEFORE, commits=common.MIN_COMMITS,
        authors=common.MIN_AUTHORS_2024_2025, files=[ common.MIN_PRODUCT_FILES, common.MAX_PRODUCT_FILES ], kb=common.MAX_REPO_KB,
        ra=[ common.ROUTE_A_MIN_BUG_ISSUES_2025, common.ROUTE_A_MIN_LINKED_FRACTION ], rb=common.ROUTE_B_MIN_CC_FRACTION,
        windows=common.WINDOWS, lookback=common.LOOKBACK_MONTHS, floor=common.EVENT_FLOOR,
        words=sorted( common.BUG_LABEL_WORDS ), veto=sorted( common.BUG_LABEL_VETO ),
        res=[ common.LINK_RE.pattern, common.ROUTE_B_RE.pattern, common.KEYWORD_RE.pattern, common.KEYWORD_VETO_RE.pattern,
              common.CONVENTIONAL_RE.pattern, common.NON_PRODUCT_NAME_RE.pattern, common.GENERATED_RE.pattern ],
        scopeveto=sorted( common.ROUTE_B_SCOPE_VETO ), exts=common.STRATUM_EXTS, dirs=sorted( common.NON_PRODUCT_DIRS ),
        osi=sorted( common.OSI_SPDX ), m=[ common.RECALL_AT, common.BOOTSTRAP_SEED, common.BOOTSTRAP_RESAMPLES, common.MARGIN_M,
                                            common.DELTA_SIMPLER, common.SIGN_CONSISTENCY ], order=common.SIMPLICITY_ORDER,
        floors=[ common.PARSE_FLOOR, common.JOIN_FLOOR, common.CCX_FLOOR, common.JOIN_LINE_SLACK ], rw=common.RIPWIRE_VERSION,
        pruned=sorted( common.RIPWIRE_PRUNED_DIRS ) )
    import hashlib
    digest = hashlib.sha256( json.dumps( frozen, sort_keys=True ).encode() ).hexdigest()
    assert digest == PINNED_CONSTANTS, "frozen constants changed: %s" % digest


PINNED_CONSTANTS = "06aeb464902b157abe325e66efa8a77f4e4e91c3f787da621019415b7522bfb6"


def test_salted_rank_is_stable():
    assert common.salted_rank( "s", "Owner/Name" ) == common.salted_rank( "s", "owner/name" )
    assert common.salted_rank( common.SELECTION_SALT, "a/b" ) != common.salted_rank( common.SD_PILOT_SALT, "a/b" )


# ── maphunks on real (synthetic) git history ────────────────────────────────────────────────────────────
def test_hunk_parse_insertion_rename_and_mapping():
    g = GitRepo()
    try:
        g.write( "m.toy", "class K\n def a\n  x\n  y\n def b\n  z\ndef top\n  w\n" )
        g.write( "other.toy", "def q\n  1\n" )
        t = g.commit( "base" )
        # c1: rename m.toy -> n.toy with a change inside b (line 6), and an insertion after line 3 (inside a)
        g.git( "mv", "m.toy", "n.toy" )
        g.write( "n.toy", "class K\n def a\n  x\n  inserted\n  y\n def b\n  Z\ndef top\n  w\n" )
        c1 = g.commit( "fix crash in b" )
        # c2: change top (line 9 at the parent c1 = 'w'), and delete other.toy
        g.write( "n.toy", "class K\n def a\n  x\n  inserted\n  y\n def b\n  Z\ndef top\n  W\n" )
        os.remove( os.path.join( g.dir, "other.toy" ) )
        c2 = g.commit( "fix top" )
        f1 = maphunks.commit_diff( g.dir, c1 )
        assert len( f1 ) == 1 and f1[ 0 ][ 0 ] == "m.toy" and f1[ 0 ][ 1 ] == "n.toy"
        assert sorted( f1[ 0 ][ 2 ] ) == [ ( 3, 0 ), ( 6, 1 ) ], f1
        prov = ToyFunctions()
        cache = maphunks.UnitCache( g.dir, prov )
        t_units = { ( p, u[ 0 ], u[ 1 ], u[ 2 ] ) for p in ( "m.toy", "other.toy" ) for u in cache.units( t, p ) }
        assert ( "m.toy", "K", "a", 0 ) in t_units and ( "m.toy", "", "top", 0 ) in t_units
        tr = maphunks.RenameTracker()
        hit1, n1 = maphunks.touched_units( f1, lambda p: cache.units( c1 + "^1", p ), tr, t_units )
        assert hit1 == { ( "m.toy", "K", "a", 0 ), ( "m.toy", "K", "b", 0 ) }, hit1   # insertion anchor 3 -> a; line 6 -> b
        tr.advance( f1 )
        assert tr.path_at_t( "n.toy" ) == "m.toy"
        f2 = maphunks.commit_diff( g.dir, c2 )
        hit2, n2 = maphunks.touched_units( f2, lambda p: cache.units( c2 + "^1", p ), tr, t_units )
        # identity carried through the rename; deleting other.toy is a hunk over q's lines, so it touches q
        assert hit2 == { ( "m.toy", "", "top", 0 ), ( "other.toy", "", "q", 0 ) }, hit2
        assert n2 == dict( hunks=2, mapped=2, unmapped=0, born_after_t=0, out_of_population=0 ), n2
        cache.blobs.close()
    finally:
        g.close()


def test_added_after_t_is_not_in_population():
    g = GitRepo()
    try:
        g.write( "a.toy", "def f\n  1\n" )
        t = g.commit( "base" )
        g.write( "b.toy", "def g\n  1\n" )
        c1 = g.commit( "add b" )
        g.write( "b.toy", "def g\n  2\n" )
        c2 = g.commit( "fix g" )
        tr = maphunks.RenameTracker()
        tr.advance( maphunks.commit_diff( g.dir, c1 ) )
        assert tr.path_at_t( "b.toy" ) is None
        cache = maphunks.UnitCache( g.dir, ToyFunctions() )
        hit, n = maphunks.touched_units( maphunks.commit_diff( g.dir, c2 ), lambda p: cache.units( c2 + "^1", p ), tr, { ( "a.toy", "", "f", 0 ) } )
        assert hit == set() and n[ "born_after_t" ] == 1 and n[ "mapped" ] == 0
        cache.blobs.close()
    finally:
        g.close()


def test_name_status_matches_diff_renames():
    g = GitRepo()
    try:
        g.write( "a.toy", "def f\n  1\n  2\n  3\n  4\n" )
        g.write( "d.toy", "def d\n" )
        g.commit( "base" )
        g.git( "mv", "a.toy", "b.toy" )
        os.remove( os.path.join( g.dir, "d.toy" ) )
        g.write( "n.toy", "def n\n" )
        c = g.commit( "move" )
        ns = sorted( maphunks.name_status( g.dir, c ), key=str )
        full = [ ( o, n, [] ) for o, n, _ in maphunks.commit_diff( g.dir, c ) ]
        assert ns == sorted( full, key=str ) == sorted( [ ( "a.toy", "b.toy", [] ), ( "d.toy", None, [] ), ( None, "n.toy", [] ) ], key=str ), ns
    finally:
        g.close()


def test_batched_diffs_equal_per_commit_diffs():
    g = GitRepo()
    try:
        g.write( "a.toy", "def f\n  1\n  2\n  3\n  4\n" )
        g.write( "b.toy", "def b\n  1\n" )
        t = g.commit( "base" )
        g.git( "checkout", "-q", "-b", "side" )
        g.write( "b.toy", "def b\n  2\n" )
        g.commit( "side change" )
        g.git( "checkout", "-q", "main" )
        g.git( "mv", "a.toy", "c.toy" )
        g.write( "c.toy", "def f\n  1\n  X\n  3\n  4\n" )
        g.commit( "move and edit" )
        g.git( "merge", "-q", "--no-ff", "-m", "Merge pull request #9 from x/side\n\nfix: side", "side",
               env=dict( GIT_AUTHOR_DATE="@1800000000 +0000", GIT_COMMITTER_DATE="@1800000000 +0000" ) )
        chain = labels.first_parent_chain( g.dir, "HEAD" )
        shas = [ s for s, _ in chain if s != t ]
        path = list( reversed( shas ) )
        mb = labels.merged_messages_batch( g.dir, t, shas[ 0 ], path )
        assert set( mb ) == { shas[ 0 ] } and sorted( mb[ shas[ 0 ] ] ) == labels.merged_messages( g.dir, shas[ 0 ], 2 ), mb
        batched = maphunks.first_parent_diffs( g.dir, shas )
        ns = maphunks.first_parent_name_status( g.dir, t, shas[ 0 ] )
        assert set( batched ) == set( shas ) == set( ns )
        for s in shas:
            assert batched[ s ] == maphunks.commit_diff( g.dir, s ), s
            assert sorted( ns[ s ], key=str ) == sorted( maphunks.name_status( g.dir, s ), key=str ), s
    finally:
        g.close()


def test_a1_sample_is_order_free():
    recs = [ ( "o/n", "%040x" % i, "a.c", i, 1, [] ) for i in range( 200 ) ]
    s1 = maphunks.a1_sample( recs, 50 )
    s2 = maphunks.a1_sample( list( reversed( recs ) ), 50 )
    assert s1 == s2 and len( s1 ) == 50 and s1 != recs[ :50 ]


def test_overload_ordinals():
    raw = [ ( "", "f", 10, 12 ), ( "", "g", 1, 3 ), ( "", "f", 4, 8 ) ]
    assert maphunks.with_ordinals( raw ) == [ ( "", "g", 0, 1, 3 ), ( "", "f", 0, 4, 8 ), ( "", "f", 1, 10, 12 ) ]


def test_quoted_paths_and_combined_parse():
    assert maphunks.unquote_path( '"a\\tb.c"' ) == "a\tb.c"
    assert maphunks.unquote_path( '"caf\\303\\251.py"' ) == "café.py"
    txt = "diff --combined x.c\nindex 1,2..3\n@@@ -5,2 -7,0 +5,3 @@@\n@@@ -20 -21 +22 @@@\n"
    assert maphunks.parse_combined( txt ) == [ ( "x.c", "x.c", [ ( 5, 2 ), ( 20, 1 ) ] ) ]
    assert maphunks.old_lines( 0, 0 ) == ( 1, 1 ) and maphunks.old_lines( 7, 0 ) == ( 7, 7 ) and maphunks.old_lines( 7, 3 ) == ( 7, 9 )


# ── rankers ─────────────────────────────────────────────────────────────────────────────────────────────
def test_months_before_epoch_matches_ripwire_semantics():
    D = labels.iso_to_epoch
    assert rankers.months_before_epoch( D( "2025-06-30T12:00:00Z" ), 12 ) == D( "2024-06-30T12:00:00Z" )
    assert rankers.months_before_epoch( D( "2025-03-31T00:00:05Z" ), 1 ) == D( "2025-03-03T00:00:05Z" )   # Feb 1 + 30 days
    assert rankers.months_before_epoch( D( "2024-02-29T00:00:00Z" ), 12 ) == D( "2023-03-01T00:00:00Z" )


def test_health_hotspots():
    ok = dict( window="12mo@HEAD", at="abc1234", files="10", ranked="4", unranked_no_churn="3", unranked_no_complexity="2", unranked_extent_suspect="1" )
    assert rankers.health_hotspots( ok, "abc1234ffff" ) == []
    assert rankers.health_hotspots( dict( ok, at="abc1234+dirty" ), "abc1234ffff" )
    assert rankers.health_hotspots( dict( ok, window="12mo" ), "abc1234ffff" )
    assert rankers.health_hotspots( dict( ok, files="11" ), "abc1234ffff" )


def test_file_arms_and_lookback():
    g = GitRepo()
    try:
        g.write( "src/a.c", "int a(){return 1;}\n" )
        g.write( "src/b.c", "int b(){return 1;}\n" )
        g.commit( "init" )
        g.write( "src/a.c", "int a(){return 2;}\n" )
        g.commit( "fix crash in a" )
        g.write( "src/b.c", "int b(){return 2;}\n" )
        t = g.commit( "tidy b" )
        lb, since = rankers.lookback_commits( g.dir, t )
        assert len( lb ) == 3
        hot = { "src/a.c": dict( score="6" ) }
        mrows = [ dict( t="fn", p="src/a.c", ccx="3", **{ "in": "2" } ), dict( t="fn", p="src/b.c", ccx="1", **{ "in": "5" } ),
                  dict( t="cls", p="src/b.c", ccx="9" ) ]
        arms, diag = rankers.file_arms( { "src/a.c": 1, "src/b.c": 1 }, hot, mrows, lb )
        assert arms[ "src/a.c" ] == dict( HOT=6, CCX=3, FANIN=2, CHURN=2, HOTFN=6, PRIOR=1, RANDOM=0, SMALL=-1, BIG=1 )
        assert arms[ "src/b.c" ][ "HOT" ] == -1 and arms[ "src/b.c" ][ "CCX" ] == 1 and arms[ "src/b.c" ][ "PRIOR" ] == 0
    finally:
        g.close()


def test_ripwire_read_fraction():
    units = { "pkg/a.py": 10, "pkg/build/b.py": 10, "pkg/out/c.py": 5, "pkg/big.py": 9, "pkg/d.py": 1 }
    frac, pruned, unread = rankers.ripwire_read_fraction( units, { "pkg/big.py": "oversize", "pkg/d.py": "degraded-parse" } )
    assert ( pruned, unread ) == ( 2, 1 ) and abs( frac - 0.4 ) < 1e-12
    assert common.ripwire_prunes( "a/cmake-build-debug/x.c" ) and not common.ripwire_prunes( "build.py" )


def test_function_join():
    units = [ ( "a.c", "", "f", 0, 10, 20 ), ( "a.c", "", "g", 0, 30, 40 ), ( "a.c", "", "h", 0, 50, 60 ) ]
    rows = [ dict( p="a.c", n="f", l="12" ), dict( p="a.c", n="g", l="36" ), dict( p="a.c", n="h", l="49" ), dict( p="a.c", n="h", l="51" ) ]
    joined, c = rankers.join_function_rows( units, rows )
    assert set( joined ) == { ( "a.c", "", "f", 0 ) } and c == dict( joined=1, ambiguous=1, missing=1, units=3 )


# ── the window labeller end to end on a toy history (file grain) ────────────────────────────────────────
def test_label_window_known_fixes():
    import runrepo
    g = GitRepo()
    try:
        D = labels.iso_to_epoch
        g.write( "src/a.c", "1\n2\n3\n" )
        g.write( "src/b.c", "1\n" )
        g.write( "src/c.c", "1\n" )
        t = g.commit( "init", when=D( "2024-12-01T00:00:00Z" ) )
        g.git( "mv", "src/b.c", "src/bb.c" )
        g.commit( "rename b", when=D( "2025-01-02T00:00:00Z" ) )
        g.write( "src/bb.c", "one\n" )
        g.commit( "Fix crash in bb", when=D( "2025-01-03T00:00:00Z" ) )
        g.write( "src/a.c", "1\n2\n3\n4\n" )
        g.commit( "feat: grow a", when=D( "2025-01-04T00:00:00Z" ) )
        g.write( "src/new.c", "x\n" )
        g.write( "src/c.c", "2\n" )
        g.commit( "fix: new file and c", when=D( "2025-01-05T00:00:00Z" ) )
        g.write( "src/c.c", "3\n" )
        g.commit( "fix: late", when=D( "2025-08-01T00:00:00Z" ) )              # outside the window
        chain = labels.first_parent_chain( g.dir, "HEAD" )
        tt = labels.resolve_t( chain, D( "2024-12-31T23:59:59Z" ) )
        assert tt == t
        win, path = labels.window_commits( chain, tt, D( "2024-12-31T23:59:59Z" ), D( "2025-06-30T23:59:59Z" ) )
        assert len( win ) == 4
        lab = labels.label_commits( g.dir, "o/n", win, [], None )
        rules = { "keyword": { s for s, v in lab.items() if v[ "keyword" ] }, "B": { s for s, v in lab.items() if v[ "route_b" ] } }
        fixed, n = runrepo.label_window( g.dir, rules, path, win, { ( p, "", "<file>", 0 ) for p in ( "src/a.c", "src/b.c", "src/c.c" ) }, tt )
        # "Fix crash in bb" reaches T's path through the rename; "fix: new file and c" is a fix under both rules,
        # and new.c was born after T, so it is not a unit; "feat: grow a" and the late fix label nothing
        assert fixed[ "keyword" ] == { "src/b.c": 1, "src/c.c": 1 }, fixed
        assert fixed[ "B" ] == { "src/c.c": 1 }, fixed
        assert n[ "fix_commits" ] == { "keyword": 2, "B": 1 }
    finally:
        g.close()


# ── analyze ─────────────────────────────────────────────────────────────────────────────────────────────
def test_power_reproduces_the_registered_table():
    import analyze
    # §7's table (normal approximation): SD, n -> P(beats | Δ=0.08), P(beats | Δ=0.05)
    for sd, n, p08, p05 in ( ( 0.10, 24, 0.92, 0.4 ), ( 0.10, 15, 0.86, 0.4 ), ( 0.12, 24, 0.84, 0.35 ), ( 0.12, 15, 0.69, 0.3 ) ):
        assert abs( analyze.power( sd, n, 0.08 ) - p08 ) < 0.015, ( sd, n )
        assert abs( analyze.power( sd, n, 0.05 ) - p05 ) < 0.03, ( sd, n )
        assert analyze.power( sd, n, 0.0 ) <= 0.025
    assert abs( analyze.power( 0.10, 24, 0.08, z=2.64 ) - 0.89 ) < 0.01


def test_bootstrap_and_beats_are_deterministic():
    import analyze
    table = { "r%d" % i: { "1": { "HOT": dict( popt=0.6 + 0.01 * i, recall20=0.3 ), "RANDOM": dict( popt=0.5, recall20=0.2 ) } } for i in range( 8 ) }
    mp = analyze.per_repo_means( table, "popt" )
    mr = analyze.per_repo_means( table, "recall20" )
    a = analyze.beats( mp, mr, "HOT", "RANDOM" )
    b = analyze.beats( mp, mr, "HOT", "RANDOM" )
    assert a == b and a[ "ok" ] and a[ "ci" ][ 0 ] > 0 and a[ "sign" ] == 1.0
    lo, hi = analyze.sd_ci( 0.1, 3 )
    assert 0.05 < lo < 0.06 and 0.6 < hi < 0.65


# ── selectrepos pure parts ──────────────────────────────────────────────────────────────────────────────
def test_stage0_and_authors():
    c = dict( full_name="o/n", archived=False, fork=False, is_template=False, mirror_url=None, license="MIT", size_kb=10 )
    assert selectrepos.stage0( c, set(), set() ) == []
    assert selectrepos.stage0( dict( c, license="NOASSERTION" ), set(), set() ) == [ "licence" ]
    assert selectrepos.stage0( dict( c, size_kb=common.MAX_REPO_KB + 1 ), set(), set() ) == [ "over_2gb" ]
    assert selectrepos.stage0( c, { "o/n" }, set() ) == [ "in_E" ]
    assert selectrepos.stage0( dict( c, full_name="x/N" ), set(), { "n" } ) == [ "in_E" ]
    assert selectrepos.author_key( dict( author=dict( email="A@x.org", user=dict( login="Al" ) ) ) ) == "u:al"
    assert selectrepos.author_key( dict( author=dict( email="a@x.org", user=None ) ) ) == "e:a@x.org"
    assert selectrepos.author_key( dict( author=dict( email="x@y", user=dict( login="dependabot[bot]" ) ) ) ) is None
    assert selectrepos._after( "2024-12-31T23:59:59Z" ) == "2025-01-01T00:00:00Z"
    assert common.CONVENTIONAL_RE.match( "chore(deps): bump" ) and not common.CONVENTIONAL_RE.match( "Merge pull request #1" )


def test_route_a_early_verdicts_are_exact():
    D = selectrepos.route_a_decide
    assert D( { "bug": 40 }, 0, 0 ) is False                               # < 50 even if the union is everything
    assert D( { "bug": 200 }, 100, 60 ) is True                            # 60 >= 0.3 * 200 whatever the rest are
    assert D( { "bug": 200 }, 100, 10 ) is None                            # 10 + 100 unseen could still reach 60
    assert D( { "bug": 200 }, 190, 5 ) is False                            # 5 + 10 < 60
    assert D( { "a": 30, "b": 30 }, 30, 18 ) is None                       # union may be 30 (< 50) or 60
    assert D( { "a": 60, "b": 30 }, 60, 27 ) is True                       # union in [60, 90]; 27 >= 0.3 * 90


def test_sd_pilot_walk():
    ok = lambda r: dict( s0=[], s1=dict( reasons=[] ), s2=dict( reasons=[] ), s3=dict( reasons=[] ), s4=dict( route=r ) )
    bad = dict( s0=[ "licence" ] )
    pending = dict( s0=[], s1=dict( reasons=[] ) )
    names = sorted( ( "o/r%d" % i for i in range( 40 ) ), key=selectrepos._pilot_order )
    strata = [ "cpp", "go", "cpp", "rust", "go", "java" ] + [ "python" ] * 34
    st = { "strata": {} }
    for n, s_ in zip( names, strata ):
        st[ "strata" ].setdefault( s_, { "candidates": {} } )[ "candidates" ][ n ] = ok( "A" )
    st[ "strata" ][ "cpp" ][ "candidates" ][ names[ 0 ] ] = bad
    picks, complete = selectrepos.sd_pilot_picks( st )
    assert complete and [ p[ 1 ] for p in picks ] == [ names[ 1 ], names[ 2 ], names[ 3 ] ], picks   # go, cpp, rust; the 2nd go skipped
    st[ "strata" ][ "rust" ][ "candidates" ][ names[ 3 ] ] = pending
    picks, complete = selectrepos.sd_pilot_picks( st )
    assert not complete and len( picks ) == 2


def test_exclusion_scan():
    out = set()
    exclusions.scan_text( "see https://github.com/Foo/Bar.git and django__django-11099 and github.com/sponsors/x", out )
    assert out == { "foo/bar", "django/django" }


def main():
    tests = [ ( n, f ) for n, f in sorted( globals().items() ) if n.startswith( "test_" ) and callable( f ) ]
    fails = 0
    for n, f in tests:
        try:
            f()
            print( "ok   %s" % n )
        except Exception as e:                       # noqa: BLE001 — report every failure, keep going
            fails += 1
            print( "FAIL %s: %s: %s" % ( n, type( e ).__name__, e ) )
    print( "%d/%d passed" % ( len( tests ) - fails, len( tests ) ) )
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit( main() )
