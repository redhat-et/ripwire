#!/usr/bin/env python3
# maphunks.py — the ONE module that maps diff hunks onto units (§4.2/§4.3). It serves the labels (FIXED_k)
# and the look-back predictors (CHURN, HOTFN, PRIOR) alike, so a mapping rule can never differ between an
# outcome and a predictor.
#
# A UNIT is (path_at_T, scope, name, ordinal): ordinal orders same-(path, scope, name) units by start line
# (overloads, §4.3). Units come from a UnitProvider:
#   FileUnits      — one unit per product-source file, spanning the whole file (the S5 file grain; no parser);
#   a function-grain provider — the independent tree-sitter parser §4.3 requires. It is NOT in this module:
#                  none is available yet (see README "Parser status"), and ripwire's own parse is never used
#                  here, by design.
# A provider answers units(path, blob_bytes) -> [(scope, name, start_line, end_line)] (1-based, inclusive).
#
# Rules, all from the registration:
#   * a hunk's OLD-side lines overlap a unit's span at the commit's own PARENT -> the unit is touched;
#   * a pure insertion (old length 0) is attributed to the unit containing its anchor line (the old-side line
#     the insertion follows; line 0 -> line 1);
#   * identity at T: the parent-side path is mapped back to T through git's rename tracking, walked commit by
#     commit along the first-parent chain (RenameTracker), then (scope, name, ordinal) must match a unit at T;
#   * a merge (CHURN only) counts through its combined diff; its old side is the FIRST parent's range.
import os, re, subprocess, sys

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
import common

HUNK_RE = re.compile( r"^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@" )
CHUNK_RE = re.compile( r"^@@@ -(\d+)(?:,(\d+))? -\d+(?:,\d+)? \+\d+(?:,\d+)? @@@" )


def unquote_path( p ):
    """git's C-style quoted path ("a\\tb") -> text; unquoted paths pass through."""
    if len( p ) >= 2 and p[ 0 ] == '"' and p[ -1 ] == '"':
        raw = p[ 1:-1 ].encode( "latin-1", "backslashreplace" ).decode( "unicode_escape" )
        return raw.encode( "latin-1", "replace" ).decode( "utf-8", "replace" )
    return p


def _strip_prefix( p, prefix ):
    p = unquote_path( p.rstrip( "\t" ) )
    if p == "/dev/null":
        return None
    return p[ len( prefix ): ] if p.startswith( prefix ) else p


def parse_unified( text ):
    """-U0 unified diff -> [(old_path|None, new_path|None, [(old_start, old_len)])]."""
    files, cur = [], None
    for line in text.split( "\n" ):
        if line.startswith( "diff --git " ):
            cur = [ None, None, [] ]
            files.append( cur )
        elif cur is None:
            continue
        elif line.startswith( "--- " ):
            cur[ 0 ] = _strip_prefix( line[ 4: ], "a/" )
        elif line.startswith( "+++ " ):
            cur[ 1 ] = _strip_prefix( line[ 4: ], "b/" )
        elif line.startswith( "rename from " ):
            cur[ 0 ] = unquote_path( line[ 12: ] )
        elif line.startswith( "rename to " ):
            cur[ 1 ] = unquote_path( line[ 10: ] )
        elif line.startswith( "@@ " ):
            m = HUNK_RE.match( line )
            if m:
                cur[ 2 ].append( ( int( m.group( 1 ) ), 1 if m.group( 2 ) is None else int( m.group( 2 ) ) ) )
    return [ tuple( f ) for f in files ]


def parse_combined( text ):
    """-c -U0 combined diff -> [(path, path, [(first_parent_start, first_parent_len)])]."""
    files, cur = [], None
    for line in text.split( "\n" ):
        if line.startswith( "diff --combined " ) or line.startswith( "diff --cc " ):
            p = unquote_path( line.split( " ", 2 )[ 2 ] )
            cur = [ p, p, [] ]
            files.append( cur )
        elif cur is not None and line.startswith( "@@@ " ):
            m = CHUNK_RE.match( line )
            if m:
                cur[ 2 ].append( ( int( m.group( 1 ) ), 1 if m.group( 2 ) is None else int( m.group( 2 ) ) ) )
    return [ tuple( f ) for f in files ]


def commit_diff( repo, sha, parent=None ):
    """The diff of a commit against its FIRST parent (the fix-unit rule), -U0, renames on."""
    parent = parent or ( sha + "^1" )
    return parse_unified( common.git( repo, "diff", "-U0", "--no-color", "--no-ext-diff", "-M", "--src-prefix=a/",
                                      "--dst-prefix=b/", parent, sha ) )


def merge_combined_diff( repo, sha ):
    return parse_combined( common.git( repo, "diff-tree", "-c", "-U0", "--no-color", "--no-ext-diff", sha ) )


def old_lines( start, length ):
    """Old-side lines a hunk touches; a pure insertion is its anchor line."""
    if length > 0:
        return ( start, start + length - 1 )
    a = max( start, 1 )
    return ( a, a )


def overlapping( spans, lo, hi ):
    """Indices of spans [(s, e)] (1-based inclusive) that overlap [lo, hi]."""
    return [ i for i, ( s, e ) in enumerate( spans ) if s <= hi and e >= lo ]


# ── units ───────────────────────────────────────────────────────────────────────────────────────────────
def with_ordinals( raw ):
    """[(scope, name, start, end)] -> [(scope, name, ordinal, start, end)] sorted by start; ordinal counts
    same-(scope, name) units in start-line order (the overload rule)."""
    seen, out = {}, []
    for scope, name, s, e in sorted( raw, key=lambda u: ( u[ 2 ], u[ 3 ], u[ 0 ], u[ 1 ] ) ):
        k = ( scope, name )
        seen[ k ] = seen.get( k, -1 ) + 1
        out.append( ( scope, name, seen[ k ], s, e ) )
    return out


def line_count( data ):
    if not data:
        return 0
    return data.count( b"\n" ) + ( 0 if data.endswith( b"\n" ) else 1 )


class FileUnits:
    """S5 file grain: a file is one unit spanning all its lines (effort = its line count, floor 1)."""
    grain = "file"

    def units( self, path, data ):
        return [ ( "", "<file>", 1, max( 1, line_count( data ) ) ) ]


class Blobs:
    """`git cat-file --batch` over one long-lived process: rev:path or blob sha -> bytes (None if missing)."""

    def __init__( self, repo ):
        self.p = subprocess.Popen( common.git_argv( repo, "cat-file", "--batch" ), env=common.git_env(), stdin=subprocess.PIPE, stdout=subprocess.PIPE )

    def get( self, spec ):
        self.p.stdin.write( ( spec + "\n" ).encode() )
        self.p.stdin.flush()
        header = self.p.stdout.readline().decode().rstrip( "\n" )
        if header.endswith( " missing" ) or header.endswith( " ambiguous" ):
            return None
        parts = header.split()
        size = int( parts[ 2 ] )
        data = self.p.stdout.read( size )
        self.p.stdout.read( 1 )
        return data if parts[ 1 ] == "blob" else None

    def close( self ):
        self.p.stdin.close()
        self.p.wait()


class UnitCache:
    """Units per (rev, path), parsed once per BLOB (identical blobs share one parse)."""

    def __init__( self, repo, provider ):
        self.repo, self.provider, self.blobs = repo, provider, Blobs( repo )
        self.by_blob, self.blob_of = {}, {}

    def blob_sha( self, rev, path ):
        k = ( rev, path )
        if k not in self.blob_of:
            out = common.git( self.repo, "rev-parse", "--verify", "-q", "%s:%s" % ( rev, path ), check=False ).strip()
            self.blob_of[ k ] = out or None
        return self.blob_of[ k ]

    def units( self, rev, path ):
        sha = self.blob_sha( rev, path )
        if sha is None:
            return []
        if sha not in self.by_blob:
            data = self.blobs.get( sha ) or b""
            self.by_blob[ sha ] = with_ordinals( self.provider.units( path, data ) )
        return self.by_blob[ sha ]


# ── rename tracking along the first-parent chain ────────────────────────────────────────────────────────
class RenameTracker:
    """Maps a path at the current first-parent commit back to its path at T. Advance it over each
    first-parent commit in order (oldest first) with that commit's first-parent diff."""

    def __init__( self ):
        self.to_t = {}          # path now -> path at T; absent = identity; None = born after T

    def path_at_t( self, path_now ):
        return self.to_t.get( path_now, path_now )

    def advance( self, files ):
        """files: parse_unified() output of ONE first-parent commit."""
        updates, dead = {}, []
        for old, new, _ in files:
            if old is None and new is not None:
                updates[ new ] = None                              # added after T
            elif old is not None and new is None:
                dead.append( old )
            elif old != new:
                updates[ new ] = self.path_at_t( old )
                dead.append( old )
        for d in dead:
            if d not in updates:
                self.to_t[ d ] = None
        self.to_t.update( updates )


def touched_units( files, units_at_parent, tracker, t_index, t_paths=None ):
    """The set of T-units a first-parent commit's hunks touch.
    files           — parse_unified() of c vs c^1
    units_at_parent — callable(path_at_parent) -> with_ordinals() units at c^1
    tracker         — RenameTracker positioned at c^1 (NOT yet advanced over c)
    t_index         — set of (path_at_T, scope, name, ordinal) in the population
    t_paths         — the population's paths at T (derived from t_index when None)
    Returns (touched set, counters): every hunk lands in exactly one of mapped / unmapped (in a population
    file but on no population unit — module-level code, a declaration, a unit born after T) / born_after_t
    (its file did not exist at T) / out_of_population (a file at T that is not product source)."""
    if t_paths is None:
        t_paths = { k[ 0 ] for k in t_index }
    hit = set()
    n = dict( hunks=0, mapped=0, unmapped=0, born_after_t=0, out_of_population=0 )
    for old, new, hunks in files:
        if old is None or not hunks:
            continue
        pt = tracker.path_at_t( old )
        if pt is None or pt not in t_paths:
            key = "born_after_t" if pt is None else "out_of_population"
            n[ "hunks" ] += len( hunks )
            n[ key ] += len( hunks )
            continue
        units = units_at_parent( old )
        spans = [ ( u[ 3 ], u[ 4 ] ) for u in units ]
        for start, length in hunks:
            n[ "hunks" ] += 1
            lo, hi = old_lines( start, length )
            mapped = False
            for i in overlapping( spans, lo, hi ):
                key = ( pt, ) + tuple( units[ i ][ :3 ] )
                if key in t_index:
                    hit.add( key )
                    mapped = True
            n[ "mapped" if mapped else "unmapped" ] += 1
    return hit, n


def name_status( repo, sha, parent=None ):
    """A first-parent commit's file-level changes only (for the rename walk over non-fix commits): the same
    shape as parse_unified() with empty hunk lists. Much cheaper than a -U0 diff."""
    parent = parent or ( sha + "^1" )
    out = common.git( repo, "diff", "--name-status", "-z", "-M", "--no-ext-diff", parent, sha )
    toks, files, i = out.split( "\x00" ), [], 0
    while i < len( toks ) and toks[ i ]:
        st = toks[ i ]
        if st[ 0 ] in "RC":
            old, new = toks[ i + 1 ], toks[ i + 2 ]
            i += 3
            files.append( ( old, new, [] ) if st[ 0 ] == "R" else ( None, new, [] ) )     # a copy is a new file
        else:
            path = toks[ i + 1 ]
            i += 2
            files.append( ( None, path, [] ) if st[ 0 ] == "A" else ( path, None, [] ) if st[ 0 ] == "D" else ( path, path, [] ) )
    return files


# ── batched forms (one git process per window instead of one per commit) ────────────────────────────────
def _split_log( out ):
    """`git log --format=%x00%H ...` output -> [(sha, text)] in log order."""
    recs = []
    for rec in out.split( "\x00" )[ 1: ]:
        sha, _, rest = rec.partition( "\n" )
        recs.append( ( sha.strip(), rest ) )
    return recs


def _parse_name_status_lines( text ):
    files = []
    for line in text.split( "\n" ):
        if not line or "\t" not in line:
            continue
        parts = line.split( "\t" )
        st = parts[ 0 ]
        if st[ 0 ] == "R":
            files.append( ( unquote_path( parts[ 1 ] ), unquote_path( parts[ 2 ] ), [] ) )
        elif st[ 0 ] == "C":
            files.append( ( None, unquote_path( parts[ 2 ] ), [] ) )
        elif st[ 0 ] == "A":
            files.append( ( None, unquote_path( parts[ 1 ] ), [] ) )
        elif st[ 0 ] == "D":
            files.append( ( unquote_path( parts[ 1 ] ), None, [] ) )
        else:
            p = unquote_path( parts[ 1 ] )
            files.append( ( p, p, [] ) )
    return files


def first_parent_name_status( repo, t_sha, last_sha ):
    """{sha: name_status()-shaped files} for every first-parent commit in (T, last], each against its first
    parent, from ONE git process."""
    out = common.git( repo, "log", "--first-parent", "--diff-merges=first-parent", "-M", "--no-ext-diff", "--format=%x00%H",
                      "--name-status", "%s..%s" % ( t_sha, last_sha ) )
    return { sha: _parse_name_status_lines( text ) for sha, text in _split_log( out ) }


def first_parent_diffs( repo, shas ):
    """{sha: commit_diff()-shaped files} for the given commits, each against its FIRST parent, -U0, from ONE git
    process (merges included, through --diff-merges=first-parent)."""
    if not shas:
        return {}
    env_in = "\n".join( shas ) + "\n"
    p = subprocess.run( common.git_argv( repo, "log", "--no-walk=unsorted", "--stdin", "--diff-merges=first-parent", "-M", "-U0", "--no-color",
                                         "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/", "--format=%x00%H" ),
                        input=env_in, capture_output=True, text=True, errors="replace", env=common.git_env() )
    if p.returncode != 0:
        raise RuntimeError( "git log --stdin failed: " + p.stderr[ :300 ] )
    return { sha: parse_unified( text ) for sha, text in _split_log( p.stdout ) }


# ── A1: the hand-check sample of fix-hunk mappings (rule fixed before any sample is drawn) ──────────────
A1_SALT = "m1-lookback-a1-handcheck-2026-09"


def a1_sample( records, n=50, salt=A1_SALT ):
    """records: [(repo, commit_sha, old_path, old_start, old_len, mapped_units)] for fix hunks that fall in a
    population file. The sample is the n records with the lowest SHA-256(salt|repo|sha|path|start|len) — a
    seeded draw no reader can steer, stable under record order."""
    import hashlib
    def k( r ):
        return hashlib.sha256( ( "%s|%s|%s|%s|%d|%d" % ( salt, r[ 0 ], r[ 1 ], r[ 2 ], r[ 3 ], r[ 4 ] ) ).encode() ).hexdigest()
    return sorted( records, key=k )[ :n ]
