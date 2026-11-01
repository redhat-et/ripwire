#!/usr/bin/env bash
# rule3memberguardcheck.sh — RULE3-MEMBER-GUARD: Rule 3 (the import-closure narrow, graph.h) sees that the caller's closure holds a file
# defining the name. Where the language writes what a name is bound to, that writing is the proof (langfacts.h rule3NameProof):
#   Rust    a `use` of the name, a glob of the target's module, a qualifier naming its module or type
#   Python  an import binding of the name, a star import of an indexed module
# A call without it keeps the edge marked via="name". M arms pin that a member call with an unknown receiver is already hedged on every
# language (FE-B); N arms pin that Rule 3 still decides the languages with no name proof (C, C++, TS).
# Fixtures are built at runtime. usage: bash test/rule3memberguardcheck.sh [BIN]   (BIN falls back to RIPWIRE_BIN, then build/ripwire)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-${RIPWIRE_BIN:-$HERE/../build/ripwire}}
case "$BIN" in /*) ;; *) BIN=$PWD/$BIN ;; esac
echo "rule3memberguardcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "rule3memberguardcheck: no binary at $BIN"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "rule3memberguardcheck: python3 required"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/rule3memberguardcheck.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
w() { mkdir -p "$(dirname "$1")"; printf '%b' "$2" > "$1"; }
# row ID ROOT VERB CALLER PATH NAME WANT: the row of --VERB=CALLER at file PATH named NAME is `proven` (no via), `name` (via="name"), or `none` (absent)
row() {
    local id=$1 root=$2 verb=$3 caller=$4 path=$5 name=$6 want=$7 got
    got=$( ( cd "$root" && "$BIN" "$root" "--$verb=$caller" --no-cache --legend=compact </dev/null 2>/dev/null ) | python3 -I -c '
import re,sys
path,name=sys.argv[1],sys.argv[2]
got="none"
doc=sys.stdin.read()
if "schema=" not in doc: print("failed-run"); sys.exit()
for m in re.finditer(r"<s [^>]*>",doc):
    t=m.group(0)
    n=re.search(r" n=\"([^\"]*)\"",t); p=re.search(r" p=\"([^\":]*)",t)
    if n and p and p.group(1)==path and (n.group(1)==name or n.group(1).endswith("::"+name) or n.group(1).endswith("."+name)):
        got="name" if " via=\"name\"" in t else "proven"
print(got)' "$path" "$name" )
    if [ "$got" = "$want" ]; then echo "PASS $id"; else echo "FAIL $id $caller -> $path:$name want $want got $got"; fail=1; fi
}

# ---- Rust: one crate, two modules holding every namesake, so Rule 3 has an ambiguous name and one imported file.
R=$T/rs
w "$R/Cargo.toml" '[package]\nname = "r"\nversion = "0.1.0"\n'
w "$R/src/lib.rs" 'pub mod a;\npub mod far;\npub mod user;\npub mod globuser;\npub mod nest;\n'
w "$R/src/a.rs" 'pub fn helper() {}\npub fn globbed() {}\npub fn Ok(x: i32) -> i32 { x }\npub fn channel() {}\npub fn swap() {}\npub fn assert(x: bool) {}\npub struct Thing;\nimpl Thing {\n    pub fn new() -> Thing { Thing }\n    pub fn lock(&self) {}\n}\npub fn new() {}\n'
w "$R/src/far.rs" 'pub fn helper() {}\npub fn globbed() {}\npub fn Ok(x: i32) -> i32 { x }\npub fn channel() {}\npub fn swap() {}\npub fn assert(x: bool) {}\npub struct Other;\nimpl Other {\n    pub fn new() -> Other { Other }\n    pub fn lock(&self) {}\n}\npub fn new() {}\n'
w "$R/src/user.rs" 'use crate::a::helper;\nuse crate::a::Thing;\nuse crate::a;\nuse futures::channel::oneshot;\nuse std::mem::swap;\nfn u_use() { helper(); }\nfn u_prelude() -> i32 { Ok(1) }\nfn u_macro() { assert!(true); }\nfn u_type() { let _ = Thing::new(); }\nfn u_module() { a::channel(); }\nfn u_outside() { let _ = oneshot::channel(); }\nfn u_stdtype() { let _ = String::new(); }\nfn u_stduse() { swap(); }\nfn u_member(x: &std::sync::Mutex<u32>) { let _ = x.lock(); }\n'
w "$R/src/globuser.rs" 'use crate::a::*;\nfn g_glob() { globbed(); }\n'
w "$R/src/nest.rs" 'use crate::a::helper;\nuse std::mem::swap;\nmod tests {\n    use super::*;\n    fn t_super_glob() -> i32 { Ok(1) }\n    fn t_super_use() { helper(); }\n    fn t_super_out() { swap(); }\n}\n'
row R1.use        "$R" callees u_use        src/a.rs helper  proven
row R1.far        "$R" callees u_use        src/far.rs helper none
row R2.prelude    "$R" callees u_prelude    src/a.rs Ok      name
row R3.macro      "$R" callees u_macro      src/a.rs assert  name
row R4.type       "$R" callees u_type       src/a.rs Thing::new proven
row R5.module     "$R" callees u_module     src/a.rs channel proven
row R6.outside    "$R" callees u_outside    src/a.rs channel none
row R7.stdtype    "$R" callees u_stdtype    src/a.rs new     none
row R8.stduse     "$R" callees u_stduse     src/a.rs swap    name
row R9.glob       "$R" callees g_glob       src/a.rs globbed proven
row R10.superglob "$R" callees t_super_glob src/a.rs Ok      name
row R11.superuse  "$R" callees t_super_use  src/a.rs helper  proven
row R11.superout  "$R" callees t_super_out  src/a.rs swap    name
row R12.callers   "$R" callers Ok           src/user.rs u_prelude name
row M.rust        "$R" callees u_member     src/a.rs Thing::lock name

# ---- Python
P=$T/py
w "$P/a.py" 'def helper():\n    pass\ndef conv():\n    pass\ndef starred():\n    pass\nclass A:\n    def getvalue(self):\n        pass\n'
w "$P/far.py" 'def helper():\n    pass\ndef conv():\n    pass\ndef starred():\n    pass\nclass B:\n    def getvalue(self):\n        pass\n'
w "$P/user.py" 'import a\nfrom a import helper\ndef p_import():\n    helper()\ndef p_local():\n    conv = make()\n    return conv()\ndef p_unbound():\n    return conv()\ndef p_param(conv):\n    return conv()\ndef p_alias():\n    return a.conv()\ndef p_member(x):\n    return x.getvalue()\ndef make():\n    return None\n'
w "$P/staruser.py" 'from a import *\ndef p_star():\n    return starred()\n'
row Y1.import  "$P" callees p_import src/none helper none
row Y1.bound   "$P" callees p_import a.py helper proven
row Y2.unbound "$P" callees p_unbound a.py conv name
row Y3.alias   "$P" callees p_alias a.py conv proven
row Y4.star    "$P" callees p_star a.py starred proven
row M.python   "$P" callees p_member a.py A.getvalue name

# ---- C++, Go, TS: member calls already hedged; Rule 3 still decides a C++ free function, a C++ qualified name, a TS named import.
C=$T/cpp
w "$C/a.h" 'struct Status { int status(); };\nint freeFn();\nnamespace ns { struct Q { static int qual(); }; }\n'
w "$C/far.h" 'struct Other { int status(); };\nint freeFn();\nnamespace other { struct Q2 { static int qual(); }; }\n'
w "$C/c.cpp" '#include "a.h"\ntemplate <class T> int c_member( T& t ) { return t.status(); }\nint c_free() { return freeFn(); }\nint c_qual() { return ns::Q::qual(); }\n'
row M.cpp  "$C" callees c_member a.h Status::status name
row N.cpp  "$C" callees c_free   a.h freeFn proven
row N.cppq "$C" callees c_qual   a.h qual proven
G=$T/go
w "$G/go.mod" 'module ex.com/m\n'
w "$G/a/a.go" 'package a\ntype S struct{}\nfunc (s S) Close() {}\nfunc Make() S { return S{} }\n'
w "$G/far/far.go" 'package far\ntype T struct{}\nfunc (s T) Close() {}\nfunc Make() T { return T{} }\n'
w "$G/main.go" 'package main\nimport "ex.com/m/a"\nfunc g_member(x interface{ Close() }) { x.Close() }\nfunc g_alias() { a.Make() }\n'
row N.goalias "$G" callees g_alias a/a.go Make proven
J=$T/ts
w "$J/a.ts" 'export class A { run() {} }\nexport function make() {}\n'
w "$J/far.ts" 'export class B { run() {} }\nexport function make() {}\n'
w "$J/c.ts" 'import { A, make } from "./a";\nexport function t_member(x: any) { return x.run(); }\nexport function t_named() { return make(); }\n'
row M.ts "$J" callees t_member a.ts A.run name
row N.ts "$J" callees t_named  a.ts make proven

# ---- Polyglot: every language in one tree, names shared across them. A guard reads the caller's own language, never a neighbour's bindings.
X=$T/poly
w "$X/Cargo.toml" '[package]\nname = "x"\nversion = "0.1.0"\n'
w "$X/src/lib.rs" 'pub mod a;\npub mod far;\npub mod user;\n'
w "$X/src/a.rs" 'pub fn helper() {}\npub fn conv() {}\n'
w "$X/src/far.rs" 'pub fn helper() {}\npub fn conv() {}\n'
w "$X/src/user.rs" 'use crate::a::helper;\nfn x_rust_use() { helper(); }\nfn x_rust_unbound() { conv(); }\n'
w "$X/py/pa.py" 'def helper():\n    pass\ndef conv():\n    pass\n'
w "$X/py/pfar.py" 'def helper():\n    pass\ndef conv():\n    pass\n'
w "$X/py/puser.py" 'import pa\nfrom pa import helper\ndef x_py_import():\n    helper()\ndef x_py_unbound():\n    return conv()\n'
row X1.rust    "$X" callees x_rust_use     src/a.rs helper proven
row X2.rust    "$X" callees x_rust_unbound src/a.rs conv   name
row X3.py      "$X" callees x_py_import    py/pa.py helper proven
row X4.py      "$X" callees x_py_unbound   py/pa.py conv   name
row X5.nocross "$X" callees x_py_import    src/a.rs helper none

[ "$fail" = 0 ] && echo "rule3memberguardcheck: PASS" || echo "rule3memberguardcheck: FAIL"
exit "$fail"
