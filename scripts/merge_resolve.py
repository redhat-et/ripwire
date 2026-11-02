#!/usr/bin/env python3
"""merge_resolve.py — resolve the merge conflicts that have a mechanical answer; leave every other one.

Run by scripts/merge_main.sh while a merge is stopped on conflicts (the conflict style must be diff3, so a
hunk carries its base). For each unmerged path it resolves only these hunk classes and leaves the rest
with their markers:

  (a) LIST   test/regression.sh absorb-list lines (`    name \\`) on every side: a 3-way SET merge (both
             sides' additions kept, both sides' removals applied), then byte-sorted.
  (c) GEN    a hunk whose every non-blank line on both sides carries a generator marker (`<!-- gatecount -->`,
             `// gatecount`) or is the README cap-inventory sentence, and whose two sides differ ONLY in
             their numbers (a prose edit on such a line stays a conflict): the other side's text is taken, and
             merge_main.sh then re-runs the generator that owns those lines (the value is recomputed, not
             chosen). docs/LIMITS.md and docs/TUNING.md are generated whole: the file is taken and rebuilt.
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

def classify( path, ours, base, theirs ):
    sides = ours + theirs + ( base or [] )
    if path == 'test/regression.sh' and base is not None and sides and all( LIST_LINE.match( l ) for l in sides ):
        return 'a'
    nonblank = [ l for l in ours + theirs if l.strip() ]
    if nonblank and all( GEN_LINE.search( l ) for l in nonblank ) and digits_only( ours, theirs ):
        return 'c'
    if path.startswith( BIN_PINNED ):
        return 'b'
    return 'd'

def digits_only( ours, theirs ):
    """The two sides differ only in their numbers: the generator owns the numbers, so either side's text is the
    same text once it re-runs. A prose edit on a marked line is NOT that, and stays a conflict for a person."""
    mask = lambda ls: [ re.sub( r'[0-9]+', '#', l ) for l in ls ]
    return mask( ours ) == mask( theirs )

def resolve_list( ours, base, theirs ):
    o, b, t = set( ours ), set( base ), set( theirs )
    merged = ( b | ( o - b ) | ( t - b ) ) - ( b - o ) - ( b - t )
    return sorted( merged )

def main():
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
        counts, left, outLines = { 'a': 0, 'b': 0, 'c': 0 }, 0, []
        for kind, payload in chunks:
            if kind == 'text':
                outLines += payload; continue
            ours, base, theirs, raw = payload
            c = classify( path, ours, base, theirs )
            if c == 'a':
                outLines += resolve_list( ours, base, theirs )
            elif c in ( 'b', 'c' ):
                outLines += theirs
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
    sys.exit( main() )
