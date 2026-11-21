#!/usr/bin/env bash
# dctiercutcheck.sh — BAND DC (docs/EVALS.md, pre-registration 2026-11-17 amendment 10c): an answer the tool names as the complete
# call either lists every row of every tier, or says which tier it cut, that tier's count, and the call that lists it all.
#
# WHY. --limit sizes two listings on --callers and --impact: the symbol rows (shown= / total= / capped=) and the declined call
# sites (<dc>, <dcols>). The call a windowed root names (all_next=, and the --for hand-off's next= beside windows="1") carries
# --limit=<row total> (amendment 10b: a limit that cleared both tiers nearly doubled the median bytes to every row), so where the
# answer holds more declined sites than rows that call still cuts them. It says so: shown_dc= (the sites printed), declined_calls=
# (the tier's count, a floor under counts_floor="1"), dc_next= (the call that lists every site). That disclosure was asserted by one
# arm on one surface and no mutation had shown the arm can fail. This gate asserts it on every surface and breaks it three ways.
#
#   (T1) a cut tier is SAID: each named call — and the same question as XML, under --legend=full, as --json, and through the MCP
#        twin at the same limit — that prints fewer declined sites than declined_calls= carries shown_dc= and dc_next= on its root.
#   (T2) the disclosure is arithmetic: shown_dc= equals the sites printed (<dc> rows; <dcols n=> and every array; the JSON list),
#        shown_dc < declined_calls, counts_floor rides the same root, and the answer's own legend / note defines shown_dc=.
#   (T3) dc_next=, run verbatim, clears BOTH tiers: rc 0, no shown_dc=, no has_more="1", declined_calls= sites listed, and the same
#        symbol rows as the named call, in the same form.
#   (T4) no false alarm: an answer whose declined tier is whole carries neither attribute (a named call whose rows outnumber its
#        declined sites; a small answer under the default cut).
#   (H1) --help: the --impact paragraph that names all_next= scopes it to total= and names shown_dc= and dc_next=.
#   (N)  non-vacuity: a named call that cuts the tier on --impact, on --callers and through a --for hand-off; one that does not.
#   (M)  the registered mutation controls, RIPWIRE_TEST_DCCUT_MUTANT in the real binary, each of which must turn its arm RED:
#        silentcut -> (T1)   reader: a cut answer reads as whole
#        nextshort -> (T3)   reader: the call named as listing every site does not
#        cutalways -> (T4)   bytes, and a whole answer called cut
#   (I)  two runs byte-identical; every XML answer parses.
#
# Usage: bash test/dctiercutcheck.sh [BIN]     (or RIPWIRE_BIN=...). Exits non-zero on any failure.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"          # a relative binary is relative to the caller's cwd
echo "dctiercutcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "dctiercutcheck: python3 required"; exit 2; }
unset RIPWIRE_TEST_DCCUT_MUTANT RIPWIRE_TEST_DCCOLS_MUTANT RIPWIRE_TEST_HANDOFF_MUTANT RIPWIRE_NO_WINDOW_HANDOFF
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export PYTHONDONTWRITEBYTECODE=1
fail=0
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# Every arm runs in the Python below; its exit status (1 on any FAIL arm, anything else on a crash) is the accumulator's input.
python3 - "$BIN" "$TMP" <<'PY' || no "the arms above did not all pass (or the checker itself failed): python rc != 0"
import json, os, re, shlex, subprocess, sys
import xml.etree.ElementTree as ET

BIN, TMP = sys.argv[1], sys.argv[2]
MUT = "RIPWIRE_TEST_DCCUT_MUTANT"
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

def run( args, env = None ):
    """( rc, stdout ) of one CLI answer over the fixture; rc 124 on a timeout. `env` adds variables (a mutation control)."""
    e = dict( os.environ ); e.update( env or {} )
    try:
        p = subprocess.run( [ BIN, W, "--no-cache" ] + list( args ), capture_output = True, text = True, timeout = 240, env = e )
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired:
        return 124, ""

def mcp( tool, arguments, env = None ):
    """The MCP tool's text payload (initialize + one tools/call over stdio), or "" when the call did not answer."""
    e = dict( os.environ ); e.update( env or {} )
    req = json.dumps( { "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
              "protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": { "name": "dctiercutcheck", "version": "0" } } } ) + "\n" + json.dumps(
          { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": tool, "arguments": arguments } } ) + "\n"
    try:
        p = subprocess.run( [ BIN, "--mcp" ], input = req, capture_output = True, text = True, timeout = 240, env = e )
    except subprocess.TimeoutExpired:
        return ""
    for line in p.stdout.splitlines():
        try:
            o = json.loads( line )
        except ValueError:
            continue
        if o.get( "id" ) == 2 and "result" in o:
            return o[ "result" ][ "content" ][ 0 ][ "text" ]
    return ""

def body( text ):
    """the answer without its comments (a legend spells shown_dc= and <dcols ...> to define them)"""
    return re.sub( r"<!--.*?-->", "", text, flags = re.S )

def attr( tag, name ):
    m = re.search( r' %s="([^"]*)"' % re.escape( name ), tag )
    return m.group( 1 ) if m else None

def unesc( s ):
    return s.replace( "&apos;", "'" ).replace( "&quot;", '"' ).replace( "&lt;", "<" ).replace( "&gt;", ">" ).replace( "&amp;", "&" )

class Ans:
    """One answer, whatever its surface, read down to the facts the rule is about. Every field is read from the answer itself:
    `sites` the declined call sites actually printed, `rows` the symbol rows actually printed (order kept), None where unreadable."""
    def __init__( self, text, name ):
        self.name, self.text, self.ok = name, text, False
        self.declined = self.shown_dc = self.dc_next = self.has_more = self.floor = None
        self.sites, self.rows, self.arrays_ok, self.defines = None, None, True, False
        t = text.lstrip()
        if t.startswith( "{" ):
            self._json( t )
        elif t:
            self._xml( text )
    def _json( self, t ):
        try:
            j = json.loads( t )
        except ValueError:
            return
        self.ok       = True
        self.declined = j.get( "declined_calls", 0 )
        self.shown_dc = j.get( "shown_dc" )
        self.dc_next  = j.get( "dc_next" )
        self.has_more = "1" if j.get( "has_more" ) else "0"
        self.floor    = j.get( "counts_floor" ) is True
        dc            = j.get( "dc", j.get( "declined_sites", [] ) )
        self.sites    = len( dc )
        rows          = j.get( "impact", j.get( "callers", j.get( "calledBy", [] ) ) )
        self.rows     = [ json.dumps( r, sort_keys = True ) for r in rows ]
        # the CLI --json form carries no legend; the MCP twin's declined_note is its definition
        self.defines  = "shown_dc" in j.get( "declined_note", "" ) if "declined_note" in j else None
    def _xml( self, text ):
        b = body( text )
        m = re.search( r"<(callers|impact) [^>]*>", b )
        if m is None:
            return
        r = m.group( 0 )
        self.ok       = True
        self.declined = int( attr( r, "declined_calls" ) or 0 )
        self.shown_dc = int( attr( r, "shown_dc" ) ) if attr( r, "shown_dc" ) is not None else None
        self.dc_next  = unesc( attr( r, "dc_next" ) ) if attr( r, "dc_next" ) is not None else None
        self.has_more = attr( r, "has_more" )
        self.floor    = attr( r, "counts_floor" ) == "1"
        self.defines  = "shown_dc=" in "".join( re.findall( r"<!--.*?-->", text, flags = re.S ) )
        blk = re.search( r"<dcols( [^>]*)>(.*?)</dcols>", b, re.S )
        if blk is not None:
            self.sites = int( attr( blk.group( 1 ), "n" ) or -1 )
            for f in ( attr( blk.group( 1 ), "fields" ) or "" ).split( "," ):
                c = re.search( r"<%s>(.*?)</%s>" % ( f, f ), blk.group( 2 ), re.S )
                self.arrays_ok = self.arrays_ok and c is not None and len( c.group( 1 ).split( "," ) ) == self.sites
        else:
            self.sites = len( re.findall( r"<dc [^>]*/>", b ) )
        cols = re.search( r"<cols [^>]*>(.*?)</cols>", b, re.S )
        if cols is not None:
            col = lambda f: ( re.search( r"<%s>(.*?)</%s>" % ( f, f ), cols.group( 1 ), re.S ) or [ "", "" ] )[ 1 ].split( "," )
            self.rows = list( zip( col( "name" ), col( "line" ) ) )
        else:
            self.rows = re.findall( r'<s t="[^"]*" n="[^"]*" p="[^"]*"', b )
    def cut( self ):
        return self.ok and self.sites is not None and self.sites < self.declined
    def said( self ):
        return self.shown_dc is not None and bool( self.dc_next )

# ── the generated tree. Three families, each built so the numbers below are facts of the tree and are RE-READ by (N):
#    leaf:  300 proven callers + C0.poll calls it (301 rows); 10 same-named `poll` methods, 360 declined x.poll() sites  -> impact cut
#    tick:  300 proven callers of E0.tick; 10 same-named `tick` methods, 400 declined x.tick() sites                     -> callers cut
#    quiet: 120 proven callers + D0.ping calls it (121 rows); 3 same-named `ping` methods, 30 declined x.ping() sites     -> NOT cut
#    zap:   2 same-named methods, 5 declined sites: under the default cut of 16, never cut ──────────────────────────────────────
W = os.path.join( TMP, "w" )
def put( rel, text ):
    p = os.path.join( W, rel )
    os.makedirs( os.path.dirname( p ), exist_ok = True )
    with open( p, "w" ) as h:
        h.write( text )
def family( d, cls, meth, n, calls ):
    for k in range( n ):
        put( "%s/%s%d.py" % ( d, cls.lower(), k ), "class %s%d:\n    def %s(self):\n        return %s\n" % ( cls, k, meth, ( calls + "()" ) if k == 0 and calls else str( k ) ) )
def declined( d, meth, files, per ):
    for f in range( files ):
        put( "%s/u%d.py" % ( d, f ), "".join( "def use_%s_%d_%d(x):\n    return x.%s()\n\n\n" % ( meth, f, k, meth ) for k in range( per ) ) )
def fan( d, target, files, per ):
    for f in range( files ):
        put( "%s/f%d.py" % ( d, f ), "".join( "def call_%s_%d_%d():\n    return %s()\n\n\n" % ( target, f, k, target ) for k in range( per ) ) )
put( "core.py", "def leaf():\n    return 1\n\n\ndef quiet():\n    return 2\n" )
family( "cs", "C", "poll", 10, "leaf" );  declined( "usepoll", "poll", 6, 60 );  fan( "fanleaf", "leaf", 6, 50 )
family( "ds", "D", "ping", 3, "quiet" );  declined( "useping", "ping", 3, 10 );  fan( "fanquiet", "quiet", 4, 30 )
family( "zs", "Z", "zap", 2, "" );        declined( "usezap", "zap", 1, 5 )
family( "es", "E", "tick", 10, "" );      declined( "usetick", "tick", 8, 50 )
for f in range( 6 ):
    put( "pr/p%d.py" % f, "from es.e0 import E0\n\n\n" + "".join( "def pr_%d_%d():\n    e = E0()\n    return e.tick()\n\n\n" % ( f, k ) for k in range( 50 ) ) )

TWIN = { "impact": "impact", "callers": "find_referencing_symbols" }

def named_call( verb, sel, env = None, via_for = None ):
    """The call the tool names as complete for --VERB=SEL, as argv: the direct root's all_next=, or the --for hand-off's next=."""
    if via_for:
        _, t = run( [ "--for=" + via_for ], env )
        m = re.search( r'<callers\b(?![^>]*schema=)[^>]*windows="1"[^>]*>', t )
        nxt = attr( m.group( 0 ), "next" ) if m else None
    else:
        _, t = run( [ "--%s=%s" % ( verb, sel ) ], env )
        m = re.search( r"<(callers|impact) [^>]*>", body( t ) )
        nxt = attr( m.group( 0 ), "all_next" ) if m else None
    return shlex.split( unesc( nxt ) ) if nxt else None

def surfaces( verb, sel, argv, env = None ):
    """The named call, verbatim, and the same question at the same limit on every other surface: [ ( Ans, rerun ) ], where
    rerun( limit ) asks that surface again at another limit (how dc_next='s limit is put to a surface with no CLI spelling)."""
    limit = int( argv[ -1 ].split( "=" )[ 1 ] )
    xml   = [ a for a in argv if a != "--format=columnar" ]
    out   = []
    for label, base in ( ( "named call (columnar)", argv ), ( "XML", xml ), ( "columnar --legend=full", argv + [ "--legend=full" ] ),
                         ( "XML --legend=full", xml + [ "--legend=full" ] ), ( "--json", xml + [ "--json" ] ) ):
        out.append( ( Ans( run( base, env )[ 1 ], "--%s=%s %s" % ( verb, sel, label ) ), None ) )
    twin = lambda n: Ans( mcp( TWIN[ verb ], { "path": W, "symbol": sel, "limit": n }, env ), "--%s=%s MCP %s limit=%d" % ( verb, sel, TWIN[ verb ], n ) )
    out.append( ( twin( limit ), twin ) )
    return out

def follow( a, rerun, env = None ):
    """dc_next= of answer `a`, run verbatim (CLI), or its limit put to the MCP twin; the answer it names."""
    argv = shlex.split( a.dc_next or "" )
    if not argv:
        return None
    if rerun is not None:
        return rerun( int( argv[ -1 ].split( "=" )[ 1 ] ) )
    if a.text.lstrip().startswith( "{" ):
        argv = argv + [ "--json" ]   # the --json answer spells its follow-up as flags; the form is the caller's
    return Ans( run( argv, env )[ 1 ], a.name + " -> dc_next" )

CUT_CELLS   = [ ( "impact", "leaf", None ), ( "callers", "es/e0.py:tick", None ), ( "impact", "leaf", "leaf" ) ]   # ( verb, selector, --for query )
WHOLE_CELLS = [ ( "impact", "quiet" ) ]

def sweep( env = None ):
    """-> dict of arm -> [ failure text ], and the non-vacuity counts, over every surface of every cell"""
    bad  = { "T1": [], "T2": [], "T3": [], "T4": [] }
    seen = { "cut": 0, "cut_impact": 0, "cut_callers": 0, "cut_for": 0, "whole": 0, "surfaces": 0, "sites_listed": 0, "sites_counted": 0 }
    for verb, sel, q in CUT_CELLS:
        argv = named_call( verb, sel, env, via_for = q )
        if not argv:
            bad[ "T1" ].append( "--%s=%s%s: no named call on the root" % ( verb, sel, " (via --for)" if q else "" ) ); continue
        for a, rerun in surfaces( verb, sel, argv, env ):
            seen[ "surfaces" ] += 1
            if not a.ok:
                bad[ "T1" ].append( "%s: no answer" % a.name ); continue
            if not a.cut():
                continue
            seen[ "cut" ] += 1
            seen[ "cut_for" if q else "cut_" + verb ] += 1
            seen[ "sites_listed" ] += a.sites; seen[ "sites_counted" ] += a.declined
            if not a.said():
                bad[ "T1" ].append( "%s: %d of %d declined sites printed, shown_dc=%s dc_next=%r" % ( a.name, a.sites, a.declined, a.shown_dc, a.dc_next ) )
                continue
            if a.shown_dc != a.sites or not a.shown_dc < a.declined or not a.arrays_ok or not a.floor or a.defines is False:
                bad[ "T2" ].append( "%s: shown_dc=%s, %s sites printed, declined_calls=%s, arrays %s, counts_floor %s, defined %s" % (
                    a.name, a.shown_dc, a.sites, a.declined, "ok" if a.arrays_ok else "RAGGED", a.floor, a.defines ) )
            f = follow( a, rerun, env )
            if f is None or not f.ok or f.shown_dc is not None or f.dc_next or f.has_more == "1" or f.sites != a.declined or f.rows != a.rows or not f.rows:
                bad[ "T3" ].append( "%s: dc_next=%r answered %s" % ( a.name, a.dc_next, "nothing" if f is None or not f.ok else
                    "%s of %s sites, shown_dc=%s, has_more=%s, %d rows against %d" % ( f.sites, a.declined, f.shown_dc, f.has_more, len( f.rows or [] ), len( a.rows or [] ) ) ) )
    for verb, sel in WHOLE_CELLS:
        argv = named_call( verb, sel, env )
        if not argv:
            bad[ "T4" ].append( "--%s=%s: no named call on the root" % ( verb, sel ) ); continue
        for a, _ in surfaces( verb, sel, argv, env ):
            seen[ "surfaces" ] += 1
            whole = a.ok and a.sites == a.declined and a.declined > 16
            seen[ "whole" ] += 1 if whole else 0
            if not whole or a.shown_dc is not None or a.dc_next:
                bad[ "T4" ].append( "%s: %s of %s sites printed, shown_dc=%s dc_next=%r" % ( a.name, a.sites, a.declined, a.shown_dc, a.dc_next ) )
    for extra in ( [], [ "--format=columnar" ], [ "--json" ] ):
        a = Ans( run( [ "--callers=zs/z0.py:zap" ] + extra, env )[ 1 ], "--callers=zs/z0.py:zap %s" % " ".join( extra ) )
        seen[ "surfaces" ] += 1
        if not a.ok or a.sites != 5 or a.declined != 5 or a.shown_dc is not None or a.dc_next:
            bad[ "T4" ].append( "%s: %s of %s sites printed, shown_dc=%s dc_next=%r" % ( a.name, a.sites, a.declined, a.shown_dc, a.dc_next ) )
    return bad, seen

print( "=== (T1) (T2) (T3) (T4) every surface of every named call ===" )
bad, seen = sweep()
say( not bad[ "T1" ], "(T1) a cut tier is said", "%d answers print fewer declined sites than declined_calls= (%d of %d listed) and each carries shown_dc= and dc_next=" % (
     seen[ "cut" ], seen[ "sites_listed" ], seen[ "sites_counted" ] ), "; ".join( bad[ "T1" ][ :3 ] ) )
say( not bad[ "T2" ], "(T2) arithmetic", "shown_dc= is the sites printed and below declined_calls=, every array is that long, counts_floor rides the root, the legend / note defines it",
     "; ".join( bad[ "T2" ][ :3 ] ) )
say( not bad[ "T3" ], "(T3) dc_next clears both tiers", "run verbatim: no shown_dc=, no has_more=\"1\", every declined site, the same symbol rows in the same form", "; ".join( bad[ "T3" ][ :3 ] ) )
say( not bad[ "T4" ], "(T4) no false alarm", "%d answers whose tier is whole (a named call with more rows than declined sites; 5 sites under the default cut) carry neither attribute" % (
     seen[ "whole" ] + 3 ), "; ".join( bad[ "T4" ][ :3 ] ) )
say( seen[ "cut_impact" ] >= 6 and seen[ "cut_callers" ] >= 6 and seen[ "cut_for" ] >= 6 and seen[ "whole" ] >= 6, "(N) non-vacuity",
     "cut answers seen: %d --impact, %d --callers, %d via the --for hand-off; whole: %d (6 surfaces a cell)" % (
     seen[ "cut_impact" ], seen[ "cut_callers" ], seen[ "cut_for" ], seen[ "whole" ] ), str( seen ) )

# ── (H1) the help sentence ────────────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (H1) --help scopes the pointer ===" )
try:
    para = subprocess.run( [ BIN, "--help=--impact" ], capture_output = True, text = True, timeout = 60 ).stdout   # that flag's full text
except subprocess.TimeoutExpired:
    para = ""
lines = [ l.strip() for l in para.splitlines() ]
at    = next( ( i for i, l in enumerate( lines ) if "all_next=" in l ), len( lines ) )
line  = " ".join( lines[ at : at + 3 ] )   # the sentence that names the pointer, and the two lines it may wrap onto
say( "all_next=" in para and "every row of total=" in line and "shown_dc=" in line and "dc_next=" in line and "declined" in line, "(H1) help",
     "the --impact paragraph names all_next= as every row of total=, and shown_dc= / dc_next= for the declined call sites beside it", line[ :260 ] or "no --impact paragraph naming all_next= was found" )

# ── (M) the registered mutation controls ──────────────────────────────────────────────────────────────────────────────────────
print( "=== (M) each registered mutant makes its arm fail ===" )
def mut( name, arm, what ):
    b, _ = sweep( { MUT: name } )
    say( bool( b[ arm ] ), "(M) %s" % name, "%s -> %s" % ( what, "RED, as registered (%d failures, e.g. %s)" % ( len( b[ arm ] ), b[ arm ][ 0 ][ :150 ] ) if b[ arm ]
         else "the arm still passes: it asserts nothing, or the binary has no such mutant" ) )
mut( "silentcut", "T1", "the tier is cut and the root says neither shown_dc= nor dc_next=: (T1)" )
mut( "nextshort", "T3", "dc_next= names a limit one site short: (T3)" )
mut( "cutalways", "T4", "shown_dc= / dc_next= ride an answer whose tier is whole: (T4)" )

# ── (I) determinism and well-formedness ───────────────────────────────────────────────────────────────────────────────────────
print( "=== (I) determinism, well-formedness ===" )
off = []
for args in ( [ "--impact=leaf", "--format=columnar", "--limit=301" ], [ "--impact=leaf", "--limit=301" ], [ "--callers=es/e0.py:tick", "--format=columnar", "--limit=300" ],
              [ "--impact=quiet", "--format=columnar", "--limit=121" ] ):
    a, b = run( args )[ 1 ], run( args )[ 1 ]
    try:
        ET.fromstring( "<x>" + a + "</x>" )
    except ET.ParseError as e:
        off.append( "%s: not well-formed: %s" % ( " ".join( args ), e ) )
    if a != b or not a or "\n" in a.rstrip( "\n" ):
        off.append( "%s: two runs differ, the answer is empty, or it holds a newline" % " ".join( args ) )
say( not off, "(I)", "two runs byte-identical, each answer parses as XML, no newline inside", "; ".join( off[ :2 ] ) )

print( "dctiercutcheck: %d passed, %d failed" % ( npass, nfail ) )
sys.exit( 1 if nfail else 0 )
PY

if [ "$fail" -ne 0 ]; then echo "dctiercutcheck: FAILURES"; exit 1; fi
echo "dctiercutcheck: ALL PASS"
