#!/usr/bin/env bash
# declinedsitecheck.sh — the call SITES the resolver declined are NAMED, as hedged rows that are never a resolved edge.
#
#   test/declinedsitecheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# THE GAP. A tier-3 decline (test/declinecheck.sh) or a builtin/standard-member gate decline leaves a call with no
# edge and counts it: --callees answers declined_calls="6", --callers declined_calls="33". The count is honest, but
# it names nothing: buildGraph interns only the candidate LIST (graph.h internDeclinedList, shared by every call with
# the same list), so no answer can say WHICH call, on which line, in which caller. A question "what does doPackage
# call" then misses `pkg.Package( info, f )` through an interface value, and "who calls TaskManager#define_task"
# misses every test that calls it on an untyped receiver — both one call away from the answer.
#
# THE CONTRACT (design: the lane's Phase A note).
#   * At every decline site buildGraph also records ( caller, list index, line ): one record per declined CALL.
#   * --callees=X: one <dc n="NAME" l="LINE" cands="K" via="declined"/> row per declined call X makes, after the <s>
#     rows; a gate decline says which gate: gate="builtin" (the builtin-method name gate) or gate="std" (the C++
#     standard-member gate); a tier-3 decline carries no gate=.
#   * --callers=T (and --safe-delete=T): one <dc in="CALLER" p="FILE:LINE" cands="K" via="declined"/> row per declined
#     call whose candidate LIST holds a definition of T (membership, never the called name: two lists can share a name).
#   * Ruby: a call the side cut declined (in reach, on the other side of self) reads gate="side"; a declined `new` names
#     the called name (n="new"), never its `initialize` candidates.
#   * NEVER an edge: count=, the <s> rows, hop_tested=/hop_untested= and every MCP "count" are exactly what the
#     pre-change binary printed; a <dc> row is its own element and never carries via="name" or prov=.
#   * Capped AND counted: declined_calls= stays the total; past the cap the root says dc_shown="N" (rows printed) and
#     dc_next= (the pasteable call that lists every site); rows past the cap are chosen file-first (each file's first
#     site before any file's second), so a cut still names every file it can.
#   * Candidates are named only on --legend=full (cand="FILE:LINE ...", the definitions the call could have meant);
#     the default rows carry the count alone (cands=).
#   * Multi-definition selectors (attrib-multidef): a callees-form <dc> carries of_def="K" (the definition that makes
#     the call, a fact); a callers-form <dc> carries ONLY hedged tokens K~d ("this declined call's candidates include
#     group K"), never a bare K.
#   * Legend: an answer with <dc> rows defines them, saying what they do NOT mean ("the resolver saw K definitions of
#     this name and proved none; not a claim this call reaches any of them"); an answer without carries no clause.
#   * Dialects: CLI --json "dc":[{"n","l","cands","via"}] / [{"in","p","cands"}]; --format=columnar keeps the <dc>
#     rows verbatim; the MCP twins (find_symbol, find_referencing_symbols) carry "declined_sites":[...] with the same
#     sites ({"name","line","cands","via"} / {"in","file","line","cands"}) and an unchanged "count".
#   * --safe-delete: a definition with no caller and no use but a declined call that could have meant it reads
#     risk="possible-callers", never "none-found", and lists the <dc> rows; --for prints no <dc> row, and --impact (lane
#     ix2-slice, IX-4) prints the callers-form rows of exactly the declines its declined_calls= counts.
#
# ARMS (fixture test/declinedsitefix: go/ py/ rs/ ts/ cpp/ rb/, plus test/declinefix, test/builtinbindfix,
# test/stdmembergatefix and test/lpinfix):
#   (A) the three shapes the rows ask about: a Go interface value (pkg.ConventionalFileName twice, pkg.Package), a Rust
#       &dyn trait call (preprocessor.run), Ruby test-DSL calls of TaskManager#define_task from three test files —
#       every site named with its line, every candidate with --legend=full, none by default
#   (B) language neutrality: the 16 ladder languages of test/declinefix (callees and callers form), plus TS (an
#       interface-typed receiver), C++ (a template parameter receiver) and Python (two declines sharing ONE list keep
#       two rows); Elixir's lexical refusal is not a decline and gets no row
#   (C) near misses: a resolved call, a via="name" row and an external call never get a <dc>; a builtin-gate and a
#       std-gate decline stay labelled as such; count= and the <s> rows are the pre-change binary's (pinned)
#   (D) multi-definition labels (of_def on <dc>)
#   (E) dialects: --json, columnar, the MCP twins (same sites, same count), and every answer parses as XML
#   (F) legend: defined where rows ride, absent elsewhere (and on the zero-decline corpus test/lpinfix)
#   (G) the cap, on generated trees: callers and callees past the cap are counted, file-first, with dc_next=
#   (H) safe-delete never reads none-found beside a declined possible caller; impact lists its <dc> rows, for prints none
#   (K) the gates review's amendments: R1 the three Ruby decline sites (new, side, side over the assembled set) and
#       the W1 discriminator (callers by candidate list, never by name); R2 rows == declined_calls= on every uncut
#       answer (== declined_iface= on the TS interface answers); R3 W1 on the declinedlistcheck shapes (language and
#       root filters split one name into two lists); R4 the default attribute whitelist (no candidates leak under
#       another key, CLI JSON or MCP); R5 every other root attribute is the pre-change literal; R6 dc_next= runs and
#       names every declined line; R7 the cut is file-first in path order; R8 safe-delete's possible-callers is
#       per definition (control none-found; the TS interface method flips); R9/R10 the legend drops "no count or
#       row" where rows ride and reads the review's hedge wording
#   (N) a proven Ruby subscript the side cut declines (`self[ k ]` in a class method, the `def []` an instance method;
#       the same through an included module): the record names the subscript's own reference — rc 0, no contract
#       abort (the ladder runs on a copy of the site, so the record cannot be derived from the copy's address)
#   (I) determinism; (J) the predicates can fail
#
# RED ON BASE: every [P] arm fails on a binary without the record (no <dc> row anywhere); [C] arms are controls that
# pass on both. Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"          # a relative binary is relative to the caller's cwd
echo "declinedsitecheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
for d in declinedsitefix declinefix builtinbindfix stdmembergatefix lpinfix; do
    [ -d "$ROOT/test/$d" ] || { echo "fixture missing: test/$d"; exit 2; }
done
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# Every arm runs in the Python below; its exit status (1 on any FAIL arm, anything else on a crash) is the accumulator's input.
python3 - "$BIN" "$ROOT" "$TMP" <<'PY' || no "the arms above did not all pass (or the checker itself failed): python rc != 0"
import json, os, re, subprocess, sys
import xml.etree.ElementTree as ET

BIN, ROOT, TMP = sys.argv[1], sys.argv[2], sys.argv[3]
T = os.path.join( ROOT, "test" )
FIX, DF = os.path.join( T, "declinedsitefix" ), os.path.join( T, "declinefix" )
BB, SM, CLEAN = os.path.join( T, "builtinbindfix" ), os.path.join( T, "stdmembergatefix" ), os.path.join( T, "lpinfix" )
npass = nfail = 0

def say( good, tag, msg, why = "" ):
    global npass, nfail
    if good:
        npass += 1; print( "  PASS  %s: %s" % ( tag, msg ) )
    else:
        nfail += 1; print( "  FAIL  %s: %s%s" % ( tag, msg, ( " -- " + why ) if why else "" ) )

def run( root, *args ):
    """( rc, stdout ) of one CLI answer; rc 124 on a timeout."""
    try:
        p = subprocess.run( [ BIN, root, "--no-cache" ] + list( args ), capture_output = True, text = True, timeout = 240 )
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired:
        return 124, ""

def mcp( tool, arguments ):
    """The MCP tool's text payload parsed as JSON, or None (initialize + one tools/call over stdio)."""
    req = json.dumps( { "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {} } ) + "\n" + json.dumps(
        { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": tool, "arguments": arguments } } ) + "\n"
    try:
        p = subprocess.run( [ BIN, "--mcp" ], input = req, capture_output = True, text = True, timeout = 240 )
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
    """One XML answer: its root element, the <s>/<c> rows, the <dc> rows (anywhere), the leading legend comments."""
    def __init__( self, rc, text, tag ):
        self.rc, self.text, self.tag = rc, text, tag
        self.root, self.err = None, ""
        m = re.match( r"(\s*<!--.*?-->)+", text, re.S )
        self.legend = m.group( 0 ) if m else ""
        try:
            doc = ET.fromstring( "<doc>" + text + "</doc>" )
            self.root = doc.find( tag )
        except ET.ParseError as e:
            self.err = "not well-formed XML: %s" % e
        self.dc = [ dict( e.attrib ) for e in self.root.iter( "dc" ) ] if self.root is not None else []
        rowtag = "c" if tag == "safe-delete" else "s"
        self.rows = [ dict( e.attrib ) for e in self.root.findall( rowtag ) ] if self.root is not None else []
    @property
    def ok( self ):
        return self.rc == 0 and self.root is not None
    def a( self, k ):
        return self.root.get( k ) if self.root is not None else None
    def why( self ):
        if self.rc != 0: return "rc=%s" % self.rc
        if self.root is None: return self.err or "no <%s> root" % self.tag
        return "root %s; dc=%s" % ( dict( self.root.attrib ), self.dc )

def ask( root, verb, sel, *more ):
    rc, out = run( root, "--%s=%s" % ( verb, sel ), *more )
    return Answer( rc, out, verb if verb != "safe-delete" else "safe-delete" )

def dc_sites( ans, key ):
    return sorted( ( d.get( key[ 0 ] ), d.get( key[ 1 ] ), d.get( "cands" ) ) for d in ans.dc )

def line_of( path, needle ):
    with open( path, encoding = "utf-8" ) as f:
        for i, line in enumerate( f, 1 ):
            if needle in line:
                return str( i )
    return "?"

LEG_DONT = "proved none"
LEG_NOT  = "not a claim this call reaches any of them"

# ── (A) the three shapes ────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (A) the declined sites the rows ask about are named ===" )
GO, RS, RB = os.path.join( FIX, "go" ), os.path.join( FIX, "rs" ), os.path.join( FIX, "rb" )
a = ask( GO, "callees", "doPackage" )
want = WANT_GO = [ ( "ConventionalFileName", "16", "2" ), ( "ConventionalFileName", "18", "2" ), ( "Package", "24", "2" ) ]
say( a.ok and dc_sites( a, ( "n", "l" ) ) == want, "[P] a_go",
     "go --callees=doPackage names pkg.ConventionalFileName@16, @18 and pkg.Package@24 (cands=2 each)", a.why() )
say( a.ok and all( d.get( "via" ) == "declined" and "gate" not in d for d in a.dc ) and len( a.dc ) == 3, "[P] a_go_via",
     "each tier-3 row reads via=\"declined\" and carries no gate=", a.why() )
say( a.ok and a.a( "count" ) == "2" and a.a( "declined_calls" ) == "3" and sorted( r.get( "n" ) for r in a.rows ) == [ "Get", "WithDefaults" ],
     "[C] a_go_count", "count=\"2\" and the two resolved <s> rows are the pre-change answer; declined_calls=\"3\" stays the total", a.why() )
say( a.ok and not ( { d.get( "n" ) for d in a.dc } & { "Get", "WithDefaults", "Create", "Stat" } ), "[C] a_go_neg",
     "the resolved (pkgr.Get, pkgr.WithDefaults) and external (os.Create) calls get no <dc>", a.why() )
say( a.ok and not any( "cand" in d for d in a.dc ), "[C] a_go_nocand", "default rows carry no candidate names (cand=)", a.why() )
af = ask( GO, "callees", "doPackage", "--legend=full" )
cands = { ( d.get( "n" ), d.get( "l" ) ): set( d.get( "cand", "" ).split() ) for d in af.dc }
say( af.ok and cands.get( ( "Package", "24" ) ) == { "deb/deb.go:15", "rpm/rpm.go:15" }
     and cands.get( ( "ConventionalFileName", "16" ) ) == { "deb/deb.go:11", "rpm/rpm.go:11" }, "[P] a_go_full",
     "--legend=full lists each row's candidates as file:line (Deb and RPM; not the interface's bodyless signature)", af.why() )

r = ask( RS, "callees", "preprocess_book" )
say( r.ok and dc_sites( r, ( "n", "l" ) ) == [ ( "run", "18", "2" ) ], "[P] a_rs",
     "rust --callees=preprocess_book names preprocessor.run@18 through Box<dyn Preprocessor> (cands=2)", r.why() )
say( r.ok and r.a( "count" ) == "2" and sorted( x.get( "n" ) for x in r.rows ) == [ "PreprocessorContext::new", "preprocessor_should_run" ], "[C] a_rs_count",
     "count=\"2\" (PreprocessorContext::new, preprocessor_should_run) unchanged", r.why() )
rf = ask( RS, "callees", "preprocess_book", "--legend=full" )
say( rf.ok and len( rf.dc ) == 1 and set( rf.dc[ 0 ].get( "cand", "" ).split() ) == { "src/builtin/index/mod.rs:10", "src/builtin/links/mod.rs:10" },
     "[P] a_rs_full", "--legend=full names LinkPreprocessor::run and IndexPreprocessor::run", rf.why() )

b = ask( RB, "callers", "lib/rake/task_manager.rb:define_task" )
want = WANT_RB = sorted( [ ( "test_create_task_manager", "test/test_task_manager.rb:9", "2" ), ( "test_define_two", "test/test_task_manager.rb:13", "2" ),
                 ( "test_define_two", "test/test_task_manager.rb:14", "2" ), ( "test_load_rakefile", "test/test_application.rb:5", "2" ),
                 ( "test_top_level", "test/test_application.rb:9", "2" ), ( "test_namespace_lookup", "test/test_name_space.rb:6", "2" ) ] )
say( b.ok and dc_sites( b, ( "in", "p" ) ) == want, "[P] a_rb",
     "ruby --callers=TaskManager#define_task names the six test-DSL sites in all three test files", b.why() )
say( b.ok and b.a( "count" ) == "2" and b.a( "declined_calls" ) == "6" and len( b.rows ) == 2, "[C] a_rb_count",
     "count=\"2\" (Task.define_task, synthesize_file_task) and declined_calls=\"6\" unchanged", b.why() )

# ── (B) language neutrality ────────────────────────────────────────────────────────────────────────────────────────
print( "=== (B) every ladder language names its declined site ===" )
# lang | caller | callee | call file (relative to test/declinefix) | one definition selector
table = [
    ( "java", "javaDeclined", "jbody", "java/caller/JavaCaller.java", "java/alpha/Alpha.java:jbody" ),
    ( "cpp", "cppDeclined", "crender", "cpp/caller/caller.cpp", "cpp/alpha/alpha.cpp:crender" ),
    ( "py", "py_declined", "pyfetch", "py/caller/caller.py", "py/alpha/alpha.py:pyfetch" ),
    ( "rust", "rust_declined", "rfetch", "rust/caller/caller.rs", "rust/alpha/alpha.rs:rfetch" ),
]
for lang, caller, callee in [ ( "ts", "tsDeclined", "tsHop" ), ( "js", "jsDeclined", "jsHop" ), ( "go", "GoDeclined", "GoHop" ),
                              ( "swift", "swiftDeclined", "swiftHop" ), ( "objc", "objcDeclined", "objcHop" ),
                              ( "bash", "bash_declined", "bash_hop" ), ( "ruby", "ruby_declined", "ruby_hop" ),
                              ( "csharp", "CsDeclined", "CsHop" ), ( "c", "c_declined", "c_hop" ), ( "php", "phpDeclined", "phpHop" ),
                              ( "lua", "lua_declined", "lua_hop" ), ( "dart", "dartDeclined", "dartHop" ) ]:
    cdir, adir = os.path.join( DF, "sweep", lang, "c" ), os.path.join( DF, "sweep", lang, "a" )
    cfile = [ f for f in sorted( os.listdir( cdir ) ) ][ 0 ]
    afile = [ f for f in sorted( os.listdir( adir ) ) ][ 0 ]
    table.append( ( lang, caller, callee, "sweep/%s/c/%s" % ( lang, cfile ), "sweep/%s/a/%s:%s" % ( lang, afile, callee ) ) )
for lang, caller, callee, cfile, defsel in table:
    call_line = line_of( os.path.join( DF, cfile ), callee )
    x = ask( DF, "callees", caller )
    say( x.ok and dc_sites( x, ( "n", "l" ) ) == [ ( callee, call_line, "2" ) ] and x.a( "count" ) == "0", "[P] b_%s" % lang,
         "%s: --callees=%s names %s@%s (cands=2), count=\"0\"" % ( lang, caller, callee, call_line ), x.why() )
    y = ask( DF, "callers", defsel )
    say( y.ok and dc_sites( y, ( "in", "p" ) ) == [ ( caller, "%s:%s" % ( cfile, call_line ), "2" ) ] and y.a( "count" ) == "0",
         "[P] b_%s_callers" % lang, "%s: --callers=%s names %s at %s:%s" % ( lang, defsel, caller, cfile, call_line ), y.why() )
x = ask( DF, "callees", "ex_declined" )
say( x.ok and x.dc == [] and x.a( "graph_unresolved" ) == "2", "[C] b_elixir",
     "elixir: the lexical refusal is counted unresolved, not declined, and gets no <dc>", x.why() )
TS, CPP, PYF = os.path.join( FIX, "ts" ), os.path.join( FIX, "cpp" ), os.path.join( FIX, "py" )
x = ask( TS, "callees", "dispatch" )
say( x.ok and dc_sites( x, ( "n", "l" ) ) == [ ( "match", "8", "2" ) ] and x.a( "count" ) == "1", "[P] b_ts_iface",
     "ts: router.match@8 on an interface-typed receiver is named; clean() stays the one <s> row", x.why() )
x = ask( CPP, "callees", "drive" )
say( x.ok and dc_sites( x, ( "n", "l" ) ) == [ ( "run", "9", "2" ) ] and x.a( "count" ) == "1", "[P] b_cpp_tmpl",
     "c++: engine.run@9 on a template-parameter receiver is named; twice() stays the one <s> row", x.why() )
x = ask( PYF, "callees", "caller/use.py:load_twice" )
say( x.ok and dc_sites( x, ( "n", "l" ) ) == [ ( "fetch", "11", "2" ), ( "fetch", "12", "2" ) ], "[P] b_py_shared",
     "python: two declines sharing ONE interned candidate list keep two rows, one per line", x.why() )

# ── (C) near misses ────────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (C) near misses: no <dc> where nothing was declined; gate declines stay labelled ===" )
x = ask( GO, "callees", "onlyResolved" )
say( x.ok and x.dc == [] and x.a( "declined_calls" ) is None and not any( k.startswith( "dc_" ) for k in x.root.attrib )
     and "<dc" not in x.legend, "[C] c_resolved", "a function whose every call resolved: no <dc>, no dc_ attribute, no legend clause", x.why() )
x = ask( PYF, "callees", "fetch_all" )
say( x.ok and x.dc == [] and len( x.rows ) == 2 and all( r.get( "via" ) == "name" for r in x.rows ), "[C] c_byname",
     "via=\"name\" rows (a same-directory by-name binding) are edges, never <dc>", x.why() )
x = ask( BB, "callees", "py/plain.py:param_get" )
say( x.ok and len( x.dc ) == 1 and x.dc[ 0 ].get( "n" ) == "get" and x.dc[ 0 ].get( "gate" ) == "builtin" and x.a( "count" ) == "0",
     "[P] c_gate_builtin", "the builtin-method gate's decline (config.get) reads gate=\"builtin\"", x.why() )
x = ask( SM, "callees", "stdAppend" )
stdm = x.root.find( "stdm" ) if x.root is not None else None
say( x.ok and len( x.dc ) == 1 and x.dc[ 0 ].get( "n" ) == "append" and x.dc[ 0 ].get( "gate" ) == "std" and stdm is not None,
     "[P] c_gate_std", "the C++ standard-member gate's decline reads gate=\"std\", beside its unchanged <stdm> line", x.why() )
for tag, root, verb, sel in [ ( "go", GO, "callees", "doPackage" ), ( "rs", RS, "callees", "preprocess_book" ),
                              ( "rb", RB, "callers", "lib/rake/task_manager.rb:define_task" ), ( "py", PYF, "callers", "fetch" ) ]:
    x = ask( root, verb, sel )
    say( x.ok and len( x.rows ) == int( x.a( "count" ) or -1 ) and not any( r.get( "via" ) == "declined" for r in x.rows )
         and not any( "prov" in d or d.get( "via" ) == "name" for d in x.dc ), "[C] c_count_%s" % tag,
         "%s --%s=%s: <s> rows == count=, no <s> row reads via=\"declined\", no <dc> reads like an edge" % ( tag, verb, sel ), x.why() )

# ── (D) multi-definition labels ────────────────────────────────────────────────────────────────────────────────────
print( "=== (D) of_def on <dc> rows ===" )
x = ask( PYF, "callees", "load" )
got = sorted( ( d.get( "l" ), d.get( "of_def" ) ) for d in x.dc )
say( x.ok and x.a( "defs" ) == "2" and got == [ ( "2", "2" ), ( "7", "1" ) ], "[P] d_callees",
     "callees of two definitions: each <dc> names the definition that makes the call (of_def=\"1\" / \"2\", a fact)", x.why() )
x = ask( PYF, "callers", "fetch" )
toks = [ set( d.get( "of_def", "" ).split() ) for d in x.dc ]
say( x.ok and len( x.dc ) == 4 and all( t == { "1~d", "2~d" } for t in toks ), "[P] d_callers",
     "callers of two definitions: every <dc> reads of_def=\"1~d 2~d\" (hedged: its candidates hold both), never a bare K", x.why() )
say( x.ok and "~d" in x.legend, "[P] d_legend", "the legend defines the ~d mark", x.why() )

# ── (E) dialects ───────────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (E) --json, columnar, MCP ===" )
rc, out = run( GO, "--callees=doPackage", "--json" )
try:
    j = json.loads( out )
except ValueError:
    j = {}
jd = sorted( ( d.get( "n" ), str( d.get( "l" ) ), str( d.get( "cands" ) ) ) for d in j.get( "dc", [] ) )
say( rc == 0 and jd == WANT_GO and len( j.get( "callees", [] ) ) == 2 and j.get( "count" ) == 2, "[P] e_json_callees",
     "--json carries \"dc\" with the XML sites; \"callees\" and \"count\" unchanged", "rc=%s dc=%s" % ( rc, j.get( "dc" ) ) )
rc, out = run( RB, "--callers=lib/rake/task_manager.rb:define_task", "--json" )
try:
    j = json.loads( out )
except ValueError:
    j = {}
jd = sorted( ( d.get( "in" ), d.get( "p" ), str( d.get( "cands" ) ) ) for d in j.get( "dc", [] ) )
say( rc == 0 and jd == WANT_RB and j.get( "count" ) == 2, "[P] e_json_callers",
     "callers --json carries the same six sites", "rc=%s dc=%s" % ( rc, j.get( "dc" ) ) )
rc, out = run( GO, "--callees=doPackage", "--format=columnar" )
c = Answer( rc, out, "callees" )
say( c.ok and dc_sites( c, ( "n", "l" ) ) == WANT_GO, "[P] e_columnar", "columnar keeps the <dc> rows verbatim", c.why() )
m = mcp( "find_symbol", { "path": GO, "symbol": "doPackage" } ) or {}
md = sorted( ( d.get( "name" ), str( d.get( "line" ) ), str( d.get( "cands" ) ) ) for d in m.get( "declined_sites", [] ) )
say( md == WANT_GO and m.get( "count" ) == 2 and all( d.get( "via" ) == "declined" for d in m.get( "declined_sites", [] ) ),
     "[P] e_mcp_callees", "MCP find_symbol: \"declined_sites\" == the CLI rows, \"count\" unchanged", "declined_sites=%s count=%s" % ( m.get( "declined_sites" ), m.get( "count" ) ) )
say( m != {} and not any( str( x.get( "via", "" ) ) == "declined" for x in m.get( "calls", [] ) ), "[C] e_mcp_calls",
     "MCP \"calls\" holds no declined site", str( m.get( "calls" ) ) )
m = mcp( "find_referencing_symbols", { "path": RB, "symbol": "lib/rake/task_manager.rb:define_task" } ) or {}
md = sorted( ( d.get( "in" ), "%s:%s" % ( d.get( "file" ), d.get( "line" ) ), str( d.get( "cands" ) ) ) for d in m.get( "declined_sites", [] ) )
say( md == WANT_RB and m.get( "count" ) == 2, "[P] e_mcp_callers",
     "MCP find_referencing_symbols: the same six sites, \"count\" unchanged", "declined_sites=%s count=%s" % ( m.get( "declined_sites" ), m.get( "count" ) ) )
for tag, ans in [ ( "full_go", af ), ( "full_rs", rf ) ]:
    say( ans.ok and ans.err == "", "[C] e_xml_%s" % tag, "the --legend=full answer with <dc> rows is well-formed XML", ans.why() )

# ── (F) legend ─────────────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (F) the legend says what a <dc> row does NOT mean ===" )
say( a.ok and "<dc" in a.legend and LEG_DONT in a.legend and LEG_NOT in a.legend, "[P] f_legend_callees",
     "callees legend defines <dc> with 'proved none' and 'not a claim this call reaches any of them'", a.legend[ -400: ] )
say( b.ok and "<dc" in b.legend and LEG_NOT in b.legend, "[P] f_legend_callers", "callers legend defines <dc> the same way", b.legend[ -400: ] )
for sel, verb in [ ( "other", "callers" ), ( "go", "callees" ), ( "other", "impact" ) ]:
    x = ask( CLEAN, verb, sel )
    say( x.ok and x.dc == [] and x.a( "declined_calls" ) is None and "<dc" not in x.legend and "dc_" not in x.text, "[C] f_absent_%s" % verb,
         "zero-decline corpus: --%s carries no <dc> row and no clause" % verb, x.why() )

# ── (G) the cap, on generated trees ────────────────────────────────────────────────────────────────────────────────
print( "=== (G) capped AND counted ===" )
G = os.path.join( TMP, "cap" )
for d in ( "alpha", "beta", "callers", "big" ):
    os.makedirs( os.path.join( G, d ), exist_ok = True )
open( os.path.join( G, "alpha", "a.py" ), "w" ).write( "class A:\n    def poll(self):\n        return 1\n" )
open( os.path.join( G, "beta", "b.py" ), "w" ).write( "class B:\n    def poll(self):\n        return 2\n" )
for f in range( 3 ):
    with open( os.path.join( G, "callers", "f%d.py" % f ), "w" ) as h:
        for k in range( 12 ):
            h.write( "def use_%d_%d(x):\n    return x.poll()\n\n\n" % ( f, k ) )
with open( os.path.join( G, "big", "big.py" ), "w" ) as h:
    h.write( "def big(x):\n" + "".join( "    x.poll()\n" for _ in range( 40 ) ) + "    return x\n" )
x = ask( G, "callers", "alpha/a.py:poll" )
shown = int( x.a( "dc_shown" ) or 0 ) if x.ok else 0
files = { d.get( "p", "" ).rsplit( ":", 1 )[ 0 ] for d in x.dc }
say( x.ok and x.a( "declined_calls" ) == "76" and 8 <= shown <= 24 and len( x.dc ) == shown and x.a( "dc_next" ),
     "[P] g_callers_cut", "76 declined callers: dc_shown=N (8..24) rows printed, declined_calls=\"76\" the total, dc_next= present", x.why() )
say( x.ok and files == { "callers/f0.py", "callers/f1.py", "callers/f2.py", "big/big.py" }, "[P] g_callers_files",
     "the cut is file-first: all four calling files are named", "files=%s" % sorted( files ) )
x = ask( G, "callees", "big" )
shown = int( x.a( "dc_shown" ) or 0 ) if x.ok else 0
ls = [ int( d.get( "l", "0" ) ) for d in x.dc ]
say( x.ok and x.a( "declined_calls" ) == "40" and 8 <= shown <= 24 and len( x.dc ) == shown and ls == sorted( ls ) and len( set( ls ) ) == len( ls )
     and x.a( "dc_next" ), "[P] g_callees_cut", "40 declined calls in one body: dc_shown rows in line order, dc_next= present", x.why() )
x = ask( G, "callees", "use_0_0" )
say( x.ok and len( x.dc ) == 1 and x.a( "dc_shown" ) is None and x.a( "dc_next" ) is None, "[P] g_uncut",
     "under the cap: every row, no dc_shown= and no dc_next=", x.why() )

# ── (H) the other verbs ────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (H) safe-delete, impact, for ===" )
x = ask( GO, "safe-delete", "deb/deb.go:Package" )
say( x.ok and x.a( "risk" ) == "possible-callers" and x.a( "callers" ) == "0", "[P] h_sd_risk",
     "safe-delete of a definition only a declined call could mean: risk=\"possible-callers\", never none-found; callers=\"0\" unchanged", x.why() )
say( x.ok and dc_sites( x, ( "in", "p" ) ) == [ ( "doPackage", "cmd/package.go:24", "2" ) ], "[P] h_sd_rows",
     "safe-delete lists the declined possible caller as a <dc> row", x.why() )
x = ask( PYF, "safe-delete", "beta/store.py:fetch" )
say( x.ok and x.a( "risk" ) == "untested-radius" and x.a( "callers" ) == "1", "[C] h_sd_ctrl",
     "a definition with a real caller keeps its risk= (untested-radius) and callers=\"1\"", x.why() )
x = ask( GO, "impact", "deb/deb.go:Package" )
# lane ix2-slice (IX-4): --impact now names the declines its declined_calls= counts, in the callers form (was: no row)
say( x.ok and dc_sites( x, ( "in", "p" ) ) == [ ( "doPackage", "cmd/package.go:24", "2" ) ] and x.a( "reaches" ) == "0" and x.a( "declined_calls" ) == "1",
     "[P] h_impact", "impact lists the declined call its declined_calls=\"1\" counts as a callers-form <dc> row; reaches=\"0\" unchanged", x.why() )
xf = ask( GO, "impact", "deb/deb.go:Package", "--legend=full" )
say( xf.ok and "<dc in= p= via=\"declined\">" in xf.legend and LEG_NOT in xf.legend and "the <dc> rows below name them" in xf.legend
     and "The callers verb on SYM lists" not in xf.legend and "<dc n= l=|in= p=" in x.legend, "[P] h_impact_legend",
     "the impact legend defines its <dc> rows the callers way (full: what a row is NOT; compact: the dc reading)", xf.legend[ -400: ] )
# lane ix2-slice (IX-4): the served order is TIER first (source, then test/bench, then docs — filter.h pathTierOf), then path:
# a test file whose path sorts first no longer leads; and the impact rows ride --json and columnar as --callers' do.
TO = os.path.join( TMP, "tierorder" )
for d in ( "alpha", "beta", "tests", "zlib" ):
    os.makedirs( os.path.join( TO, d ), exist_ok = True )
open( os.path.join( TO, "alpha", "a.py" ), "w" ).write( "class A:\n    def poll(self):\n        return 1\n" )
open( os.path.join( TO, "beta", "b.py" ), "w" ).write( "class B:\n    def poll(self):\n        return 2\n" )
open( os.path.join( TO, "tests", "t.py" ), "w" ).write( "def use_t(x):\n    return x.poll()\n" )
open( os.path.join( TO, "zlib", "u.py" ), "w" ).write( "def use_u(x):\n    return x.poll()\n" )
x = ask( TO, "callers", "alpha/a.py:poll" )
say( x.ok and [ d.get( "p" ) for d in x.dc ] == [ "zlib/u.py:2", "tests/t.py:2" ], "[P] h_tier_order",
     "callers <dc> rows: the source site (zlib/) before the test site (tests/), though tests/ sorts first by path", x.why() )
x = ask( TO, "impact", "alpha/a.py:poll" )
say( x.ok and [ d.get( "p" ) for d in x.dc ] == [ "zlib/u.py:2", "tests/t.py:2" ] and x.a( "declined_calls" ) == "2", "[P] h_impact_order",
     "impact lists the same two rows in the same order, declined_calls=\"2\"", x.why() )
rc, out = run( TO, "--impact=alpha/a.py:poll", "--json" )
try:
    jd = json.loads( out ).get( "dc", [] )
except ValueError:
    jd = None
say( rc == 0 and jd is not None and [ ( d.get( "in" ), d.get( "p" ) ) for d in jd ] == [ ( "use_u", "zlib/u.py:2" ), ( "use_t", "tests/t.py:2" ) ], "[P] h_impact_json",
     "impact --json carries \"dc\" with the same rows (keys = the XML attribute names)", "rc=%s %s" % ( rc, out[ :300 ] ) )
rc, out = run( TO, "--impact=alpha/a.py:poll", "--format=columnar" )
body = re.sub( r"<!--.*?-->", "", out, flags = re.S )
say( rc == 0 and body.count( "<dc " ) == 2 and body.index( "zlib/u.py:2" ) < body.index( "tests/t.py:2" ), "[P] h_impact_columnar",
     "impact --format=columnar keeps the <dc> rows verbatim", "rc=%s %s" % ( rc, out[ -300: ] ) )
rc, out = run( GO, "--for=doPackage" )
say( rc == 0 and "<dc" not in out and len( out ) > 0, "[C] h_for", "--for prints no <dc> row", "rc=%s" % rc )

# ── (K) the gates review's amendments (R1–R11): the wrong implementations that passed every arm above ────────────────
print( "=== (K) R1 Ruby decline sites: new, and the two side cuts (gate=\"side\") ===" )
RBS = os.path.join( FIX, "rbside" )
x = ask( RBS, "callees", "build" )
say( x.ok and len( x.dc ) == 1 and x.dc[ 0 ].get( "n" ) == "new" and x.dc[ 0 ].get( "l" ) == "3" and x.dc[ 0 ].get( "cands" ) == "1"
     and "gate" not in x.dc[ 0 ], "[P] k_rb_new",
     "ruby --callees=build names the declined `new` at base.rb:3 as n=\"new\" (the CALLED name, never the candidate's initialize), cands=1, no gate=", x.why() )
x = ask( RBS, "callers", "lib/child.rb:initialize" )
say( x.ok and dc_sites( x, ( "in", "p" ) ) == [ ( "build", "lib/base.rb:3", "1" ) ], "[P] k_rb_new_callers",
     "ruby --callers=lib/child.rb:initialize names the declined `new` in build at lib/base.rb:3", x.why() )
for sel in ( "run", "make" ):
    x = ask( RBS, "callees", sel )
    say( x.ok and len( x.dc ) == 1 and x.dc[ 0 ].get( "n" ) == "helper" and x.dc[ 0 ].get( "l" ) == "7" and x.dc[ 0 ].get( "gate" ) == "side",
         "[P] k_rb_side_%s" % sel, "ruby --callees=%s names helper@7 with gate=\"side\" (in reach, other side of self)" % sel, x.why() )
for sel, only in ( ( "lib/widget.rb:helper", "run" ), ( "lib/gadget.rb:helper", "make" ) ):
    x = ask( RBS, "callers", sel )
    say( x.ok and [ d.get( "in" ) for d in x.dc ] == [ only ], "[P] k_rb_w1_%s" % only,
         "W1: --callers=%s names ONLY %s (candidate-list membership, never the called name)" % ( sel, only ), x.why() )

print( "=== (K) R3 W1 on the declinedlistcheck shapes: lists, never names ===" )
ONE, WS = os.path.join( TMP, "one" ), os.path.join( TMP, "ws" )
def cfn( path, name, body ):
    os.makedirs( os.path.dirname( path ), exist_ok = True )
    open( path, "w" ).write( "int %s()\n{\n    return %s;\n}\n" % ( name, body ) )
def pyfn( path, name, body ):
    os.makedirs( os.path.dirname( path ), exist_ok = True )
    open( path, "w" ).write( "def %s():\n    return %s\n" % ( name, body ) )
cfn( os.path.join( ONE, "a", "size.cpp" ), "size", "1" ); cfn( os.path.join( ONE, "b", "size.cpp" ), "size", "2" )
pyfn( os.path.join( ONE, "c", "size.py" ), "size", "3" ); pyfn( os.path.join( ONE, "d", "size.py" ), "size", "4" )
cfn( os.path.join( ONE, "e", "caller.cpp" ), "e_call", "size()" ); pyfn( os.path.join( ONE, "f", "caller.py" ), "f_call", "size()" )
for r in ( "r1", "r2" ):
    cfn( os.path.join( WS, r, "x.cpp" ), "foo", "1" ); cfn( os.path.join( WS, r, "y", "foo.cpp" ), "foo", "2" )
    cfn( os.path.join( WS, r, "z", "caller.cpp" ), "%s_call" % r, "foo()" )
for sel, only in ( ( "a/size.cpp:size", "e_call" ), ( "c/size.py:size", "f_call" ) ):
    x = ask( ONE, "callers", sel )
    say( x.ok and [ d.get( "in" ) for d in x.dc ] == [ only ] and x.a( "declined_calls" ) == "1", "[P] k_list_%s" % only,
         "W1: --callers=%s names only %s (the language filter splits `size` into two lists)" % ( sel, only ), x.why() )
rc, out = 124, ""
try:
    p = subprocess.run( [ BIN, "r1", "r2", "--no-cache", "--callers=r1/x.cpp:foo" ], cwd = WS, capture_output = True, text = True, timeout = 240 )
    rc, out = p.returncode, p.stdout
except subprocess.TimeoutExpired:
    pass
x = Answer( rc, out, "callers" )
say( x.ok and [ d.get( "in" ) for d in x.dc ] == [ "r1_call" ], "[P] k_list_roots",
     "W1: two roots: --callers=r1/x.cpp:foo names only r1's caller (the root filter splits `foo`)", x.why() )

print( "=== (K) R2 rows == declined_calls= on every uncut answer; TS: == declined_iface= too ===" )
uncut = [ ( "go callees doPackage", ask( GO, "callees", "doPackage" ) ), ( "rb callers define_task", ask( RB, "callers", "lib/rake/task_manager.rb:define_task" ) ),
          ( "py callers fetch", ask( PYF, "callers", "fetch" ) ), ( "py callees load", ask( PYF, "callees", "load" ) ),
          ( "go safe-delete Package", ask( GO, "safe-delete", "deb/deb.go:Package" ) ), ( "rbside callees build", ask( RBS, "callees", "build" ) ),
          ( "rbside callers widget helper", ask( RBS, "callers", "lib/widget.rb:helper" ) ), ( "bb callees param_get", ask( BB, "callees", "py/plain.py:param_get" ) ),
          ( "sm callees stdAppend", ask( SM, "callees", "stdAppend" ) ), ( "ts callees dispatch", ask( TS, "callees", "dispatch" ) ),
          ( "cpp callees drive", ask( CPP, "callees", "drive" ) ), ( "df callers java", ask( DF, "callers", "java/alpha/Alpha.java:jbody" ) ) ]
bad = [ "%s: rows=%d declined_calls=%s" % ( tag, len( x.dc ), x.a( "declined_calls" ) ) for tag, x in uncut
        if not ( x.ok and x.a( "dc_shown" ) is None and len( x.dc ) > 0 and str( len( x.dc ) ) == x.a( "declined_calls" ) ) ]
say( not bad, "[P] k_rows_eq_declined", "on %d uncut answers the <dc> row count equals declined_calls= (every decline site records)" % len( uncut ), "; ".join( bad ) )
for sel in ( "src/routers/trie/router.ts:match", "src/routers/router.ts:match" ):
    x = ask( TS, "callers", sel )
    say( x.ok and len( x.dc ) == 1 and x.a( "declined_calls" ) == "1" and x.a( "declined_iface" ) == "1" and x.dc[ 0 ].get( "in" ) == "dispatch",
         "[P] k_ts_iface_%s" % sel.split( "/" )[ -2 ], "ts --callers=%s: one <dc> (dispatch) == declined_calls=\"1\" == declined_iface=\"1\"" % sel, x.why() )

print( "=== (K) R4 attribute whitelist; R11 via=\"declined\" on every form ===" )
CALLEE_KEYS, CALLER_KEYS = { "n", "l", "cands", "via", "gate", "of_def" }, { "in", "p", "cands", "via", "gate", "of_def" }
ce = [ x for tag, x in uncut if x.tag == "callees" ] + [ ask( G, "callees", "big" ) ]
cr = [ x for tag, x in uncut if x.tag != "callees" ] + [ ask( G, "callers", "alpha/a.py:poll" ) ]
say( all( x.ok and x.dc for x in ce ) and all( set( d ) <= CALLEE_KEYS and d.get( "via" ) == "declined" for x in ce for d in x.dc ), "[P] k_keys_callees",
     "default callees <dc> keys stay within {n,l,cands,via,gate,of_def}, via=\"declined\" on each", str( [ d for x in ce for d in x.dc if set( d ) - CALLEE_KEYS ][ :3 ] ) )
say( all( x.ok and x.dc for x in cr ) and all( set( d ) <= CALLER_KEYS and d.get( "via" ) == "declined" for x in cr for d in x.dc ), "[P] k_keys_callers",
     "default callers and safe-delete <dc> keys stay within {in,p,cands,via,gate,of_def}, via=\"declined\" on each (Q2)",
     str( [ d for x in cr for d in x.dc if set( d ) - CALLER_KEYS or d.get( "via" ) != "declined" ][ :3 ] ) )
jbad = []
for root, flag in ( ( GO, "--callees=doPackage" ), ( RB, "--callers=lib/rake/task_manager.rb:define_task" ) ):
    rc, out = run( root, flag, "--json" )
    try:
        j = json.loads( out )
    except ValueError:
        j = {}
    if rc != 0 or not j.get( "dc" ) or any( "cand" in d or "candidates" in d for d in j[ "dc" ] ):
        jbad.append( "%s rc=%s dc=%s" % ( flag, rc, j.get( "dc" ) ) )
say( not jbad, "[P] k_json_nocand", "--json default \"dc\" entries carry no \"cand\" (candidates only on legend=full)", "; ".join( jbad ) )
mbad = []
for tool, root, sym in ( ( "find_symbol", GO, "doPackage" ), ( "find_referencing_symbols", RB, "lib/rake/task_manager.rb:define_task" ) ):
    m = mcp( tool, { "path": root, "symbol": sym } ) or {}
    ds = m.get( "declined_sites", [] )
    if not ds or any( "candidates" in d or "cand" in d or d.get( "via" ) != "declined" for d in ds ):
        mbad.append( "%s declined_sites=%s" % ( tool, ds ) )
say( not mbad, "[P] k_mcp_nocand", "MCP default \"declined_sites\" entries carry via=\"declined\" and no \"candidates\"", "; ".join( mbad ) )

print( "=== (K) R5 the root keeps every base attribute (dc_shown/dc_next aside) ===" )
BASE_ROOTS = [
    ( "a_go", GO, "callees", "doPackage", { "schema": "ripwire.callees/v1", "of": "doPackage", "defs": "1", "count": "2", "hop_tested": "0", "hop_untested": "2",
      "declined_calls": "3", "graph_ambiguous": "0", "graph_unresolved": "0", "graph_unindexed": "1", "counts_floor": "1", "next": "--expand=doPackage" } ),
    ( "a_rb", RB, "callers", "lib/rake/task_manager.rb:define_task", { "schema": "ripwire.callers/v1", "of": "lib/rake/task_manager.rb:define_task", "defs": "1",
      "count": "2", "hop_tested": "0", "hop_untested": "2", "declined_calls": "6", "graph_ambiguous": "0", "graph_unresolved": "0", "counts_floor": "1",
      "next": "--uses=define_task" } ),
    ( "d_callers", PYF, "callers", "fetch", { "schema": "ripwire.callers/v1", "of": "fetch", "defs": "2", "count": "2", "hop_tested": "0", "hop_untested": "2",
      "declined_calls": "4", "graph_ambiguous": "0", "graph_unresolved": "0", "counts_floor": "1", "next": "--uses=fetch" } ),
    ( "g_callers", G, "callers", "alpha/a.py:poll", { "schema": "ripwire.callers/v1", "of": "alpha/a.py:poll", "defs": "1", "count": "0", "hop_tested": "0",
      "hop_untested": "0", "declined_calls": "76", "graph_ambiguous": "0", "graph_unresolved": "0", "counts_floor": "1", "next": "--uses=poll" } ),
]
for tag, root, verb, sel, want in BASE_ROOTS:
    x = ask( root, verb, sel )
    got = { k: v for k, v in ( x.root.attrib.items() if x.root is not None else [] ) if k not in ( "root", "dc_shown", "dc_next" ) }
    say( x.ok and x.dc and got == want, "[P] k_root_%s" % tag, "%s --%s=%s: rows ride and every other root attribute is the base literal" % ( tag, verb, sel ),
         "got %s" % { k: ( got.get( k ), want.get( k ) ) for k in set( got ) | set( want ) if got.get( k ) != want.get( k ) } )

print( "=== (K) R6 dc_next is a call that lists every site; R7 the cut is file-first in path order ===" )
import shlex
G_CALLER_LINES = { "big/big.py:%d" % l for l in range( 2, 42 ) } | { "callers/f%d.py:%d" % ( f, 2 + 4 * k ) for f in range( 3 ) for k in range( 12 ) }
for verb, sel, want_lines in ( ( "callers", "alpha/a.py:poll", G_CALLER_LINES ), ( "callees", "big", { str( l ) for l in range( 2, 42 ) } ) ):
    x = ask( G, verb, sel )
    nxt = x.a( "dc_next" ) or ""
    rc, out = run( G, *shlex.split( nxt ) ) if nxt else ( 1, "" )
    if verb == "callers":
        named = set( re.findall( r' p="([^"]+)"', out ) )
    else:
        named = { m for m in re.findall( r'<dc [^>]*\bl="(\d+)"', out ) }
    say( x.ok and nxt and rc == 0 and want_lines <= named, "[P] k_dc_next_%s" % verb,
         "the printed dc_next= (%s) runs (rc 0) and names all %d declined call lines" % ( nxt or "absent", len( want_lines ) ),
         "rc=%s missing=%d" % ( rc, len( want_lines - named ) ) )
x = ask( G, "callers", "alpha/a.py:poll" )
first4 = [ d.get( "p", "" ).rsplit( ":", 1 )[ 0 ] for d in x.dc[ :4 ] ]
say( x.ok and first4 == [ "big/big.py", "callers/f0.py", "callers/f1.py", "callers/f2.py" ], "[P] k_cut_order",
     "the first four callers rows of the cut are four distinct files in path order (each file's first site before any file's second)", "first4=%s" % first4 )

print( "=== (K) R8 safe-delete: possible-callers only where a declined call could mean THIS definition ===" )
x = ask( GO, "safe-delete", "cmd/package.go:onlyResolved" )
say( x.ok and x.a( "risk" ) == "none-found" and x.dc == [] and x.a( "declined_calls" ) is None, "[C] k_sd_ctrl",
     "a definition no declined call could mean keeps risk=\"none-found\" on a tree that has declines", x.why() )
x = ask( TS, "safe-delete", "src/routers/trie/router.ts:match" )
say( x.ok and x.a( "risk" ) == "possible-callers" and [ d.get( "in" ) for d in x.dc ] == [ "dispatch" ], "[P] k_sd_ts",
     "ts --safe-delete=src/routers/trie/router.ts:match reads risk=\"possible-callers\" with the dispatch <dc> row (base: none-found)", x.why() )

print( "=== (K) R9 + R10 legend: no \"no count or row\" where <dc> rides; the hedge in the review's words ===" )
R10_EDGE = "NOT an edge and NOT a caller or callee claim"
R10_K1   = "(K may be 1)"
lbad = []
for tag, x in uncut + [ ( "g callers", ask( G, "callers", "alpha/a.py:poll" ) ) ]:
    if not x.ok or not x.dc:
        lbad.append( "%s: no <dc> rows" % tag )
    elif "no count or row" in x.legend:
        lbad.append( "%s: says 'no count or row'" % tag )
say( not lbad, "[P] k_legend_drift", "no answer carrying <dc> rows also says 'no count or row' (compact)", "; ".join( lbad[ :4 ] ) )
lbad = []
for root, verb, sel in ( ( GO, "callees", "doPackage" ), ( RB, "callers", "lib/rake/task_manager.rb:define_task" ), ( GO, "safe-delete", "deb/deb.go:Package" ),
                         ( RBS, "callees", "run" ) ):
    x = ask( root, verb, sel, "--legend=full" )
    if not x.ok or not x.dc:
        lbad.append( "%s: no <dc> rows" % sel )
    elif "no count or row" in x.legend or R10_EDGE not in x.legend or R10_K1 not in x.legend or LEG_DONT not in x.legend or LEG_NOT not in x.legend:
        lbad.append( "%s: legend lacks the R10 wording or keeps 'no count or row'" % sel )
    elif x.err:
        lbad.append( "%s: %s" % ( sel, x.err ) )
say( not lbad, "[P] k_legend_full", "--legend=full: the <dc> clause reads 'NOT an edge and NOT a caller or callee claim', '(K may be 1)', 'proved none', "
     "'not a claim this call reaches any of them'; no 'no count or row'; well-formed XML", "; ".join( lbad ) )
x = ask( RBS, "callees", "run", "--legend=full" )
say( x.ok and x.dc and "gate=side" in x.legend, "[P] k_legend_side", "the gate=side reading rides where a gate=\"side\" row does", x.why() )
x = ask( GO, "safe-delete", "deb/deb.go:Package", "--legend=full" )
say( x.ok and "possible-callers:" in x.legend and "not a safety reading" in x.legend and "none-found beside declined_calls=" not in x.legend,
     "[P] k_legend_sd", "safe-delete's risk sentence defines possible-callers and says it is not a safety reading", x.why() )

# ── (I) determinism ────────────────────────────────────────────────────────────────────────────────────────────────
print( "=== (I) determinism ===" )
rc1, o1 = run( GO, "--callees=doPackage", "--legend=full" )
rc2, o2 = run( GO, "--callees=doPackage", "--legend=full" )
say( rc1 == 0 and rc2 == 0 and o1 == o2 and len( o1 ) > 0, "[C] i_det", "two runs byte-identical" )

# ── (L) train 28: PR #380's inert quoted sites beside the <dc> records ─────────────────────────────────────────────────
# An Elixir call candidate inside inert quote AST is counted in declinedOut (the callees declined_calls=) but reaches no
# decline site, so it writes no record and has no <dc> row. Merged with this lane, declinedSitesMadeBy's postcondition
# (records == declined_calls=) aborted --callees on such a function (ENSURES, both branches: a tree with no record at all,
# and a tree whose records belong to other callers). Arms: an Elixir-only tree, then the same file beside a Python tree
# with tier-3 records; and the rows legend says the quoted sites have no row (only where both ride).
print( "=== (L) inert quoted sites (PR #380) carry no record and abort nothing ===" )
EX = os.path.join( T, "elixirfix" )
x = ask( EX, "callees", "quoted", "--legend=full" )
say( x.ok and x.a( "declined_calls" ) == "1" and not x.dc, "[L] l_ex_only",
     "elixirfix --callees=quoted: exit 0, declined_calls=\"1\" (the quoted nonexistent(x)), no <dc> row", x.why() )
MIX = os.path.join( TMP, "mix" )
import shutil
shutil.copytree( PYF, os.path.join( MIX, "py" ) )
os.makedirs( os.path.join( MIX, "ex" ) ); shutil.copy( os.path.join( EX, "run.exs" ), os.path.join( MIX, "ex", "run.exs" ) )
x = ask( MIX, "callees", "quoted" )
say( x.ok and x.a( "declined_calls" ) == "1" and not x.dc, "[L] l_mixed_inert",
     "beside Python records: --callees=quoted exit 0, declined_calls=\"1\", no <dc> row", x.why() )
# a selector whose definitions made BOTH: a Python `quoted` with a declined store.fetch (rows) beside the Elixir quoted/0
with open( os.path.join( MIX, "py", "caller", "q.py" ), "w", encoding = "utf-8" ) as f:
    f.write( "def quoted(store, key):\n    return store.fetch(key)\n" )
rc, out = run( MIX, "--callees=quoted", "--legend=full" )
y = Answer( rc, out, "callees" )
say( y.ok and len( y.dc ) >= 1 and int( y.a( "declined_calls" ) or 0 ) == len( y.dc ) + 1
     and "No <dc> row names those quoted sites" in out and "inert quote AST" in out, "[L] l_rows_legend",
     "--callees=quoted over a Python and an Elixir definition: the Python rows, declined_calls= one more (the inert site), the inert clause and its no-row sentence", y.why() )
rc, out = run( PYF, "--callees=caller/use.py:load_twice", "--legend=full" )
say( rc == 0 and "No <dc> row names those quoted sites" not in out and "inert quote AST" not in out, "[L] l_rows_legend_neg",
     "the same answer on the Python tree alone carries neither sentence (present-only)" )

# (L, CR pre-pass) the inert sentences ride only an answer whose OWN definitions made an inert quoted site: on the same mixed
# tree a Python selector whose every declined call has its row carries neither (it was charged graph-wide before);
# and the MCP map (analyze) defines the inert sites its declined= counts, as the CLI map does.
rc, out = run( MIX, "--callees=load", "--legend=full" )
y = Answer( rc, out, "callees" )
say( y.ok and len( y.dc ) == int( y.a( "declined_calls" ) or -1 ) and "No <dc> row names those quoted sites" not in out and "inert quote AST" not in out,
     "[L] l_rows_no_inert", "mixed tree, --callees=load: every declined call has its row, so neither inert sentence rides", y.why() )
req = json.dumps( { "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {} } ) + "\n" + json.dumps(
    { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": "analyze", "arguments": { "path": EX, "legend": "full" } } } ) + "\n"
an = ""
try:
    p = subprocess.run( [ BIN, "--mcp" ], input = req, capture_output = True, text = True, timeout = 240 )
    for line in p.stdout.splitlines():
        try: r = json.loads( line )
        except ValueError: continue
        if r.get( "id" ) == 2 and "result" in r: an = r[ "result" ][ "content" ][ 0 ][ "text" ]
except ( subprocess.TimeoutExpired, KeyError, IndexError, TypeError ): an = ""
say( "declined=" in an and "inert-quote-AST" in an, "[L] l_mcp_map", "MCP analyze on elixirfix: declined= and the inert map clause, as on the CLI", an[ :160 ] )

# ── (M) train 28: the review's N1 (honesty-adjacent) and N3 ──────────────────────────────────────────────────────────
# N1: both declined_calls= clauses said "two or more same-language definitions, none in the caller's file or directory"
# of every counted call, false beside a Ruby side-cut row whose ONE candidate is in the caller's own file (rbside). The
# clause now scopes that to tier 3 and says a name gate or Ruby's side/new rule may decline one. N3: the MCP declined_note
# describes the "declined_sites" entries by their own keys, not the XML <dc in= p=> attributes.
print( "=== (M) the declined_calls= clauses scope tier 3; the MCP note speaks its own keys ===" )
UNSCOPED = "none in the caller's file or directory, and no qualifier, receiver type or include chose one, so no edge"
SCOPED = "chose one (tier 3); a name gate or Ruby's side/new rule may decline one"
x = ask( RBS, "callees", "run", "--legend=full" )
say( x.ok and any( d.get( "gate" ) == "side" and d.get( "cands" ) == "1" for d in x.dc ) and SCOPED in x.text and UNSCOPED not in x.text,
     "[M] m_rows_clause", "rbside --callees=run beside a gate=\"side\" cands=\"1\" row: the rows clause scopes tier 3", x.why() )
x = ask( RBS, "impact", "lib/widget.rb:helper", "--legend=full" )
say( x.ok and ( "declined_calls=" not in x.text or ( SCOPED in x.text and UNSCOPED not in x.text ) ), "[M] m_base_clause",
     "the row-less clause (impact) is scoped the same way where it rides", x.why() )
m = mcp( "find_symbol", { "path": GO, "symbol": "doPackage" } ) or {}
note = str( m.get( "declined_note", "" ) )
say( bool( m.get( "declined_sites" ) ) and note.startswith( "declined_sites:" ) and "{name, line" in note and "<dc" not in note, "[M] m_mcp_note",
     "MCP find_symbol declined_note names the declined_sites keys, not <dc> attributes", note[ :160 ] )
m = mcp( "find_symbol", { "path": PYF, "symbol": "load" } ) or {}
note = str( m.get( "declined_note", "" ) )
say( any( d.get( "of_def" ) for d in m.get( "declined_sites", [] ) ) and "of_def [K]" in note and "<dc" not in note, "[M] m_mcp_note_ofdef",
     "MCP find_symbol on a multi-definition selector: the of_def clause speaks the entry keys too", note[ -200: ] )

# ── (N) a proven subscript the side cut declines (CodeRabbit, #413) ──────────────────────────────────────────────
print( "=== (N) a declined proven subscript is recorded at its own reference ===" )
RBSUB = os.path.join( TMP, "rbsub" )
os.makedirs( RBSUB, exist_ok = True )
with open( os.path.join( RBSUB, "k.rb" ), "w" ) as f:
    f.write( "class Keeper\n  def [](k)\n    k\n  end\n  def self.run\n    self[1]\n  end\nend\n"
             "module Mixer\n  def [](k)\n    k\n  end\nend\nclass Holder\n  include Mixer\n  def self.go\n    self[2]\n  end\nend\n" )
for caller, line in ( ( "run", "6" ), ( "go", "17" ) ):
    x = ask( RBSUB, "callees", caller )
    say( x.ok and [ ( d.get( "n" ), d.get( "l" ), d.get( "gate" ) ) for d in x.dc ] == [ ( "[]", line, "side" ) ], "[P] n_sub_%s" % caller,
         "ruby --callees=%s: `self[...]` in a class method declines on the side cut, one <dc n=\"[]\" l=\"%s\" gate=\"side\"> (rc 0, no abort)" % ( caller, line ),
         x.why() )
x = ask( RBSUB, "callers", "[]" )
say( x.ok and sorted( ( d.get( "in" ), d.get( "p" ) ) for d in x.dc ) == [ ( "go", "k.rb:17" ), ( "run", "k.rb:6" ) ], "[P] n_sub_callers",
     "ruby --callers=[]: both declined subscripts are named at their own lines", x.why() )

# ── (J) the predicates can fail ────────────────────────────────────────────────────────────────────────────────────
print( "=== (J) the predicates reject what they must ===" )
fake = Answer( 0, '<callers of="x" count="1" declined_calls="1"><s n="a" p="f:1"/><dc in="b" p="g:2" cands="2" of_def="1"/></callers>', "callers" )
say( fake.ok and not all( set( d.get( "of_def", "" ).split() ) <= { "1~d", "2~d" } for d in fake.dc ), "[C] j_bare_k",
     "a callers-form <dc of_def=\"1\"> (a bare K) is caught" )
fake = Answer( 0, '<callees of="x" count="1"><s n="a"/><s n="b" via="declined"/></callees>', "callees" )
say( fake.ok and ( len( fake.rows ) != int( fake.a( "count" ) ) or any( r.get( "via" ) == "declined" for r in fake.rows ) ), "[C] j_in_count",
     "a declined site folded into the <s> rows / count= is caught" )
fake = Answer( 0, '<callees of="x"><dc n="a" l="1" cands="2"/>', "callees" )
say( not fake.ok, "[C] j_malformed", "a malformed answer is not read as an empty one" )

print( "declinedsitecheck: %d PASS / %d FAIL" % ( npass, nfail ) )
sys.exit( 1 if nfail else 0 )
PY
if [ "$fail" = 0 ]; then echo "declinedsitecheck: PASS"; else echo "declinedsitecheck: FAIL"; exit 1; fi
