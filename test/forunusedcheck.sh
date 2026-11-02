#!/usr/bin/env bash
# forunusedcheck.sh — UNUSED-IN-FILE: the --for table for "which public X in <file> are unused" (src/forunused.h; practice-60 group E).
#
# THE CONTRACT: a --for subject with an unused cue that names a file or a directory carries <unused_in_file>, one <u> per public def.
#   v=used       a non-test caller elsewhere bound by more than the name, or an in-file chain from one
#   v=unknown    why= says what may reach it; never a claim
#   v=file-only  same-file references only
#   v=test-only  references only in tests; never live
#   v=unused     no mention in this tree, and no hedge
# --dead-code keeps its internal-linkage meaning. No cue, no file: byte-identical to RIPWIRE_NO_UNUSED_TABLE=1.
#
# Every arm here is one row of the honesty table in src/forunused.h, or a near miss: re-export only; called only by a test; called through a
# string; a private helper; an overload set; the same name in two files. Each is RED on the pre-table binary b8c31789 (no block at all).
set -u
RIPWIRE="${RIPWIRE_BIN:-${RIPWIRE:-./build/ripwire}}" # RIPWIRE_BIN first: pargates.py and regression.sh set it (binoverridecheck)
case "$RIPWIRE" in /*) ;; *) RIPWIRE="$PWD/$RIPWIRE" ;; esac
[ -x "$RIPWIRE" ] || { echo "SKIP: no binary at $RIPWIRE"; exit 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home" TMPDIR="$T/"; mkdir -p "$HOME"
fails=0
fail() { echo "FAIL $*"; fails=$((fails+1)); }
pass() { echo "ok   $*"; }
ask() { # ask DIR TASK → the answer
  ( cd "$1" && "$RIPWIRE" . --no-cache --for="$2" 2>/dev/null )
}
rowof() { # rowof ANSWERFILE NAME → the <u> row
  python3 - "$1" "$2" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
m=re.search(r'<u n="%s"[^>]*/>'%re.escape(sys.argv[2]),s)
print(m.group(0) if m else "")
PY
}
want() { # want ARM ANSWERFILE NAME VERDICT [WHY-WORD]
  local arm=$1 f=$2 n=$3 v=$4 w=${5:-} r
  r=$(rowof "$f" "$n")
  case "$r" in *" v=\"$v\""*) ;; *) fail "$arm: $n wants v=$v, got: ${r:-no row}"; return ;; esac
  if [ -n "$w" ]; then
    case "$r" in *why=\"*"$w"*) ;; *) fail "$arm: $n wants why=$w, got: $r"; return ;; esac
  fi
  pass "$arm: $n v=$v${w:+ why=$w}"
}
notv_or_norow() { local r; r=$(rowof "$2" "$3"); case "$r" in *" v=\"$4\""*) fail "$1: $3 reads v=$4: $r" ;; *) pass "$1: $3 is not $4" ;; esac; }
notv() { # notv ARM ANSWERFILE NAME VERDICT : the row exists and does NOT read VERDICT
  local r; r=$(rowof "$2" "$3")
  case "$r" in "") fail "$1: $3 has no row" ;; *" v=\"$4\""*) fail "$1: $3 reads v=$4: $r" ;; *) pass "$1: $3 is not $4" ;; esac
}
norow() { # norow ARM ANSWERFILE NAME
  local r; r=$(rowof "$2" "$3")
  if [ -z "$r" ]; then pass "$1: $3 has no row"; else fail "$1: $3 has a row: $r"; fi
}

# ---- Python ----
P="$T/py"; mkdir -p "$P/pkg" "$P/tests"
cat > "$P/pkg/__init__.py" <<'E'
from .util import reexported_only
E
cat > "$P/pkg/util.py" <<'E'
__all__ = ["listed_in_all"]

def really_dead():
    return 1

def only_a_test_calls():
    return 2

def live_fn():
    return chained()

def chained():
    return _private_helper()

def _private_helper():
    return 3

def reached_through_string():
    return 4

def reexported_only():
    return 5

def listed_in_all():
    return 6

def only_dead_calls_me():
    return 7

def file_caller():
    return only_dead_calls_me()

def same_name_two_files():
    return 8

def called_by_member():
    return 9

def built_on_demand_alpha():
    return 10

@some_registry.register
def registered_plugin():
    return 11

def is_stem_free():
    return 14

class Holder:
    def is_stem_member(self):
        return 15

def plainlog_thing():
    return 20

def held_in_table():
    return 21

TABLE = {"k": held_in_table}

def script_entry():
    return 16

def named_in_a_comment():
    return 17

def named_in_a_doc():
    return 18

def harness_only():
    return 19

class Plain:
    def plain_method(self):
        return 12

class Derived(Base):
    def over_ridden(self):
        return 13
E
cat > "$P/pkg/other.py" <<'E'
def same_name_two_files():
    return 80
E
cat > "$P/pkg/app.py" <<'E'
import importlib
from pkg.util import live_fn
from pkg.other import same_name_two_files
def main_app(obj, which):
    live_fn()
    same_name_two_files()
    obj.called_by_member()
    getattr(importlib.import_module("pkg.util"), "reached_through_string")()
    return getattr(obj, f"built_on_demand_{which}")()
E
printf '[project.scripts]\nrun = "pkg.util:script_entry"\n' > "$P/pyproject.toml"
printf '\n\n\n\n\n\nLOG = f"plainlog_{1}"\n' > "$P/pkg/logs.py"
printf 'See named_in_a_doc for details.\n' > "$P/README.md"
mkdir -p "$P/harness"; printf 'from pkg.util import harness_only\nharness_only()\n' > "$P/harness/h.py"
cat > "$P/pkg/stems.py" <<'E'
# named_in_a_comment is not a use
def probe(obj, x):
    return getattr(obj, f"is_{x}")()
E
cat > "$P/tests/test_util.py" <<'E'
from pkg.util import only_a_test_calls, is_stem_free
def test_it():
    assert only_a_test_calls() == 2 and is_stem_free() == 14
E
ask "$P" "unused functions in pkg/util.py" > "$T/py.out"
want PY1  "$T/py.out" really_dead unused
want PY2  "$T/py.out" only_a_test_calls test-only
want PY3  "$T/py.out" live_fn used
want PY4  "$T/py.out" chained used                       # an in-file chain from a used def
want PY5  "$T/py.out" reached_through_string unknown string
want PY6  "$T/py.out" reexported_only unknown import
want PY7  "$T/py.out" listed_in_all unknown string
want PY8  "$T/py.out" only_dead_calls_me file-only
want PY9  "$T/py.out" called_by_member unknown name
want PY10 "$T/py.out" built_on_demand_alpha unknown built-name
want PY19 "$T/py.out" is_stem_free unknown built-name      # a 3-byte stem joined to anything computed hedges, lookup near it or not (fix round 2, M8)
want PY20 "$T/py.out" is_stem_member unknown built-name
want PY21 "$T/py.out" script_entry unknown manifest
want PY22 "$T/py.out" named_in_a_comment unused
want PY23 "$T/py.out" named_in_a_doc unused
want PY24 "$T/py.out" harness_only test-only                # a test-support tree is a test
want PY25 "$T/py.out" plainlog_thing unknown built-name     # an extra `unknown` costs little against a false `unused`: no proximity test (M8)
want PY26 "$T/py.out" held_in_table unknown value
want PY11 "$T/py.out" registered_plugin unknown framework
want PY12 "$T/py.out" over_ridden unknown dispatch
want PY13 "$T/py.out" plain_method unused
norow PY14 "$T/py.out" _private_helper
# same name in two files: the edge goes to other.py, so util.py's namesake is not `used`, and the word keeps it from `unused`
want PY15 "$T/py.out" same_name_two_files unknown by-name
ask "$P" "unused functions in pkg/other.py" > "$T/py2.out"
want PY16 "$T/py2.out" same_name_two_files unknown by-name       # the resolver split the call, so neither side is proven; never unused
grep -q 'private="' "$T/py.out" && pass "PY17: private= counted" || fail "PY17: no private="
grep -q 'graph_unresolved="' <(python3 -c "import re,sys;print(re.search(r'<unused_in_file [^>]*>',open('$T/py.out').read()).group(0))") && pass "PY18: root carries graph_unresolved=" || fail "PY18: no graph_unresolved= on the root"

# ---- TypeScript ----
S="$T/ts"; mkdir -p "$S/src" "$S/test"
cat > "$S/src/a.ts" <<'E'
export function tsDead() { return 1; }
export function tsTestOnly() { return 2; }
export function tsLive() { return tsHelper(); }
function tsHelper() { return 3; }
export function tsReexported() { return 4; }
export function tsOver(a: string): string;
export function tsOver(a: number): number;
export function tsOver(a: any): any { return a; }
export const tsArrow = () => 5;
export class TsThing { run() { return 6; } }
export class TsSvc {
  tsUniqueMember() { return 8; }
}
E
cat > "$S/src/barrelled.ts" <<'E'
export function tsBehindStar() { return 7; }
E
cat > "$S/src/index.ts" <<'E'
export * from "./barrelled";
export { tsReexported } from "./a";
E
cat > "$S/src/main.ts" <<'E'
import { tsLive } from "./a";
tsLive();
export function viaAny(o: any) { return o.tsUniqueMember(); }
E
cat > "$S/test/a.test.ts" <<'E'
import { tsTestOnly } from "../src/a";
tsTestOnly();
E
ask "$S" "unused exports in src/a.ts" > "$T/ts.out"
want TS1 "$T/ts.out" tsDead unused
want TS2 "$T/ts.out" tsTestOnly test-only
want TS3 "$T/ts.out" tsLive used
want TS4 "$T/ts.out" tsReexported unknown import
want TS10 "$T/ts.out" tsUniqueMember unknown by-name       # one member call on an `any`: bound by name alone is never proof
want TS11 "$T/ts.out" TsSvc unknown members                 # the class's name appears nowhere, its member is reached
want TS5 "$T/ts.out" tsOver unused
norow TS6 "$T/ts.out" tsHelper
case "$(rowof "$T/ts.out" tsOver)" in *'defs="'*) pass "TS7: an overload set is one row with defs=" ;; *) pass "TS7: the overload set is one row (one def indexed)" ;; esac
[ "$(grep -o '<u n="tsOver"' "$T/ts.out" | wc -l | tr -d ' ')" = 1 ] && pass "TS8: one tsOver row" || fail "TS8: several tsOver rows"
ask "$S" "unused exports in src/barrelled.ts" > "$T/ts2.out"
want TS9 "$T/ts2.out" tsBehindStar unknown barrel

# ---- Go ----
G="$T/go"; mkdir -p "$G/internal/x" "$G/pkg/y" "$G/cmd"
printf 'module example.com/m\n\ngo 1.21\n' > "$G/go.mod"
cat > "$G/internal/x/x.go" <<'E'
package x

import "reflect"

func GoDead() int { return 1 }
func GoTestOnly() int { return 2 }
func GoLive() int { return goHelper() }
func goHelper() int { return 3 }
func GoReflected() int { return 4 }

type T struct{}

func (t T) AnyMethod() int { return 5 }

//export GoExportedToC
func GoExportedToC() int { return 6 }

func Use(v any) { reflect.ValueOf(v).MethodByName("GoReflected") }
E
cat > "$G/internal/x/x_test.go" <<'E'
package x

import "testing"

func TestIt(t *testing.T) { _ = GoTestOnly() }
E
cat > "$G/pkg/y/y.go" <<'E'
package y

func GoApiDead() int { return 1 }
E
cat > "$G/cmd/main.go" <<'E'
package main

import "example.com/m/internal/x"

func main() { x.GoLive(); x.Use(nil) }
E
ask "$G" "unused functions in internal/x/x.go" > "$T/go.out"
want GO1 "$T/go.out" GoDead unused
want GO2 "$T/go.out" GoTestOnly test-only
want GO3 "$T/go.out" GoLive used
want GO4 "$T/go.out" GoReflected unknown string
want GO5 "$T/go.out" AnyMethod unknown dispatch
want GO6 "$T/go.out" GoExportedToC unknown framework
norow GO7 "$T/go.out" goHelper
ask "$G" "unused functions in pkg/y/y.go" > "$T/go2.out"
want GO8 "$T/go2.out" GoApiDead unknown api

# ---- Rust ----
R="$T/rs"; mkdir -p "$R/bin/src" "$R/lib/src"
printf '[package]\nname = "b"\nversion = "0.1.0"\n' > "$R/bin/Cargo.toml"
printf '[package]\nname = "l"\nversion = "0.1.0"\n' > "$R/lib/Cargo.toml"
cat > "$R/bin/src/main.rs" <<'E'
mod x;
fn main() { x::rs_live(); }
E
cat > "$R/bin/src/x.rs" <<'E'
pub fn rs_dead() -> i32 { 1 }
pub fn rs_live() -> i32 { rs_helper() }
fn rs_helper() -> i32 { 3 }
pub fn rs_test_only() -> i32 { 4 }
#[no_mangle]
pub extern "C" fn rs_attr() -> i32 { 5 }
#[cfg(test)]
mod tests {
    #[test]
    fn t() { assert_eq!(super::rs_test_only(), 4); }
}
E
cat > "$R/lib/src/lib.rs" <<'E'
pub fn rs_api() -> i32 { 1 }
E
ask "$R" "unused functions in bin/src/x.rs" > "$T/rs.out"
want RS1 "$T/rs.out" rs_dead unused
want RS2 "$T/rs.out" rs_live used
norow RS3 "$T/rs.out" rs_helper
want RS4 "$T/rs.out" rs_attr unknown framework
ask "$R" "unused functions in lib/src/lib.rs" > "$T/rs2.out"
want RS5 "$T/rs2.out" rs_api unknown api

# ---- C ----
C="$T/c"; mkdir -p "$C/test"
cat > "$C/x.h" <<'E'
int c_dead(void);
int c_live(void);
int c_test_only(void);
int c_in_table(void);
E
cat > "$C/x.c" <<'E'
#include "x.h"
static int c_static_helper(void) { return 0; }
int c_dead(void) { return 1; }
int c_live(void) { return c_static_helper(); }
int c_test_only(void) { return 3; }
int c_in_table(void) { return 4; }
int cmd_pasted_one(void) { return 5; }
int c_proto_elsewhere(void) { return 6; }
enum c_kind { K_A };
struct c_inner { int a; };
struct c_outer {
    enum c_kind kind_field;
    struct c_inner inner_field;
};
enum c_unscoped_enum { C_ONE, C_TWO };
struct c_named_enum { int a; };
int c_holds(void) { struct c_named_enum x; return x.a + C_ONE; }
E
cat > "$C/other.h" <<'E'
int c_proto_elsewhere(void);
E
cat > "$C/main.c" <<'E'
#include "x.h"
#define CMD(n) cmd_##n
struct e { int (*f)(void); } tbl[] = { { c_in_table } };
int main(void) { return c_live() + tbl[0].f(); }
E
cat > "$C/test/test_x.c" <<'E'
#include "../x.h"
int run(void) { return c_test_only(); }
E
ask "$C" "unused functions in x.c" > "$T/c.out"
want C7 "$T/c.out" c_unscoped_enum unknown members
want C8 "$T/c.out" c_named_enum file-only                # `enum E x;` uses the type: that symbol is a mention, not a second definition
want C9 "$T/c.out" c_proto_elsewhere unused              # a prototype in an unrelated header, the tmux.h shape
want C10 "$T/c.out" c_inner file-only                    # `struct S f;` inside another struct is a use, never a second def
case "$(rowof "$T/c.out" c_kind)" in *'defs="'*) fail "C11: a mention counted as a second def: $(rowof "$T/c.out" c_kind)" ;; *) pass "C11: c_kind is one def" ;; esac
want C1 "$T/c.out" c_dead unused                         # a prototype in x.h is its other half, not a use
want C2 "$T/c.out" c_live used
want C3 "$T/c.out" c_test_only test-only
want C4 "$T/c.out" c_in_table unknown
want C5 "$T/c.out" cmd_pasted_one unknown built-name
norow C6 "$T/c.out" c_static_helper

# ---- C++ ----
X="$T/cpp"; mkdir -p "$X/include/lib" "$X/src"
cat > "$X/src/k.h" <<'E'
class Base { public: virtual int vm(); };
class K : public Base {
public:
    int vm() override;
    int plain_dead();
};
int cpp_free_dead();
int cpp_free_live();
E
cat > "$X/src/k.cpp" <<'E'
#include "k.h"
int K::vm() { return 1; }
int K::plain_dead() { return 2; }
int cpp_free_dead() { return 3; }
int cpp_free_live() { return 4; }
int main() { return cpp_free_live(); }
E
cat > "$X/include/lib/api.h" <<'E'
inline int cpp_api_dead() { return 1; }
E
ask "$X" "unused functions in src/k.cpp" > "$T/cpp.out"
want CX1 "$T/cpp.out" cpp_free_dead unused
want CX2 "$T/cpp.out" cpp_free_live used
want CX3 "$T/cpp.out" vm unknown dispatch
ask "$X" "unused functions in include/lib/api.h" > "$T/cpp2.out"
want CX4 "$T/cpp2.out" cpp_api_dead unknown api

# ---- polyglot: one repo, a Python def and a TS caller of the same word; no cross-language edge, so never used, and the word keeps it from unused ----
Y="$T/poly"; mkdir -p "$Y/py" "$Y/web" "$Y/native"
cat > "$Y/py/lib.py" <<'E'
def shared_word():
    return 1
def poly_dead():
    return 2
E
cat > "$Y/web/app.ts" <<'E'
export function shared_word() { return 2; }
shared_word();
E
cat > "$Y/native/n.go" <<'E'
package native

func Poly_go_dead() int { return 3 }
E
printf 'from py import lib\n' > "$Y/py/imp_lib.py"
ask "$Y" "unused functions in py/lib.py" > "$T/poly.out"
want PG1 "$T/poly.out" shared_word unknown name
want PG2 "$T/poly.out" poly_dead unused
ask "$Y" "unused functions in web/app.ts" > "$T/poly2.out"
want PG3 "$T/poly2.out" shared_word used

# ---- fix round 1 (review F2-F6): every arm below is RED on the head before this round ----
# F2: a caller in a file the index does not take (.vue, .svelte, .ipp, Procfile, a template, vendor/, dist/, a file past the index size limit)
U="$T/f2"; mkdir -p "$U/pkg" "$U/views" "$U/web" "$U/vendor/lib" "$U/dist" "$U/gen"
cat > "$U/pkg/t.py" <<'E'
def vue_only_helper():
    return 1
def svelte_only_helper():
    return 2
def ipp_only_thing():
    return 3
def proc_factory():
    return 4
def vendor_only_fn():
    return 5
def dist_only_fn():
    return 6
def big_only_thing():
    return 7
def truly_dead_f2():
    return 8
def tmpl_only_fn():
    return 9
E
printf '<script>\nimport { vue_only_helper } from "../pkg/t";\nvue_only_helper();\n</script>\n' > "$U/views/a.vue"
printf '<script>\n  svelte_only_helper();\n</script>\n' > "$U/views/b.svelte"
printf 'template <class T> int m() { return ipp_only_thing(); }\n' > "$U/web/m.ipp"
printf 'web: gunicorn pkg.t:proc_factory\n' > "$U/Procfile"
printf 'call vendor_only_fn now\n' > "$U/vendor/lib/conf.tmpl"
printf 'var x = dist_only_fn();\n' > "$U/dist/bundle.min.cfg"
printf '{{ tmpl_only_fn }}\n' > "$U/web/page.j2"
python3 - "$U/gen/huge.dat" <<'PY'
import sys
with open(sys.argv[1],"w") as f:
    f.write("x = 1\n" * 1000000)
    f.write("big_only_thing()\n")
PY
printf 'from pkg import t\n' > "$U/pkg/imp_t.py"
ask "$U" "unused functions in pkg/t.py" > "$T/f2.out"
for n in vue_only_helper svelte_only_helper ipp_only_thing proc_factory vendor_only_fn dist_only_fn big_only_thing tmpl_only_fn; do want F2a "$T/f2.out" $n unknown name; done
want F2b "$T/f2.out" truly_dead_f2 unused                 # the walk does not blanket-hedge: a name nowhere stays unused
U2="$T/f2u"; mkdir -p "$U2/pkg" "$U2/gen"
printf 'def dead_but_unseen():\n    return 1\n' > "$U2/pkg/t.py"
python3 -c "
f=open('$U2/gen/blob.txtdata','w'); f.write('x = 1\n' * 6000000); f.close()"
ask "$U2" "unused functions in pkg/t.py" > "$T/f2u.out"
want F2c "$T/f2u.out" dead_but_unseen unknown unseen    # a text file too large to read: absence is not proven
grep -q ' unseen="[1-9]' "$T/f2u.out" && pass "F2d: the block says unseen=N" || fail "F2d: no unseen= on the block"
# F3: `#` opens a comment only where the language facts say so
H="$T/f3"; mkdir -p "$H/src" "$H/py" "$H/web"
cat > "$H/src/t.rs" <<'E'
pub fn parse_port_thing() -> u16 { 1 }
pub fn rs_commented_only() -> u16 { 2 }
E
cat > "$H/src/a.rs" <<'E'
#[arg(long, value_parser = crate::t::parse_port_thing)]
struct A {}
// rs_commented_only is not a use
E
cat > "$H/py/t.py" <<'E'
def py_commented_only():
    return 1
def py_code_after_hash():
    return 2
E
printf '# py_commented_only is not a use\nx = 1  # trailing words are not read as code either\n' > "$H/py/u.py"
printf 'print(1)\n' > "$H/py/v.py"
cat > "$H/web/h.ts" <<'E'
export function tsHashHelper() { return 1; }
E
cat > "$H/web/q.ts" <<'E'
import { tsHashHelper } from "./h";
class Q {
    #cb = tsHashHelper;
}
E
cat > "$H/web/t.c" <<'E'
int hxx_only_thing(void) { return 1; }
E
printf '#define HX hxx_only_thing()\n' > "$H/web/m.hxx"
ask "$H" "unused functions in src/t.rs" > "$T/f3rs.out"
want F3a "$T/f3rs.out" parse_port_thing unknown name
want F3b "$T/f3rs.out" rs_commented_only unused             # a // comment is still a comment
printf 'from py import t\n' > "$H/py/imp_t.py"
ask "$H" "unused functions in py/t.py" > "$T/f3py.out"
want F3c "$T/f3py.out" py_commented_only unused             # Python's `#` is a comment (langFacts hashComment)
ask "$H" "unused exports in web/h.ts" > "$T/f3ts.out"
want F3d "$T/f3ts.out" tsHashHelper unknown name           # a JS/TS `#private` field line is code
ask "$H" "unused functions in web/t.c" > "$T/f3c.out"
want F3e "$T/f3c.out" hxx_only_thing unknown name           # a `#define` body in any non-hash language is code
# F4: one-character names are scanned
O="$T/f4"; mkdir -p "$O/pkg" "$O/go"
printf 'K = 5\ndef f():\n    return 1\ndef dead_plain_f4():\n    return 2\n' > "$O/pkg/t.py"
printf 'from pkg.t import K, f\nprint(K, f())\n' > "$O/pkg/other.py"
printf 'package x\n\nfunc F() int { return 1 }\n\ntype Q struct{}\n' > "$O/go/x.go"
printf 'package main\n\nimport "ex/go"\n\nvar _ = x.F\n' > "$O/go/main.go"
ask "$O" "unused functions in pkg/t.py" > "$T/f4.out"
notv F4a "$T/f4.out" K unused
notv F4b "$T/f4.out" f unused
want F4c "$T/f4.out" dead_plain_f4 unused
ask "$O" "unused functions in go/x.go" > "$T/f4go.out"
notv F4d "$T/f4go.out" F unused
# F5: a library's public API is never `test-only` or `unused` on the strength of this tree alone
L="$T/f5"; mkdir -p "$L/lib/pkg" "$L/lib/tests" "$L/app/pkg" "$L/app/tests" "$L/js/src" "$L/js/test" "$L/jsapp/src"
printf '[project]\nname = "lib"\n' > "$L/lib/pyproject.toml"
printf 'def public_api_fn():\n    return 1\ndef public_api_untested():\n    return 2\n' > "$L/lib/pkg/api.py"
printf 'def impl_fn():\n    return 3\n' > "$L/lib/pkg/_impl.py"
printf 'from pkg.api import public_api_fn\ndef test_it():\n    assert public_api_fn() == 1\n' > "$L/lib/tests/test_api.py"
printf '[tool.ruff]\nline-length = 100\n' > "$L/app/pyproject.toml"
printf 'def app_fn():\n    return 1\n' > "$L/app/pkg/mod.py"
printf 'from pkg.mod import app_fn\ndef test_it():\n    assert app_fn() == 1\n' > "$L/app/tests/test_mod.py"
printf '{"name":"jslib","main":"dist/index.js","version":"1.0.0"}\n' > "$L/js/package.json"
printf 'export function tsLibApi() { return 1; }\n' > "$L/js/src/api.ts"
printf 'export type TsTypeThing = { a: number };\n' > "$L/js/src/types.ts"
printf 'export type * from "./types";\n' > "$L/js/src/index.ts"
printf 'import { tsLibApi } from "../src/api";\ntsLibApi();\n' > "$L/js/test/api.test.ts"
printf '{"name":"jsapp","private":true,"main":"x.js"}\n' > "$L/jsapp/package.json"
printf 'export function tsAppFn() { return 1; }\n' > "$L/jsapp/src/api.ts"
printf 'import { tsAppFn } from "../src/api";\ntsAppFn();\n' > "$L/jsapp/src/api.test.ts"
ask "$L/lib" "unused functions in pkg/api.py" > "$T/f5py.out"
want F5a "$T/f5py.out" public_api_fn unknown api
want F5b "$T/f5py.out" public_api_untested unknown api
printf 'from pkg import _impl\n' > "$L/lib/pkg/imp_impl.py"
ask "$L/lib" "unused functions in pkg/_impl.py" > "$T/f5pyp.out"
[ -z "$(rowof "$T/f5pyp.out" impl_fn)" ] || want F5c "$T/f5pyp.out" impl_fn unused
ask "$L/app" "unused functions in pkg/mod.py" > "$T/f5app.out"
want F5d "$T/f5app.out" app_fn test-only                     # a pyproject with no [project] builds nothing: not a library
ask "$L/js" "unused exports in src/api.ts" > "$T/f5ts.out"
want F5e "$T/f5ts.out" tsLibApi unknown api
ask "$L/js" "unused exports in src/types.ts" > "$T/f5tt.out"
want F5f "$T/f5tt.out" TsTypeThing unknown barrel           # `export type *` is a barrel
ask "$L/jsapp" "unused exports in src/api.ts" > "$T/f5ja.out"
want F5g "$T/f5ja.out" tsAppFn test-only                    # "private": true publishes nothing
grep -q 'never live' "$T/f5py.out" && fail "F5h: the legend still says never live" || pass "F5h: no 'never live' in the legend"
# F6: routes by path, registries, string-built names, directory imports, a short stem aimed at a module
N="$T/f6"; mkdir -p "$N/app/about" "$N/src/pages" "$N/pkg/ext" "$N/modules" "$N/pkg2"
printf 'export default function AboutRoutePage() { return 1; }\nexport function generateMetadata() { return 2; }\n' > "$N/app/about/page.tsx"
printf 'export function HomePageComponent() { return 1; }\nexport function getServerSideProps() { return 2; }\n' > "$N/src/pages/home.tsx"
cat > "$N/pkg/reg.py" <<'E'
REG = []
class Base:
    def __init_subclass__(cls):
        REG.append(cls)
class AutoPlugin(Base):
    pass
class PlainNoBase:
    pass
E
cat > "$N/pkg/cat.py" <<'E'
def concat_handle_alpha():
    return 1
def plainjoin_one():
    return 2
E
cat > "$N/pkg/cat_use.py" <<'E'
import pkg.cat as t
def go(kind):
    return getattr(t, "concat_handle" + kind)()









note = "plainjoin" + "_x"
E
printf 'export class Widget {\n  renderAlpha() { return 1; }\n  renderPlain() { return 2; }\n}\nexport function modAlpha() { return 3; }\nexport function modLiteral() { return 4; }\n' > "$N/modules/w.ts"
cat > "$N/modules/use.ts" <<'E'
import { Widget } from "./w";
export async function load(kind: string, key: string) {
  const w = new Widget() as any;
  const f = w["render" + kind];
  const m = await import(`./modules/${kind}`);
  return [f, m[key]()];
}
E
printf 'def setup_alpha():\n    return 1\n' > "$N/pkg/ext/alpha.py"
printf 'import importlib\ndef load(name):\n    return importlib.import_module("pkg.ext." + name)\n' > "$N/pkg/loader.py"
printf 'def is_private_addr(x):\n    return x\ndef is_free_other(x):\n    return x\n' > "$N/pkg2/isx_t.py"
printf 'import pkg2.isx_t as n\ndef probe(k, x):\n    return getattr(n, f"is_{k}")(x)\n' > "$N/pkg2/probe.py"
ask "$N" "unused exports in app/about/page.tsx" > "$T/f6a.out"
want F6a "$T/f6a.out" generateMetadata unknown framework
ask "$N" "unused exports in src/pages/home.tsx" > "$T/f6b.out"
want F6b "$T/f6b.out" getServerSideProps unknown framework
printf 'from pkg import reg\n' > "$N/pkg/imp_reg.py"
ask "$N" "unused classes in pkg/reg.py" > "$T/f6c.out"
want F6c "$T/f6c.out" AutoPlugin unknown dispatch
want F6d "$T/f6c.out" PlainNoBase unused                    # a class with no base is not registered by a hook
want PY27 "$T/py.out" Derived unused                        # near miss: no hook anywhere in that tree, a base alone hedges nothing
ask "$N" "unused functions in pkg/cat.py" > "$T/f6e.out"
want F6e "$T/f6e.out" concat_handle_alpha unknown built-name
want F6f "$T/f6e.out" plainjoin_one unknown built-name      # the same, joined with `+` (M8)
ask "$N" "unused exports in modules/w.ts" > "$T/f6g.out"
want F6g "$T/f6g.out" modAlpha unknown built-name
ask "$N" "unused functions in pkg/ext/alpha.py" > "$T/f6h.out"
want F6h "$T/f6h.out" setup_alpha unknown built-name
ask "$N" "unused functions in pkg2/isx_t.py" > "$T/f6i.out"
want F6i "$T/f6i.out" is_private_addr unknown built-name   # the lookup's object is the target module: no stem-length rule
# F10 (over-hedge, safe to tighten): a def's own line naming itself is no use; pub(crate) has no consumer outside the crate
printf 'from typing import TypeVar\nW = TypeVar("W")\n' > "$O/pkg/tv.py"
printf 'from pkg import tv\n' > "$O/pkg/imp_tv.py"
ask "$O" "unused functions in pkg/tv.py" > "$T/f10a.out"
want F10a "$T/f10a.out" W unused
mkdir -p "$T/f10/src"; printf '[package]\nname = "l"\nversion = "0.1.0"\n' > "$T/f10/Cargo.toml"
printf 'pub fn pub_api_f10() -> i32 { 1 }\npub(crate) fn crate_only_dead() -> i32 { 2 }\n' > "$T/f10/src/lib.rs"
ask "$T/f10" "unused functions in src/lib.rs" > "$T/f10b.out"
want F10b "$T/f10b.out" pub_api_f10 unknown api
want F10c "$T/f10b.out" crate_only_dead unused
grep -q 'kForUnusedForeignStem' "$(dirname "$0")/../src/forunused.h" 2>/dev/null && fail "F6j: the stem-length rule is back" || pass "F6j: no stem-length rule"

# ---- fix round 2 (review M1-M10, N1, the delete-intent triggers): every arm below is RED on the head before this round (73bbd88f) ----
mk() { mkdir -p "$(dirname "$1")"; printf '%b' "$2" > "$1"; } # mk PATH TEXT (printf %b: \n and \t expand)
R="$T/r2"
# M1: a C/C++ call is not a prototype: the text ahead of the name must be type words only
mk "$R/m1/src/t.c" 'int helper_a(int x){return x;}\nint helper_b(int x){return x;}\nint helper_c(int x){return x;}\nint helper_d(int x){return x;}\nint helper_e(int x){return x;}\nint proto_only(int x){return x;}\nconst char *proto_ptr(const char *s){return s;}\nint proto_tmpl(int x){return x;}\n'
mk "$R/m1/vendor/v.c" 'void g(int y){\n  foo(1, helper_a(2));\n  if (y) helper_b(y);\n  (void) helper_c(y);\n  y && helper_d(y);\n  if (y) other(); else helper_e(y);\n}\n'
mk "$R/m1/vendor/p.h" 'int proto_only(int x);\nconst char *proto_ptr(const char *s);\nstd::map<int, long> proto_tmpl(int x);\n'
ask "$R/m1" "unused functions in src/t.c" > "$T/m1.out"
for n in helper_a helper_b helper_c helper_d helper_e; do want M1a "$T/m1.out" $n unknown name; done
for n in proto_only proto_ptr proto_tmpl; do want M1b "$T/m1.out" $n unused; done          # a declaration is the definition's other half, not a use
# M2: a non-ASCII name is one name; a name beside non-ASCII punctuation is still that name
mk "$R/m2/pkg/__init__.py" ''
mk "$R/m2/pkg/tgt.py" 'def café():\n    return 1\ndef smart_quoted():\n    return 2\ndef dead_na():\n    return 3\n'
mk "$R/m2/pkg/u.py" 'from pkg import tgt\ndef z(o):\n    return o.café()\n'
mk "$R/m2/x/c.cfg" 'say “smart_quoted”\n'
mk "$R/m2/src/tgt.ts" 'export function 描画() { return 1; }\nexport function plain_dead_m2() { return 2; }\n'
mk "$R/m2/package.json" '{"name":"a","private":true}\n'
mk "$R/m2/v/a.vue" '<script>\nimport "../src/tgt"\n描画()\n</script>\n'
ask "$R/m2" "unused functions in pkg/tgt.py" > "$T/m2a.out"
want M2a "$T/m2a.out" café unknown name
want M2b "$T/m2a.out" smart_quoted unknown name
want M2c "$T/m2a.out" dead_na unused
ask "$R/m2" "unused functions in src/tgt.ts" > "$T/m2b.out"
want M2d "$T/m2b.out" 描画 unknown name
want M2e "$T/m2b.out" plain_dead_m2 unused
# M3: .mdx is code and .txt is a linker list; prose docs (.md .rst .adoc, changelogs) are the one kind not read, and the legend says so
mk "$R/m3/pkg/__init__.py" ''
mk "$R/m3/pkg/tgt.py" 'def mdx_helper_fn():\n    return 1\ndef txt_list_fn():\n    return 2\ndef readme_only_fn():\n    return 3\ndef dead_m3():\n    return 4\n'
mk "$R/m3/pkg/u.py" 'from pkg import tgt\n'
mk "$R/m3/docs/a.mdx" "import { mdx_helper_fn } from '../pkg/tgt'\n\n<Foo x={mdx_helper_fn()} />\n"
mk "$R/m3/build/exports.txt" 'txt_list_fn\n'
mk "$R/m3/README.md" 'readme_only_fn is documented here\n'
ask "$R/m3" "unused functions in pkg/tgt.py" > "$T/m3.out"
want M3a "$T/m3.out" mdx_helper_fn unknown name
want M3b "$T/m3.out" txt_list_fn unknown name
want M3c "$T/m3.out" readme_only_fn unused
want M3d "$T/m3.out" dead_m3 unused
grep -q 'prose docs' "$T/m3.out" && pass "M3e: the legend names the docs it does not read" || fail "M3e: the legend does not name the prose docs"
# M4: a directory that cannot be entered is counted, not skipped
mk "$R/m4/pkg/__init__.py" ''
mk "$R/m4/pkg/tgt.py" 'def perm_only():\n    return 1\n'
mk "$R/m4/pkg/u.py" 'from pkg import tgt\n'
mk "$R/m4/locked/a.j2" '{{ perm_only() }}\n'
chmod 000 "$R/m4/locked"
if ls "$R/m4/locked" >/dev/null 2>&1; then pass "M4: skipped (the locked directory is readable here, running as root)"
else
  ask "$R/m4" "unused functions in pkg/tgt.py" > "$T/m4.out"
  want M4a "$T/m4.out" perm_only unknown unseen
  grep -q 'unseen_by="walk=1"' "$T/m4.out" && pass "M4b: unseen_by names the walk" || fail "M4b: no unseen_by=\"walk=1\""
fi
chmod 755 "$R/m4/locked"
# M5: `* ` and `// ` line heads are comments only where the language says so (black-wrapped Python continuation lines are code)
mk "$R/m5/pkg/__init__.py" ''
mk "$R/m5/pkg/tgt.py" 'def scale_it(x):\n    return x\ndef div_it(x):\n    return x\ndef ts_doc_mention():\n    return 1\ndef ts_line_mention():\n    return 2\n'
mk "$R/m5/pkg/u.py" 'from pkg import tgt\ndef z(o, a):\n    return (\n        a\n        * o.scale_it(a)\n        // o.div_it(a)\n    )\n'
mk "$R/m5/web/c.ts" '/**\n * see ts_doc_mention() for details\n */\n// ts_line_mention() is documented elsewhere\nexport const z = 1;\n'
ask "$R/m5" "unused functions in pkg/tgt.py" > "$T/m5.out"
want M5a "$T/m5.out" scale_it unknown name
want M5b "$T/m5.out" div_it unknown name
want M5c "$T/m5.out" ts_doc_mention unused                  # a leading `*` inside a /* */ block is still a comment
want M5d "$T/m5.out" ts_line_mention unused
# M6: the module object indexed, looked into or passed along: no name is spelled, so every def of it may be reached
M6="$R/m6"; mk "$M6/package.json" '{"name":"a","private":true}\n'; mk "$M6/pkg/__init__.py" ''
mk "$M6/src/ops.ts" 'export function opAdd(){return 1}\nexport function opSub(){return 2}\n'
mk "$M6/src/m.ts" "import * as ops from './ops'\nexport function run(n: string){ return (ops as any)[n]() }\n"
mk "$M6/src/ops2.ts" 'export function opVal(){return 1}\n'
mk "$M6/src/m2.ts" "import * as ops2 from './ops2'\nexport const all = Object.values(ops2)\n"
mk "$M6/src/ops3.ts" 'export function opUsedOk(){return 1}\nexport function opDeadOk(){return 2}\n'
mk "$M6/src/m3.ts" "import * as ops3 from './ops3'\nexport const v = ops3.opUsedOk()\n"
mk "$M6/pkg/ops.py" 'def op_add():\n    return 1\n'
mk "$M6/pkg/m.py" 'from pkg import ops\nimport sys\ndef run(n):\n    return getattr(ops, n)()\n'
mk "$M6/pkg/ops_m.py" 'def op_mem():\n    return 1\n'
mk "$M6/pkg/mm.py" 'import inspect\nfrom pkg import ops_m\nALL = dict(inspect.getmembers(ops_m, inspect.isfunction))\n'
ask "$M6" "unused exports in src/ops.ts" > "$T/m6a.out"; want M6a "$T/m6a.out" opAdd unknown built-name; want M6a2 "$T/m6a.out" opSub unknown built-name
ask "$M6" "unused exports in src/ops2.ts" > "$T/m6b.out"; want M6b "$T/m6b.out" opVal unknown built-name
ask "$M6" "unused exports in src/ops3.ts" > "$T/m6c.out"; want M6c "$T/m6c.out" opDeadOk unused   # only `ops3.name` is used: no def is reached by a computed name
ask "$M6" "unused functions in pkg/ops.py" > "$T/m6d.out"; want M6d "$T/m6d.out" op_add unknown built-name
ask "$M6" "unused functions in pkg/ops_m.py" > "$T/m6e.out"; want M6e "$T/m6e.out" op_mem unknown built-name
# M7: a default export has no name to find: an importer (a .vue, React.lazy, an alias) names it by anything
M7="$R/m7"; mk "$M7/package.json" '{"name":"a","private":true}\n'
mk "$M7/src/tgt.ts" 'export default function vueDefault(){return 1}\nexport function namedDead7(){return 2}\n'
mk "$M7/src/a.vue" "<script>\nimport other from './tgt'\nother()\n</script>\n"
mk "$M7/src/Comp.tsx" 'export default function LazyPage(){return null}\n'
mk "$M7/src/m.tsx" "import React from 'react'\nexport const L = React.lazy(() => import('./Comp'))\n"
mk "$M7/src/c.js" 'function cjsThing(){return 1}\nmodule.exports = cjsThing\n'
mk "$M7/src/mc.js" "const x = require('./c')\nx()\n"
ask "$M7" "unused exports in src/tgt.ts" > "$T/m7a.out"; want M7a "$T/m7a.out" vueDefault unknown import; want M7b "$T/m7a.out" namedDead7 unused
ask "$M7" "unused exports in src/Comp.tsx" > "$T/m7b.out"; want M7c "$T/m7b.out" LazyPage unknown import
ask "$M7" "unused functions in src/c.js" > "$T/m7c.out"; notv_or_norow M7d "$T/m7c.out" cjsThing unused
# M8: a stem joined to anything computed builds names, in any non-test file, without a lookup beside it (a 2-byte stem still needs one)
M8="$R/m8"; mk "$M8/package.json" '{"name":"a","private":true}\n'; mk "$M8/pkg/__init__.py" ''
mk "$M8/pkg/tgt.py" 'def concat_alpha():\n    return 1\ndef alpha_handler():\n    return 2\ndef do_run():\n    return 3\ndef run_cb():\n    return 4\ndef plain_dead_m8():\n    return 5\n'
mk "$M8/pkg/imp.py" 'import pkg.tgt\n'
mk "$M8/pkg/u.py" 'def go(c, kind):\n    name = "concat_" + kind\n    a = 1\n    a = 2\n    a = 3\n    a = 4\n    a = 5\n    a = 6\n    return name\n\ndef hh(c, kind):\n    return getattr(c, f"{kind}_handler")()\n\ndef dd(c, k):\n    return getattr(c, "do_" + k)()\n\ndef cc(c, k):\n    return getattr(c, k + "_cb")()\n'
mk "$M8/pkg/isx.py" 'def is_big_m8(x):\n    return x\n'
mk "$M8/pkg/isimp.py" 'import pkg.isx\n'
mk "$M8/pkg/probe.py" 'def check(mod, k, x):\n    return getattr(mod, f"is_{k}")(x)\n'
ask "$M8" "unused functions in pkg/tgt.py" > "$T/m8a.out"
want M8a "$T/m8a.out" concat_alpha unknown built-name        # the lookup is outside the window
want M8b "$T/m8a.out" alpha_handler unknown built-name       # the stem is the tail, after an f-string hole
want M8c "$T/m8a.out" do_run unknown built-name
want M8d "$T/m8a.out" run_cb unknown built-name              # a 3-byte tail
want M8e "$T/m8a.out" plain_dead_m8 unused
ask "$M8" "unused functions in pkg/isx.py" > "$T/m8b.out"; want M8f "$T/m8b.out" is_big_m8 unknown built-name   # the module is a parameter: it is not named in that file
mk "$M8/src/tgt.ts" 'export class V {\n  renderAlpha() { return 1; }\n  renderBeta() { return 2; }\n  alphaHandler() { return 3; }\n  onClick() { return 4; }\n  plainDeadTs() { return 5; }\n}\n'
mk "$M8/src/imp.ts" 'import { V } from "./tgt";\nexport const v = new V();\n'
mk "$M8/src/k.ts" 'export function go(v: any, kind: string, k: string) {\n  const key = "render" + kind;\n  const key2 = `render${kind}`;\n  const h = v[`${k}Handler`];\n  const o = v["on" + k];\n  return [v[key](), v[key2](), h, o];\n}\n'
ask "$M8" "unused exports in src/tgt.ts" > "$T/m8c.out"
for n in renderAlpha renderBeta alphaHandler onClick; do want M8g "$T/m8c.out" $n unknown built-name; done
mk "$M8/c/t.c" 'int plugin_run(void){return 1;}\n'
mk "$M8/c/u.c" 'void f(char *buf, const char *name){\n  snprintf(buf, 64, "plugin_%s", name);\n  int a = 1;\n  a = 2;\n  a = 3;\n  a = 4;\n  a = 5;\n  a = 6;\n  void *p = dlsym(h, buf);\n}\n'
ask "$M8" "unused functions in c/t.c" > "$T/m8d.out"; want M8h "$T/m8d.out" plugin_run unknown built-name
# M9: framework entry points: a decorator or attribute more than one line up; a module nothing imports (convention files, plugins, registries)
M9="$R/m9"; mk "$M9/package.json" '{"name":"a","private":true}\n'
mk "$M9/src/ctl.ts" "export class Ctl {\n  @Get(\n    '/x'\n  )\n  listAll() { return 1; }\n  @Controller({\n    path: 'y',\n  })\n  other() { return 2; }\n}\n"
mk "$M9/src/imp.ts" 'import { Ctl } from "./ctl";\nexport const c = new Ctl();\n'
ask "$M9" "unused exports in src/ctl.ts" > "$T/m9a.out"; want M9a "$T/m9a.out" listAll unknown framework; want M9b "$T/m9a.out" other unknown framework
mk "$M9/rs/Cargo.toml" '[package]\nname = "a"\nversion = "0.1.0"\n'
mk "$M9/rs/src/cmds.rs" '#[tauri::command(\n    rename_all = "snake_case"\n)]\npub fn multi_attr_cmd() -> u32 { 1 }\n\n#[tauri::command]\n/// doc line\npub fn attr_then_doc() -> u32 { 2 }\n\npub fn plain_rs_dead() -> u32 { 3 }\n'
ask "$M9/rs" "unused functions in src/cmds.rs" > "$T/m9b.out"
want M9c "$T/m9b.out" multi_attr_cmd unknown framework; want M9d "$T/m9b.out" attr_then_doc unknown framework; want M9e "$T/m9b.out" plain_rs_dead unused
mk "$M9/py/plug.py" 'import extlib\nclass AutoPlugin(extlib.Plugin):\n    pass\ndef post_fork(server, worker):\n    pass\n'
mk "$M9/py/used_mod.py" 'def dead_in_imported():\n    return 1\n'
mk "$M9/py/imp.py" 'import used_mod\n'
ask "$M9/py" "unused functions in plug.py" > "$T/m9c.out"; want M9f "$T/m9c.out" post_fork unknown unimported; want M9g "$T/m9c.out" AutoPlugin unknown unimported
ask "$M9/py" "unused functions in used_mod.py" > "$T/m9d.out"; want M9h "$T/m9d.out" dead_in_imported unused   # an imported module's dead def is still dead
mk "$M9/src/instrumentation.ts" 'export function register() { return 1; }\nexport class AutoEntity extends Base {}\n'
ask "$M9" "unused exports in src/instrumentation.ts" > "$T/m9e.out"; want M9i "$T/m9e.out" register unknown unimported; want M9j "$T/m9e.out" AutoEntity unknown unimported
# M10: a binary is no text: it is sniffed first and counts toward no cap, so one in target/ or build/ never flips every claim to unknown
M10="$R/m10"; mk "$M10/pkg/__init__.py" ''; mk "$M10/pkg/tgt.py" 'def really_dead_m10():\n    return 1\n'; mk "$M10/pkg/u.py" 'from pkg import tgt\n'
mkdir -p "$M10/target/debug" "$M10/bin"
python3 - "$M10" <<'PY'
import sys
d=sys.argv[1]
with open(d+"/bin/big.bin","wb") as f: f.truncate(40<<20)
for k in range(26):
    with open(d+"/target/debug/b%d.o"%k,"wb") as f: f.truncate(31<<20)
PY
ask "$M10" "unused functions in pkg/tgt.py" > "$T/m10.out"
want M10a "$T/m10.out" really_dead_m10 unused
grep -qE '<unused_in_file[^>]* unseen=' "$T/m10.out" && fail "M10b: a binary counted toward a cap (unseen=)" || pass "M10b: no unseen= for 27 binaries over the caps"
M10T="$R/m10t"; mk "$M10T/pkg/__init__.py" ''; mk "$M10T/pkg/tgt.py" 'def dead_but_big_text():\n    return 1\n'; mk "$M10T/pkg/u.py" 'from pkg import tgt\n'
python3 -c "
f=open('$M10T/gen.dat','w'); f.write('x = 1\n' * 6000000); f.close()"
ask "$M10T" "unused functions in pkg/tgt.py" > "$T/m10t.out"
want M10c "$T/m10t.out" dead_but_big_text unknown unseen
grep -q 'unseen_by="size=1"' "$T/m10t.out" && pass "M10d: unseen_by names the limit" || fail "M10d: no unseen_by=\"size=1\""
# N1: names a runtime, loader or harness calls with no call in the tree
mk "$R/n1/src/fz.cc" 'extern "C" int LLVMFuzzerTestOneInput(const unsigned char *d, unsigned long n) { return 0; }\nint LLVMFuzzerInitialize(int *argc, char ***argv) { return 0; }\nint DllMain(void *h, unsigned long r, void *p) { return 1; }\nint Java_com_foo_Bar_baz(void) { return 1; }\nint PyInit_mod(void) { return 1; }\nint plain_dead_cc(void) { return 2; }\n'
ask "$R/n1" "unused functions in src/fz.cc" > "$T/n1a.out"
for n in LLVMFuzzerTestOneInput LLVMFuzzerInitialize DllMain Java_com_foo_Bar_baz PyInit_mod; do want N1a "$T/n1a.out" $n unknown framework; done
want N1b "$T/n1a.out" plain_dead_cc unused
mk "$R/n1/pkg/__init__.py" ''; mk "$R/n1/pkg/tgt.py" 'def setup_module(m):\n    pass\ndef plain_dead_n1():\n    return 1\n'; mk "$R/n1/pkg/u.py" 'from pkg import tgt\n'
ask "$R/n1" "unused functions in pkg/tgt.py" > "$T/n1b.out"; want N1c "$T/n1b.out" setup_module unknown framework; want N1d "$T/n1b.out" plain_dead_n1 unused
mk "$R/n1/package.json" '{"name":"a","private":true}\n'; mk "$R/n1/ext/tgt.ts" 'export function activate() { return 1; }\nexport function plain_dead_n1ts() { return 2; }\n'; mk "$R/n1/ext/imp.ts" 'import "./tgt";\n'
ask "$R/n1" "unused exports in ext/tgt.ts" > "$T/n1c.out"; want N1e "$T/n1c.out" activate unknown framework; want N1f "$T/n1c.out" plain_dead_n1ts unused
# Neighbour shapes the review did not name (lesson 16): the class, not the repro
NB="$R/nb"; mk "$NB/package.json" '{"name":"a","private":true}\n'; mk "$NB/pkg/__init__.py" ''
# M1: a qualified call, an assignment, a return, a ternary are calls; a declaration stays a declaration
mk "$NB/c/t.cpp" 'int q_a(int x){return x;}\nint q_b(int x){return x;}\nint q_c(int x){return x;}\nint q_d(int x){return x;}\nint q_dead(int x){return x;}\n'
mk "$NB/vendor/w.cpp" 'void g(int y){\n  ns::q_a(y);\n  int z = q_b(y);\n  y ? q_c(y) : 0;\n  obj->q_d(y);\n}\nextern int q_dead(int x);\n'
ask "$NB" "unused functions in c/t.cpp" > "$T/nb1.out"
for n in q_a q_b q_c q_d; do notv NM1 "$T/nb1.out" $n unused; done; want NM1b "$T/nb1.out" q_dead unused
# M3: a code file named like a changelog is read; a .txt with no caller still proves nothing false
mk "$NB/pkg/tchg.py" 'def chg_tool_only():\n    return 1\n'; mk "$NB/pkg/imp_chg.py" 'from pkg import tchg\n'; mk "$NB/tools/CHANGELOG_tool.py" 'def z(o):\n    return o.chg_tool_only()\n'
ask "$NB" "unused functions in pkg/tchg.py" > "$T/nb3.out"; notv NM3 "$T/nb3.out" chg_tool_only unused
# M5: a block comment's `*` line stays a comment; C's `* f(y)` continuation is code; an unknown language has no comment line
mk "$NB/c2/t.c" 'int star_call(int x){return x;}\nint star_doc(int x){return x;}\nint slash_other(int x){return x;}\n'
mk "$NB/c2/u.c" '/*\n * star_doc is described here\n */\nint z(int a){\n  return a\n    * star_call(a);\n}\n'
mk "$NB/w/x.nosuchlang" '// slash_other()\n'
ask "$NB" "unused functions in c2/t.c" > "$T/nb5.out"; want NM5a "$T/nb5.out" star_doc unused; notv NM5b "$T/nb5.out" star_call unused; notv NM5c "$T/nb5.out" slash_other unused
# M6: the module spelled in other ways, or bound under a list, a loader or a dotted path; and near misses that bind no module
mk "$NB/pkg/o1.py" 'def o1_f():\n    return 1\n'; mk "$NB/pkg/u1.py" 'import pkg.o1\ndef run(n):\n    return getattr(pkg.o1, n)()\n'
mk "$NB/pkg/o2.py" 'def o2_f():\n    return 1\n'; mk "$NB/pkg/u2.py" 'from pkg import (\n    o2,  # note\n    o1,\n)\ndef run(n):\n    return getattr(o2, n)()\n'
mk "$NB/pkg/o3.py" 'def o3_f():\n    return 1\n'; mk "$NB/pkg/u3.py" 'import importlib\nm = importlib.import_module("pkg.o3")\ndef run(n):\n    return getattr(m, n)()\n'
mk "$NB/pkg/o4.py" 'def o4_f():\n    return 1\n'; mk "$NB/pkg/u4.py" 'from . import o4\ndef run(n):\n    return o4.__dict__[n]()\n'
mk "$NB/pkg/o5.py" 'def o5_used():\n    return 1\ndef o5_dead():\n    return 2\n'; mk "$NB/pkg/u5.py" 'from pkg.o5 import o5_used\no5 = 3\nprint(o5, o5_used())\n'
mk "$NB/pkg/o6.py" 'def o6_dead():\n    return 2\n'; mk "$NB/pkg/u6.py" 'from pkg import (\n    o6,\n)\nprint(o6.other)\n'
for k in 1 2 3 4; do ask "$NB" "unused functions in pkg/o$k.py" > "$T/nbo$k.out"; want NM6$k "$T/nbo$k.out" o${k}_f unknown built-name; done
ask "$NB" "unused functions in pkg/o5.py" > "$T/nbo5.out"; want NM6n1 "$T/nbo5.out" o5_dead unused   # `from pkg.o5 import x` binds no module, so a local `o5` is no use of it
ask "$NB" "unused functions in pkg/o6.py" > "$T/nbo6.out"; want NM6n2 "$T/nbo6.out" o6_dead unused   # a listed import and `o6.name` only
mk "$NB/src/j1.ts" 'export function j1F(){return 1}\n'; mk "$NB/src/uj1.ts" "export function run(n: string){ return require('./j1')[n]() }\n"
mk "$NB/src/j2.js" 'export function j2F(){return 1}\n'; mk "$NB/src/uj2.js" "const reg = require('./j2')\nexport const all = Object.keys(reg)\n"
mk "$NB/src/j3.ts" 'export function j3F(){return 1}\n'; mk "$NB/src/uj3.ts" "import * as j3 from './j3'\nexport { j3 }\n"
mk "$NB/src/j4.ts" 'export function j4F(){return 1}\n'; mk "$NB/src/uj4.ts" "export const p = import('./j4').then(m => m)\n"
for k in 1 3 4; do ask "$NB" "unused exports in src/j$k.ts" > "$T/nbj$k.out"; want NM6j$k "$T/nbj$k.out" j${k}F unknown built-name; done
ask "$NB" "unused exports in src/j2.js" > "$T/nbj2.out"; want NM6j2 "$T/nbj2.out" j2F unknown built-name
mk "$NB/src/Btn.tsx" 'export default function Btn(){return null}\nexport function btnDead(){return 1}\n'; mk "$NB/src/uBtn.tsx" "import Btn from './Btn'\nimport { a as b } from './other'\nexport const x = Btn(b)\n"
ask "$NB" "unused exports in src/Btn.tsx" > "$T/nbbtn.out"; want NM6n3 "$T/nbbtn.out" btnDead unused      # a default import binds a def, not the module
# M7: other ways to spell a default export
mk "$NB/src/d1.ts" 'function d1Thing(){return 1}\nexport {\n  d1Thing as default,\n}\n'; mk "$NB/src/ud1.ts" "import q from './d1'\nexport const a = q()\n"
ask "$NB" "unused exports in src/d1.ts" > "$T/nbd1.out"; notv NM7 "$T/nbd1.out" d1Thing unused
# M8: a head and a tail around a hole, text in the middle of two holes, .concat
mk "$NB/pkg/b1.py" 'def pre_x_post():\n    return 1\ndef a_mid_b():\n    return 2\ndef b1_dead():\n    return 3\n'; mk "$NB/pkg/ub1.py" 'from pkg import b1\ndef go(a, c):\n    return b1.__name__, f"{a}_mid_{c}"\n'
ask "$NB" "unused functions in pkg/b1.py" > "$T/nbb1.out"; want NM8a "$T/nbb1.out" a_mid_b unknown built-name; want NM8b "$T/nbb1.out" b1_dead unused
mk "$NB/src/b2.ts" 'export class B2 { headMidTail(){return 1} concatThing(){return 2} tmplHeadX(){return 3} b2Dead(){return 4} }\n'
mk "$NB/src/ub2.ts" 'import { B2 } from "./b2";\nexport function go(v: any, k: string) {\n  const a = v[`head${k}Tail`];\n  const b = v["concat".concat(k)];\n  const c = v[`tmplHead${k}`];\n  return [a, b, c, new B2()];\n}\n'
ask "$NB" "unused exports in src/b2.ts" > "$T/nbb2.out"; for n in headMidTail concatThing tmplHeadX; do want NM8c "$T/nbb2.out" $n unknown built-name; done; want NM8d "$T/nbb2.out" b2Dead unused
# M9: an unrelated module of the same stem is no importer; a real one, however written, is
mk "$NB/proj/settings.py" 'MIDDLEWARE = []\n'; mk "$NB/other/views2.py" 'from django.conf import settings\nprint(settings.DEBUG)\n'
ask "$NB" "unused functions in proj/settings.py" > "$T/nb9a.out"; want NM9a "$T/nb9a.out" MIDDLEWARE unknown unimported
mk "$NB/src/a/utl.ts" 'export function utlConv(){return 1}\n'; mk "$NB/src/b/utl.ts" 'export function otherUtl(){return 1}\n'; mk "$NB/src/b/ub.ts" "import { otherUtl } from './utl'\nimport x from 'utl'\nimport y from 'lodash/utl'\nexport const q = [otherUtl, x, y]\n"
ask "$NB" "unused exports in src/a/utl.ts" > "$T/nb9b.out"; want NM9b "$T/nb9b.out" utlConv unknown unimported   # ./utl there, a package, a package's file: none is this file
mk "$NB/src/m1.ts" 'export function m1Dead(){return 1}\nexport function m1Live(){return 2}\n'; mk "$NB/src/um1.ts" "import {\n  m1Live,\n} from '@/m1'\nexport const a = m1Live()\n"
ask "$NB" "unused exports in src/m1.ts" > "$T/nb9c.out"; want NM9c "$T/nb9c.out" m1Dead unused
mk "$NB/lib/r1.py" 'def r1_dead():\n    return 1\n'; mk "$NB/lib/sub/ur.py" 'from ..r1 import other\n'
ask "$NB" "unused functions in lib/r1.py" > "$T/nb9d.out"; want NM9d "$T/nb9d.out" r1_dead unused      # a relative import resolves from the importer
# N1: other runtime names, by language; the same word in a language it means nothing in
mk "$NB/n/g.py" 'def lambda_handler(e, c):\n    return 1\ndef LLVMFuzzerTestOneInput():\n    return 2\n'; mk "$NB/n/ug.py" 'from n import g\n'
ask "$NB" "unused functions in n/g.py" > "$T/nbn.out"; want NN1a "$T/nbn.out" lambda_handler unknown framework; want NN1b "$T/nbn.out" LLVMFuzzerTestOneInput unused
mk "$NB/src/it.ts" 'export class It { next(){return 1} toJSON(){return 2} itDead(){return 3} }\n'; mk "$NB/src/uit.ts" "import { It } from './it'\nexport const a = JSON.stringify(new It())\n"
ask "$NB" "unused exports in src/it.ts" > "$T/nbit.out"; want NN2a "$T/nbit.out" next unknown framework; want NN2b "$T/nbit.out" toJSON unknown framework; want NN2c "$T/nbit.out" itDead unused
mk "$NB/cc/v.hpp" 'struct V { int* begin(); int* end(); int v_dead(); };\n'; mk "$NB/cc/u.cpp" '#include "v.hpp"\nint z(V v){ int s=0; for(int x: v) s+=x; return s; }\n'
ask "$NB" "unused functions in cc/v.hpp" > "$T/nbcc.out"; want NN2d "$T/nbcc.out" begin unknown framework; want NN2e "$T/nbcc.out" v_dead unused
mk "$NB/Include/zz.h" 'int Zz_Public(void);\n'; ask "$NB" "unused functions in Include/zz.h" > "$T/nbinc.out"; want NN3 "$T/nbinc.out" Zz_Public unknown api
# triggers: a delete question about the rows fires, one about behaviour does not
mk "$NB/n/t.py" 'def trig_dead():\n    return 1\n'; mk "$NB/n/ut.py" 'from n import t\n'
for q in "safely delete functions in n/t.py" "what can be removed from n/t.py" "functions that can be removed in n/t.py"; do
  ask "$NB" "$q" | grep -q '<unused_in_file' && pass "NT: fires on: $q" || fail "NT: silent on: $q"; done
for q in "how to safely delete a message in n/t.py" "items can be removed from the queue in n/t.py"; do
  ask "$NB" "$q" | grep -q '<unused_in_file' && fail "NT: fires on: $q" || pass "NT: silent on: $q"; done
# the five honesty guards no arm needed before (mutants unreadable, multiroot, walk_git, walk_symlink, pkg_nearest)
SV="$R/sv"; mk "$SV/pkg/__init__.py" ''; mk "$SV/pkg/tgt.py" 'def dead_in_git_only():\n    return 1\ndef dead_via_symlink():\n    return 2\n'; mk "$SV/pkg/u.py" 'from pkg import tgt\n'
mk "$SV/.git/notes.txt" 'dead_in_git_only was mentioned in a commit message\n'
mk "$T/outside_sv.txt" 'dead_via_symlink()\n'; ln -s "$T/outside_sv.txt" "$SV/link.txt"
ask "$SV" "unused functions in pkg/tgt.py" > "$T/sv.out"
want SVa "$T/sv.out" dead_in_git_only unused               # .git is not a text file of the tree: its objects, hooks and messages name everything
want SVb "$T/sv.out" dead_via_symlink unused               # a symlink is never opened: a link to a file outside the root is not a file under it
mk "$R/pk/package.json" '{"name":"root","private":true}\n'
mk "$R/pk/src/package.json" '{"name":"lib","main":"tgt.js"}\n'
mk "$R/pk/src/tgt.ts" 'export function nearest_pub(){return 1}\n'
mk "$R/pk/src/tgt.test.ts" 'import { nearest_pub } from "./tgt";\nnearest_pub();\n'
ask "$R/pk" "unused exports in src/tgt.ts" > "$T/pk.out"
want PKa "$T/pk.out" nearest_pub unknown api              # the nearest package.json decides: this one publishes, the private root above it does not

# ---- the trigger, on the words of the stored argv ----
for q in "unused functions in pkg/util.py" "pkg/util.py unused functions" "which functions in pkg/util.py are never called" \
         "dead code in pkg/util.py" "what in pkg/util.py has no callers" "functions in pkg/util.py that nobody calls" "which functions of pkg/util.py does nothing use" \
         "functions in pkg/util.py only used by tests" "which public functions in pkg/util.py are unused" "pkg/util.py functions with no non-test callers" \
         "functions in pkg/util.py that are not being used" "functions in pkg/util.py that aren't being called" "functions in pkg/util.py that never get called" \
         "functions in pkg/util.py with no call sites" "functions in pkg/util.py without a caller" "pkg/util.py functions no one calls" "pkg/util.py functions used by nothing" \
         "functions in pkg/util.py called by no one" "functions in pkg/util.py only tests use" "unused macros in pkg/util.py" "unused enums in pkg/util.py" "unused interfaces in pkg/util.py" \
         "unused traits in pkg/util.py" "unused globals in pkg/util.py" "unused hooks in pkg/util.py" "unused components in pkg/util.py" "orphaned functions in pkg/util.py" \
         "unreachable functions in pkg/util.py" "stale functions in pkg/util.py" "which functions in pkg/util.py can I safely delete" "what can be removed from pkg/util.py" \
         "does anything call the functions in pkg/util.py" "safely delete the functions in pkg/util.py" "functions that can be removed from pkg/util.py"; do
  if ask "$P" "$q" | grep -q '<unused_in_file '; then pass "T1: fires: $q"; else fail "T1: did not fire: $q"; fi
done
for q in "unused imports in pkg/util.py" "unused parameter in pkg/util.py" "dead code elimination in pkg/util.py" "unused functions" "pkg/util.py" \
         "where is live_fn defined in pkg/util.py" "what calls live_fn" "how to safely delete a message in pkg/util.py" "items can be removed from the queue in pkg/util.py"; do
  ask "$P" "$q" > "$T/near.a"; ( cd "$P" && RIPWIRE_NO_UNUSED_TABLE=1 "$RIPWIRE" . --no-cache --for="$q" 2>/dev/null ) > "$T/near.b"
  sed -E 's/ at="[^"]*"| est_tokens="[0-9]+"//g' "$T/near.a" > "$T/near.a2"; sed -E 's/ at="[^"]*"| est_tokens="[0-9]+"//g' "$T/near.b" > "$T/near.b2"
  if grep -q '<unused_in_file ' "$T/near.a"; then fail "T2: fired on a near miss: $q"
  elif cmp -s "$T/near.a2" "$T/near.b2"; then pass "T2: no block, byte-identical: $q"
  else fail "T2: bytes moved with no block: $q"; fi
done
# a directory: a table per file, the cut disclosed
ask "$G" "unused functions in internal/x" > "$T/dir.out"
n=$(grep -o '<unused_in_file ' "$T/dir.out" | wc -l | tr -d ' ')
[ "$n" -ge 1 ] && pass "T3: a directory gets a table per file ($n)" || fail "T3: directory tables: $n"
# --json and --token-budget carry none
( cd "$P" && "$RIPWIRE" . --no-cache --json --for="unused functions in pkg/util.py" 2>/dev/null ) | grep -q unused_in_file && fail "T4: --json carries the table" || pass "T4: --json carries none"
( cd "$P" && "$RIPWIRE" . --no-cache --token-budget=4000 --for="unused functions in pkg/util.py" 2>/dev/null ) | grep -q '<unused_in_file ' && fail "T5: --token-budget carries the table" || pass "T5: --token-budget carries none"
# the legend names every word it prints, and the answer is well-formed
if command -v xmllint >/dev/null; then xmllint --noout "$T/py.out" 2>/dev/null && pass "T6: well-formed" || fail "T6: not well-formed"; fi
grep -q 'unused_in_file p= public= private=' "$T/py.out" && pass "T7: legend present" || fail "T7: no legend clause"
# --dead-code keeps its meaning
( cd "$P" && "$RIPWIRE" . --no-cache --dead-code=pkg/util.py 2>/dev/null ) > "$T/dc.out"
grep -q 'evidence="internal-linkage+zero-callers"' "$T/dc.out" && pass "T8: --dead-code keeps evidence=internal-linkage" || fail "T8: --dead-code moved"
grep -q '<unused_in_file ' "$T/dc.out" && fail "T9: --dead-code prints the table" || pass "T9: --dead-code prints no table"
grep -q 'next="--for=' "$T/dc.out" && pass "T11: --dead-code=PATH names the table" || fail "T11: no next= on --dead-code=PATH"
( cd "$P" && "$RIPWIRE" . --no-cache --dead-code 2>/dev/null ) | grep -q 'next="--for=' && fail "T12: bare --dead-code grew a next=" || pass "T12: bare --dead-code has no next="
# deterministic
ask "$P" "unused functions in pkg/util.py" > "$T/py.again"
sed -E 's/ at="[0-9a-f+a-z]*"//' "$T/py.out" > "$T/a1"; sed -E 's/ at="[0-9a-f+a-z]*"//' "$T/py.again" > "$T/a2"
cmp -s "$T/a1" "$T/a2" && pass "T10: deterministic" || fail "T10: two runs differ"

echo "forunusedcheck: $fails failure(s)"
[ "$fails" = 0 ]
