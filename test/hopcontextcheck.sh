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
#   (6) cap       — a caller with two calls of the callee prints the first site and sites="2"
#   (7) legend    — every hop attribute the answer prints is defined (name=) in its own legend, compact and full; MCP
#                   path_between and connect print the CLI's hop rows byte for byte
#   (8) hoisting  — a 40-hop --path and a 14-terminal --connect each make ONE reference scan (RIPWIRE_HOP_STATS), files read
#                   once each
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
mkdir -p "$F/c" "$F/cpp" "$F/py" "$F/ts" "$F/go" "$F/rs" "$F/pyd" "$F/chain"

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
printf '%s\n' "${SHED_T[@]}" > "$O/shed_list"
# (8) hoisting
run chain_path "$F/chain" RIPWIRE_HOP_STATS=1 -- --path=f0,f40
run chain_conn "$F/chain" RIPWIRE_HOP_STATS=1 -- --connect=f0,f3,f6,f9,f12,f15,f18,f21,f24,f27,f30,f33,f36,f39

# MCP twins (arm 7)
python3 - "$BIN" "$F" "$O" <<'PY'
import json, subprocess, sys
binp, F, O = sys.argv[1:4]
calls = [("mcp_c_path", "path_between", {"path": F + "/c", "from": "top", "to": "leaf"}),
         ("mcp_pyd_conn", "connect", {"path": F + "/pyd", "symbols": ["AuthPhase.async_handle", "ActiveConnection.async_handle"]})]
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
python3 - "$O" <<'PY'
import os, re, sys
O = sys.argv[1]
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
HOPATTR = r' (?:site|sites|call|sig|fp|tp)="[^"]*"'
def strip(t):
    t = re.sub(r'<!--.*?-->', '', t, flags=re.S)
    t = re.sub(r' est_tokens="\d+"', ' est_tokens="N"', t)
    t = re.sub(r' hop_(?:nosite|unread|notext|shed)="[^"]*"', '', t)
    t = re.sub(r'(<e [^>]*?)((?:' + HOPATTR + r')+)(/>)', r'\1\3', t)
    return re.sub(r'(<s t="[^"]*" n="[^"]*" p="[^"]*"[^>]*?)((?:' + HOPATTR + r')+)(/>)', r'\1\3', t)
def rows(t, tag):
    return re.findall(r'<%s [^>]*/>' % tag, t)
def row(t, n):   # the --path hop row naming n
    return next((r for r in rows(t, "s") if (' n="%s"' % n) in r), "")

# (1) identity, with its positive twin
names = ["c_path", "c_macro", "c_far", "c_conn", "cpp_path", "py_path", "pyd_conn", "ts_path", "go_path", "rs_path", "self_path", "self_conn"]
for n in names:
    if ran(n) and ran(n + ".off"):
        check(strip(rd(n)) == strip(rd(n + ".off")), "(1) %s: the answer minus the hop attributes is the kill-switch answer byte for byte" % n)
        check(" site=\"" not in rd(n + ".off") or n == "self_path_none", "(1) %s: RIPWIRE_NO_HOP_CONTEXT=1 prints no site=" % n)
check(all(" site=\"" in rd(n) for n in names), "(1) every default answer above carries site= (the field exists)")

# (2) per language
t = rd("c_path")
check('site="a.c:12" call="int top( int n ) { return mid( n ); }" sig="int mid( int n )"' in row(t, "mid"), "(2) C free call: site, the call line, the callee signature")
check('site="a.c:7" sites="2" call="int r = leaf( n, n + 1 );" sig="int leaf( int a, int b )"' in row(t, "leaf"), "(2) C call over two lines (tab-indented): joined, whitespace collapsed; (6) first of 2 sites, sites=2")
t = rd("c_macro")
check('site="a.c:13" call="int viamacro( int n ) { return WRAP( n ); }"' in row(t, "WRAP"), "(2) C macro invocation: its site is the invocation line")
check('site="a.c:1" call="#define WRAP( x ) helper( x )" sig="static int helper( int v )"' in row(t, "helper"), "(2) C call inside a macro body: the #define line")
t = rd("c_far")
check('site="b.c:2"' in row(t, "leaf") and 'sig="int leaf( int a, int b )"' in row(t, "leaf"), "(2) C callee declared in b.c, defined in a.c: sig= from the definition")
t = rd("cpp_path")
check('n="Widget::draw"' in t and 'call="int render( const ns::Widget* w ) { return w-&gt;draw( 3, &quot;café &amp; &lt;ok&gt;&quot; ); }"' in row(t, "Widget::draw"),
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
        missing = [a for a in ("site", "sites", "call", "sig", "tp", "hop_nosite", "hop_unread", "hop_notext")
                   if re.search(r'<(?:e|s|path|connect) [^>]* %s="' % a, body) and (a + "=") not in leg]
        check(not missing, "(7) %s: every hop attribute it prints is defined in its legend%s" % (v, (" (missing: " + ",".join(missing) + ")") if missing else ""))
m = rd("mcp_c_path")
check(m != "" and rows(m, "s") == rows(rd("c_path"), "s"), "(7) MCP path_between prints the CLI's hop rows byte for byte")
m = rd("mcp_pyd_conn")
check(m != "" and rows(m, "e") == rows(rd("pyd_conn"), "e"), "(7) MCP connect prints the CLI's <e> rows byte for byte")

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
