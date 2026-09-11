#!/usr/bin/env bash
# mcpstrictschemacheck.sh — issue #48: a tool input schema a STRICT MCP client will actually accept.
#
# THE FINDING, quoted from the reporter (stalep, opencode + @ai-sdk/google-vertex/anthropic, ripwire 0.4.0):
#
#     tools.16.custom.input_schema: input_schema does not support oneOf, allOf, or anyOf at the top level
#
# That sentence is the Anthropic tool-schema validator's, not an opencode quirk, so it is not one client's
# problem: it is every strict client's. ripwire's own README lists opencode as supported and `ripwire wrap
# opencode` prints a recipe for it, so for as long as the server emitted that keyword the front page carried
# a claim the binary could not honour. The offending tool was `exemplar` — the 16th stanza tools/list emits —
# whose kind-or-task requirement had been rendered as a top-level `"anyOf":[{"required":["kind"]},
# {"required":["task"]}]`. Exactly one of the 31 tools carried it; the validator stops at the first.
#
# WHY THE UNION EXISTED, and why it is gone rather than moved. It encoded a REAL fact — exemplar answers to
# `kind` OR to `task`, and refuses when it has neither — expressed in the one JSON Schema keyword that says
# so machine-readably. The keyword is unavailable; the fact is not negotiable. So the fact now lives in the
# two places a strict client can still read it: each member's own property `description` (which arm (A/M12)
# of mcpcontractcheck already obliges every declared property to carry) and the server's runtime refusal,
# which was always the actual enforcement. Flattening to "both optional, say nothing" would have been the
# dishonest flatten — a schema that no longer mentions a requirement the server still enforces — and this
# gate exists to make that flatten impossible to land quietly: arm (D) fails if the words go missing, and
# arm (E) proves arm (D) can fail.
#
# WHAT IT ASSERTS
#   (A) NO TOP-LEVEL UNION on any tool, in all THREE server postures (bare --mcp in a workspace cwd,
#       `ripwire <root> --mcp`, and the truly rootless cwd=/ server whose `required` differs). The reported
#       defect is posture-independent; sweeping the three costs one process each and means a future
#       policy-dependent schema branch cannot reintroduce it on the posture nobody dumps.
#   (B) NO UNION ANYWHERE — nested `oneOf`/`allOf`/`anyOf`/`not`/`if`/`then`/`else` too. The reported error
#       names the top level; a nested one is the same class of finding one client release away.
#   (C) THE NEIGHBOURING STRICT-CLIENT HAZARDS, swept while the schemas are in hand rather than in the next
#       issue: top-level `type` must be exactly "object"; every top-level keyword must be in the allowlist;
#       no `$ref` and no `"null"` type anywhere; every declared property carries a `type`; every name in
#       `required` is a declared property; and `required`, when present, is never the empty array (valid in
#       draft-06+, rejected by draft-04-strict validators, and semantically identical to omitting it).
#   (D) THE CONTRACT SURVIVED THE FLATTENING. The AnyOf groups are PARSED OUT OF src/mcprefusal.h, never
#       restated here, so a new group gets the same obligation for free: every member's description must
#       carry the word REQUIRED and name every sibling; the server must still refuse a call carrying none
#       of them, naming all of them; it must still answer a call carrying any ONE of them; and the
#       precedence the description claims (the first group member wins) must be the precedence the dispatch
#       actually applies — checked by comparing payloads, not by reading the source.
#   (E) MUTATION CONTROLS. Four mutants — a re-injected top-level anyOf, a nested anyOf, a re-injected empty
#       `required`, and a description with the REQUIRED clause stripped — are fed to the SAME predicates the
#       real arms use. Each must be caught. A schema checker that cannot fail is the inert shape this suite
#       keeps finding, and (E) is what makes (A)-(D) evidence instead of decoration.
#
# Usage:  test/mcpstrictschemacheck.sh [BIN]
#         RIPWIRE_BIN=asan/ripwire test/mcpstrictschemacheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative BIN
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "mcpstrictschemacheck: BIN=$BIN"

rc=0
python3 - "$BIN" "$ROOT" "$TMP" <<'PY' || rc=$?
import json, os, re, subprocess, sys

BIN, ROOT, TMP = sys.argv[1], sys.argv[2], sys.argv[3]
fails = 0
def check( cond, msg ):
    global fails
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: fails += 1

# ─── a small real repo: the (D) runtime arms need a tree exemplar can actually answer from ───────────────
REPO = os.path.join( TMP, "repo" )
os.makedirs( REPO, exist_ok = True )
open( os.path.join( REPO, "alpha.cpp" ), "w" ).write(
    "// writeJsonRow serialises one row.\n"
    "int writeJsonRow( int x ) { return x + 1; }\n"
    "int callerOne( int x ) { return writeJsonRow( x ) * 2; }\n"
    "int callerTwo( int x ) { return writeJsonRow( x ) + callerOne( x ); }\n"
    "class RowSink { public: int emit( int x ) { return writeJsonRow( x ); } };\n" )
for cmd in ( [ "git", "init", "-q" ], [ "git", "add", "-A" ],
             [ "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init" ] ):
    subprocess.run( cmd, cwd = REPO, stdout = subprocess.DEVNULL, stderr = subprocess.DEVNULL )

class Stdio:
    def __init__( self, root = None, cwd = None ):
        argv = [ BIN ] + ( [ root ] if root else [] ) + [ "--mcp" ]
        self.p = subprocess.Popen( argv, stdin = subprocess.PIPE, stdout = subprocess.PIPE,
                                   stderr = subprocess.DEVNULL, cwd = cwd )
        self.n = 0
    def call( self, method, params = None ):
        self.n += 1
        req = { "jsonrpc": "2.0", "id": self.n, "method": method }
        if params is not None: req[ "params" ] = params
        self.p.stdin.write( json.dumps( req ).encode() + b"\n" ); self.p.stdin.flush()
        return json.loads( self.p.stdout.readline().decode( "utf-8", "replace" ) )
    def tools( self ):
        return self.call( "tools/list" )[ "result" ][ "tools" ]
    def tool( self, name, args ):
        return self.call( "tools/call", { "name": name, "arguments": args } )
    def close( self ):
        try:    self.p.stdin.close(); self.p.wait( 30 )
        except Exception: self.p.kill()

def payload( r ):
    """the text of a tools/call answer, refusal or not — one accessor both (D) arms read."""
    res = r.get( "result" ) or {}
    out = []
    for c in res.get( "content", [] ):
        if isinstance( c, dict ) and "text" in c: out.append( c[ "text" ] )
    if not out and "error" in r: out.append( json.dumps( r[ "error" ] ) )
    return "\n".join( out )

# ═══ THE PREDICATES — one implementation, run against the real schemas in (A)-(C) and against deliberately
#     broken ones in (E). A checker that is not itself exercised on a mutant is a checker nobody has seen
#     fail, and this suite has shipped two of those. ══════════════════════════════════════════════════════
UNION_KEYWORDS = ( "oneOf", "allOf", "anyOf", "not", "if", "then", "else" )
# The keywords a tool input schema may carry at its top level. Deliberately SHORT: the Anthropic validator's
# refusal is about what it does not support, and the safe set is the object-shape core plus documentation.
TOP_ALLOWED    = { "type", "properties", "required", "additionalProperties", "description", "title" }

def topLevelUnions( schema ):
    return [ k for k in UNION_KEYWORDS if k in schema ]

def unionsAnywhere( node, path = "" ):
    """every union keyword at any depth, as path strings — (B) is (A) without the top-level restriction."""
    found = []
    if isinstance( node, dict ):
        for k, v in node.items():
            if k in UNION_KEYWORDS: found.append( ( path + "/" + k ).lstrip( "/" ) )
            found += unionsAnywhere( v, path + "/" + k )
    elif isinstance( node, list ):
        for i, v in enumerate( node ): found += unionsAnywhere( v, "%s[%d]" % ( path, i ) )
    return found

def strictHazards( name, schema ):
    """(C): the non-union shapes a strict client rejects. Returns a list of human-readable findings."""
    bad = []
    if schema.get( "type" ) != "object":
        bad.append( "%s: top-level type is %r, not \"object\"" % ( name, schema.get( "type" ) ) )
    for k in schema:
        if k not in TOP_ALLOWED and k not in UNION_KEYWORDS:
            bad.append( "%s: unsupported top-level keyword %r" % ( name, k ) )
    if "required" in schema and schema[ "required" ] == []:
        bad.append( "%s: `required` is the EMPTY array (omit the key instead — identical meaning, and "
                    "draft-04-strict validators reject the empty form)" % name )
    blob = json.dumps( schema )
    if "$ref" in blob:  bad.append( "%s: carries a $ref" % name )
    if '"null"' in blob: bad.append( "%s: carries a \"null\" type" % name )
    props = schema.get( "properties", {} )
    for pn, pv in props.items():
        if not isinstance( pv, dict ) or "type" not in pv:
            bad.append( "%s.%s: declared property with no `type`" % ( name, pn ) )
        if not ( isinstance( pv, dict ) and pv.get( "description" ) ):
            bad.append( "%s.%s: declared property with no `description`" % ( name, pn ) )
    for r in schema.get( "required", [] ):
        if r not in props:
            bad.append( "%s: `required` names %r, which is not a declared property" % ( name, r ) )
    return bad

def anyOfClauseMissing( groups, tools ):
    """(D1): every AnyOf member's description must carry REQUIRED and name every sibling."""
    byName = { t[ "name" ]: t for t in tools }
    missing = []
    for verb, members in groups.items():
        t = byName.get( verb )
        if t is None: continue                     # a pruned verb (git-only) is not a finding here
        props = t[ "inputSchema" ].get( "properties", {} )
        for m in members:
            desc = ( props.get( m ) or {} ).get( "description", "" )
            if "REQUIRED" not in desc:
                missing.append( "%s.%s: description never says REQUIRED" % ( verb, m ) )
            for sib in members:
                if sib != m and sib not in desc:
                    missing.append( "%s.%s: description never names its alternative %r" % ( verb, m, sib ) )
    return missing

# ═══ the source table, PARSED — the AnyOf groups are read out of src/mcprefusal.h so a NEW group inherits
#     the obligation without anyone remembering to widen this gate. ═════════════════════════════════════
REFUSAL_H = open( os.path.join( ROOT, "src", "mcprefusal.h" ), encoding = "utf-8" ).read()
blk = REFUSAL_H[ REFUSAL_H.index( "kMcpRequiredFields[] = {" ) : ]
blk = blk[ : blk.index( "\n};" ) ]
GROUPS = {}
for line in blk.splitlines():
    if "FieldRule::AnyOf" not in line: continue
    m = re.match( r'\s*\{\s*"([a-z_]+)"\s*,\s*"([a-z_]+)"\s*,', line )
    if m: GROUPS.setdefault( m.group( 1 ), [] ).append( m.group( 2 ) )
check( bool( GROUPS ), "AnyOf groups parsed out of src/mcprefusal.h: %s" % GROUPS )

# ═══ (A) NO TOP-LEVEL UNION, three server postures ═══════════════════════════════════════════════════════
postures = [ ( "bare --mcp in a workspace cwd", Stdio( cwd = REPO ) ),
             ( "rooted `ripwire <root> --mcp`", Stdio( REPO ) ),
             ( "rootless (cwd=/)",              Stdio( cwd = "/" ) ) ]
served = {}
for label, srv in postures:
    tools = srv.tools()
    served[ label ] = tools
    guilty = [ ( i, t[ "name" ], topLevelUnions( t[ "inputSchema" ] ) )
               for i, t in enumerate( tools ) if topLevelUnions( t[ "inputSchema" ] ) ]
    for i, n, ks in guilty[ :5 ]:
        print( "  FAIL  (A) tools.%d (%s) top-level %s — 'input_schema does not support oneOf, allOf, or "
               "anyOf at the top level'" % ( i, n, ks ) )
    check( not guilty, "(A) %s: %d tools, none with a top-level oneOf/allOf/anyOf" % ( label, len( tools ) ) )

MAIN = served[ "bare --mcp in a workspace cwd" ]

# ═══ (B) NO UNION ANYWHERE ═══════════════════════════════════════════════════════════════════════════════
nested = [ ( t[ "name" ], unionsAnywhere( t[ "inputSchema" ] ) ) for t in MAIN ]
nested = [ ( n, p ) for n, p in nested if p ]
for n, p in nested[ :5 ]: print( "  FAIL  (B) %s: union keyword(s) at %s" % ( n, p ) )
check( not nested, "(B) no union keyword at ANY depth across %d schemas" % len( MAIN ) )

# ═══ (C) the neighbouring strict-client hazards ══════════════════════════════════════════════════════════
for label, tools in served.items():
    haz = []
    for t in tools: haz += strictHazards( t[ "name" ], t[ "inputSchema" ] )
    for h in haz[ :8 ]: print( "  FAIL  (C) [%s] %s" % ( label, h ) )
    check( not haz, "(C) %s: %d schemas clean of $ref / null-type / typeless property / empty `required` / "
                    "unsupported top-level keyword" % ( label, len( tools ) ) )

# ═══ (D) the contract survived the flattening ════════════════════════════════════════════════════════════
miss = anyOfClauseMissing( GROUPS, MAIN )
for m in miss[ :6 ]: print( "  FAIL  (D1) %s" % m )
check( not miss, "(D1) every AnyOf member's description says REQUIRED and names its alternatives (%d group(s))"
                 % len( GROUPS ) )

srv = Stdio( cwd = REPO )
for verb, members in GROUPS.items():
    # (D2) NONE of them -> refuse, naming ALL of them. This is the enforcement the schema keyword used to
    #      duplicate; if it ever goes quiet, the flatten became a lie.
    r = srv.tool( verb, {} )
    text = payload( r )
    named = all( m in text for m in members )
    refused = ( "missing required field" in text ) or bool( r.get( "error" ) )
    check( refused and named,
           "(D2) %s with none of %s refuses and names all of them: %r" % ( verb, members, text[ :140 ] ) )

    # (D3) ANY ONE of them -> a real answer, not a refusal. The union said "at least one"; so must the server.
    answers = {}
    for m in members:
        rr = srv.tool( verb, { m: "fn" if m == "kind" else "a JSON writer" } )
        tt = payload( rr )
        answers[ m ] = tt
        check( "missing required field" not in tt and not rr.get( "error" ) and len( tt ) > 0,
               "(D3) %s with only `%s` answers (%d B)" % ( verb, m, len( tt ) ) )

    # (D4) PRECEDENCE — the description claims the FIRST member wins when several are sent. Checked against
    #      the payloads, not against the source: both-sent must equal first-only, and must differ from the
    #      other member alone (otherwise "wins" would be unfalsifiable on this fixture).
    if len( members ) >= 2:
        both = payload( srv.tool( verb, { members[0]: "fn", members[1]: "a JSON writer" } ) )
        check( both == answers[ members[0] ],
               "(D4) %s with %s AND %s == %s alone (the precedence the description states)"
               % ( verb, members[0], members[1], members[0] ) )
        check( answers[ members[0] ] != answers[ members[1] ],
               "(D4) control: %s-alone and %s-alone differ on this fixture, so (D4) is falsifiable"
               % ( members[0], members[1] ) )
srv.close()
for _l, s in postures: s.close()

# ═══ (E) MUTATION CONTROLS — the predicates, fed schemas that MUST be rejected ════════════════════════════
victim = json.loads( json.dumps( MAIN[0][ "inputSchema" ] ) )

m1 = json.loads( json.dumps( victim ) )
m1[ "anyOf" ] = [ { "required": [ "kind" ] }, { "required": [ "task" ] } ]
check( topLevelUnions( m1 ) == [ "anyOf" ],
       "(E1) mutation control: a re-injected top-level anyOf is caught by (A)'s predicate" )

m2 = json.loads( json.dumps( victim ) )
firstProp = sorted( m2[ "properties" ] )[0]
m2[ "properties" ][ firstProp ] = { "oneOf": [ { "type": "string" }, { "type": "integer" } ],
                                    "description": "x" }
check( unionsAnywhere( m2 ), "(E2) mutation control: a NESTED oneOf is caught by (B)'s predicate" )

m3 = json.loads( json.dumps( victim ) )
m3[ "required" ] = []
check( any( "EMPTY array" in h for h in strictHazards( "mutant", m3 ) ),
       "(E3) mutation control: a re-injected empty `required` is caught by (C)'s predicate" )

mutTools = json.loads( json.dumps( MAIN ) )
stripped = False
for t in mutTools:
    if t[ "name" ] in GROUPS:
        for m in GROUPS[ t[ "name" ] ]:
            p = t[ "inputSchema" ][ "properties" ].get( m )
            if p: p[ "description" ] = "a value"; stripped = True
check( stripped and anyOfClauseMissing( GROUPS, mutTools ),
       "(E4) mutation control: stripping the REQUIRED clause out of an AnyOf member's description is "
       "caught by (D1)'s predicate" )

# a NEGATIVE control for (E): the unmutated schema must pass every predicate it was just shown to reject.
check( not topLevelUnions( victim ) and not unionsAnywhere( victim )
       and not any( "EMPTY array" in h for h in strictHazards( "clean", victim ) ),
       "(E5) negative control: the unmutated schema passes all three predicates (they discriminate)" )

print( "" )
if fails == 0: print( "mcpstrictschemacheck: ALL PASS" )
else:          print( "mcpstrictschemacheck: %d CHECK(S) FAILED" % fails )
sys.exit( 1 if fails else 0 )
PY

[ "$rc" -eq 0 ] && ok "schema strictness, contract survival and 5 mutation controls" \
                || no "mcpstrictschemacheck: see the FAIL lines above (python rc=$rc)"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
