#!/usr/bin/env bash
# mcpnextcallcheck.sh — every MCP tool-execution refusal names the ripwire call to make next, and that call works.
#
# Xu & Wu, "MCP Error Messages Written for Developers Hurt the Most Capable Agents Most" (2609.35381): of 3,001
# error messages in 150 MCP servers, a recovery step that named a terminal command left 45% of tasks recovered,
# while a step naming a SERVER TOOL raised it to 84-88%, and the loss grew with model capability. So the contract
# is: every isError this server sends (and every found=0 answer's refusal sentence) ends in
#     — next: <tool> field="value" ...
# naming a tool the server answers, in argument spelling, and that call is WELL-FORMED: sent back through
# tools/call (with the same root) it is not refused for its own arguments (no missing / unknown / invalid field,
# no unknown tool). It may still answer "not found": the example values are the table's, not this tree's names.
#
# Arms, each driven over the refusal table rather than restated (the M14 lesson):
#   (M) every advertised tool called with no arguments: a missing-field refusal names a next call;
#   (V) every value-taking field of every tool, sent with a wrong-shaped value: the bad-value refusal does;
#   (U) every tool with an undeclared field (a near-miss of a declared one, and a far one);
#   (N) the not-found family (symbol / type / file), with a near-miss and without;
#   (B) business-logic refusals the minimal call would only repeat (rank_by=churn, a frameless trace, ...);
#   (R) every next call above round-trips well-formed.
# Red on the pre-next-call binary: every arm (no refusal named a next call).
#
# Usage:  test/mcpnextcallcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "mcpnextcallcheck: BIN=$BIN"

python3 - "$BIN" "$TMP" <<'PY'
import json, os, re, subprocess, sys
BIN, TMP = sys.argv[1], sys.argv[2]
fails = 0
def check( cond, msg ):
    global fails
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: fails += 1

repo = os.path.join( TMP, "repo" )
os.makedirs( os.path.join( repo, "src" ) )
SRC = "int helper( int x ) { return x + 1; }\nint caller( void ) { return helper( 2 ); }\n"
open( os.path.join( repo, "src", "a.c" ), "w" ).write( SRC )
for cmd in ( [ "git", "init", "-q" ], [ "git", "add", "-A" ], [ "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "i" ] ):
    subprocess.run( cmd, cwd = repo, stdout = subprocess.DEVNULL, stderr = subprocess.DEVNULL )

def session( reqs ):
    lines = [ '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}' ]
    for i, r in enumerate( reqs, 1 ):
        lines.append( json.dumps( dict( { "jsonrpc": "2.0", "id": i }, **r ) ) )
    out = subprocess.run( [ BIN, "--mcp" ], input = "\n".join( lines ) + "\n", capture_output = True, text = True,
                          cwd = repo, errors = "replace" ).stdout
    byId = {}
    for l in out.splitlines():
        try:
            o = json.loads( l )
        except ValueError:
            continue
        byId[ o.get( "id" ) ] = o
    return [ byId.get( i ) for i in range( 1, len( reqs ) + 1 ) ]

def tool( name, args ):
    return { "method": "tools/call", "params": { "name": name, "arguments": args } }

def refusalText( r ):
    """The sentence a model reads: an isError result's content, a found=0 answer's refusal block, or (base) the error."""
    if r is None:
        return None
    if "error" in r:
        return r[ "error" ].get( "message", "" )
    res = r.get( "result", {} )
    texts = [ c.get( "text", "" ) for c in res.get( "content", [] ) ]
    if res.get( "isError" ):
        return "\n".join( texts )
    nf = [ t for t in texts if " not found" in t and "next:" in t ] or [ t for t in texts if " not found: '" in t ]
    return nf[ 0 ] if nf else None

listing = session( [ { "method": "tools/list", "params": {} } ] )[ 0 ]
tools   = { t[ "name" ]: t for t in listing[ "result" ][ "tools" ] }
CALLABLE = set( tools ) | { "pack_task" }

VAL  = r'"(?:[^"\\]|\\.)*"|\[[^\]]*\]|[^ ]+'
NEXT = re.compile( r' — next: ([a-z_]+)((?: [a-z_]+=(?:' + VAL + r'))*)\s*$' )
ARG  = re.compile( r' ([a-z_]+)=(' + VAL + ')' )
def parseNext( text ):
    for line in ( text or "" ).splitlines():
        m = NEXT.search( line )
        if m:
            args = {}
            for k, v in ARG.findall( m.group( 2 ) ):
                try:
                    args[ k ] = json.loads( v )
                except ValueError:
                    return ( m.group( 1 ), None )
            return ( m.group( 1 ), args )
    return ( None, None )

# ── build the refusal set from tools/list itself ──
cases = []   # (arm, label, request)
WRONG = { "string": 5, "integer": "x", "boolean": "yes", "array": 5, "object": 5 }
for name, t in sorted( tools.items() ):
    props = t[ "inputSchema" ].get( "properties", {} )
    cases.append( ( "M", name + " with no arguments", tool( name, {} ) ) )
    for field, spec in sorted( props.items() ):
        if field in ( "path", "paths" ):
            continue   # a bad root is a root refusal (its own arm in mcpcontractcheck), not a field of this tool
        cases.append( ( "V", "%s %s=%r" % ( name, field, WRONG[ spec.get( "type", "string" ) ] ),
                        tool( name, { field: WRONG[ spec.get( "type", "string" ) ] } ) ) )
    near = sorted( k for k in props if k not in ( "path", "paths" ) )
    if near:
        cases.append( ( "U", name + " near-miss field " + near[ 0 ] + "s", tool( name, { near[ 0 ] + "s": "x" } ) ) )
    cases.append( ( "U", name + " far undeclared field", tool( name, { "zzqqxx": "x" } ) ) )
for name in ( "find_symbol", "find_referencing_symbols", "impact", "uses", "edit_check", "slice", "mentions" ):
    cases.append( ( "N", name + " symbol with a near-miss", tool( name, { "symbol": "helpr" } ) ) )
    cases.append( ( "N", name + " symbol with none",        tool( name, { "symbol": "zzqqxx_nowhere" } ) ) )
cases += [
    ( "N", "lego type not indexed",                 tool( "lego", { "type": "ZzqqxxType" } ) ),
    ( "N", "cochange file with a near-miss",        tool( "cochange", { "file": "src/b.c" } ) ),
    ( "N", "cochange file with none",               tool( "cochange", { "file": "zzqqxx.rs" } ) ),
    ( "N", "path_between endpoint not indexed",     tool( "path_between", { "from": "caller", "to": "zzqqxx_nowhere" } ) ),
    ( "N", "replace_symbol_body symbol not found",  tool( "replace_symbol_body", { "symbol": "zzqqxx_nowhere", "new_body": "int zzqqxx_nowhere( void ) { return 0; }" } ) ),
    ( "B", "rank_by=churn (refused on MCP)",        tool( "rank_by", { "rank_by": "churn" } ) ),
    ( "B", "rank_by with an unknown signal",        tool( "rank_by", { "rank_by": "zzqqxx" } ) ),
    ( "B", "from_trace with no frames in it",       tool( "from_trace", { "trace": "nothing to see here" } ) ),
    ( "B", "explore partition with limit",          tool( "explore", { "task": "add a since filter", "partition": 2, "limit": 5 } ) ),
    ( "B", "exemplar with nothing of that kind",    tool( "exemplar", { "kind": "iface" } ) ),
    ( "B", "affected with an item matching nothing", tool( "affected", { "files": "zzqqxx_nowhere" } ) ),
    ( "B", "grep in= an unknown tier",              tool( "grep", { "pattern": "helper", "in": "zzqqxx" } ) ),
    ( "B", "legend= an unknown posture",            tool( "analyze", { "legend": "zzqqxx" } ) ),
]

got = session( [ c[ 2 ] for c in cases ] )
refused, nextCalls = 0, []
missingNext, badNext = [], []
for ( arm, label, req ), r in zip( cases, got ):
    text = refusalText( r )
    if text is None:
        continue     # the tool answered (a request this tool can serve): not a refusal row
    refused += 1
    verb, args = parseNext( text )
    if verb is None:
        missingNext.append( ( arm, label, text[ :160 ] ) )
    elif args is None or verb not in CALLABLE:
        badNext.append( ( arm, label, text[ -160: ] ) )
    else:
        nextCalls.append( ( arm, label, verb, args ) )

for arm in "MVUNB":
    rows  = [ c for c in cases if c[ 0 ] == arm ]
    miss  = [ m for m in missingNext if m[ 0 ] == arm ]
    for m in miss[ :4 ]:
        print( "        no next call: [%s] %s -> %r" % m )
    check( rows and not miss, "(%s) every refusal in this arm names a next call (%d requests, %d without one)" % ( arm, len( rows ), len( miss ) ) )
for b in badNext[ :4 ]:
    print( "        unparseable or unknown tool: [%s] %s -> %r" % b )
check( not badNext, "every next call names a tool this server answers, in parseable argument spelling (%d bad)" % len( badNext ) )
check( refused >= len( cases ) // 2, "the table produced refusals to judge (%d of %d requests refused)" % ( refused, len( cases ) ) )

# ── (R) the round trip: each distinct next call, sent back, is not refused for its own shape ──
FIELD_FAULT = ( "missing required field", "invalid value for field", "unknown field:", "unknown tool:" )
distinct = {}
for arm, label, verb, args in nextCalls:
    distinct.setdefault( ( verb, json.dumps( args, sort_keys = True ) ), ( arm, label, verb, args ) )
trips = session( [ tool( v, a ) for ( _, _, v, a ) in distinct.values() ] )
badTrip = []
for ( arm, label, verb, args ), r in zip( distinct.values(), trips ):
    if r is None or "error" in r:
        badTrip.append( ( label, verb, args, json.dumps( r )[ :160 ] ) )
        continue
    res = r.get( "result", {} )
    t = "".join( c.get( "text", "" ) for c in res.get( "content", [] ) )
    if res.get( "isError" ) and t.startswith( FIELD_FAULT ):
        badTrip.append( ( label, verb, args, t[ :160 ] ) )
for b in badTrip[ :5 ]:
    print( "        next call refused for its own arguments: %s -> %s %s -> %s" % b )
check( distinct and not badTrip, "(R) every distinct next call (%d) round-trips through tools/call well-formed" % len( distinct ) )

# an edit refusal must point at a READ first: a placeholder new_body is not a step to run blind
editNext = [ v for ( arm, label, v, a ) in nextCalls if label.startswith( "replace_symbol_body symbol not found" ) ]
check( editNext and all( v not in ( "replace_symbol_body", "insert_before_symbol", "insert_after_symbol" ) for v in editNext ),
       "(N) a not-found edit names a read verb next, never a placeholder edit (got %s)" % editNext )
check( open( os.path.join( repo, "src", "a.c" ) ).read() == SRC, "(R) no round trip wrote a byte of the fixture" )

print( "" )
print( "ALL PASS" if fails == 0 else "%d CHECK(S) FAILED" % fails )
sys.exit( 1 if fails else 0 )
PY
