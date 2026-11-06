#!/usr/bin/env bash
# subjectanchorcheck.sh — SUBJECT-ANCHOR: a symbol named exactly in a descriptive --for subject is the anchor (src/subjectanchor.h).
#   A1-A5  per language, a plain word beside an exact symbol stops being an anchor: the route prints dropped:, <callers> is back
#   B      a route DECLINED for a word routes on the symbol
#   C      a prose tail keeps the conceptual answer, byte for byte, and <callers by="subject"> rides on top
#   SC     SUBJECT-CALLERS-NATURAL: a sentence naming one function and asking what depends on it gets its callers; the route and
#          the rest are unchanged; no dependents cue (a lead, "defined", "reaches") reads as before; nor does a cue in another sense
#          (callee shape, "API calls", "used to", negated) or a sentence naming two functions
#   N1-N8  near misses: namesake flood, symbol only in tests, question, graph form, join, plain-only subject, too many plain words, no word to drop
#   D      dotted beats bare; a polyglot name splits and carries no row until a qualifier places it
#   H      confidence: an anchor served from a test, doc or data file reads low; a source definition keeps it
#   FH     FRAME-HIGH-CONFIDENCE: high needs the anchor (or its file) at the head of the ranked rows; another head reads low and route=
#          names it (CLI and MCP); a file subject and a conceptual route are unchanged
#   F      FIX ROUND: F6 a declined route flips only where the body AND the callers print (one function, resolved anchor, body fits),
#          F2 a namesake in ANY directory keeps the map, F1 the MCP `for` verb never trades its map, F4 a plain word never vouches
#          for a spelled name, F10 an angle-bracketed owner is a name
#   W/MF2  subject-fix4: a refused flip keeps the whole subject's route (no conceptual re-rank), several names never flip, a paged,
#          budgeted or candidates call never flips
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
hasnt "$( route "$A" )" 'dropped:' "N1 family: five namesakes are not one function (the gate), the map answers"
A="$( ask "$PY" 'helper_only_tests new parameter' )"
hasnt "$( route "$A" )" 'dropped:' "N2 test-only: the words stay (a test anchor leaves the route as it was; it reads low)"
A="$( ask "$PY" 'helper_only_tests zznope sturdy' )"
hasnt "$A" 'by="subject"' "N2 test-only: a symbol only in tests lifts no callers onto a conceptual route"
A="$( ask "$PY" 'where is prepare_setup_platform new' )"
has "$( route "$A" )" 'dropped: new(1-defs)' "N3 question: a plain-word anchor goes on a question too"
A="$( ask "$PY" 'where prepare_setup_platform zznope sturdy' )"; hasnt "$A" 'by="subject"' "N3 question lead: no callers lifted"
has "$A" '<ctx ' "N3 question lead: an answer printed (twin)"
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
# ── SUBJECT-CALLERS-NATURAL: a sentence that names ONE function and frames it gets that function's callers, route unchanged ──
# the task frame (question leads, "I need to", change/add/affected/breaks/depends/calls/defined) is not counted as plain words
nat(){ # $1 root $2 subject $3 caller row $4 label: callers ride, no flip, and the answer minus the block equals the no-hop answer
    local A; A="$( ask "$1" "$2" )"
    has "$A" '<callers by="subject"' "SC $4: callers ride by subject"
    has "$( blk "$A" )" "$3" "SC $4: the caller row"
    hasnt "$( route "$A" )" 'dropped:' "SC $4: the route is not flipped"
    if python3 - "$A" "$( cd "$1" && RIPWIRE_NO_CALLER_HOP=1 "$BIN" "$1" --no-cache "--for=$2" 2>/dev/null </dev/null )" <<'X'
import re,sys
a,b=sys.argv[1:3]
m=lambda s:re.sub(r' est_tokens="\d+"| at="[^"]*"','',s)
a=re.sub(r'<callers by="subject".*?</callers>','',a,flags=re.S)
ca=re.sub(r'<!--.*?-->','',m(a),flags=re.S); cb=re.sub(r'<!--.*?-->','',m(b),flags=re.S)
sys.exit(0 if ca==cb and cb.strip() else 1)
X
    then ok "SC $4: the rest of the answer is byte-identical"; else no "SC $4: the block displaced something (or no answer)"; fi
}
NAT="$TMP/nat"; mkdir -p "$NAT/app"
cat > "$NAT/app/setup.py" <<'X'
def prepare_setup_platform(hass, name):
    return name

def first_caller(hass):
    return prepare_setup_platform(hass, "a")
X
nat "$NAT" 'I want to add a new parameter to prepare_setup_platform; what is affected?' first_caller "py I want to add"
nat "$NAT" 'I need to change how prepare_setup_platform works; what depends on it?' first_caller "py I need to change"
nat "$NAT" 'Where is prepare_setup_platform defined and who calls it?' first_caller "py where defined, who calls"
nat "$NAT" 'what calls prepare_setup_platform and would need updating if its signature grew?' first_caller "py what calls"
# neighbour shapes: another language, the name not after the lead, a qualified spelling
TSN="$TMP/tsn"; mkdir -p "$TSN/src"
cat > "$TSN/src/transformer.ts" <<'X'
export function transformNodes(nodes: number[]): number[] { return nodes; }
export function runTransforms(n: number[]) { return transformNodes(n); }
X
nat "$TSN" 'adding an argument to transformNodes: which ones break?' runTransforms "ts name mid-sentence"
nat "$GO" 'If I change proxy.NewProxier, what breaks?' createProxier "go qualified, conditional frame"
nat "$GO" 'I want to pass a new parameter into proxy.NewProxier from the config; what needs to change?' createProxier "go prepositions are frame"
nat "$TSN" 'adding an argument between emit and transformNodes: which functions are in the way?' runTransforms "ts between is frame"
# no dependents cue: a sentence that does not ask who uses the function reads as before (a lead, defined, a value question)
for q in 'how does prepare_setup_platform work?' 'where is prepare_setup_platform defined?' 'how prepare_setup_platform reaches first_caller' 'default prepare_setup_platform and first_caller for Go and Rust buffers'; do
    A="$( ask "$NAT" "$q" )"; hasnt "$A" 'by="subject"' "SC no cue ($q): no callers"; has "$A" '<ctx ' "SC no cue ($q): an answer printed (twin)"
done
# negative twins: plain words past the bound still refuse, a frame word never counts toward a name, no function no block
A="$( ask "$NAT" 'I want prepare_setup_platform to log retry timing metrics somewhere useful please' )"
hasnt "$A" 'by="subject"' "SC prose past the bound (frame aside): no callers"; has "$A" '<ctx ' "SC prose past the bound: an answer printed (twin)"
A="$( ask "$NAT" 'I need to change how it works; what depends on it?' )"
hasnt "$A" 'by="subject"' "SC frame words only, no name: no callers"; has "$A" '<ctx ' "SC frame words only: an answer printed (twin)"
# SCN-FIX1 pins. Each cue alone (deleting it from the table turns its arm red), a capitalised cue on a non-descriptive sentence (the
# table is read case-folded), and the plain-word bound from both sides (4 fires, 5 does not; the CodeRabbit cue-past-the-bound case)
nat "$NAT" 'Adding a new keyword argument to prepare_setup_platform: what would I need to fix?' first_caller "py capitalised cue (Adding)"
nat "$NAT" 'who uses prepare_setup_platform?' first_caller "py uses alone"
nat "$NAT" 'where is prepare_setup_platform used today?' first_caller "py used alone"
nat "$NAT" 'what depends on prepare_setup_platform today?' first_caller "py depends alone"
nat "$NAT" 'what is affected if prepare_setup_platform gains a flag?' first_caller "py affected alone"
nat "$NAT" 'if I modify prepare_setup_platform, what else?' first_caller "py modify alone"
nat "$NAT" 'which code would need updating if prepare_setup_platform grows an argument?' first_caller "py updating alone"
nat "$NAT" 'what broke after prepare_setup_platform moved?' first_caller "py broke alone"
nat "$NAT" 'I need to change prepare_setup_platform to log retry timing metrics; what depends on it?' first_caller "py cue, 4 plain words (the bound)"
A="$( ask "$NAT" 'I need to change prepare_setup_platform to log retry timing metrics somewhere; what depends on it?' )"
hasnt "$A" 'by="subject"' "SC cue, 5 plain words (past the bound): no callers"; has "$A" '<ctx ' "SC cue past the bound: an answer printed (twin)"
# the cues added by SCN-FIX1, each with a twin in a sense that is not "who depends on it" (the function's own action)
nat "$NAT" 'who invokes prepare_setup_platform?' first_caller "py invokes"
nat "$NAT" 'who references prepare_setup_platform?' first_caller "py references"
nat "$NAT" 'what would I have to touch to rename prepare_setup_platform?' first_caller "py rename"
nat "$NAT" 'which tests exercise prepare_setup_platform?' first_caller "py tests exercise (plain callers)"
nat "$NAT" 'who is using prepare_setup_platform?' first_caller "py is using"
# no block: the callee shape (what the function itself does), a noun or purpose sense, a negated mention, two named functions
printf 'def other_helper(hass):\n    return hass\n' > "$NAT/app/other.py"
for q in 'what does prepare_setup_platform depend on?' 'what state does prepare_setup_platform modify?' \
         'which functions does prepare_setup_platform use internally and what do they update?' 'where does prepare_setup_platform make API calls?' \
         'what is prepare_setup_platform used to do, compared with captures?' 'I changed nothing in prepare_setup_platform; where is the 404 fallback decided?' \
         'When prepare_setup_platform changes, who calls other_helper?' 'what does prepare_setup_platform invoke?' \
         'which config keys does prepare_setup_platform reference?' 'how does prepare_setup_platform rename the field?' \
         'which code paths does prepare_setup_platform exercise?' 'how would I build a platform using prepare_setup_platform here?'; do
    A="$( ask "$NAT" "$q" )"; hasnt "$A" 'by="subject"' "SC not a dependents sense ($q): no callers"; has "$A" '<ctx ' "SC not a dependents sense ($q): an answer printed (twin)"
done
A="$( ask "$GO" 'I want to pass a new parameter into proxy.NewProxier from createProxier; what needs to change?' )"
hasnt "$A" 'by="subject"' "SC go two names in a sentence: no callers (no guess)"; has "$A" '<ctx ' "SC go two names: an answer printed (twin)"
# two exact symbols: no ONE anchor, so no flip: the whole subject's route stands (both names anchored, and the word with them)
A="$( ask "$PY" 'first_caller second_caller new' )"; R="$( route "$A" )"
has "$R" 'first_caller(' "T two exact: first anchored"; has "$R" 'second_caller(' "T two exact: second anchored"; hasnt "$R" 'dropped:' "T two exact: nothing dropped (no set flip)"
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
# the MCP `for` verb, one tools/call (F1, FH)
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
# ── FRAME-HIGH-CONFIDENCE: high needs the anchor at the head of the ranked rows (src/subjectanchor.h routeAnchorHeadsRows) ──
NOHEAD='anchor is not the ranked head'
FH="$TMP/fh"; mkdir -p "$FH/pkg/futures" "$FH/ui" "$FH/cc"
printf 'class ThreadPoolExecutor:\n    def submit(self, fn):\n        return fn()\n' > "$FH/pkg/futures/thread.py"
printf 'class Icon:\n    def where(self, x):\n        return x\n' > "$FH/ui/dnd.py"
printf 'def where(x):\n    return x\n' > "$FH/ui/other.py"
printf 'def icon_helper(x):\n    return x\n' > "$FH/ui/IconTools.py"
# (a) the anchor heads the rows: high, no clause
A="$( ask "$FH" 'where ThreadPoolExecutor is defined' )"
has "$( route "$A" )" 'name-exact(ThreadPoolExecutor)' "FH(a) the route is name-exact on the anchor"
if [ "$( conf "$A" )" = high ]; then ok "FH(a) anchor heads: high"; else no "FH(a) anchor heads: $( conf "$A" )"; fi; hasnt "$A" "$NOHEAD" "FH(a) anchor heads: no clause"
# (b) the anchor is present but another symbol heads (a plain word's namesake, ld-cpython-01's shape): not high, and route= says which row heads
A="$( ask "$FH" 'where pkg.futures.ThreadPoolExecutor is defined' )"; R="$( route "$A" )"
has "$R" 'name-exact(pkg.futures.ThreadPoolExecutor)' "FH(b) the route is name-exact on the dotted anchor"
if [ "$( conf "$A" )" = low ]; then ok "FH(b) another head: low"; else no "FH(b) another head: $( conf "$A" )"; fi
has "$R" "$NOHEAD (r=1 is where in ui/other.py)" "FH(b) route= names the row that heads"
M="$( mcpfor "$FH" 'where pkg.futures.ThreadPoolExecutor is defined' )"
if [ "$( conf "$M" )" = low ]; then ok "FH(b) MCP twin: low"; else no "FH(b) MCP twin: $( conf "$M" )"; fi; has "$( route "$M" )" "$NOHEAD" "FH(b) MCP twin: the clause"
# (b) sibling: C++, a qualified anchor beside a plain word that is a function elsewhere
printf 'namespace app { struct WidgetBox { int size() const { return 1; } }; }\n' > "$FH/cc/widget.h"
printf 'int where( int x ) { return x; }\n' > "$FH/cc/util.cpp"
A="$( ask "$FH" 'where app::WidgetBox is defined' )"; R="$( route "$A" )"
has "$R" 'name-exact(app::WidgetBox)' "FH(b) C++ sibling: name-exact on the qualified anchor"
if [ "$( conf "$A" )" = low ]; then ok "FH(b) C++ sibling: the free function where heads, low"; else no "FH(b) C++ sibling: $( conf "$A" )"; fi
has "$R" "$NOHEAD (r=1 is where in cc/util.cpp)" "FH(b) C++ sibling: route= names the head"
# a FILE subject anchors its file: a row in it heads, high stays (mf1-htop-03's shape)
A="$( ask "$FH" 'IconTools.py' )"; has "$( route "$A" )" 'name-exact(IconTools.py)' "FH file subject: name-exact"
if [ "$( conf "$A" )" = high ]; then ok "FH file subject: its own row heads, high"; else no "FH file subject: $( conf "$A" )"; fi; hasnt "$A" "$NOHEAD" "FH file subject: no clause"
# (c) no anchor (a conceptual route): unchanged, no clause; the positive twin says the fixture can read high there
A="$( ask "$FH" 'thread pool submit work' )"; R="$( route "$A" )"
case "$R" in subtoken+body*) ok "FH(c) conceptual route";; *) no "FH(c) not conceptual: $R";; esac
if [ "$( conf "$A" )" = high ]; then ok "FH(c) no anchor: high as before"; else no "FH(c) no anchor: $( conf "$A" )"; fi; hasnt "$A" "$NOHEAD" "FH(c) no anchor: no clause"

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
# M1-M5 (review rv-subject-anchor-delta): the flip needs a real body AND real callers
mkfx(){ d="$TMP/m_$1"; mkdir -p "$d/src" "$d/cc"; cp "$FX/src/"p*.ts "$FX/src/fresh.ts" "$d/src/"; printf '%s' "$d"; }
CU='#include "t.h"\nint userOne(){ return SoloThing(1); }\n'
# M1: a declaration beside its definition in one file shares the six-candidate pool: a body past it cannot print, so the map stays
M1="$( mkfx m1 )"
python3 - "$M1/cc/t.h" "$M1/cc/u.cc" <<'X2'
import sys
open(sys.argv[1],'w').write('int SoloThing(int a);\nint SoloThing(int a) {\n' + '    a = a + 1;\n'*700 + '    return a;\n}\n')
open(sys.argv[2],'w').write('#include "t.h"\nint userOne(){ return SoloThing(1); }\n')
X2
A="$( ask "$M1" 'SoloThing fresh parameter' )"; R="$( route "$A" )"
hasnt "$R" 'dropped:' "M1 declaration + a ~10 KB definition in one file: the map stays"
hasnt "$A" 'body omitted' "M1 the answer never claims a body it cannot print"
M1S="$( mkfx m1s )"
printf 'int SoloThing(int a);\nint SoloThing(int a) { return a + 41; }\n' > "$M1S/cc/t.h"; printf '%b' "$CU" > "$M1S/cc/u.cc"
A="$( ask "$M1S" 'SoloThing fresh parameter' )"
has "$( route "$A" )" 'dropped:' "M1 control: declaration + a small definition still flips"
has "$A" 'int SoloThing(int a) { return a + 41; }' "M1 control: the body prints"
# M2: a declaration-only symbol never flips
M2="$( mkfx m2 )"; printf 'int SoloThing(int a);\n' > "$M2/cc/t.h"; printf '%b' "$CU" > "$M2/cc/u.cc"
A="$( ask "$M2" 'SoloThing fresh parameter' )"; hasnt "$( route "$A" )" 'dropped:' "M2 C++ prototype only: no flip"
M2T="$( mkfx m2t )"; printf 'export declare function SoloThing(a: number): number;\n' > "$M2T/src/thing.d.ts"; printf "import {SoloThing} from './thing';\nexport function userOne() { return SoloThing(1); }\n" > "$M2T/src/user.ts"
A="$( ask "$M2T" 'SoloThing fresh parameter' )"; hasnt "$( route "$A" )" 'dropped:' "M2 TS declare function only: no flip"
M2I="$( mkfx m2i )"; mkdir -p "$M2I/j"; printf 'interface I { int SoloThing(int a); }\n' > "$M2I/j/I.java"; printf 'class U { int userOne(I i) { return i.SoloThing(1); } }\n' > "$M2I/j/U.java"
A="$( ask "$M2I" 'SoloThing fresh parameter' )"; hasnt "$( route "$A" )" 'dropped:' "M2 Java interface method only: no flip"
# M3: --signatures-only prints no body and no callers: the map stays
A="$( cd "$FX" && "$BIN" "$FX" --no-cache '--for=SoloThing fresh parameter' --signatures-only 2>/dev/null </dev/null )"
hasnt "$( route "$A" )" 'dropped:' "M3 --signatures-only: no flip"
has "$( route "$A" )" 'declined' "M3 --signatures-only: the declined route is disclosed"
# M5: a function with no caller has no <callers> to trade the map for
M5="$( mkfx m5 )"; printf 'export function SoloThing(a: number) { return a + 41; }\n' > "$M5/src/thing.ts"
A="$( ask "$M5" 'SoloThing fresh parameter' )"; hasnt "$( route "$A" )" 'dropped:' "M5 no caller: no flip"
# M4: a declaration in namespace a and a definition in namespace b are two functions: no flip (the body and a caller would be the other's)
M4="$( mkfx m4 )"; mkdir -p "$M4/aaa" "$M4/zzz"
printf 'namespace a { int SoloThing(int v); }\n' > "$M4/aaa/a.h"
printf 'namespace b { int SoloThing(int v) { return v + 41; } }\n' > "$M4/zzz/b.cc"
printf 'namespace a { int SoloThing(int); }\nint userOne(){ return a::SoloThing(1); }\n' > "$M4/zzz/u.cc"
A="$( ask "$M4" 'SoloThing fresh parameter' )"; hasnt "$( route "$A" )" 'dropped:' "M4 declaration in a, definition in b: no flip"
# ── FIX 3 (review rv-subject-anchor-delta2): the gate runs for EVERY flip, and tests the outcome ──
# MF1: natural wording. `work` is itself a symbol (one definition), so the WHOLE route is name-exact and the dropped word is a plain-word
# anchor; before this fix that path skipped M1-M5 and printed a prototype at high. The arms above pass only because their fill word makes
# the route decline; these reach the gate with question wording, a task verb and a bare tail.
wfx(){ d="$( mkfx "w_$1" )"; printf 'export function work(a: number) { return a; }\nexport function fix(a: number) { return a; }\nexport function bug(a: number) { return a; }\n' > "$d/src/work.ts"; printf '%s' "$d"; }
WQ=( 'how does SoloThing work' 'fix a bug in SoloThing' 'SoloThing work' )
refused(){ # $1 fixture, $2 label: a refused flip answers as the whole subject always did: chooseForRanker's route, the plain word
    # still among its anchors, nothing dropped, and no conceptual re-rank of the whole task (subject-fix4: that fallback ranked the
    # dropped word and lost type subjects)
    local q A R
    for q in "${WQ[@]}"; do
        A="$( ask "$1" "$q" )"; R="$( route "$A" )"
        hasnt "$R" 'dropped:' "$2 [$q]: nothing dropped"
        has "$R" 'name-exact(' "$2 [$q]: the whole subject's name-exact route stands"
        has "$R" '(src/work.ts)' "$2 [$q]: the plain-word anchor is the whole route's, as before"
    done
}
W1="$( wfx m1 )"; python3 - "$W1/cc/t.h" "$W1/cc/u.cc" <<'X2'
import sys
open(sys.argv[1],'w').write('int SoloThing(int a);\nint SoloThing(int a) {\n' + '    a = a + 1;\n'*700 + '    return a;\n}\n')
open(sys.argv[2],'w').write('#include "t.h"\nint userOne(){ return SoloThing(1); }\n')
X2
refused "$W1" "W-M1 declaration + a ~10 KB definition"
W2="$( wfx m2 )"; printf 'int SoloThing(int a);\n' > "$W2/cc/t.h"; printf '%b' "$CU" > "$W2/cc/u.cc"
refused "$W2" "W-M2 C++ prototype only"
W2T="$( wfx m2t )"; printf 'export declare function SoloThing(a: number): number;\n' > "$W2T/src/thing.d.ts"; printf "import {SoloThing} from './thing';\nexport function userOne() { return SoloThing(1); }\n" > "$W2T/src/user.ts"
refused "$W2T" "W-M2 TS declare function only"
W2I="$( wfx m2i )"; mkdir -p "$W2I/j"; printf 'interface I { int SoloThing(int a); }\n' > "$W2I/j/I.java"; printf 'class U { int userOne(I i) { return i.SoloThing(1); } }\n' > "$W2I/j/U.java"
refused "$W2I" "W-M2 Java interface method only"
W2G="$( wfx m2g )"; mkdir -p "$W2G/g"; printf 'package g\ntype I interface {\n\tSoloThing(a int) int\n}\n' > "$W2G/g/i.go"; printf 'package g\nfunc userOne(i I) int { return i.SoloThing(1) }\n' > "$W2G/g/u.go"
refused "$W2G" "W-M2 Go interface method only"
W5="$( wfx m5 )"; printf 'export function SoloThing(a: number) { return a + 41; }\n' > "$W5/src/thing.ts"
refused "$W5" "W-M5 no caller"
W4="$( wfx m4 )"; mkdir -p "$W4/aaa" "$W4/zzz"
printf 'namespace a { int SoloThing(int v); }\n' > "$W4/aaa/a.h"; printf 'namespace b { int SoloThing(int v) { return v + 41; } }\n' > "$W4/zzz/b.cc"
printf 'namespace a { int SoloThing(int); }\nint userOne(){ return a::SoloThing(1); }\n' > "$W4/zzz/u.cc"
refused "$W4" "W-M4 declaration in a, definition in b"
# neighbour shapes the review did not name: a Python def with no caller, a Rust trait method with no body
WP="$( wfx py )"; mkdir -p "$WP/py"; printf 'def solo_thing(a):\n    return a + 41\n' > "$WP/py/s.py"
for q in 'how does solo_thing work' 'fix a bug in solo_thing' 'solo_thing work'; do
    A="$( ask "$WP" "$q" )"; hasnt "$( route "$A" )" 'dropped:' "W py no caller [$q]: no flip"
done
WR="$( wfx rs )"; mkdir -p "$WR/rs"; printf 'trait T { fn solo_thing(&self, a: i32) -> i32; }\n' > "$WR/rs/t.rs"; printf 'fn user_one(t: &dyn T) -> i32 { t.solo_thing(1) }\n' > "$WR/rs/u.rs"
for q in 'how does solo_thing work' 'fix a bug in solo_thing' 'solo_thing work'; do
    A="$( ask "$WR" "$q" )"; hasnt "$( route "$A" )" 'dropped:' "W rust trait method only [$q]: no flip"
done
# neighbour: SEVERAL exact names are a name-exact set; the set form of the gate (every name has a body) still refuses prototypes
WS="$( wfx set )"; printf 'int SoloOne(int a);\nint SoloTwo(int a);\n' > "$WS/cc/t.h"; printf '#include "t.h"\nint userOne(){ return SoloOne(1) + SoloTwo(2); }\n' > "$WS/cc/u.cc"
A="$( ask "$WS" 'SoloOne SoloTwo work' )"; hasnt "$( route "$A" )" 'dropped:' "W set of two prototypes + work: no flip"
WS2="$( wfx set2 )"; printf 'int SoloOne(int a) { return a + 1; }\nint SoloTwo(int a) { return a + 2; }\n' > "$WS2/cc/t.cc"
A="$( ask "$WS2" 'SoloOne SoloTwo work' )"; R="$( route "$A" )"
hasnt "$R" 'dropped:' "W set: two bodied names + work: several names never flip"; has "$R" '(src/work.ts)' "W set: the whole route stands"
# the set shapes review delta3 found passing the old set gate: a case-folded namesake struct (C++), a Rust trait method (syntax anchor),
# two bodies past the allowance. No set flip exists now; each keeps the whole route.
WS3="$( wfx set3 )"; printf 'int AlphaOne(int a) { return a + 1; }\n' > "$WS3/cc/a.cc"; printf 'int BetaTwo(int a);\nstruct betatwo { int x; int y; };\n' > "$WS3/cc/b.h"
A="$( ask "$WS3" 'AlphaOne BetaTwo work' )"; hasnt "$( route "$A" )" 'dropped:' "W set s3 (prototype + case-folded struct): no flip"
WS6="$( wfx set6 )"; mkdir -p "$WS6/rs"; printf 'trait T { fn beta_two(&self, a: i32) -> i32; }\nfn alpha_one(a: i32) -> i32 { a + 1 }\n' > "$WS6/rs/t.rs"
A="$( ask "$WS6" 'alpha_one beta_two work' )"; hasnt "$( route "$A" )" 'dropped:' "W set s6 (Rust trait method, syntax anchor): no flip"
# ONE placed name beside a second identifier the index does not hold is still two names: no flip (its twin, the control below, flips)
WC0="$( wfx ctl0 )"; printf 'export function SoloThing(a: number) { return a + 41; }\nexport function soloUser() { return SoloThing(1); }\n' > "$WC0/src/thing.ts"
A="$( ask "$WC0" 'SoloThing zzNotIndexed work' )"; hasnt "$( route "$A" )" 'dropped:' "W one placed + one unplaced identifier: no flip"
A="$( ask "$WC0" 'SoloThing work' )"; has "$( route "$A" )" 'dropped: work' "W one placed name: twin flips"
# a TYPE subject (review delta3 must-fix 3: mdbook BookConfig, cpython Py_buffer): a type has no caller contract, so the gate refuses
# the flip, and the answer is the whole subject's as before: the type is still anchored, never a conceptual re-rank led by `run`
WT="$( wfx type )"; printf 'export function run(a: number) { return a; }\n' >> "$WT/src/work.ts"
printf 'export class SoloType { x = 1; y = 2; }\nexport function soloMaker() { return new SoloType(); }\n' > "$WT/src/type.ts"
for q in 'how does SoloType run' 'SoloType work' 'SoloType fresh parameter'; do
    A="$( ask "$WT" "$q" )"; R="$( route "$A" )"
    hasnt "$R" 'dropped:' "W type subject [$q]: no flip"
    has "$A" 'class SoloType' "W type subject [$q]: the type's body still prints"
    case "$q" in *fresh*) has "$R" 'declined' "W type subject [$q]: the declined route stands";;
                 *) has "$R" 'name-exact(' "W type subject [$q]: the whole subject's name-exact route stands, no conceptual re-rank";; esac
done
# controls: one function, a body that fits, a caller: the natural wording still flips and the body and callers print
WC="$( wfx ctl )"; printf 'export function SoloThing(a: number) { return a + 41; }\nexport function soloUser() { return SoloThing(1); }\n' > "$WC/src/thing.ts"
for q in "${WQ[@]}"; do
    A="$( ask "$WC" "$q" )"
    has "$( route "$A" )" 'name-exact(SoloThing)' "W control [$q]: flips to the symbol"
    has "$A" 'n="SoloThing"><![CDATA[function SoloThing' "W control [$q]: the body prints"
    has "$( blk "$A" )" 'soloUser' "W control [$q]: the callers print"
done
# MF2: the outcome, not a flag list. Every mode that prints no body, or no callers, keeps the map; the same call in the default mode flips.
mode(){ ( cd "$FX" && "$BIN" "$FX" --no-cache '--for=SoloThing fresh parameter' "$@" 2>/dev/null ) </dev/null; }
A="$( mode )"; has "$( route "$A" )" 'dropped:' "MF2 control: the default mode flips"
A="$( mode --json )"
case "$A" in *'name-exact(SoloThing)'*) no "MF2 --json flipped to a signature row with no body";; *) ok "MF2 --json: no flip";; esac
case "$A" in *'dropped:'*) no "MF2 --json names dropped words";; *) ok "MF2 --json: nothing dropped";; esac
A="$( mode --detail=1 )"; hasnt "$( route "$A" )" 'dropped:' "MF2 --detail=1: no flip (bodies, no callers hop)"
A="$( mode --token-budget=2000 )"; hasnt "$( route "$A" )" 'dropped:' "MF2 --token-budget: no flip"
# the file page (--limit/--offset) prints file rows, no body and no callers; an explicit --pack-budget-bytes is a body ceiling the
# single-anchor allowance never sees (CodeRabbit #502). Each keeps the map; each arm reads a route first, so an empty answer is red.
for fl in --limit=5 --offset=1 '--limit=5 --offset=0' --pack-budget-bytes=4000; do
    # shellcheck disable=SC2086  # word splitting is the point: '--limit=5 --offset=0' is two flags
    A="$( mode $fl )"; R="$( route "$A" )"
    case "$R" in @@NONE) no "MF2 $fl: no route (empty or failed answer)";; *dropped:*|*'name-exact(SoloThing)'*) no "MF2 $fl flipped: $R";; *) ok "MF2 $fl: no flip";; esac
done
A="$( mode --pack-budget-bytes=65536 )"; has "$( route "$A" )" 'dropped:' "MF2 --pack-budget-bytes at its default: still flips"
# --format=candidates prints the route TAG (route="name-exact"), never the anchor clause: test the tag, with a positive twin
A="$( mode --format=candidates )"
case "$A" in *'route="subtoken+body'*) ok "MF2 --format=candidates: no flip (the declined map's tag)";; *) no "MF2 --format=candidates flipped or failed";; esac
A="$( cd "$FX" && "$BIN" "$FX" --no-cache '--for=SoloThing' --format=candidates 2>/dev/null </dev/null )"
has "$A" 'route="name-exact"' "MF2 --format=candidates twin: a bare symbol's tag is name-exact, so the arm above can see a flip"
A="$( mode --detail=2 )"; hasnt "$( route "$A" )" 'dropped:' "MF2 --detail=2: no flip"
A="$( mode --json --signatures-only )"
case "$A" in *'name-exact(SoloThing)'*) no "MF2 --json --signatures-only flipped";; *) ok "MF2 --json --signatures-only: no flip";; esac
A="$( mode --auto-bodies )"; has "$( route "$A" )" 'dropped:' "MF2 --auto-bodies prints bodies and callers on the name-exact route: still flips"
# determinism + well-formed
A1="$( ask "$PY" 'prepare_setup_platform new parameter' )"; A2="$( ask "$PY" 'prepare_setup_platform new parameter' )"
if [ "$( printf '%s' "$A1" | sed -E 's/ at="[^"]*"//' )" = "$( printf '%s' "$A2" | sed -E 's/ at="[^"]*"//' )" ]; then ok "determinism"; else no "determinism"; fi
if printf '%s' "$A1" | xmllint --noout - 2>/dev/null; then ok "xml well formed"; else no "xml not well formed"; fi
[ "$fail" = 0 ] && { echo "subjectanchorcheck: PASS"; exit 0; }
echo "subjectanchorcheck: FAIL"; exit 1
