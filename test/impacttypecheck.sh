#!/usr/bin/env bash
# impacttypecheck.sh — L7 type-use impact (src/typeuse.h): --impact of a class / struct / named type / interface starts its
# walk from the symbols that NAME the type (a parser-read type position), not from call edges alone.
#
# THE DEFECT. --impact walked CALL edges into SYM only. A struct has no callers, so `--impact=grid_cell` on tmux answered
# reaches="0" while 32 files declare, copy or access the struct; a TS class never listed the file defining it, nor a
# function that only takes it as a parameter. Arms (1) (4)-(10) and (11)-(13) are RED on the pre-L7 binary.
#
# FIXTURES (written below, one directory per language so each arm's corpus is its own):
#   c/     struct cell in cell.h; a.c (pointer param + field write; a_caller calls a_set), b.c (copy through two params),
#          c.c (a local of the type); fnonly.c (functions only) and comment.c (the word in a comment and as a VARIABLE
#          name, never as a type) — the two files that must NOT be listed.
#   cnode/ struct node AND a function node() (C keeps tags and functions apart): uses.c names the struct, calls.c only
#          calls the function.
#   cdup/  two `struct cell` definitions in two files (type_defs="2").
#   cpp/   class Widget; p.cpp (param), m.cpp (member of Holder), r.cpp (return type), d.cpp (base class); nm.cpp holds a
#          PARAMETER named Widget (a value, not a type); ctor.cpp only constructs one (`Widget()`, a CALL edge: listed at
#          d=1, never via="type").
#   ts/    interface Router + TrieRouter implements Router (DECISION: an implementor is impact — it names the interface in
#          its implements clause, and changing the interface breaks it) + run( r: Router ); class HttpErr with instanceof,
#          extends and throw-new users; fnonly.ts.
#   js/    class Base; inst.js (instanceof), sub.js (extends).
#   go/ rs/ py/ java/: a type, a function taking it, a function-only file.
#   gp*: a GENERIC TYPE PARAMETER spelled like the type (C++ `template <class Widget>`, Rust `fn g<Cell>`, TS
#          `function g<Router>`, Go `func g[Cell any]`, Java `<Cell> Cell g`) — inside that scope the name is the
#          parameter, not the type, so the file is never listed (arm 19).
#
# ARMS
#   (1) C struct: rf rows cell.h d="0", a.c b.c c.c d="1" via="type"; fnonly.c and comment.c absent; reaches>0; the
#       symbol rows hold a_set/b_copy/c_read at d=1 and a_caller at d=2; type_users="3".
#   (2) near miss — a FUNCTION impact (--impact=a_set): no <files> element, no type_users=, no TYPE IMPACT clause.
#   (3) a type named like a function: --impact=node (defs=2) lists uses.c via="type" and calls.c at d=1 WITHOUT
#       via="type" (a call, not a type mention).
#   (4) C++: p.cpp m.cpp r.cpp d.cpp listed via="type"; nm.cpp absent; ctor.cpp d=1 without via="type".
#   (5) TS interface: impl.ts (implementor) and use.ts listed via="type"; fnonly.ts absent.
#   (6) TS class: inst.ts (instanceof) and sub.ts (extends) via="type"; err.ts at d="0".
#   (7) JS: inst.js and sub.js via="type".
#   (8) Go, (9) Rust, (10) Python (annotation + base class), (10b) Java: the user file via="type", fnonly absent.
#   (11) MCP impact twin: the <files> element is byte-identical to the CLI's.
#   (12) --json: files.rows carry the d=0 row and "via":"type"; files.type_users equals the XML's.
#   (13) type_defs="2" on the two-definition corpus, and its legend sentence rides.
#   (14) legend: --legend=full carries the TYPE IMPACT clause on a type impact only; no "--" inside the legend comment.
#   (15) --limit=2 beats the first-hop band: shown_files="2" files_capped="1" with files_next=.
#   (16) determinism: two runs byte-identical.
#   (18) a class only CONSTRUCTED from 25 files (call edges, no type mention) keeps the 20-row default window.
#   FLOORS (no row, no arm: the tier has no clause to read; the legend names them): a Python STRING annotation
#          (`c: "Cell"`), a qualified Python base (`mod.Base`), a Go type satisfying an interface IMPLICITLY.
#   (19) generic-parameter namesakes: every gp* file is absent from its language's rollup (arms 4, 5, 8, 9, 10b).
#   (17) the first-hop band: 25 files naming a struct + its header = 26 rows listed with no --limit (default cap is 20).
#   (22) --format=columnar: the <by_type> column marks the rows reached only through a type mention (the form has no
#        <files> rollup), a call-reached row reads 0, both legends define it; a function impact carries neither.
#
# Usage: bash test/impacttypecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/impacttypecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "impacttypecheck: $BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
mk() { mkdir -p "$( dirname "$TMP/$1" )"; cat >"$TMP/$1"; }

mk c/cell.h <<'EOF'
struct cell { int fg; int bg; };
EOF
mk c/a.c <<'EOF'
#include "cell.h"
void a_set( struct cell *gc ) { gc->fg = 1; }
void a_caller( void ) { a_set( 0 ); }
EOF
mk c/b.c <<'EOF'
#include "cell.h"
void b_copy( struct cell *dst, const struct cell *src ) { *dst = *src; }
EOF
mk c/c.c <<'EOF'
#include "cell.h"
int c_read( void ) { struct cell gc; gc.bg = 2; return gc.bg; }
EOF
mk c/fnonly.c <<'EOF'
int f_only( int x ) { return x + 1; }
EOF
mk c/comment.c <<'EOF'
/* this file talks about struct cell in a comment only */
int g_count( int cell ) { return cell * 2; }
EOF

mk cnode/node.h <<'EOF'
struct node { int v; };
int node( int x );
EOF
mk cnode/impl.c <<'EOF'
int node( int x ) { return x; }
EOF
mk cnode/uses.c <<'EOF'
#include "node.h"
int n_get( struct node *n ) { return n->v; }
EOF
mk cnode/calls.c <<'EOF'
#include "node.h"
int n_call( void ) { return node( 3 ); }
EOF

mk cdup/one/cell.h <<'EOF'
struct cell { int a; };
EOF
mk cdup/two/cell.h <<'EOF'
struct cell { int b; };
EOF
mk cdup/use.c <<'EOF'
int d_use( struct cell *p ) { return p != 0; }
EOF

mk cpp/w.h <<'EOF'
class Widget { public: int v; };
EOF
mk cpp/p.cpp <<'EOF'
#include "w.h"
int take( const Widget& w ) { return w.v; }
EOF
mk cpp/m.cpp <<'EOF'
#include "w.h"
struct Holder { Widget w; };
int hold( Holder& h ) { return h.w.v; }
EOF
mk cpp/r.cpp <<'EOF'
#include "w.h"
Widget* lookup() { return 0; }
EOF
mk cpp/ctor.cpp <<'EOF'
#include "w.h"
int build_one() { Widget(); return 0; }
EOF
mk cpp/d.cpp <<'EOF'
#include "w.h"
class Derived : public Widget { public: int more; };
EOF
mk cpp/nm.cpp <<'EOF'
int count_widgets( int Widget ) { return Widget + 1; }
EOF

mk ts/router.ts <<'EOF'
export interface Router { match( m: string ): string }
EOF
mk ts/impl.ts <<'EOF'
import { Router } from './router'
export class TrieRouter implements Router { match( m: string ) { return m } }
EOF
mk ts/use.ts <<'EOF'
import { Router } from './router'
export function run( r: Router ) { return r.match( 'x' ) }
EOF
mk ts/err.ts <<'EOF'
export class HttpErr extends Error { code = 1 }
EOF
mk ts/inst.ts <<'EOF'
import { HttpErr } from './err'
export function isIt( e: unknown ) { return e instanceof HttpErr }
EOF
mk ts/sub.ts <<'EOF'
import { HttpErr } from './err'
export class SubErr extends HttpErr { more = 2 }
EOF
mk ts/fnonly.ts <<'EOF'
export function plain( x: number ) { return x + 1 }
EOF

mk js/base.js <<'EOF'
export class Base { constructor() { this.k = 1 } }
EOF
mk js/inst.js <<'EOF'
import { Base } from './base'
export function isBase( e ) { return e instanceof Base }
EOF
mk js/sub.js <<'EOF'
import { Base } from './base'
export class Sub extends Base { more() { return 2 } }
EOF

mk go/cell.go <<'EOF'
package cells

type Cell struct{ X int }
EOF
mk go/use.go <<'EOF'
package cells

func Use( c *Cell ) int { return c.X }
EOF
mk go/fnonly.go <<'EOF'
package cells

func Plain( x int ) int { return x + 1 }
EOF

mk rs/lib.rs <<'EOF'
pub struct Cell { pub x: i32 }
EOF
mk rs/use_cell.rs <<'EOF'
use crate::Cell;
pub fn use_cell( c: &Cell ) -> i32 { c.x }
EOF
mk rs/gp.rs <<'EOF'
pub fn generic_rs<Cell>( c: Cell ) -> Cell { c }
pub struct Wrap<Cell: Clone> { pub inner: Cell }
EOF
mk cpp/gp.cpp <<'EOF'
template <class Widget> int genericW( Widget w ) { return 0; }
template <typename Widget = int> struct Box { Widget held; };
EOF
mk ts/gp.ts <<'EOF'
export function genericTs<Router>( r: Router ): Router { return r; }
EOF
mk go/gp.go <<'EOF'
package cells
func GenericGo[Cell any]( c Cell ) Cell { return c }
EOF
mk java/Gp.java <<'EOF'
public class Gp { static <Cell> Cell g( Cell c ) { return c; } }
EOF
mk rs/fnonly.rs <<'EOF'
pub fn plain( x: i32 ) -> i32 { x + 1 }
EOF

# rsimpl/: a trait and a struct whose `impl` headers sit on their own line (the rustfmt shape): the header names the type,
# but no indexed definition covers that line — the methods inside the block are the users.
mk rsimpl/lib.rs <<'EOF'
pub trait Shape {
    fn area(&self) -> i32;
}

pub struct Sq {
    s: i32,
}

impl Shape for Sq {
    fn area(&self) -> i32 {
        self.s * self.s
    }
}

impl Sq {
    fn side(&self) -> i32 {
        self.s
    }
}
EOF
mk rsimpl/tri.rs <<'EOF'
use crate::Shape;
pub struct Tri {
    b: i32,
}

impl Shape for Tri {
    fn area(&self) -> i32 {
        self.b / 2
    }
}
EOF
mk rsimpl/empty.rs <<'EOF'
pub struct Marker;
impl crate::Shape for Marker {}
EOF

# rsstd/ cppstd/: a local type named like a standard-library type. A path rooted at the standard library (std::io::Error,
# std::fmt::Error, std::vector) never names the in-tree type; a crate-rooted or bare spelling does.
mk rsstd/lib.rs <<'EOF'
pub struct Error {
    code: i32,
}

pub fn read_it() -> std::io::Error {
    std::io::Error::other("x")
}

pub fn fmt_it(e: &std::fmt::Error) -> i32 {
    0
}

pub fn core_it(e: core::fmt::Error) -> i32 {
    0
}

pub fn mine(e: &Error) -> i32 {
    e.code
}

pub fn via_crate(e: &crate::Error) -> i32 {
    e.code
}
EOF
mk cppstd/v.h <<'EOF'
struct vector { int n; };
EOF
mk cppstd/use.cpp <<'EOF'
#include "v.h"
int sum_std( const std::vector<int>& v ) { return 0; }
int sum_chrono( std::chrono::duration<int> d ) { return 0; }
int mine( const vector& v ) { return v.n; }
int via_global( const ::vector& v ) { return v.n; }
EOF

mk py/cell.py <<'EOF'
class Cell:
    x = 1
EOF
mk py/use.py <<'EOF'
from cell import Cell
def use( c: Cell ) -> int:
    return c.x
EOF
mk py/sub.py <<'EOF'
from cell import Cell
class Sub( Cell ):
    y = 2
EOF
mk py/fnonly.py <<'EOF'
# Cell is mentioned in this comment only
def plain( x ):
    Cell = x
    return Cell
EOF

mk java/Cell.java <<'EOF'
public class Cell { public int x; }
EOF
mk java/Use.java <<'EOF'
public class Use { static int use( Cell c ) { return c.x; } }
EOF
mk java/Plain.java <<'EOF'
public class Plain { static int plain( int x ) { return x + 1; } }
EOF

# band/: one struct and 25 files that each name it — more d=1 files than the rollup's default 20 (arm 17)
mkdir -p "$TMP/band"; printf 'struct wide { int v; };\n' >"$TMP/band/wide.h"
for i in $( seq -w 1 25 ); do printf 'int use_%s( struct wide *w ) { return w->v; }\n' "$i" >"$TMP/band/u$i.c"; done
# callband/: a Python class only CONSTRUCTED (call edges) from 25 files — no type mention, so no band (arm 18)
mkdir -p "$TMP/callband"; printf 'class Made:\n    pass\n' >"$TMP/callband/made.py"
for i in $( seq -w 1 25 ); do printf 'from made import Made\ndef mk_%s():\n    return Made()\n' "$i" >"$TMP/callband/c$i.py"; done

BIN="$BIN" FIX="$TMP" python3 - <<'PY'
import json, os, re, shutil, subprocess, sys

BIN, FIX = os.environ["BIN"], os.environ["FIX"]
fail = [0]
def ok(m): print("  PASS  " + m)
def no(m): print("  FAIL  " + m); fail[0] = 1

def run(d, *args):
    p = subprocess.run([BIN, ".", "--no-cache"] + list(args), cwd=os.path.join(FIX, d), capture_output=True, text=True, timeout=300)
    if p.returncode != 0:
        no("%s %s exited %d: %s" % (d, " ".join(args), p.returncode, p.stderr[-300:]))
    return p.stdout

def root(doc):
    m = re.search(r"<impact ([^>]*)>", doc)
    return dict(re.findall(r'(\w[\w-]*)="([^"]*)"', m.group(1))) if m else None

def files_el(doc):
    m = re.search(r"<files [^>]*>.*?</files>", doc)
    return m.group(0) if m else ""

def rf(doc):
    """{path: attrs} of the <rf> rows"""
    return {a["p"]: a for a in (dict(re.findall(r'(\w[\w-]*)="([^"]*)"', r)) for r in re.findall(r"<rf [^>]*/>", files_el(doc)))}

def srows(doc):
    body = doc[doc.index("<impact "):] if "<impact " in doc else ""
    out, d = [], None
    for r in re.findall(r"<s [^>]*/>", body):
        m = re.search(r' d="(\d+)"', r)
        d = m.group(1) if m else d
        out.append((re.search(r' n="([^"]*)"', r).group(1), d))
    return out

def typed_arm(label, d, sym, defs, users, absent, untyped=()):
    doc = run(d, "--impact=" + sym)
    a, rows = root(doc) or {}, rf(doc)
    reaches = a.get("reaches", "")
    bad = []
    if not reaches.isdigit() or int(reaches) == 0:
        bad.append("reaches=%r" % reaches)
    for f in defs:
        if rows.get(f, {}).get("d") != "0":
            bad.append("%s not d=0 (%r)" % (f, rows.get(f)))
    for f in users:
        r = rows.get(f, {})
        if r.get("d") != "1" or r.get("via") != "type":
            bad.append("%s not d=1 via=type (%r)" % (f, r))
    for f in untyped:
        r = rows.get(f, {})
        if r.get("d") != "1" or r.get("via") == "type":
            bad.append("%s not a plain d=1 row (%r)" % (f, r))
    for f in absent:
        if f in rows:
            bad.append("%s listed (%r)" % (f, rows[f]))
    if bad:
        no("%s --impact=%s: %s" % (label, sym, "; ".join(bad)))
    else:
        ok("%s --impact=%s: reaches=%s, rf %s" % (label, sym, reaches, ", ".join("%s d=%s%s" % (p, r["d"], " via=type" if r.get("via") == "type" else "") for p, r in sorted(rows.items()))))
    return doc

# (1) C struct
c1 = typed_arm("(1) C struct", "c", "cell", ["cell.h"], ["a.c", "b.c", "c.c"], ["fnonly.c", "comment.c"])
sr = dict(srows(c1))
fe = re.search(r"<files [^>]*>", c1)
if sr.get("a_set") == "1" and sr.get("b_copy") == "1" and sr.get("c_read") == "1" and sr.get("a_caller") == "2" and fe and 'type_users="3"' in fe.group(0):
    ok("(1b) symbol rows: a_set/b_copy/c_read d=1, a_caller d=2; type_users=\"3\"")
else:
    no("(1b) symbol rows %r files %r" % (sr, fe and fe.group(0)))

# (2) near miss: a function impact carries none of it
f2 = run("c", "--impact=a_set", "--legend=full")
a2 = root(f2) or {}
if a2.get("reaches") == "1" and "<files " not in f2 and "type_users" not in f2 and "TYPE IMPACT" not in f2:
    ok("(2) --impact=a_set (a function): reaches=1, no <files>, no type_users=, no TYPE IMPACT clause")
else:
    no("(2) function impact reaches=%r files=%s type_users=%s clause=%s" % (a2.get("reaches"), "<files " in f2, "type_users" in f2, "TYPE IMPACT" in f2))

# (3) a type named like a function
d3 = typed_arm("(3) struct node + node()", "cnode", "node", ["node.h"], ["uses.c"], [], untyped=["calls.c"])
if (root(d3) or {}).get("defs") != "3":
    no("(3b) defs=%r, expected 3 (the struct, the prototype and the function)" % (root(d3) or {}).get("defs"))
else:
    ok("(3b) defs=\"3\": every definition seeds; only the struct's mentions are via=\"type\"")

typed_arm("(4) C++ class", "cpp", "Widget", ["w.h"], ["p.cpp", "m.cpp", "r.cpp", "d.cpp"], ["nm.cpp", "gp.cpp"], untyped=["ctor.cpp"])
typed_arm("(5) TS interface + implementor", "ts", "Router", ["router.ts"], ["impl.ts", "use.ts"], ["fnonly.ts", "err.ts", "gp.ts"])
typed_arm("(6) TS class", "ts", "HttpErr", ["err.ts"], ["inst.ts", "sub.ts"], ["fnonly.ts", "router.ts"])
typed_arm("(7) JS class", "js", "Base", ["base.js"], ["inst.js", "sub.js"], [])
typed_arm("(8) Go struct", "go", "Cell", ["cell.go"], ["use.go"], ["fnonly.go", "gp.go"])
typed_arm("(9) Rust struct", "rs", "Cell", ["lib.rs"], ["use_cell.rs"], ["fnonly.rs", "gp.rs"])
typed_arm("(10) Python class", "py", "Cell", ["cell.py"], ["use.py", "sub.py"], ["fnonly.py"])
typed_arm("(10b) Java class", "java", "Cell", ["Cell.java"], ["Use.java"], ["Plain.java", "Gp.java"])

# (11) the MCP twin
req = "\n".join([json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize"}),
                 json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "impact",
                            "arguments": {"path": os.path.join(FIX, "c"), "symbol": "cell", "legend": "full"}}})]) + "\n"
p = subprocess.run([BIN, "--mcp"], input=req, capture_output=True, text=True, timeout=300)
try:
    mt = json.loads(p.stdout.strip().splitlines()[-1])["result"]["content"][0]["text"]
    cli = run("c", "--impact=cell", "--legend=full")
    clause = re.search(r"TYPE IMPACT [^.]*\.", cli)
    if files_el(mt) and files_el(mt) == files_el(cli) and clause and clause.group(0) in mt:
        ok("(11) MCP impact: the <files> element and the TYPE IMPACT clause equal the CLI's")
    else:
        no("(11) MCP files=%r CLI files=%r clause-shared=%s" % (files_el(mt)[:200], files_el(cli)[:200], bool(clause and clause.group(0) in mt)))
except Exception as e:
    no("(11) MCP impact answered nothing parseable: %s / %s" % (e, p.stdout[-300:]))

# (12) --json
try:
    j = json.loads(run("c", "--impact=cell", "--json"))
    fr = {r["p"]: r for r in j["files"]["rows"]}
    if fr.get("cell.h", {}).get("d") == 0 and fr.get("a.c", {}).get("via") == "type" and j["files"].get("type_users") == 3:
        ok("(12) --json: cell.h d=0, a.c via=type, type_users=3")
    else:
        no("(12) --json files %r" % j.get("files"))
except Exception as e:
    no("(12) --json unparseable: %s" % e)

# (13) two definitions share the name
d13 = run("cdup", "--impact=cell", "--legend=full")
fe = re.search(r"<files [^>]*>", d13)
if fe and 'type_defs="2"' in fe.group(0) and "type_defs=K: K indexed type definitions share that name" in d13 and rf(d13).get("use.c", {}).get("via") == "type":
    ok("(13) two struct cell definitions: type_defs=\"2\" and its sentence ride; use.c via=\"type\"")
else:
    no("(13) cdup files=%r sentence=%s" % (fe and fe.group(0), "type_defs=K" in d13))

# (14) legend wording, and no double hyphen inside the legend comment
full = run("c", "--impact=cell", "--legend=full")
comments = re.findall(r"<!--(.*?)-->", full, re.S)
if "TYPE IMPACT" in full and all("--" not in c for c in comments):
    ok("(14) --legend=full: the TYPE IMPACT clause rides; no '--' inside any legend comment")
else:
    no("(14) clause=%s double-hyphen=%s" % ("TYPE IMPACT" in full, [c for c in comments if "--" in c][:1]))
if shutil.which("xmllint"):
    x = subprocess.run(["xmllint", "--noout", "-"], input="<r>" + full + "</r>", capture_output=True, text=True)
    (ok if x.returncode == 0 else no)("(14b) xmllint: the full type-impact answer is well-formed (rc=%d %s)" % (x.returncode, x.stderr[:200]))
else:
    print("  SKIP  (14b) xmllint not installed")

# (15) --limit beats the band
l15 = run("c", "--impact=cell", "--limit=2")
fe = re.search(r"<files [^>]*>", l15)
fa = dict(re.findall(r'(\w[\w-]*)="([^"]*)"', fe.group(0))) if fe else {}
if fa.get("shown_files") == "2" and fa.get("files_capped") == "1" and "--limit=" in fa.get("files_next", "") and len(rf(l15)) == 2:
    ok("(15) --limit=2: shown_files=2 files_capped=1 files_next=%s" % fa.get("files_next"))
else:
    no("(15) --limit=2 files %r rows=%d" % (fa, len(rf(l15))))

# (17) the first-hop band: with no --limit every d<=1 file is listed, past the default 20
b17 = run("band", "--impact=wide")
fe = re.search(r"<files [^>]*>", b17)
fa = dict(re.findall(r'(\w[\w-]*)="([^"]*)"', fe.group(0))) if fe else {}
if fa.get("files") == "26" and fa.get("shown_files") == "26" and fa.get("files_capped") == "0":
    ok("(17) 25 user files + the defining one: shown_files=26 files_capped=0 (the band, past the default 20)")
else:
    no("(17) band files %r" % fa)

# (18) only type-reached files widen the window: a class only constructed from 25 files keeps the 20-row default
b18 = run("callband", "--impact=Made")
fe = re.search(r"<files [^>]*>", b18)
fa = dict(re.findall(r'(\w[\w-]*)="([^"]*)"', fe.group(0))) if fe else {}
if fa.get("files") == "26" and fa.get("shown_files") == "20" and fa.get("files_capped") == "1" and fa.get("type_users") == "0":
    ok("(18) constructor-only callers: files=26 shown_files=20 files_capped=1 type_users=0 (the band is the type-reached files only)")
else:
    no("(18) callband files %r" % fa)

# (20) Rust impl blocks: a multi-line `impl Shape for Sq {` / `impl Sq {` header names the type on a line no indexed
# definition covers; the methods inside the block are the users (same file and another file), and an empty impl block
# still lists its file
d20 = run("rsimpl", "--impact=Shape")
r20, s20 = rf(d20), srows(d20)
# member rows print Owner::name: the two impl methods are exactly Sq::area (lib.rs) and Tri::area (tri.rs)
areas = sorted(n for n, d in s20 if n.endswith("::area") and d == "1")
if areas == ["Sq::area", "Tri::area"] and r20.get("tri.rs", {}).get("via") == "type" and r20.get("tri.rs", {}).get("syms", "0") != "0" and "empty.rs" in r20:
    ok("(20) --impact=Shape: both impl methods `area` at d=1 (lib.rs and tri.rs), tri.rs via=type syms=%s, empty.rs listed" % r20["tri.rs"].get("syms"))
else:
    no("(20) --impact=Shape rows %r rf %r" % (s20, r20))
d20b = run("rsimpl", "--impact=Sq")
s20b = dict(srows(d20b))
if s20b.get("Sq::side") == "1" and s20b.get("Sq::area") == "1":
    ok("(20b) --impact=Sq: the inherent impl's side and the trait impl's area at d=1")
else:
    no("(20b) --impact=Sq rows %r" % srows(d20b))

# (21) a standard-library path never names the in-tree namesake: std::io::Error / std::fmt::Error / core::fmt::Error and
# std::vector / std::chrono::duration are not users; a bare, crate-rooted or global-rooted spelling is
d21 = run("rsstd", "--impact=Error")
s21 = dict(srows(d21))
fe = re.search(r"<files [^>]*>", d21)
if s21.get("mine") == "1" and s21.get("via_crate") == "1" and not ({"read_it", "fmt_it", "core_it"} & set(s21)) and fe and 'type_users="2"' in fe.group(0):
    ok("(21) Rust --impact=Error: mine and via_crate at d=1, no std/core-path function, type_users=\"2\"")
else:
    no("(21) Rust --impact=Error rows %r files %r" % (srows(d21), fe and fe.group(0)))
d21b = run("cppstd", "--impact=vector")
s21b = dict(srows(d21b))
if s21b.get("mine") == "1" and s21b.get("via_global") == "1" and not ({"sum_std", "sum_chrono"} & set(s21b)):
    ok("(21b) C++ --impact=vector: mine and via_global at d=1, no std:: parameter")
else:
    no("(21b) C++ --impact=vector rows %r" % srows(d21b))

# (22) CodeRabbit 4303967681: --format=columnar carries no <files> rollup, so before the <by_type> column a type user sat at
# depth 1 under "1 = direct caller". The column marks every row reached only through a type mention (1), a call-reached row
# stays 0 (ctor.cpp's build_one CONSTRUCTS a Widget: a call edge), the compact legend defines the column, the full legend's
# clause rides and stays well-formed, and a FUNCTION impact (no type tier) carries neither the column nor the clause.
def cols(doc):
    m = re.search(r'<cols n="\d+" fields="([^"]*)">(.*?)</cols>', doc)
    if not m:
        return None, {}
    arr = dict(re.findall(r"<(\w+)>([^<]*)</\1>", m.group(2)))
    return m.group(1).split(","), arr
c22 = run("cpp", "--impact=Widget", "--format=columnar")
f22, a22 = cols(c22)
z22 = dict(zip(a22.get("name", "").split(","), a22.get("by_type", "").split(","))) if f22 else {}
full22 = run("cpp", "--impact=Widget", "--format=columnar", "--legend=full")
xml22 = subprocess.run(["xmllint", "--noout", "-"], input=full22, capture_output=True, text=True) if shutil.which("xmllint") else None
fn22 = run("c", "--impact=a_set", "--format=columnar", "--legend=full")
fails22 = []
if not f22 or "by_type" not in f22: fails22.append("fields=%r has no by_type" % (f22,))
if z22.get("build_one") != "0": fails22.append("build_one (a constructor CALL) by_type=%r, want 0" % z22.get("build_one"))
for n in ("take", "Holder", "lookup", "Derived"):
    if z22.get(n) != "1": fails22.append("%s (a type user) by_type=%r, want 1" % (n, z22.get(n)))
if "<by_type> column: 1 = reached only through a type mention" not in c22: fails22.append("compact legend lacks the <by_type> definition")
if "the by_type column (present when a shown row has it)" not in full22: fails22.append("full legend lacks the by_type clause")
if xml22 is not None and xml22.returncode != 0: fails22.append("--legend=full answer is not well-formed XML: " + xml22.stderr[:160])
if "by_type" in fn22: fails22.append("a FUNCTION impact (--impact=a_set) carries by_type")
if fails22:
    no("(22) columnar by_type: " + "; ".join(fails22) + " rows=%r" % (z22,))
else:
    ok("(22) --format=columnar type impact: <by_type> 1 on take/Holder/lookup/Derived, 0 on the constructor call build_one; both legends define it (xmllint %s); a function impact has none"
       % ("clean" if xml22 is not None else "not installed"))

# (16) determinism
(ok if run("c", "--impact=cell") == run("c", "--impact=cell") else no)("(16) two runs byte-identical")

print("impacttypecheck: " + ("FAILURES" if fail[0] else "ALL PASS"))
sys.exit(fail[0])
PY
