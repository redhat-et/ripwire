#!/usr/bin/env bash
# forfilesymscheck.sh — K-WRONGSYM (src/forfilesyms.h): a --for answer names, in <syms> before </ctx>, symbols of its first shown files
# that it does not name anywhere: by="name" (the name shares a task word) and by="callee" (a head <d> row calls it; the graph edge's
# hedge rides the row). The answer before the block is unchanged.
#
# ARMS (each language: Python, TypeScript, Go, C++, Rust, Ruby; one generated shape — 80 `integration_check_NN` functions, each calling a
# helper directly and a member of its own Store type through a parameter, so the head's later rows have callees no hop names)
#   (a1) by="name" rows: three, and name_total= the candidates (the cap is disclosed; the constants 3 rows, 6 files, 8 head rows live in the
#        legend, so no name=/callee=/*_capped=/head= attribute prints), each p=file:line and no body
#   (a2) by="callee" rows: a direct call is evidence-bound (no via=), and in Python and TypeScript the
#        parameter's member call is bound by name alone and says via="name"
#   (q1) a member row is Scope.name in its language's spelling (`.` Python/TS/Go, `::` C++/Rust, `#` Ruby)
#   (ns1) Python: namesakes of two head rows (same names, a test file) are the only callers of a shown-file function: by="callee" via="name"
#   (d1) dedupe: no <y> row's name is a word anywhere else in the answer
#   (e1) the answer with RIPWIRE_NO_FILE_SYMS=1 equals the answer minus the block (legend comment + element), byte for byte, but
#        for the one edit the block makes (R-DEDUP: <syms> has priority): a name it prints is cut from the sym= of a tail row whose
#        file a <d> row shows (a row left with none prints p= only)
#   (w1) well formed XML, the block's legend holds no double hyphen, the block is last before </ctx>, one per answer
#   (l1) every attribute the block prints (<syms> and each <y>, the core p= n= aside) is defined `name=` in the legend comment right
#        before it (the legendcoveragecheck predicate): the compact legend on the CLI rows, the full one on x1 (MCP); (h1) the held stub's
#        own legend defines held= and next=
#   (m1) M1, the dedupe reads the bytes the run emitted: a task that fires the literal-anchor block (the textual-03 shape: a function the
#        <lit> body calls was offered as unnamed) offers none of its names; twin: with RIPWIRE_NO_LITERAL_ANCHOR=1 the same names are offered
#   (m2) M1, a name is a token of the answer with its sigil: TypeScript `Router.#addRoute` (the hono-11 shape), JS `$addRoute`, Ruby `add_route?`
#        are shown rows and are not offered again; twin: an unshown sigil-spelled member is offered
#        (a sigil-spelled helper only the <lit> body names: TypeScript `#isValidAnimationLevel`, Ruby `animation_level_valid?`, with the same twin)
#   (m3) the same dedupe over --with-graph and a graph_verb block (every block before <syms> is read)
#   (s2) a C++ header declaration and its out-of-line definition are one row (the definition's p=), no n= repeats
#        (and the C shape: api.h declarations, api.c definitions)
#   (k1..k5) K-DECL-IDENT, C and C++: a header declaration folds into a same-name definition only when they are provably one function.
#        (k1) the definition's file does not include the header and shares no stem: both rows, the header's row kept (a namesake);
#        (k2) it includes the header directly; (k3) through an umbrella header; (k4) same path stem, no include; (k5) a root-relative
#        include from another directory (`#include "include/api.h"` in src/): each folds to the definition's row only;
#        (k6) the source file only repeats the prototypes: the header's row stays beside it (a prototype is no implementation);
#        (k7) api.h and api.C (uppercase C++ extension), no include: same stem, folds
#   (s1) a row in a test file says test="1"; no row of a source file does
#   (u1) a run that cannot buffer its bytes prints <syms held="uncaptured"/> and says so on stderr (non-NDEBUG flavour: SKIP otherwise)
#   (p1) a shown path holding a tab (the answer writes it `a&#9;b.py`) is looked up as the indexed file: its symbols are offered, p= spelled as the answer spells it
#   (t1) a shown TypeScript private member (`Router.#addRoute`, stored as `#addRoute`) is a head row for by="callee": the helpers it calls are offered
#   (i1..i4) CONST-INIT-CALLEE by="init" (residual pass 11-12, card 3; i1 i2 i4 RED on main 0b8f0bf8d): a head row's name (one of the
#        first 5 <d> rows, or the re-export walk's <def> row) whose module-level declaration's value is one file-scope call names that
#        call's callee (of= the name, at= the declaration); a literal initialiser or an already-shown callee is no row; RIPWIRE_NO_INIT_ROWS=1
#   (i5) FORFILESYMS-INIT-WINDOW-LEGEND (CodeRabbit on #646; RED on main 44f7d3326): an initialiser whose `(` sits past the 200-byte
#        window is disclosed (<syms init_cut="1">, both legends state the window); (i5n) its short twin is an ordinary row, no init_cut
#   (i6) FORFILESYMS-COMMENT-DECL (CodeRabbit on #646; RED on main 44f7d3326): a docstring or /* */ twin declaration earlier in the
#        file is skipped (no file-scope call stands in it): the real declaration's callee prints
#   (i7) FORFILESYMS-INIT-REF-RESOLVE (CodeRabbit on #646; RED on main 44f7d3326): an external initialiser call is not credited with
#        another module-scope call's same-named edge (no row); two calls written alike (angular's makeDecorator) keep the row
#   (o1) overloads: the shown row's edge reaches one overload, the kept row is another: it says via="name"; twin (o2) one definition, the call is plain
#   (h2) a held block's next= carries the origin call's ranking flags (--no-route, --anchor under RIPWIRE_DEV, --pack-top-n=N)
#   (c2) a capture whose buffer fails to flush (RLIMIT_FSIZE, a real short write) is not read as the whole answer: stderr says so, exit 1, the stub says held="uncaptured", no rows; twin: unlimited, rows
#   (n1) present-only: a one-function tree has no candidate and prints no block (twin: a1 fires on the same binary)
#   (h1) --token-budget holds the block: <syms held="budget" next=...>, no rows; (j1) --json carries no block
#   (x1) MCP `for`: the block (one renderer), read off the MCP answer's own bytes: a1, d1 and w1 hold on it
#   (b1..b5) VR-BINDER-ROW, TypeScript and Python (any language whose value-ref pass records into= slot binds): a head <d> row that
#        another function stores into a slot (a returned object literal, a dict) gains a by="bind" row naming that binder, with into=
#        the slot as the callers' <vr> row spells it, from any file. (b1) the factory in another file is the row; (b2) a head nobody
#        binds, in a block a by="name" row prints, has no by="bind" row and no bind clause in its legend (bytes only when a bind exists); (b3) three binders of one
#        head: two rows (kForFileSymsBindPerHead) and bind_total="3", the cap stated in the legend; (b4) Python: a dict's value binds
#        the same way; (b5) the legend right before the block defines by="bind", into= and bind_total=; RIPWIRE_NO_BIND_ROWS=1 drops them; (b6) a binder an
#        earlier head counted past its cap prints once under a later head's free slot
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forfilesymscheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
TASK='why does the integration check fail'

# one generated tree per language
python3 - "$TMP" <<'PY' || { echo "fixture generator failed"; exit 2; }
import os, sys
T = sys.argv[1]
def w( d, f, s ):
    os.makedirs( os.path.join( T, d ), exist_ok = True ); open( os.path.join( T, d, f ), "w" ).write( s )
N = range( 1, 81 )
w( "py", "checks.py", "\n".join( f"def integration_check_{i:02d}(x, store):\n    store.warm_entry_{i:02d}(x)\n    return _helper_{i:02d}(x)\n\n\n"
                                 f"def _helper_{i:02d}(x):\n    return x\n\n\nclass Store{i:02d}:\n    def warm_entry_{i:02d}(self, x):\n        return x\n\n" for i in N ) )
w( "ts", "checks.ts", "\n".join( f"export function integrationCheck{i:02d}(x: number, store: any): number {{\n  store.warmEntry{i:02d}(x);\n  return helper{i:02d}(x);\n}}\n"
                                 f"function helper{i:02d}(x: number): number {{\n  return x;\n}}\n"
                                 f"export class Store{i:02d} {{\n  warmEntry{i:02d}(x: number): number {{\n    return x;\n  }}\n}}\n" for i in N ) )
w( "go", "go.mod", "module fx\n\ngo 1.21\n" )
w( "go", "checks.go", "package fx\n\n" + "\n".join( f"type Store{i:02d} struct{{}}\n\nfunc (s *Store{i:02d}) warmEntry{i:02d}(x int) int {{ return x }}\n\n"
                                                     f"func helper{i:02d}(x int) int {{ return x }}\n\n"
                                                     f"func IntegrationCheck{i:02d}(x int, s *Store{i:02d}) int {{\n\ts.warmEntry{i:02d}(x)\n\treturn helper{i:02d}(x)\n}}\n" for i in N ) )
w( "cpp", "checks.cpp", "\n".join( f"struct Store{i:02d} {{\n    int warm_entry_{i:02d}( int x );\n}};\nint Store{i:02d}::warm_entry_{i:02d}( int x ) {{ return x; }}\n"
                                   f"static int helper_{i:02d}( int x ) {{ return x; }}\n"
                                   f"int integration_check_{i:02d}( int x, Store{i:02d}& s ) {{\n    s.warm_entry_{i:02d}( x );\n    return helper_{i:02d}( x );\n}}\n" for i in N ) )
w( "rs", "checks.rs", "\n".join( f"pub struct Store{i:02d};\nimpl Store{i:02d} {{\n    pub fn warm_entry_{i:02d}(&self, x: i32) -> i32 {{ x }}\n}}\n"
                                 f"fn helper_{i:02d}(x: i32) -> i32 {{ x }}\n"
                                 f"pub fn integration_check_{i:02d}(x: i32, s: &Store{i:02d}) -> i32 {{\n    s.warm_entry_{i:02d}(x);\n    helper_{i:02d}(x)\n}}\n" for i in N ) )
w( "rb", "checks.rb", "\n".join( f"class Store{i:02d}\n  def warm_entry_{i:02d}(x)\n    x\n  end\nend\n\n"
                                 f"def helper_{i:02d}(x)\n  x\nend\n\n"
                                 f"def integration_check_{i:02d}(x, s)\n  s.warm_entry_{i:02d}(x)\n  helper_{i:02d}(x)\nend\n" for i in N ) )
# namesakes of head rows 5 and 6 in a test file (ranked below the shown rows) are the only callers of namesake_target (in the shown
# file): its row is hedged via="name" although each call is a plain one
w( "pyns", "checks.py", open( os.path.join( T, "py", "checks.py" ) ).read() + "\n\ndef namesake_target(x):\n    return x\n" )
w( "pyns/tests", "elsewhere.py", "from checks import namesake_target\n\n\ndef integration_check_05(x):\n    return namesake_target(x)\n\n\n"
                               "def integration_check_06(x):\n    return namesake_target(x)\n" )
# M1 / S1 / S2 / constants shapes (the generators mirror reports/rv-k.md's repros: textual-03 literal block, hono-11 `#private`, C++ decl+def)
w( "lit", "constants.py", 'import os\n\nTEXTUAL_ANIMATIONS = "TEXTUAL_ANIMATIONS"\n\n\ndef _is_valid_animation_level(value):\n    return value in ("none", "basic", "full")\n\n\n'
                           'def _get_animation_level():\n    value = os.environ.get(TEXTUAL_ANIMATIONS, "full")\n    if _is_valid_animation_level(value):\n        return value\n    return "full"\n' )
w( "lit", "other.py", 'import os\n\n\ndef read_flag():\n    return os.environ.get("TEXTUAL_ANIMATIONS", "")\n' )
# the same literal shape with a sigil-spelled helper only the <lit> body names (a TypeScript #private method, a Ruby predicate): not a shown row, so only the token spelling hides it
w( "tslit", "constants.ts", 'export const TEXTUAL_ANIMATIONS = "TEXTUAL_ANIMATIONS";\n\nexport class AnimationConfig {\n  #isValidAnimationLevel(value: string): boolean {\n    return value === "none" || value === "full";\n  }\n\n'
                            '  getAnimationLevel(): string {\n    const value = process.env[TEXTUAL_ANIMATIONS] ?? "full";\n    if (this.#isValidAnimationLevel(value)) {\n      return value;\n    }\n    return "full";\n  }\n}\n' )
w( "tslit", "other.ts", 'export function readFlag(): string {\n  return process.env["TEXTUAL_ANIMATIONS"] ?? "";\n}\n' )
w( "rblit", "constants.rb", 'TEXTUAL_ANIMATIONS = "TEXTUAL_ANIMATIONS"\n\nclass AnimationConfig\n  def animation_level_valid?(value)\n    %w[none full].include?(value)\n  end\n\n'
                            '  def animation_level\n    value = ENV.fetch(TEXTUAL_ANIMATIONS, "full")\n    return value if animation_level_valid?(value)\n    "full"\n  end\nend\n' )
w( "rblit", "other.rb", 'def read_flag\n  ENV["TEXTUAL_ANIMATIONS"].to_s\nend\n' )
M = range( 1, 41 )
w( "tssig", "router.ts", "export class Router {\n  private routes: string[] = [];\n  add(path: string): void {\n    this.#addRoute(path);\n  }\n  #addRoute(path: string): void {\n    this.routes.push(path);\n  }\n}\n"
   + "".join( f"class Step{i:02d} {{\n  #routeStep{i:02d}(path: string): string {{\n    return path;\n  }}\n}}\n" for i in M ) )
w( "jssig", "ed.js", "function $addRoute(x) {\n  return x;\n}\nfunction addRoute(x) {\n  return $addRoute(x);\n}\n" + "".join( f"function $routeStep{i:02d}(x) {{\n  return x;\n}}\n" for i in M ) )
w( "rbsig", "router.rb", "class Router\n  def add_route?(x)\n    !x.nil?\n  end\n\n  def add_route(x)\n    add_route?(x)\n  end\nend\n"
   + "".join( f"\nclass Step{i:02d}\n  def route_step_{i:02d}?(x)\n    x\n  end\nend\n" for i in M ) )
w( "cppdecl", "ver.h", "#pragma once\nstruct Plan {\n" + "".join( f"  bool EdgeWanted{i:02d}(int x);\n" for i in M ) + "};\n" + "".join( f"int ParseVersion{i:02d}(const char* s);\n" for i in M ) )
w( "cppdecl", "ver.cc", '#include "ver.h"\n' + "".join( f"bool Plan::EdgeWanted{i:02d}(int x) {{ return x > {i}; }}\n" for i in M ) + "".join( f"int ParseVersion{i:02d}(const char* s) {{ return s[0] - {i}; }}\n" for i in M ) )
w( "pyt/tests", "test_checks.py", "\n".join( f"def test_integration_check_{i:02d}(x):\n    assert x\n\n" for i in N ) )
w( "chdr", "api.h", "#pragma once\n" + "".join( f"int find_home_{i:02d}(void);\n" for i in M ) )
w( "chdr", "api.c", '#include "api.h"\n' + "".join( f"int find_home_{i:02d}(void) {{ return {i}; }}\n" for i in M ) )
for f in range( 1, 9 ):
    w( "wide", f"m{f}.py", "".join( f"def route_table_{f}_{i:02d}(x):\n    return x\n\n\n" for i in range( 1, 30 ) ) )
w( "one", "solo.py", "def integration_check(x):\n    return x\n" )
# CR 4486667521: a shown path holding a tab is written a&#9;b.py; CR 4486667567: a TypeScript private head row keeps its # (the stored name);
# CR 4486667593: overloads, the call binds to the second, the first is kept
try:
    w( "tabp", "a\tb.py", "".join( f"def integration_check_{i:02d}(x):\n    return helper_{i:02d}(x)\n\n\ndef helper_{i:02d}(x):\n    return x\n\n\n" for i in range( 1, 30 ) ) )
except OSError:
    pass                                                               # a file system that cannot hold a tab in a name: (p1) SKIPs below
w( "tspriv", "router.ts", "".join( f"function linkTarget{i:02d}(path: string): string {{\n  return path;\n}}\nclass Step{i:02d} {{\n  #routeStep{i:02d}(path: string): string {{\n    return linkTarget{i:02d}(path);\n  }}\n}}\n" for i in M ) )
w( "ovl", "checks.cpp", "".join( f"static int tally_{i:02d}( int a ) {{ return a; }}\nstatic int tally_{i:02d}( int a, int b ) {{ return a + b; }}\n" for i in N )
   + "\n".join( f"int integration_check_{i:02d}( int x ) {{\n    return tally_{i:02d}( x, x );\n}}\n" for i in N ) )
w( "ovl1", "checks.cpp", "".join( f"static int tally_{i:02d}( int a, int b ) {{ return a + b; }}\n" for i in N )
   + "\n".join( f"int integration_check_{i:02d}( int x ) {{\n    return tally_{i:02d}( x, x );\n}}\n" for i in N ) )
# K-DECL-IDENT (CodeRabbit on #555): a header declaration folds into a definition only when the definition's file answers the header
for ext, d in ( ( "c", "k" ), ( "cc", "kx" ) ):
    hdr = "#pragma once\n" + "".join( f"int find_home_{i:02d}(void);\n" for i in M )
    defs = lambda inc: inc + "".join( f"int find_home_{i:02d}(void) {{ return {i}; }}\n" for i in M )
    w( d + "1", "api.h", hdr ); w( d + "1", "impl." + ext, defs( "" ) )
    w( d + "2", "api.h", hdr ); w( d + "2", "impl." + ext, defs( '#include "api.h"\n' ) )
    w( d + "3", "api.h", hdr ); w( d + "3", "all.h", '#pragma once\n#include "api.h"\n' ); w( d + "3", "impl." + ext, defs( '#include "all.h"\n' ) )
    w( d + "4", "api.h", hdr ); w( d + "4", "api." + ext, defs( "" ) )
    w( d + "5/include", "api.h", hdr ); w( d + "5/src", "impl." + ext, defs( '#include "include/api.h"\n' ) )
    # CR 4497112013: the source file only repeats the prototypes (it includes the header): no implementation to fold into, the header keeps its lead
    w( d + "6", "api.h", hdr ); w( d + "6", "impl." + ext, '#include "api.h"\n' + "".join( f"int find_home_{i:02d}(void);\n" for i in M ) )
# CR 4497111991: a path stem is recognised for the uppercase C++ spelling `.C` as well (api.h and api.C: same stem, no include)
w( "kx7", "api.h", "#pragma once\n" + "".join( f"int find_home_{i:02d}(void);\n" for i in M ) )
w( "kx7", "api.C", "".join( f"int find_home_{i:02d}(void) {{ return {i}; }}\n" for i in M ) )
PY

run(){ local d="$1"; shift; ( cd "$TMP/$d" || exit 1; "$BIN" "$TMP/$d" --no-cache "$@" 2>/dev/null </dev/null ); }
# check.py ANSWER LANG BLOCKLESS_ANSWER: one line per arm, "PASS|FAIL id text"
cat > "$TMP/check.py" <<'PY'
import re, sys, xml.dom.minidom as M
path, lang, offpath = sys.argv[1], sys.argv[2], sys.argv[3]
s = open( path, encoding = "utf8" ).read().rstrip( "\n" ); off = open( offpath, encoding = "utf8" ).read().rstrip( "\n" ) if offpath != "-" else ""
def say( good, arm, text ): print( ( "PASS" if good else "FAIL" ), "(%s) %s: %s" % ( arm, lang, text ) )
m = re.search( r'(<!-- (?:ripwire for )?syms:.*?-->)(<syms [^>]*>.*?</syms>)(?=</ctx>\s*$)', s, re.S )
if not m:
    say( False, "a1", "no <syms> block last before </ctx>: %r" % s[ -300: ] ); sys.exit( 0 )
legend, blk = m.group( 1 ), m.group( 2 )
openTag = re.match( r'<syms [^>]*>', blk ).group( 0 )
rows = [ dict( re.findall( r'(\w+)="([^"]*)"', r ) ) for r in re.findall( r'<y [^>]*/>', blk ) ]
byName = [ r for r in rows if r.get( "by" ) == "name" ]; byCallee = [ r for r in rows if r.get( "by" ) == "callee" ]
total = re.search( r' name_total="(\d+)"', openTag )
say( len( byName ) == 3 and total is not None and int( total.group( 1 ) ) > 3
     and all( re.search( r':\d+$', r["p"] ) for r in byName ), "a1", "by=name rows %d, open %s" % ( len( byName ), openTag ) )
# (c1) the constants (3 rows per rule, 6 files, 8 head rows) are in the legend: no count of what the rows show, no *_capped, head= only below 8
tagAttrs = dict( re.findall( r'(\w+)="([^"]*)"', openTag ) )
say( not ( set( tagAttrs ) - { "files", "files_total", "head", "name_total", "callee_total" } ) and tagAttrs.get( "head", "0" ) != "8"
     and ( "files" not in tagAttrs or int( tagAttrs["files"] ) < 6 ), "c1", "open tag prints only what differs from the legend's constants: %s" % openTag )
direct = [ r for r in byCallee if "via" not in r and re.search( r'helper', r["n"], re.I ) ]
member = [ r for r in byCallee if re.search( r'warm', r["n"], re.I ) ]
named  = [ r for r in member if r.get( "via" ) == "name" ]
wantVia = lang in ( "py", "ts" )
if lang != "pyns":
  say( len( byCallee ) >= 1 and len( direct ) >= 1 and ( not wantVia or len( named ) >= 1 ),
     "a2", "callee rows %s" % [ ( r["n"], r.get( "via" ) ) for r in byCallee ] )
sep = { "cpp": "::", "rs": "::", "rb": "#" }.get( lang, "." )
if lang == "pyns":
    ns = [ r for r in byCallee if r["n"] == "namesake_target" ]
    say( len( ns ) == 1 and ns[0].get( "via" ) == "name", "ns1", "a namesake's call is hedged via=name: %s" % ns )
elif lang != "mcp":
  say( len( member ) >= 1 and all( re.fullmatch( r'Store\d\d' + re.escape( sep ) + r'\w+', r["n"] ) for r in member ), "q1", "member rows %s" % [ r["n"] for r in member ] )
rest = s[ : m.start() ] + s[ m.end(): ]
words = set( re.findall( r'[#$@~]?\w+[?!]?', rest ) ) | set( re.findall( r'\w+', rest ) )
def leafOf( n ):
    leaf = re.split( r'::|\.', n )[ -1 ]
    return leaf.split( "#" )[ -1 ] if "#" in leaf[ 1: ] else leaf      # Ruby Scope#name; a leading # is TypeScript's private mark
leaked = [ r["n"] for r in rows if leafOf( r["n"] ) in words ]
say( not leaked, "d1", "rows named elsewhere in the answer: %s" % leaked )
mask = lambda t: re.sub( r' at="[^"]*"| est_tokens="\d+"', '', t )
heads = set( re.findall( r'<d [^>]*?\bp="([^"]*)"', off ) )
def cutRow( t ):
    if t.group( 1 ) not in heads:
        return t.group( 0 )
    kept = [ y for y in t.group( 2 ).split( "," ) if y not in { r["n"] for r in rows } | { leafOf( r["n"] ) for r in rows } ]
    return '<t p="%s"%s' % ( t.group( 1 ), ' sym="%s"' % ",".join( kept ) if kept else "" )
off = re.sub( r'<t p="([^"]*)" sym="([^"]*)"', cutRow, off )   # R-DEDUP: the block's names leave the head files' tail rows
say( mask( rest ) == mask( off ) and len( off ) > 0, "e1", "answer minus block vs RIPWIRE_NO_FILE_SYMS=1 (%d vs %d bytes)" % ( len( rest ), len( off ) ) )
try:
    M.parseString( s ); wf = True
except Exception as exc:
    wf = False
say( wf and "--" not in legend[ 4 : -3 ] and s.count( "<syms " ) == 1, "w1", "well formed, legend without a double hyphen, one block" )
say( not any( "test" in r for r in rows ), "t1", "no row of a source file says test=" )
attrs = sorted( { a for t in re.findall( r'<(?:syms|y) [^>]*>', blk ) for a in re.findall( r'(\w+)="', t ) } - { "p", "n" } )
undef = [ a for a in attrs if not re.search( r'(?<![\w:.-])' + a + r'\s*=', legend ) ]
say( attrs and not undef, "l1", "the legend defines every block attribute %s (undefined: %s)" % ( attrs, undef ) )
PY

for lang in py ts go cpp rs rb pyns; do
  run "$lang" "--for=$TASK" >"$TMP/$lang.xml"; rc=$?
  RIPWIRE_NO_FILE_SYMS=1 run "$lang" "--for=$TASK" >"$TMP/$lang.off.xml"; rc2=$?
  if [ "$rc" != 0 ] || [ "$rc2" != 0 ] || [ ! -s "$TMP/$lang.xml" ]; then no "($lang) the --for run failed (rc=$rc/$rc2) or printed nothing"; continue; fi
  python3 "$TMP/check.py" "$TMP/$lang.xml" "$lang" "$TMP/$lang.off.xml" >"$TMP/$lang.res" 2>&1 || { no "($lang) check.py crashed: $( head -c 300 "$TMP/$lang.res" )"; continue; }
  [ -s "$TMP/$lang.res" ] || { no "($lang) check.py printed nothing"; continue; }
  while IFS= read -r line; do
    case "$line" in PASS*) ok "${line#PASS }";; *) no "${line#FAIL }";; esac
  done <"$TMP/$lang.res"
done

# ── (m1)(m2)(m3)(s1)(s2)(c1): the dedupe reads every emitted byte; sigil spellings; decl+def; test mark; constants stay in the legend
cat > "$TMP/lead.py" <<'PY'
import re, sys
path, mode = sys.argv[1], sys.argv[2]
s = open( path, encoding = "utf8" ).read()
def say( good, arm, text ): print( ( "PASS" if good else "FAIL" ), "(%s) %s: %s" % ( arm, mode, text ) )
m = re.search( r'<!-- syms:.*?--><syms ([^>]*)>(.*?)</syms>', s, re.S )
rows = [ dict( re.findall( r'(\w+)="([^"]*)"', r ) ) for r in re.findall( r'<y [^>]*/>', m.group( 2 ) ) ] if m else []
tag = dict( re.findall( r'(\w+)="([^"]*)"', m.group( 1 ) ) ) if m else {}
rest = s[ : m.start() ] + s[ m.end(): ] if m else s
words = set( re.findall( r'[#$@~]?\w+[?!]?', rest ) ) | set( re.findall( r'\w+', rest ) )
def leafOf( n ):
    leaf = re.split( r'::|\.', n )[ -1 ]
    return leaf.split( "#" )[ -1 ] if "#" in leaf[ 1: ] else leaf
leaked = [ r["n"] for r in rows if leafOf( r["n"] ) in words ]
if mode.startswith( "lit-off" ):          # the twin: with the literal block off, the names the block carries are offered
    say( m is not None and any( leafOf( r["n"] ) in ( "_is_valid_animation_level", "_get_animation_level", "#isValidAnimationLevel", "animation_level_valid?" ) for r in rows ), "m1", "twin: %s" % [ r["n"] for r in rows ] )
elif mode in ( "lit", "tslit", "rblit" ):
    say( "<lit " in s and not leaked, "m1", "the literal-anchor block fires and none of its names is offered again (rows %s, leaked %s)" % ( [ r["n"] for r in rows ], leaked ) )
elif mode in ( "ts", "js", "rb" ):
    shown = { "ts": "#addRoute", "js": "$addRoute", "rb": "add_route?" }[ mode ] in s.split( "<syms" )[ 0 ]
    sig = [ r["n"] for r in rows if { "ts": leafOf( r["n"] ).startswith( "#" ), "js": leafOf( r["n"] ).startswith( "$" ), "rb": leafOf( r["n"] ).endswith( "?" ) }[ mode ] ]
    say( shown and m is not None and not leaked and len( sig ) >= 1, "m2", "the shown sigil-spelled member is not offered again (leaked %s); an unshown one is (%s)" % ( leaked, sig[ :2 ] ) )
elif mode == "graph" or mode == "callers":
    twin = "flowchart" in s if mode == "graph" else "<graph_verb" in s
    say( twin and m is not None and not leaked, "m3", "the %s block fired and no row repeats a name it carries (leaked %s)" % ( mode, leaked ) )
elif mode == "cppdecl":
    ns = [ r["n"] for r in rows ]
    say( len( rows ) == 3 and len( set( ns ) ) == 3 and all( r["p"].startswith( "ver.cc:" ) for r in rows ) and int( tag.get( "name_total", "0" ) ) == 40,
         "s2", "a declaration and its definition are one row, the definition's: %s total %s" % ( [ ( r["n"], r["p"] ) for r in rows ], tag.get( "name_total" ) ) )
elif mode == "chdr":
    ns = [ r["n"] for r in rows ]
    say( len( rows ) >= 2 and len( set( ns ) ) == len( ns ) and all( r["p"].startswith( "api.c:" ) for r in rows ),
         "s2", "a C declaration and its definition are one row, the definition's: %s" % [ ( r["n"], r["p"] ) for r in rows ] )
elif mode[ :2 ] in ( "k1", "k2", "k3", "k4", "k5", "k6", "k7" ):
    arm = mode[ :2 ]
    hdr = [ r for r in rows if re.match( r'(include/)?api\.h:', r["p"] ) ]
    defs = [ r for r in rows if re.match( r'(src/)?(impl|api)\.(c|cc|C):', r["p"] ) ]
    if arm in ( "k1", "k6" ):          # the same-name PAIR is in the answer (a header row and a source row of one name), not merely a row of each file
        say( m is not None and bool( { r["n"] for r in hdr } & { r["n"] for r in defs } ), arm, "the header lead is kept beside the source file's same-name row (%s): %s" % ( "an unrelated definition" if arm == "k1" else "a prototype only", [ ( r["n"], r["p"] ) for r in rows ] ) )
    else:
        say( m is not None and not hdr and len( defs ) >= 1 and len( { r["n"] for r in rows } ) == len( rows ), arm, "the declaration folds into its definition's row: %s" % [ ( r["n"], r["p"] ) for r in rows ] )
elif mode == "pyt":
    say( len( rows ) >= 1 and all( r.get( "test" ) == "1" for r in rows ), "s1", "every row of a test file says test=\"1\": %s" % rows )
elif mode == "tabp":
    say( m is not None and len( rows ) >= 1 and all( r["p"].startswith( "a&#9;b.py:" ) for r in rows ), "p1", "the tab-named file's symbols are offered, p= as the answer spells it: %s" % [ r["p"] for r in rows ][ :3 ] )
elif mode == "tspriv":
    cal = [ r for r in rows if r.get( "by" ) == "callee" and r["n"].startswith( "linkTarget" ) ]
    say( len( cal ) >= 1, "t1", "a shown Router.#priv head row credits its callees: %s" % [ r["n"] for r in rows ] )
elif mode == "ovl":
    cal = [ r for r in rows if r.get( "by" ) == "callee" and r["n"].startswith( "tally_" ) ]
    say( len( cal ) >= 1 and all( r.get( "via" ) == "name" for r in cal ), "o1", "overloads: the kept row was not the one the call reaches, so it is hedged: %s" % [ ( r["n"], r["p"], r.get( "via" ) ) for r in cal ] )
elif mode == "ovl1":
    cal = [ r for r in rows if r.get( "by" ) == "callee" and r["n"].startswith( "tally_" ) ]
    say( len( cal ) >= 1 and all( "via" not in r for r in cal ), "o2", "one definition, a plain call: no hedge: %s" % [ ( r["n"], r.get( "via" ) ) for r in cal ] )
elif mode == "wide":
    say( m is not None and "files" not in tag and "head" not in tag and int( tag.get( "files_total", "0" ) ) > 6, "c1", "six files and eight head rows are the legend's constants; files_total= names the cut: %s" % tag )
PY
fxrun(){ local mode="$1" d="$2" tsk="$3"; shift 3; run "$d" "--for=$tsk" "$@" >"$TMP/fx.$mode.xml" 2>/dev/null; python3 "$TMP/lead.py" "$TMP/fx.$mode.xml" "$mode" >"$TMP/fx.$mode.res" 2>&1 || { no "($mode) lead.py crashed: $( head -c 300 "$TMP/fx.$mode.res" )"; return; }
  [ -s "$TMP/fx.$mode.res" ] || { no "($mode) lead.py printed nothing"; return; }
  while IFS= read -r line; do case "$line" in PASS*) ok "${line#PASS }";; *) no "${line#FAIL }";; esac; done <"$TMP/fx.$mode.res"; }
fxrun lit lit TEXTUAL_ANIMATIONS
RIPWIRE_NO_LITERAL_ANCHOR=1 fxrun lit-off lit TEXTUAL_ANIMATIONS
fxrun tslit tslit TEXTUAL_ANIMATIONS
RIPWIRE_NO_LITERAL_ANCHOR=1 fxrun lit-off-ts tslit TEXTUAL_ANIMATIONS
fxrun rblit rblit TEXTUAL_ANIMATIONS
RIPWIRE_NO_LITERAL_ANCHOR=1 fxrun lit-off-rb rblit TEXTUAL_ANIMATIONS
fxrun ts tssig 'how does the router add a route'
fxrun js jssig 'how does the router add a route'
fxrun rb rbsig 'how does the router add a route'
fxrun graph py 'why does the integration check fail' --with-graph
fxrun callers py 'callers of _helper_05 integration check'
fxrun cppdecl cppdecl 'parse the version and check the edge wanted'
fxrun chdr chdr 'find home 07 and 08'
fxrun k1-c k1 'find home 39 and 40'
fxrun k2-c k2 'find home 39 and 40'
fxrun k3-c k3 'find home 39 and 40'
fxrun k4-c k4 'find home 39 and 40'
fxrun k5-c k5 'find home 39 and 40'
fxrun k6-c k6 'find home 39 and 40'
fxrun k1-cpp kx1 'find home 39 and 40'
fxrun k2-cpp kx2 'find home 39 and 40'
fxrun k3-cpp kx3 'find home 39 and 40'
fxrun k4-cpp kx4 'find home 39 and 40'
fxrun k5-cpp kx5 'find home 39 and 40'
fxrun k6-cpp kx6 'find home 39 and 40'
fxrun k7-cpp kx7 'find home 39 and 40'
fxrun pyt pyt 'why does the integration check fail'
fxrun wide wide 'route table'
if [ -f "$TMP/tabp/$( printf 'a\tb.py' )" ]; then fxrun tabp tabp "$TASK"; else echo "  SKIP  (p1) this file system cannot hold a tab in a file name"; fi
fxrun tspriv tspriv 'how does the router add a route'
fxrun ovl ovl "$TASK"
fxrun ovl1 ovl1 "$TASK"

# (h2) the held block's next= keeps the origin call's ranking flags
RIPWIRE_DEV=1 run py "--for=$TASK" --token-budget=4000 --no-route --anchor --pack-top-n=12 >"$TMP/h2.xml"; rc=$?
if [ "$rc" = 0 ] && grep -q "<syms held=\"budget\" next=\"--for=&apos;$TASK&apos; --anchor --no-route --pack-top-n=12\"/></ctx>\$" "$TMP/h2.xml"; then ok "(h2) a held block's next= carries --anchor --no-route --pack-top-n=12"; else no "(h2) rc=$rc: $( grep -o '<syms held.*' "$TMP/h2.xml" | head -c 300 )"; fi
run py "--for=$TASK" --max-tokens=2000 --no-route >"$TMP/h3.xml"; rc=$?
if [ "$rc" = 0 ] && grep -q "<syms held=\"budget\" next=\"--for=&apos;$TASK&apos; --no-route\"/></ctx>\$" "$TMP/h3.xml"; then ok "(h2) --max-tokens: next= carries --no-route"; else no "(h2) max-tokens rc=$rc: $( grep -o '<syms held.*' "$TMP/h3.xml" | head -c 300 )"; fi

# (c2) a buffer that fails to flush: a real short write (RLIMIT_FSIZE with SIGXFSZ ignored; stdout is a pipe so only the capture file is limited)
run py "--for=$TASK" >"$TMP/c2.full.xml"
bash -c 'trap "" XFSZ; ulimit -f 4 2>/dev/null || exit 99; cd "$1" || exit 98; shift; exec "$@"' x "$TMP/py" "$BIN" "$TMP/py" --no-cache "--for=$TASK" </dev/null 2>"$TMP/c2.err" | cat >"$TMP/c2.xml"; rc=${PIPESTATUS[0]}
if [ "$rc" = 99 ] || { [ "$rc" = 0 ] && [ -s "$TMP/c2.full.xml" ] && [ "$( wc -c <"$TMP/c2.xml" )" -ge "$( wc -c <"$TMP/c2.full.xml" )" ]; }; then
  echo "  SKIP  (c2) this platform does not enforce a file-size limit on the capture buffer (rc=$rc)"
elif [ "$rc" = 1 ] && grep -aq "buffer failed to flush or read back whole" "$TMP/c2.err" && grep -aq '<syms held="uncaptured"/></ctx>$' "$TMP/c2.xml" && ! grep -aq '<y ' "$TMP/c2.xml"; then
  ok "(c2) a buffer that fails to flush is not the whole answer: stderr says so, exit 1, <syms held=\"uncaptured\"/>, no rows"
else
  no "(c2) rc=$rc stderr: $( head -c 200 "$TMP/c2.err" ) tail: $( tail -c 160 "$TMP/c2.xml" )"
fi
if grep -aq '<y ' "$TMP/c2.full.xml"; then ok "(c2) twin: without the limit the same run prints rows"; else no "(c2) twin: the unlimited run printed no rows"; fi

# (u1) a run that cannot buffer its bytes: RIPWIRE_FAULT_CHARGE_BUFFER=1 (the est_tokens family's switch, non-NDEBUG flavour only)
( cd "$TMP/py" && RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" "$TMP/py" --no-cache "--for=$TASK" >"$TMP/u1.xml" 2>"$TMP/u1.err" </dev/null ); rc=$?
if grep -aq 'could not buffer the answer' "$TMP/u1.err"; then
  if [ "$rc" = 0 ] && grep -aq '<syms held="uncaptured"/></ctx>$' "$TMP/u1.xml" && ! grep -aq '<y ' "$TMP/u1.xml" && grep -aq 'held="uncaptured"' "$TMP/u1.xml" \
     && grep -aqE '<!-- ripwire for syms: held="budget"[^>]*held="uncaptured"[^>]*-->' "$TMP/u1.xml"; then ok "(u1) an unbufferable run prints <syms held=\"uncaptured\"/> with its legend, no rows, exit 0"; else no "(u1) rc=$rc: $( grep -ao '<syms.*' "$TMP/u1.xml" | head -c 300 )"; fi
elif ! grep -aq 'open_memstream failed' "$TMP/u1.err"; then
  echo "  SKIP  (u1) the fault switch is absent on this flavour (NDEBUG): the uncaptured stub is not exercised"
else
  no "(u1) the fault switch was live but the capture did not report: $( head -c 300 "$TMP/u1.err" )"
fi

run one "--for=$TASK" >"$TMP/one.xml"; rc=$?
if [ "$rc" = 0 ] && grep -q '</ctx>$' "$TMP/one.xml" && ! grep -q '<syms' "$TMP/one.xml"; then ok "(n1) present-only: a one-function tree prints no block"; else no "(n1) rc=$rc: $( grep -o '<syms.*' "$TMP/one.xml" | head -c 300 )"; fi

run py "--for=$TASK" --token-budget=4000 >"$TMP/h1.xml"; rc=$?
if [ "$rc" = 0 ] && grep -q "<syms held=\"budget\" next=\"--for=&apos;$TASK&apos;\"/></ctx>\$" "$TMP/h1.xml" && ! grep -q '<y ' "$TMP/h1.xml" \
   && grep -qE '<!-- ripwire for syms: held="budget":[^>]* next= [^>]*--><syms held=' "$TMP/h1.xml"; then ok "(h1) a token budget holds the block: held=\"budget\" next=, no rows, its own legend defines held= and next="; else no "(h1) rc=$rc: $( grep -o '<syms.*' "$TMP/h1.xml" | head -c 300 )"; fi
run py "--for=$TASK" --json >"$TMP/j1.json"; rc=$?
if [ "$rc" = 0 ] && [ -s "$TMP/j1.json" ] && ! grep -q 'syms' "$TMP/j1.json"; then ok "(j1) --json carries no block"; else no "(j1) rc=$rc json: $( grep -o '.\{40\}syms.\{80\}' "$TMP/j1.json" | head -c 300 )"; fi

printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$TMP/py" "$TASK" \
  | ( cd "$TMP/py" || exit 1; "$BIN" --mcp 2>/dev/null ) | python3 -c '
import json, sys
for line in sys.stdin:
    d = json.loads( line )
    if d.get( "id" ) == 1:
        print( d["result"]["content"][0]["text"], end="" )
' >"$TMP/x1.xml"
if [ -s "$TMP/x1.xml" ] && python3 "$TMP/check.py" "$TMP/x1.xml" mcp - >"$TMP/x1.res" 2>&1 && grep -q '^PASS (d1)' "$TMP/x1.res" && grep -q '^PASS (a1)' "$TMP/x1.res" && grep -q '^PASS (w1)' "$TMP/x1.res" && grep -q '^PASS (l1)' "$TMP/x1.res"
then ok "(x1) MCP for: the block, its by=name cap, its dedupe against the MCP answer's own words, and the full legend defines its attributes"; else no "(x1) MCP: $( grep -v '^PASS' "$TMP/x1.res" | head -c 400 )"; fi

# ── VR-BINDER-ROW (b1..b5): the binder of a head row's slot bind, a <y by="bind"> row ──────────────────────────────────────────
mkdir -p "$TMP/bind/src" "$TMP/bindpy"
cat >"$TMP/bind/src/vis.ts" <<'TS'
export function isNodeShown(node: number): boolean {
    return node > 0 && node < 100;
}
export function plainHelper(x: number): number {
    return x * 2 + 1;
}
export function cappedPredicate(x: number): boolean {
    return x % 3 === 0;
}
export function helperPlainScale(x: number): number {
    return x * 4;
}
TS
cat >"$TMP/bind/src/table.ts" <<'TS'
import { isNodeShown, cappedPredicate } from "./vis";
export function buildTable() {
    return { isNodeShown, count: 3 };
}
export function wireOne() {
    return { check: cappedPredicate };
}
export function wireTwo() {
    return { check: cappedPredicate };
}
export function wireThree() {
    return { check: cappedPredicate };
}
TS
cat >"$TMP/bind/src/use.ts" <<'TS'
import { plainHelper } from "./vis";
export function runIt(n: number): number {
    return plainHelper(n) + 1;
}
TS
# (b6) CR 4507663235: a binder an earlier head counted past its cap still prints under a later head with a free slot
mkdir -p "$TMP/bind2/src"
cat >"$TMP/bind2/src/vis.ts" <<'TS'
export function alphaPred(x: number): boolean {
    return x % 3 === 0;
}
export function betaPred(x: number): boolean {
    return x % 5 === 0;
}
TS
cat >"$TMP/bind2/src/table.ts" <<'TS'
import { alphaPred, betaPred } from "./vis";
export function wireAlphaOne() {
    return { check: alphaPred };
}
export function wireAlphaTwo() {
    return { check: alphaPred };
}
export function wireBoth() {
    return { first: alphaPred, second: betaPred };
}
TS
cat >"$TMP/bindpy/handlers.py" <<'PYF'
def on_resize_event(ev):
    return ev + 1
PYF
cat >"$TMP/bindpy/registry.py" <<'PYF'
from handlers import on_resize_event

def make_dispatch():
    return {"resize": on_resize_event}
PYF
# bindrows ANSWER: line 1 the by="bind" rows as name@into@file;… line 2 bind_total= or -, line 3 clause|noclause, line 4 defs|nodefs
bindrows(){ python3 - "$1" <<'PYF'
import re, sys
s = open( sys.argv[1], encoding = "utf8" ).read()
m = re.search( r'(<!-- (?:ripwire for )?syms:.*?-->)(<syms[^>]*>.*?</syms>)', s, re.S )
legend, blk = ( m.group( 1 ), m.group( 2 ) ) if m else ( "", "" )
rows = [ dict( re.findall( r'(\w+)="([^"]*)"', r ) ) for r in re.findall( r'<y [^>]*/>', blk ) ]
total = re.search( r'<syms[^>]* bind_total="(\d+)"', blk )
print( ";".join( "%s@%s@%s" % ( r["n"], r.get( "into", "" ), r["p"].split( ":" )[0] ) for r in rows if r.get( "by" ) == "bind" ) )
print( total.group( 1 ) if total else "-" )
print( "clause" if 'by="bind"' in legend or "by=bind" in legend else "noclause" )
print( "defs" if all( re.search( r'(?<![\w:.-])' + a + r'\s*=', legend ) for a in ( "by", "into", "bind_total" ) ) else "nodefs" )
PYF
}
run bind "--for=isNodeShown" >"$TMP/b1.xml"; rc=$?
b1="$( bindrows "$TMP/b1.xml" )"
if [ "$rc" = 0 ] && [ "$( sed -n 1p <<<"$b1" )" = "buildTable@(return).isNodeShown@src/table.ts" ] && [ "$( sed -n 2p <<<"$b1" )" = "-" ]; then ok "(b1) the factory that returns { isNodeShown } is a by=\"bind\" row with into=, from another file"; else no "(b1) rc=$rc rows: $( tr '\n' '|' <<<"$b1" ) $( grep -o '<syms.*' "$TMP/b1.xml" | head -c 400 )"; fi
run bind "--for=plainHelper" >"$TMP/b2.xml"; rc=$?
b2="$( bindrows "$TMP/b2.xml" )"
if [ "$rc" = 0 ] && grep -q '<y [^>]*n="helperPlainScale" by="name"' "$TMP/b2.xml" && [ -z "$( sed -n 1p <<<"$b2" )" ] && [ "$( sed -n 3p <<<"$b2" )" = "noclause" ]; then ok "(b2) a head nobody binds: the block prints (a by=\"name\" row) with no by=\"bind\" row and no bind clause in the legend"; else no "(b2) rc=$rc: $( tr '\n' '|' <<<"$b2" ) $( grep -o '<syms.*' "$TMP/b2.xml" | head -c 400 )"; fi
run bind "--for=cappedPredicate" >"$TMP/b3.xml"; rc=$?
b3="$( bindrows "$TMP/b3.xml" )"
if [ "$rc" = 0 ] && [ "$( sed -n 1p <<<"$b3" | tr ';' '\n' | grep -c '@(return).check@src/table.ts$' )" = 2 ] && [ "$( sed -n 2p <<<"$b3" )" = 3 ] \
   && grep -q 'two per head' "$TMP/b3.xml"; then ok "(b3) three binders of one head: two rows, bind_total=\"3\", the cap in the legend"; else no "(b3) rc=$rc: $( tr '\n' '|' <<<"$b3" ) $( grep -o '<syms.*' "$TMP/b3.xml" | head -c 400 )"; fi
run bindpy "--for=on_resize_event" >"$TMP/b4.xml"; rc=$?
b4="$( bindrows "$TMP/b4.xml" )"
if [ "$rc" = 0 ] && sed -n 1p <<<"$b4" | grep -q '^make_dispatch@[^@]*resize[^@]*@registry.py$'; then ok "(b4) Python: the function returning {\"resize\": on_resize_event} is a by=\"bind\" row"; else no "(b4) rc=$rc: $( tr '\n' '|' <<<"$b4" ) $( grep -o '<syms.*' "$TMP/b4.xml" | head -c 400 )"; fi
run bind2 "--for=alphaPred betaPred" >"$TMP/b6.xml"; rc=$?
b6="$( bindrows "$TMP/b6.xml" )"
if [ "$rc" = 0 ] && sed -n 1p <<<"$b6" | tr ';' '\n' | grep -q '^wireBoth@(return).second@src/table.ts$' && [ "$( sed -n 1p <<<"$b6" | tr ';' '\n' | grep -c '^wireBoth@' )" = 1 ]; then ok "(b6) a binder alphaPred counted past its cap prints once under betaPred's free slot"; else no "(b6) rc=$rc: $( tr '\n' '|' <<<"$b6" ) $( grep -o '<syms.*' "$TMP/b6.xml" | head -c 400 )"; fi
RIPWIRE_NO_BIND_ROWS=1 run bind "--for=isNodeShown" >"$TMP/b5.off.xml"
if [ "$( sed -n 3,4p <<<"$b1" | tr '\n' ' ' )" = "clause defs " ] && ! grep -q 'by="bind"' "$TMP/b5.off.xml"; then ok "(b5) the legend before the block defines by=\"bind\" into= bind_total=; RIPWIRE_NO_BIND_ROWS=1 drops the rows"; else no "(b5) legend: $( sed -n 3,4p <<<"$b1" | tr '\n' ' ' ) off: $( grep -o '<syms.*' "$TMP/b5.off.xml" | head -c 300 )"; fi

# CONST-INIT-CALLEE fixtures (by="init"): a TypeScript decorator-style value behind a spelled import, a Python module-level object
mkdir -p "$TMP/init/packages/core/src/util" "$TMP/init/packages/router/src" "$TMP/initpy/conf"
cat >"$TMP/init/packages/core/index.ts" <<'FIX'
export * from './src/core';
FIX
cat >"$TMP/init/packages/core/package.json" <<'FIX'
{ "name": "@acme/core", "main": "index.ts" }
FIX
cat >"$TMP/init/packages/core/src/core.ts" <<'FIX'
export * from './widgets';
FIX
cat >"$TMP/init/packages/core/src/split.ts" <<'FIX'
export function makeSplit(name: string): any {
  return name + '!';
}
FIX
cat >"$TMP/init/packages/core/src/widgets.ts" <<'FIX'
import { forgeValue } from './util/factory';
import { makeSplit } from './split';

/** The Widget marker's options. */
export interface Widget {
  selector?: string;
}

export const Widget: any = forgeValue(
  'Widget',
  (w: Widget = {}) => ({ ...w }),
);

export interface Gizmo {
  size?: number;
}

export const Gizmo: any = { size: 3 };

export const Sprocket: any = makeSplit('Sprocket');
FIX
cat >"$TMP/init/packages/core/src/util/factory.ts" <<'FIX'
export function forgeValue(name: string, props?: (x: any) => any): any {
  const fn = (...args: any[]) => ({ name, args, props });
  return fn;
}
export function makeSplit(name: string): any {
  return name;
}
FIX
cat >"$TMP/init/packages/router/src/outlet.ts" <<'FIX'
import { Widget } from '@acme/core';

@Widget({ selector: 'outlet' })
export class Outlet {}
FIX
cat >"$TMP/initpy/app.py" <<'FIX'
from conf import config


def start():
    return config.debug
FIX
cat >"$TMP/initpy/conf/__init__.py" <<'FIX'
class LazyConfig:
    """Loads the config on first attribute access."""

    def __getattr__(self, name):
        return name


def make_registry():
    return {}


config = LazyConfig()
registry = make_registry()
FIX

# initrows ANSWER: line 1 the by="init" rows as n@of@at@file;… line 2 clause|noclause, line 3 defs|nodefs
initrows(){ python3 - "$1" <<'PYF'
import re, sys
s = open( sys.argv[1], encoding = "utf8" ).read()
m = re.search( r'(<!-- (?:ripwire for )?syms:.*?-->)(<syms[^>]*>.*?</syms>)', s, re.S )
legend, blk = ( m.group( 1 ), m.group( 2 ) ) if m else ( "", "" )
rows = [ dict( re.findall( r'(\w+)="([^"]*)"', r ) ) for r in re.findall( r'<y [^>]*/>', blk ) ]
print( ";".join( "%s@%s@%s@%s" % ( r["n"], r.get( "of", "" ), r.get( "at", "" ), r["p"] ) for r in rows if r.get( "by" ) == "init" ) )
print( "clause" if 'by="init"' in legend or "by=init" in legend else "noclause" )
print( "defs" if all( re.search( r'(?<![\w:.-])' + a + r'\s*=', legend ) for a in ( "by", "of", "at" ) ) else "nodefs" )
PYF
}
run init "--for=where the Widget marker from @acme/core is defined" >"$TMP/i1.xml"; rc=$?
i1="$( initrows "$TMP/i1.xml" )"
if [ "$rc" = 0 ] && grep -q '<def n="Widget" p="packages/core/src/widgets.ts"' "$TMP/i1.xml" \
   && [ "$( sed -n 1p <<<"$i1" )" = "forgeValue@Widget@packages/core/src/widgets.ts:9@packages/core/src/util/factory.ts:1" ]; then
    ok "(i1) TypeScript: the re-export walk's def row Widget (an interface; its value is \`export const Widget = forgeValue(…)\`) gets by=\"init\" forgeValue"
else no "(i1) rc=$rc rows: $( tr '\n' '|' <<<"$i1" ) $( grep -o '<syms.*' "$TMP/i1.xml" | head -c 400 )"; fi
run initpy "--for=registry" >"$TMP/i2.xml"; rc=$?
i2="$( initrows "$TMP/i2.xml" )"
if [ "$rc" = 0 ] && [ "$( sed -n 1p <<<"$i2" )" = "make_registry@registry@conf/__init__.py:13@conf/__init__.py:8" ]; then
    ok "(i2) Python: the module-level \`registry = make_registry()\` head row gets by=\"init\" make_registry"
else no "(i2) rc=$rc rows: $( tr '\n' '|' <<<"$i2" ) $( grep -o '<syms.*' "$TMP/i2.xml" | head -c 400 )"; fi
# negatives, each with its premise counted: a literal initialiser (Gizmo, its def row printed), a callee a shown row stands on
# (LazyConfig is the r=1 row beside `config = LazyConfig()`)
run init "--for=where the Gizmo marker from @acme/core is defined" >"$TMP/i3.xml"; i3rc=$?
run initpy "--for=where is the config object made" >"$TMP/i3p.xml"; i3prc=$?
seen=0
grep -q '<def n="Gizmo"' "$TMP/i3.xml" && seen=$(( seen + 1 ))
grep -q '<d [^>]*n="config"' "$TMP/i3p.xml" && grep -q '<d [^>]*n="LazyConfig"' "$TMP/i3p.xml" && seen=$(( seen + 1 ))
if [ "$seen" = 2 ] && [ "$i3rc$i3prc" = 00 ] && ! grep -q 'of="Gizmo"' "$TMP/i3.xml" && ! grep -q 'by="init"[^>]*of="config"' "$TMP/i3p.xml"; then
    ok "(i3) no by=\"init\" row for an object-literal value or for a callee already shown (saw $seen of 2 premises)"
else no "(i3) rc=$i3rc/$i3prc, saw $seen of 2 premises, or a row printed: $( grep -o '<syms.*' "$TMP/i3.xml" "$TMP/i3p.xml" | head -c 500 )"; fi
RIPWIRE_NO_INIT_ROWS=1 run init "--for=where the Widget marker from @acme/core is defined" >"$TMP/i4.off.xml"; i4orc=$?
run init "--for=where the Widget marker from @acme/core is defined" --legend=full >"$TMP/i4f.xml"; i4frc=$?
i4f="$( initrows "$TMP/i4f.xml" )"
if [ "$( sed -n 2,3p <<<"$i1" | tr '\n' ' ' )" = "clause defs " ] && [ "$( sed -n 2,3p <<<"$i4f" | tr '\n' ' ' )" = "clause defs " ] && [ "$i4orc$i4frc" = 00 ] \
   && ! grep -q 'by="init"' "$TMP/i4.off.xml" && ! grep -q 'by=init\|by=\\"init' "$TMP/i4.off.xml" && [ "$( sed -n 2p <<<"$( initrows "$TMP/i3p.xml" )" )" = "noclause" ]; then
    ok "(i4) both legends define by=\"init\" of= at= beside a row, a block without one carries no clause; RIPWIRE_NO_INIT_ROWS=1 drops rows and clause"
else no "(i4) rc=$i4orc/$i4frc compact: $( sed -n 2,3p <<<"$i1" | tr '\n' ' ' ) full: $( sed -n 2,3p <<<"$i4f" | tr '\n' ' ' ) off: $( grep -o '<syms.*' "$TMP/i4.off.xml" | head -c 300 )"; fi

# (i5) FORFILESYMS-INIT-WINDOW-LEGEND (CodeRabbit on #646): the initialiser's `(` sits past the 200-byte window (a dotted callee head
# generated here, 230 bytes): no row, but <syms init_cut="1"> and the init clause stating the window, in both legends
mkdir -p "$TMP/initcut"
LONGHEAD="$( python3 -c 'print( ".".join( [ "segment%02d" % i for i in range( 23 ) ] ) )' )"
printf 'def make_big():\n    return {}\n\n\nbig_registry = %s.make_big()\n' "$LONGHEAD" >"$TMP/initcut/app.py"
run initcut "--for=big_registry" >"$TMP/i5.xml"; i5rc=$?
run initcut "--for=big_registry" --legend=full >"$TMP/i5f.xml"; i5frc=$?
i5pre="$( python3 -c 'import sys; t=open(sys.argv[1]).read(); a=t.index("= ")+2; print( len( t[a:t.index("(", a)] ) )' "$TMP/initcut/app.py" )"
if [ "$i5rc$i5frc" = 00 ] && [ "${i5pre:-0}" -gt 200 ] && grep -q '<syms[^>]* init_cut="1"' "$TMP/i5.xml" && grep -q '<syms[^>]* init_cut="1"' "$TMP/i5f.xml" \
   && grep -q 'within 200 bytes' "$TMP/i5.xml" && grep -q 'within 200 bytes' "$TMP/i5f.xml" \
   && [ "$( sed -n 3p <<<"$( initrows "$TMP/i5.xml" )" )" = defs ] && [ "$( sed -n 3p <<<"$( initrows "$TMP/i5f.xml" )" )" = defs ]; then
    ok "(i5) a call head past the 200-byte window ($i5pre bytes before its \`(\`) is disclosed: init_cut=\"1\", both legends state the window"
else no "(i5) rc=$i5rc/$i5frc head=$i5pre bytes: $( grep -o '<syms.*' "$TMP/i5.xml" | head -c 400 )"; fi
# (i5n) the window's control: the same declaration with a short head is an ordinary by="init" row and no init_cut
mkdir -p "$TMP/initshort"
printf 'def make_big():\n    return {}\n\n\nbig_registry = make_big()\n' >"$TMP/initshort/app.py"
run initshort "--for=big_registry" >"$TMP/i5n.xml"; i5nrc=$?
if [ "$i5nrc" = 0 ] && [ "$( sed -n 1p <<<"$( initrows "$TMP/i5n.xml" )" )" = "make_big@big_registry@app.py:5@app.py:1" ] && ! grep -q '<syms[^>]* init_cut=' "$TMP/i5n.xml"; then
    ok "(i5n) the short twin prints its by=\"init\" row and no init_cut"
else no "(i5n) rc=$i5nrc rows: $( initrows "$TMP/i5n.xml" | tr '\n' '|' ) $( grep -o '<syms.*' "$TMP/i5n.xml" | head -c 300 )"; fi

# (i6) FORFILESYMS-COMMENT-DECL (CodeRabbit on #646): a declaration twin inside a string or a block comment EARLIER in the file is no
# declaration: the row comes from the real one (no file-scope call stands in the twin). Python: a module docstring; TypeScript: /* */.
mkdir -p "$TMP/initdoc/conf" "$TMP/initcmt/src"
cat >"$TMP/initdoc/conf/__init__.py" <<'FIX'
"""Settings.

registry = old_registry()
was the shape before the factory moved; see make_registry below.
"""


def old_registry():
    return []


def make_registry():
    return {}


registry = make_registry()
FIX
cat >"$TMP/initcmt/src/marks.ts" <<'FIX'
import { forgeMark } from './forge';

/*
export const Banner: any = legacyMark(
  'Banner',
);
*/

export interface Banner {
  title?: string;
}

export const Banner: any = forgeMark('Banner');
FIX
cat >"$TMP/initcmt/src/forge.ts" <<'FIX'
export function forgeMark(name: string): any {
  return { name };
}
export function legacyMark(name: string): any {
  return name;
}
FIX
run initdoc "--for=registry" >"$TMP/i6.xml"; i6rc=$?
run initcmt "--for=Banner" >"$TMP/i6t.xml"; i6trc=$?
i6seen=0
grep -q '^registry = old_registry()' "$TMP/initdoc/conf/__init__.py" && i6seen=$(( i6seen + 1 ))
grep -q '^export const Banner: any = legacyMark(' "$TMP/initcmt/src/marks.ts" && i6seen=$(( i6seen + 1 ))
if [ "$i6rc$i6trc" = 00 ] && [ "$i6seen" = 2 ] && [ "$( sed -n 1p <<<"$( initrows "$TMP/i6.xml" )" )" = "make_registry@registry@conf/__init__.py:16@conf/__init__.py:12" ] \
   && [ "$( sed -n 1p <<<"$( initrows "$TMP/i6t.xml" )" )" = "forgeMark@Banner@src/marks.ts:13@src/forge.ts:1" ]; then
    ok "(i6) a docstring or block-comment twin earlier in the file is skipped: the real declaration's callee prints (saw $i6seen of 2 twins)"
else no "(i6) rc=$i6rc/$i6trc twins $i6seen of 2: py $( initrows "$TMP/i6.xml" | head -1 ) ts $( initrows "$TMP/i6t.xml" | head -1 ) $( grep -o '<syms.*' "$TMP/i6.xml" "$TMP/i6t.xml" | head -c 500 )"; fi

# (i7) FORFILESYMS-INIT-REF-RESOLVE (CodeRabbit on #646): the declaration's call `ext.makeThing(…)` is external, and ANOTHER module-scope
# call `makeThing(…)` supplies the module scope's only edge named makeThing: that edge is not the declaration's call, so no row
# (fails closed); (i7n) the same file with the declaration's call written like the other one (`makeThing(…)` twice: angular's many
# `X = makeDecorator(…)`) keeps its row
mkdir -p "$TMP/initref/src" "$TMP/initrefok/src"
cat >"$TMP/initref/src/real.ts" <<'FIX'
export function makeThing(name: string): any {
  return { name };
}
FIX
cp "$TMP/initref/src/real.ts" "$TMP/initrefok/src/real.ts"
cat >"$TMP/initref/src/use.ts" <<'FIX'
import { Thing } from './things';

export function useThing(): any {
  return Thing;
}
FIX
cp "$TMP/initref/src/use.ts" "$TMP/initrefok/src/use.ts"
cat >"$TMP/initref/src/things.ts" <<'FIX'
import { makeThing } from './real';
import * as ext from 'ext-lib';

export interface Thing {
  size?: number;
}

export const Thing: any = ext.makeThing('Thing');

export const helper: any = makeThing('helper');
FIX
cat >"$TMP/initrefok/src/things.ts" <<'FIX'
import { makeThing } from './real';

export interface Thing {
  size?: number;
}

export const Thing: any = makeThing('Thing');

export const helper: any = makeThing('helper');
FIX
run initref "--for=Thing" >"$TMP/i7.xml"; i7rc=$?
run initrefok "--for=Thing" >"$TMP/i7n.xml"; i7nrc=$?
i7pre=0
grep -q "^export const Thing: any = ext.makeThing('Thing');" "$TMP/initref/src/things.ts" && grep -q "^export const helper: any = makeThing('helper');" "$TMP/initref/src/things.ts" && i7pre=1
if [ "$i7rc$i7nrc" = 00 ] && [ "$i7pre" = 1 ] && ! grep -q 'by="init"' "$TMP/i7.xml" \
   && [ "$( sed -n 1p <<<"$( initrows "$TMP/i7n.xml" )" )" = "makeThing@Thing@src/things.ts:7@src/real.ts:1" ]; then
    ok "(i7) an external initialiser call is never credited with another module-scope call's edge (no row); written alike, both calls share it and the row stays"
else no "(i7) rc=$i7rc/$i7nrc premise=$i7pre: wrong $( initrows "$TMP/i7.xml" | head -1 ) ok $( initrows "$TMP/i7n.xml" | head -1 )"; fi

[ "$fail" = 0 ] && echo "forfilesymscheck: PASS" || echo "forfilesymscheck: FAIL"
exit "$fail"
