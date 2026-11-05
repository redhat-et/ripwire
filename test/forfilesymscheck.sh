#!/usr/bin/env bash
# forfilesymscheck.sh — K-WRONGSYM (src/forfilesyms.h): a --for answer names, in <syms> before </ctx>, symbols of its first shown files
# that it does not name anywhere: by="name" (the name shares a task word) and by="callee" (a head <d> row calls it; the graph edge's
# hedge rides the row). The answer before the block is unchanged.
#
# ARMS (each language: Python, TypeScript, Go, C++, Rust, Ruby; one generated shape — 80 `integration_check_NN` functions, each calling a
# helper directly and a member of its own Store type through a parameter, so the head's later rows have callees no hop names)
#   (a1) by="name" rows: name="3" and name_capped="1" name_total= the candidates (the cap is disclosed), each p=file:line and no body
#   (a2) by="callee" rows: callee= rows shown; a direct call is evidence-bound (no via=), and in Python and TypeScript the
#        parameter's member call is bound by name alone and says via="name"
#   (q1) a member row is Scope.name in its language's spelling (`.` Python/TS/Go, `::` C++/Rust, `#` Ruby)
#   (ns1) Python: namesakes of two head rows (same names, a test file) are the only callers of a shown-file function: by="callee" via="name"
#   (d1) dedupe: no <y> row's name is a word anywhere else in the answer
#   (e1) the answer with RIPWIRE_NO_FILE_SYMS=1 equals the answer minus the block (legend comment + element), byte for byte
#   (w1) well formed XML, the block's legend holds no double hyphen, the block is last before </ctx>, one per answer
#   (l1) every attribute the block prints (<syms> and each <y>, the core p= n= aside) is defined `name=` in the legend comment right
#        before it (the legendcoveragecheck predicate): the compact legend on the CLI rows, the full one on x1 (MCP); (h1) the held stub's
#        own legend defines held= and next=
#   (n1) present-only: a one-function tree has no candidate and prints no block (twin: a1 fires on the same binary)
#   (h1) --token-budget holds the block: <syms held="budget" next=...>, no rows; (j1) --json carries no block
#   (x1) MCP `for`: the block (one renderer), read off the MCP answer's own bytes: a1, d1 and w1 hold on it
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
w( "one", "solo.py", "def integration_check(x):\n    return x\n" )
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
total = re.search( r' name_capped="1" name_total="(\d+)"', openTag )
say( len( byName ) == 3 and ' name="3"' in openTag and total is not None and int( total.group( 1 ) ) > 3
     and all( re.search( r':\d+$', r["p"] ) for r in byName ), "a1", "by=name rows %d, open %s" % ( len( byName ), openTag ) )
direct = [ r for r in byCallee if "via" not in r and re.search( r'helper', r["n"], re.I ) ]
member = [ r for r in byCallee if re.search( r'warm', r["n"], re.I ) ]
named  = [ r for r in member if r.get( "via" ) == "name" ]
wantVia = lang in ( "py", "ts" )
if lang != "pyns":
  say( len( byCallee ) >= 1 and ( ' callee="%d"' % len( byCallee ) ) in openTag and len( direct ) >= 1 and ( not wantVia or len( named ) >= 1 ),
     "a2", "callee rows %s" % [ ( r["n"], r.get( "via" ) ) for r in byCallee ] )
sep = { "cpp": "::", "rs": "::", "rb": "#" }.get( lang, "." )
if lang == "pyns":
    ns = [ r for r in byCallee if r["n"] == "namesake_target" ]
    say( len( ns ) == 1 and ns[0].get( "via" ) == "name", "ns1", "a namesake's call is hedged via=name: %s" % ns )
elif lang != "mcp":
  say( len( member ) >= 1 and all( re.fullmatch( r'Store\d\d' + re.escape( sep ) + r'\w+', r["n"] ) for r in member ), "q1", "member rows %s" % [ r["n"] for r in member ] )
rest = s[ : m.start() ] + s[ m.end(): ]
words = set( re.findall( r'\w+', rest ) )
leaked = [ r["n"] for r in rows if re.split( r'::|\.|#', r["n"] )[ -1 ] in words ]
say( not leaked, "d1", "rows named elsewhere in the answer: %s" % leaked )
mask = lambda t: re.sub( r' at="[^"]*"| est_tokens="\d+"', '', t )
say( mask( rest ) == mask( off ) and len( off ) > 0, "e1", "answer minus block vs RIPWIRE_NO_FILE_SYMS=1 (%d vs %d bytes)" % ( len( rest ), len( off ) ) )
try:
    M.parseString( s ); wf = True
except Exception as exc:
    wf = False
say( wf and "--" not in legend[ 4 : -3 ] and s.count( "<syms " ) == 1, "w1", "well formed, legend without a double hyphen, one block" )
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

[ "$fail" = 0 ] && echo "forfilesymscheck: PASS" || echo "forfilesymscheck: FAIL"
exit "$fail"
