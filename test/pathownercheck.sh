#!/usr/bin/env bash
# pathownercheck.sh — a --path / path_between hop row names a member by its owner: n="Owner.name" (src/defattrib.h pathHopOwners).
#
# THE DEFECT. Every hop row printed the bare name: <s t="method" n="scan" .../>. On a path through two methods that share a
# name (A::go -> B::go) the rows read n="go" n="go", and a reader who wants to open a hop had to re-resolve the bare name
# against every same-named definition the corpus holds.
#
# THE CONTRACT. A hop whose definition scope names a TYPE or MODULE definition the index holds in the same language (a
# class/struct/interface/named type, or a module: Rust mod, Ruby module) prints n="Owner<sep>name", Owner the stored scope and
# <sep> the language's (QUALNAME-1: `::` C/C++/Rust, `#` Ruby — a `def self.` singleton too, a disclosed floor — `.` elsewhere) —
# a spelling the shared selector resolves (--callers=Owner::name). A free function, a member of a scope the
# index holds no such definition for (a C++ namespace), and a type hop itself stay bare. The legend clause rides only when a
# row carries an owner, so an answer without one is byte-identical. MCP path_between prints the same rows.
#
# ARMS
#   (A) C++: topCpp -> Matcher::run -> outer::inner::Scanner::scan -> inner::leaf — Matcher::run, Scanner::scan; leaf (namespace) bare.
#   (B) Python: entry -> Reader.read -> Writer.write -> helper; the module functions stay bare.
#   (C) Rust: rs_entry -> Engine::start -> Engine::ignite -> m::modfn (a `mod` is an indexed module owner).
#   (D) Ruby: Task#run -> Exec#execute; a module method: Util#fmt (singleton, `#` by the disclosed floor) -> Inner#go.
#   (E) two owners, one name, one path: callA -> A.go -> B.go -> twoOwners — the two go rows are distinguishable.
#   (F) negative: a path of free functions only (C) prints bare rows and no owner legend clause.
#   (G) negative: a C++ function in namespace Reader beside a Python class Reader stays bare (owner must be the hop's language).
#   (I) negative: a hop that IS a type (a constructor call edge into class Box) is not printed as Box.Box.
#   (L) the --legend=full clause rides exactly when a row carries an owner; the answer parses as XML (xmllint when present).
#   (X) clickable: every printed Owner.name, pasted into --callers, resolves (rc=0, defs>=1).
#   (M) MCP path_between serves the same <s> rows as the CLI on A-E.
#   (H) Go: Matcher.Loop -> Matcher.scan -> goLeaf — Go receiver scopes (go-scope, #403) are on main since train 29, so the
#       arm no longer SKIPs: a Go method with no sc= is a FAIL (train 30 re-check).
#
# Usage: test/pathownercheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "pathownercheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

# ── fixtures ────────────────────────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$TMP/cpp" "$TMP/py" "$TMP/rs" "$TMP/rb" "$TMP/two" "$TMP/c" "$TMP/mix" "$TMP/ty" "$TMP/go"
cat > "$TMP/cpp/a.cpp" <<'EOF'
namespace outer { namespace inner {
struct Scanner { int scan(); int step(); };
int leaf();
int Scanner::step() { return 1; }
int Scanner::scan() { return step() + leaf(); }
int leaf() { return 2; }
} }
class Matcher { public: int run() { outer::inner::Scanner s; return s.scan(); } };
int topCpp() { Matcher m; return m.run(); }
EOF
cat > "$TMP/py/b.py" <<'EOF'
class Reader:
    def read(self):
        return Writer().write()
class Writer:
    def write(self):
        return helper()
def helper():
    return 1
def entry():
    return Reader().read()
EOF
cat > "$TMP/rs/d.rs" <<'EOF'
mod m { pub fn modfn() -> i32 { 1 } }
struct Engine;
impl Engine { fn start(&self) -> i32 { self.ignite() } fn ignite(&self) -> i32 { m::modfn() } }
fn rs_entry() -> i32 { let e = Engine; e.start() }
EOF
cat > "$TMP/rb/g.rb" <<'EOF'
class Task
  def run
    Exec.new.execute
  end
end
class Exec
  def execute
    1
  end
end
module Util
  def self.fmt
    Inner.new.go
  end
end
class Inner
  def go
    2
  end
end
EOF
cat > "$TMP/two/h.cpp" <<'EOF'
struct A { int go(); };
struct B { int go(); };
int twoOwners() { return 3; }
int B::go() { return twoOwners(); }
int A::go() { B b; return b.go(); }
int callA() { A a; return a.go(); }
EOF
cat > "$TMP/c/m.c" <<'EOF'
static int c_leaf( void ) { return 1; }
static int c_mid( void ) { return c_leaf(); }
int c_top( void ) { return c_mid(); }
EOF
cat > "$TMP/mix/n.cpp" <<'EOF'
namespace Reader { int nsRead() { return 1; } }
int mixTop() { return Reader::nsRead(); }
EOF
cat > "$TMP/mix/r.py" <<'EOF'
class Reader:
    def other(self):
        return 1
EOF
cat > "$TMP/ty/t.py" <<'EOF'
class Box:
    def __init__(self):
        self.v = 1
def make():
    return Box()
EOF
cat > "$TMP/go/e.go" <<'EOF'
package p
type Matcher struct{}
func (m *Matcher) Loop() int { return m.scan() }
func (m *Matcher) scan() int { return goLeaf() }
func goLeaf() int { return 1 }
EOF

# runp DIR FROM,TO — run --path (rc into $prc, the answer into $TMP/last.xml); hops — that answer's hop n= values, space-separated
runp(){ "$BIN" "$1" --no-cache "--path=$2" > "$TMP/last.xml" 2> "$TMP/last.err"; prc=$?; }
hops(){
    python3 - "$TMP/last.xml" <<'PY2'
import re, sys
t = open( sys.argv[1], encoding = "utf-8", errors = "replace" ).read()
print( " ".join( re.findall( r'<s t="[^"]*" n="([^"]*)"', t ) ) )
PY2
}
expect(){   # LABEL DIR FROM,TO EXPECTED-ROWS
    runp "$2" "$3"
    local got; got="$( hops )"
    if [ "$prc" -ne 0 ]; then no "$1: --path=$3 rc=$prc ($( head -c 200 "$TMP/last.err" ))"; return; fi
    if [ "$got" = "$4" ]; then ok "$1: $got"; else no "$1: rows '$got' (want '$4')"; fi
}

echo "(A)-(E) owners on member hops"
expect "(A) C++ class members, namespace function bare" "$TMP/cpp" "topCpp,leaf" "topCpp Matcher::run Scanner::scan leaf"
expect "(B) Python methods, module functions bare"      "$TMP/py"  "entry,helper" "entry Reader.read Writer.write helper"
expect "(C) Rust impl methods + mod member"             "$TMP/rs"  "rs_entry,modfn" "rs_entry Engine::start Engine::ignite m::modfn"
expect "(D1) Ruby class methods"                        "$TMP/rb"  "run,execute" "Task#run Exec#execute"
expect "(D2) Ruby module method"                        "$TMP/rb"  "fmt,go" "Util#fmt Inner#go"
expect "(E) two owners of one name in one path"         "$TMP/two" "callA,twoOwners" "callA A::go B::go twoOwners"

echo "(F)/(G)/(I) bare where no owner"
expect "(F) free functions only" "$TMP/c" "c_top,c_leaf" "c_top c_mid c_leaf"
if grep -q 'Owner.name' "$TMP/last.xml"; then no "(F) owner legend clause rides on an answer with no owner row"; else ok "(F) no owner legend clause"; fi
expect "(G) C++ namespace named like a Python class stays bare" "$TMP/mix" "mixTop,nsRead" "mixTop nsRead"
runp "$TMP/ty" "make,Box"; got="$( hops )"
case "$got" in
    *Box.Box*) no "(I) a type hop printed as its own owner: '$got'" ;;
    "make Box") ok "(I) type hop bare: $got" ;;
    *) no "(I) premise: make -> Box path rows '$got' (rc=$prc; want 'make Box')" ;;
esac

echo "(L) legend clause rides with an owner row; XML parses"
# the clause is full-dialect prose; the compact default keeps its one n= reading (compactlegend.h keys terms on attribute
# NAMES and this adds none), so compact owner answers and owner-free answers alike carry no extra legend bytes
"$BIN" "$TMP/cpp" --no-cache --legend=full --path=topCpp,leaf > "$TMP/last.xml" 2> "$TMP/last.err"; prc=$?
if [ "$prc" -eq 0 ] && grep -q 'n=Owner.name' "$TMP/last.xml"; then ok "(L) owner clause present on a --legend=full owner answer"; else no "(L) no 'n=Owner.name' clause on the --legend=full C++ owner answer (rc=$prc)"; fi
"$BIN" "$TMP/c" --no-cache --legend=full --path=c_top,c_leaf > "$TMP/free.xml" 2> "$TMP/free.err"; frc=$?
# the absence is read only off a run that succeeded and printed its path rows (an empty or failed run has no clause either)
if [ "$frc" -ne 0 ] || ! grep -q '<s ' "$TMP/free.xml"; then no "(L) premise: the --legend=full owner-free answer rc=$frc or no <s> rows ($( head -c 200 "$TMP/free.err" ))"
elif grep -q 'n=Owner.name' "$TMP/free.xml"; then no "(L) owner clause rides a --legend=full answer with no owner row"
else ok "(L) no owner clause on a --legend=full owner-free answer"; fi
if command -v xmllint > /dev/null 2>&1; then
    if xmllint --noout "$TMP/last.xml" 2> "$TMP/xl.err"; then ok "(L) xmllint parses the owner answer"; else no "(L) xmllint: $( head -c 300 "$TMP/xl.err" )"; fi
else
    echo "  SKIP  (L) xmllint not installed — XML parse not checked"
fi

echo "(X) every printed Owner.name resolves as a selector"
xbad=0; xn=0
for spec in "cpp topCpp,leaf" "py entry,helper" "rs rs_entry,modfn" "rb run,execute" "rb fmt,go" "two callA,twoOwners"; do
    set -- $spec
    runp "$TMP/$1" "$2"
    for n in $( hops ); do
        case "$n" in *.*|*::*|*'#'*) ;; *) continue ;; esac   # QUALNAME-1: every language separator (., ::, #)
        xn=$(( xn + 1 ))
        out="$( "$BIN" "$TMP/$1" --no-cache "--callers=$n" 2>&1 )"; xrc=$?
        d="$( printf '%s' "$out" | grep -o '<callers [^>]* defs="[0-9]*"' | grep -o 'defs="[0-9]*"' | grep -o '[0-9]*' )"
        if [ "$xrc" -ne 0 ] || [ -z "$d" ] || [ "$d" -lt 1 ]; then no "(X) --callers=$n in $1: rc=$xrc defs='$d'"; xbad=1; fi
    done
done
if [ "$xn" -eq 0 ]; then no "(X) premise: no Owner.name row printed to paste"; elif [ "$xbad" -eq 0 ]; then ok "(X) $xn Owner.name rows each resolve via --callers"; fi

echo "(M) MCP path_between serves the CLI's hop rows"
python3 - "$BIN" "$TMP" <<'PY'
import json, re, subprocess, sys
binp, tmp = sys.argv[1], sys.argv[2]
cases = [ ( "cpp", "topCpp", "leaf" ), ( "py", "entry", "helper" ), ( "rs", "rs_entry", "modfn" ), ( "rb", "fmt", "go" ), ( "two", "callA", "twoOwners" ) ]
reqs = [ { "jsonrpc": "2.0", "id": 0, "method": "initialize", "params": { "protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": { "name": "g", "version": "1" } } } ]
for i, ( d, a, b ) in enumerate( cases ):
    reqs.append( { "jsonrpc": "2.0", "id": i + 1, "method": "tools/call", "params": { "name": "path_between", "arguments": { "path": tmp + "/" + d, "from": a, "to": b } } } )
p = subprocess.run( [ binp, "--mcp", "--mcp-legend=inline" ], input = "".join( json.dumps( r ) + "\n" for r in reqs ), capture_output = True, text = True, timeout = 120 )
resp = {}
for line in p.stdout.splitlines():
    try:
        o = json.loads( line )
    except ValueError:
        continue
    if isinstance( o.get( "id" ), int ) and o[ "id" ] > 0:
        resp[ o[ "id" ] ] = "".join( c.get( "text", "" ) for c in o.get( "result", {} ).get( "content", [] ) )
bad = 0
for i, ( d, a, b ) in enumerate( cases ):
    mcp = resp.get( i + 1, "" )
    cli = subprocess.run( [ binp, tmp + "/" + d, "--no-cache", "--path=%s,%s" % ( a, b ) ], capture_output = True, text = True ).stdout
    mr, cr = re.findall( r'<s [^>]*/>', mcp ), re.findall( r'<s [^>]*/>', cli )
    if not cr:
        print( "  %s: CLI premise: no <s> rows" % d ); bad = 1
    elif mr != cr:
        print( "  %s: MCP rows %r vs CLI %r" % ( d, mr, cr ) ); bad = 1
    if ( "n=Owner.name" in mcp ) != ( "n=Owner.name" in cli ):
        print( "  %s: owner legend clause differs MCP vs CLI" % d ); bad = 1
sys.exit( bad )
PY
mrc=$?
if [ "$mrc" -eq 0 ]; then ok "(M) path_between rows + owner clause equal the CLI's on A-E"; else no "(M) MCP path_between disagrees with the CLI (rc=$mrc, details above)"; fi

echo "(H) Go receiver owners"
if "$BIN" "$TMP/go" --no-cache --for="scan Loop" --signatures-only 2>/dev/null | grep -q 'n="Matcher.scan"'; then   # QUALNAME-1: a <d> member row folds sc= into n=
    expect "(H) Go methods by receiver" "$TMP/go" "Loop,goLeaf" "Matcher.Loop Matcher.scan goLeaf"
else
    no "(H) Go methods carry no sc= on this binary (go-scope #403 is on main): the receiver owners cannot print"
fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "FAIL"; fi
exit "$fail"
