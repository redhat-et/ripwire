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
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

# verify-wave2 F1 — the FILTER-echo block below used to name `lane` against the OPERATOR'S OWN branch
# namespace (`--stray-content=lane` on this checkout, MCP `kind:"lane"` on this path). That is wave-1 R3
# re-opened inside a gate this wave ADDED: with the round's lane/ca-* heads present every arm passed, and
# from a fresh `git clone --local` whose only head is `work` the same binary gave
#   FAIL stray_content (CLI, filtered): the root echoes filter= (NO)
#   FAIL stray_content MCP probe: __ERROR__:not a git repository (or no HEAD commit) — no refs to compare
# A probe about a ref-name filter must OWN its refs, so the two ref-filtered rows run against
# test/lib/strayfixture.sh's throwaway repo (branch `main` + a divergent `lane/probe`) exactly as
# precedencecheck / substrfiltercheck / mcpclidiffcheck now do. Presence-guarded: no ref, no assertion.
. "$ROOT/test/lib/strayfixture.sh"
SFIX="$( mktemp -d )"
MFIX_CLEANUP=""
trap 'rm -rf "$SFIX" $MFIX_CLEANUP' EXIT
mkStrayFixture "$SFIX"
strayFixtureHasRef "$SFIX" || {
    echo "  FAIL  fixture: no lane/* ref in the throwaway repo — the filter rows would refuse for the wrong reason"
    echo "1 CHECK(S) FAILED"; exit 1; }
echo "  PASS  fixture: throwaway repo carries a lane/* ref for the kind=lane filter rows to select"

# A2 (found-items 2026-09-17): the CLI and MCP spellings of the "sidecar present but unreadable" baseline
# marker diverged (git-HEAD (sidecar unreadable) vs git-HEAD (unreadable sidecar ignored)). Build a
# throwaway repo with a pre-stamp v5 sidecar — qbaselineproducercheck.sh's own (F) technique, present on
# disk but unrecognizable — so the VALUE probe below (attrparity above is deliberately name-only) can pin
# both surfaces to the ONE documented spelling (verbs_quality.h's own legend).
MFIX="$( mktemp -d )"; MFIX_CLEANUP="$MFIX"
( cd "$MFIX" && git init -q . -b main >/dev/null 2>&1 \
    && git config user.email fx@example.invalid && git config user.name fx \
    && printf 'int f(){return 1;}\n' > a.cpp && git add -A && git commit -qm seed >/dev/null 2>&1 )
"$BIN" "$MFIX" --quality-baseline >/dev/null 2>&1
if [ -f "$MFIX/.ripwire_quality_baseline" ]; then
    sed '1s/^# ripwire quality baseline v[0-9]* /# ripwire quality baseline v5 /' "$MFIX/.ripwire_quality_baseline" >"$MFIX/.rqb.new"
    mv "$MFIX/.rqb.new" "$MFIX/.ripwire_quality_baseline"
fi
# The analyze twin arm needs a corpus BOTH windows show WHOLE: over the full repo each surface keeps its
# own top-200 slice, so window drift (any commit that nudges one ranking) can drop the merged const/
# non-const pair from one side alone — a false divergence with no contract changed. Ten rows, one
# overloading pair, shown entirely by both dialects.
AFX="$( mktemp -d )"; MFIX_CLEANUP="$MFIX_CLEANUP $AFX"   # #279 analyze-twin fixture; cleaned by the trap above
cat > "$AFX/afx.hpp" <<'EOF'
struct Box {
    int* buf();
    const int* buf() const;
    int size();
    void fill( int n );
};
inline int helper_add( int a, int b ) { return a + b; }
inline int helper_sub( int a, int b ) { return a - b; }
inline int helper_mul( int a, int b ) { return a * b; }
EOF
cat > "$AFX/afx.cpp" <<'EOF'
#include "afx.hpp"
int* Box::buf() { return nullptr; }
const int* Box::buf() const { return nullptr; }
int Box::size() { return 0; }
void Box::fill( int ) {}
int client() { Box b; b.fill( 1 ); return b.size() + helper_add( 1, 2 ); }
EOF
echo "mcpattrparitycheck: BIN=$BIN  CORPUS=$ROOT  REFFIX=$SFIX  MARKERFIX=$MFIX  ANFIX=$AFX"

python3 - "$BIN" "$ROOT" "$SFIX" "$MFIX" "$AFX" <<'PY'
import json, os, re, subprocess, sys

BIN, ROOT, SFIX, MFIX, AFX = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

fails = 0
def check( cond, msg ):
    global fails
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: fails += 1

# ── the three surfaces ────────────────────────────────────────────────────────────────────────────────
def cliAt( corpus, args ):
    # L1 (2026-09-19): the CLI default legend is compact; every twin here is the FULL posture (see M1 below), so the CLI
    # operand asks for full too — unless the arm spells its own --legend=, or reads --json (no XML legend).
    if not any( a.startswith( "--legend=" ) or a == "--json" for a in args ):
        args = args + [ "--legend=full" ]
    return subprocess.run( [ BIN, corpus ] + args, capture_output = True, text = True ).stdout

def cli( args ):
    return cliAt( ROOT, args )

# M1 RE-PIN (terminality round A, 2026-09-05): the MCP legend DEFAULT moved full -> compact. Every arm in
# this file compares an MCP payload against the CLI's DEFAULT (full) output, so the server operand asks for
# the posture it is being compared with — `legend:"full"`, injected here once rather than at twenty call
# sites, and only for the seventeen verbs that DECLARE the argument (elsewhere it is an unknown field and is
# refused). An arm that means to exercise the DEFAULT passes raw = True and gets the untouched request; the
# slice block below is the one that does, and it is where the flip itself is pinned CLI-to-MCP.
LEGEND_FAMILY = { "analyze", "lego", "owners", "batch", "exemplar", "impact", "uses", "path_between",
                  "connect", "explore", "from_trace", "edit_check", "whereis", "stray_content", "flags",
                  "doc_drift", "slice",
                  # lane/t10-mcp-coverage: rank_by and affected both declare `legend` (mcprefusal.h)
                  "rank_by", "affected" }

def mcp( name, arguments, raw = False ):
    arguments = dict( arguments )
    if not raw and name in LEGEND_FAMILY and "legend" not in arguments:
        arguments[ "legend" ] = "full"
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
    # quality_delta (lane lean-trio, idea #11): a regression-free CLI answer collapses its <sa> rows to stale_by_kind= and
    # stale_next= (the --show-stale call); the twin LISTS those rows as "sa", so the two facts survive as the rows themselves.
    "stale_by_kind": { "sa" },
    "stale_next":    { "sa" },
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

# A2 (found-items 2026-09-17): VALUE parity for the "sidecar present but unreadable" baseline marker.
# attrparity above is deliberately NAME-only (a git stamp or a root path legitimately differs by value),
# but this one string is a closed, documented vocabulary (verbs_quality.h's own legend) and CLI/MCP must
# spell it identically — MFIX carries a pre-stamp v5 sidecar (present, unrecognizable) built above.
markSide = os.path.join( MFIX, ".ripwire_quality_baseline" )
if not os.path.isfile( markSide ):
    check( False, "A2 fixture: no .ripwire_quality_baseline under MFIX — the marker-parity probe has nothing to corrupt" )
else:
    mkXml = cliAt( MFIX, [ "--quality-delta" ] )
    mkMcp = mcp( "quality_delta", { "path": MFIX } )
    mCli = re.search( r'\bbaseline="([^"]*)"', stripComments( mkXml ) )
    try:    mMcpVal = json.loads( mkMcp ).get( "baseline" ) if not mkMcp.startswith( "__ERROR__" ) else None
    except Exception: mMcpVal = None
    check( bool( mCli ) and mCli.group( 1 ) == "git-HEAD (sidecar unreadable)",
           "A2: CLI baseline= on a present-but-unreadable sidecar is \"git-HEAD (sidecar unreadable)\" (got %r)"
           % ( mCli.group( 1 ) if mCli else None, ) )
    check( mMcpVal == "git-HEAD (sidecar unreadable)",
           "A2: MCP quality_delta baseline spells the same state identically to the CLI (got %r)" % ( mMcpVal, ) )

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
#
# The corpus is a FIXTURE, not $ROOT, on purpose: both surfaces serve a top-200 window, so comparing the
# two windows over a 2,000-symbol tree grades which rows each window happened to keep, not whether the
# dialects agree. An unrelated commit that shifts one ranking can drop the merged const/non-const pair
# out of one window alone (the exact shape of the mcpattrparitycheck rc=1 that followed the --lsp hover
# tiers — no contract changed, the window just moved). The fixture is ten rows: every surface shows the
# whole corpus, so an attribute one dialect can carry and the other cannot is a real divergence again.
mapXml = cliAt( AFX, [] )
anMcp  = mcp( "analyze", { "path": AFX } )
if anMcp.startswith( "__ERROR__" ):
    check( False, "analyze probe: " + anMcp[ :120 ] )
else:
    check( 'overloads="' in mapXml, "analyze fixture: the CLI map merges the const/non-const pair (the twin arm is not vacuous)" )
    report( "analyze rows", xmlRowAttrs( mapXml, "s" ), xmlRowAttrs( anMcp, "s" ), declaredLens( anMcp ) )

# lane/t10-mcp-coverage: rank_by — the SAME <r> map shape as analyze (same serialize() call, same
# statsFirstScreen=true MCP posture, same known divergence: the files=/symbols=/… stanza rides a LEADING
# CLI comment and a TRAILING MCP one — see analyze's own comment above). The <s> row attribute SET is the
# fact that must not move; the comment's POSITION is the declared, accepted difference.
rbXml = cliAt( AFX, [ "--rank-by=authority" ] )
rbMcp = mcp( "rank_by", { "path": AFX, "rank_by": "authority" } )
if rbMcp.startswith( "__ERROR__" ):
    check( False, "rank_by probe: " + rbMcp[ :120 ] )
else:
    check( 'rank_by="authority"' in rbXml, "rank_by fixture: the CLI map stamps rank_by=\"authority\" (the twin arm is not vacuous)" )
    report( "rank_by rows", xmlRowAttrs( rbXml, "s" ), xmlRowAttrs( rbMcp, "s" ), declaredLens( rbMcp ) )
    check( ( 'rank_by="authority"' in stripComments( rbMcp ) ), "rank_by root: MCP stamps the same rank_by=\"authority\" attribute the CLI does" )

# lane/t10-mcp-coverage: affected — UNLIKE analyze/rank_by, this verb has NO posture difference at all
# (testmap.h::writeAffectedReport is the literal same function both surfaces call), so the bar here is the
# tighter one: byte-IDENTICAL once root= (which legitimately differs — "." on a relative CLI invocation vs
# an absolute MCP `path`) is normalised away. Same technique the slice legend-posture block below uses.
afXml = cliAt( ROOT, [ "--affected=src/graph.h" ] )
afMcp = mcp( "affected", { "path": ROOT, "files": "src/graph.h" } )
if afMcp.startswith( "__ERROR__" ):
    check( False, "affected probe: " + afMcp[ :120 ] )
else:
    normAf = lambda t: re.sub( r' root="[^"]*"', ' root="R"', t ).strip()
    check( normAf( afXml ) == normAf( afMcp ),
           "affected: the MCP payload is byte-identical to the CLI's, modulo root= (%d vs %d B)"
           % ( len( afXml ), len( afMcp ) ) )

# ═══ REFUSAL parity: the new tools' bad-input messages name the same facts the CLI's do ═══════════════════
print( "" )
print( "=== REFUSAL: rank_by / affected refuse the CLI's own closed-set and two-reading facts ===" )
# rank_by=churn / churn-decay are valid CLI values this tool REFUSES for now (no MainDispatch/Config over
# MCP to mine git history through) — the refusal must NAME the value and the CLI escape hatch, never read
# as an unknown-value typo (that message is a DIFFERENT sentence, asserted separately below).
for mode in ( "churn", "churn-decay" ):
    m = mcp( "rank_by", { "path": ROOT, "rank_by": mode } )
    check( m.startswith( "__ERROR__" ) and mode in m and "CLI" in m,
           "rank_by=%s: refused by name, pointing at the CLI (%s)" % ( mode, m[ :140 ] ) )
badRb = mcp( "rank_by", { "path": ROOT, "rank_by": "nonsense" } )
check( badRb.startswith( "__ERROR__" ) and "unknown value" in badRb and "nonsense" in badRb,
       "rank_by=nonsense: refused as an unknown value, not silently read as pagerank (%s)" % badRb[ :140 ] )
# TRAIN 10 (CodeRabbit 4056211646): ABSENT and PRESENT-BUT-EMPTY are two different requests. `rank_by:""` read
# as "omitted" and answered pagerank at exit 0 (RED, measured: a 19,552 B map where a refusal belongs), while
# the CLI's own `--rank-by=` refuses. Both halves are asserted, and the OMITTED case beside them — a fix that
# took the default down with the empty value would pass a one-sided arm.
emptyRb = mcp( "rank_by", { "path": ROOT, "rank_by": "" } )
check( emptyRb.startswith( "__ERROR__" ) and "unknown value" in emptyRb,
       "rank_by='' (present but empty): refused as an unknown value, not read as the omitted default (%s)" % emptyRb[ :140 ] )
emptyCli = subprocess.run( [ BIN, ROOT, "--rank-by=" ], capture_output = True, text = True )
check( emptyCli.returncode != 0 and "unknown value" in emptyCli.stderr,
       "--rank-by= (CLI, empty value): refuses with the same reading its MCP twin now gives (%s)" % emptyCli.stderr.strip()[ :110 ] )
check( mcp( "rank_by", { "path": ROOT } ) == mcp( "rank_by", { "path": ROOT, "rank_by": "pagerank" } ) != "__ERROR__",
       "rank_by OMITTED still answers, byte-identically to rank_by='pagerank' — the empty-value refusal did not take the default with it" )
# affected: an item matching neither an indexed path nor a symbol refuses with the same two-reading fact
# the CLI's stderr states (verbs_change.h::runAffected) — echoed on both surfaces, never silently dropped.
cliBad = subprocess.run( [ BIN, ROOT, "--affected=__definitely_not_indexed__" ], capture_output = True, text = True ).stderr
mcpBad = mcp( "affected", { "path": ROOT, "files": "__definitely_not_indexed__" } )
check( "matches no indexed file path" in cliBad and "__definitely_not_indexed__" in cliBad,
       "affected (CLI): the bad-selector refusal names the fact and echoes the item (%s)" % ( "yes" if "matches no indexed file path" in cliBad else "NO" ) )
check( mcpBad.startswith( "__ERROR__" ) and "matches no indexed file path" in mcpBad and "__definitely_not_indexed__" in mcpBad,
       "affected (MCP): the same two-reading refusal, same echoed item (%s)" % mcpBad[ :160 ] )

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
# F1: the CORPUS is a column. `RIPWIRE` is a kind of flag, so `flags` reads this repo; `lane` is a REF NAME,
# so the two ref-filtered rows read SFIX — the throwaway repo that owns a lane/probe head — never whatever
# branches the operator happens to be carrying.
for label, corpus, args, elem, mcpVerb, mcpArgs in (
        ( "flags", ROOT, [ "--flags=RIPWIRE" ],  "flags",   "flags",     { "path": ROOT, "kind": "RIPWIRE" } ),
        # whereis: MCP-only. The CLI verb has NO ref-name filter argument of its own — cfg.strayFilter is
        # set solely by --stray-content=SUBSTR, and passing both selects --stray-content instead. So there
        # is no CLI shape to probe, and "" as the CLI args means the CLI half is skipped, not silently passed.
        ( "whereis", SFIX, [], "whereis", "whereis", { "path": SFIX, "symbol": "probeOne", "kind": "lane" } ),
        ( "stray_content", SFIX, [ "--stray-content=lane" ], "stray", "stray_content",
                                                             { "path": SFIX, "kind": "lane" } ) ):
    if args:
        a = xmlRootAttrs( cliAt( corpus, args ), elem )
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

# ═══ LEGEND posture: the opt-in compact form is the CLI's compact form ═════════════════════════════════
print( "" )
print( "=== LEGEND: legend=\"compact\" on MCP == --legend=compact on the CLI ===" )
# §5a decision 3. The compact posture swaps explanatory prose for a versioned schema id and touches NOTHING
# else — so the assertion is exact: the two payloads are byte-identical once the root= each surface
# legitimately spells differently is normalised away. Default (`legend` omitted) must stay byte-identical to
# what this verb always emitted, which is what makes this opt-in rather than a behaviour change.
# M1: the middle row is the FLIP, pinned across the two surfaces. `legend` omitted is no longer "what this
# verb always emitted" — it is COMPACT, and it must equal the CLI's `--legend=compact` byte for byte. The
# row is asked raw (no injected posture), which is what makes it a test of the default rather than of the
# argument. The other two rows are unchanged and still pin both explicit spellings.
sliceArgs = { "path": ROOT, "symbol": "escapeXml", "var": "out" }
for label, extra, cliFlags, rawCall in ( ( "compact", { "legend": "compact" }, [ "--legend=compact" ], False ),
                                         ( "default (M1: compact)", {},        [ "--legend=compact" ], True  ),
                                         ( "full (explicit)", { "legend": "full" }, [], False ) ):
    a = dict( sliceArgs ); a.update( extra )
    cx = cli( [ "--slice=escapeXml:out" ] + cliFlags )
    mx = mcp( "slice", a, raw = rawCall )
    if mx.startswith( "__ERROR__" ):
        check( False, "slice legend=%s: MCP refused (%s)" % ( label, mx[ :120 ] ) )
        continue
    norm = lambda t: re.sub( r' root="[^"]*"', ' root="R"', t ).strip()
    check( norm( cx ) == norm( mx ),
           "slice legend=%s: the MCP payload is byte-identical to the CLI's, modulo root= (%d vs %d B)"
           % ( label, len( cx ), len( mx ) ) )
    if label == "compact":
        check( 'schema="ripwire.slice/v1"' in mx and len( mx ) < len( cli( [ "--slice=escapeXml:out" ] ) ),
               "slice legend=compact: carries the versioned schema id and is smaller than the full form" )
# a value outside the closed set is refused, never read as the default (the `in` argument's own rule)
bad = mcp( "slice", { "path": ROOT, "symbol": "escapeXml", "var": "out", "legend": "terse" } )
check( bad.startswith( "__ERROR__" ) and "legend" in bad,
       "slice legend=terse: refused by name, never silently read as full" )

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
# The near-miss probe's typo is BUILT, never written as a literal: whereis scans every ref's blobs, this
# file is one of them, and a literal typo here would turn its own zero into a one-hit answer — the probe
# poisoning the property it tests (measured: it did, the first time).
nearMissSel = "escape" + "Xm"
for label, sel in ( ( "@FILE:LINE seed", seedSpec ), ( "near-miss", nearMissSel ) ):
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
