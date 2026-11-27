#!/usr/bin/env bash
# mcpiserrorcheck.sh — SEP-1303 (MCP spec 2025-11-25): which failures are RESULTS and which are JSON-RPC errors.
#
# The spec splits a tools/call failure in two. A Tool Execution Error (input validation, business logic, a
# not-found) is a RESULT with `isError:true` and the explanation in `content`; clients SHOULD show it to the
# model. A Protocol Error (an unknown tool, a malformed request, a method the server does not have) is a JSON-RPC
# `error`; clients MAY show it. ripwire sent every one of them as `-32602`. Claude Code happens to surface those
# (audit 2026-11-26: 6 of 6 sampled `-32602`s reached the model as `is_error`), so the gain is every other client.
#
# And a not-found that carries the CLI's found=0 document (impact / uses / path_between / find_*) is an ANSWER —
# zero means none found — so it is a plain result: the document first, the refusal sentence beside it.
#
# Arms: (E) tool execution errors are isError results with the sentence in content[0] and no `error` key;
#       (P) protocol errors stay JSON-RPC errors with their code; (A) a found=0 answer is a plain result.
# Red on the pre-SEP-1303 binary: every (E) and (A) arm.
#
# Usage:  test/mcpiserrorcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "mcpiserrorcheck: BIN=$BIN"

python3 - "$BIN" "$TMP" <<'PY'
import json, os, subprocess, sys
BIN, TMP = sys.argv[1], sys.argv[2]
fails = 0
def check( cond, msg ):
    global fails
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: fails += 1

repo = os.path.join( TMP, "repo" )
os.makedirs( repo )
SRC = "int helper( int x ) { return x + 1; }\nint caller( void ) { return helper( 2 ); }\n"
open( os.path.join( repo, "a.c" ), "w" ).write( SRC )
for cmd in ( [ "git", "init", "-q" ], [ "git", "add", "-A" ], [ "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "i" ] ):
    subprocess.run( cmd, cwd = repo, stdout = subprocess.DEVNULL, stderr = subprocess.DEVNULL )

def call( reqs ):
    lines = [ '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}' ]
    for i, r in enumerate( reqs, 1 ):
        lines.append( r if isinstance( r, str ) else json.dumps( dict( { "jsonrpc": "2.0", "id": i }, **r ) ) )
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

EXEC = [   # (label, request, a substring the sentence must carry)
    ( "find_symbol, a required field missing",  tool( "find_symbol", { "path": repo } ),                                 "missing required field: symbol" ),
    ( "grep, a bad value (limit=0)",            tool( "grep", { "path": repo, "pattern": "helper", "limit": 0 } ),       "invalid value for field: limit" ),
    ( "grep, an undeclared field",              tool( "grep", { "path": repo, "pattern": "helper", "nosuch": 1 } ),      "unknown field: 'nosuch'" ),
    ( "grep, a wrong-typed argument",           tool( "grep", { "path": repo, "pattern": 5 } ),                          "pattern" ),
    ( "lego, a type that is not indexed",       tool( "lego", { "path": repo, "type": "NoSuchType" } ),                  "not found" ),
    ( "rank_by, a value refused on MCP",        tool( "rank_by", { "path": repo, "rank_by": "churn" } ),                 "rank_by=churn" ),
    ( "analyze, a path that does not exist",    tool( "analyze", { "path": os.path.join( TMP, "nowhere" ) } ),           "nowhere" ),
    ( "replace_symbol_body, symbol not found",  tool( "replace_symbol_body", { "path": repo, "symbol": "nosuch_fn",
                                                                              "new_body": "int nosuch_fn( void ) { return 0; }" } ), "nosuch_fn" ),
]
PROTO = [  # (label, request, the JSON-RPC code)
    ( "an unknown tool",                        tool( "nosuch_tool", { "path": repo } ),                                -32602 ),
    ( "tools/call naming no tool",              { "method": "tools/call", "params": { "arguments": { "path": repo } } }, -32602 ),
    ( "arguments sent as a string of JSON",     { "method": "tools/call", "params": { "name": "grep", "arguments": json.dumps( { "path": repo } ) } }, -32602 ),
    ( "a method the server does not have",      { "method": "nosuch/method", "params": {} },                            -32601 ),
]
ANSWER = [ # (label, request, the found=0 marker in content[0])
    ( "impact of a symbol that is not indexed", tool( "impact", { "path": repo, "symbol": "nosuch_sym" } ),            'found="0"' ),
    ( "find_symbol of a symbol not indexed",    tool( "find_symbol", { "path": repo, "symbol": "nosuch_sym" } ),       '"found":0' ),
    ( "path_between with an unknown endpoint",  tool( "path_between", { "path": repo, "from": "caller", "to": "nosuch_sym" } ), 'found="0"' ),
]

got = call( [ r for _, r, _ in EXEC ] + [ r for _, r, _ in PROTO ] + [ r for _, r, _ in ANSWER ] )
ex, pr, an = got[ :len( EXEC ) ], got[ len( EXEC ):len( EXEC ) + len( PROTO ) ], got[ len( EXEC ) + len( PROTO ): ]

for ( label, _, want ), r in zip( EXEC, ex ):
    res  = ( r or {} ).get( "result", {} )
    text = "".join( c.get( "text", "" ) for c in res.get( "content", [] ) )
    check( r is not None and "error" not in r and res.get( "isError" ) is True and want in text,
           "(E) %s: an isError result carrying %r in content (got %s)" % ( label, want, json.dumps( r )[ :220 ] ) )

for ( label, _, code ), r in zip( PROTO, pr ):
    check( r is not None and "result" not in r and ( r.get( "error" ) or {} ).get( "code" ) == code,
           "(P) %s: still a JSON-RPC error %d (got %s)" % ( label, code, json.dumps( r )[ :220 ] ) )

for ( label, _, marker ), r in zip( ANSWER, an ):
    res     = ( r or {} ).get( "result", {} )
    content = res.get( "content", [] )
    ok = ( r is not None and "error" not in r and not res.get( "isError" ) and len( content ) >= 2
           and marker in content[ 0 ].get( "text", "" ) and "not found" in content[ 1 ].get( "text", "" ) )
    check( ok, "(A) %s: a plain result, the found=0 document first and the refusal sentence beside it (got %s)"
               % ( label, json.dumps( r )[ :220 ] ) )

# the edit refusal left the file byte-identical (the edit verbs' contract, unchanged by the envelope)
check( open( os.path.join( repo, "a.c" ) ).read() == SRC, "(E) the refused edit left a.c byte-identical" )

print( "" )
print( "ALL PASS" if fails == 0 else "%d CHECK(S) FAILED" % fails )
sys.exit( 1 if fails else 0 )
PY
