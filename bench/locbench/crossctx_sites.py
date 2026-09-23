#!/usr/bin/env python3
# crossctx_sites.py — the mechanical stage of the cross-context external-rate pre-registration
# (docs/research/cross-context-external-rate.md, registered 2026-09-23, before any data; amendment 1 the
# same day after adversarial review, still before any data).
#
# WHAT THIS IS. Given a Loc-Bench row's fix patch and a reader for the pre-fix tree, compute the SITES the
# fix touched — (file, outermost function-level definition) at base_commit — and the row's mechanical class
# (ONE-SITE / MULTI-SITE-ONE-FILE / MULTI-FILE, or an excluded bucket). Plus: the legacy fix-shape rule
# recomputed VERBATIM as the population fingerprint (§4.4), the stratified systematic sampler for the rater
# stage (R1) and its one-step enlargement (§9), Wilson and post-stratified bootstrap intervals (§7), and the
# decision table (§9). The rater-stage driver (packets, label ingest, kappa, the §8 table) is
# crossctx_rater.py. Every constant a later reader might be tempted to tune is named in FROZEN below.
#
# WHAT THIS IS NOT. It does not walk history (no `git log`, no `rev-list`), does not invoke the ripwire binary
# (the recipe is deliberately independent of the tool whose motivation it measures — §12 decision 11), and
# does not label anything CROSS or LOCAL: that is the raters' step (§6). It fetches nothing unless
# `--materialise` is passed explicitly, and then only through run_locbench.py's own checkout() (§4.2).
#
# NO DATA HAS PASSED THROUGH THIS FILE. As committed, it has run only on the synthetic fixtures in
# test_crossctx_sites.py. `main()` refuses a rows file whose SHA-256 is not the one pinned in
# bench/locbench/dataset.lock, so the run can prove which population it scored (§4.1).
#
# House conventions: pure Python 3, standard library only, no pytest dependency; same as compare_runs.py.
import argparse, ast, collections, hashlib, json, os, pathlib, random, re, subprocess, sys

# ── FROZEN BY THE PRE-REGISTRATION ────────────────────────────────────────────────────────────────────────
# A change to any value here after R1 has run is a new pre-registration, not a bug fix (§10).
FROZEN = dict(
    rows_json_sha256   = "5bbcea4bff11396f38f8aca3e64d697a8ea1da2bc54d705da7f6e34886804c97",   # §4.1, dataset.lock
    fingerprint        = dict( CROSS=94, **{ "SPREAD-IN-FILE": 254 }, LOCAL=212 ),               # §4.4
    per_stratum_floor  = 40,          # R1
    enlargement_steps  = 1,           # §9 — at most ONE enlargement pass, only on the straddle clause
    enlargement_offset = "k//2",      # §9 — the second systematic pass starts at floor(k/2) within each stratum
    pilot_rows         = 10,          # R3 — first ten unsampled scoreable rows in instance_id order; never estimated
    rater_tool_budget  = 25,          # R3 — tree reads per row per rater; over budget = UNDECIDED
    rater_output_tokens= 1500,        # R3 — output budget per row per rater; over budget = UNDECIDED
    rater_families     = ( "anthropic-claude", "openai-gpt" ),   # R3 — the PREFERRED pair: two different model families
    # R3 — the FALLBACK pair, used if and only if a second family is unavailable at run time, decided before any
    # packet is built: two different Claude model lines/generations, strictly separate contexts per row, kappa floor
    # unchanged, disclosed in the Outcome as WEAKER independence. A same-family result is never restated as two-family.
    rater_families_fallback = ( "anthropic-claude-opus-5.5", "anthropic-claude-sonnet-5" ),
    kappa_floor        = 0.60,        # R7 — quotable
    kappa_moderate     = 0.40,        # R7 — "moderate agreement", not quotable for §9
    untagged_ceiling   = 0.50,        # §3.4 / §9 — U above this is INDETERMINATE
    stark_hi           = 0.50,        # §9 — STARK iff CI upper bound <= this
    thin_lo            = 0.60,        # §9 — THIN  iff CI lower bound >= this
    m8_recall_floor    = 0.70,        # M8 — plumbing check: recall of gold edit_functions in SOURCE files
    unavailable_floor  = 0.05,        # §4.5 — above this share, the estimate is of the materialised sub-population
    bootstrap_seed     = 20260923,    # §7
    bootstrap_resamples= 2000,        # §7
    move_min_lines     = 3,           # M6
)
INTERNAL_CHAIN = dict( rows=377, usable=292, tagged=169, untagged=123, cross=149, local=20 )   # §2
# §3.4 / amendment 1: the same chain with the ledger's "not a code defect" class (klass d) removed.
INTERNAL_CHAIN_CODE_ONLY = dict( rows=377, usable=209, tagged=124, untagged=85, cross=109, local=15 )

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

def file_identity( fd ):
    """The pre-fix path when there is one, else the new path (a brand-new file). Used wherever two hunks
    must be compared for 'same file or another file' (M6): a rename is the same file."""
    return fd.old_path if fd.old_path != "/dev/null" else fd.new_path

# ── M2: classify each file by path ────────────────────────────────────────────────────────────────────────
_TEST_DIRS = { "test", "tests", "testing", "spec", "specs" }
_DOC_DIRS = { "doc", "docs", "changelog.d", "changes", "news", "release-notes", "releasenotes" }
_DOC_BASENAMES = ( "CHANGELOG", "CHANGES", "NEWS", "HISTORY", "README", "AUTHORS" )
_GEN_DIRS = { "migrations", "versions" }
_GEN_COMMENT = re.compile( r"^\s*#.*(auto-?generated|automatically generated|generated by|do not edit)", re.I )
CODE_EXTS = { ".py", ".pyi" } | LEGACY_IDX

def test_rule_basis( path ):
    """'basename' when a test BASENAME rule fires, 'dir' when only the directory rule does, else None.
    The directory rule is the lossy one (product source under `pkg/test/` or `pkg/testing/` is excluded
    by it), so rows that rest on it alone are counted and carried as a sensitivity (§7)."""
    parts = path.split( "/" )
    base = parts[ -1 ]
    if base.startswith( "test_" ) or base.endswith( ( "_test.py", "_tests.py" ) ) or base == "conftest.py":
        return "basename"
    if set( parts[ :-1 ] ) & _TEST_DIRS:
        return "dir"
    return None

def classify_path( path, head_lines=() ):
    """'TEST' | 'DOC' | 'GENERATED' | 'SOURCE' | 'OTHERLANG' | 'NONSOURCE' — first match wins (M2, amended).
    `head_lines` = the file's first three lines at base_commit, when the caller has them. The DOC directory
    and basename rules apply only to NON-code extensions (`pkg/history.py`, `docs/conf.py` are SOURCE); the
    GENERATED header rule reads COMMENT lines only, never a docstring's prose."""
    parts = path.split( "/" )
    base = parts[ -1 ]
    dirs = set( parts[ :-1 ] )
    ext = os.path.splitext( base )[ 1 ]
    is_code = ext in CODE_EXTS
    if test_rule_basis( path ):
        return "TEST"
    if ext in ( ".md", ".rst", ".txt" ) or ( not is_code and ( dirs & _DOC_DIRS or base.upper().startswith( _DOC_BASENAMES ) ) ):
        return "DOC"
    if dirs & _GEN_DIRS or base == "_version.py" or any( _GEN_COMMENT.match( l ) for l in list( head_lines )[ :3 ] ):
        return "GENERATED"
    if ext in ( ".py", ".pyi" ):
        return "SOURCE"
    if ext in LEGACY_IDX:
        return "OTHERLANG"
    return "NONSOURCE"

# ── M3: changed old lines per hunk, and the insertion anchor ──────────────────────────────────────────────
_NEW_DEF = re.compile( r"^(\s*)(@|(async\s+)?def\b|class\b)" )

def changed_old_lines( hunk ):
    """Old line numbers of the hunk's '-' lines (empty for a pure insertion — see insertion_anchor)."""
    removed, old = [], hunk.old_start
    for line in hunk.lines:
        tag = line[ :1 ]
        if tag == "-":
            removed.append( old ); old += 1
        elif tag != "+":
            old += 1
    return set( removed )

def insertion_anchor( hunk ):
    """For a pure insertion: (anchor, new_def_indent). anchor = the old line immediately preceding the
    insertion point (old line 1 at the top of a non-empty file; 0 for an empty file). new_def_indent = the
    indent of the first non-blank '+' line when that line begins a definition (`@`, `def`, `async def`,
    `class`), else None. (None, None) when the hunk has '-' lines or no '+' lines."""
    if changed_old_lines( hunk ):
        return ( None, None )
    old, anchor, indent, first_plus_seen = hunk.old_start, None, None, False
    for line in hunk.lines:
        tag = line[ :1 ]
        if tag == "+":
            if anchor is None:
                anchor = old - 1
            if not first_plus_seen and line[ 1: ].strip():
                first_plus_seen = True
                m = _NEW_DEF.match( line[ 1: ] )
                if m:
                    indent = len( m.group( 1 ).expandtabs( 8 ) )
        else:
            old += 1
    if anchor is None:
        return ( None, None )
    if hunk.old_len == 0 and hunk.old_start == 0:
        return ( 0, indent )
    return ( max( 1, anchor ), indent )

# ── M4: map lines to definitions, with Python's own ast ───────────────────────────────────────────────────
Span = collections.namedtuple( "Span", "qualname start end kind col" )       # kind: 'def' | 'class'
_CONTAINERS = tuple( t for t in ( getattr( ast, "If", None ), getattr( ast, "Try", None ), getattr( ast, "TryStar", None ),
                                  getattr( ast, "With", None ), getattr( ast, "AsyncWith", None ) ) if t is not None )

def _statements( body ):
    """Statements in `body`, descending through if/try/with containers (a def under `if TYPE_CHECKING:`
    or in an `except:` fallback is still a module- or class-level definition to a reader)."""
    for s in body:
        if isinstance( s, _CONTAINERS ):
            for field in ( "body", "orelse", "finalbody" ):
                yield from _statements( getattr( s, field, None ) or [] )
            for h in getattr( s, "handlers", [] ) or []:
                yield from _statements( h.body )
        else:
            yield s

def python_definition_spans( source_text ):
    """Spans of every module-level def/async def, every class, and every method (outermost function level;
    nested functions collapse into their parent), including definitions under module- or class-level
    if/try/with. Raises SyntaxError when the file does not parse."""
    tree = ast.parse( source_text )
    spans = []
    for node in _statements( tree.body ):
        if isinstance( node, ( ast.FunctionDef, ast.AsyncFunctionDef ) ):
            spans.append( Span( node.name, _first_line( node ), node.end_lineno, "def", node.col_offset ) )
        elif isinstance( node, ast.ClassDef ):
            spans.append( Span( node.name, _first_line( node ), node.end_lineno, "class", node.col_offset ) )
            for sub in _statements( node.body ):
                if isinstance( sub, ( ast.FunctionDef, ast.AsyncFunctionDef ) ):
                    spans.append( Span( "%s.%s" % ( node.name, sub.name ), _first_line( sub ), sub.end_lineno, "def", sub.col_offset ) )
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

def site_for_new_definition( spans, anchor, indent ):
    """M3/§12.3: a pure insertion that BEGINS a definition is attributed to the CONTAINER the new definition
    belongs to, not to whatever definition git's hunk placement happened to end on: indent 0 → '<module>';
    otherwise the innermost span containing the anchor whose own column is shallower than the new indent
    (a class for a new method; a method for a new nested def); '<module>' when none contains it."""
    if indent == 0 or anchor <= 0:
        return "<module>"
    best = None
    for s in spans:
        if s.start <= anchor <= s.end and s.col < indent:
            if best is None or ( s.end - s.start ) < ( best.end - best.start ):
                best = s
    return best.qualname if best else "<module>"

# ── M5–M7: the site set and the mechanical class ──────────────────────────────────────────────────────────
SiteResult = collections.namedtuple( "SiteResult", "sites flags buckets mclass collapsed_sites mclass_collapsed test_dir_only" )

def sites_for_row( patch, read_base ):
    """M1–M7 for one row. `read_base(path)` returns the pre-fix file text at base_commit, or None.
    Returns SiteResult: sites={(file, qualname)}, flags, buckets=Counter of file classes, mclass, plus the
    moves-collapsed site set and class (M6 sensitivity) and whether a TEST-ONLY verdict rests on the
    directory rule alone (M2 sensitivity)."""
    diffs = parse_patch( patch )
    per_hunk, flags, buckets = {}, set(), collections.Counter()     # (identity, hunk_idx) -> {sites}
    saw_test_hunk, test_basis = False, set()
    for fd in diffs:
        ident = file_identity( fd )
        text = read_base( fd.old_path ) if fd.old_path != "/dev/null" else None
        head = text.splitlines()[ :3 ] if text is not None else ()
        klass = classify_path( ident, head )
        buckets[ klass ] += 1
        if klass == "TEST":
            if fd.hunks:
                saw_test_hunk = True
                test_basis.add( test_rule_basis( ident ) )
            continue
        if klass in ( "DOC", "GENERATED", "NONSOURCE" ):
            continue
        if fd.is_rename and not fd.hunks:
            flags.add( "rename_only" )
            continue
        if not fd.hunks:
            continue
        if fd.old_path == "/dev/null":
            # a brand-new source file does not exist at base_commit, so it is not a site (§12 decision 3)
            flags.add( "new_file" )
            continue
        if klass == "OTHERLANG":
            flags.add( "otherlang" )
            for i, h in enumerate( fd.hunks ):
                per_hunk[ ( ident, i ) ] = { ( fd.old_path, "<file>" ) }
            continue
        if text is None:
            # a pre-fix file that SHOULD exist and could not be read: a materialisation failure. The row is
            # routed to EXCLUDED-UNREADABLE below, never to NON-CODE.
            flags.add( "unreadable" )
            continue
        try:
            spans = python_definition_spans( text )
        except SyntaxError:
            flags.add( "unparsed" )
            for i, h in enumerate( fd.hunks ):
                per_hunk[ ( ident, i ) ] = { ( fd.old_path, "<unparsed>" ) }
            continue
        for i, h in enumerate( fd.hunks ):
            got = set()
            removed = changed_old_lines( h )
            if removed:
                got = { ( fd.old_path, site_for_line( spans, ln ) ) for ln in removed }
            else:
                anchor, indent = insertion_anchor( h )
                if anchor is not None:
                    q = site_for_new_definition( spans, anchor, indent ) if indent is not None \
                        else ( site_for_line( spans, anchor ) if anchor > 0 else "<module>" )
                    got = { ( fd.old_path, q ) }
            per_hunk[ ( ident, i ) ] = got
    sites = set().union( *per_hunk.values() ) if per_hunk else set()
    move_sources = detect_moves( diffs )
    if move_sources:
        flags.add( "move" )
    kept = [ v for k, v in per_hunk.items() if k not in move_sources ]
    collapsed = set().union( *kept ) if kept else set()
    if "unreadable" in flags:
        mclass = "EXCLUDED-UNREADABLE"
    else:
        mclass = mechanical_class( sites, saw_test_hunk, "new_file" in flags )
    test_dir_only = mclass == "TEST-ONLY" and test_basis == { "dir" }
    if test_dir_only:
        flags.add( "test_dir_only" )
    mclass_collapsed = mclass if mclass.startswith( "EXCLUDED" ) else mechanical_class( collapsed, saw_test_hunk, "new_file" in flags )
    return SiteResult( sites, flags, buckets, mclass, collapsed, mclass_collapsed, test_dir_only )

def mechanical_class( sites, saw_test_hunk, new_file_only=False ):
    if not sites:
        if saw_test_hunk:
            return "TEST-ONLY"
        return "NEW-FILE-ONLY" if new_file_only else "NON-CODE"
    if len( sites ) == 1:
        return "ONE-SITE"
    return "MULTI-FILE" if len( { f for f, _ in sites } ) >= 2 else "MULTI-SITE-ONE-FILE"

SCOREABLE = ( "ONE-SITE", "MULTI-SITE-ONE-FILE", "MULTI-FILE" )
EXCLUDED = ( "EXCLUDED-UNAVAILABLE", "EXCLUDED-UNREADABLE", "NON-CODE", "TEST-ONLY", "NEW-FILE-ONLY" )

# ── M6: moves ─────────────────────────────────────────────────────────────────────────────────────────────
def _norm_lines( lines, tag ):
    return collections.Counter( re.sub( r"\s+", " ", l[ 1: ].strip() ) for l in lines if l[ :1 ] == tag and l[ 1: ].strip() )

def detect_moves( diffs ):
    """The SOURCE hunks of moves: {(file_identity, hunk_idx)} for every hunk whose non-blank '-' lines, as a
    whitespace-normalised multiset of >= FROZEN['move_min_lines'] lines, equal the non-blank '+' lines of a
    hunk in ANOTHER file (file identity = pre-fix path; a rename is the same file). Whole-hunk equality: a
    destination hunk that also adds an import defeats it, which under-flags moves and is stated (M6)."""
    removed = [ ( file_identity( fd ), i, _norm_lines( h.lines, "-" ) ) for fd in diffs for i, h in enumerate( fd.hunks ) ]
    added = [ ( file_identity( fd ), _norm_lines( h.lines, "+" ) ) for fd in diffs for h in fd.hunks ]
    out = set()
    for rp, ri, rc in removed:
        if sum( rc.values() ) < FROZEN[ "move_min_lines" ]:
            continue
        if any( ap != rp and rc == ac for ap, ac in added ):
            out.add( ( rp, ri ) )
    return out

# ── M8: cross-check against the dataset's own gold ────────────────────────────────────────────────────────
def spell( sites ):
    return { "%s:%s" % ( f, q ) for f, q in sites }

def jaccard( a, b ):
    a, b = set( a ), set( b )
    return 1.0 if not a and not b else len( a & b ) / float( len( a | b ) )

def gold_recall( sites, edit_functions ):
    """M8 (amended): the share of Loc-Bench `edit_functions` whose file is SOURCE under M2 that appear in
    S, spelled `path:Class.method` / `path:func` exactly as the dataset spells them. None when the row has
    no such gold (nothing to recall). `added_functions` are never in S by construction and are not gold
    here; a nested gold `outer.inner` cannot be recalled (S collapses it to `outer`) — a stated loss."""
    gold = { e for e in edit_functions if ":" in e and classify_path( e.split( ":", 1 )[ 0 ] ) == "SOURCE" }
    if not gold:
        return None
    return len( gold & spell( sites ) ) / float( len( gold ) )

# ── R1: stratified systematic sample, and the §9 one-step enlargement ─────────────────────────────────────
def _step( n, floor ):
    return max( 1, n // floor )

def stratified_systematic_sample( ids_by_stratum, floor=None, offset=0 ):
    """{stratum: [instance_id]} → {stratum: [sampled ids]}; within each stratum sorted, every k-th from
    index `offset` (an int, or a callable of k) with k = max(1, N_s // floor). A function of the manifest
    alone. A stratum of 79 is taken whole (k = 1); one of 80 gives 40 (k = 2); one of 250 gives 42 (k = 6)."""
    floor = FROZEN[ "per_stratum_floor" ] if floor is None else floor
    out = {}
    for s, ids in ids_by_stratum.items():
        ids = sorted( ids )
        k = _step( len( ids ), floor )
        start = min( offset( k ) if callable( offset ) else offset, max( 0, k - 1 ) )
        out[ s ] = ids[ start::k ]
    return out

def enlargement_sample( ids_by_stratum, first_sample, floor=None ):
    """§9: the ONE permitted enlargement — a second systematic pass at offset floor(k/2) within each
    stratum, unioned with the first sample. When k == 1 the stratum was already taken whole and nothing is
    added. Returns {stratum: [ids]} with the union, sorted."""
    second = stratified_systematic_sample( ids_by_stratum, floor, offset=lambda k: k // 2 )
    return { s: sorted( set( first_sample.get( s, [] ) ) | set( second.get( s, [] ) ) ) for s in ids_by_stratum }

def pilot_rows( scoreable_ids, sample_ids, n=None ):
    """R3: the first `n` scoreable rows in instance_id order that are NOT in the R1 sample. Fixed by the
    manifest; used once to check the wording is answerable; never enter any estimate."""
    n = FROZEN[ "pilot_rows" ] if n is None else n
    taken = set( sample_ids )
    return [ i for i in sorted( scoreable_ids ) if i not in taken ][ :n ]

# ── R6/R7: labels and agreement ───────────────────────────────────────────────────────────────────────────
def row_label( a, b ):
    """Two raters' verdicts → 'CROSS' | 'LOCAL' | ('UNTAGGED', sub-bucket). NOT-A-DEFECT and UNDECIDED from
    EITHER rater win over a disagreement, so the sub-buckets are disjoint."""
    if "NOT-A-DEFECT" in ( a, b ):
        return ( "UNTAGGED", "NOT-A-DEFECT" )
    if "UNDECIDED" in ( a, b ):
        return ( "UNTAGGED", "UNDECIDED" )
    if a == b and a in ( "CROSS", "LOCAL" ):
        return a
    return ( "UNTAGGED", "DISAGREE" )

def three_way( verdict ):
    """R7's 3-way category for one rater's verdict: CROSS / LOCAL / other."""
    return verdict if verdict in ( "CROSS", "LOCAL" ) else "other"

def cohen_kappa( a, b ):
    """Cohen's kappa over two equal-length sequences of hashable labels; 1.0 when both are constant and
    identical. Labels are compared by equality, never ordered, so mixed str/tuple sequences are accepted."""
    if len( a ) != len( b ) or not a:
        raise ValueError( "kappa needs two non-empty sequences of equal length" )
    n = float( len( a ) )
    cats = list( { c: None for c in list( a ) + list( b ) } )
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
    A stratum with no tagged labels is dropped from both the point and the weights and NAMED in `dropped`
    (stated, not silent)."""
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
    """'STARK' | 'THIN' | 'INDETERMINATE', with the clause that fired. Every gate is a pre-registered constant.
    The clause text 'straddles the anchors' is the ONLY one on which §9's one-step enlargement may run."""
    if not fingerprint_ok:
        return ( "INDETERMINATE", "fingerprint failed (§4.4)" )
    if not m8_ok:
        return ( "INDETERMINATE", "M8 gold recall below floor" )
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

def enlargement_permitted( verdict_clause, steps_taken ):
    """§9: the one enlargement runs only on the straddle clause and only once."""
    return verdict_clause.endswith( "straddles the anchors" ) and steps_taken < FROZEN[ "enlargement_steps" ]

def internal_comparator( chain=None ):
    c = INTERNAL_CHAIN if chain is None else chain
    lo, hi = wilson( c[ "cross" ], c[ "tagged" ] )
    return dict( rate=c[ "cross" ] / float( c[ "tagged" ] ), lo=lo, hi=hi, **c )

# ── the run (not executed as committed) ───────────────────────────────────────────────────────────────────
MANIFEST_COLUMNS = ( "instance_id", "repo", "base_commit", "mclass", "n_sites", "flags", "mclass_collapsed" )

def _git_show( repo_dir, sha, path ):
    r = subprocess.run( [ "git", "-C", str( repo_dir ), "show", "%s:%s" % ( sha, path ) ], capture_output=True, text=True,
                        errors="replace" )
    return r.stdout if r.returncode == 0 else None

def _has_commit( repo_dir, sha ):
    return os.path.isdir( str( repo_dir ) ) and subprocess.run( [ "git", "-C", str( repo_dir ), "cat-file", "-e", sha + "^{commit}" ],
                                                                 capture_output=True ).returncode == 0

def manifest_line( instance_id, repo, base_commit, mclass, n_sites=0, flags=(), mclass_collapsed=None ):
    return "\t".join( [ instance_id, repo, base_commit, mclass, str( n_sites ), ",".join( sorted( flags ) ) or "-",
                        mclass_collapsed or mclass ] )

def manifest_hash( lines ):
    return hashlib.sha256( ( "\n".join( lines ) + "\n" ).encode( "utf-8" ) ).hexdigest()

def main( argv=None ):
    ap = argparse.ArgumentParser( description="mechanical stage of the cross-context external-rate pre-registration "
                                  "(docs/research/cross-context-external-rate.md). Runs nothing without explicit inputs." )
    ap.add_argument( "--rows", required=True, help="the Loc-Bench rows JSON; refused unless its SHA-256 is the pinned one" )
    ap.add_argument( "--repos-dir", required=True, help="checkout dir in run_locbench.py's layout (one dir per repo, owner__name)" )
    ap.add_argument( "--out", required=True, help="output dir for crossctx_population.tsv, the sample, the pilot list" )
    ap.add_argument( "--materialise", action="store_true",
                     help="§4.2: fetch each row's base_commit at depth 1 through run_locbench.checkout() (network; owner's go-ahead)" )
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
    repos_dir = pathlib.Path( a.repos_dir )
    if a.materialise:
        sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )
        from run_locbench import checkout                      # one dir per repo; per-sha shallow fetch; fails closed
        for repo, sha in sorted( { ( r[ "repo" ], r[ "base_commit" ] ) for r in rows } ):
            if checkout( repo, sha, repos_dir, 1 ) is None:
                print( "# MATERIALISE FAIL %s@%s (counted as EXCLUDED-UNAVAILABLE)" % ( repo, sha ), file=sys.stderr )
    lines, by_stratum, flag_counts, class_counts = [], collections.defaultdict( list ), collections.Counter(), collections.Counter()
    excluded_by_repo, recalls, jacs = collections.defaultdict( list ), [], []
    for r in rows:
        repo_dir = repos_dir / r[ "repo" ].replace( "/", "__" )
        if not _has_commit( repo_dir, r[ "base_commit" ] ):
            lines.append( manifest_line( r[ "instance_id" ], r[ "repo" ], r[ "base_commit" ], "EXCLUDED-UNAVAILABLE" ) )
            class_counts[ "EXCLUDED-UNAVAILABLE" ] += 1
            excluded_by_repo[ r[ "repo" ] ].append( r[ "instance_id" ] )
            continue
        res = sites_for_row( r[ "patch" ], lambda p, d=repo_dir, s=r[ "base_commit" ]: _git_show( d, s, p ) )
        lines.append( manifest_line( r[ "instance_id" ], r[ "repo" ], r[ "base_commit" ], res.mclass, len( res.sites ), res.flags, res.mclass_collapsed ) )
        class_counts[ res.mclass ] += 1
        for f in res.flags:
            flag_counts[ f ] += 1
        if res.mclass == "EXCLUDED-UNREADABLE":
            excluded_by_repo[ r[ "repo" ] ].append( r[ "instance_id" ] )
        if res.mclass in SCOREABLE:
            by_stratum[ res.mclass ].append( r[ "instance_id" ] )
            rc = gold_recall( res.sites, r.get( "edit_functions", [] ) )
            if rc is not None:
                recalls.append( rc )
            jacs.append( jaccard( spell( res.sites ), set( r.get( "edit_functions", [] ) ) ) )
    open( os.path.join( a.out, "crossctx_population.tsv" ), "w" ).write( "\t".join( MANIFEST_COLUMNS ) + "\n" + "\n".join( lines ) + "\n" )
    n_unavail = class_counts[ "EXCLUDED-UNAVAILABLE" ] + class_counts[ "EXCLUDED-UNREADABLE" ]
    floor_note = "  (FLOOR — %d unavailable/unreadable rows > %.0f%%: the estimate is of the MATERIALISED sub-population, §4.5)" \
                 % ( n_unavail, 100 * FROZEN[ "unavailable_floor" ] ) if n_unavail > FROZEN[ "unavailable_floor" ] * len( rows ) else ""
    print( "# manifest sha256 %s  rows=%d%s" % ( manifest_hash( lines ), len( rows ), floor_note ) )
    for k in EXCLUDED + SCOREABLE:
        print( "# %-22s %d" % ( k, class_counts[ k ] ) )
    print( "# flags: %s" % dict( sorted( flag_counts.items() ) ) )
    if excluded_by_repo:
        print( "# excluded rows per repository (unavailable or unreadable):" )
        for repo, ids in sorted( excluded_by_repo.items() ):
            print( "#   %-40s %d  %s" % ( repo, len( ids ), " ".join( ids ) ) )
    mean_rc = sum( recalls ) / len( recalls ) if recalls else 0.0
    print( "# M8 gold recall: %.3f over %d scoreable rows with SOURCE gold  %s   (Jaccard, descriptive: %.3f over %d)"
           % ( mean_rc, len( recalls ), "PASS" if mean_rc >= FROZEN[ "m8_recall_floor" ] else "FAIL — STOP before R1",
               sum( jacs ) / len( jacs ) if jacs else 0.0, len( jacs ) ) )
    sample = stratified_systematic_sample( by_stratum )
    json.dump( sample, open( os.path.join( a.out, "crossctx_sample.json" ), "w" ), indent=1 )
    scoreable_ids = [ i for ids in by_stratum.values() for i in ids ]
    pilot = pilot_rows( scoreable_ids, [ i for ids in sample.values() for i in ids ] )
    json.dump( pilot, open( os.path.join( a.out, "crossctx_pilot.json" ), "w" ), indent=1 )
    print( "# sample: %s  pilot: %d rows  (packets are built by crossctx_rater.py from these lists)"
           % ( { s: len( v ) for s, v in sample.items() }, len( pilot ) ) )
    return 0

if __name__ == "__main__":
    sys.exit( main() )
