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
# and that those four disagreed. `paths` was consumed on all 31 verbs and declared on 18; every `required`
# omitted `path`; 0 of 84 properties carried a description; and six single-root verbs answered a multi-root
# workspace with a refusal naming a FALSE cause.
#
# Every arm below compares two of those four columns. Nothing here restates a string the source owns — the
# expected sets are PARSED OUT OF src/mcprefusal.h, because a gate that restates the fix cannot notice the
# fix being un-done (the §B6 M14 lesson, and the shape arm (K) of mcpframehonestycheck already uses).
#
# Usage:  test/mcpcontractcheck.sh [BIN]
#         RIPWIRE_BIN=asan/ripwire test/mcpcontractcheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "mcpcontractcheck: BIN=$BIN"

# Arm (E)'s HTTP client is the one the --listen gates share (test/lib/gatehttp.sh): it waits until the listener
# ANSWERS, and a request that gets no answer is a FAIL of its own rather than a body to compare.
. "$ROOT/test/lib/gatehttp.sh"
GATEHTTP="$( gatehttp_install "$TMP" )" || { echo "could not write the shared HTTP client into $TMP"; exit 2; }

python3 - "$BIN" "$ROOT" "$TMP" "$GATEHTTP" <<'PY'
import hashlib, json, os, re, shutil, subprocess, sys

BIN, ROOT, TMP, GATEHTTP = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
sys.path.insert( 0, os.path.dirname( GATEHTTP ) )
import gatehttp                    # waitServing / post / NoAnswer: see test/lib/gatehttp.sh
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
    def __init__( self, root = None, cwd = None ):
        argv = [ BIN ] + ( [ root ] if root else [] ) + [ "--mcp" ]
        self.p = subprocess.Popen( argv, stdin = subprocess.PIPE, stdout = subprocess.PIPE,
                                   stderr = subprocess.DEVNULL, cwd = cwd )
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
    return { v: f.split() for v, f in re.findall(
        r'\{\s*"([a-z_]+)",\s*"([a-z_ ]+)"(?:,\s*McpVerbFields::Effect::[A-Za-z]+)?\s*\}', blk ) }

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
check( len( verbFields ) == 31, "kMcpVerbFields parsed: %d verbs" % len( verbFields ) )
check( universal == [ "path", "paths" ], "kMcpUniversalFields parsed: %s" % universal )
check( len( singleRoot ) >= 6, "kMcpSingleRootVerbs parsed: %d rows (%s)" % ( len( singleRoot ), ",".join( singleRoot ) ) )

# ═══ (A) DECLARED == ENFORCED — the schema vs the unknown-field guard (M2) ═════════════════════════════════
srv   = Stdio()
tools = srv.call( "tools/list" )[ "result" ][ "tools" ]
check( len( tools ) == 31, "(A) tools/list advertises 31 verbs" )

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
check( not mismatch,     "(A) all 31 inputSchemas == declaredFieldsFor (schema and unknown-field guard are ONE list)" )
# M2 stated as its own assertion so a regression names the finding, not just the invariant.
check( not missingPaths, "(A/M2) `paths` declared on all 31 verbs (was 18; %d missing)" % len( missingPaths ) )
# M12
check( not noDesc,       "(A/M12) every declared property carries a description (%d missing)" % len( noDesc ) )
totalProps = sum( len( t[ "inputSchema" ][ "properties" ] ) for t in tools )
print( "  INFO  (A) %d declared properties across 31 verbs" % totalProps )

# ═══ (B) M4 — `path` is required exactly when this server cannot supply a root ═════════════════════════════
# R2a (the 2026-08-12 usage mine) changed WHICH servers can: a bare `--mcp` launched inside a workspace
# now supplies its own launch cwd (assumedRoot), so the shipped install's schema stops demanding `path`.
# The M4 principle is unchanged; the truly root-less server is one launched from "/" (the startup guard
# refuses to assume "/" or $HOME), and THAT schema must still require `path` on all 31 verbs.
stillReq0 = [ t[ "name" ] for t in tools if "path" in t[ "inputSchema" ].get( "required", [] ) ]
check( not stillReq0, "(B/M4+R2a) bare `--mcp` launched in a workspace cwd: `path` NOT required (%d wrongly required)" % len( stillReq0 ) )
rootless = Stdio( cwd = "/" )
rltools  = rootless.call( "tools/list" )[ "result" ][ "tools" ]
badReq   = [ t[ "name" ] for t in rltools if "path" not in t[ "inputSchema" ].get( "required", [] ) ]
check( not badReq, "(B/M4) truly rootless server (cwd=/): `path` in every verb's required (%d missing)" % len( badReq ) )
rootless.close()

# M4's second half, AS AMENDED BY ISSUE #48. It used to render as a top-level JSON Schema `anyOf`. The
# Anthropic tool-schema validator refuses oneOf/allOf/anyOf at the top level of a tool input schema, so
# that one stanza made the whole server un-registerable in opencode and every other strict client. The
# CONTRACT did not change and this arm still checks the same thing M4 cared about — the kind-or-task
# requirement is STATED in the schema a client reads — but the statement now lives in the two members'
# own descriptions. Group parsed out of the source, like every other expectation in this file.
anyOfRows = {}
for line in REFUSAL_H[ REFUSAL_H.index( "kMcpRequiredFields[] = {" ) : ].splitlines():
    if line.startswith( "};" ): break
    if "FieldRule::AnyOf" not in line: continue
    m = re.match( r'\s*\{\s*"([a-z_]+)"\s*,\s*"([a-z_]+)"\s*,', line )
    if m: anyOfRows.setdefault( m.group( 1 ), [] ).append( m.group( 2 ) )
check( anyOfRows, "(B/M4+#48) AnyOf rows parsed out of kMcpRequiredFields: %s" % anyOfRows )
stated, keyword = [], []
for verb, members in anyOfRows.items():
    schema = [ t for t in tools if t[ "name" ] == verb ][ 0 ][ "inputSchema" ]
    keyword += [ "%s.%s" % ( verb, k ) for k in ( "oneOf", "allOf", "anyOf" ) if k in schema ]
    for f in members:
        d = schema[ "properties" ][ f ][ "description" ]
        if "REQUIRED" not in d or any( s not in d for s in members if s != f ):
            stated.append( "%s.%s: %r" % ( verb, f, d[ :80 ] ) )
check( not keyword, "(B/M4+#48) no AnyOf verb carries a top-level union keyword (%s)" % keyword )
check( not stated,  "(B/M4+#48) each AnyOf member's description states the requirement and names its "
                    "alternatives (%s)" % stated )
srv.close()

# the ROOTED server is the other half of the same claim: a schema that declared `path` required
# unconditionally would be newly WRONG here, which is why it is rendered from the policy.
rooted = Stdio( rA )
rtools = rooted.call( "tools/list" )[ "result" ][ "tools" ]
stillReq = [ t[ "name" ] for t in rtools if "path" in t[ "inputSchema" ].get( "required", [] ) ]
check( not stillReq, "(B/M4) rooted server (`ripwire <root> --mcp`): `path` NOT required (%d wrongly required)" % len( stillReq ) )
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
                 "no .ripwire_quality_baseline and no git HEAD" )

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
#
# READY MEANS ANSWERED, and a request with no answer is not a body. This arm used to sleep a fixed 2 s and then post
# through its own client, whose 5 s recv timeout nothing caught: a listener still warming its index handed the rest
# of the warm-up to the first frame, and when that ran out Python died with "TimeoutError: timed out", taking every
# arm after this one with it and failing the gate for a transport that was fine. gatehttp.waitServing polls until the
# listener ANSWERS (30 s ceiling); gatehttp.post raises NoAnswer, which is reported per frame and never compared.
FRAMES = ( '{"jsonrpc":"2.0","id":7,"method":"tools/list"}',
           '{"jsonrpc":"2.0","id":7,"method":"ping"}',
           '{"jsonrpc":"2.0","id":true,"method":"ping"}',
           '{"jsonrpc":"2.0","id":7,"method":"initialize","params":{"protocolVersion":5}}',
           '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"analyze","arguments":{"kind":"x"}}}' )
port  = 24000 + ( os.getpid() % 6000 )
token = "mc-%d" % os.getpid()
http  = subprocess.Popen( [ BIN, rA, "--listen=127.0.0.1:%d" % port, "--mcp-token=" + token ],
                          stdout = subprocess.PIPE, stderr = subprocess.STDOUT )
try:
    whyNotServing = gatehttp.waitServing( port, lambda: http.poll() is None )
    if http.poll() is not None:
        check( False, "(E) the HTTP listener did not start: %s" % http.stdout.read()[ :180 ].decode( "utf-8", "replace" ) )
    elif whyNotServing:
        check( False, "(E) " + whyNotServing )
    else:
        auth   = b"Authorization: Bearer " + token.encode() + b"\r\n"
        stdio  = Stdio( rA )
        differ, noAnswer = [], []
        try:
            for line in FRAMES:
                s = stdio.raw( line )
                try:
                    h = gatehttp.post( port, line.encode(), auth ).strip()
                except gatehttp.NoAnswer as e:     # no body is not a DIFFERENT body: name it, never compare it
                    noAnswer.append( ( line[ :60 ], str( e ) ) )
                    continue
                if s != h: differ.append( ( line[ :60 ], s[ :70 ], h[ :70 ] ) )
        finally:
            stdio.close()
        for l, why in noAnswer: print( "  FAIL  (E) %s\n           no HTTP answer: %s — not a transport difference" % ( l, why ) )
        for l, s, h in differ:  print( "  FAIL  (E) %s\n           stdio=%s\n           http =%s" % ( l, s, h ) )
        check( not noAnswer, "(E) all %d contract frames got an HTTP answer (%d did not)" % ( len( FRAMES ), len( noAnswer ) ) )
        check( not differ,   "(E) stdio == HTTP byte-for-byte on all %d answered contract frames (asserted, not assumed)"
                             % ( len( FRAMES ) - len( noAnswer ) ) )
finally:                                   # every path, an escaping exception included, stops the listener
    http.terminate()
    try:    http.wait( 10 )
    except Exception: http.kill()

# ═══ (G) M13 — a CLI verb that PAGES has a twin that pages; a CLI verb with a BUDGET has a twin with one ═══
# capture-audit 2026-09-04. Only grep/impact/uses/whereis took limit/offset over MCP, while their CLI twins
# and six more (cochange, owners, doc_drift, stray_content, mentions, --callers/--callees) were all in
# cli.h's honorsPaging set. The refusal was loud — "unknown field: 'limit'" — but loud is not answerable: an
# MCP-only agent had no page 2 for any of them, and `for` had no ceiling at all though `--for
# --token-budget` has existed for its whole life.
#
# The expected set is DERIVED, never restated: kPagingHonoringVerbs is the string cli.h prints in its own
# refusal, mapped to MCP names through the one twin table below (the only hand-written part, because the
# rename CLI->MCP is genuinely a naming decision and nothing in the source states it). A CLI verb with no
# MCP twin is skipped BY NAME, so "it has no twin" can never quietly become "we forgot".
CLI_H = open( os.path.join( ROOT, "src", "cli.h" ), encoding = "utf-8" ).read()
m = re.search( r'kPagingHonoringVerbs\s*=\s*((?:\s*"[^"]*")+)\s*;', CLI_H )
pagingCli = set( re.findall( r"--[a-z-]+", m.group( 1 ) ) ) if m else set()
check( len( pagingCli ) >= 30, "(G) parsed %d paging verbs out of cli.h's kPagingHonoringVerbs" % len( pagingCli ) )

# CLI flag -> the MCP verb that answers the same question. "" = deliberately no twin (the reason is the
# comment beside it), and those rows are reported, not silently dropped.
TWIN = {
    "--callers": "find_referencing_symbols", "--callees": "find_symbol",
    "--cochange": "cochange", "--owners": "owners", "--doc-drift": "doc_drift",
    "--whereis": "whereis", "--stray-content": "stray_content", "--mentions": "mentions",
    # kPagingHonoringVerbs spells the grep family "--grep/--regex"; the regex splits it into two tokens.
    "--impact": "impact", "--uses": "uses", "--grep": "grep", "--regex": "grep",
    # No MCP twin at all — each is a CLI-only report verb (no tools/list stanza answers it).
    "--lint": "", "--hotspots": "", "--tree": "", "--deps": "", "--clones": "", "--communities": "",
    "--community": "", "--match": "", "--pattern": "", "--exercises": "", "--seams": "", "--zoom": "",
    "--external-surface": "", "--dead-code": "", "--graph-query": "", "--test-gate": "",
    "--readability": "", "--ensemble": "", "--quality-panel": "", "--context-ratio": "",
    "--nonlocal-state": "", "--comment-coherence": "", "--naming-consistency": "", "--safe-delete": "",
    # P4 (L7): --pr-context joined the paging set for its changed-file window (--offset=N); CLI-only report verb.
    "--pr-context": "",
    # 2026-09-10: --edit-check joined the paging set (it windows its unflagged caller rows) and its twin
    # honors limit/offset through the same mcpPageArgs, so it is a MAPPED verb, not a CLI-only one.
    "--edit-check": "edit_check",
    # 2026-09-10 (C1 F-07/F-10): --flags (with its --flip mode) and --situ joined the paging set when their
    # row listings became windowable. Both have twins, and both twins honour limit/offset through the same
    # mcpPageArgs — so they are MAPPED, not CLI-only. Note the situational twin's DEFAULT is unbounded while
    # the CLI report's is 8: the payload is machine-read and has always served every row, so limit there is
    # relief for a caller who wants less, never a new cut.
    "--flags": "flags", "--situ": "situational_awareness",
}
unmapped = sorted( v for v in pagingCli if v not in TWIN )
check( not unmapped, "(G) every paging CLI verb is classified twin-or-not (%s)" % ( ",".join( unmapped ) or "none unmapped" ) )

missingPage = []
for cliVerb in sorted( pagingCli ):
    twin = TWIN.get( cliVerb, "" )
    if not twin or twin not in verbFields:
        continue
    have = set( verbFields[ twin ] )
    if not { "limit", "offset" } <= have:
        missingPage.append( "%s->%s declares %s" % ( cliVerb, twin, sorted( have ) ) )
for row in missingPage[ :8 ]:
    print( "  FAIL  (G) " + row )
check( not missingPage, "(G/M13) every MCP twin of a paging CLI verb declares limit+offset" )

# The budget half of the same rule: cli.h's kShapingVerbs says which verbs honor --token-budget; every one
# of them that HAS an MCP twin must declare budget_tokens.
mb = re.search( r"inline constexpr ShapingVerb kShapingVerbs\[\]\s*=\s*\{(.*?)\n\};", CLI_H, re.S )
budgetCli = []
for line in ( mb.group( 1 ).splitlines() if mb else [] ):
    row = line.split( "//" )[ 0 ].strip()
    if not row.startswith( "{" ): continue
    f = [ x.strip() for x in row.strip( "{}," ).split( "," ) ]
    if len( f ) > 5 and f[ 5 ] == "true": budgetCli.append( f[ 0 ].strip( '"' ) )
BUDGET_TWIN = { "--for": "for", "--pack-task": "explore", "--from-trace": "from_trace",
                "--handoff": "", "--run-trace": "" }   # the last two are CLI-only verbs
check( len( budgetCli ) >= 4, "(G) parsed %d --token-budget honoring rows out of kShapingVerbs" % len( budgetCli ) )
missingBudget = [ "%s->%s declares %s" % ( c, BUDGET_TWIN[ c ], sorted( verbFields[ BUDGET_TWIN[ c ] ] ) )
                  for c in budgetCli
                  if BUDGET_TWIN.get( c ) and "budget_tokens" not in verbFields.get( BUDGET_TWIN[ c ], [] ) ]
for row in missingBudget:
    print( "  FAIL  (G) " + row )
check( not missingBudget, "(G/M13) every MCP twin of a --token-budget verb declares budget_tokens" )

# DECLARED is not HONORED: prove the window actually moves rows on the verbs this round added, and that a
# second page starts where the first said it would. One live probe per newly-paged verb, on this repo.
srvG = Stdio()
for verb, args, arrayKey in ( ( "find_referencing_symbols", { "path": ROOT, "symbol": "escapeXml" }, "calledBy" ),
                              ( "cochange",                 { "path": ROOT, "file": "src/main.cpp" },  "rows" ),
                              ( "mentions",                 { "path": ROOT, "symbol": "escapeXml" },  "files" ) ):
    a1 = dict( args ); a1.update( { "limit": 2, "offset": 0 } )
    a2 = dict( args ); a2.update( { "limit": 2, "offset": 2 } )
    try:
        p1 = json.loads( srvG.tool( verb, a1 )[ "result" ][ "content" ][ 0 ][ "text" ] )
        p2 = json.loads( srvG.tool( verb, a2 )[ "result" ][ "content" ][ 0 ][ "text" ] )
    except Exception as e:
        check( False, "(G) %s limit/offset probe failed: %s" % ( verb, e ) )
        continue
    rows1, rows2 = p1.get( arrayKey, [] ), p2.get( arrayKey, [] )
    check( len( rows1 ) <= 2 and rows1 != rows2 and p1.get( "next_offset" ) == 2,
           "(G) %s: limit=2 serves %d rows, offset=2 serves different rows, next_offset=%s"
           % ( verb, len( rows1 ), p1.get( "next_offset" ) ) )

# (G/#127-3985249704) A CUT ARRAY MUST SAY SO. situational_awareness windows TWO independent arrays —
# blast_radius and forgotten — with the same limit/offset, and emitted neither a row count nor a total for
# either: a caller could not tell that rows were dropped, and could not build a next request. The CLI twin
# has disclosed its blast-radius cut in prose all along (situ.h's situShowingNote, "showing N of M files —
# shown=N total=M capped=1"), so this was the two dialects disagreeing about the same run.
#
# The shape is --test-gate's (pageview.h rule 6 + rule 1's noun-prefixed exception): a shown_/_capped pair
# per LISTING, plus the paging half for the PRIMARY one. Both halves are asserted DERIVED — shown must
# equal the rows actually served, capped must equal shown < total — so a hand-written constant cannot
# satisfy this arm.
try:
    # Named files, not the working tree's git diff: on a CLEAN checkout (CI, or an integrator's tree) the
    # bare form has zero changed files, zero blast radius, total=0 — and every assertion below reads that
    # zero as a red about paging. The fixture must not be the live repo's dirty state (the same trap
    # gate-fixture-is-the-live-repo names); src/graph.h + src/verbs_for.h reach well over two files.
    SITU_FILES = "src/graph.h,src/verbs_for.h"
    bare = json.loads( srvG.tool( "situational_awareness", { "path": ROOT, "files": SITU_FILES } )[ "result" ][ "content" ][ 0 ][ "text" ] )
    cut  = json.loads( srvG.tool( "situational_awareness",
                                  { "path": ROOT, "files": SITU_FILES, "limit": 2, "offset": 0 } )[ "result" ][ "content" ][ 0 ][ "text" ] )
except Exception as e:
    check( False, "(G) situational_awareness paging probe failed: %s" % e )
    bare = cut = None
if bare is not None:
    check( len( bare.get( "blast_radius", [] ) ) > 2,
           "(G) presence guard: the named files reach %d blast-radius rows (> the 2-row window; a zero here would make every arm below vacuous)"
           % len( bare.get( "blast_radius", [] ) ) )
    for doc, label in ( ( bare, "bare" ), ( cut, "limit=2" ) ):
        for arr, shownKey, cappedKey in ( ( "blast_radius", "shown_blast_radius", "blast_radius_capped" ),
                                          ( "forgotten",    "shown_forgotten",    "forgotten_capped"    ) ):
            check( doc.get( shownKey ) == len( doc.get( arr, [] ) ),
                   "(G) situational_awareness %s: %s=%s matches the %d %s rows served"
                   % ( label, shownKey, doc.get( shownKey ), len( doc.get( arr, [] ) ), arr ) )
            check( isinstance( doc.get( cappedKey ), bool ),
                   "(G) situational_awareness %s: %s is present and boolean (rule 1 pairs it with shown)"
                   % ( label, cappedKey ) )
    # the second listing's own row population, so `forgotten_capped` is checkable by the caller
    check( bare.get( "forgotten_total" ) == len( bare.get( "forgotten", [] ) ),
           "(G) situational_awareness bare: forgotten_total=%s is the whole forgotten population"
           % bare.get( "forgotten_total" ) )
    # …and the CUT run carries the continuation for the primary listing, with total unchanged by the window
    check( cut.get( "has_more" ) is True and cut.get( "next_offset" ) == 2
           and cut.get( "limit" ) == 2 and cut.get( "offset" ) == 0
           and cut.get( "total" ) == len( bare.get( "blast_radius", [] ) ),
           "(G) situational_awareness limit=2: total=%s has_more=%s next_offset=%s offset=%s limit=%s"
           % ( cut.get( "total" ), cut.get( "has_more" ), cut.get( "next_offset" ),
               cut.get( "offset" ), cut.get( "limit" ) ) )
    check( cut.get( "blast_radius_capped" ) is ( len( cut.get( "blast_radius", [] ) ) < cut.get( "total", 0 ) )
           and cut.get( "forgotten_capped" ) is ( len( cut.get( "forgotten", [] ) ) < cut.get( "forgotten_total", 0 ) ),
           "(G) situational_awareness limit=2: both _capped bits are DERIVED from shown < total, not asserted" )
srvG.close()

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
