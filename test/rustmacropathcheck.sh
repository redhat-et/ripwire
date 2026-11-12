#!/usr/bin/env bash
# rustmacropathcheck.sh — RUST-MACRO-PATH and RUST-REEXPORT-DUP (#610): Rust edges a written path or a `use` proves.
#   M arms  a macro invocation binds by its path's last segment and through a `use … as` alias (fixture test/rustmacropathfix/macro, a
#           two-crate workspace): `define_thing!(Alpha)` through `use crate::__define_thing as define_thing;`, `crate::__define_thing!(Beta)`,
#           `$crate::other_thing!` inside a `macro_rules!` transcriber, a file-scope `define_thing! { Epsilon }` (a use site, no caller
#           node), and the same three shapes from a second workspace crate (`thing_core::__define_thing!`, axum's
#           `use axum_core::__define_rejection as define_rejection;`). M0 is the bare twin that bound before.
#   N arms  negatives: an outside crate's macro path (`serde_json::json!`, `use serde_json::json as sj; sj!`, `other_crate::__define_thing!`)
#           never binds the in-tree namesake. Each counts its premise (the site is read, under the target's name) and FAILs on zero.
#   X arms  #610 (fixture by @soarkit, test/rustmacropathfix/rx-*): a `pub use` that resolves outside the tree carries no class, and two
#           re-exports of the SAME class agree, so `make()`'s `crate::facade::Config` types `c.get()` (proven); two re-exports of DIFFERENT
#           in-tree classes stay ambiguous (both rows by name, none proven; premise: two Config::get rows).
# usage: bash test/rustmacropathcheck.sh [BIN]   (BIN falls back to RIPWIRE_BIN, then build/ripwire)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-${RIPWIRE_BIN:-$HERE/../build/ripwire}}
case "$BIN" in /*) ;; *) BIN=$PWD/$BIN ;; esac
echo "rustmacropathcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "rustmacropathcheck: no binary at $BIN"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "rustmacropathcheck: python3 required"; exit 2; }
FX=$HERE/rustmacropathfix
T=$(mktemp -d "${TMPDIR:-/tmp}/rustmacropathcheck.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
# the fixtures are copied out, so a run never writes beside the committed files
cp -R "$FX/." "$T/"
M=$T/macro
# ask ROOT VERB SYM: the answer, or FAILED-RUN when the run exits nonzero or prints no schema
ask() {
    local root=$1 verb=$2 sym=$3 out rc
    out=$( cd "$root" && "$BIN" "$root" "--$verb=$sym" --no-cache --legend=compact </dev/null 2>/dev/null )
    rc=$?
    if [ "$rc" != 0 ] || ! printf '%s' "$out" | grep -q 'schema='; then printf 'FAILED-RUN'; return; fi
    printf '%s' "$out"
}
# classify PATH NAME: the <s> row at PATH named NAME is proven (no via), name (via="name") or none
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
    local id=$1 root=$2 verb=$3 sym=$4 path=$5 name=$6 want=$7 got good=no
    got=$( ask "$root" "$verb" "$sym" | classify "$path" "$name" )
    case "$want:$got" in
        present:proven|present:name) good=yes ;;
        *) [ "$got" = "$want" ] && good=yes ;;
    esac
    if [ "$good" = yes ]; then echo "PASS $id ($got)"; else echo "FAIL $id --$verb=$sym -> $path:$name want $want got $got"; fail=1; fi
}
# site ROOT SYM P: how many --uses=SYM rows sit at P (file:line); FAILED-RUN prints -1
site() {
    local out
    out=$( ask "$1" uses "$2" )
    if [ "$out" = "FAILED-RUN" ]; then printf -- '-1'; return; fi
    printf '%s' "$out" | grep -oE "<u [^>]* p=\"$3\"" | grep -c .
}
# usesite ID ROOT SYM P: --uses=SYM lists the site P
usesite() {
    local n
    n=$( site "$2" "$3" "$4" )
    if [ "$n" -ge 1 ]; then echo "PASS $1 (--uses=$3 lists $4)"; else echo "FAIL $1 --uses=$3 does not list $4 (n=$n)"; fail=1; fi
}
# premise ID ROOT SYM P: a negative arm's premise — the outside-path site is read, under the in-tree macro's name; FAIL on zero
premise() {
    local n
    n=$( site "$2" "$3" "$4" )
    if [ "$n" -ge 1 ]; then echo "PASS $1.premise (sites=$n)"; else echo "FAIL $1.premise --uses=$3 lists no site at $4: the negative arm saw nothing"; fail=1; fi
}

MD=thing_core/src/macros.rs
# ---- M: in-crate paths and aliases (thing_core/src/user.rs)
row     M0.bare        "$M" callees gamma        $MD __define_thing present
row     M1.alias       "$M" callees alpha        $MD __define_thing present
row     M2.cratepath   "$M" callees beta         $MD __define_thing present
row     M3.dollarcrate "$M" callers other_thing  $MD wrap_thing     present
usesite M4.filescope   "$M" __define_thing thing_core/src/user.rs:19
# ---- M: another workspace crate's path and alias (app/src/lib.rs)
row     M5.crossalias  "$M" callees app_alias    $MD __define_thing present
row     M6.crosspath   "$M" callees app_path     $MD __define_thing present
usesite M7.crossfile   "$M" __define_thing app/src/lib.rs:16
# ---- N: outside-crate macro paths (thing_core/src/ext.rs, app/src/lib.rs) never bind the in-tree namesake
premise N1 "$M" json thing_core/src/ext.rs:5
row     N1.extpath     "$M" callees ext_path     $MD json           none
premise N2 "$M" json thing_core/src/ext.rs:10
row     N2.extalias    "$M" callees ext_alias    $MD json           none
premise N3 "$M" __define_thing thing_core/src/ext.rs:15
row     N3.extcrate    "$M" callees ext_other    $MD __define_thing none
premise N4 "$M" json app/src/lib.rs:12
row     N4.crossext    "$M" callees app_ext      $MD json           none

# ---- X: #610 re-export bindings (fixture by @soarkit)
row X1.extplusintree "$T/rx-ext"  callees src/app.rs:use_it src/model.rs Config::get proven
row X2.sameclass     "$T/rx-same" callees src/app.rs:use_it src/model.rs Config::get proven
# X3: two re-exports of DIFFERENT in-tree classes stay ambiguous: premise two Config::get rows, then none proven
x3=$( ask "$T/rx-diff" callees src/app.rs:use_it )
x3rows=$( printf '%s' "$x3" | grep -oE '<s [^>]*n="Config::get"[^>]*>' | grep -c . )
x3proven=$( printf '%s' "$x3" | grep -oE '<s [^>]*n="Config::get"[^>]*>' | grep -vc 'via="name"' )
if [ "$x3rows" -lt 2 ]; then echo "FAIL X3.premise want two Config::get rows (two in-tree classes), got $x3rows"; fail=1; else echo "PASS X3.premise (rows=$x3rows)"; fi
if [ "$x3rows" -ge 2 ] && [ "$x3proven" = 0 ]; then echo "PASS X3.diffclass (ambiguous: $x3rows rows by name)"; else echo "FAIL X3.diffclass want every Config::get row via=\"name\", got $x3proven proven of $x3rows"; fail=1; fi

if [ "$fail" = 0 ]; then echo "rustmacropathcheck: PASS"; else echo "rustmacropathcheck: FAIL"; fi
exit "$fail"
