#!/usr/bin/env bash
# subjectanchorcheck.sh — SUBJECT-ANCHOR: a symbol named exactly in a descriptive --for subject is the anchor (src/subjectanchor.h).
#   A1-A5  per language, a plain word beside an exact symbol stops being an anchor: the route prints dropped:, <callers> is back
#   B      a route DECLINED for a word routes on the symbol
#   C      a prose tail keeps the conceptual answer, byte for byte, and <callers by="subject"> rides on top
#   N1-N8  near misses: namesake flood, symbol only in tests, question, graph form, join, plain-only subject, too many plain words, no word to drop
#   D      dotted beats bare; a polyglot name splits and carries no row until a qualifier places it
#   (confidence arms: commit 2)
# Usage: bash test/subjectanchorcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/subjectanchorcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN - build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "subjectanchorcheck: BIN=$BIN"
ask(){ ( cd "$1" && "$BIN" "$1" --no-cache "--for=$2" 2>/dev/null ) </dev/null; }
route(){ printf '%s' "$1" | python3 -c 'import re,sys; b=sys.stdin.read(); m=re.search(r"route=\"([^\"]*)\"",b); print(m.group(1) if m else "@@NONE")'; }
has(){ case "$1" in *"$2"*) ok "$3";; *) no "$3 (missing: $2)";; esac; }
hasnt(){ case "$1" in *"$2"*) no "$3 (present: $2)";; *) ok "$3";; esac; }
blk(){ printf '%s' "$1" | python3 -c 'import re,sys; m=re.search(r"<callers .*?</callers>",sys.stdin.read(),re.S); print(m.group(0) if m else "")'; }

# ── Python: new() and parameter() really are symbols, once each: every plausibility bound passes them ──
PY="$TMP/py"; mkdir -p "$PY/app"
cat > "$PY/app/setup.py" <<'X'
def prepare_setup_platform(hass, name):
    return name

def first_caller(hass):
    return prepare_setup_platform(hass, "a")

def second_caller(hass):
    return prepare_setup_platform(hass, "b")
X
cat > "$PY/app/words.py" <<'X'
def new(x):
    return x

def parameter(x):
    return x
X
mkdir -p "$PY/tests"
cat > "$PY/tests/test_only.py" <<'X'
def helper_only_tests(x):
    return x

def test_it():
    return helper_only_tests(1)
X
A="$( ask "$PY" 'prepare_setup_platform new parameter' )"; R="$( route "$A" )"
has   "$R" 'name-exact(prepare_setup_platform)' "A1 py: the exact symbol is the anchor"
has   "$R" 'dropped: new(1-defs) parameter(1-defs)' "A1 py: dropped words visible, each with its definitions"
hasnt "$R" 'new(app' "A1 py: new is not an anchor"
has   "$A" '<callers of="prepare_setup_platform"' "A1 py: <callers> no longer lost to the words"
has   "$A" 'first_caller' "A1 py: caller row printed"
BARE="$( ask "$PY" 'prepare_setup_platform' )"
python3 - "$A" "$BARE" <<'X' && ok "A1 py: <callers> and <bodies> equal the bare subject's" || no "A1 py: differs from the bare subject"
import re,sys
a,b=sys.argv[1:3]
f=lambda s:(re.findall(r'<callers .*?</callers>',s,re.S),re.findall(r'<bodies.*?</bodies>',s,re.S))
sys.exit(0 if f(a)==f(b) and f(a)[0] else 1)
X
# ── C++: `new` over the definitions bound declines at base, the qualified symbol anchors here ──
CX="$TMP/cx"; mkdir -p "$CX/src"
cat > "$CX/src/registry.cpp" <<'X'
struct RegistryMap { int insert( int a ); };
int RegistryMap::insert( int a ) { return a; }
int callOne( RegistryMap& r ) { return r.insert( 1 ); }
int fresh( int a ) { return a; }
X
for i in 1 2 3 4 5 6; do printf 'struct S%s { int parameter( int a ) { return a; } };\n' "$i" > "$CX/src/s$i.cpp"; done
A="$( ask "$CX" 'RegistryMap::insert fresh parameter' )"; R="$( route "$A" )"
has   "$R" 'name-exact(RegistryMap::insert)' "B cpp: a qualified symbol is not declined for a word"
has   "$R" 'parameter(6-defs)' "B cpp: the refused word's definitions are disclosed"
hasnt "$R" 'declined' "B cpp: no decline"
# ── TypeScript, Rust: same class, unqualified ──
TS="$TMP/ts"; mkdir -p "$TS/src"
cat > "$TS/src/a.ts" <<'X'
export function transformNodes(n: number) { return n; }
export function useIt() { return transformNodes(1); }
export function argument(n: number) { return n; }
export function fresh(n: number) { return n; }
X
A="$( ask "$TS" 'transformNodes fresh argument' )"
has "$( route "$A" )" 'dropped: fresh(1-defs) argument(1-defs)' "A2 ts: dropped clause"
has "$A" '<callers of="transformNodes"' "A2 ts: callers"
A="$( ask "$TS" 'transformNodes zznope argument' )"
hasnt "$( route "$A" )" 'dropped:' "A2 ts: a word naming nothing leaves a conceptual route, nothing to drop from it"
has "$A" '<callers by="subject" of="transformNodes"' "A2 ts: and the callers ride by subject"
RS="$TMP/rs"; mkdir -p "$RS/src"
cat > "$RS/src/lib.rs" <<'X'
pub fn do_the_work(a: i32) -> i32 { a }
pub fn default() -> i32 { do_the_work(1) }
X
A="$( ask "$RS" 'do_the_work default' )"; R="$( route "$A" )"
has "$R" 'name-exact(do_the_work)' "A3 rust: two-word subject anchors the symbol"
has "$R" 'dropped: default(1-defs)' "A3 rust: default dropped though it is a real function"
hasnt "$R" 'default(src' "A3 rust: default is not an anchor"
# ── C: Go, a prose tail with words that name nothing: the conceptual answer stands, callers ride on top ──
GO="$TMP/go"; mkdir -p "$GO/proxy" "$GO/other"
cat > "$GO/proxy/proxier.go" <<'X'
package proxy
func NewProxier(a int) int { return a }
func createProxier() int { return NewProxier(1) }
X
cat > "$GO/other/proxier.go" <<'X'
package other
func NewProxier(a int) int { return a }
func otherCreate() int { return NewProxier(2) }
X
A="$( ask "$GO" 'proxy.NewProxier gains sturdy zzknob' )"
has "$( route "$A" )" 'subtoken+body' "C go: the route stays conceptual"
has "$A" '<callers by="subject"' "C go: callers ride by subject"
has "$( blk "$A" )" 'createProxier' "D go: the dotted qualifier picks proxy's callers"
hasnt "$( blk "$A" )" 'otherCreate' "D go: not the namesake's callers"
python3 - "$A" "$( cd "$GO" && RIPWIRE_NO_CALLER_HOP=1 "$BIN" "$GO" --no-cache '--for=proxy.NewProxier gains sturdy zzknob' 2>/dev/null )" <<'X' && ok "C go: answer minus the block and its clause is byte-identical" || no "C go: the block displaced something"
import re,sys
a,b=sys.argv[1:3]
m=lambda s:re.sub(r' est_tokens="\d+"| at="[^"]*"','',s)
a=re.sub(r'<callers by="subject".*?</callers>','',a,flags=re.S)
ca=re.sub(r'<!--.*?-->','',m(a),flags=re.S); cb=re.sub(r'<!--.*?-->','',m(b),flags=re.S)
sys.exit(0 if ca==cb else 1)
X
# ── near misses: each byte-identical in route to a run with no reading ──
FL="$TMP/flood"; mkdir -p "$FL/a"
for i in 1 2 3 4 5; do printf 'def flood_name(x):\n    return x\n\ndef parameter%s(x):\n    return flood_name(x)\n' "$i" > "$FL/a/m$i.py"; done
A="$( ask "$FL" 'flood_name new parameter' )"
hasnt "$A" 'dropped:' "N1 flood: a namesake flood gets no reading"
hasnt "$A" 'by="subject"' "N1 flood: no callers lifted"
A="$( ask "$PY" 'helper_only_tests new parameter' )"
has "$( route "$A" )" 'dropped:' "N2 test-only: a word anchor still goes"
A="$( ask "$PY" 'helper_only_tests zznope sturdy' )"
hasnt "$A" 'by="subject"' "N2 test-only: a symbol only in tests lifts no callers onto a conceptual route"
A="$( ask "$PY" 'where is prepare_setup_platform new' )"
has "$( route "$A" )" 'dropped: new(1-defs)' "N3 question: a plain-word anchor goes on a question too"
A="$( ask "$PY" 'where prepare_setup_platform zznope sturdy' )"; hasnt "$A" 'by="subject"' "N3 question lead: no callers lifted"
A="$( ask "$PY" 'path from first_caller to prepare_setup_platform' )"; hasnt "$( route "$A" )" 'dropped:' "N4 graph form: no reading"
hasnt "$A" 'by="subject"' "N4 graph form: no subject callers"
A="$( ask "$PY" 'first_caller + prepare_setup_platform' )"; hasnt "$( route "$A" )" 'dropped:' "N5 join of two symbols: no reading"
hasnt "$A" 'by="subject"' "N5 join: no subject callers"
A="$( ask "$PY" 'new parameter' )"; hasnt "$( route "$A" )" 'dropped:' "N6 plain words only: no reading"
A="$( ask "$PY" 'prepare_setup_platform and the other long descriptive prose words around' )"
hasnt "$A" 'by="subject"' "N7 prose past the plain-word bound: no reading"
A="$( ask "$PY" 'prepare_setup_platform' )"; hasnt "$( route "$A" )" 'dropped:' "N8 bare symbol: nothing to drop"
# two exact symbols: both anchor, neither word survives
A="$( ask "$PY" 'first_caller second_caller new' )"; R="$( route "$A" )"
has "$R" 'first_caller(' "T two exact: first anchored"; has "$R" 'second_caller(' "T two exact: second anchored"; has "$R" 'dropped: new(1-defs)' "T two exact: word dropped"
# ── polyglot: one name in Python and TypeScript ──
PG="$TMP/poly"; mkdir -p "$PG/pyside" "$PG/tsside"
printf 'def shared_name(x):\n    return x\n\ndef py_user():\n    return shared_name(1)\n' > "$PG/pyside/mod.py"
printf 'export function shared_name(x: number) { return x; }\nexport function tsUser() { return shared_name(1); }\n' > "$PG/tsside/mod.ts"
A="$( ask "$PG" 'shared_name zzgains zzknob sturdy' )"
hasnt "$A" 'by="subject"' "D poly: two languages, one name: no row, exact or none"
A="$( ask "$PG" 'pyside.shared_name zzgains zzknob sturdy' )"
has "$( blk "$A" )" 'py_user' "D poly: a qualifier places the Python one"
hasnt "$( blk "$A" )" 'tsUser' "D poly: not the TypeScript one"
# determinism + well-formed
A1="$( ask "$PY" 'prepare_setup_platform new parameter' )"; A2="$( ask "$PY" 'prepare_setup_platform new parameter' )"
[ "$( printf '%s' "$A1" | sed -E 's/ at="[^"]*"//' )" = "$( printf '%s' "$A2" | sed -E 's/ at="[^"]*"//' )" ] && ok "determinism" || no "determinism"
printf '%s' "$A1" | xmllint --noout - 2>/dev/null && ok "xml well formed" || no "xml not well formed"
[ "$fail" = 0 ] && { echo "subjectanchorcheck: PASS"; exit 0; }
echo "subjectanchorcheck: FAIL"; exit 1
