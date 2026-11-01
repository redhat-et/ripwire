#!/usr/bin/env bash
# subjectanchorcheck.sh — SUBJECT-ANCHOR: a symbol named exactly in a descriptive --for subject is the anchor (src/subjectanchor.h).
#   A1-A5  per language, a plain word beside an exact symbol stops being an anchor: the route prints dropped:, <callers> is back
#   B      a route DECLINED for a word routes on the symbol
#   C      a prose tail keeps the conceptual answer, byte for byte, and <callers by="subject"> rides on top
#   N1-N8  near misses: namesake flood, symbol only in tests, question, graph form, join, plain-only subject, too many plain words, no word to drop
#   D      dotted beats bare; a polyglot name splits and carries no row until a qualifier places it
#   H      confidence: an anchor served from a test, doc or data file reads low; a source definition keeps it
#   F      FIX ROUND: F6 a declined route flips only where the body AND the callers print (one function, resolved anchor, body fits),
#          F2 a namesake in ANY directory keeps the map, F1 the MCP `for` verb never trades its map, F4 a plain word never vouches
#          for a spelled name, F10 an angle-bracketed owner is a name
# Usage: bash test/subjectanchorcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/subjectanchorcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN - build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
if python3 - "$A" "$BARE" <<'X'
import re,sys
a,b=sys.argv[1:3]
f=lambda s:(re.findall(r'<callers .*?</callers>',s,re.S),re.findall(r'<bodies.*?</bodies>',s,re.S))
sys.exit(0 if f(a)==f(b) and f(a)[0] else 1)
X
then ok "A1 py: <callers> and <bodies> equal the bare subject's"; else no "A1 py: differs from the bare subject"; fi
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
# a qualified spelling binds no anchor definition (anchors: X(syntax)), so no body is known to print: the declined map stands (F6/F3)
has   "$R" 'declined(parameter;6-carriers' "B cpp: a qualified symbol beside a refused word: the declined route stands and names the word"
hasnt "$R" 'dropped:' "B cpp: no flip on an unbound anchor"
has   "$( blk "$A" )" 'callOne' "B cpp: the symbol's callers ride on top of the map"
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
if python3 - "$A" "$( cd "$GO" && RIPWIRE_NO_CALLER_HOP=1 "$BIN" "$GO" --no-cache '--for=proxy.NewProxier gains sturdy zzknob' 2>/dev/null )" <<'X'
import re,sys
a,b=sys.argv[1:3]
m=lambda s:re.sub(r' est_tokens="\d+"| at="[^"]*"','',s)
a=re.sub(r'<callers by="subject".*?</callers>','',a,flags=re.S)
ca=re.sub(r'<!--.*?-->','',m(a),flags=re.S); cb=re.sub(r'<!--.*?-->','',m(b),flags=re.S)
sys.exit(0 if ca==cb else 1)
X
then ok "C go: answer minus the block and its clause is byte-identical"; else no "C go: the block displaced something"; fi
# ── near misses: each byte-identical in route to a run with no reading ──
FL="$TMP/flood"; mkdir -p "$FL/a"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do printf 'def flood_name(x):\n    return x\n' > "$FL/a/m$i.py"; done
for i in 1 2 3 4 5; do printf 'def family_name(x):\n    return x\n' > "$FL/a/f$i.py"; done
printf 'def new(x):\n    return x\n' > "$FL/a/words.py"
A="$( ask "$FL" 'flood_name new' )"
hasnt "$( route "$A" )" 'dropped:' "N1 flood: 14 namesakes prove nothing, no reading"
A="$( ask "$FL" 'family_name new' )"
has "$( route "$A" )" 'dropped: new(1-defs)' "N1 family: one definition per backend is still a name"
A="$( ask "$PY" 'helper_only_tests new parameter' )"
hasnt "$( route "$A" )" 'dropped:' "N2 test-only: the words stay (a test anchor leaves the route as it was; it reads low)"
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
printf 'def lonely_function(x):\n    return x\n' > "$PY/app/lonely.py"
A="$( ask "$PY" 'lonely_function zznope sturdy' )"; hasnt "$A" 'by="subject"' "N9 no callers: no element, never a bare total=0"
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
# ── CONFIDENCE-ANCHOR ──
conf(){ printf '%s' "$1" | python3 -c 'import re,sys; m=re.search(r"confidence=\"(\w+)\"",sys.stdin.read()); print(m.group(1) if m else "@@NONE")'; }
NOSRC='anchor has no source definition'
A="$( ask "$PY" 'helper_only_tests' )"
if [ "$( conf "$A" )" = low ]; then ok "H test-only: confidence low"; else no "H test-only: confidence $( conf "$A" )"; fi; has "$A" "$NOSRC" "H test-only: the note says why"
printf '{"json_only_key": true}\n' > "$PY/app/conf.json"
A="$( ask "$PY" 'json_only_key' )"; if [ "$( conf "$A" )" = low ]; then ok "H data file: low"; else no "H data file: $( conf "$A" )"; fi
A="$( ask "$PY" 'prepare_setup_platform' )"; if [ "$( conf "$A" )" = high ]; then ok "H source: high"; else no "H source: $( conf "$A" )"; fi; hasnt "$A" "$NOSRC" "H source: no note"
A="$( ask "$PY" 'helper_only_tests new parameter' )"; if [ "$( conf "$A" )" = low ]; then ok "H test-only beside dropped words: low"; else no "H test-only beside words: $( conf "$A" )"; fi
A="$( ask "$PY" 'zznope sturdy words' )"; hasnt "$A" "$NOSRC" "H conceptual route: no note"
printf 'def plain_src(x):\n    return x\n' > "$PY/app/some_mod.py"
A="$( ask "$PY" 'app/some_mod.py' )"; hasnt "$A" "$NOSRC" "H a source FILE subject is a source anchor"
A="$( ask "$CX" 'src/registry.cpp' )"; hasnt "$A" "$NOSRC" "H a source FILE subject, cpp"
# two exact on a route declined for a word: no ONE anchor, the map stands, the function's callers on top
for i in 1 2 3 4 5; do printf 'struct W%s { int fresh2( int a ) { return a; } };\n' "$i" > "$CX/src/w$i.cpp"; done
printf 'struct UrlThing { int a; };\nint segmentMaker( int a ) { return a; }\nint segUser() { return segmentMaker( 1 ); }\n' > "$CX/src/seg.cpp"
A="$( ask "$CX" 'parameter UrlThing segmentMaker' )"; R="$( route "$A" )"
hasnt "$R" 'dropped:' "T declined + two exact: the route is not flipped"
has "$R" 'declined' "T declined + two exact: declined stays disclosed"
has "$( blk "$A" )" 'segUser' "T declined + two exact: the function's callers ride"
# ── a CI or vendored copy first in path order must not displace the answer (LD-2 ld2-angular-09's shape, one exact symbol) ──
VN="$TMP/vend"; mkdir -p "$VN/.github/actions" "$VN/src" "$VN/vendor/lib"
printf 'function BundledThing(a) { return a; }\nfunction parameter(a) { return a; }\n' > "$VN/.github/actions/main.js"
printf 'export function BundledThing(a: number) { return a; }\nexport function bundledUser() { return BundledThing(1); }\n' > "$VN/src/thing.ts"
for i in 1 2 3 4 5; do printf 'export function parameter(a: number) { return a; }\n' > "$VN/src/p$i.ts"; done
printf 'def VendorOnlyThing(x):\n    return x\n' > "$VN/vendor/lib/copy.py"
printf 'export function fresh(a: number) { return a; }\n' > "$VN/src/fresh.ts"
A="$( ask "$VN" 'BundledThing fresh parameter' )"; R="$( route "$A" )"
has "$R" 'declined' "V .github first in path order: the declined route stands, the map is not given up"
hasnt "$R" 'dropped:' "V .github first: no flip"
has "$( blk "$A" )" 'bundledUser' "V .github first: the source def's callers ride on top, or the map stands"
A="$( ask "$VN" 'BundledThing parameter' )"; has "$( route "$A" )" 'anchor has no source definition' "V two words, already name-exact at base: no map to lose, and the CI anchor says so"
A="$( ask "$VN" 'VendorOnlyThing' )"; if [ "$( conf "$A" )" = low ]; then ok "V vendored anchor: confidence low"; else no "V vendored anchor: $( conf "$A" )"; fi
A="$( ask "$VN" 'VendorOnlyThing zznope sturdy' )"; hasnt "$A" 'by="subject"' "V vendored only: lifts nothing"

# ════ FIX ROUND (review rv-subject-anchor-v2) ════
# F6: a declined route flips to the bare symbol only when that answer serves the body AND the callers
FX="$TMP/f6"; mkdir -p "$FX/src"
printf 'export function SoloThing(a: number) { return a; }\nexport function soloUser() { return SoloThing(1); }\n' > "$FX/src/thing.ts"
for i in 1 2 3 4 5; do printf 'export function parameter(a: number) { return a; }\n' > "$FX/src/p$i.ts"; done
printf 'export function fresh(a: number) { return a; }\n' > "$FX/src/fresh.ts"
A="$( ask "$FX" 'SoloThing fresh parameter' )"; R="$( route "$A" )"
has "$R" 'name-exact(SoloThing)' "F6 one function, body fits: the declined route flips to the symbol"
has "$R" 'dropped:' "F6 flip: dropped words named"
has "$A" 'n="SoloThing"><![CDATA[function SoloThing' "F6 flip: the body is printed"
has "$( blk "$A" )" 'soloUser' "F6 flip: the callers are printed"
hasnt "$A" 'body omitted' "F6 flip: no body omitted for budget"
# F2: the class, not a path list. A namesake under ANY directory makes the name two functions: the map stays.
for d in playground e2e deps contrib benchmarks tools_x zz_other; do
    CP="$TMP/cp_$d"; mkdir -p "$CP/$d" "$CP/src"
    printf 'export function SoloThing(a: number) { return a; }\nexport function parameter(a: number) { return a; }\n' > "$CP/$d/main.ts"
    cp "$FX/src/"*.ts "$CP/src/"
    A="$( ask "$CP" 'SoloThing fresh parameter' )"; R="$( route "$A" )"
    hasnt "$R" 'dropped:' "F2 a namesake under $d/: no flip, the map is not given up"
    has "$R" 'declined' "F2 a namesake under $d/: the declined route stands and says so"
done
# F6: a body past the single-anchor allowance cannot print, so the map stays
BG="$TMP/big"; mkdir -p "$BG/src"
python3 - "$BG/src/big.ts" <<'X'
import sys
open(sys.argv[1],'w').write('export function SoloBig(a: number) {\n' + '  a = a + 1;\n'*2400 + '  return a;\n}\nexport function bigUser() { return SoloBig(1); }\n')
X
cp "$FX/src/"p*.ts "$FX/src/fresh.ts" "$BG/src/"
A="$( ask "$BG" 'SoloBig fresh parameter' )"; R="$( route "$A" )"
hasnt "$R" 'dropped:' "F6 a body over the anchor allowance: no flip"
hasnt "$A" 'body omitted (over budget): SoloBig' "F6 over-budget body: the answer never claims a body it omits"
# F3/F6: several same-named definitions (one per backend): no body can be chosen, the map stands
SY="$TMP/sync"; mkdir -p "$SY/src"
for i in 1 2 3 4; do printf 'export function syncRules(a: number) { return a + %s; }\n' "$i" > "$SY/src/b$i.ts"; done
cp "$FX/src/"p*.ts "$FX/src/fresh.ts" "$SY/src/"
A="$( ask "$SY" 'syncRules fresh parameter' )"; R="$( route "$A" )"
hasnt "$R" 'dropped:' "F3 four definitions: no flip"
hasnt "$A" 'body omitted (over budget): syncRules' "F3 four definitions: no claim of a body"
# F3: ch-08's shape: a qualified symbol whose definition is large. The flip printed an omitted body and dropped the map.
QB="$TMP/qbig"; mkdir -p "$QB/src"
python3 - "$QB/src/big.cpp" <<'X'
import sys
open(sys.argv[1],'w').write('struct BigList { int run( int a ); };\nint BigList::run( int a )\n{\n' + '    a = a + 1;\n'*1100 + '    return a;\n}\nint callBig( BigList& r ) { return r.run( 1 ); }\n')
X
for i in 1 2 3 4 5 6; do printf 'struct T%s { int parameter( int a ) { return a; } };\n' "$i" > "$QB/src/t$i.cpp"; done
printf 'int fresh( int a ) { return a; }\n' > "$QB/src/fresh.cpp"
A="$( ask "$QB" 'BigList::run fresh parameter' )"; R="$( route "$A" )"
hasnt "$R" 'dropped:' "F3 a large qualified definition: no flip"
hasnt "$A" 'body omitted (over budget)' "F3 a large qualified definition: the answer never claims a body it omits"
has "$( blk "$A" )" 'callBig' "F3 a large qualified definition: its callers ride on the map"
# F1: the MCP `for` verb serves signatures only, so it never trades a map for the symbol
mcpfor(){ ( cd "$1" && HOME="$TMP/mcphome" TMPDIR="$TMP/mcphome/" python3 - "$BIN" "$1" "$2" <<'X'
import json,subprocess,sys
b,repo,q=sys.argv[1:4]
req=json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":repo,"task":q}}})+"\n"
p=subprocess.run([b,"--mcp"],input=req.encode(),capture_output=True,timeout=300,cwd=repo)
for l in p.stdout.decode('utf8','replace').splitlines():
    try:d=json.loads(l)
    except Exception:continue
    if d.get("id")==1:
        print("".join(x.get("text","") for x in d["result"]["content"]))
X
) ; }
mkdir -p "$TMP/mcphome"
M="$( mcpfor "$FX" 'SoloThing fresh parameter' )"; R="$( route "$M" )"
hasnt "$R" 'dropped:' "F1 MCP: a declined route keeps its map"
has "$R" 'declined' "F1 MCP: the declined route is disclosed"
# F4: a plain word never vouches for a spelled name. The key lives in a data file; `read` is a function.
P4="$TMP/p4"; mkdir -p "$P4/src" "$P4/conf"
printf 'def read(x):\n    return x\n\ndef use_read():\n    return read(1)\n' > "$P4/src/reader.py"
printf 'def prepare_knob(x):\n    return x\n\ndef knob_user():\n    return prepare_knob(1)\n' > "$P4/src/knob.py"
printf 'max_concurrent_things: 100\n' > "$P4/conf/limits.yaml"
A="$( ask "$P4" 'max_concurrent_things read' )"
if [ "$( conf "$A" )" != high ]; then ok "F4 a data-file key beside a source word: not high"; else no "F4 a data-file key beside a source word reads high"; fi
has "$A" "$NOSRC" "F4 a data-file key beside a source word: the route says why"
A="$( ask "$P4" 'where is max_concurrent_things read' )"
if [ "$( conf "$A" )" != high ]; then ok "F4 question form: not high"; else no "F4 question form reads high"; fi
A="$( ask "$P4" 'prepare_knob read' )"
if [ "$( conf "$A" )" = high ]; then ok "F4 control: a source symbol beside a plain word stays high"; else no "F4 control: $( conf "$A" )"; fi
# F10: an angle-bracketed owner is a name (xmlwellformed #60: the module-scope owner was dropped as a plain word)
MS="$TMP/modscope"; mkdir -p "$MS/src"
printf 'export function setPhase(phase: string): void {\n  console.log(phase)\n}\n' > "$MS/src/lifecycle.ts"
printf "import { setPhase } from './lifecycle'\n\nexport function boot(): void {\n  setPhase('booting')\n}\n\nsetPhase('starting')\n" > "$MS/src/index.ts"
PT="$( cd "$MS" && "$BIN" "$MS" --no-cache '--pack-task=<file-scope> setPhase' 2>/dev/null )"
case "$PT" in *'capped="0" bodyless="1"'*) ok "F10 --pack-task keeps the owner in the body set (bodyless)";; *) no "F10 the module-scope owner was dropped from the body set";; esac
# determinism + well-formed
A1="$( ask "$PY" 'prepare_setup_platform new parameter' )"; A2="$( ask "$PY" 'prepare_setup_platform new parameter' )"
if [ "$( printf '%s' "$A1" | sed -E 's/ at="[^"]*"//' )" = "$( printf '%s' "$A2" | sed -E 's/ at="[^"]*"//' )" ]; then ok "determinism"; else no "determinism"; fi
if printf '%s' "$A1" | xmllint --noout - 2>/dev/null; then ok "xml well formed"; else no "xml not well formed"; fi
[ "$fail" = 0 ] && { echo "subjectanchorcheck: PASS"; exit 0; }
echo "subjectanchorcheck: FAIL"; exit 1
