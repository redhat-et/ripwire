#!/usr/bin/env bash
# unrescalleescheck.sh — a call whose name IS defined in this tree but that kept no edge and no decline record is named on
# the caller's --callees answer, in one <unres n= calls= more=> line, instead of being silently absent.
#
#   test/unrescalleescheck.sh                         # uses build/ripwire on test/unrescalleesfix
#   RIPWIRE_BIN=asan/ripwire test/unrescalleescheck.sh
#   test/unrescalleescheck.sh build_base/ripwire      # the RED run (a pre-change binary): arms A, B, F, G and H fail
#
# THE GAP (CALLEE-GAP, BRIEF-SHAPE-AUDIT 11-25 + the 61-cell re-measure of 11-27). The resolver gives every call reference one
# disposition (pincensus.h CallDisposition). Bound calls are <s> rows, declined ones <dc> rows, standard-member declines the
# <stdm> line, and a name with no in-tree definition is an outside call. Two dispositions had no per-answer trace at all:
# Unresolved (every in-tree definition of the name was filtered — another language, a known-indirect call, a local or
# closure, a refused ES import) and QualifiedExternal (the written Rust qualifier ruled every in-tree definition out). Only
# the corpus-wide graph_unresolved= gauge counted the first. cpython's PyErr_Occurred (its C definition is not extracted, so
# only a Python test definition is in reach) and zed's re-exported `language_model::read_credentials` were absent from
# every callees answer that makes them.
#
# THE FIX. buildGraph records ( caller, reference ) for those two dispositions (Graph::unresolvedSites, kept in the warm
# snapshot); the callees answer names the CALLED names once, first call first, at most kUnresolvedNamesCap (8), more= the
# rest, calls= every such call — after the <stdm> line, on XML, --json and the MCP find_symbol twin. NOT an edge: no count=,
# no row, no hop_tested=.
#
# ARMS (test/unrescalleesfix, see its README; P = positive, C = control/negative, each control counts what it saw):
#   (A) c/run.c:run calls py_only, defined only in py/tool.py: <unres n="py_only" calls="1"/>; count= and the <s> rows unchanged
#       (A0 premise: the answer's graph_unresolved= is 1, and py_only has no C definition in the fixture)
#   (B) rs/src/lib.rs:load calls api::read_key(), a `pub use` re-export the qualifier rules out: <unres n="read_key" calls="1"/>
#       (B0 premise: the answer has no row and no <dc>, so the call kept no edge)
#   (C) never on the line: strlen (no in-tree definition), shared (two declines, two <dc> rows), local_c (a row)
#   (D) 0 bytes: c/leaf.c:quiet (one row, nothing unresolved) carries neither the line nor its legend clause
#   (E) the legend clause rides exactly when the line does (A's answer has it)
#   (F) dialects: --json "unres" and the MCP find_symbol "unres" are the same object; the columnar form carries neither
#   (G) the cap: 10 distinct unresolved names → n= lists the first 8 in body order, more="2", calls="11" (one name twice)
#   (H) the warm snapshot keeps it: a cached second run loads the graph (snapshot-stats graph=loaded) and answers byte-identically
#   (K) the predicates can fail: a missing line, a line in the rows' count and a wrong calls= are each caught
set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"          # a relative binary is relative to the caller's cwd
echo "unrescalleescheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
[ -d "$ROOT/test/unrescalleesfix" ] || { echo "fixture missing: test/unrescalleesfix"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

python3 - "$BIN" "$ROOT" "$TMP" <<'PY' || no "the arms above did not all pass (or the checker itself failed): python rc != 0"
import json, os, re, shutil, subprocess, sys, time

BIN, ROOT, TMP = sys.argv[1], sys.argv[2], sys.argv[3]
FIX = os.path.join( ROOT, "test", "unrescalleesfix" )
npass = nfail = 0

def say( good, tag, msg, why = "" ):
    global npass, nfail
    if good:
        npass += 1; print( "  PASS  %s: %s" % ( tag, msg ) )
    else:
        nfail += 1; print( "  FAIL  %s: %s%s" % ( tag, msg, ( " -- " + why ) if why else "" ) )

def run( root, *args, env = None, cache = False ):
    """( rc, stdout, stderr ) of one CLI answer; rc 124 on a timeout."""
    try:
        p = subprocess.run( [ BIN, root ] + ( [] if cache else [ "--no-cache" ] ) + list( args ), capture_output = True, text = True,
                            timeout = 240, env = env, cwd = root )
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 124, "", ""

def mcp( tool, arguments ):
    """The MCP tool's text payload parsed as JSON, or None (initialize + one tools/call over stdio)."""
    req = json.dumps( { "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {} } ) + "\n" + json.dumps(
        { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": tool, "arguments": arguments } } ) + "\n"
    try:
        p = subprocess.run( [ BIN, "--mcp" ], input = req, capture_output = True, text = True, timeout = 240, cwd = FIX )
    except subprocess.TimeoutExpired:
        return None
    for line in p.stdout.splitlines():
        try:
            r = json.loads( line )
        except ValueError:
            continue
        if r.get( "id" ) == 2 and "result" in r:
            try:
                return json.loads( r[ "result" ][ "content" ][ 0 ][ "text" ] )
            except ( ValueError, KeyError, IndexError, TypeError ):
                return None
    return None

class Answer:
    """One XML callees answer: its legend, root attributes, <s> rows, <dc> rows and <unres> lines."""
    def __init__( self, rc, text ):
        self.rc, self.text = rc, text
        self.legend, _, self.body = text.partition( "-->" ) if "-->" in text else ( "", "", text )
        m = re.search( r"<callees [^>]*>", self.body )
        self.ok = rc == 0 and m is not None and self.body.rstrip().endswith( "</callees>" )
        self.root = dict( re.findall( r'(\w+)="([^"]*)"', m.group( 0 ) ) ) if m else {}
        self.rows = re.findall( r"<s [^>]*?\bn=\"([^\"]*)\"", self.body )
        self.dc = re.findall( r"<dc [^>]*?\bn=\"([^\"]*)\"", self.body )
        self.unres = [ dict( re.findall( r'(\w+)="([^"]*)"', u ) ) for u in re.findall( r"<unres [^>]*/>", self.body ) ]
    def a( self, k ):
        return self.root.get( k )
    def names( self ):
        return [ n for u in self.unres for n in u.get( "n", "" ).split( "," ) if n ]
    def why( self ):
        return self.body[ :400 ]

def ask( root, sel, *extra ):
    rc, out, _ = run( root, "--callees=" + sel, *extra )
    return Answer( rc, out )

CLAUSE = "unres n= calls= more=:"   # the compact (default) clause; --legend=full spells <unres n= calls= more=>:

# ── (A) a call whose every definition is another language's ────────────────────────────────────────────────────────
print( "=== (A) Unresolved: every in-tree definition is another language's ===" )
run_ = ask( FIX, "c/run.c:run" )
say( run_.ok and run_.a( "graph_unresolved" ) == "1", "[C] a0_premise_gauge", "the answer's graph_unresolved= is 1 (the call IS unresolved)", run_.why() )
pyonly_c = [ f for d, _, fs in os.walk( FIX ) for f in fs if f.endswith( ".c" ) and "py_only(" in open( os.path.join( d, f ) ).read().replace( "py_only( s )", "" ) ]
say( pyonly_c == [] and "def py_only" in open( os.path.join( FIX, "py", "tool.py" ) ).read(), "[C] a0_premise_defs",
     "py_only is defined only in py/tool.py (no C definition in the fixture)", str( pyonly_c ) )
say( run_.ok and run_.unres == [ { "n": "py_only", "calls": "1" } ], "[P] a_line", "<unres n=\"py_only\" calls=\"1\"/>", run_.why() )
say( run_.ok and run_.rows == [ "local_c" ] and run_.a( "count" ) == "1" and run_.a( "hop_untested" ) == "1", "[C] a_not_edge",
     "count=\"1\", one <s> row (local_c): the line is in no count and no row", run_.why() )

# ── (B) a qualified call the qualifier rules out ───────────────────────────────────────────────────────────────────
print( "=== (B) QualifiedExternal: a re-exported fn the written qualifier rules out ===" )
load = ask( FIX, "rs/src/lib.rs:load" )
say( load.ok and load.rows == [] and load.dc == [] and load.a( "count" ) == "0", "[C] b0_premise", "load's answer has no row and no <dc>", load.why() )
say( load.ok and load.unres == [ { "n": "read_key", "calls": "1" } ], "[P] b_line", "<unres n=\"read_key\" calls=\"1\"/>", load.why() )

# ── (C) never on the line ──────────────────────────────────────────────────────────────────────────────────────────
print( "=== (C) bound, declined and undefined calls are never on the line ===" )
seen = len( run_.rows ) + len( run_.dc )
say( seen == 3 and run_.dc == [ "shared", "shared" ], "[C] c0_premise", "the controls are there to be read: 1 row + 2 <dc> rows", "rows=%s dc=%s" % ( run_.rows, run_.dc ) )
bad = [ n for n in ( "strlen", "shared", "local_c" ) if n in run_.names() ]
say( run_.ok and run_.unres != [] and bad == [], "[P] c_controls", "strlen (undefined), shared (declined), local_c (bound) are not on the line", str( bad ) )

# ── (D) 0 bytes where nothing is unresolved ────────────────────────────────────────────────────────────────────────
print( "=== (D) 0 bytes on an answer with nothing unresolved ===" )
quiet = ask( FIX, "c/leaf.c:quiet" )
say( quiet.ok and quiet.rows == [ "local_c" ], "[C] d0_premise", "quiet's answer has its row", quiet.why() )
say( quiet.ok and "<unres" not in quiet.body and CLAUSE not in quiet.legend, "[P] d_zero", "neither the line nor its clause", quiet.why() )

# ── (E) the legend clause rides with the line ──────────────────────────────────────────────────────────────────────
print( "=== (E) the legend ===" )
say( run_.ok and run_.legend.count( CLAUSE ) == 1 and load.legend.count( CLAUSE ) == 1, "[P] e_clause", "A's and B's (compact) legends define <unres> once each" )
rc, full, _ = run( FIX, "--callees=c/run.c:run", "--legend=full" )
say( rc == 0 and full.partition( "-->" )[ 0 ].count( "<unres n= calls= more=>:" ) == 1, "[P] e_full", "the --legend=full clause rides once", full[ :200 ] )

# ── (F) dialects ───────────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (F) --json, MCP, columnar ===" )
rc, js, _ = run( FIX, "--callees=c/run.c:run", "--json" )
try:
    cj = json.loads( js )
except ValueError:
    cj = {}
say( cj.get( "unres" ) == { "n": "py_only", "calls": 1 } and cj.get( "count" ) == 1, "[P] f_json", "--json \"unres\":{\"n\":\"py_only\",\"calls\":1}, count 1", str( cj.get( "unres" ) ) )
m = mcp( "find_symbol", { "path": FIX, "symbol": "c/run.c:run" } ) or {}
say( m != {} and m.get( "unres" ) == cj.get( "unres" ) and m.get( "unres" ) is not None, "[P] f_mcp", "MCP find_symbol \"unres\" == the CLI --json \"unres\"",
     "mcp=%s cli=%s" % ( m.get( "unres" ), cj.get( "unres" ) ) )
rc, col, _ = run( FIX, "--callees=c/run.c:run", "--format=columnar" )
say( rc == 0 and "local_c" in col and "<unres" not in col and CLAUSE not in col, "[C] f_columnar", "the columnar form carries neither (as with <stdm>)", col[ :300 ] )

# ── (G) the cap ────────────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (G) the name cap ===" )
cap = os.path.join( TMP, "cap" ); os.makedirs( os.path.join( cap, "py" ) ); os.makedirs( os.path.join( cap, "c" ) )
with open( os.path.join( cap, "py", "defs.py" ), "w" ) as f:
    f.write( "".join( "def p%d():\n    return %d\n" % ( i, i ) for i in range( 10 ) ) )
with open( os.path.join( cap, "c", "many.c" ), "w" ) as f:
    f.write( "int many( void )\n{\n    int n = 0;\n" + "".join( "    n += p%d();\n" % i for i in ( 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 9 ) ) + "    return n;\n}\n" )
mny = ask( cap, "c/many.c:many" )
say( mny.ok and mny.unres == [ { "n": "p9,p8,p7,p6,p5,p4,p3,p2", "calls": "11", "more": "2" } ], "[P] g_cap",
     "n= the first 8 names in body order, more=\"2\", calls=\"11\"", str( mny.unres ) )

# ── (H) the warm snapshot ──────────────────────────────────────────────────────────────────────────────────────────
print( "=== (H) the warm snapshot keeps the records ===" )
warm = os.path.join( TMP, "warm" ); shutil.copytree( FIX, warm )
# a file stamped inside the snapshot's racy window (a fresh copy) keeps the save from being trusted: age the copy past it
past = time.time() - 60
for d, _, fs in os.walk( warm ):
    for f in fs:
        os.utime( os.path.join( d, f ), ( past, past ) )
env = dict( os.environ, HOME = os.path.join( TMP, "home" ), TMPDIR = os.path.join( TMP, "tmp" ), RIPWIRE_SNAPSHOT_STATS = "1" )
os.makedirs( env[ "HOME" ] ); os.makedirs( env[ "TMPDIR" ] )
outs = [ run( warm, "--callees=c/run.c:run", env = env, cache = True ) for _ in range( 3 ) ]
loaded = [ "graph=loaded" in e for _, _, e in outs ]
say( loaded[ 1 ] or loaded[ 2 ], "[C] h0_premise", "a cached run loads the graph from the snapshot", " | ".join( e.strip()[ -160: ] for _, _, e in outs ) )
cold = ask( warm, "c/run.c:run" )
say( all( o == cold.text for _, o, _ in outs ) and Answer( 0, outs[ 2 ][ 1 ] ).unres == [ { "n": "py_only", "calls": "1" } ], "[P] h_warm",
     "cached cold, warm and --no-cache answers are byte-identical and carry the line" )

# ── (K) the predicates can fail ────────────────────────────────────────────────────────────────────────────────────
print( "=== (K) the predicates reject what they must ===" )
fake = Answer( 0, '<callees of="x" count="1"><s n="local_c"/></callees>' )
say( fake.ok and fake.unres != [ { "n": "py_only", "calls": "1" } ], "[C] k_missing", "a missing <unres> line is caught" )
fake = Answer( 0, '<callees of="x" count="2"><s n="local_c"/><s n="py_only"/></callees>' )
say( fake.ok and ( fake.rows != [ "local_c" ] or fake.a( "count" ) != "1" ), "[C] k_in_count", "the call folded into the rows / count= is caught" )
fake = Answer( 0, '<callees of="x" count="1"><s n="local_c"/><unres n="py_only" calls="2"/></callees>' )
say( fake.ok and fake.unres != [ { "n": "py_only", "calls": "1" } ], "[C] k_calls", "a wrong calls= is caught" )

print( "unrescalleescheck: %d PASS / %d FAIL" % ( npass, nfail ) )
sys.exit( 1 if nfail else 0 )
PY
if [ "$fail" = 0 ]; then echo "unrescalleescheck: PASS"; else echo "unrescalleescheck: FAIL"; exit 1; fi
