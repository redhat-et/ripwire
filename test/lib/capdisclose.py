#!/usr/bin/env python3
"""capdisclose.py -- CAP-DISCLOSE-LINT (B43): every answer-path cap constant names the attribute that discloses it.

usage: capdisclose.py ROOT MAP            check; prints PASS/FAIL/INFO rows, then SUMMARY; exit 1 on any FAIL
       capdisclose.py ROOT MAP --draft    print a map row for every in-scope constant the map lacks (classify by hand)

Scope: a constant `constexpr <integer type> kName = <integer literal>` defined in an answer-path file (src/for*.h,
src/verbs_*.h, src/pathroute.h, src/clones.h) that some line of src/ compares as a bound (a CAP SITE, below), or whose
name says it bounds something (Max, Limit, Cap, Ceiling, Depth, Pairs), or that a `static_assert( kName == N, ... )`
ties to legend text. The name alone is not the scope: #613's reader cap was kReaderCallerReaders. A name with `Min`
is a threshold (a row needs at least N), not a cut, and is out of scope. A CAP SITE is a line that compares the
constant (`x >= kName`, `kName <= x`, `std::min( .., kName )`, `i < kName;` ...); its FUNCTION SCOPE is the outermost
brace block around it that is not a namespace, class, struct, union or enum body.

MAP rows (tab-separated, `#` comments):  kName <TAB> CLASS [<TAB> awaits:#N]
  sink:a,b        every function scope with a cap site of kName mentions identifier a or b (the attribute's variable,
                  a flag such as atDepthCap / readersMore, or the DISCLOSE sink) -- checked
  legend          a static_assert ties kName to a legend sentence, and no cap site prunes an answer row -- checked: the
                  static_assert must exist
  none:<reason>   not an answer cut (a work bound whose hit cannot change the bytes, a size hint) -- reason required
  pending:#N <r>  a cut that does not disclose yet, baselined with its PR/issue (or card, B43) and reason -- INFO, never FAIL
  awaits:#N       (third column) the constant lives on an unmerged lane: absent from source is INFO, present is checked

Checked both ways: an in-scope constant with no row FAILS (a new cap must say how it discloses); a row whose constant
is not in scope FAILS as stale unless it awaits a merge; a sink that some cap site's function never mentions FAILS
with file:line of that site. Output rows: `PASS|FAIL|INFO <text>`, then `SUMMARY in_scope=N sinks=S legend=L none=X
pending=P awaits=A failed=F`.
"""
import os, re, sys

STRIP = re.compile( r'//[^\n]*|/\*.*?\*/|R"([^ ()\\\t\v\f\n]{0,16})\(.*?\)\1"|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'', re.S )

def blank( m ):
    """A removed comment or literal keeps its newlines and is at least one space, so it never joins two tokens."""
    return "\n" * m.group( 0 ).count( "\n" ) or " "

def uncommented( text ):
    """text with comments blanked and every string literal kept (a static_assert's message is read)."""
    return STRIP.sub( lambda m: m.group( 0 ) if m.group( 0 )[:1] in "\"'R" else blank( m ), text )
INT_T = r'(?:std::)?(?:size_t|uint\d+_t|int\d*_t|int|unsigned|u8|u16|u32|u64|i32|i64|long)'
CONST = re.compile( r'\bconstexpr\s+' + INT_T + r'\s+(k[A-Z]\w*)\s*(?:=|\{)\s*([0-9][0-9\'uUlLzZ]*|std::size_t\s*\{\s*\d+\s*\}|std::size_t\s*\(\s*\d+\s*\))\s*\}?\s*;' )
NAMED = re.compile( r'Max|Limit|Cap|Ceiling|Depth|Pairs' )
DISCLOSURE = re.compile( r'\b(?:\w*(?:[cC]apped|[mM]ore|[tT]runc|[cC]ut|[sS]hown|[oO]mit|[eE]lided|[fF]loor|[pP]artial|[dD]ropped|[hH]idden|[sS]kipped|[oO]verflow|[rR]emain|[aA]bstain|[lL]imited|[sS]aturat)\w*|DISCLOSE)\b' )
CONTAINER = re.compile( r'\b(?:namespace|struct|class|union|enum)\b[^;{}()]*$|extern\s*$' )

def answer_path( root ):
    out = []
    for f in sorted( os.listdir( os.path.join( root, "src" ) ) ):
        if ( f.startswith( ( "for", "verbs_" ) ) and f.endswith( ".h" ) ) or f in ( "pathroute.h", "clones.h" ):
            out.append( "src/" + f )
    return out

def all_sources( root ):
    for d, dirs, files in os.walk( os.path.join( root, "src" ) ):
        dirs.sort()
        for f in sorted( files ):
            if f.endswith( ( ".h", ".cpp" ) ):
                yield os.path.relpath( os.path.join( d, f ), root )

def stripped( root, rel, cache={} ):
    key = ( root, rel )
    if key not in cache:
        cache[key] = STRIP.sub( blank, open( os.path.join( root, rel ), errors="replace" ).read() )
    return cache[key]

def function_scopes( text ):
    """[(start, end)] of outermost non-container brace blocks."""
    out, stack, last = [], [], 0
    for i, ch in enumerate( text ):
        if ch == "{":
            head = text[last:i]
            container = bool( CONTAINER.search( head ) ) and ( not stack or stack[-1][1] )
            stack.append( ( i, container ) )
            last = i + 1
        elif ch == "}":
            if stack:
                start, container = stack.pop()
                if not container and ( not stack or all( c for _, c in stack ) ):
                    out.append( ( start, i + 1 ) )
            last = i + 1
        elif ch == ";":
            last = i + 1
    return out

def cap_site( name, line ):
    k = r'(?:\w+::)*' + re.escape( name ) + r'\b'
    return bool( re.search( r'(?:>=|>|<=|<)\s*' + k, line ) or re.search( r'\b' + re.escape( name ) + r'\s*(?:<=|<|>=|>)(?!>)', line )
                 or re.search( r'std::min\s*\([^;]*\b' + re.escape( name ) + r'\b', line ) ) and "static_assert" not in line

def scope( root ):
    defs = {}
    for f in answer_path( root ):
        # the whole file, not line by line: `constexpr std::size_t kMaxRows =\n    8;` is one declaration (CodeRabbit #626 4548924360)
        text = stripped( root, f )
        for m in CONST.finditer( text ):
            defs.setdefault( m.group( 1 ), ( f, text.count( "\n", 0, m.start( 1 ) ) + 1 ) )
    asserted = set()
    for f in all_sources( root ):
        # comments blanked, strings kept: a commented-out static_assert ties nothing (CodeRabbit #626 4548924364)
        for m in re.finditer( r'static_assert\s*\(([^;]*)\)\s*;', uncommented( open( os.path.join( root, f ), errors="replace" ).read() ) ):
            if re.search( r'legend|Legend|states', m.group( 1 ) ):
                asserted.update( re.findall( r'\b(k[A-Z]\w*)\s*==', m.group( 1 ) ) )
    return { k: v for k, v in defs.items() if "Min" not in k and ( NAMED.search( k ) or k in asserted or sites( root, k ) ) }, asserted

def sites( root, name ):
    """[(file, line, scope_text or None)] for every cap site of name in src/."""
    out = []
    for f in all_sources( root ):
        text = stripped( root, f )
        if name not in text:
            continue
        scopes, pos = None, 0
        for i, line in enumerate( text.split( "\n" ), 1 ):
            if name in line and cap_site( name, line ) and not CONST.search( line ):
                if scopes is None:
                    scopes = function_scopes( text )
                at = pos + line.find( name )
                body = next( ( text[a:b] for a, b in scopes if a <= at < b ), None )
                out.append( ( f, i, body ) )
            pos += len( line ) + 1
    return out

def read_map( path ):
    rows = {}
    for n, raw in enumerate( open( path ), 1 ):
        line = raw.rstrip( "\n" )
        if not line.strip() or line.lstrip().startswith( "#" ):
            continue
        cols = line.split( "\t" )
        rows[cols[0].strip()] = ( cols[1].strip() if len( cols ) > 1 else "", cols[2].strip() if len( cols ) > 2 else "", n )
    return rows

def check( root, mpath, draft=False ):
    inscope, asserted = scope( root )
    rows = read_map( mpath ) if os.path.exists( mpath ) else {}
    fails, tally = [], { "sinks": 0, "legend": 0, "none": 0, "pending": 0, "awaits": 0 }
    def say( kind, text ):
        print( "%s %s" % ( kind, text ) )
        if kind == "FAIL":
            fails.append( text )
    if draft:
        for k in sorted( set( inscope ) - set( rows ) ):
            ss = sites( root, k )
            per = [ set( DISCLOSURE.findall( body or "" ) ) for _, _, body in ss ]
            common = { t for t in ( set.intersection( *per ) if per else set() ) if not re.match( r'k[A-Z]', t ) }
            pick = sorted( common, key=lambda t: ( -sum( ( b or "" ).count( t ) for _, _, b in ss ), t ) )[:2]
            if pick:
                print( "%s\tsink:%s" % ( k, ",".join( pick ) ) )
            elif k in asserted:
                print( "%s\tlegend" % k )
            else:
                where = ", ".join( "%s:%d" % ( f, i ) for f, i, _ in ss[:2] ) or "%s:%d (no cap site)" % inscope[k]
                print( "%s\tpending:B43 no disclosure identifier in the cap site's function (%s); audit: cut or work bound" % ( k, where ) )
        return 0
    for k in sorted( set( inscope ) - set( rows ) ):
        say( "FAIL", "%s (%s:%d) is an answer-path cap with no row in %s: name the attribute that discloses it (sink:IDENT), "
             "or classify it legend / none:<reason> / pending:#N <reason>" % ( k, inscope[k][0], inscope[k][1], os.path.basename( mpath ) ) )
    for k, ( cls, awaits, n ) in sorted( rows.items() ):
        if k not in inscope:
            if awaits.startswith( "awaits:#" ):
                tally["awaits"] += 1
                say( "INFO", "%s awaits %s (not in this tree yet; checked once it lands)" % ( k, awaits[7:] ) )
            else:
                say( "FAIL", "stale row %s (map line %d): no answer-path cap constant of that name -- delete the row" % ( k, n ) )
            continue
        if cls.startswith( "sink:" ):
            idents = [ s for s in cls[5:].split( "," ) if s ]
            ss = sites( root, k )
            if not idents:
                say( "FAIL", "%s: sink: names no identifier" % k ); continue
            if not ss:
                say( "FAIL", "%s: sink:%s but no cap site compares %s -- the premise is empty; reclassify" % ( k, ",".join( idents ), k ) ); continue
            bad = [ ( f, i ) for f, i, body in ss if body is None or not any( re.search( r'\b' + re.escape( s ) + r'\b', body ) for s in idents ) ]
            if bad:
                say( "FAIL", "%s: %d of %d cap site(s) sit in a function that never mentions %s: %s" % (
                    k, len( bad ), len( ss ), " / ".join( idents ), ", ".join( "%s:%d" % b for b in bad[:6] ) ) )
            else:
                tally["sinks"] += 1
                say( "PASS", "%s: all %d cap site(s) disclose through %s in scope" % ( k, len( ss ), " / ".join( idents ) ) )
        elif cls == "legend":
            if k in asserted:
                tally["legend"] += 1
                say( "PASS", "%s: legend-tied (static_assert)" % k )
            else:
                say( "FAIL", "%s: classified legend, but no static_assert( %s == N, \"..legend..\" ) ties it" % ( k, k ) )
        elif cls.startswith( "none:" ) and cls[5:].strip():
            tally["none"] += 1
        elif re.match( r'pending:(?:#\d+|[A-Z][\w-]*)\s+\S', cls ):
            tally["pending"] += 1
            say( "INFO", "%s pending (%s)" % ( k, cls[8:120] ) )
        else:
            say( "FAIL", "%s: unrecognised class '%s' (map line %d) -- sink:IDENT / legend / none:<reason> / pending:#N <reason>" % ( k, cls, n ) )
    print( "SUMMARY in_scope=%d sinks=%d legend=%d none=%d pending=%d awaits=%d failed=%d" % (
        len( inscope ), tally["sinks"], tally["legend"], tally["none"], tally["pending"], tally["awaits"], len( fails ) ) )
    return 1 if fails else 0

if __name__ == "__main__":
    a = sys.argv[1:]
    if len( a ) not in ( 2, 3 ) or ( len( a ) == 3 and a[2] != "--draft" ):
        print( __doc__, file=sys.stderr ); sys.exit( 2 )
    sys.exit( check( a[0], a[1], draft=len( a ) == 3 ) )
