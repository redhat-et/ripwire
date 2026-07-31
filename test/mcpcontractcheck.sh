#!/usr/bin/env bash
# mcpcontractcheck.sh — §B6 M1 / M2 / M4 / M11 / M12: the MCP surface's CONTRACT, pinned.
#
# The finding class this gate exists for is CONTRACT DIVERGENCE, not malformed input. Two verifiers have
# already proved this surface clean under ~85 hostile probes; what they could not see is that the same
# server described its arguments FOUR different ways —
#
#   1. the tools/list inputSchema (what a schema-driven client reads)
#   2. declaredFieldsFor / kMcpVerbFields (what the unknown-field guard enforces, and enumerates in its
#      own refusal: "analyze accepts: path, paths")
#   3. what the code actually CONSUMES
#   4. what the CLI does for the same request
#
# and that those four disagreed. `paths` was consumed on all 30 verbs and declared on 18; every `required`
# omitted `path`; 0 of 84 properties carried a description; and six single-root verbs answered a multi-root
# workspace with a refusal naming a FALSE cause.
#
# Every arm below compares two of those four columns. Nothing here restates a string the source owns — the
# expected sets are PARSED OUT OF src/mcprefusal.h, because a gate that restates the fix cannot notice the
# fix being un-done (the §B6 M14 lesson, and the shape arm (K) of mcpframehonestycheck already uses).
#
# Usage:  test/mcpcontractcheck.sh [BIN]
#         CTXPACK_BIN=asan/ctxpack test/mcpcontractcheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "mcpcontractcheck: BIN=$BIN"

python3 - "$BIN" "$ROOT" "$TMP" <<'PY'
import hashlib, json, os, re, shutil, socket, subprocess, sys, time

BIN, ROOT, TMP = sys.argv[1], sys.argv[2], sys.argv[3]
fails = 0
def check( cond, msg ):
    global fails
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: fails += 1

# ─── two REAL git repos: the multi-root arms are meaningless without them, because the whole M1 finding is
#     that the false causes ("not a git repository") were false. ───────────────────────────────────────────
def mkRepo( path, files ):
    os.makedirs( path, exist_ok = True )
    for name, body in files.items():
        open( os.path.join( path, name ), "w" ).write( body )
    for cmd in ( [ "git", "init", "-q" ], [ "git", "add", "-A" ],
                 [ "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init" ] ):
        subprocess.run( cmd, cwd = path, stdout = subprocess.DEVNULL, stderr = subprocess.DEVNULL )

rA = os.path.join( TMP, "rA" ); rB = os.path.join( TMP, "rB" )
mkRepo( rA, { "alpha.cpp": "// alphaOne does a thing.\nint alphaOne( int x ) { return x + 1; }\n"
                           "int alphaTwo( int x ) { return alphaOne( x ) * 2; }\n",
              "notes.md":  "# Notes\n`alphaOne` is the entry point.\n" } )
mkRepo( rB, { "beta.cpp":  "int betaOne( int y ) { return y * 3; }\n" } )

class Stdio:
    def __init__( self, root = None ):
        argv = [ BIN ] + ( [ root ] if root else [] ) + [ "--mcp" ]
        self.p = subprocess.Popen( argv, stdin = subprocess.PIPE, stdout = subprocess.PIPE,
                                   stderr = subprocess.DEVNULL )
        self.n = 0
    def raw( self, line ):
        self.p.stdin.write( line.encode() + b"\n" ); self.p.stdin.flush()
        return self.p.stdout.readline().decode( "utf-8", "replace" ).strip()
    def call( self, method, params = None ):
        self.n += 1
        req = { "jsonrpc": "2.0", "id": self.n, "method": method }
        if params is not None: req[ "params" ] = params
        return json.loads( self.raw( json.dumps( req ) ) )
    def tool( self, name, args ):
        return self.call( "tools/call", { "name": name, "arguments": args } )
    def close( self ):
        try:    self.p.stdin.close(); self.p.wait( 20 )
        except Exception: self.p.kill()

# ═══ the source tables, PARSED — never restated ════════════════════════════════════════════════════════════
REFUSAL_H = open( os.path.join( ROOT, "src", "mcprefusal.h" ), encoding = "utf-8" ).read()

def parseVerbFields():
    blk = REFUSAL_H[ REFUSAL_H.index( "kMcpVerbFields[] = {" ) : ]
    blk = blk[ : blk.index( "\n};" ) ]
    return { v: f.split() for v, f in re.findall( r'\{\s*"([a-z_]+)",\s*"([a-z_ ]+)"\s*\}', blk ) }

def parseUniversal():
    m = re.search( r"kMcpUniversalFields\[\]\s*=\s*\{([^}]*)\}", REFUSAL_H )
    return re.findall( r'"([a-z_]+)"', m.group( 1 ) ) if m else []

def parseSingleRoot():
    blk = REFUSAL_H[ REFUSAL_H.index( "kMcpSingleRootVerbs[] = {" ) : ]
    blk = blk[ : blk.index( "\n};" ) ]
    return re.findall( r'\{\s*"([a-z_]+)",', blk )

verbFields  = parseVerbFields()
universal   = parseUniversal()
singleRoot  = parseSingleRoot()
check( len( verbFields ) == 30, "kMcpVerbFields parsed: %d verbs" % len( verbFields ) )
check( universal == [ "path", "paths" ], "kMcpUniversalFields parsed: %s" % universal )
check( len( singleRoot ) >= 6, "kMcpSingleRootVerbs parsed: %d rows (%s)" % ( len( singleRoot ), ",".join( singleRoot ) ) )

# ═══ (A) DECLARED == ENFORCED — the schema vs the unknown-field guard (M2) ═════════════════════════════════
srv   = Stdio()
tools = srv.call( "tools/list" )[ "result" ][ "tools" ]
check( len( tools ) == 30, "(A) tools/list advertises 30 verbs" )

mismatch, missingPaths, noDesc = [], [], []
for t in tools:
    name  = t[ "name" ]
    props = list( t[ "inputSchema" ][ "properties" ].keys() )
    want  = list( verbFields.get( name, [] ) )
    for u in universal:
        if u not in want: want.append( u )
    if sorted( props ) != sorted( want ): mismatch.append( ( name, sorted( props ), sorted( want ) ) )
    if "paths" not in props:              missingPaths.append( name )
    for k, v in t[ "inputSchema" ][ "properties" ].items():
        if not v.get( "description" ):    noDesc.append( "%s.%s" % ( name, k ) )

for n, got, want in mismatch[ :5 ]:
    print( "  FAIL  (A) %s schema=%s enforced=%s" % ( n, got, want ) )
check( not mismatch,     "(A) all 30 inputSchemas == declaredFieldsFor (schema and unknown-field guard are ONE list)" )
# M2 stated as its own assertion so a regression names the finding, not just the invariant.
check( not missingPaths, "(A/M2) `paths` declared on all 30 verbs (was 18; %d missing)" % len( missingPaths ) )
# M12
check( not noDesc,       "(A/M12) every declared property carries a description (%d missing)" % len( noDesc ) )
totalProps = sum( len( t[ "inputSchema" ][ "properties" ] ) for t in tools )
print( "  INFO  (A) %d declared properties across 30 verbs" % totalProps )

# ═══ (B) M4 — `path` is required exactly when this server cannot supply a root ═════════════════════════════
badReq = [ t[ "name" ] for t in tools if "path" not in t[ "inputSchema" ].get( "required", [] ) ]
check( not badReq, "(B/M4) rootless server: `path` in every verb's required (%d missing)" % len( badReq ) )

exemplar = [ t for t in tools if t[ "name" ] == "exemplar" ][ 0 ][ "inputSchema" ]
anyOf    = exemplar.get( "anyOf", [] )
check( sorted( sorted( a[ "required" ] ) for a in anyOf ) == [ [ "kind" ], [ "task" ] ],
       "(B/M4) exemplar's kind-or-task is expressed as anyOf: %s" % anyOf )
srv.close()

# the ROOTED server is the other half of the same claim: a schema that declared `path` required
# unconditionally would be newly WRONG here, which is why it is rendered from the policy.
rooted = Stdio( rA )
rtools = rooted.call( "tools/list" )[ "result" ][ "tools" ]
stillReq = [ t[ "name" ] for t in rtools if "path" in t[ "inputSchema" ].get( "required", [] ) ]
check( not stillReq, "(B/M4) rooted server (`ctxpack <root> --mcp`): `path` NOT required (%d wrongly required)" % len( stillReq ) )
rooted.close()

# ═══ (C) M1 — the multi-root single-root refusals, MCP vs CLI, verb for verb ═══════════════════════════════
BASE = {
 "analyze":{}, "find_symbol":{"symbol":"alphaTwo"}, "find_referencing_symbols":{"symbol":"alphaOne"},
 "grep":{"pattern":"int"}, "cochange":{"file":"alpha.cpp"}, "memory_recall":{"task":"entry point"},
 "situational_awareness":{}, "mentions":{"symbol":"alphaOne"}, "for":{"task":"add a thing"},
 "lego":{"type":"alphaOne"}, "owners":{}, "exemplar":{"kind":"fn"}, "quality_delta":{}, "quality_baseline":{},
 "impact":{"symbol":"alphaOne"}, "uses":{"symbol":"alphaOne"},
 "path_between":{"from":"alphaTwo","to":"alphaOne"}, "connect":{"symbols":["alphaOne","alphaTwo"]},
 "explore":{"task":"change alphaOne"}, "from_trace":{"trace":'File "alpha.cpp", line 2, in alphaOne'},
 "edit_check":{"symbol":"alphaOne"}, "whereis":{"symbol":"alphaOne"}, "stray_content":{}, "flags":{},
 "doc_drift":{}, "batch":{"queries":[{"verb":"grep","pattern":"int"}]},
}
# The false causes M1 found. None may appear on a multi-root answer ever again — this is the finding
# expressed as a test, not the fix expressed as a test.
FALSE_CAUSES = ( "not a git repository", "no git history for this tree", "symbol not found",
                 "no .ctxpack_quality_baseline and no git HEAD" )

srv = Stdio()
wrongCause, notRefused, refusedButShouldNot = [], [], []
for t in tools:
    name = t[ "name" ]
    if name in ( "replace_symbol_body", "insert_before_symbol", "insert_after_symbol", "fetch_body" ):
        continue                       # edit verbs are genuinely multi-root; fetch_body needs a live handle
    args = dict( BASE.get( name, {} ) ); args[ "paths" ] = [ rA, rB ]
    r    = srv.tool( name, args )
    msg  = r.get( "error", {} ).get( "message", "" )
    if name in singleRoot:
        if "is single-root:" not in msg:            notRefused.append( ( name, msg[ :80 ] ) )
        if any( f in msg for f in FALSE_CAUSES ):   wrongCause.append( ( name, msg[ :80 ] ) )
    else:
        if "is single-root:" in msg:                refusedButShouldNot.append( ( name, msg[ :80 ] ) )
        if any( f in msg for f in FALSE_CAUSES ):   wrongCause.append( ( name, msg[ :80 ] ) )

for n, m in wrongCause[ :6 ]:  print( "  FAIL  (C/M1) %-24s names a FALSE cause on two real git repos: %s" % ( n, m ) )
for n, m in notRefused[ :6 ]:  print( "  FAIL  (C/M1) %-24s is single-root but did not say so: %s" % ( n, m ) )
for n, m in refusedButShouldNot[ :6 ]: print( "  FAIL  (C/M1) %-24s refused single-root but is not in the table: %s" % ( n, m ) )
check( not wrongCause,          "(C/M1) no multi-root answer names a false cause (the finding, as a test)" )
check( not notRefused,          "(C/M1) every kMcpSingleRootVerbs verb refuses with the shared sentence" )
check( not refusedButShouldNot, "(C/M1) no verb outside the table refuses multi-root" )

# CLI PARITY: the four verbs the CLI refuses multi-root must be refused by MCP too. Measured from the CLI,
# not asserted from a list — the CLI is the other column of the table and it is allowed to move.
CLI = { "whereis": [ "--whereis=alphaOne" ], "stray_content": [ "--stray-content" ],
        "quality_delta": [ "--quality-delta" ], "edit_check": [ "--edit-check=alphaOne" ],
        "owners": [ "--owners" ] }
parity = []
for verb, flags in CLI.items():
    rc      = subprocess.run( [ BIN, rA, rB ] + flags, stdout = subprocess.DEVNULL,
                              stderr = subprocess.DEVNULL ).returncode
    cliRef  = rc != 0
    args    = dict( BASE.get( verb, {} ) ); args[ "paths" ] = [ rA, rB ]
    mcpRef  = "is single-root:" in srv.tool( verb, args ).get( "error", {} ).get( "message", "" )
    # owners is the KNOWN inversion (CLI answers, MCP cannot) — asserted as such so it cannot drift silently
    expect  = cliRef if verb != "owners" else True
    if mcpRef != expect: parity.append( ( verb, cliRef, mcpRef ) )
for v, c, m in parity: print( "  FAIL  (C) %-16s CLI refuses=%s  MCP refuses=%s" % ( v, c, m ) )
check( not parity, "(C) MCP matches the CLI verb-for-verb on multi-root refusal (owners pinned as the known inversion)" )
srv.close()

# ═══ (D) M11 — one invalid-id behaviour, a real ping, a shape-checked protocolVersion ══════════════════════
def oneShot( line ):
    p = subprocess.run( [ BIN, "--mcp" ], input = line.encode() + b"\n",
                        stdout = subprocess.PIPE, stderr = subprocess.DEVNULL )
    out = p.stdout.decode( "utf-8", "replace" ).strip().split( "\n" )
    return json.loads( out[ 0 ] ) if out and out[ 0 ] else {}

# every INVALID id shape must produce the SAME outcome — that sameness is the finding
badIds = [ "true", "false", "{}", "[]" ]
got    = [ oneShot( '{"jsonrpc":"2.0","id":%s,"method":"ping"}' % b ).get( "id", "<none>" ) for b in badIds ]
check( got == [ None ] * len( badIds ),
       "(D/M11) all %d invalid-id shapes degrade to null — one class, one behaviour (got %s)" % ( len( badIds ), got ) )
# and the LEGAL ids still echo, so the fix did not become "always null"
legal = { '7': 7, '"a"': "a", 'null': None }
echo  = { k: oneShot( '{"jsonrpc":"2.0","id":%s,"method":"ping"}' % k ).get( "id", "<none>" ) for k in legal }
check( echo == legal, "(D/M11) legal ids (number / string / null) still echo verbatim: %s" % echo )

check( oneShot( '{"jsonrpc":"2.0","id":1,"method":"ping"}' ).get( "result" ) == {},
       "(D/M11) ping answers with an empty result (was -32601 method not found)" )

wrongTyped = oneShot( '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":5}}' )
check( wrongTyped.get( "error", {} ).get( "code" ) == -32602
       and "protocolVersion" in wrongTyped.get( "error", {} ).get( "message", "" ),
       "(D/M11) a wrong-TYPED protocolVersion is refused naming the field (was: silently negotiate latest)" )
unknownVer = oneShot( '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}' )
check( "result" in unknownVer,
       "(D/M11) an unknown but well-formed STRING version still negotiates (spec handshake, not the finding)" )

# ═══ (E) stdio == HTTP, byte for byte, on the arms this gate added ═════════════════════════════════════════
# Wave 1 established that HTTP inherits the shared dispatchMcpLine. That is asserted here, not assumed.
port  = 24000 + ( os.getpid() % 6000 )
token = "mc-%d" % os.getpid()
http  = subprocess.Popen( [ BIN, rA, "--listen=127.0.0.1:%d" % port, "--mcp-token=" + token ],
                          stdout = subprocess.PIPE, stderr = subprocess.STDOUT )
time.sleep( 2.0 )
if http.poll() is not None:
    check( False, "(E) the HTTP listener did not start: %s" % http.stdout.read()[ :180 ].decode( "utf-8", "replace" ) )
else:
    def post( line ):
        body = line.encode()
        req  = ( b"POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n"
                 b"Authorization: Bearer " + token.encode() +
                 b"\r\nAccept: application/json, text/event-stream\r\nContent-Length: "
                 + str( len( body ) ).encode() + b"\r\n\r\n" + body )
        s = socket.create_connection( ( "127.0.0.1", port ), 5 ); s.sendall( req )
        chunks = b""
        while True:
            c = s.recv( 65536 )
            if not c: break
            chunks += c
            head, sep, tail = chunks.partition( b"\r\n\r\n" )
            if sep and tail.strip().endswith( b"}" ): break
        s.close()
        return chunks.partition( b"\r\n\r\n" )[ 2 ].decode( "utf-8", "replace" ).strip()

    stdio  = Stdio( rA )
    differ = []
    for line in ( '{"jsonrpc":"2.0","id":7,"method":"tools/list"}',
                  '{"jsonrpc":"2.0","id":7,"method":"ping"}',
                  '{"jsonrpc":"2.0","id":true,"method":"ping"}',
                  '{"jsonrpc":"2.0","id":7,"method":"initialize","params":{"protocolVersion":5}}',
                  '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"analyze","arguments":{"kind":"x"}}}' ):
        s, h = stdio.raw( line ), post( line )
        if s != h: differ.append( ( line[ :60 ], s[ :70 ], h[ :70 ] ) )
    stdio.close()
    for l, s, h in differ: print( "  FAIL  (E) %s\n           stdio=%s\n           http =%s" % ( l, s, h ) )
    check( not differ, "(E) stdio == HTTP byte-for-byte on all 5 contract frames (asserted, not assumed)" )
    http.terminate()
    try:    http.wait( 10 )
    except Exception: http.kill()

# ═══ (F) the edit verbs' file identity behind a refusal — these verbs delete code when they are wrong ══════
def identity( p ):
    st = os.stat( p )
    return ( st.st_size, st.st_mtime_ns, st.st_ino, hashlib.sha256( open( p, "rb" ).read() ).hexdigest() )

wsA = os.path.join( TMP, "eA" ); wsB = os.path.join( TMP, "eB" )
shutil.copytree( rA, wsA ); shutil.copytree( rB, wsB )
target  = os.path.join( wsA, "alpha.cpp" )
before  = identity( target )
srv     = Stdio()
# an unknown-field refusal and a blank-payload refusal, both on a write verb, over a multi-root workspace
for args in ( { "paths": [ wsA, wsB ], "symbol": "alphaOne", "new_body": "‎" },
              { "paths": [ wsA, wsB ], "symbol": "alphaOne", "new_body": "int alphaOne(){}", "zzz": 1 } ):
    srv.tool( "replace_symbol_body", args )
srv.close()
check( identity( target ) == before,
       "(F) sha256+size+mtime_ns+inode unchanged behind every edit-verb refusal probed" )

print( "" )
if fails == 0: print( "mcpcontractcheck: ALL PASS" )
else:          print( "mcpcontractcheck: %d CHECK(S) FAILED" % fails )
sys.exit( 1 if fails else 0 )
PY
rc=$?
[ "$rc" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
