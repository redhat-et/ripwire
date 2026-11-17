#!/usr/bin/env bash
# dccolumnarcheck.sh — BAND DC (docs/EVALS.md, pre-registration 2026-11-17 amendment 10 and 10a): under --format=columnar the
# declined-call rows of an answer that lists MORE than the default cut (16) ride as ONE block of parallel arrays (<dcols>), and a
# --callers / --impact root that windows names the complete call (all_next=).
#
# THE FINDING. The columnar dialect removed 46 % of a complete --impact answer's symbol rows and 0 % of its <dc> rows, which it
# printed verbatim: 58.1 % of the columnar complete answer on the 32 windowed impact cells of the registered population. And a
# direct --callers / --impact root that windowed named a next PAGE (or another verb), never the one call that lists every row.
#
# WHAT A <dc> ROW IS FOR. A declined call might mean this symbol; the resolver proved nothing. Compressing the rows must not change
# what a reader can learn, so the central arm REBUILDS every row from the block and compares it byte for byte with the XML form.
#
# ARMS (the registered rule's letters)
#   (D1) every <dc> row rebuilt from <dcols> (zip the arrays, look path up in <paths>, restore &#44;, drop an empty cell's
#        attribute, put the block's via= back) equals the same call's XML row: bytes, count, order. Item grain. Run twice: as
#        shipped (the block past 16 rows, the rows verbatim at 16 or fewer) and with the block forced at any row count
#        (RIPWIRE_TEST_DCCOLS_MUTANT=always), which is what puts the gate=, bound= and of_def= fixtures through the encoder. Four
#        answers are also pinned to their pre-change literals, so both forms drifting together still fails.
#   (D2) bytes, whole document, as shipped: NO answer is larger than the same answer with the rows verbatim (amendment 10a:
#        tighter than the registered +160 B for a 1-3 row answer), and the block is at most 40 % of the rows it replaces on the
#        360-site answer.
#   (D3) the reader is told what the block is, in both legend postures: the block is defined, a site is NOT an edge, the resolver
#        proved none, and via="declined" rides the block.
#   (D4) n= equals every array's length; uncut it equals declined_calls=, cut it equals dc_shown=.
#   (D5) the XML and --json forms print their rows as before (no <dcols>).
#   (P1) all_next= rides exactly the roots that carry has_more="1": 0 false positives, 0 false negatives. Cell grain.
#   (P2) the call all_next= names, run verbatim, does not window (no has_more="1") and has no dc_shown=, and its ( path, name, line ) rows equal the XML
#        rows paged to the end in set, count and order. Symbol grain.
#   (P3) a root that does not window carries no all_next=.
#   (N)  non-vacuity: the fixtures yield a gate=, bound=, of_def=, cand=, cand_more= row, a cut answer and a windowed answer.
#   (M)  the seven registered mutation controls, on the real binary: each makes its arm fail.
#   (I)  determinism and well-formedness.
#
# RED ON BASE: (D1) (D2) (D3) (D4) (P1) (P2) fail on a binary that prints the rows verbatim and no pointer.
# Usage: bash test/dccolumnarcheck.sh [BIN]     (or RIPWIRE_BIN=...). Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"          # a relative binary is relative to the caller's cwd
echo "dccolumnarcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "dccolumnarcheck: python3 required"; exit 2; }
for d in declinedsitefix ifacedispatchfix; do
    [ -d "$ROOT/test/$d" ] || { echo "fixture missing: test/$d"; exit 2; }
done
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# Every arm runs in the Python below; its exit status (1 on any FAIL arm, anything else on a crash) is the accumulator's input.
python3 - "$BIN" "$ROOT" "$TMP" <<'PY' || no "the arms above did not all pass (or the checker itself failed): python rc != 0"
import os, re, shlex, subprocess, sys
import xml.etree.ElementTree as ET

BIN, ROOT, TMP = sys.argv[1], sys.argv[2], sys.argv[3]
T = os.path.join( ROOT, "test" )
FIX, IFX = os.path.join( T, "declinedsitefix" ), os.path.join( T, "ifacedispatchfix" )
npass = nfail = 0

def say( good, tag, msg, why = "" ):
    global npass, nfail
    try:
        if good:
            npass += 1; print( "  PASS  %s: %s" % ( tag, msg ) )
        else:
            nfail += 1; print( "  FAIL  %s: %s%s" % ( tag, msg, ( " -- " + why ) if why else "" ) )
    except OSError:
        nfail += 1   # a verdict that could not be written is not a pass

def run( root, args, env = None ):
    """( rc, stdout ) of one CLI answer; rc 124 on a timeout. `env` adds variables (a mutation control)."""
    e = dict( os.environ )
    for k in ( "RIPWIRE_TEST_DCCOLS_MUTANT", "RIPWIRE_TEST_HANDOFF_MUTANT", "RIPWIRE_NO_WINDOW_HANDOFF" ):
        e.pop( k, None )
    e.update( env or {} )
    try:
        p = subprocess.run( [ BIN, root, "--no-cache" ] + list( args ), capture_output = True, text = True, timeout = 240, env = e )
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired:
        return 124, ""

def body( text ):
    """the answer without its comments (a legend spells <dc ...> and <dcols ...> to define them)"""
    return re.sub( r"<!--.*?-->", "", text, flags = re.S )

def legend( text ):
    return "".join( re.findall( r"<!--.*?-->", text, flags = re.S ) )

def root_tag( text ):
    m = re.search( r"<(callers|callees|impact) [^>]*>", body( text ) )
    return m.group( 0 ) if m else ""

def attr( tag, name ):
    m = re.search( r' %s="([^"]*)"' % re.escape( name ), tag )
    return m.group( 1 ) if m else None

def xml_dc_rows( text ):
    return re.findall( r"<dc [^>]*/>", body( text ) )

def path_table( text ):
    """<paths>0=a 1=b</paths> as a list; the entries are read in index order, so a path may hold a space"""
    m = re.search( r"<paths>(.*?)</paths>", body( text ), re.S )
    raw, out, i = ( m.group( 1 ) if m else "" ), [], 0
    while raw.startswith( "%d=" % i ):
        raw = raw[ len( "%d=" % i ): ]
        cut = raw.find( " %d=" % ( i + 1 ) )
        out.append( raw if cut < 0 else raw[ :cut ] )
        raw = "" if cut < 0 else raw[ cut + 1: ]
        i += 1
    return out

class Block:
    """One answer's <dcols> block: its attributes, its columns, and the <dc> rows it stands for, rebuilt."""
    def __init__( self, text ):
        b = body( text )
        m = re.search( r"<dcols( [^>]*)>(.*?)</dcols>", b, re.S )
        self.present = m is not None
        self.raw     = m.group( 0 ) if m else ""
        self.tag     = m.group( 1 ) if m else ""
        self.fields  = ( attr( self.tag, "fields" ) or "" ).split( "," ) if m else []
        self.n       = int( attr( self.tag, "n" ) or -1 ) if m else -1
        self.cols, self.err = {}, ""
        for f in self.fields:
            c = re.search( r"<%s>(.*?)</%s>" % ( f, f ), m.group( 2 ), re.S )
            if c is None:
                self.err = "fields= names %s and no <%s> array rides" % ( f, f ); continue
            self.cols[ f ] = c.group( 1 ).split( "," )
        self.paths = path_table( text )
    def lengths_ok( self ):
        return self.present and not self.err and all( len( v ) == self.n for v in self.cols.values() )
    def rows( self ):
        if not self.present or self.err:
            return None
        via, out = attr( self.tag, "via" ), []
        cell = lambda f, i: self.cols[ f ][ i ].replace( "&#44;", "," ) if f in self.cols and i < len( self.cols[ f ] ) else ""
        for i in range( max( [ len( v ) for v in self.cols.values() ] or [ 0 ] ) ):
            if "path" in self.cols:
                try:
                    p = self.paths[ int( cell( "path", i ) ) ]
                except ( ValueError, IndexError ):
                    return None
                r = '<dc in="%s" p="%s:%s"' % ( cell( "in", i ), p, cell( "line", i ) )
            else:
                r = '<dc n="%s" l="%s"' % ( cell( "name", i ), cell( "line", i ) )
            r += ( ' cands="%s"' % cell( "cands", i ) ) if cell( "cands", i ) != "" else ""
            r += ( ' via="%s"' % via ) if via is not None else ""
            for f in ( "gate", "bound", "of_def", "cand", "cand_more" ):
                r += ( ' %s="%s"' % ( f, cell( f, i ) ) ) if cell( f, i ) != "" else ""
            out.append( r + "/>" )
        return out

# ── the generated tree: 10 same-named methods (cand_more under legend full), 360 declined callers in 6 files (a cut, file-first),
#    and 300 proven callers of one leaf (a window on both verbs: past the callers verb's byte band too), so --impact=leaf holds
#    MORE declined sites (360) than rows (301); the candidates' directory name holds a comma ────────────────────────────────────
W = os.path.join( TMP, "w" )
for d in ( "de,fs", "use", "fan" ):
    os.makedirs( os.path.join( W, d ), exist_ok = True )
open( os.path.join( W, "core.py" ), "w" ).write( "def leaf():\n    return 1\n" )
for k in range( 10 ):
    open( os.path.join( W, "de,fs", "c%d.py" % k ), "w" ).write(
        "from core import leaf\n\n\nclass C%d:\n    def poll(self):\n        return %s\n" % ( k, "leaf()" if k == 0 else str( k ) ) )
for f in range( 6 ):
    with open( os.path.join( W, "use", "u%d.py" % f ), "w" ) as h:
        for k in range( 60 ):
            h.write( "def use_%d_%d(x):\n    return x.poll()\n\n\n" % ( f, k ) )
    with open( os.path.join( W, "fan", "f%d.py" % f ), "w" ) as h:
        h.write( "from core import leaf\n\n\n" )
        for k in range( 50 ):
            h.write( "def call_%d_%d():\n    return leaf()\n\n\n" % ( f, k ) )

GO, RS, RBS, PYF, CPP, TS, RB = ( os.path.join( FIX, d ) for d in ( "go", "rs", "rbside", "py", "cpp", "ts", "rb" ) )
IRS = os.path.join( IFX, "rs" )
CASES = [   # ( root, verb, selector ) — each asked in both legend postures
    ( GO, "callees", "doPackage" ), ( GO, "impact", "deb/deb.go:Package" ), ( RS, "callees", "preprocess_book" ),
    ( RBS, "callees", "run" ), ( RBS, "callers", "lib/widget.rb:helper" ), ( RBS, "impact", "lib/widget.rb:helper" ),
    ( PYF, "callers", "fetch" ), ( CPP, "callees", "drive" ), ( TS, "callees", "dispatch" ), ( TS, "callers", "match" ),
    ( TS, "impact", "src/routers/trie/router.ts:match" ), ( RB, "callers", "lib/rake/task_manager.rb:define_task" ),
    ( IRS, "callees", "bound_generic" ), ( IRS, "callees", "dyn_ref" ),
    ( W, "callers", "de,fs/c0.py:poll" ), ( W, "callees", "use_0_0" ), ( W, "impact", "leaf" ), ( W, "impact", "de,fs/c0.py:poll" ),
]
POSTURES = ( (), ( "--legend=full", ) )

def ask_pair( root, verb, sel, extra = (), env = None ):
    rx, x = run( root, [ "--%s=%s" % ( verb, sel ) ] + list( extra ), env )
    rc, c = run( root, [ "--%s=%s" % ( verb, sel ), "--format=columnar" ] + list( extra ), env )
    return rx, x, rc, c

# ── (D1) (D3) (D4) (D5) over every case ─────────────────────────────────────────────────────────────────────────────────────────
MUT = "RIPWIRE_TEST_DCCOLS_MUTANT"
CUT = 16   # declinedsites.h kDeclinedSiteCap: the block replaces the rows only where more than this many print

def sweep( env = None ):
    """the per-arm failure lists of one pass over CASES x POSTURES (+ the lifted-limit answers), and what the rows carried.
    With no env the binary is as shipped: the block is expected past CUT rows and the rows verbatim otherwise. A mutant other
    than verbatim forces the block at any row count."""
    forced = env is not None and env.get( MUT ) != "verbatim"
    bad  = { "D1": [], "D3": [], "D4": [], "D5": [] }
    seen = { "rows": 0, "docs": 0, "gate": 0, "bound": 0, "of_def": 0, "cand": 0, "cand_more": 0, "cut": 0, "comma": 0 }
    jobs = [ ( r, v, s, p ) for ( r, v, s ) in CASES for p in POSTURES ]
    jobs += [ ( W, "impact", "leaf", ( "--limit=400", ) ), ( W, "callers", "de,fs/c0.py:poll", ( "--limit=400", "--legend=full" ) ) ]
    for root, verb, sel, extra in jobs:
        name = "--%s=%s %s" % ( verb, sel, " ".join( extra ) )
        rx, x, rc, c = ask_pair( root, verb, sel, extra, env )
        want = xml_dc_rows( x )
        if rx != 0 or rc != 0 or not root_tag( x ) or not root_tag( c ):
            bad[ "D1" ].append( "%s: rc=%s/%s or no root" % ( name, rx, rc ) ); continue
        if "<dcols" in body( x ):
            bad[ "D5" ].append( "%s: the XML form carries <dcols>" % name )
        blk = Block( c )
        if not want:
            if blk.present or xml_dc_rows( c ):
                bad[ "D1" ].append( "%s: no <dc> row in XML, yet the columnar form carries one" % name )
            continue
        if not forced and len( want ) <= CUT:
            if blk.present or xml_dc_rows( c ) != want:
                bad[ "D1" ].append( "%s: %d rows (at most %d): the columnar form must print them verbatim and no block" % ( name, len( want ), CUT ) )
            continue
        seen[ "docs" ] += 1; seen[ "rows" ] += len( want )
        for k in ( "gate", "bound", "of_def", "cand", "cand_more" ):
            seen[ k ] += sum( 1 for r in want if ( " %s=\"" % k ) in r )
        seen[ "comma" ] += sum( 1 for r in want if "," in r )
        seen[ "cut" ]   += 1 if attr( root_tag( c ), "dc_shown" ) else 0
        got = blk.rows()
        if got != want:
            first = next( ( i for i, ( a, b ) in enumerate( zip( got or [], want ) ) if a != b ), min( len( got or [] ), len( want ) ) )
            bad[ "D1" ].append( "%s: %s rebuilt vs %d XML rows; first difference at row %d: %r vs %r" % (
                name, "no block," if got is None else len( got ), len( want ), first,
                ( got or [ None ] )[ first ] if got and first < len( got ) else None, want[ first ] if first < len( want ) else None ) )
        if xml_dc_rows( c ):
            bad[ "D1" ].append( "%s: the columnar form still prints <dc> rows beside the block" % name )
        r = root_tag( c )
        total, shown = attr( r, "declined_calls" ), attr( r, "dc_shown" )
        if not blk.lengths_ok() or str( blk.n ) != ( shown or total ):
            bad[ "D4" ].append( "%s: n=%s, arrays %s, declined_calls=%s dc_shown=%s %s" % (
                name, blk.n, sorted( { len( v ) for v in blk.cols.values() } ), total, shown, blk.err ) )
        lg = legend( c )
        miss = [ w for w in ( "dcols", "NOT an edge", "the resolver proved none" ) if w not in lg ]
        if miss or attr( blk.tag, "via" ) != "declined":
            bad[ "D3" ].append( "%s: legend lacks %s; block via=%r" % ( name, miss, attr( blk.tag, "via" ) ) )
    return bad, seen

print( "=== (D1) (D3) (D4) (D5) every declined-call fact, rebuilt from the block ===" )
bad, seen = sweep()
say( not bad[ "D1" ] and seen[ "docs" ] >= 2, "(D1) as shipped", "%d <dc> rows on %d answers past the cut rebuilt from <dcols> equal the XML rows byte for byte, in order; "
     "every answer at or under it prints its rows verbatim" % ( seen[ "rows" ], seen[ "docs" ] ), "; ".join( bad[ "D1" ][ :3 ] ) )
shipped = bad
bad, seen = sweep( { MUT: "always" } )
for k in bad:
    bad[ k ] += shipped[ k ]
say( not bad[ "D1" ], "(D1) rebuild", "the block forced at any row count: %d <dc> rows on %d answers rebuilt equal the XML rows byte for byte, in order" % (
     seen[ "rows" ], seen[ "docs" ] ), "; ".join( bad[ "D1" ][ :3 ] ) )
say( not bad[ "D3" ], "(D3) legend", "every answer with a block defines it, keeps NOT-an-edge and proved-none, and the block says via=\"declined\"", "; ".join( bad[ "D3" ][ :3 ] ) )
say( not bad[ "D4" ], "(D4) counts", "n= is every array's length, and dc_shown= (cut) or declined_calls= (uncut)", "; ".join( bad[ "D4" ][ :3 ] ) )
say( not bad[ "D5" ], "(D5) other forms", "the XML form prints rows, never the block", "; ".join( bad[ "D5" ][ :3 ] ) )
rc, j = run( W, [ "--impact=leaf", "--json" ] )
say( rc == 0 and '"dc":[{"in":' in j and "dcols" not in j, "(D5) json", "--json keeps its \"dc\" array", j[ :200 ] )

# the pre-change literals: four answers' rows as the binary before this band printed them (both forms then)
PINS = [
    ( GO, "callees", "doPackage", [ '<dc n="ConventionalFileName" l="16" cands="2" via="declined"/>', '<dc n="ConventionalFileName" l="18" cands="2" via="declined"/>',
                                    '<dc n="Package" l="24" cands="2" via="declined"/>' ] ),
    ( PYF, "callers", "fetch", [ '<dc in="load" p="caller/use.py:7" cands="2" via="declined" of_def="1~d 2~d"/>', '<dc in="load" p="other/loader.py:2" cands="2" via="declined" of_def="1~d 2~d"/>',
                                 '<dc in="load_twice" p="caller/use.py:11" cands="2" via="declined" of_def="1~d 2~d"/>',
                                 '<dc in="load_twice" p="caller/use.py:12" cands="2" via="declined" of_def="1~d 2~d"/>' ] ),
    ( TS, "callers", "match", [ '<dc in="dispatch" p="src/app/dispatch.ts:8" cands="2" via="declined" gate="iface" of_def="1~d 3~d"/>' ] ),
    ( RBS, "callers", "lib/widget.rb:helper", [ '<dc in="run" p="lib/widget.rb:7" cands="1" via="declined" gate="side"/>' ] ),
]
off = []
for root, verb, sel, want in PINS:
    rx, x, rc, c = ask_pair( root, verb, sel )
    forced = Block( ask_pair( root, verb, sel, (), { MUT: "always" } )[ 3 ] ).rows()
    if xml_dc_rows( x ) != want or xml_dc_rows( c ) != want or forced != want:
        off.append( "--%s=%s: XML %r, columnar %r, rebuilt from the forced block %r" % ( verb, sel, xml_dc_rows( x ), xml_dc_rows( c ), forced ) )
say( not off, "(D1) pinned", "four answers' rows equal their pre-change literals: XML, columnar as shipped, and rebuilt from the forced block", "; ".join( off[ :2 ] ) )

print( "=== (N) non-vacuity ===" )
for k, what in ( ( "gate", "a gate= row" ), ( "bound", "a bound= row" ), ( "of_def", "an of_def= row" ), ( "cand", "a cand= row" ),
                 ( "cand_more", "a cand_more= row" ), ( "cut", "a cut (dc_shown=) answer" ), ( "comma", "a row whose value holds a comma" ) ):
    say( seen[ k ] > 0, "(N) %s" % k, "the fixtures yield %s (%d)" % ( what, seen[ k ] ) )

# ── (D2) bytes ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (D2) bytes, whole document ===" )
VERBATIM = { MUT: "verbatim" }
def d2( env = None ):
    """failures of the byte rule; `env` is the binary under test, the reference is always the rows-verbatim form of the same call"""
    out = []
    for root, verb, sel in CASES + [ ( W, "impact", "leaf --limit=400" ) ]:
        sel, _, lim = sel.partition( " " )
        args = [ "--%s=%s" % ( verb, sel ), "--format=columnar" ] + ( [ lim ] if lim else [] )
        rn, new = run( root, args, env )
        ro, old = run( root, args, VERBATIM )
        rows = xml_dc_rows( old )
        if rn != 0 or ro != 0 or not rows:
            if rn != 0 or ro != 0:
                out.append( "%s: rc %s/%s" % ( " ".join( args ), rn, ro ) )
            continue
        grow = len( new.encode() ) - len( old.encode() )
        if grow > 0:
            out.append( "%s: %d rows, %+d B" % ( " ".join( args ), len( rows ), grow ) )
        if len( rows ) > CUT:
            blk, was = len( Block( new ).raw.encode() ), sum( len( r.encode() ) for r in rows )
            if blk == 0 or blk * 100 > was * 40:
                out.append( "%s: the block is %d B against %d B of rows (over 40 %%)" % ( " ".join( args ), blk, was ) )
    return out
off = d2()
say( not off, "(D2) bytes", "no answer is larger than the same answer with its rows verbatim; 360 sites: the block is at most 40 % of them", "; ".join( off[ :4 ] ) )

# ── (P1) (P2) (P3) the direct roots ───────────────────────────────────────────────────────────────────────────────────────────
print( "=== (P1) (P2) (P3) the direct roots name the complete call ===" )
PCASES = [ ( W, "callers", "leaf" ), ( W, "impact", "leaf" ), ( W, "impact", "de,fs/c0.py:poll" ), ( W, "callers", "de,fs/c0.py:poll" ),
           ( W, "callers", "use_0_0" ), ( W, "impact", "use_0_0" ), ( GO, "impact", "deb/deb.go:Package" ), ( PYF, "callers", "fetch" ),
           ( TS, "callers", "match" ), ( RB, "callers", "lib/rake/task_manager.rb:define_task" ) ]

def s_rows_xml( text ):
    out = []
    for m in re.finditer( r'<s t="[^"]*" n="([^"]*)" p="([^"]*):(\d+)"', body( text ) ):
        out.append( ( m.group( 2 ), m.group( 1 ), m.group( 3 ) ) )
    return out

def s_rows_columnar( text ):
    m = re.search( r"<cols [^>]*>(.*?)</cols>", body( text ), re.S )
    if m is None:
        return None
    col = lambda f: ( re.search( r"<%s>(.*?)</%s>" % ( f, f ), m.group( 1 ), re.S ).group( 1 ) or "" ).split( "," )
    paths, p, n, l = path_table( text ), col( "path" ), col( "name" ), col( "line" )
    if p == [ "" ]:
        return []
    return [ ( paths[ int( p[ i ] ) ], n[ i ].replace( "&#44;", "," ), l[ i ] ) for i in range( len( p ) ) ]

def pointer( env = None ):
    """( false positives, false negatives, incomplete named calls, windowed roots seen ) over PCASES in both forms"""
    fp, fn, inc, win = [], [], [], 0
    for root, verb, sel in PCASES:
        for form in ( [], [ "--format=columnar" ] ):
            rc, t = run( root, [ "--%s=%s" % ( verb, sel ) ] + form, env )
            r, name = root_tag( t ), "--%s=%s %s" % ( verb, sel, " ".join( form ) )
            has, nxt = attr( r, "has_more" ) == "1", attr( r, "all_next" )
            if rc != 0 or not r:
                fn.append( "%s: rc=%s" % ( name, rc ) ); continue
            win += 1 if has else 0
            if nxt is not None and not has:
                fp.append( name )
            if nxt is None and has:
                fn.append( name )
            if nxt is None or not has or form:
                continue
            # (P2) the XML rows, paged to the end by the root's own next_offset=
            paged, page, guard = [], t, 0
            while guard < 64:
                paged += s_rows_xml( page ); guard += 1
                pr = root_tag( page )
                if attr( pr, "has_more" ) != "1":
                    break
                _, page = run( root, [ "--%s=%s" % ( verb, sel ), "--offset=%s" % attr( pr, "next_offset" ) ] )
            argv = shlex.split( nxt.replace( "&amp;", "&" ).replace( "&lt;", "<" ).replace( "&gt;", ">" ).replace( "&quot;", '"' ) )
            ra, a = run( root, argv, env )
            ar, got = root_tag( a ), s_rows_columnar( a )
            if ra != 0 or attr( ar, "has_more" ) == "1" or attr( ar, "dc_shown" ) is not None or got != paged or "--format=columnar" not in argv:
                inc.append( "%s -> %s: rc=%s has_more=%s dc_shown=%s rows %s vs %d paged" % (
                    name, nxt, ra, attr( ar, "has_more" ), attr( ar, "dc_shown" ), "none" if got is None else len( got ), len( paged ) ) )
    return fp, fn, inc, win
fp, fn, inc, win = pointer()
say( not fp and not fn and win >= 4, "(P1) exact", "all_next= rides exactly the windowed roots: %d false positives, %d false negatives on %d documents (%d windowed)" % (
     len( fp ), len( fn ), 2 * len( PCASES ), win ), "FP %s FN %s" % ( fp[ :3 ], fn[ :3 ] ) )
say( not inc and win >= 4, "(P2) complete", "each named call, run verbatim: no has_more=\"1\", no dc_shown=, rows equal the XML rows paged to the end, in order", "; ".join( inc[ :2 ] ) )
say( not fp, "(P3) unwindowed", "a root that does not window carries no all_next=", str( fp[ :3 ] ) )
rc, t = run( W, [ "--impact=leaf" ] )
r = root_tag( t )
say( rc == 0 and ( attr( r, "all_next" ) or "" ).endswith( "--limit=%s" % max( int( attr( r, "total" ) or 0 ), int( attr( r, "declined_calls" ) or 0 ) ) )
     and int( attr( r, "declined_calls" ) or 0 ) > int( attr( r, "total" ) or 0 ) > 40, "(P2) both tiers",
     "more declined sites than rows: the named limit is the larger, so the complete call cuts neither", r[ :400 ] )

# ── (M) the registered mutation controls ──────────────────────────────────────────────────────────────────────────────────────
print( "=== (M) each registered mutant makes its arm fail ===" )
def mut( tag, env, failed, what ):
    say( failed, "(M) %s" % tag, "%s -> %s" % ( what, "RED, as registered" if failed else "the arm still passes: it asserts nothing" ) )
DC = lambda v: { MUT: v }
b, _ = sweep( DC( "dropgate" ) );  mut( "dropgate", None, bool( b[ "D1" ] ), "the gate column is not written: (D1)" )
b, _ = sweep( DC( "dropvia" ) );   mut( "dropvia", None, bool( b[ "D3" ] ), "the block carries no via=: (D3)" )
b, _ = sweep( DC( "lastrow" ) );   mut( "lastrow", None, bool( b[ "D4" ] ) and bool( b[ "D1" ] ), "the last site is left out of every array: (D4) and (D1)" )
mut( "verbatim", None, bool( sweep( VERBATIM )[ 0 ][ "D1" ] ) and bool( d2( VERBATIM ) ), "the rows are printed as before: (D1), and (D2)'s 40 % bound" )
f1, f2, i3, _ = pointer( { "RIPWIRE_TEST_HANDOFF_MUTANT": "allnextalways" } )
mut( "allnextalways", None, bool( f1 ), "the pointer rides a root that does not window: (P1) false positive" )
f1, f2, i3, _ = pointer( { "RIPWIRE_NO_WINDOW_HANDOFF": "1" } )
mut( "pointer off", None, bool( f2 ), "RIPWIRE_NO_WINDOW_HANDOFF=1: (P1) false negative" )
f1, f2, i3, _ = pointer( { "RIPWIRE_TEST_HANDOFF_MUTANT": "limitminus1" } )
mut( "limitminus1", None, bool( i3 ), "the named limit is one short: (P2)" )

# ── (I) determinism and well-formedness ───────────────────────────────────────────────────────────────────────────────────────
print( "=== (I) determinism, well-formedness ===" )
off = []
for args in ( [ "--impact=leaf", "--format=columnar", "--limit=400" ], [ "--callers=de,fs/c0.py:poll", "--format=columnar", "--legend=full" ], [ "--impact=leaf" ] ):
    a, b = run( W, args )[ 1 ], run( W, args )[ 1 ]
    try:
        ET.fromstring( "<x>" + a + "</x>" )
    except ET.ParseError as e:
        off.append( "%s: not well-formed: %s" % ( " ".join( args ), e ) )
    if a != b or not a or "\n" in a.rstrip( "\n" ):
        off.append( "%s: two runs differ, the answer is empty, or it holds a newline" % " ".join( args ) )
say( not off, "(I)", "two runs byte-identical, each answer parses as XML, no newline inside", "; ".join( off[ :2 ] ) )

print( "dccolumnarcheck: %d passed, %d failed" % ( npass, nfail ) )
sys.exit( 1 if nfail else 0 )
PY

if [ "$fail" -ne 0 ]; then echo "dccolumnarcheck: FAILURES"; exit 1; fi
echo "dccolumnarcheck: ALL PASS"
