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
# (`good` is yes/no, never 0/1: test/gateexitcheck.sh (B) reads the first `X=1` in a FAIL-printing helper as the accumulator, and that is `fail`)
row() {
    local id=$1 root=$2 verb=$3 sym=$4 path=$5 name=$6 want=$7 got good=no
    got=$( ask "$BIN" "$root" "$verb" "$sym" | classify "$path" "$name" )
    case "$want:$got" in
        present:proven|present:name) good=yes ;;
        *) [ "$got" = "$want" ] && good=yes ;;
    esac
    if [ "$good" = yes ]; then echo "PASS $id ($got)"; else echo "FAIL $id --$verb=$sym -> $path:$name want $want got $got"; fail=1; fi
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
w "$R/src/lib.rs" 'pub mod a;\npub mod own;\npub mod m;\npub mod parser;\npub mod pm;\npub mod u1;\npub mod u2;\npub mod u3;\npub mod u4;\npub mod u6;\npub mod u7;\npub mod u8;\npub mod u9;\npub mod u10;\npub mod u11;\npub mod u12;\npub mod u14;\npub mod u15;\npub mod cm;\npub mod u16;\n#[macro_use]\nmod mu;\n#[macro_use]\npub(crate) mod dm;\npub mod u17;\npub mod ru;\npub mod u18;\n/* #[macro_use] mod cmt; */\npub mod cmt;\npub mod u23;\npub mod pmc;\npub mod u24;\npub mod u25;\npub mod u26;\n'
w "$R/src/a.rs" 'pub fn helper() {}\npub fn Ok(x: i32) -> i32 { x }\npub fn Err(x: i32) -> i32 { x }\npub fn assert(x: bool) {}\npub fn json() {}\npub fn mac2() {}\npub fn pmac() {}\npub fn outer() { fn drop(x: i32) {} drop(1); }\npub struct Q;\nimpl Q {\n    pub fn lock(&self) {}\n    pub fn into(self) {}\n}\n'
w "$R/src/own.rs" 'pub struct Ok(pub i32);\n'
w "$R/src/m.rs" '#[macro_export]\nmacro_rules! mac2 { () => {} }\n#[macro_export]\nmacro_rules! json { ($e:tt) => {} }\n'
w "$R/src/parser.rs" 'pub struct Parser;\nimpl Parser {\n    pub fn expect(&self, s: &str) {}\n    pub fn parse(&self) { self.expect("x"); }\n}\n'
w "$R/src/pm.rs" '/// a procedural macro\n/// let p = pmac!(1);\n#[proc_macro]\npub fn pmac(input: u32) -> u32 { input }\npub fn nmac() {}\npub fn outer() { fn gmac() {} gmac(); }\n'
w "$R/src/u1.rs" 'use crate::a::helper;\nfn p1() -> i32 { helper(); Ok(1) }\nfn p1e() -> i32 { helper(); Err(1) }\n'
w "$R/src/u2.rs" 'use crate::own::Ok;\nfn p2() -> Ok { Ok(1) }\n'
w "$R/src/u3.rs" 'fn Some(x: i32) -> i32 { x }\nfn p3() -> i32 { Some(1) }\n'
w "$R/src/u4.rs" 'fn p4() { mac2!(); }\nfn p5() { assert!(true); crate::a::helper(); }\n'
w "$R/src/u6.rs" 'use crate::json;\nfn p6() { json!({}); crate::a::helper(); }\n'
w "$R/src/u7.rs" 'fn p7() { drop(1); crate::a::helper(); }\n'
w "$R/src/u8.rs" 'fn p8(o: Option<i32>, m: std::sync::Mutex<u8>) { o.expect("v"); let _ = m.lock(); crate::a::helper(); }\n'
w "$R/src/u9.rs" 'use crate::parser::Parser;\nfn p9(p: &Parser) { p.expect("v"); }\n'
w "$R/src/u10.rs" 'use crate::pm::pmac;\nfn p10() { pmac!(1); }\n'
w "$R/src/u11.rs" 'use crate::pm::*;\nuse crate::pm::nmac;\nfn p11() { nmac!(); gmac!(); crate::a::helper(); }\n'
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
w "$R/src/cmt.rs" 'macro_rules! cmtm { () => {} }\nfn cm1() { cmtm!(); }\n'
w "$R/src/u23.rs" 'fn p23() { cmtm!(); crate::a::helper(); }\n'
w "$R/src/pmc.rs" '/*\n#[proc_macro]\n*/\npub fn cpm(x: u32) -> u32 { x }\n#[proc_macro]\npub fn rpm(x: u32) -> u32 { x }\n'
w "$R/src/u24.rs" 'use crate::pmc::{cpm, rpm};\nfn p24() { cpm!(1); rpm!(1); }\n'
w "$R/src/u25.rs" 'use crate::pm::pmac as other;\nfn p25() { pmac!(1); crate::a::helper(); }\n'
w "$R/src/u26.rs" 'use crate::pm::pmac as pmac;\nfn p26() { pmac!(1); }\n'
row P1.prelude     "$R" callees p1  src/a.rs Ok        none
row P1.own         "$R" callees p1  src/own.rs Ok      none
row P1.twin        "$R" callees p1  src/a.rs helper    proven
row P1.err         "$R" callees p1e src/a.rs Err       none
row P2.ownuse      "$R" callees p2  src/own.rs Ok      present
row P2.neighbour   "$R" callees p2  src/a.rs Ok        none
row P3.samefile    "$R" callees p3  src/u3.rs Some     proven
row P7.drop        "$R" callees p7  src/a.rs drop      none
row P7.twin        "$R" callees p7  src/a.rs helper    proven
# C arms (fix round 1, review threads): a `#[macro_use] mod` written inside a comment widens nothing; a `#[proc_macro]` inside a /* */ block
# is no attribute; `use m::pmac as other;` binds `other`, not `pmac` (the same `use` spelled `as pmac` keeps it)
row C1.cmtmacrouse "$R" callees p23 src/cmt.rs cmtm    none
row C1.twin        "$R" callees cm1 src/cmt.rs cmtm    present
row C2.blockattr   "$R" callees p24 src/pmc.rs cpm     none
row C2.twin        "$R" callees p24 src/pmc.rs rpm     present
row C3.asrename    "$R" callees p25 src/pm.rs pmac     none
row C3.asself      "$R" callees p26 src/pm.rs pmac     present
row K1.exported    "$R" callees p4  src/m.rs mac2      present
row K1.fnnamesake  "$R" callees p4  src/a.rs mac2      none
row K2.stdmacro    "$R" callees p5  src/a.rs assert    none
row K2.twin        "$R" callees p5  src/a.rs helper    proven
row K3.boundjson   "$R" callees p6  src/m.rs json      present
row K3.fnnamesake  "$R" callees p6  src/a.rs json      none
row K3.twin        "$R" callees p6  src/a.rs helper    proven
row K4.procmacro   "$R" callees p10 src/pm.rs pmac     present
# K4 neighbours: a `use`d function without #[proc_macro], and a nested fn a glob reaches (zed's `fn assert` in tests), are no macros
row K4.notproc     "$R" callees p11 src/pm.rs nmac     none
row K4.nested      "$R" callees p11 src/pm.rs gmac     none
row K4.twin        "$R" callees p11 src/a.rs helper    proven
# K4 has no same-name neighbour arm: a `use` proves every in-crate namesake of its name (receiverevidence.h rustRule3Proves, card RUST-USE-TARGET)
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
# the map header's external= counts the refused sites (p1 Ok, p1e Err, p7 drop, the out-of-scope macros p5 assert, p15 mloc,
# p16 cmac, p11 nmac and gmac, and fix round 1's p23 cmtm, p24 cpm and p25 pmac; 0 before this lane, 3 before the macro-scope fix)
attr D1.external   "$R" map     -   external 11
attr D2.declined   "$R" callers Parser::expect declined_calls 1

# ---- P10-P13 (fix round 1), a crate of their own (R's a.rs `fn Ok` would hide the shape): only a namesake a bare call can NAME cancels the
# veto. An associated `type Ok` / `type Err` in the caller's own file (serde's Serializer, FromStr), a module-level `type Ok` alias a `use`
# names, a nested `unsafe fn drop` a `use super::*;` reaches (zed's arena.rs) and a glob-imported trait's impl `type Ok` are none; a nested
# fn called inside its own fn, a same-file fn and a tuple struct (P2, P3) keep it
P=$T/pv
w "$P/Cargo.toml" '[package]\nname = "pv"\nversion = "0.1.0"\n'
w "$P/src/lib.rs" 'pub mod a;\npub mod u19;\npub mod al;\npub mod u20;\npub mod nd;\npub use nd::*;\npub mod u21;\npub mod tr;\npub mod u22;\n'
w "$P/src/a.rs" 'pub fn helper() {}\npub fn outer() { fn drop(x: i32) {} drop(1); }\n'
w "$P/src/u19.rs" 'pub trait Ser { type Ok; type Err; }\npub struct S;\nimpl Ser for S { type Ok = (); type Err = i32; }\npub fn p19() -> Result<(), i32> { if true { crate::a::helper(); return Err(1); } Ok(()) }\n'
w "$P/src/al.rs" 'pub type Ok = i32;\n'
w "$P/src/u20.rs" 'use crate::al::Ok;\nfn p20() -> Result<i32, ()> { crate::a::helper(); Ok(1) }\n'
w "$P/src/nd.rs" 'pub mod kid;\npub fn arena() { unsafe fn drop<T>(x: T) {} }\npub struct Arena;\nimpl Arena {\n    pub fn alloc(&self) {\n        unsafe fn drop<T>(p: *mut u8) {}\n    }\n}\n'
w "$P/src/nd/kid.rs" 'use super::*;\nfn p21() { drop(1); crate::a::helper(); }\n'
w "$P/src/u21.rs" 'use crate::*;\nfn p21b() { drop(1); crate::a::helper(); }\n'
w "$P/src/tr.rs" 'pub trait T { type Ok; }\npub struct X;\nimpl T for X { type Ok = u8; }\n'
w "$P/src/u22.rs" 'use crate::tr::*;\nfn p22() -> Result<u8, ()> { crate::a::helper(); Ok(1) }\n'
row P10.assocok    "$P" callees p19 src/u19.rs Ok      none
row P10.assocerr   "$P" callees p19 src/u19.rs Err     none
row P10.twin       "$P" callees p19 src/a.rs helper    proven
row P11.aliasuse   "$P" callees p20 src/al.rs Ok       none
row P11.twin       "$P" callees p20 src/a.rs helper    proven
row P12.nesteddrop "$P" callees p21 src/nd.rs drop     none
row P12.twin       "$P" callees p21 src/a.rs helper    proven
row P12.reexport   "$P" callees p21b src/nd.rs drop    none
row P12.twin2      "$P" callees p21b src/a.rs helper   proven
row P12.ownfn      "$P" callees outer src/a.rs drop    present
row P13.globtrait  "$P" callees p22 src/tr.rs Ok       none
row P13.twin       "$P" callees p22 src/a.rs helper    proven
attr D3.external   "$P" map     -   external 5

# ---- K6: a procedural macro in a workspace crate whose root is a Cargo `[lib] path` (zed's sqlez_macros): `use m::sql;` binds `sql!`;
# a caller with no `use` of it binds nothing (the name alone is no proof)
W=$T/ws
w "$W/Cargo.toml" '[workspace]\nmembers = ["crates/m", "crates/d", "crates/g"]\n'
w "$W/crates/m/Cargo.toml" '[package]\nname = "m"\nversion = "0.1.0"\n[lib]\nproc-macro = true\npath = "src/m.rs"\n'
w "$W/crates/m/src/m.rs" '#[proc_macro]\npub fn sql(t: u32) -> u32 { t }\n'
w "$W/crates/d/Cargo.toml" '[package]\nname = "d"\nversion = "0.1.0"\n[dependencies]\nm = { path = "../m" }\n'
w "$W/crates/d/src/f.rs" 'use m::sql;\nfn f7() { sql!(1); }\n'
w "$W/crates/d/src/lib.rs" 'use m::{sql};\npub mod e;\npub mod f;\npub mod h;\npub fn helper() {}\nfn f6() { sql!(1); helper(); }\n'
w "$W/crates/d/src/e.rs" 'use crate::helper;\nfn g6() { sql!(1); helper(); }\n'
row K6.libpath     "$W" callees f7  crates/m/src/m.rs sql     present
row K6.braced      "$W" callees f6  crates/m/src/m.rs sql     present
row K6.nouse       "$W" callees g6  crates/m/src/m.rs sql     none
row K6.twin        "$W" callees g6  crates/d/src/lib.rs helper proven

# ---- M6 (fix round 1): a crate root a Cargo.toml names by `[lib] path` owns its directory like lib.rs: its own non-exported macro, and one
# of a `#[macro_use] mod` it declares, bind in its child modules (a root-level package and a workspace member); another crate's file binds neither
G=$T/lg
w "$G/Cargo.toml" '[package]\nname="g"\nversion="0.1.0"\n[lib]\npath="src/g.rs"\n'
w "$G/src/g.rs" '#[macro_use]\nmod macros;\npub mod user;\nmacro_rules! rootm { () => {} }\npub fn helper() {}\n'
w "$G/src/macros.rs" 'macro_rules! mm { () => {} }\n'
w "$G/src/user.rs" 'fn here() {}\npub fn uz() { mm!(); rootm!(); here(); }\n'
row M6.libpathuse  "$G" callees uz  src/macros.rs mm      present
row M6.libpathroot "$G" callees uz  src/g.rs rootm        present
row M6.twin        "$G" callees uz  src/user.rs here      proven
# M7: src/bin/*.rs and a main.rs beside the lib root are crates of their own: a lib's non-exported macro binds in neither (a lib.rs crate
# and a `[lib] path` crate); a child module of the lib root still binds it
L=$T/lb
w "$L/Cargo.toml" '[package]\nname = "lb"\nversion = "0.1.0"\n'
w "$L/src/lib.rs" 'macro_rules! lm { () => {} }\npub mod x;\n'
w "$L/src/x.rs" 'pub fn xz() { lm!(); }\n'
w "$L/src/bin/tool.rs" 'fn there() {}\nfn tz() { lm!(); there(); }\n'
w "$L/src/main.rs" 'fn here2() {}\nfn mz() { lm!(); here2(); }\nfn main() { mz(); }\n'
row M7.child       "$L" callees xz  src/lib.rs lm         present
row M7.srcbin      "$L" callees tz  src/lib.rs lm         none
row M7.twin        "$L" callees tz  src/bin/tool.rs there proven
row M7.mainrs      "$L" callees mz  src/lib.rs lm         none
row M7.twin2       "$L" callees mz  src/main.rs here2     proven
w "$G/src/bin/tool.rs" 'fn there() {}\nfn gtz() { rootm!(); there(); }\n'
row M7.libpathbin  "$G" callees gtz src/g.rs rootm        none
# M8 (MACRO-MANIFEST-SIBLINGS): crate roots that share a directory (`[lib] path` beside a `[[bin]] path`, a `[[bin]] path` in src/bin beside
# an auto bin, a main.rs beside a `[lib] path`) own only the modules each declares there; a `[lib] path` outside the package (`../shared/b.rs`)
# owns its directory
S=$T/sib
w "$S/Cargo.toml" '[workspace]\nmembers = ["crates/a", "crates/b", "crates/z"]\n'
w "$S/crates/a/Cargo.toml" '[package]\nname = "a"\nversion = "0.1.0"\n\n[lib]\npath = "src/a_lib.rs"\n\n[[bin]]\nname = "acli"\npath = "src/a_cli.rs"\n\n[[bin]]\nname = "x"\npath = "src/bin/x.rs"\n'
w "$S/crates/a/src/a_lib.rs" 'macro_rules! lm { () => { 1 } }\n#[macro_use]\nmod macros;\nmod helper;\npub fn lf() -> i32 { lm!() }\n'
w "$S/crates/a/src/macros.rs" 'macro_rules! mm { () => { 2 } }\n'
w "$S/crates/a/src/helper.rs" 'pub fn hf() -> i32 { lm!() + mm!() }\npub fn hc() -> i32 { cm!() }\n'
w "$S/crates/a/src/a_cli.rs" 'macro_rules! cm { () => { 3 } }\nmod clih;\npub fn cliuse() -> i32 { lm!() + mm!() + cm!() }\nfn main() {}\n'
w "$S/crates/a/src/clih.rs" 'pub fn ch() -> i32 { cm!() }\n'
w "$S/crates/a/src/bin/x.rs" 'macro_rules! xm { () => { 4 } }\npub mod xh;\npub fn xf() -> i32 { xm!() }\nfn main() {}\n'
w "$S/crates/a/src/bin/xh.rs" 'pub fn xhf() -> i32 { xm!() }\n'
w "$S/crates/a/src/bin/y.rs" 'pub fn yf() -> i32 { xm!() + lm!() }\nfn main() {}\n'
w "$S/crates/b/Cargo.toml" '[package]\nname = "b"\nversion = "0.1.0"\n\n[lib]\npath = "../shared/b.rs"\n'
w "$S/crates/shared/b.rs" 'macro_rules! bm { () => { 5 } }\nmod bh;\n'
w "$S/crates/shared/bh.rs" 'pub fn bhf() -> i32 { bm!() }\n'
w "$S/crates/z/Cargo.toml" "[package]\nname = 'z'\nversion = '0.1.0'\n[lib]\npath = 'src/zl.rs'\n"
w "$S/crates/z/src/zl.rs" 'macro_rules! zm { () => {} }\npub mod zc;\n'
w "$S/crates/z/src/zc.rs" 'pub fn zcf() { zm!(); }\n'
w "$S/crates/z/src/main.rs" 'macro_rules! mainm { () => {} }\nmod zmod;\nfn zmain() { zm!(); mainm!(); }\nfn main() { zmain(); }\n'
w "$S/crates/z/src/zmod.rs" 'pub fn zmf() { zm!(); mainm!(); }\n'
row M8.hflib       "$S" callees hf     crates/a/src/a_lib.rs lm   present
row M8.hfmu        "$S" callees hf     crates/a/src/macros.rs mm  present
row M8.hc          "$S" callees hc     crates/a/src/a_cli.rs cm   none
row M8.cliuselm    "$S" callees cliuse crates/a/src/a_lib.rs lm   none
row M8.cliusemm    "$S" callees cliuse crates/a/src/macros.rs mm  none
row M8.cliuseown   "$S" callees cliuse crates/a/src/a_cli.rs cm   present
row M8.clichild    "$S" callees ch     crates/a/src/a_cli.rs cm   present
row M8.yf          "$S" callees yf     crates/a/src/bin/x.rs xm   none
row M8.yflib       "$S" callees yf     crates/a/src/a_lib.rs lm   none
row M8.xchild      "$S" callees xhf    crates/a/src/bin/x.rs xm   present
row M8.bhf         "$S" callees bhf    crates/shared/b.rs bm      present
row M8.zchild      "$S" callees zcf    crates/z/src/zl.rs zm      present
row M8.zmain       "$S" callees zmain  crates/z/src/zl.rs zm      none
row M8.zmainmod    "$S" callees zmf    crates/z/src/zl.rs zm      none
row M8.zmainown    "$S" callees zmf    crates/z/src/main.rs mainm present
w "$W/crates/g/Cargo.toml" '[package]\nname = "g"\nversion = "0.1.0"\n[lib]\npath = "src/g.rs"\n'
w "$W/crates/g/src/g.rs" '#[macro_use]\nmod gm;\npub mod gu;\nmacro_rules! groot { () => {} }\n'
w "$W/crates/g/src/gm.rs" 'macro_rules! gmm { () => {} }\n'
w "$W/crates/g/src/gu.rs" 'pub fn gz() { gmm!(); groot!(); }\n'
w "$W/crates/d/src/h.rs" 'fn there() {}\nfn h6() { groot!(); gmm!(); there(); }\n'
row M6.wsuse       "$W" callees gz  crates/g/src/gm.rs gmm present
row M6.wsroot      "$W" callees gz  crates/g/src/g.rs groot present
row M6.othercrate  "$W" callees h6  crates/g/src/g.rs groot none
row M6.othercrate2 "$W" callees h6  crates/g/src/gm.rs gmm none
row M6.twin2       "$W" callees h6  crates/d/src/h.rs there proven

# ---- polyglot: Python's and C's builtin vetoes are their own Phase-5 rows; a bound or same-file namesake keeps its edge there
X=$T/poly
w "$X/py/a.py" 'def Ok(x):\n    return x\n'
w "$X/py/b.py" 'from a import Ok\n\ndef q():\n    return Ok(1)\n'
w "$X/c/x.c" 'static void drop(int v) {}\nvoid f(void) { drop(1); }\n'
row X1.pyimport "$X" callees q py/a.py Ok   proven
row X2.csame    "$X" callees f c/x.c drop   proven
# a Clojure `defmacro` is invoked as `(name ..)`, a Call site: the Rust-only Call-never-binds-a-macro gate (LangFacts::bangMacros) leaves it
w "$X/clj/m.clj" '(ns m)\n(defmacro mm [x] x)\n(defn usem [] (mm 1))\n'
row X3.cljmacro "$X" callees usem clj/m.clj mm present

# ---- self-test: a row read through a binary that crashes is failed-run, never a pass (the gate cannot go green on a dead binary)
STUB=$T/stub.sh
printf '#!/bin/sh\nkill -SEGV $$\n' > "$STUB"; chmod +x "$STUB"
got=$( ask "$STUB" "$R" callees p1 | classify src/a.rs Ok )
if [ "$got" = "failed-run" ]; then echo "PASS Z1.crashstub ($got)"; else echo "FAIL Z1.crashstub got $got want failed-run"; fail=1; fi

[ "$fail" = 0 ] && echo "preludevetocheck: PASS" || echo "preludevetocheck: FAIL"
exit "$fail"
