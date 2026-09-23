#!/usr/bin/env python3
# crossctx_sites.py — the mechanical stage of the cross-context external-rate pre-registration
# (docs/research/cross-context-external-rate.md, registered 2026-09-23, before any data).
#
# WHAT THIS IS. Given a Loc-Bench row's fix patch and a reader for the pre-fix tree, compute the SITES the
# fix touched — (file, outermost function-level definition) at base_commit — and the row's mechanical class
# (ONE-SITE / MULTI-SITE-ONE-FILE / MULTI-FILE, or an excluded bucket). Plus: the legacy fix-shape rule
# recomputed VERBATIM as the population fingerprint (§4.4), the stratified systematic sampler for the rater
# stage (R1), Cohen's kappa (R7), Wilson and post-stratified bootstrap intervals (§7), and the decision
# table (§9). Every constant a later reader might be tempted to tune is named in FROZEN below.
#
# WHAT THIS IS NOT. It does not fetch anything, does not walk history (no `git log`, no `rev-list`), does not
# invoke the ripwire binary (the recipe is deliberately independent of the tool whose motivation it
# measures — §12 decision 11), and does not label anything CROSS or LOCAL: that is the raters' step (§6),
# and this module only prepares their sample and scores their labels afterwards.
#
# NO DATA HAS PASSED THROUGH THIS FILE. As committed, it has run only on the synthetic fixtures in
# test_crossctx_sites.py. `main()` refuses a rows file whose SHA-256 is not the one pinned in
# bench/locbench/dataset.lock, so the run can prove which population it scored (§4.1).
#
# House conventions: pure Python 3, standard library only, no pytest dependency; same as compare_runs.py.
import argparse, ast, collections, hashlib, json, os, random, re, subprocess, sys

# ── FROZEN BY THE PRE-REGISTRATION ────────────────────────────────────────────────────────────────────────
# A change to any value here after R1 has run is a new pre-registration, not a bug fix (§10).
FROZEN = dict(
    rows_json_sha256   = "5bbcea4bff11396f38f8aca3e64d697a8ea1da2bc54d705da7f6e34886804c97",   # §4.1, dataset.lock
    fingerprint        = dict( CROSS=94, **{ "SPREAD-IN-FILE": 254 }, LOCAL=212 ),               # §4.4
    per_stratum_floor  = 40,          # R1
    kappa_floor        = 0.60,        # R7 — quotable
    kappa_moderate     = 0.40,        # R7 — "moderate agreement", not quotable for §9
    untagged_ceiling   = 0.50,        # §3.4 / §9 — U above this is INDETERMINATE
    stark_hi           = 0.50,        # §9 — STARK iff CI upper bound <= this
    thin_lo            = 0.60,        # §9 — THIN  iff CI lower bound >= this
    m8_jaccard_floor   = 0.70,        # M8 — plumbing check
    unavailable_floor  = 0.05,        # §4.5 — above this share, the Outcome opens by saying it is a floor
    bootstrap_seed     = 20260923,    # §7
    bootstrap_resamples= 2000,        # §7
    move_min_lines     = 3,           # M6
)
INTERNAL_CHAIN = dict( rows=377, usable=292, tagged=169, untagged=123, cross=149, local=20 )   # §2

# ── §1 / §4.4: the LEGACY fix-shape rule, verbatim ────────────────────────────────────────────────────────
# Reproduces the 2026-09-20 script exactly — including its two known looseness points (tests are NOT
# excluded; hunks are counted inside the FIRST source file's diff section). It exists only to prove the
# population is the one the 94/254/212 came from. It is never reported as the cross-context rate.
LEGACY_IDX = { ".py", ".js", ".jsx", ".ts", ".tsx", ".go", ".rs", ".java", ".rb", ".c", ".cc", ".cpp", ".h",
               ".hpp", ".cs", ".swift" }
_LEGACY_FILE = re.compile( r"^diff --git a/(\S+) b/(\S+)", re.M )
_LEGACY_HUNK = re.compile( r"^@@ ", re.M )

def legacy_shape( patch ):
    """'CROSS' | 'SPREAD-IN-FILE' | 'LOCAL' | None (no source file in the patch), by the legacy rule."""
    files = [ m.group( 2 ) for m in _LEGACY_FILE.finditer( patch ) ]
    src = [ f for f in files if any( f.endswith( e ) for e in LEGACY_IDX ) ]
    if not src:
        return None
    if len( src ) >= 2:
        return "CROSS"
    seg = patch.split( "diff --git a/%s" % src[ 0 ] )[ -1 ].split( "diff --git " )[ 0 ]
    return "LOCAL" if len( _LEGACY_HUNK.findall( seg ) ) <= 1 else "SPREAD-IN-FILE"

def fingerprint( rows ):
    """(counts, passed): the legacy counts over `rows` against FROZEN['fingerprint'] (§4.4)."""
    c = collections.Counter( legacy_shape( r[ "patch" ] ) for r in rows )
    counts = { k: c.get( k, 0 ) for k in ( "CROSS", "SPREAD-IN-FILE", "LOCAL" ) }
    return counts, counts == FROZEN[ "fingerprint" ]

# ── M1: parse the patch ────────────────────────────────────────────────────────────────────────────────────
Hunk = collections.namedtuple( "Hunk", "old_start old_len lines" )              # lines keep their +/-/space prefix
FileDiff = collections.namedtuple( "FileDiff", "old_path new_path is_rename hunks" )
_HUNK_HDR = re.compile( r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@" )

def parse_patch( patch ):
    """Unified diff → [FileDiff]. Tolerates `diff --git` headers with or without ---/+++ lines, rename
    headers, and /dev/null sides. A section with no hunks is kept (pure rename / mode change)."""
    out, cur, hunk = [], None, None
    def flush_hunk():
        nonlocal hunk
        if hunk is not None and cur is not None:
            cur.hunks.append( hunk )
        hunk = None
    for line in patch.splitlines():
        m = _LEGACY_FILE.match( line )
        if m:
            flush_hunk()
            cur = FileDiff( m.group( 1 ), m.group( 2 ), False, [] )
            out.append( cur )
            continue
        if cur is None:
            continue
        if line.startswith( "rename from " ) or line.startswith( "rename to " ):
            cur = cur._replace( is_rename=True ); out[ -1 ] = cur
            continue
        if line.startswith( "--- /dev/null" ):
            cur = cur._replace( old_path="/dev/null" ); out[ -1 ] = cur       # a brand-new file: no pre-fix side
            continue
        if line.startswith( "+++ /dev/null" ):
            cur = cur._replace( new_path="/dev/null" ); out[ -1 ] = cur       # a deleted file
            continue
        if line.startswith( "--- " ) or line.startswith( "+++ " ) or line.startswith( "index " ) \
           or line.startswith( "similarity index" ) or line.startswith( "new file mode" ) \
           or line.startswith( "deleted file mode" ) or line.startswith( "old mode" ) or line.startswith( "new mode" ):
            continue
        h = _HUNK_HDR.match( line )
        if h:
            flush_hunk()
            hunk = Hunk( int( h.group( 1 ) ), int( h.group( 2 ) if h.group( 2 ) is not None else 1 ), [] )
            continue
        if hunk is not None and ( line[ :1 ] in ( " ", "+", "-" ) or line == "" ):
            hunk.lines.append( line if line else " " )
        # "\ No newline at end of file" and anything else is ignored
    flush_hunk()
    return out

# ── M2: classify each file by path ────────────────────────────────────────────────────────────────────────
_TEST_DIRS = { "test", "tests", "testing", "spec", "specs" }
_DOC_DIRS = { "doc", "docs", "changelog.d", "changes", "news", "release-notes", "releasenotes" }
_DOC_BASENAMES = ( "CHANGELOG", "CHANGES", "NEWS", "HISTORY", "README", "AUTHORS" )
_GEN_DIRS = { "migrations", "versions" }
_GEN_HEAD = re.compile( r"generated|do not edit", re.I )

def classify_path( path, head_lines=() ):
    """'TEST' | 'DOC' | 'GENERATED' | 'SOURCE' | 'OTHERLANG' | 'NONSOURCE' — first match wins (M2).
    `head_lines` = the file's first three lines at base_commit, when the caller has them."""
    parts = path.split( "/" )
    base = parts[ -1 ]
    dirs = set( parts[ :-1 ] )
    ext = os.path.splitext( base )[ 1 ]
    if dirs & _TEST_DIRS or base.startswith( "test_" ) or base.endswith( ( "_test.py", "_tests.py" ) ) or base == "conftest.py":
        return "TEST"
    if ext in ( ".md", ".rst", ".txt" ) or dirs & _DOC_DIRS or base.upper().startswith( _DOC_BASENAMES ):
        return "DOC"
    if dirs & _GEN_DIRS or base == "_version.py" or any( _GEN_HEAD.search( l ) for l in list( head_lines )[ :3 ] ):
        return "GENERATED"
    if ext in ( ".py", ".pyi" ):
        return "SOURCE"
    if ext in LEGACY_IDX:
        return "OTHERLANG"
    return "NONSOURCE"

# ── M3: changed old lines per hunk ────────────────────────────────────────────────────────────────────────
def changed_old_lines( hunk ):
    """Old line numbers of the hunk's '-' lines; for a pure insertion, the single anchor line = the old
    line immediately preceding the insertion point (old line 1 at the top of a non-empty file)."""
    removed, old = [], hunk.old_start
    first_plus_anchor = None
    for line in hunk.lines:
        tag = line[ :1 ]
        if tag == "-":
            removed.append( old ); old += 1
        elif tag == "+":
            if first_plus_anchor is None:
                first_plus_anchor = old - 1
        else:
            old += 1
    if removed:
        return set( removed )
    if first_plus_anchor is None:
        return set()
    return { max( 1, first_plus_anchor ) } if hunk.old_len > 0 or hunk.old_start > 0 else { 0 }

# ── M4: map lines to definitions, with Python's own ast ───────────────────────────────────────────────────
Span = collections.namedtuple( "Span", "qualname start end kind" )       # kind: 'def' | 'class'

def python_definition_spans( source_text ):
    """Spans of every module-level def/async def, every class, and every method (outermost function level;
    nested defs collapse into their parent). Raises SyntaxError when the file does not parse."""
    tree = ast.parse( source_text )
    spans = []
    for node in tree.body:
        if isinstance( node, ( ast.FunctionDef, ast.AsyncFunctionDef ) ):
            spans.append( Span( node.name, _first_line( node ), node.end_lineno, "def" ) )
        elif isinstance( node, ast.ClassDef ):
            spans.append( Span( node.name, _first_line( node ), node.end_lineno, "class" ) )
            for sub in node.body:
                if isinstance( sub, ( ast.FunctionDef, ast.AsyncFunctionDef ) ):
                    spans.append( Span( "%s.%s" % ( node.name, sub.name ), _first_line( sub ), sub.end_lineno, "def" ) )
    return spans

def _first_line( node ):
    # a decorated definition starts at its first decorator: an edit to `@property` is an edit to the method
    decos = getattr( node, "decorator_list", [] )
    return min( [ node.lineno ] + [ d.lineno for d in decos ] )

def site_for_line( spans, lineno ):
    """The innermost matching span's qualname: a method beats its class; '<module>' when none."""
    best = None
    for s in spans:
        if s.start <= lineno <= s.end:
            if best is None or ( s.end - s.start ) < ( best.end - best.start ):
                best = s
    return best.qualname if best else "<module>"

# ── M5–M7: the site set and the mechanical class ──────────────────────────────────────────────────────────
SiteResult = collections.namedtuple( "SiteResult", "sites flags buckets mclass" )

def sites_for_row( patch, read_base ):
    """M1–M7 for one row. `read_base(path)` returns the pre-fix file text at base_commit, or None.
    Returns SiteResult(sites={(file, qualname)}, flags={...}, buckets=Counter of file classes, mclass)."""
    diffs = parse_patch( patch )
    sites, flags, buckets = set(), set(), collections.Counter()
    saw_test_hunk = False
    for fd in diffs:
        head = None
        text = read_base( fd.old_path ) if fd.old_path != "/dev/null" else None
        if text is not None:
            head = text.splitlines()[ :3 ]
        klass = classify_path( fd.old_path if fd.old_path != "/dev/null" else fd.new_path, head or () )
        buckets[ klass ] += 1
        if klass == "TEST":
            saw_test_hunk = saw_test_hunk or bool( fd.hunks )
            continue
        if klass in ( "DOC", "GENERATED", "NONSOURCE" ):
            continue
        if fd.is_rename and not fd.hunks:
            flags.add( "rename_only" )
            continue
        if klass == "OTHERLANG":
            if fd.hunks:
                sites.add( ( fd.old_path, "<file>" ) ); flags.add( "otherlang" )
            continue
        if not fd.hunks:
            continue
        if fd.old_path == "/dev/null" or text is None:
            # a brand-new source file: it does not exist at base_commit, so it is not a site (§12 decision 3);
            # a missing pre-fix file that SHOULD exist is a materialisation failure the caller must count.
            flags.add( "new_file" if fd.old_path == "/dev/null" else "unreadable" )
            continue
        try:
            spans = python_definition_spans( text )
        except SyntaxError:
            sites.add( ( fd.old_path, "<unparsed>" ) ); flags.add( "unparsed" )
            continue
        for h in fd.hunks:
            for ln in changed_old_lines( h ):
                sites.add( ( fd.old_path, site_for_line( spans, ln ) if ln > 0 else "<module>" ) )
    if detect_moves( diffs ):
        flags.add( "move" )
    return SiteResult( sites, flags, buckets, mechanical_class( sites, saw_test_hunk ) )

def mechanical_class( sites, saw_test_hunk ):
    if not sites:
        return "TEST-ONLY" if saw_test_hunk else "NON-CODE"
    if len( sites ) == 1:
        return "ONE-SITE"
    return "MULTI-FILE" if len( { f for f, _ in sites } ) >= 2 else "MULTI-SITE-ONE-FILE"

SCOREABLE = ( "ONE-SITE", "MULTI-SITE-ONE-FILE", "MULTI-FILE" )

# ── M6: moves ─────────────────────────────────────────────────────────────────────────────────────────────
def detect_moves( diffs ):
    """True when a block of >= FROZEN['move_min_lines'] non-blank '-' lines in one file equals (as a
    whitespace-normalised multiset) the '+' lines of some hunk in ANOTHER file."""
    def norm( lines, tag ):
        return collections.Counter( re.sub( r"\s+", " ", l[ 1: ].strip() ) for l in lines if l[ :1 ] == tag and l[ 1: ].strip() )
    removed = [ ( fd.old_path, norm( h.lines, "-" ) ) for fd in diffs for h in fd.hunks ]
    added = [ ( fd.new_path, norm( h.lines, "+" ) ) for fd in diffs for h in fd.hunks ]
    for rp, rc in removed:
        if sum( rc.values() ) < FROZEN[ "move_min_lines" ]:
            continue
        for ap, ac in added:
            if ap != rp and rc == ac:
                return True
    return False

# ── M8: cross-check against the dataset's own gold ────────────────────────────────────────────────────────
def spell( sites ):
    return { "%s:%s" % ( f, q ) for f, q in sites }

def jaccard( a, b ):
    a, b = set( a ), set( b )
    return 1.0 if not a and not b else len( a & b ) / float( len( a | b ) )

# ── R1: stratified systematic sample ──────────────────────────────────────────────────────────────────────
def stratified_systematic_sample( ids_by_stratum, floor=None ):
    """{stratum: [instance_id]} → {stratum: [sampled ids]}; within each stratum sorted, every k-th from
    index 0 with k = max(1, N_s // floor). A function of the manifest alone."""
    floor = FROZEN[ "per_stratum_floor" ] if floor is None else floor
    out = {}
    for s, ids in ids_by_stratum.items():
        ids = sorted( ids )
        k = max( 1, len( ids ) // floor )
        out[ s ] = ids[ ::k ]
    return out

# ── R6/R7: labels and agreement ───────────────────────────────────────────────────────────────────────────
def row_label( a, b ):
    """Two raters' answers → 'CROSS' | 'LOCAL' | ('UNTAGGED', sub-bucket). NOT-A-DEFECT and UNDECIDED from
    EITHER rater win over a disagreement, so the sub-buckets are disjoint."""
    if "NOT-A-DEFECT" in ( a, b ):
        return ( "UNTAGGED", "NOT-A-DEFECT" )
    if "UNDECIDED" in ( a, b ):
        return ( "UNTAGGED", "UNDECIDED" )
    if a == b and a in ( "CROSS", "LOCAL" ):
        return a
    return ( "UNTAGGED", "DISAGREE" )

def cohen_kappa( a, b ):
    """Cohen's kappa over two equal-length label sequences; 1.0 when both are constant and identical."""
    if len( a ) != len( b ) or not a:
        raise ValueError( "kappa needs two non-empty sequences of equal length" )
    n = float( len( a ) )
    cats = sorted( set( a ) | set( b ) )
    po = sum( 1 for x, y in zip( a, b ) if x == y ) / n
    pe = sum( ( a.count( c ) / n ) * ( b.count( c ) / n ) for c in cats )
    if pe == 1.0:
        return 1.0 if po == 1.0 else 0.0
    return ( po - pe ) / ( 1.0 - pe )

def kappa_verdict( kappa ):
    if kappa >= FROZEN[ "kappa_floor" ]:
        return "quotable"
    if kappa >= FROZEN[ "kappa_moderate" ]:
        return "moderate"
    return "failed"

# ── §7: estimators ────────────────────────────────────────────────────────────────────────────────────────
def wilson( k, n, z=1.959963984540054 ):
    """Wilson score interval (lo, hi) for k successes in n trials; (0, 0) when n == 0."""
    if n <= 0:
        return ( 0.0, 0.0 )
    p = k / float( n ); z2 = z * z
    denom = 1.0 + z2 / n
    centre = ( p + z2 / ( 2.0 * n ) ) / denom
    half = z * ( ( p * ( 1.0 - p ) / n + z2 / ( 4.0 * n * n ) ) ** 0.5 ) / denom
    return ( max( 0.0, centre - half ), min( 1.0, centre + half ) )

def post_stratified_estimate( strata, seed=None, resamples=None ):
    """strata = {name: dict(N=<manifest count>, labels=[ 'CROSS'|'LOCAL', ... tagged sample labels ])}.
    Returns (point, lo, hi): P = sum_s (N_s/N) * p_s, with a within-stratum bootstrap percentile interval.
    A stratum with no tagged labels contributes its weight at p_s = None and is reported by the caller;
    here it is dropped from both the point and the weights (stated, not silent: see `dropped`)."""
    seed = FROZEN[ "bootstrap_seed" ] if seed is None else seed
    resamples = FROZEN[ "bootstrap_resamples" ] if resamples is None else resamples
    live = { s: v for s, v in strata.items() if v[ "labels" ] }
    dropped = sorted( set( strata ) - set( live ) )
    N = float( sum( v[ "N" ] for v in live.values() ) )
    if N == 0:
        return dict( point=None, lo=None, hi=None, dropped=dropped )
    def estimate( draw ):
        return sum( ( v[ "N" ] / N ) * ( sum( 1 for l in draw( v[ "labels" ] ) if l == "CROSS" ) / float( len( v[ "labels" ] ) ) )
                    for v in live.values() )
    point = estimate( lambda labels: labels )
    rng = random.Random( seed )
    boots = sorted( estimate( lambda labels: [ rng.choice( labels ) for _ in labels ] ) for _ in range( resamples ) )
    lo = boots[ int( 0.025 * resamples ) ]
    hi = boots[ min( resamples - 1, int( 0.975 * resamples ) ) ]
    return dict( point=point, lo=lo, hi=hi, dropped=dropped )

# ── §9: the decision table ────────────────────────────────────────────────────────────────────────────────
def decision( lo, hi, kappa_binary, untagged_share, fingerprint_ok=True, m8_ok=True ):
    """'STARK' | 'THIN' | 'INDETERMINATE', with the clause that fired. Every gate is a pre-registered constant."""
    if not fingerprint_ok:
        return ( "INDETERMINATE", "fingerprint failed (§4.4)" )
    if not m8_ok:
        return ( "INDETERMINATE", "M8 gold agreement below floor" )
    if lo is None or hi is None:
        return ( "INDETERMINATE", "no estimate" )
    if kappa_verdict( kappa_binary ) != "quotable":
        return ( "INDETERMINATE", "binary kappa %.2f below %.2f (R7)" % ( kappa_binary, FROZEN[ "kappa_floor" ] ) )
    if untagged_share > FROZEN[ "untagged_ceiling" ]:
        return ( "INDETERMINATE", "untagged share %.2f above %.2f" % ( untagged_share, FROZEN[ "untagged_ceiling" ] ) )
    if hi <= FROZEN[ "stark_hi" ]:
        return ( "STARK", "CI upper %.3f <= %.2f" % ( hi, FROZEN[ "stark_hi" ] ) )
    if lo >= FROZEN[ "thin_lo" ]:
        return ( "THIN", "CI lower %.3f >= %.2f" % ( lo, FROZEN[ "thin_lo" ] ) )
    return ( "INDETERMINATE", "CI [%.3f, %.3f] straddles the anchors" % ( lo, hi ) )

def internal_comparator():
    c = INTERNAL_CHAIN
    lo, hi = wilson( c[ "cross" ], c[ "tagged" ] )
    return dict( rate=c[ "cross" ] / float( c[ "tagged" ] ), lo=lo, hi=hi, **c )

# ── the run (not executed as committed) ───────────────────────────────────────────────────────────────────
def _git_show( repo_dir, sha, path ):
    r = subprocess.run( [ "git", "-C", repo_dir, "show", "%s:%s" % ( sha, path ) ], capture_output=True, text=True,
                        errors="replace" )
    return r.stdout if r.returncode == 0 else None

def manifest_hash( lines ):
    return hashlib.sha256( ( "\n".join( lines ) + "\n" ).encode( "utf-8" ) ).hexdigest()

def main( argv=None ):
    ap = argparse.ArgumentParser( description="mechanical stage of the cross-context external-rate pre-registration "
                                  "(docs/research/cross-context-external-rate.md). Runs nothing without explicit inputs." )
    ap.add_argument( "--rows", required=True, help="the Loc-Bench rows JSON; refused unless its SHA-256 is the pinned one" )
    ap.add_argument( "--repos-dir", required=True, help="checkout dir written by run_locbench.py's checkout() (depth 1 is enough)" )
    ap.add_argument( "--out", required=True, help="output dir for crossctx_population.tsv, the sample and the packets" )
    a = ap.parse_args( argv )
    raw = open( a.rows, "rb" ).read()
    got = hashlib.sha256( raw ).hexdigest()
    if got != FROZEN[ "rows_json_sha256" ]:
        print( "REFUSED: rows file sha256 %s is not the pinned %s (§4.1)" % ( got, FROZEN[ "rows_json_sha256" ] ), file=sys.stderr )
        return 2
    rows = sorted( json.loads( raw ), key=lambda r: r[ "instance_id" ] )
    counts, ok = fingerprint( rows )
    print( "# fingerprint (legacy rule, verbatim): %s  %s" % ( counts, "PASS" if ok else "FAIL — STOP (§4.4)" ) )
    if not ok:
        return 3
    os.makedirs( a.out, exist_ok=True )
    lines, by_stratum, unavailable, jac = [], collections.defaultdict( list ), 0, []
    for r in rows:
        repo_dir = os.path.join( a.repos_dir, r[ "repo" ].replace( "/", "__" ) )
        have = subprocess.run( [ "git", "-C", repo_dir, "cat-file", "-e", r[ "base_commit" ] + "^{commit}" ],
                               capture_output=True ).returncode == 0 if os.path.isdir( repo_dir ) else False
        if not have:
            unavailable += 1
            lines.append( "\t".join( [ r[ "instance_id" ], r[ "repo" ], r[ "base_commit" ], "EXCLUDED-UNAVAILABLE" ] ) )
            continue
        res = sites_for_row( r[ "patch" ], lambda p, d=repo_dir, s=r[ "base_commit" ]: _git_show( d, s, p ) )
        lines.append( "\t".join( [ r[ "instance_id" ], r[ "repo" ], r[ "base_commit" ], res.mclass ] ) )
        if res.mclass in SCOREABLE:
            by_stratum[ res.mclass ].append( r[ "instance_id" ] )
            gold = set( r.get( "edit_functions", [] ) ) | set( r.get( "added_functions", [] ) )
            jac.append( jaccard( spell( res.sites ), gold ) )
    open( os.path.join( a.out, "crossctx_population.tsv" ), "w" ).write( "\n".join( lines ) + "\n" )
    print( "# manifest sha256 %s  rows=%d unavailable=%d%s" % ( manifest_hash( lines ), len( rows ), unavailable,
           "  (FLOOR — over %.0f%% unavailable, §4.5)" % ( 100 * FROZEN[ "unavailable_floor" ] ) if unavailable > FROZEN[ "unavailable_floor" ] * len( rows ) else "" ) )
    mean_j = sum( jac ) / len( jac ) if jac else 0.0
    print( "# M8 gold agreement: mean Jaccard %.3f over %d scoreable rows  %s" % ( mean_j, len( jac ),
           "PASS" if mean_j >= FROZEN[ "m8_jaccard_floor" ] else "FAIL — STOP before R1" ) )
    for s in SCOREABLE:
        print( "# %-20s N=%d" % ( s, len( by_stratum[ s ] ) ) )
    sample = stratified_systematic_sample( by_stratum )
    json.dump( sample, open( os.path.join( a.out, "crossctx_sample.json" ), "w" ), indent=1 )
    print( "# sample: %s  (packets are assembled by the rater-stage driver from this list)" % { s: len( v ) for s, v in sample.items() } )
    return 0

if __name__ == "__main__":
    sys.exit( main() )
