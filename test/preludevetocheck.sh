#!/usr/bin/env bash
# preludevetocheck.sh — EDGE-PRELUDE-VETO: a prelude name or a macro with no in-tree binding is not a call into the tree.
#   P arms  Rust prelude calls (langfacts.h LangFacts::preludeCalls: Ok, Err, Some, drop): with no written binding (a definition in the
#           caller's file, or one a `use` proves) the call is external=, whatever namesake an imported file defines; a user's own `Ok`
#           type reached through a `use`, or a same-file `fn Some`, keeps its edge.
#   K arms  Rust macro invocations (queries/rust/tags.scm @reference.macro, role Macro): bind to an indexed `macro_rules!` of the name
#           or a procedural macro a `use` names, never to a same-named function by name alone (`assert!`, a `json!` whose `json` is
#           bound to an in-tree function); a local `macro_rules! assert` keeps its edge.
#   M arms  macro scope: a `macro_rules!` without #[macro_export] binds only in its own file, its child modules, a `#[macro_use] mod`
#           parent's scope, or where a `use` names it (`pub(crate) use m;`); an exported one binds crate-wide (graph.h rustMacroScopeOf).
#   S arms  measured member names (externalnames.h kRustStdMemberNames: expect, into, join, lock, status) with no receiver proof are
#           declined and counted; a receiver typed as the in-tree class, or the impl's own `self.expect()`, keeps the edge (the way back).
#   D arms  disclosure: the refused calls are counted (external= on the caller, declined_calls= on the callers answer).
#   X arms  polyglot: Python and C are untouched (their builtin vetoes are the Phase-5 ones).
# Fixtures are built at runtime. usage: bash test/preludevetocheck.sh [BIN]   (BIN falls back to RIPWIRE_BIN, then build/ripwire)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-${RIPWIRE_BIN:-$HERE/../build/ripwire}}
case "$BIN" in /*) ;; *) BIN=$PWD/$BIN ;; esac
echo "preludevetocheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "preludevetocheck: no binary at $BIN"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "preludevetocheck: python3 required"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/preludevetocheck.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
w() { mkdir -p "$(dirname "$1")"; printf '%b' "$2" > "$1"; }
# ask BIN ROOT VERB SYM: the answer, or FAILED-RUN when the run exits nonzero or prints no schema
ask() {
    local bin=$1 root=$2 verb=$3 sym=$4 out rc
    if [ "$verb" = map ]; then
        out=$( cd "$root" && "$bin" "$root" --no-cache --legend=compact </dev/null 2>/dev/null )   # the default map: its header counts the graph
    else
        out=$( cd "$root" && "$bin" "$root" "--$verb=$sym" --no-cache --legend=compact </dev/null 2>/dev/null )
    fi
    rc=$?
    if [ "$rc" != 0 ] || ! printf '%s' "$out" | grep -q 'schema='; then printf 'FAILED-RUN'; return; fi
    printf '%s' "$out"
}
# classify PATH NAME: reads an answer on stdin; the <s> row at PATH named NAME is proven (no via), name (via="name") or none;
# failed-run and no-caller (defs="0") pass no arm
classify() {
    python3 -I -c '
import re,sys
path,name=sys.argv[1],sys.argv[2]
doc=sys.stdin.read()
if doc=="FAILED-RUN" or "schema=" not in doc: print("failed-run"); sys.exit()
d=re.search(r" defs=\"([0-9]+)\"",doc)
if not d or d.group(1)=="0": print("no-caller"); sys.exit()
got="none"
for m in re.finditer(r"<s [^>]*>",doc):
    t=m.group(0)
    n=re.search(r" n=\"([^\"]*)\"",t); p=re.search(r" p=\"([^\":]*)",t)
    if n and p and p.group(1)==path and (n.group(1)==name or n.group(1).endswith("::"+name)):
        got="name" if " via=\"name\"" in t else "proven"
print(got)' "$1" "$2"
}
# row ID ROOT VERB SYM PATH NAME WANT   WANT: proven | name | none | present (proven or name)
row() {
    local id=$1 root=$2 verb=$3 sym=$4 path=$5 name=$6 want=$7 got ok=0
    got=$( ask "$BIN" "$root" "$verb" "$sym" | classify "$path" "$name" )
    case "$want:$got" in
        present:proven|present:name) ok=1 ;;
        *) [ "$got" = "$want" ] && ok=1 ;;
    esac
    if [ "$ok" = 1 ]; then echo "PASS $id ($got)"; else echo "FAIL $id --$verb=$sym -> $path:$name want $want got $got"; fail=1; fi
}
# attr ID ROOT VERB SYM ATTR MIN: the answer's ATTR="N" or header ATTR=N (first occurrence) is at least MIN; VERB map = the default map
attr() {
    local id=$1 root=$2 verb=$3 sym=$4 a=$5 min=$6 out n
    out=$( ask "$BIN" "$root" "$verb" "$sym" )
    if [ "$out" = "FAILED-RUN" ]; then echo "FAIL $id --$verb=$sym failed-run"; fail=1; return; fi
    n=$( printf '%s' "$out" | grep -oE " $a=\"?[0-9]+" | head -1 | grep -oE '[0-9]+' )
    if [ -n "$n" ] && [ "$n" -ge "$min" ]; then echo "PASS $id ($a=$n)"; else echo "FAIL $id --$verb=$sym $a='${n:-absent}' want >= $min"; fail=1; fi
}

# ---- Rust: one crate; a.rs holds a namesake of every prelude name and macro, so each call has an in-tree name to be bound to by mistake.
R=$T/rs
w "$R/Cargo.toml" '[package]\nname = "p"\nversion = "0.1.0"\n'
w "$R/src/lib.rs" 'pub mod a;\npub mod own;\npub mod m;\npub mod parser;\npub mod pm;\npub mod u1;\npub mod u2;\npub mod u3;\npub mod u4;\npub mod u6;\npub mod u7;\npub mod u8;\npub mod u9;\npub mod u10;\npub mod u12;\npub mod u14;\npub mod u15;\npub mod cm;\npub mod u16;\n#[macro_use]\nmod mu;\n#[macro_use]\npub(crate) mod dm;\npub mod u17;\npub mod ru;\npub mod u18;\n'
w "$R/src/a.rs" 'pub fn helper() {}\npub fn Ok(x: i32) -> i32 { x }\npub fn Err(x: i32) -> i32 { x }\npub fn assert(x: bool) {}\npub fn json() {}\npub fn mac2() {}\npub fn pmac() {}\npub fn outer() { fn drop(x: i32) {} drop(1); }\npub struct Q;\nimpl Q {\n    pub fn lock(&self) {}\n    pub fn into(self) {}\n}\n'
w "$R/src/own.rs" 'pub struct Ok(pub i32);\n'
w "$R/src/m.rs" '#[macro_export]\nmacro_rules! mac2 { () => {} }\n#[macro_export]\nmacro_rules! json { ($e:tt) => {} }\n'
w "$R/src/parser.rs" 'pub struct Parser;\nimpl Parser {\n    pub fn expect(&self, s: &str) {}\n    pub fn parse(&self) { self.expect("x"); }\n}\n'
w "$R/src/pm.rs" 'pub fn pmac(input: u32) -> u32 { input }\n'
w "$R/src/u1.rs" 'use crate::a::helper;\nfn p1() -> i32 { helper(); Ok(1) }\nfn p1e() -> i32 { helper(); Err(1) }\n'
w "$R/src/u2.rs" 'use crate::own::Ok;\nfn p2() -> Ok { Ok(1) }\n'
w "$R/src/u3.rs" 'fn Some(x: i32) -> i32 { x }\nfn p3() -> i32 { Some(1) }\n'
w "$R/src/u4.rs" 'fn p4() { mac2!(); }\nfn p5() { assert!(true); crate::a::helper(); }\n'
w "$R/src/u6.rs" 'use crate::json;\nfn p6() { json!({}); crate::a::helper(); }\n'
w "$R/src/u7.rs" 'fn p7() { drop(1); crate::a::helper(); }\n'
w "$R/src/u8.rs" 'fn p8(o: Option<i32>, m: std::sync::Mutex<u8>) { o.expect("v"); let _ = m.lock(); crate::a::helper(); }\n'
w "$R/src/u9.rs" 'use crate::parser::Parser;\nfn p9(p: &Parser) { p.expect("v"); }\n'
w "$R/src/u10.rs" 'use crate::pm::pmac;\nfn p10() { pmac!(1); }\n'
w "$R/src/u12.rs" 'macro_rules! assert { ($e:expr) => {} }\nfn p12() { assert!(true); }\n'
# M arms (macro scope): a `macro_rules!` without #[macro_export] is textual: its file, its child modules, a `#[macro_use] mod` parent's
w "$R/src/u14.rs" '#[macro_export]\nmacro_rules! mexp { () => {} }\nmacro_rules! mloc { () => {} }\n'
w "$R/src/u15.rs" 'fn p15() { mexp!(); mloc!(); crate::a::helper(); }\n'
w "$R/src/cm.rs" 'macro_rules! cmac { () => {} }\npub mod child;\n'
w "$R/src/cm/child.rs" 'fn pc() { cmac!(); }\n'
w "$R/src/u16.rs" 'fn p16() { cmac!(); crate::a::helper(); }\n'
w "$R/src/mu.rs" 'macro_rules! mumac { () => {} }\n'
w "$R/src/dm/mod.rs" 'macro_rules! dmac { () => {} }\n'
w "$R/src/u17.rs" 'fn p17() { mumac!(); dmac!(); }\n'
w "$R/src/ru.rs" 'macro_rules! rmac { () => {} }\npub(crate) use rmac;\n'
w "$R/src/u18.rs" 'use crate::ru::rmac;\nfn p18() { rmac!(); }\n'
row P1.prelude     "$R" callees p1  src/a.rs Ok        none
row P1.own         "$R" callees p1  src/own.rs Ok      none
row P1.twin        "$R" callees p1  src/a.rs helper    proven
row P1.err         "$R" callees p1e src/a.rs Err       none
row P2.ownuse      "$R" callees p2  src/own.rs Ok      present
row P2.neighbour   "$R" callees p2  src/a.rs Ok        none
row P3.samefile    "$R" callees p3  src/u3.rs Some     proven
row P7.drop        "$R" callees p7  src/a.rs drop      none
row P7.twin        "$R" callees p7  src/a.rs helper    proven
row K1.exported    "$R" callees p4  src/m.rs mac2      present
row K1.fnnamesake  "$R" callees p4  src/a.rs mac2      none
row K2.stdmacro    "$R" callees p5  src/a.rs assert    none
row K2.twin        "$R" callees p5  src/a.rs helper    proven
row K3.boundjson   "$R" callees p6  src/m.rs json      present
row K3.fnnamesake  "$R" callees p6  src/a.rs json      none
row K3.twin        "$R" callees p6  src/a.rs helper    proven
row K4.procmacro   "$R" callees p10 src/pm.rs pmac     present
# K4 has no neighbour arm: a `use` proves every in-crate namesake of its name (receiverevidence.h rustRule3Proves, card RUST-USE-TARGET)
row K5.localmacro  "$R" callees p12 src/u12.rs assert  present
row K5.fnnamesake  "$R" callees p12 src/a.rs assert    none
row M1.localother  "$R" callees p5  src/u12.rs assert  none
row M2.exported    "$R" callees p15 src/u14.rs mexp    present
row M2.localother  "$R" callees p15 src/u14.rs mloc    none
row M2.twin        "$R" callees p15 src/a.rs helper    proven
row M3.childmod    "$R" callees pc  src/cm.rs cmac     present
row M3.sibling     "$R" callees p16 src/cm.rs cmac     none
row M3.twin        "$R" callees p16 src/a.rs helper    proven
row M4.macrouse    "$R" callees p17 src/mu.rs mumac    present
row M4.modrs       "$R" callees p17 src/dm/mod.rs dmac present
row M5.reexport    "$R" callees p18 src/ru.rs rmac     present
row S1.expect      "$R" callees p8  src/parser.rs Parser::expect none
row S1.lock        "$R" callees p8  src/a.rs Q::lock   none
row S1.twin        "$R" callees p8  src/a.rs helper    proven
row S2.typed       "$R" callees p9  src/parser.rs Parser::expect present
row S2.self        "$R" callees Parser::parse src/parser.rs Parser::expect present
# the map header's external= counts the refused sites (p1 Ok, p1e Err, p7 drop, and the out-of-scope macros p5 assert, p15 mloc,
# p16 cmac; 0 before this lane, 3 before the macro-scope fix)
attr D1.external   "$R" map     -   external 6
attr D2.declined   "$R" callers Parser::expect declined_calls 1

# ---- polyglot: Python's and C's builtin vetoes are their own Phase-5 rows; a bound or same-file namesake keeps its edge there
X=$T/poly
w "$X/py/a.py" 'def Ok(x):\n    return x\n'
w "$X/py/b.py" 'from a import Ok\n\ndef q():\n    return Ok(1)\n'
w "$X/c/x.c" 'static void drop(int v) {}\nvoid f(void) { drop(1); }\n'
row X1.pyimport "$X" callees q py/a.py Ok   proven
row X2.csame    "$X" callees f c/x.c drop   proven

# ---- self-test: a row read through a binary that crashes is failed-run, never a pass (the gate cannot go green on a dead binary)
STUB=$T/stub.sh
printf '#!/bin/sh\nkill -SEGV $$\n' > "$STUB"; chmod +x "$STUB"
got=$( ask "$STUB" "$R" callees p1 | classify src/a.rs Ok )
if [ "$got" = "failed-run" ]; then echo "PASS Z1.crashstub ($got)"; else echo "FAIL Z1.crashstub got $got want failed-run"; fail=1; fi

if [ "$fail" = 0 ]; then echo "preludevetocheck: PASS"; exit 0; fi
echo "preludevetocheck: FAIL"; exit 1
