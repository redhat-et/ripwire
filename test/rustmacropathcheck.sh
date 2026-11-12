#!/usr/bin/env bash
# rustmacropathcheck.sh — RUST-MACRO-PATH and RUST-REEXPORT-DUP (#610): Rust edges a written path or a `use` proves.
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
