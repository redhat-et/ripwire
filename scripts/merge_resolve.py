#!/usr/bin/env python3
"""merge_resolve.py — resolve the merge conflicts that have a mechanical answer; leave every other one.

Run by scripts/merge_main.sh while a merge is stopped on conflicts (the conflict style must be diff3, so a
hunk carries its base). For each unmerged path it resolves only these hunk classes and leaves the rest
with their markers:

  (a) LIST   test/regression.sh absorb-list lines (`    name \\`) on every side: a 3-way SET merge (both
             sides' additions kept, both sides' removals applied), then byte-sorted.
  (r) RESHAPE test/regression.sh, once per branch that predates the one-name-per-line list: a hunk where one
             side still holds the old one-line `for _g in a b c; do` list, and is otherwise identical to the
             base, against the new list on the other side. The names of all three sides are set-merged (as
             in (a)) into the new side's list. An old side that changed any other line stays a conflict.
  (c) GEN    in a gatecount site file only (docs/gatecount_build.py's SITES: README.md, docs/EVALS.md, the
             deck), a hunk whose every non-blank line on both sides carries a generator marker
             (`<!-- gatecount -->`, `// gatecount`) or is the README cap-inventory sentence, and whose two
             sides differ ONLY in the spans a generator owns (the gate count's SPELLINGS, the cap
             sentence's two numbers, the "counts snapshot YYYY-MM-DD" date), or ONE side differs from the base only in those spans (it just re-ran
             the generator) while the other also edited the prose (2026-11-02: the counts-snapshot rewording
             met every open branch that had regenerated a count). Every other figure is compared literally, with
             the sign or qualifier glued to it (~210, 200+, -200, 70%), so
             a hand-written number, or prose edited on both sides, stays a conflict. The side carrying the
             prose edit is taken (the other side when neither does); a prose side that changed any non-owned number
             stays a conflict, and merge_main.sh then re-runs the
             generator that owns those spans (the value is recomputed, not chosen).
             docs/LIMITS.md and docs/TUNING.md are generated whole: the file is taken and rebuilt.
  (b) PIN    files the binary's own output pins (test/printf_parity.manifest, docs/COMMANDS.md,
             docs/captures/*): the other side's text is taken and the path is reported as REGEN-AFTER-BUILD,
             because the right bytes exist only after the merged tree is built.

Everything else is (d), real content: left for a person. Output (stdout), one line per path:
    RESOLVED <path> <class counts>    fully resolved and `git add`-ed
    PARTIAL  <path> <counts> left=<n> some hunks left with markers
    UNTOUCHED <path> left=<n>
    REGEN    <path>                   needs the merged binary to regenerate
Exit 0 when nothing is left, 1 when any (d) hunk remains, 2 on a usage or git error.
"""
import os, re, subprocess, sys

WHOLE_GENERATED = { 'docs/LIMITS.md', 'docs/TUNING.md' }
BIN_PINNED      = ( 'test/printf_parity.manifest', 'docs/COMMANDS.md', 'docs/captures/' )
LIST_LINE       = re.compile( r'^    [A-Za-z0-9_.-]+ \\$' )
GEN_LINE        = re.compile( r'<!--\s*gatecount\s*-->|//\s*gatecount(?![A-Za-z0-9_])|\b[0-9]+ compile-time caps and [0-9]+ ranking parameters\b' )

def generator_constants():
    """The site files and the number spellings the generators own, read from the generators' own source (they
    run at import, so they are parsed, not imported): one list, so this file and the generators cannot drift.
    Returns ( site files, [ owned-number patterns ] ); exits 2 when a generator no longer declares them."""
    import ast
    here = os.path.join( os.path.dirname( os.path.abspath( __file__ ) ), '..', 'docs' )
    found = {}
    for gen, names in ( ( 'gatecount_build.py', ( 'SITES', 'SPELLINGS', 'SNAPSHOT_DATE' ) ), ( 'limits_build.py', ( '_pat', ) ) ):
        try:
            tree = ast.parse( open( os.path.join( here, gen ), encoding = 'utf-8' ).read() )
        except ( OSError, SyntaxError ):                        # the generator itself is mid-conflict: use ours
            try:
                tree = ast.parse( git( 'show', 'HEAD:docs/' + gen ) )
            except SyntaxError as e:
                sys.stderr.write( 'merge_resolve: cannot parse docs/%s: %s\n' % ( gen, e ) ); sys.exit( 2 )
        for node in ast.walk( tree ):
            if isinstance( node, ast.Assign ) and len( node.targets ) == 1 and isinstance( node.targets[ 0 ], ast.Name ) \
               and node.targets[ 0 ].id in names and node.targets[ 0 ].id not in found:
                found[ node.targets[ 0 ].id ] = eval( compile( ast.Expression( node.value ), gen, 'eval' ), { 're': re } )
    missing = [ n for n in ( 'SITES', 'SPELLINGS', 'SNAPSHOT_DATE', '_pat' ) if n not in found ]
    if missing:
        sys.stderr.write( 'merge_resolve: docs/gatecount_build.py or docs/limits_build.py no longer declares %s\n' % ', '.join( missing ) )
        sys.exit( 2 )
    # limits_build's README sentence pattern captures both numbers as groups 1 and 3; mask exactly those spans
    capPat = found[ '_pat' ]
    capOwned = lambda line: capPat.sub( lambda m: '#' + m.group( 2 ) + '#' + m.group( 4 ), line )
    # the snapshot date a marked line carries ("counts snapshot YYYY-MM-DD") is generator-owned text too
    spell = list( found[ 'SPELLINGS' ] ) + [ found[ 'SNAPSHOT_DATE' ] ]
    return set( found[ 'SITES' ] ), lambda line: capOwned( _subAll( spell, line ) )

def _subAll( pats, line ):
    for p in pats:
        line = p.sub( '#', line )
    return line

GEN_SITES, MASK_OWNED = None, None
# a figure as gen_side compares it: the digits plus any sign/qualifier before (~ ≈ < > ± + - −) and after (+ % ×)
# and inner separators, so a prose edit that keeps the digits but changes what they claim is still a change
NUMBER = re.compile( r'[~≈<>±+\-−]*[0-9]+(?:[.,][0-9]+)*[+%×]*' )

def git( *args, check = True ):
    p = subprocess.run( [ 'git' ] + list( args ), capture_output = True, text = True )
    if check and p.returncode != 0:
        sys.stderr.write( 'merge_resolve: git %s failed: %s' % ( ' '.join( args ), p.stderr ) )
        sys.exit( 2 )
    return p.stdout

def parse( text ):
    """Split a diff3-marked file into ( kind, payload ) chunks: ( 'text', [lines] ) or ( 'hunk', (ours, base, theirs, raw) )."""
    lines = text.split( '\n' )
    out, i, plain = [], 0, []
    while i < len( lines ):
        if lines[ i ].startswith( '<<<<<<< ' ):
            if plain:
                out.append( ( 'text', plain ) ); plain = []
            raw, ours, base, theirs, part = [ lines[ i ] ], [], None, [], 'ours'
            i += 1
            while i < len( lines ) and not lines[ i ].startswith( '>>>>>>> ' ):
                ln = lines[ i ]; raw.append( ln )
                if ln.startswith( '||||||| ' ):
                    part = 'base'; base = []
                elif ln == '=======':
                    part = 'theirs'
                elif part == 'ours':
                    ours.append( ln )
                elif part == 'base':
                    base.append( ln )
                else:
                    theirs.append( ln )
                i += 1
            if i >= len( lines ):
                return None                                     # an unterminated hunk: not ours to touch
            raw.append( lines[ i ] )
            out.append( ( 'hunk', ( ours, base, theirs, raw ) ) )
        else:
            plain.append( lines[ i ] )
        i += 1
    if plain:
        out.append( ( 'text', plain ) )
    return out

OLD_LIST = re.compile( r'^for _g in ([A-Za-z0-9_. -]+); do$' )

def reshape_sides( ours, base, theirs ):
    """The one-time reshape: one side still has the OLD one-line list (`for _g in a b c; do`) where the base has
    it too, and the other side has the NEW one-name-per-line list. Returns ( new side's lines, merged names )
    or None. The old side must equal the base on every line except its `for` line (so its only change is to
    the names); otherwise it changed loop code as well, and that is a real conflict."""
    if base is None:
        return None
    def oldNames( ls ):
        hits = [ ( i, OLD_LIST.match( l ) ) for i, l in enumerate( ls ) if OLD_LIST.match( l ) ]
        return hits[ 0 ] if len( hits ) == 1 else ( None, None )
    def newNames( ls ):
        if 'for _g in \\' not in ls or '    ; do' not in ls:
            return None
        a, z = ls.index( 'for _g in \\' ), ls.index( '    ; do' )
        body = ls[ a + 1:z ]
        return [ l.strip()[ :-1 ].strip() for l in body ] if a < z and all( LIST_LINE.match( l ) for l in body ) else None
    bi, bm = oldNames( base )
    if bm is None:
        return None
    for oldSide, newSide in ( ( ours, theirs ), ( theirs, ours ) ):
        oi, om = oldNames( oldSide )
        nn = newNames( newSide )
        if om is None or nn is None or oi != bi or len( oldSide ) != len( base ):
            continue
        if any( oldSide[ i ] != base[ i ] for i in range( len( base ) ) if i != bi ):
            continue
        o, b, n = set( om.group( 1 ).split() ), set( bm.group( 1 ).split() ), set( nn )
        merged = ( b | ( o - b ) | ( n - b ) ) - ( b - o ) - ( b - n )
        return newSide, sorted( merged )
    return None

def resolve_reshape( newSide, merged ):
    a, z = newSide.index( 'for _g in \\' ), newSide.index( '    ; do' )
    return newSide[ :a + 1 ] + [ '    %s \\' % n for n in merged ] + newSide[ z: ]

def classify( path, ours, base, theirs ):
    sides = ours + theirs + ( base or [] )
    if path == 'test/regression.sh' and base is not None and sides and all( LIST_LINE.match( l ) for l in sides ):
        return 'a'
    if path == 'test/regression.sh' and reshape_sides( ours, base, theirs ) is not None:
        return 'r'
    nonblank = [ l for l in ours + theirs if l.strip() ]
    if path in GEN_SITES and nonblank and all( GEN_LINE.search( l ) for l in nonblank ) and gen_side( ours, base, theirs ) is not None:
        return 'c'
    if path.startswith( BIN_PINNED ):
        return 'b'
    return 'd'

def owned_only( ours, theirs ):
    """The two sides differ only in the numbers a generator OWNS (the gate count's spellings in
    docs/gatecount_build.py, the two numbers of README's cap sentence in docs/limits_build.py): either side's
    text is the same text once the generator re-runs. Every other digit stays literal, so a hand-written
    number on a marked line (docs/EVALS.md's "~210 ... 200+") or any prose edit stays a conflict for a person."""
    mask = lambda ls: [ MASK_OWNED( l ) for l in ls ]
    return mask( ours ) == mask( theirs )

def gen_side( ours, base, theirs ):
    """The side a (c) hunk resolves to, or None when it is not (c): either side when they differ only in owned
    numbers; otherwise, with a base, the side that changed more than owned numbers when the other changed
    nothing else (its edit was a generator re-run, which merge_main.sh repeats on the merged tree). The prose side
    must keep every non-owned number of the base literally: a hand-written number changed on a marked line
    (docs/EVALS.md's "~210") stays a conflict for a person, as before."""
    if owned_only( ours, theirs ):
        return theirs
    if base is None:
        return None
    # every non-owned figure WITH the sign or qualifier glued to it: "~210" -> "210", "200+" -> "200", "200" -> "-200",
    # "1.5" -> "1,5" or "70%" -> "70" is a changed figure, not a rewording
    digits = lambda ls: [ NUMBER.findall( MASK_OWNED( l ) ) for l in ls ]
    if owned_only( ours, base ) and digits( theirs ) == digits( base ):
        return theirs
    if owned_only( theirs, base ) and digits( ours ) == digits( base ):
        return ours
    return None

def resolve_list( ours, base, theirs ):
    o, b, t = set( ours ), set( base ), set( theirs )
    merged = ( b | ( o - b ) | ( t - b ) ) - ( b - o ) - ( b - t )
    return sorted( merged )

def main():
    global GEN_SITES, MASK_OWNED
    GEN_SITES, MASK_OWNED = generator_constants()
    if not os.path.isdir( '.git' ) and git( 'rev-parse', '--show-toplevel' ).strip() != os.getcwd():
        sys.stderr.write( 'merge_resolve: run from the top of the work tree\n' ); return 2
    unmerged = [ p for p in git( 'diff', '--name-only', '--diff-filter=U' ).split( '\n' ) if p ]
    left_total = 0
    for path in unmerged:
        if path in WHOLE_GENERATED:
            git( 'checkout', '--theirs', '--', path ); git( 'add', '--', path )
            print( 'RESOLVED %s c=whole-file (regenerated next)' % path ); continue
        try:
            text = open( path, encoding = 'utf-8', errors = 'surrogateescape' ).read()
        except OSError:
            print( 'UNTOUCHED %s left=? (not a readable file: a delete/rename conflict)' % path ); left_total += 1; continue
        chunks = parse( text )
        if chunks is None or not any( k == 'hunk' for k, _ in chunks ):
            print( 'UNTOUCHED %s left=? (no diff3 hunk found: binary, delete/modify or unterminated)' % path ); left_total += 1; continue
        counts, left, outLines = { 'a': 0, 'b': 0, 'c': 0, 'r': 0 }, 0, []
        for kind, payload in chunks:
            if kind == 'text':
                outLines += payload; continue
            ours, base, theirs, raw = payload
            c = classify( path, ours, base, theirs )
            if c == 'a':
                outLines += resolve_list( ours, base, theirs )
            elif c == 'r':
                outLines += resolve_reshape( *reshape_sides( ours, base, theirs ) )
            elif c == 'b':
                outLines += theirs
            elif c == 'c':
                outLines += gen_side( ours, base, theirs )
            else:
                outLines += raw; left += 1; continue
            counts[ c ] += 1
        new = '\n'.join( outLines )
        if path == 'test/regression.sh':
            new = sort_absorb_list( new )
        with open( path, 'w', encoding = 'utf-8', errors = 'surrogateescape' ) as fh:
            fh.write( new )
        tag = ' '.join( '%s=%d' % kv for kv in sorted( counts.items() ) if kv[ 1 ] )
        if left:
            print( '%s %s %s left=%d' % ( 'PARTIAL' if tag else 'UNTOUCHED', path, tag, left ) ); left_total += left
        else:
            git( 'add', '--', path ); print( 'RESOLVED %s %s' % ( path, tag ) )
        if path.startswith( BIN_PINNED ) and counts[ 'b' ]:
            print( 'REGEN %s' % path )
    return 1 if left_total else 0

def sort_absorb_list( text ):
    """Byte-sort the absorb list if it is intact (no marker inside it); otherwise leave it for the person."""
    m = re.search( r'^for _g in \\\n(.*?)^    ; do\n', text, re.S | re.M )
    if m is None:
        return text
    body = m.group( 1 ).split( '\n' )[ :-1 ]
    if not all( LIST_LINE.match( l ) for l in body ):
        return text
    body = sorted( set( body ) )
    return text[ :m.start( 1 ) ] + '\n'.join( body ) + '\n' + text[ m.end( 1 ): ]

if __name__ == '__main__':
    if len( sys.argv ) > 1 and sys.argv[ 1 ] == '--sort-list':
        p = 'test/regression.sh'; t = open( p ).read(); n = sort_absorb_list( t )
        if n != t:
            open( p, 'w' ).write( n )
        sys.exit( 0 )
    try:
        rc = main()
    except Exception:                                   # a crash is never "conflicts left" (1) to merge_main.sh
        import traceback; traceback.print_exc(); rc = 2
    sys.exit( rc )
