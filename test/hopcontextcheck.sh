#!/usr/bin/env bash
# hopcontextcheck.sh — HOP-CONTEXT-1 (IDEAS_LIST card 20): every hop a --path / --connect answer prints carries its call site,
# the call's text and the callee's signature, from ONE shared hop record (src/hoprecord.h), and says so when it cannot.
#
# Owner (11-04): "the parts of the call tree arguments return types indirection ... are in a bunch of different files ...
# doing it in one call for an agent will make the agents job much easier". A hop row used to name the callee's definition
# only; the agent then opened the caller to see the call (R1) and the callee to see its parameters (R2): ~2 reads per edge.
#
# Arms (Stage 0, reports/hop-context-s0.md; each negative arm has a positive twin; every command's exit code is checked):
#   (1) identity  — RIPWIRE_NO_HOP_CONTEXT=1 is the answer before the lane: the default answer with the hop attributes, the hop
#                   root disclosures and the legend comments removed (est_tokens masked) equals it, on every fixture command and
#                   on ripwire's own src; and the default answer DOES carry site= (red on a binary without the field)
#   (2) languages — C (multi-line free call, macro invocation), C++ (Class::method through ->, XML/UTF-8 text), Python (self.m()
#                   multi-line await, decorated callee), TypeScript (this.#dispatch, namespace call, via=name), Go (receiver
#                   chain), Rust (impl method with a where clause on following lines): exact site= call= sig=
#   (3) unread    — a file unreadable / edited since the crawl withholds call= and sig= (hop_unread=N), a site whose text no
#                   longer spells the callee withholds call= (hop_notext=N); site= stays; never an empty call=
#   (4) shed      — under --max-tokens the --connect hop sheds sig= (hop_shed="sig"), then call= (hop_shed="sig,call"); site=
#                   and every <e> row stay
#   (5) dedupe    — two <e> rows that would read alike (homeassistant-08's shape) differ by tp=
#   (6) cap       — a caller with two calls of the callee prints the first site and sites="2"; the pick (review S1/S2): a call
#                   qualified by the callee's owner first (C++ ns::W::make / W::make, TS B.make), a call whose argument count
#                   the callee rejects last (C++ a.get( 1 ) vs b.get( 2, 3 )); a tie with a namesake callee says
#                   site_by="first" (Python s.fetch / c.fetch), no fitting call says site_by="nofit"
#   (7) legend    — every hop attribute the answer prints is defined (name=) in its own legend, compact and full; MCP
#                   path_between and connect print the CLI's hop rows byte for byte
#   (8) hoisting  — a 40-hop --path and a 14-terminal --connect each make ONE reference scan (RIPWIRE_HOP_STATS), files read
#                   once each
#   (9) secrets   — a credential a cut would split (the 40 B move to the name, the 512 B window on a long line, the 120 B cap,
#                   a keyword-gated run past the window) never prints in part, CLI + MCP path_between + MCP connect; a name
#                   inside a redacted run withholds call= (hop_redacted=1)
#  (10) no site   — a hop with no site still prints the callee's sig= (Python import alias, TS import alias); a one-line
#                   caller's call= starts at its statement, not its own signature
#
# Usage:  test/hopcontextcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/hopcontextcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_HOP_CONTEXT RIPWIRE_HOP_STATS RIPWIRE_TEST_FILETEXT_UNREAD RIPWIRE_TEST_FILETEXT_EDITED RIPWIRE_TEST_FILETEXT_BLANKED RIPWIRE_NO_HOP_BODY
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "hopcontextcheck: SKIP (no python3)"; exit 0; }
echo "hopcontextcheck: BIN=$BIN"
SCR="$( mktemp -d -t hopcontextcheck.XXXXXX )" || { echo "mktemp failed"; exit 2; }
trap 'rm -rf "$SCR"' EXIT
export HOME="$SCR"
F="$SCR/fix"
mkdir -p "$F/c" "$F/cpp" "$F/py" "$F/ts" "$F/go" "$F/rs" "$F/pyd" "$F/chain" "$F/cpp2" "$F/py2" "$F/qual" "$F/tsq" "$F/tsa" "$F/nf" "$F/sec"

# ── fixtures (written at runtime) ─────────────────────────────────────────────────────────────────────────────────────
cat > "$F/c/a.c" <<'X'
#define WRAP( x ) helper( x )
struct ops { int ( *open )( int ); };
static int helper( int v ) { return v + 1; }
int leaf( int a, int b ) { return a * b; }
int mid( int n )
{
	int r = leaf( n,
	              n + 1 );
	r += leaf( r, 2 );
	return r;
}
int top( int n ) { return mid( n ); }
int viamacro( int n ) { return WRAP( n ); }
X
cat > "$F/c/b.c" <<'X'
int leaf( int a, int b );
int far( int n ) { return leaf( n, 1 ); }
X
cat > "$F/cpp/w.h" <<'X'
#pragma once
namespace ns {
struct Widget
{
    int draw( int depth, const char* label ) const;
    static int make( int seed );
};
}
X
printf '%s\n' '#include "w.h"' 'namespace ns {' 'int Widget::draw( int depth, const char* label ) const { return depth + label[0]; }' \
  'int Widget::make( int seed ) { return seed * 2; }' '}' \
  "int render( const ns::Widget* w ) { return w->draw( 3, \"caf$( printf '\303\251' ) & <ok>\" ); }" \
  'int build() { return ns::Widget::make( 7 ) + render( nullptr ); }' > "$F/cpp/w.cpp"
cat > "$F/py/svc.py" <<'X'
def traced(fn):
    return fn

class Service:
    @traced
    async def fetch(self, key: str, *, retries: int = 3) -> bytes:
        return b""

    async def run(self, key):
        data = await self.fetch(
            key,
            retries=5,
        )
        return data

def main():
    s = Service()
    return s.run("k")
X
cat > "$F/pyd/ws.py" <<'X'
class AuthPhase:
    def async_handle(self, msg):
        return msg

class ActiveConnection:
    def async_handle(self, msg):
        return None

def get(handler):
    return handler.async_handle({})
X
cat > "$F/ts/app.ts" <<'X'
export namespace util {
  export function join(a: string, b: string): string { return a + b; }
}
export class App {
  #dispatch(req: Request, depth: number): Response { return new Response(util.join("a", "b")); }
  fetch(req: Request): Response {
    return this.#dispatch(req, 0);
  }
}
export function serve(app: App, r: Request): string {
  app.fetch(r);
  return "x";
}
X
cat > "$F/go/m.go" <<'X'
package m

type Pattern struct{}

func (p *Pattern) MatchItem(item string, withPos bool) bool { return withPos }

type merger struct{ pattern *Pattern }
type Terminal struct{ resultMerger merger }

func (t *Terminal) Loop() bool {
	return t.resultMerger.pattern.MatchItem("x", true)
}
X
cat > "$F/rs/lib.rs" <<'X'
pub struct Store;
impl Store {
    pub async fn load<T>(&self, key: &str) -> Result<T, String>
    where
        T: Default,
    {
        Ok(T::default())
    }
}
pub async fn get(s: &Store) -> Result<u32, String> {
    let v: u32 = s.load("k").await?;
    Ok(v)
}
X
# text hazards: a minified 6 KB line, a CRLF file, a credential-shaped argument (built at runtime: ripwirepubliccheck)
python3 - "$F" <<'PY'
import sys
d = sys.argv[1]
open(d + "/ts/min.ts", "w").write("import { util } from \"./app\"; export function mm(): string { " + "let a = 1; " * 600 + "return util.join(\"x\", \"y\"); }\n")
open(d + "/c/crlf.c", "wb").write(b"int leaf( int a, int b );\r\nint cr( int n )\r\n{\r\n\treturn leaf( n,\r\n\t             3 );\r\n}\r\n")
key = "AKIA" + "Q" * 4 + "7" * 12
open(d + "/c/key.c", "w").write("int leaf( int a, int b );\nint keyed( const char* k );\nint usekey( void ) { return leaf( keyed( \"%s\" ), 1 ); }\n" % key)
PY
# (6) the pick among same-named calls (review S1/S2) and (10) a hop with no site
cat > "$F/cpp2/m.cpp" <<'X'
struct A { int get( int k ); };
struct B { int get( int k, int j ); };
int A::get( int k ) { return k; }
int B::get( int k, int j ) { return k + j; }
int caller( A& a, B& b )
{
    int x = a.get( 1 );
    int y = b.get( 2, 3 );
    return x + y;
}
X
cat > "$F/py2/lib.py" <<'X'
class Store:
    def fetch(self, key):
        return key

class Cache:
    def fetch(self, key, default=None):
        return default
X
printf 'def compute(a, b):\n    return a + b\n' > "$F/py2/helpers.py"
cat > "$F/py2/app.py" <<'X'
from lib import Store, Cache
from helpers import compute as calc

def handler(s: Store, c: Cache):
    a = s.fetch("x")
    b = c.fetch("y",
                default=1)
    return a, b

def withlambda(items):
    f = lambda v: calc(v, 2)
    return [f(i) for i in items]
X
cat > "$F/qual/q.cpp" <<'X'
namespace ns { struct W { static int make( int s ); }; }
struct O { static int make( int s ); };
int ns::W::make( int s ) { return s; }
int O::make( int s ) { return s + 1; }
int b1() {
    int a = O::make( 1 );
    return a + ns::W::make( 7 ); }
int b2() {
    int a = O::make( 1 );
    return a + W::make( 7 ); }
X
cat > "$F/tsq/q.ts" <<'X'
export class A { static make(n: number): number { return n; } }
export class B { static make(n: number): number { return n + 1; } }
export function t(): number {
  const a = A.make(1);
  return a + B.make(2);
}
X
printf 'export function compute(a: number, b: number): number { return a + b; }\n' > "$F/tsa/h.ts"
printf 'import { compute as calc } from "./h";\nexport function w(): number {\n  return calc(1, 2);\n}\n' > "$F/tsa/w.ts"
cat > "$F/nf/n.cpp" <<'X'
struct C { int get( int a, int b, int c ); };
int C::get( int a, int b, int c ) { return a + b + c; }
int z( C& c )
{
    return c.get( 1 );
}
X
# (9) credentials a cut would split (built at runtime: ripwirepubliccheck); their bodies go to $F/sec/tokens for the checks
python3 - "$F/sec" <<'PY'
import sys
d = sys.argv[1]
body = "".join("Z9y8X7w6V5u4T3s2R1q0"[(i * 3) % 20] for i in range(36))
tok = "gh" + "p_" + body
gen = "".join("Qm4+Rt7/Kx2Ws9Lp3Vb8"[(i * 7) % 20] for i in range(600))
def w(n, t):
    open("%s/%s" % (d, n), "w").write(t)
# w4: the token sits in the 40 bytes the move to the name (past the 120 B cap) keeps
w("w4.js", 'function sink4(a){return a}\nfunction f(x){return x}\nfunction src4(){ return ' + "a" * 70 + '+f("' + tok + '")+sink4(1); }\n')
# w5: the 512 B window before the name starts inside the token (a whitespace-padded long line)
w("w5.js", 'function sink5(a){return a}\nfunction src5(){ var k = "' + tok + '";' + " " * 473 + 'return sink5(1); }\n')
# w6: a keyword-gated run (token=...) the 512 B window cuts: the keyword falls outside the window, the run's tail inside
w("w6.js", 'function sink6(a){return a}\nfunction src6(){var token="' + gen + '";return sink6(1);}\n')
# w7: the token after the name, its redaction straddling the 120 B cap
w("w7.js", 'function sink7(a,b){return a}\nfunction src7(){ return sink7(' + "c" * 85 + ', "' + tok + '"); }\n')
# w8: the token after a name that sits past the cap (the move to the name, then the token whole after it)
w("w8.js", 'function sink8(a){return a}\nfunction src8(){ return ' + "d" * 120 + '+sink8("' + tok + '"); }\n')
# w9: the callee name inside a keyword-gated run: no call text can print without a cut through the redaction
w("w9.js", 'function sink9(a){return a}\nfunction src9(){ var o = {token: 1}; return ' + gen[:40] + '+sink9(1); }\n')
# w10: a whole keyword-gated run after the name, its keyword (token=) on the same long line but outside the 512 B window
w("w10.js", 'function sink10(a,b){return a}\nfunction src10(){var token=1;' + "var a=1;" * 80 + 'return sink10(1, "' + gen[100:140] + '");}\n')
open(d + "/tokens", "w").write(body + "\n" + gen + "\n")
PY

# (8) a 40-hop chain over 4 files: f0 -> f1 -> ... -> f40
python3 - "$F/chain" <<'PY'
import sys
d = sys.argv[1]
for k in range(4):
    with open(f"{d}/part{k}.c", "w") as o:
        for i in range(k * 10, k * 10 + 10):
            o.write(f"int f{i + 1}( int n );\n")
            o.write(f"int f{i}( int n ) {{ return f{i + 1}( n + {i} ); }}\n")
    if k == 3:
        with open(f"{d}/part{k}.c", "a") as o:
            o.write("int f40( int n ) { return n; }\n")
PY

# ── the runs: one answer per file, exit code recorded beside it ─────────────────────────────────────────────────────────
O="$SCR/out"; mkdir -p "$O"
# run NAME DIR ENV... -- ARGS : stdout to $O/NAME, stderr to $O/NAME.err, exit code to $O/NAME.rc
run(){
  local name="$1" dir="$2"; shift 2
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=( "$1" ); shift; done
  shift
  ( cd "$dir" && env ${envs[@]+"${envs[@]}"} "$BIN" . --no-cache "$@" > "$O/$name" 2> "$O/$name.err" ); echo "$?" > "$O/$name.rc"
}
CMDS=(
  "c_path|c|--path=top,leaf"
  "c_macro|c|--path=viamacro,helper"
  "c_far|c|--path=far,leaf"
  "c_conn|c|--connect=top,far,viamacro"
  "cpp_path|cpp|--path=build,draw"
  "py_path|py|--path=main,fetch"
  "pyd_conn|pyd|--connect=AuthPhase.async_handle,ActiveConnection.async_handle"
  "ts_path|ts|--path=serve,join"
  "go_path|go|--path=Loop,MatchItem"
  "rs_path|rs|--path=get,load"
  "min_path|ts|--path=mm,join"
  "crlf_path|c|--path=cr,leaf"
  "key_path|c|--path=usekey,leaf"
  "cpp2_path|cpp2|--path=caller,B::get"
  "cpp2_conn|cpp2|--connect=A::get,B::get"
  "py2_path|py2|--path=handler,Cache.fetch"
  "py2_alias|py2|--path=withlambda,compute"
  "qual_b1|qual|--path=b1,ns::W::make"
  "qual_b2|qual|--path=b2,W::make"
  "tsq_b|tsq|--path=t,B.make"
  "tsq_a|tsq|--path=t,A.make"
  "tsa_alias|tsa|--path=w,compute"
  "nf_path|nf|--path=z,C::get"
  "sec4|sec|--path=src4,sink4"
  "sec5|sec|--path=src5,sink5"
  "sec6|sec|--path=src6,sink6"
  "sec7|sec|--path=src7,sink7"
  "sec8|sec|--path=src8,sink8"
  "sec9|sec|--path=src9,sink9"
  "sec10|sec|--path=src10,sink10"
)
for spec in "${CMDS[@]}"; do
  IFS='|' read -r name dir arg <<< "$spec"
  run "$name" "$F/$dir" -- "$arg"
  run "$name.full" "$F/$dir" -- "$arg" --legend=full
  run "$name.off" "$F/$dir" RIPWIRE_NO_HOP_CONTEXT=1 -- "$arg"
done
# ripwire's own source: a real tree (arm 1)
run self_path "$ROOT/src" -- --path=serialize,escapeXml
run self_path.off "$ROOT/src" RIPWIRE_NO_HOP_CONTEXT=1 -- --path=serialize,escapeXml
run self_conn "$ROOT/src" -- --connect=serialize,escapeXml,rankGraph
run self_path.full "$ROOT/src" -- --path=serialize,escapeXml --legend=full
run self_conn.full "$ROOT/src" -- --connect=serialize,escapeXml,rankGraph --legend=full
run self_conn.off "$ROOT/src" RIPWIRE_NO_HOP_CONTEXT=1 -- --connect=serialize,escapeXml,rankGraph
# (3) faults
run c_unread "$F/c" RIPWIRE_TEST_FILETEXT_UNREAD=a.c -- --path=top,leaf
run c_edited "$F/c" RIPWIRE_TEST_FILETEXT_EDITED=a.c -- --path=top,leaf
run c_blank "$F/c" RIPWIRE_TEST_FILETEXT_BLANKED=b.c -- --path=far,leaf
# (4) shed ladder: the same connect at falling ceilings (the full-legend token estimate is what --max-tokens is read against)
SHED_T=( 100000 )
t=2000; while [ "$t" -ge 1000 ]; do SHED_T+=( "$t" ); t=$(( t - 10 )); done
for t in "${SHED_T[@]}"; do run "c_shed_$t" "$F/c" -- --connect=top,leaf,far --max-tokens=$t; done
# a level narrower than the 10-token step (one hop sig= nets a few tokens once hop_shed="sig" and its clause print) is
# walked at step 1 between the two coarse ceilings it hides between, so the ladder sees every level it passes
FINE_T=( $( python3 - "$O" "${SHED_T[@]}" <<'PY'
import re, sys
O, ts = sys.argv[1], [int(x) for x in sys.argv[2:]]
order = {"": 0, "sig": 1, "sig,call": 2, "sig,call,site": 3}
def lvl(t):
    try:
        m = re.search(r'<connect [^>]*?hop_shed="([^"]*)"', open("%s/c_shed_%d" % (O, t), encoding="utf-8", errors="replace").read())
    except OSError:
        return 0
    return order.get(m.group(1), 0) if m else 0
for hi, lo in zip(ts[1:], ts[2:]):
    if lvl(lo) - lvl(hi) > 1:
        print(" ".join(str(x) for x in range(hi - 1, lo, -1)))
PY
) )
for t in ${FINE_T[@]+"${FINE_T[@]}"}; do run "c_shed_$t" "$F/c" -- --connect=top,leaf,far --max-tokens=$t; done
printf '%s\n' "${SHED_T[@]}" ${FINE_T[@]+"${FINE_T[@]}"} | sort -rn | uniq > "$O/shed_list"
# (8) hoisting
run chain_path "$F/chain" RIPWIRE_HOP_STATS=1 -- --path=f0,f40
run chain_conn "$F/chain" RIPWIRE_HOP_STATS=1 -- --connect=f0,f3,f6,f9,f12,f15,f18,f21,f24,f27,f30,f33,f36,f39

# MCP twins (arm 7)
python3 - "$BIN" "$F" "$O" <<'PY'
import json, subprocess, sys
binp, F, O = sys.argv[1:4]
calls = [("mcp_c_path", "path_between", {"path": F + "/c", "from": "top", "to": "leaf"}),
         ("mcp_pyd_conn", "connect", {"path": F + "/pyd", "symbols": ["AuthPhase.async_handle", "ActiveConnection.async_handle"]}),
         ("mcp_sec4_path", "path_between", {"path": F + "/sec", "from": "src4", "to": "sink4"}),
         ("mcp_sec4_conn", "connect", {"path": F + "/sec", "symbols": ["src4", "sink4"]}),
         ("mcp_sec5_path", "path_between", {"path": F + "/sec", "from": "src5", "to": "sink5"})]
reqs = [{"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "g", "version": "1"}}}]
for i, (_, tool, args) in enumerate(calls):
    reqs.append({"jsonrpc": "2.0", "id": i + 1, "method": "tools/call", "params": {"name": tool, "arguments": args}})
p = subprocess.run([binp, "--mcp", "--mcp-legend=inline"], input="".join(json.dumps(r) + "\n" for r in reqs), capture_output=True, text=True, timeout=120, cwd=F)
got = {}
for line in p.stdout.splitlines():
    try: o = json.loads(line)
    except ValueError: continue
    if isinstance(o.get("id"), int) and o["id"] > 0:
        got[o["id"]] = "".join(c.get("text", "") for c in o.get("result", {}).get("content", []))
for i, (name, _, _) in enumerate(calls):
    open(O + "/" + name, "w").write(got.get(i + 1, ""))
    open(O + "/" + name + ".rc", "w").write(str(p.returncode) + "\n")
PY

# ── the checks ────────────────────────────────────────────────────────────────────────────────────────────────────────
python3 - "$O" "$F" <<'PY'
import os, re, sys
O, F = sys.argv[1], sys.argv[2]
fails = 0
def check(ok, msg):
    global fails
    print("  %s  %s" % ("PASS" if ok else "FAIL", msg))
    fails += 0 if ok else 1
def rd(n):
    p = os.path.join(O, n)
    return open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else ""
def rc(n):
    p = os.path.join(O, n + ".rc")
    return open(p).read().strip() if os.path.exists(p) else "missing"
def ran(n):
    good = rc(n) == "0" and rd(n).strip() != ""
    if not good:
        check(False, "%s: exit %s, %d bytes (the command must answer)" % (n, rc(n), len(rd(n))))
    return good
HOPATTR = r' (?:site|sites|site_by|call|sig|fp|tp)="[^"]*"'
def strip(t):
    t = re.sub(r'<!--.*?-->', '', t, flags=re.S)
    t = re.sub(r' est_tokens="\d+"', ' est_tokens="N"', t)
    t = re.sub(r' hop_(?:nosite|unread|notext|redacted|shed)="[^"]*"', '', t)
    t = re.sub(r'(<e [^>]*?)((?:' + HOPATTR + r')+)(/>)', r'\1\3', t)
    return re.sub(r'(<s t="[^"]*" n="[^"]*" p="[^"]*"[^>]*?)((?:' + HOPATTR + r')+)(/>)', r'\1\3', t)
def rows(t, tag):
    return re.findall(r'<%s [^>]*/>' % tag, t)
def row(t, n):   # the --path hop row naming n
    return next((r for r in rows(t, "s") if (' n="%s"' % n) in r), "")

# (1) identity, with its positive twin
names = ["c_path", "c_macro", "c_far", "c_conn", "cpp_path", "py_path", "pyd_conn", "ts_path", "go_path", "rs_path", "min_path", "crlf_path", "key_path", "self_path", "self_conn",
         "cpp2_path", "cpp2_conn", "py2_path", "qual_b1", "qual_b2", "tsq_b", "tsq_a", "nf_path", "sec4", "sec5", "sec6", "sec7", "sec8", "sec9", "sec10"]
for n in names:
    if ran(n) and ran(n + ".off"):
        check(strip(rd(n)) == strip(rd(n + ".off")), "(1) %s: the answer minus the hop attributes is the kill-switch answer byte for byte" % n)
        check(" site=\"" not in rd(n + ".off") or n == "self_path_none", "(1) %s: RIPWIRE_NO_HOP_CONTEXT=1 prints no site=" % n)
check(all(" site=\"" in rd(n) for n in names), "(1) every default answer above carries site= (the field exists)")
for n in ("py2_alias", "tsa_alias"):   # no site on the hop: the identity holds with sig= alone too
    if ran(n) and ran(n + ".off"):
        check(strip(rd(n)) == strip(rd(n + ".off")), "(1) %s: the answer minus the hop attributes is the kill-switch answer byte for byte" % n)

# (2) per language
t = rd("c_path")
check('site="a.c:12" call="return mid( n ); }" sig="int mid( int n )"' in row(t, "mid"), "(2)/(10) C free call in a one-line caller: site, the statement (not the caller's own head), the callee signature")
check('site="a.c:7" sites="2" call="int r = leaf( n, n + 1 );" sig="int leaf( int a, int b )"' in row(t, "leaf"), "(2) C call over two lines (tab-indented): joined, whitespace collapsed; (6) first of 2 sites, sites=2")
t = rd("c_macro")
check('site="a.c:13" call="return WRAP( n ); }"' in row(t, "WRAP"), "(2) C macro invocation: its site is the invocation line (from the statement)")
check('site="a.c:1" call="helper( x )" sig="static int helper( int v )"' in row(t, "helper"), "(2) C call inside a macro body: the #define line, past the macro's own head")
t = rd("c_far")
check('site="b.c:2"' in row(t, "leaf") and 'sig="int leaf( int a, int b )"' in row(t, "leaf"), "(2) C callee declared in b.c, defined in a.c: sig= from the definition")
t = rd("cpp_path")
check('n="Widget::draw"' in t and 'call="return w-&gt;draw( 3, &quot;café &amp; &lt;ok&gt;&quot; ); }"' in row(t, "Widget::draw"),
      "(2) C++ member call through ->: XML-escaped (<, >, &, quotes), UTF-8 kept")
check('sig="int Widget::draw( int depth, const char* label ) const"' in row(t, "Widget::draw"), "(2) C++ Class::method: the definition's signature, not the header prototype")
t = rd("py_path")
check('site="svc.py:10" call="data = await self.fetch( key, retries=5, …"' in row(t, "Service.fetch"), "(2) Python self.m() await call past 3 lines: joined, the cut marked")
check('sig="async def fetch(self, key: str, *, retries: int = 3) -&gt; bytes:"' in row(t, "Service.fetch"), "(2) Python decorated callee: the def line, not the decorator")
t = rd("ts_path")
check('site="app.ts:7" call="return this.#dispatch(req, 0);" sig="#dispatch(req: Request, depth: number): Response"' in row(t, "App.#dispatch"), "(2) TS this.#private call")
check('via="name" site="app.ts:5"' in row(t, "join") and 'sig="function join(a: string, b: string): string"' in row(t, "join"), "(2) TS namespace call util.join, via=name kept beside site=")
t = rd("go_path")
check('site="m.go:11" call="return t.resultMerger.pattern.MatchItem(&quot;x&quot;, true)" sig="func (p *Pattern) MatchItem(item string, withPos bool) bool"' in row(t, "Pattern.MatchItem"), "(2) Go receiver chain")
t = rd("rs_path")
check('site="lib.rs:11" call="let v: u32 = s.load(&quot;k&quot;).await?;" sig="pub async fn load&lt;T&gt;(&amp;self, key: &amp;str) -&gt; Result&lt;T, String&gt; where T: Default,"' in row(t, "Store::load"),
      "(2) Rust .await? call; impl sig with generics and a where clause on following lines")

# text hazards
t = row(rd("min_path"), "join")
m = re.search(r' call="([^"]*)"', t)
check(bool(m) and m.group(1).startswith("\u2026") and "util.join(&quot;x&quot;" in m.group(1) and len(m.group(1).replace("&quot;", '"').encode()) <= 120 + 3,
      "(2) a 6 KB minified line: call= is a marked window around the call, <= 120 bytes (%s)" % (m.group(1)[:50] if m else "no call="))
check('site="crlf.c:4" call="return leaf( n, 3 );"' in row(rd("crlf_path"), "leaf"), "(2) CRLF file: the call joined across lines, no CR left")
t = row(rd("key_path"), "leaf")
check('[REDACTED:aws-key]' in t and ("AKIA" + "Q" * 4 + "7" * 12) not in rd("key_path"), "(2) a credential-shaped argument in call= is redacted")

# (3) unread / edited / blanked, each with the positive twin above (c_path / c_far print call= and sig=)
for n, why in (("c_unread", "unreadable"), ("c_edited", "edited since the crawl")):
    if ran(n):
        t = rd(n)
        check(' hop_unread="2"' in t and ' call="' not in t and ' sig="' not in t and 'site="a.c:12"' in row(t, "mid") and 'site="a.c:7"' in row(t, "leaf"),
              "(3) a.c %s: call=/sig= withheld on both hops, hop_unread=2, site= kept" % why)
        check('call=""' not in t and 'sig=""' not in t, "(3) %s: never an empty call=/sig=" % n)
if ran("c_blank"):
    t = rd("c_blank")
    check(' hop_notext="1"' in t and ' call="' not in row(t, "leaf") and 'sig="int leaf( int a, int b )"' in row(t, "leaf") and 'site="b.c:2"' in row(t, "leaf"),
          "(3) b.c's site text no longer spells leaf: call= withheld (hop_notext=1), sig= from a.c kept, site= kept")
    check("hop_notext=N" in t, "(3) hop_notext= is defined in that answer's legend")

# (4) shed ladder over falling ceilings: hop sig= goes first, then call=, then site=, and only then (as before the lane) the join
#     sigs and the legs; at the deepest hop shed every <e> row and every join sig= still prints
ceil = [int(x) for x in rd("shed_list").split()]
lad = [(k, rd("c_shed_%d" % k)) for k in ceil]
if all(ran("c_shed_%d" % k) for k in ceil):
    lvl = lambda t: (re.search(r'<connect [^>]*hop_shed="([^"]*)"', t) or re.search(r'$', "")).group(1) if re.search(r'<connect [^>]*hop_shed="', t) else ""
    order = {"": 0, "sig": 1, "sig,call": 2, "sig,call,site": 3}
    seq = [order[lvl(t)] for _, t in lad]
    check(seq == sorted(seq) and set(seq) == {0, 1, 2, 3}, "(4) falling ceilings walk full -> sig -> sig,call -> sig,call,site, never back (%s)" % sorted(set(seq)))
    full = lad[0][1]
    ne = len(rows(full, "e"))
    jsig = len(re.findall(r'<s [^>]* sig="', full))
    first = {o: next((t for _, t in lad if order[lvl(t)] == o), "") for o in (1, 2, 3)}
    check(re.search(r'<e [^>]* sig="', full) is not None and ne > 0 and jsig > 0, "(4) the unbudgeted answer has an <e sig=>, %d <e> rows, %d join sigs" % (ne, jsig))
    check(not re.search(r'<e [^>]* sig="', first[1]) and ' call="' in first[1] and len(rows(first[1], "e")) == ne, "(4) hop_shed=sig: no <e sig=>, call= kept, every <e> row kept")
    check(' call="' not in first[2] and first[2].count(' site="') == full.count(' site="') and len(rows(first[2], "e")) == ne, "(4) hop_shed=sig,call: no call=, every site= and <e> row kept")
    check(' site="' not in first[3] and len(rows(first[3], "e")) == ne and len(re.findall(r'<s [^>]* sig="', first[3])) == jsig and 'truncated=' not in first[3],
          "(4) hop_shed=sig,call,site: the hop attributes go before any join sig or leg (%d <e>, %d join sigs, no truncated=)" % (len(rows(first[3], "e")), len(re.findall(r'<s [^>]* sig="', first[3]))))
    check(all("hop_shed=" in "".join(re.findall(r'<!--.*?-->', first[o], re.S)) for o in (1, 2, 3)), "(4) hop_shed= is defined in the legend of each answer that carries it")
    check(all(t.count('<e ') or 'truncated="paths"' in t for _, t in lad), "(4) an answer that lost <e> rows says truncated=paths")

# (5) dedupe: the two get -> async_handle rows differ by tp=
t = rd("pyd_conn")
e = [r for r in rows(t, "e") if 'f="get" t="async_handle"' in r]
check(len(e) == 2 and e[0] != e[1] and all(' tp="ws.py:' in r for r in e) and all(' site="ws.py:10"' in r for r in e),
      "(5) two <e f=get t=async_handle> rows: same site, told apart by tp= (%d rows)" % len(e))

# (7) legend: each attribute present is defined in the answer's own legend (compact default and full)
for n in names:
    for v in (n, n + ".full"):
        if not ran(v):
            continue
        t = rd(v)
        leg = "".join(re.findall(r'<!--.*?-->', t, re.S))
        body = re.sub(r'<!--.*?-->', '', t, flags=re.S)
        missing = [a for a in ("site", "sites", "site_by", "call", "sig", "tp", "hop_nosite", "hop_unread", "hop_notext", "hop_redacted")
                   if re.search(r'<(?:e|s|path|connect) [^>]* %s="' % a, body) and (a + "=") not in leg]
        check(not missing, "(7) %s: every hop attribute it prints is defined in its legend%s" % (v, (" (missing: " + ",".join(missing) + ")") if missing else ""))
m = rd("mcp_c_path")
check(m != "" and rows(m, "s") == rows(rd("c_path"), "s"), "(7) MCP path_between prints the CLI's hop rows byte for byte")
m = rd("mcp_pyd_conn")
check(m != "" and rows(m, "e") == rows(rd("pyd_conn"), "e"), "(7) MCP connect prints the CLI's <e> rows byte for byte")

# (6) the pick: owner first, an arity misfit last, a namesake tie and a misfit disclosed (review S1/S2)
t = rd("cpp2_path")
check('site="m.cpp:8" sites="2" call="int y = b.get( 2, 3 );" sig="int B::get( int k, int j )"' in row(t, "B::get") and "site_by=" not in t,
      "(6) caller -> B::get: the call whose argument count B::get accepts (b.get( 2, 3 )), not the first same-named one; decided, no site_by=")
e = rows(rd("cpp2_conn"), "e")
check(len(e) == 2 and any('tp="m.cpp:3" site="m.cpp:7"' in r and 'call="int x = a.get( 1 );"' in r for r in e)
      and any('tp="m.cpp:4" site="m.cpp:8"' in r and 'call="int y = b.get( 2, 3 );"' in r for r in e),
      "(6) --connect=A::get,B::get: each <e> row its own call (m.cpp:7 for A::get, m.cpp:8 for B::get), not one site twice")
t = row(rd("py2_path"), "Cache.fetch")
check('site="app.py:5" sites="2" site_by="first"' in t, "(6) Python s.fetch / c.fetch (an implicit receiver: arity cannot decide): the first site, the tie disclosed (site_by=first)")
check('site="q.cpp:7"' in row(rd("qual_b1"), "W::make") and 'call="return a + ns::W::make( 7 ); }"' in row(rd("qual_b1"), "W::make"),
      "(6) b1 -> ns::W::make: the call qualified by the owner (ns::W::make, line 7), not the earlier O::make (line 6)")
check('site="q.cpp:10"' in row(rd("qual_b2"), "W::make"), "(6) b2 -> W::make (namespace dropped): the owner-qualified call (line 10), not O::make")
check('site="q.ts:5"' in row(rd("tsq_b"), "B.make") and 'site="q.ts:4"' in row(rd("tsq_a"), "A.make"),
      "(6) TS A.make / B.make (owner by containment, no stored scope): each row its own class's call")
check('site="n.cpp:5" site_by="nofit" call="return c.get( 1 );"' in row(rd("nf_path"), "C::get"),
      "(6) c.get( 1 ) beside C::get( a, b, c ): the only name match, its arity misfit disclosed (site_by=nofit)")
for n in ("py2_path", "nf_path"):
    leg = "".join(re.findall(r'<!--.*?-->', rd(n), re.S))
    check("site_by=" in leg and "site_by=" in "".join(re.findall(r'<!--.*?-->', rd(n + ".full"), re.S)), "(6) %s: site_by= is defined in its compact and full legend" % n)
check(rd("cpp2_path").count(' site="') > 0 and "site_by=" not in "".join(re.findall(r'<!--.*?-->', rd("cpp2_path"), re.S)),
      "(6) cpp2_path prints site= and no site_by=, so its legend carries no site_by= (present-only)")

# (9) credentials a cut would split: no 12-byte run of a token body anywhere, every REDACTED marker whole; CLI + MCP
body, gen = (open(os.path.join(F, "sec", "tokens")).read().split("\n") + ["", ""])[:2]
def leaks(t):
    return [x[:4] + "..." for x in (body, gen) for i in range(len(x) - 11) if x[i:i + 12] in t][:1]
def markers_whole(t):
    return all(re.match(r'\[REDACTED:[a-z-]+\]', t[m.start() - 1:]) for m in re.finditer(r'REDACTED', t))
check(len(body) == 36 and len(gen) == 600, "(9) the runtime tokens were written (%d, %d bytes)" % (len(body), len(gen)))
for n in ("sec4", "sec5", "sec6", "sec7", "sec8", "sec9", "sec10", "mcp_sec4_path", "mcp_sec4_conn", "mcp_sec5_path"):
    if (n.startswith("mcp_") and rd(n) != "") or (not n.startswith("mcp_") and ran(n)):
        t = rd(n)
        check(" site=\"" in t and not leaks(t) and markers_whole(t), "(9) %s: a site prints, no 12-byte run of the token, every [REDACTED:kind] whole%s" % (n, (" (leak " + leaks(t)[0] + ")") if leaks(t) else ""))
    else:
        check(False, "(9) %s: the command must answer (%d bytes)" % (n, len(rd(n))))
for n in ("sec4", "mcp_sec4_path", "mcp_sec4_conn", "sec8"):
    check(re.search(r' call="[^"]*\[REDACTED:github-token\]', rd(n)) is not None, "(9) %s: call= prints with the token redacted whole (positive twin)" % n)
check(re.search(r' call="[^"]*sink10\(1, &quot;[^"]*\[REDACTED:secret\]', rd("sec10")) is not None,
      "(9) sec10: a run gated by a keyword the window dropped (same line, past 512 B) is still redacted in call=")
for n in ("sec5", "sec6", "sec7"):
    check(re.search(r' call="[^"]*sink[567]\(', rd(n)) is not None, "(9) %s: call= still prints the call (the cut moved off the token, the call kept)" % n)
t = rd("sec9")
check(' hop_redacted="1"' in t and ' call="' not in row(t, "sink9") and 'site="w9.js:2"' in row(t, "sink9") and "hop_redacted=N" in t,
      "(9) sec9: the callee name inside a redacted run: call= withheld, hop_redacted=1 counted and defined, site= kept")

# (10) a hop with no site still prints sig= (review S3); the legend defines what prints
for n, sig in (("py2_alias", 'sig="def compute(a, b):"'), ("tsa_alias", 'sig="function compute(a: number, b: number): number"')):
    if ran(n):
        t = rd(n)
        r = row(t, "compute")
        check(sig in r and ' site="' not in r and ' hop_nosite="1"' in t, "(10) %s: no site (an import alias), hop_nosite=1, the callee's sig= still prints" % n)
        leg = "".join(re.findall(r'<!--.*?-->', t, re.S))
        check("sig=" in leg and "hop_nosite=" in leg, "(10) %s: sig= and hop_nosite= are defined in its legend" % n)

# (8) hoisting: one reference scan per answer, each file read once
for n, edges in (("chain_path", 40), ("chain_conn", 39)):
    if ran(n):
        err = rd(n + ".err")
        m = re.search(r'hop facts: edges=(\d+) reference_scans=(\d+) files_read=(\d+)', err)
        check(bool(m) and int(m.group(1)) >= edges and m.group(2) == "1" and int(m.group(3)) <= 4,
              "(8) %s: %s edges, ONE reference scan, <= 4 files read (%s)" % (n, m.group(1) if m else "?", m.group(0) if m else "no stats line"))
        check(rd(n).count(' site="') >= edges, "(8) %s: every hop printed a site (%d)" % (n, rd(n).count(' site="')))
sys.exit(1 if fails else 0)
PY
st=$?
if [ "$st" -eq 0 ]; then echo "hopcontextcheck: PASS"; exit 0; fi
echo "hopcontextcheck: FAIL"; exit 1
