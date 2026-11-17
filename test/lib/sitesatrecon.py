#!/usr/bin/env python3
"""sitesatrecon.py — the reconstruction half of test/sitesatshortcheck.sh.

A caller row's sites_at= prints a call site in the row's OWN file (the file of its p=) as a bare line, and any other
site as the full file:line token. This script puts the dropped bytes back from the DELIVERED answer alone and compares
the result with an independent reference, byte for byte:

    xml      NEW LEGACY MINROWS   rows of the XML dialect (<s> callers rows, <c> safe-delete rows)
    json     NEW LEGACY MINROWS   --json rows ("p" and "sites_at":[...])
    columnar NEW LEGACY MINROWS   --format=columnar (<paths>, <path>, <line>, <sites_at> columns)
    uses     NEW USES   MINROWS   the answer's sites against the uses verb's role="call" rows (a second reference)
    count    NEW                  rows / tokens / bare / full, for the non-vacuity arm
    unitrows FILE                 test/sitesatshort_unit.cpp's `ROW <p file>|<legacy>|<new>` lines (the rows no index produces)
    symbols  MAP N                the first N distinct identifier-named symbols of a default map (the at-scale arm's selectors)

LEGACY is an answer in the file:line-everywhere form (a golden captured from the binary before this change, or that
binary's live output). The legacy side is NEVER split on whitespace: a path can hold a space, so `my dir/a.py:3
my dir/a.py:4` has no unambiguous split. It is compared as a WHOLE value, and "is every token in the row's file" is
asked of it as one anchored pattern built from the row's own p=.

Two verdicts per row, both required:
    LOSSLESS   the value rebuilt from NEW equals LEGACY's value
    SHORT      a row whose LEGACY value is entirely in the row's own file prints bare lines only in NEW
               (this is the half that goes red when a legacy answer is fed in as if it were new)
Exit 0 only when every row holds both AND at least MINROWS rows carried sites_at= (an empty document proves nothing).
"""
import html
import json
import re
import sys

DIGITS = re.compile( r'[0-9]+' )


def strip_legend( doc ):
    return re.sub( r'<!--.*?-->', '', doc, flags=re.S )


def rebuild( pfile, value ):
    """NEW value -> the file:line-everywhere value. A space-delimited all-digit fragment is a bare line of pfile; every
    other fragment is kept verbatim, so a foreign token (whose path may itself hold spaces) passes through whole."""
    return ' '.join( ( pfile + ':' + f ) if DIGITS.fullmatch( f ) else f for f in value.split( ' ' ) )


def own_file_only( pfile, legacy ):
    """Is the LEGACY value exactly `pfile:N pfile:N ...`? One anchored pattern over the whole value, no split."""
    tok = re.escape( pfile ) + r':[0-9]+'
    return re.fullmatch( tok + '(?: ' + tok + ')*', legacy ) is not None


def xml_rows( doc ):
    """[(row text without its sites_at= attribute, p file, sites_at value or None)] for every <s>/<c> row, in order."""
    rows = []
    for m in re.finditer( r'<[sc] [^>]*?/>', strip_legend( doc ) ):
        row = m.group( 0 )
        p = re.search( r' p="([^"]*)"', row )
        if p is None:
            continue
        a = re.search( r' sites_at="([^"]*)"', row )
        rest = row if a is None else row[: a.start()] + row[a.end():]
        rows.append( ( rest, html.unescape( p.group( 1 ) ).rsplit( ':', 1 )[0], None if a is None else html.unescape( a.group( 1 ) ) ) )
    return rows


def json_rows( doc ):
    d = json.loads( doc )
    rows = []
    for key in ( 'callers', 'calledBy' ):
        for x in d.get( key, [] ):
            pv = x.get( 'p' ) or ( x.get( 'path', '' ) + ':0' )
            sites = x.get( 'sites_at' )
            rest = json.dumps( { k: v for k, v in x.items() if k != 'sites_at' }, sort_keys=True )
            rows.append( ( rest, pv.rsplit( ':', 1 )[0], None if sites is None else ' '.join( sites ) ) )
    return rows


def columnar_rows( doc ):
    body = strip_legend( doc )

    def col( name ):
        m = re.search( '<' + name + '>(.*?)</' + name + '>', body, flags=re.S )
        return None if m is None else m.group( 1 )
    paths = {}
    # `0=a.c 1=my dir/b.c`: an id is digits then `=`, and a path may hold a space, so cut at each ` N=` boundary
    for m in re.finditer( r'(?:^| )([0-9]+)=(.*?)(?= [0-9]+=|$)', col( 'paths' ) or '' ):
        paths[m.group( 1 )] = html.unescape( m.group( 2 ) )
    ids, names, lines, sites = ( ( col( c ) or '' ).split( ',' ) for c in ( 'path', 'name', 'line', 'sites_at' ) )
    if col( 'sites_at' ) is None:
        sites = [ '' ] * len( ids )
    rows = []
    for i, pid in enumerate( ids ):
        if pid == '':
            continue
        v = html.unescape( sites[i] ) if i < len( sites ) else ''
        rows.append( ( names[i] + ':' + lines[i], paths.get( pid, '?' ), v if v != '' else None ) )
    return rows


READERS = { 'xml': xml_rows, 'json': json_rows, 'columnar': columnar_rows }


def tally( rows ):
    n = tok = bare = 0
    for _, _, v in rows:
        if v is None:
            continue
        n += 1
        for f in v.split( ' ' ):
            if DIGITS.fullmatch( f ):
                bare += 1; tok += 1
            elif re.search( r':[0-9]+$', f ):
                tok += 1
    return n, tok, bare, tok - bare


def compare( dialect, new_path, legacy_path, minrows ):
    new, old = READERS[dialect]( open( new_path, encoding='utf-8' ).read() ), READERS[dialect]( open( legacy_path, encoding='utf-8' ).read() )
    bad = []
    if len( new ) != len( old ):
        bad.append( 'ROWS: %d rows in the answer, %d in the reference' % ( len( new ), len( old ) ) )
    carried = 0
    for i, ( ( nrest, npf, nv ), ( orest, opf, ov ) ) in enumerate( zip( new, old ) ):
        if nrest != orest:
            bad.append( 'ROW %d: the row outside sites_at= moved: %s | %s' % ( i, nrest, orest ) )
        if ( nv is None ) != ( ov is None ):
            bad.append( 'ROW %d: sites_at= %s here and %s in the reference (absence already means "no call spelled like it")'
                        % ( i, 'absent' if nv is None else 'present', 'absent' if ov is None else 'present' ) )
            continue
        if nv is None:
            continue
        carried += 1
        got = rebuild( npf, nv )
        if got != ov:
            bad.append( 'LOSSLESS ROW %d: rebuilt "%s" from sites_at="%s" + p file "%s", reference "%s"' % ( i, got, nv, npf, ov ) )
        if own_file_only( opf, ov ) and re.fullmatch( r'[0-9]+(?: [0-9]+)*', nv ) is None:
            bad.append( 'SHORT ROW %d: every site is in the row\'s own file "%s" but sites_at="%s" is not a bare-line list' % ( i, opf, nv ) )
    if carried < minrows:
        bad.append( 'FLOOR: %d row(s) carry sites_at=, the arm needs at least %d' % ( carried, minrows ) )
    return carried, bad


def uses( new_path, uses_path, minrows ):
    rows = xml_rows( open( new_path, encoding='utf-8' ).read() )
    want = set( html.unescape( p ) for p in re.findall( r'<u role="call" p="([^"]*)"', strip_legend( open( uses_path, encoding='utf-8' ).read() ) ) )
    got, carried, bad = set(), 0, []
    cut = False
    for row, pf, v in rows:
        if v is None:
            continue
        carried += 1
        cut = cut or ' sites_total="' in row
        if re.fullmatch( r'[0-9]+(?: [0-9]+)*', v ):
            got.update( pf + ':' + n for n in v.split( ' ' ) )   # a bare-line row: the file comes from p= alone, never a split of a path
        else:
            got.add( '\x00WHOLE:' + rebuild( pf, v ) )           # a row holding a foreign token is compared whole elsewhere; never matches here
    extra = sorted( got - want )
    missing = sorted( want - got )
    if extra:
        bad.append( 'USES: sites the uses verb does not list as role="call": ' + ' '.join( extra[:6] ) )
    if missing and not cut:
        bad.append( 'USES: role="call" sites no caller row lists: ' + ' '.join( missing[:6] ) )
    if carried < minrows:
        bad.append( 'FLOOR: %d row(s) carry sites_at=, the arm needs at least %d' % ( carried, minrows ) )
    return carried, bad


def unitrows( path ):
    """Each synthetic row is either byte-identical to its legacy value (the whole-row-full fallback, or a row with no site
    in its own file) or rebuilds to it; a row entirely in its own file must be bare lines. Counted by shape so the shell arm
    can require that the cross-file, mixed and whole-row-full shapes were all actually exercised."""
    bad, n, mixed, same, whole = [], 0, 0, 0, 0
    for line in open( path, encoding='utf-8' ).read().split( '\n' ):
        if not line.startswith( 'ROW ' ):
            continue
        pf, old, new = line[4:].split( '|' )
        n += 1
        if new != old and rebuild( pf, new ) != old:
            bad.append( 'LOSSLESS UNIT ROW %d: "%s" neither equals nor rebuilds to "%s" (p file "%s")' % ( n, new, old, pf ) )
        if own_file_only( pf, old ):
            same += 1
            if re.fullmatch( r'[0-9]+(?: [0-9]+)*', new ) is None:
                bad.append( 'SHORT UNIT ROW %d: own-file row "%s" printed "%s"' % ( n, old, new ) )
        elif new == old:
            whole += 1
        else:
            mixed += 1
    for b in bad:
        print( b )
    print( 'unit_rows=%d own_file=%d mixed=%d verbatim=%d failures=%d' % ( n, same, mixed, whole, len( bad ) ) )
    return 1 if bad or n == 0 else 0


def symbols( map_path, n ):
    names = []
    for nm in re.findall( r'<s [^>]*?n="([A-Za-z_][A-Za-z0-9_]*)"', strip_legend( open( map_path, encoding='utf-8', errors='replace' ).read() ) ):
        if nm not in names:
            names.append( nm )
            if len( names ) == n:
                break
    print( '\n'.join( names ) )
    return 0


def main( argv ):
    mode = argv[1]
    if mode == 'unitrows':
        return unitrows( argv[2] )
    if mode == 'symbols':
        return symbols( argv[2], int( argv[3] ) )
    if mode == 'count':
        print( 'rows=%d tokens=%d bare=%d full=%d' % tally( xml_rows( open( argv[2], encoding='utf-8' ).read() ) ) )
        return 0
    minrows = int( argv[4] )
    carried, bad = uses( argv[2], argv[3], minrows ) if mode == 'uses' else compare( mode, argv[2], argv[3], minrows )
    for b in bad[:12]:
        print( b )
    print( 'rows_with_sites=%d failures=%d' % ( carried, len( bad ) ) )
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit( main( sys.argv ) )
