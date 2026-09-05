#!/usr/bin/env bash
# mcpattrparitycheck.sh — capture-audit 2026-09-04 H14: the DIALECT PARITY property, asserted mechanically.
#
# THE FINDING, as a family rather than as eight bugs. For every verb with a sibling dialect, the CLI's XML
# root carried disclosures the JSON/MCP twin dropped — and each drop was invisible on the surface that had
# it, because a payload with fewer keys looks like a complete answer:
#   * MCP quality_delta   dropped rename_window_commits / renames_window_truncated — so `renames:39` read as
#                         a total when the CLI says the 400-commit mining window was hit and it is a floor.
#   * MCP cochange        dropped window / sub_windows / shown / capped and returned 70 rows uncapped where
#                         the CLI shows 30 with capped="1".
#   * MCP for             dropped confidence / margin_pct on the root (the routing trust gauge) and
#                         churn / amp / tested per row (the "what is fragile before you touch it" lens), and
#                         so served 26 rows against the CLI's 23 under the same byte cap — invisibly.
#   * MCP find_*          dropped count / defs / hop_tested / hop_untested / tested.
#   * MCP analyze         drops k= on every row — and that one is CORRECT (--stable omits it so an unedited
#                         prefix stays byte-identical for KV-cache hits), which is exactly why a gate that
#                         only forbids drops would be wrong. A deliberate omission is DECLARED on the root.
#   * MCP flags/whereis   apply a `kind` filter and echo no filter=, so gates="41" reads as the repo total.
#   * --for --json        drops the compose/field rows and the doc-mention rows while keeping
#                         compose_total:10, under a --help sentence promising the "SAME content".
#   * --impact --format=columnar dropped shown_importers / importers_capped.
#
# WHY MECHANICAL. Every one of these passed its own per-verb gate: each surface was self-consistent. Only a
# COMPARISON sees them, so this gate extracts attribute NAMES (never values — a git stamp or a root path
# legitimately differs) and diffs the sets. It is deliberately name-only and deliberately dumb: the next
# drop is caught by set arithmetic instead of by someone reading two payloads side by side.
#
# THE CONTRACT
#   1. CLI XML root attribute-name set  ⊆  the twin's top-level key set, modulo the declared RENAMES below.
#   2. CLI XML per-row attribute names  ⊆  the twin's per-row key set, same modulo.
#   3. A deliberate omission is DECLARED: the twin's root carries lens="a,b,c" naming exactly the attributes
#      it drops on purpose, and the gate subtracts that set. An undeclared drop fails; a declaration naming
#      an attribute that is NOT dropped also fails (a stale exemption is a lie in the other direction).
#
# Usage:
#   bash test/mcpattrparitycheck.sh                                 # uses build/ripwire
#   RIPWIRE_BIN=build_base/ripwire bash test/mcpattrparitycheck.sh   # the RED run (pre-fix binary)
# Exits non-zero on any divergence.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "mcpattrparitycheck: BIN=$BIN  CORPUS=$ROOT"

python3 - "$BIN" "$ROOT" <<'PY'
import json, re, subprocess, sys

BIN, ROOT = sys.argv[1], sys.argv[2]
fails = 0
def check( cond, msg ):
    global fails
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: fails += 1

# ── the three surfaces ────────────────────────────────────────────────────────────────────────────────
def cli( args ):
    return subprocess.run( [ BIN, ROOT ] + args, capture_output = True, text = True ).stdout

def mcp( name, arguments ):
    req = "\n".join( [ json.dumps( { "jsonrpc": "2.0", "id": 1, "method": "initialize" } ),
                       json.dumps( { "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                                     "params": { "name": name, "arguments": arguments } } ) ] ) + "\n"
    out = subprocess.run( [ BIN, "--mcp" ], input = req, capture_output = True, text = True ).stdout
    last = [ l for l in out.splitlines() if l.strip() ][ -1 ]
    r = json.loads( last )
    if "error" in r:
        return "__ERROR__:" + r[ "error" ].get( "message", "" )
    return r[ "result" ][ "content" ][ 0 ][ "text" ]

# ── name extraction: XML attribute names, and a recursive JSON key walk ───────────────────────────────
# Legends are stripped first: an XML comment is prose, and prose full of `name=` text would poison the set.
def stripComments( t ):
    return re.sub( r"<!--.*?-->", "", t, flags = re.S )

def xmlRootAttrs( t, elem ):
    m = re.search( r"<%s\b([^>]*)>" % re.escape( elem ), stripComments( t ) )
    return set( re.findall( r'([\w:-]+)="', m.group( 1 ) ) ) if m else None

def xmlRowAttrs( t, elem ):
    names = set()
    for a in re.findall( r"<%s\b([^>]*?)/?>" % re.escape( elem ), stripComments( t ) ):
        names |= set( re.findall( r'([\w:-]+)="', a ) )
    return names

def jsonKeys( obj, out = None ):
    out = set() if out is None else out
    if isinstance( obj, dict ):
        for k, v in obj.items():
            out.add( k )
            jsonKeys( v, out )
    elif isinstance( obj, list ):
        for v in obj:
            jsonKeys( v, out )
    return out

def jsonTopKeys( text ):
    return set( json.loads( text ).keys() )

def jsonRowKeys( text, key ):
    rows = json.loads( text ).get( key, [] )
    out = set()
    for r in rows:
        if isinstance( r, dict ): out |= set( r.keys() )
    return out

# lens="a,b,c" on the twin's root = the attributes it drops ON PURPOSE. Read from either dialect.
def declaredLens( text ):
    if text.lstrip().startswith( "{" ):
        try:    return set( filter( None, str( json.loads( text ).get( "lens", "" ) ).split( "," ) ) )
        except Exception: return set()
    m = re.search( r'\blens="([^"]*)"', stripComments( text ) )
    return set( filter( None, m.group( 1 ).split( "," ) ) ) if m else set()

# Documented renames: the CLI attribute name -> the twin's key name for the same fact. Each is a decision
# with a reason, not a tolerance: a rename with no entry here is a DROP as far as this gate is concerned.
RENAME = {
    "of":   { "file", "symbol", "sym" },   # the seed: `of=` on the CLI root, `file`/`symbol` in JSON
    "n":    { "name" },                    # row: n= is the symbol name
    "t":    { "kind" },                    # row: t= is the symbol kind
    # role="macro" is emitted ONLY when the kind is already macro (verbs_navigate.h::macroRoleAttr), so the
    # CLI carries the fact twice and the JSON row carries it once as kind:"macro". A rename, not a drop —
    # and the lens report grades it LOW for exactly that reason.
    "role": { "kind" },
    "p":    { "file", "line" },            # row: p="file:line" splits into two JSON keys
    "l":    { "line" },
    "hits": { "total" },                   # grep: the CLI's hits= is the JSON total
}

def report( label, cliNames, twinNames, lens ):
    missing = set()
    for a in sorted( cliNames ):
        if a in twinNames or ( RENAME.get( a, set() ) & twinNames ) or a in lens:
            continue
        missing.add( a )
    stale = { a for a in lens if a in twinNames }
    check( not missing, "%s: every CLI attribute survives (%s)"
                        % ( label, "missing: " + ",".join( sorted( missing ) ) if missing else "none dropped" ) )
    if lens:
        check( not stale, "%s: lens=\"%s\" names only attributes actually omitted (%s)"
                          % ( label, ",".join( sorted( lens ) ),
                              "stale: " + ",".join( sorted( stale ) ) if stale else "all real" ) )

# ═══ ROOT parity, verb by verb ═════════════════════════════════════════════════════════════════════════
print( "" )
print( "=== ROOT: the CLI XML root's attribute names vs the twin's top-level keys ===" )

# quality_delta — CLI --json vs MCP (both JSON; the CLI XML root is the reference set)
qdXml  = cli( [ "--quality-delta" ] )
qdMcp  = mcp( "quality_delta", { "path": ROOT } )
if qdMcp.startswith( "__ERROR__" ):
    check( False, "quality_delta probe: " + qdMcp[ :120 ] )
else:
    report( "quality_delta root", xmlRootAttrs( qdXml, "quality-delta" ) or set(),
            jsonTopKeys( qdMcp ), declaredLens( qdMcp ) )

# cochange — CLI XML root vs MCP JSON
ccXml = cli( [ "--cochange=src/main.cpp" ] )
ccMcp = mcp( "cochange", { "path": ROOT, "file": "src/main.cpp" } )
if ccMcp.startswith( "__ERROR__" ):
    check( False, "cochange probe: " + ccMcp[ :120 ] )
else:
    report( "cochange root", xmlRootAttrs( ccXml, "cochange" ) or set(),
            jsonTopKeys( ccMcp ), declaredLens( ccMcp ) )

# callers -> find_referencing_symbols  /  callees -> find_symbol
for cliArgs, elem, verb, rowKey, rowElem in (
        ( [ "--callers=escapeXml" ], "callers", "find_referencing_symbols", "calledBy", "s" ),
        ( [ "--callees=serialize" ], "callees", "find_symbol",              "calls",    "s" ) ):
    cx = cli( cliArgs )
    mx = mcp( verb, { "path": ROOT, "symbol": cliArgs[ 0 ].split( "=", 1 )[ 1 ] } )
    if mx.startswith( "__ERROR__" ):
        check( False, "%s probe: %s" % ( verb, mx[ :120 ] ) )
        continue
    report( "%s root" % verb, xmlRootAttrs( cx, elem ) or set(), jsonTopKeys( mx ), declaredLens( mx ) )
    report( "%s rows" % verb, xmlRowAttrs( cx, rowElem ), jsonRowKeys( mx, rowKey ), declaredLens( mx ) )

# for — CLI XML <ctx> vs MCP XML <ctx>, root AND the <d> signature rows
forXml = cli( [ "--for=pagerank power iteration", "--signatures-only" ] )
forMcp = mcp( "for", { "path": ROOT, "task": "pagerank power iteration" } )
if forMcp.startswith( "__ERROR__" ):
    check( False, "for probe: " + forMcp[ :120 ] )
else:
    report( "for root", xmlRootAttrs( forXml, "ctx" ) or set(), xmlRootAttrs( forMcp, "ctx" ) or set(),
            declaredLens( forMcp ) )
    report( "for rows", xmlRowAttrs( forXml, "d" ), xmlRowAttrs( forMcp, "d" ), declaredLens( forMcp ) )

# analyze — the default CLI map's <s> rows vs MCP analyze's. This is the pair whose drop is DELIBERATE:
# --stable omits the globally volatile k= so an unedited prefix stays byte-identical, and MCP serves the
# stable order. The gate demands the declaration, not the attribute.
mapXml = cli( [] )
anMcp  = mcp( "analyze", { "path": ROOT } )
if anMcp.startswith( "__ERROR__" ):
    check( False, "analyze probe: " + anMcp[ :120 ] )
else:
    report( "analyze rows", xmlRowAttrs( mapXml, "s" ), xmlRowAttrs( anMcp, "s" ), declaredLens( anMcp ) )

# ═══ CLI-vs-CLI dialects: the same property between a verb's own two spellings ══════════════════════════
print( "" )
print( "=== DIALECT: a verb's XML root vs its own --json / --format=columnar ===" )

impXml = cli( [ "--impact=escapeXml" ] )
impCol = cli( [ "--impact=escapeXml", "--format=columnar" ] )
report( "impact columnar root", xmlRootAttrs( impXml, "impact" ) or set(),
        ( xmlRootAttrs( impCol, "impact" ) or set() ), declaredLens( impCol ) )

# --for --json: the XML carries <compose>/<field> and <d …>/<doc> sections; --help promises "SAME content",
# so every CHILD ELEMENT of the XML form maps to a JSON key (or is declared on the root).
forJson = cli( [ "--for=pagerank power iteration", "--json" ] )
try:
    fj      = json.loads( forJson )
    fjKeys  = jsonKeys( fj )
    fjLens  = declaredLens( forJson )
    xmlKids = set( re.findall( r"<([a-z][a-z_-]*)[ >]", stripComments( forXml ) ) )
    # ctx/sigs/tail are the envelope itself; d/f/t are row elements inside them.
    SECTION_MAP = { "compose": "compose", "field": "compose", "doc": "docs", "hops": "hops" }
    missing = sorted( { SECTION_MAP[ k ] for k in xmlKids if k in SECTION_MAP }
                      - fjKeys - fjLens )
    check( not missing, "--for --json: every XML section reaches the JSON (%s)"
                        % ( "missing: " + ",".join( missing ) if missing else "none dropped" ) )
    # the specific shape the finding names: a COUNT with no rows behind it and no declaration.
    bad = [ k for k in ( "compose_total", "lego_total", "routes_total" )
            if fj.get( k, 0 ) and k[ : -len( "_total" ) ] not in fjKeys and k[ : -len( "_total" ) ] not in fjLens ]
    check( not bad, "--for --json: no non-zero *_total without its rows or a declaration (%s)"
                    % ( ",".join( bad ) if bad else "none" ) )
except json.JSONDecodeError as e:
    check( False, "--for --json did not parse: %s" % e )

# ═══ FILTER echo: a count under a filter is never mistaken for the repo total ═══════════════════════════
print( "" )
print( "=== FILTER: a verb that accepts a filter echoes it on the root ===" )
for label, args, elem, mcpVerb, mcpArgs in (
        ( "flags",         [ "--flags=RIPWIRE" ],  "flags",   "flags",     { "path": ROOT, "kind": "RIPWIRE" } ),
        # whereis: MCP-only. The CLI verb has NO ref-name filter argument of its own — cfg.strayFilter is
        # set solely by --stray-content=SUBSTR, and passing both selects --stray-content instead. So there
        # is no CLI shape to probe, and "" as the CLI args means the CLI half is skipped, not silently passed.
        ( "whereis",       [], "whereis", "whereis",         { "path": ROOT, "symbol": "escapeXml", "kind": "lane" } ),
        ( "stray_content", [ "--stray-content=lane" ], "stray", "stray_content", { "path": ROOT, "kind": "lane" } ) ):
    if args:
        a = xmlRootAttrs( cli( args ), elem )
        check( a is not None and "filter" in a,
               "%s (CLI, filtered): the root echoes filter= (%s)" % ( label, "yes" if a and "filter" in a else "NO" ) )
    else:
        print( "  SKIP  %s (CLI): this verb takes no filter argument on the CLI — MCP-only, asserted below" % label )
    mx = mcp( mcpVerb, mcpArgs )
    if mx.startswith( "__ERROR__" ):
        check( False, "%s MCP probe: %s" % ( label, mx[ :120 ] ) )
        continue
    ma = xmlRootAttrs( mx, elem )
    check( ma is not None and "filter" in ma,
           "%s (MCP, filtered): the root echoes filter= (%s)" % ( label, "yes" if ma and "filter" in ma else "NO" ) )

# ═══ SELECTOR parity: the same spellings resolve, and the same zero is explained ═══════════════════════
print( "" )
print( "=== SELECTOR: whereis answers the CLI's selector spellings on both surfaces ===" )
# lane L5's found-not-fixed, taken here (H14's "same verb, same contract" half): MCP `whereis` treated an
# @FILE:LINE seed as a LITERAL string and grepped it across every blob — a true, useless hits="0" shaped
# exactly like a name this repo never had — and explained a zero with no near-miss where the CLI does.
# The seed is DERIVED, never pinned. A hard-coded file:line rots the first time the file moves, and a probe
# that silently starts exercising the REFUSAL path instead of the RESOLUTION path is worse than no probe.
# --edit-check reports a symbol's definition site; that line is one an @FILE:LINE seed must resolve.
edp      = re.search( r'<edit-check sym="escapeXml"[^>]*\bp="([^"]+)"', cli( [ "--edit-check=escapeXml" ] ) )
seedSpec = ( "@" + edp.group( 1 ) ) if edp else ""
check( bool( seedSpec ),
       "whereis: derived an @FILE:LINE seed from escapeXml's own definition site (%s)"
       % ( seedSpec or "DERIVATION FAILED — fix this probe, do not pin a literal" ) )
for label, sel in ( ( "@FILE:LINE seed", seedSpec ), ( "near-miss", "escapXml" ) ):
    if not sel:
        continue
    cx = cli( [ "--whereis=" + sel ] )
    mx = mcp( "whereis", { "path": ROOT, "symbol": sel } )
    if mx.startswith( "__ERROR__" ):
        check( False, "whereis %s: MCP refused (%s)" % ( label, mx[ :100 ] ) )
        continue
    cnote = re.findall( r"<selector-note [^>]*>", cx )
    mnote = re.findall( r"<selector-note [^>]*>", mx )
    check( cnote and cnote == mnote,
           "whereis %s: the selector-note is identical on both surfaces (%s)"
           % ( label, cnote[ 0 ] if cnote else "the CLI emitted none — probe is stale, fix it" ) )
    # and the ANSWER itself: a resolved seed must not be answered about the literal string.
    ca, ma = xmlRootAttrs( cx, "whereis" ) or {}, xmlRootAttrs( mx, "whereis" ) or {}
    check( "sym" in ca and "sym" in ma, "whereis %s: both roots carry sym=" % label )
    csym = re.search( r'<whereis sym="([^"]*)"', stripComments( cx ) )
    msym = re.search( r'<whereis sym="([^"]*)"', stripComments( mx ) )
    check( csym and msym and csym.group( 1 ) == msym.group( 1 ),
           "whereis %s: both surfaces resolved the selector to the same symbol (%s vs %s)"
           % ( label, csym.group( 1 ) if csym else "?", msym.group( 1 ) if msym else "?" ) )

print( "" )
if fails == 0: print( "ALL PASS" )
else:          print( "%d CHECK(S) FAILED" % fails )
sys.exit( 1 if fails else 0 )
PY
rc=$?
exit $rc
