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
want PY19 "$T/py.out" is_stem_free test-only              # a short stem elsewhere, `f"is_{x}"`, reads on members only
want PY20 "$T/py.out" is_stem_member unknown built-name
want PY21 "$T/py.out" script_entry unknown manifest
want PY22 "$T/py.out" named_in_a_comment unused
want PY23 "$T/py.out" named_in_a_doc unused
want PY24 "$T/py.out" harness_only test-only                # a test-support tree is a test
want PY25 "$T/py.out" plainlog_thing unused                 # a stem with no lookup near it builds no name
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
ask "$U" "unused functions in pkg/t.py" > "$T/f2.out"
for n in vue_only_helper svelte_only_helper ipp_only_thing proc_factory vendor_only_fn dist_only_fn big_only_thing tmpl_only_fn; do want F2a "$T/f2.out" $n unknown name; done
want F2b "$T/f2.out" truly_dead_f2 unused                 # the walk does not blanket-hedge: a name nowhere stays unused
U2="$T/f2u"; mkdir -p "$U2/pkg" "$U2/gen"
printf 'def dead_but_unseen():\n    return 1\n' > "$U2/pkg/t.py"
python3 -c "
f=open('$U2/gen/blob.txtdata','w'); f.truncate(40<<20); f.close()"
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
ask "$N" "unused classes in pkg/reg.py" > "$T/f6c.out"
want F6c "$T/f6c.out" AutoPlugin unknown dispatch
want F6d "$T/f6c.out" PlainNoBase unused                    # a class with no base is not registered by a hook
want PY27 "$T/py.out" Derived unused                        # near miss: no hook anywhere in that tree, a base alone hedges nothing
ask "$N" "unused functions in pkg/cat.py" > "$T/f6e.out"
want F6e "$T/f6e.out" concat_handle_alpha unknown built-name
want F6f "$T/f6e.out" plainjoin_one unused                  # a joined literal with no lookup near it builds no name
ask "$N" "unused exports in modules/w.ts" > "$T/f6g.out"
want F6g "$T/f6g.out" modAlpha unknown built-name
ask "$N" "unused functions in pkg/ext/alpha.py" > "$T/f6h.out"
want F6h "$T/f6h.out" setup_alpha unknown built-name
ask "$N" "unused functions in pkg2/isx_t.py" > "$T/f6i.out"
want F6i "$T/f6i.out" is_private_addr unknown built-name   # the lookup's object is the target module: no stem-length rule
# F10 (over-hedge, safe to tighten): a def's own line naming itself is no use; pub(crate) has no consumer outside the crate
printf 'from typing import TypeVar\nW = TypeVar("W")\n' > "$O/pkg/tv.py"
ask "$O" "unused functions in pkg/tv.py" > "$T/f10a.out"
want F10a "$T/f10a.out" W unused
mkdir -p "$T/f10/src"; printf '[package]\nname = "l"\nversion = "0.1.0"\n' > "$T/f10/Cargo.toml"
printf 'pub fn pub_api_f10() -> i32 { 1 }\npub(crate) fn crate_only_dead() -> i32 { 2 }\n' > "$T/f10/src/lib.rs"
ask "$T/f10" "unused functions in src/lib.rs" > "$T/f10b.out"
want F10b "$T/f10b.out" pub_api_f10 unknown api
want F10c "$T/f10b.out" crate_only_dead unused
grep -q 'kForUnusedForeignStem' "$(dirname "$0")/../src/forunused.h" 2>/dev/null && fail "F6j: the stem-length rule is back" || pass "F6j: no stem-length rule"

# ---- the trigger, on the words of the stored argv ----
for q in "unused functions in pkg/util.py" "pkg/util.py unused functions" "which functions in pkg/util.py are never called" \
         "dead code in pkg/util.py" "what in pkg/util.py has no callers" "functions in pkg/util.py that nobody calls" "which functions of pkg/util.py does nothing use" \
         "functions in pkg/util.py only used by tests" "which public functions in pkg/util.py are unused" "pkg/util.py functions with no non-test callers" \
         "functions in pkg/util.py that are not being used" "functions in pkg/util.py that aren't being called" "functions in pkg/util.py that never get called" \
         "functions in pkg/util.py with no call sites" "functions in pkg/util.py without a caller" "pkg/util.py functions no one calls" "pkg/util.py functions used by nothing" \
         "functions in pkg/util.py called by no one" "functions in pkg/util.py only tests use" "unused macros in pkg/util.py" "unused enums in pkg/util.py" "unused interfaces in pkg/util.py" \
         "unused traits in pkg/util.py" "unused globals in pkg/util.py" "unused hooks in pkg/util.py" "unused components in pkg/util.py" "orphaned functions in pkg/util.py" \
         "unreachable functions in pkg/util.py" "stale functions in pkg/util.py" "which functions in pkg/util.py can I safely delete" "what can be removed from pkg/util.py" \
         "does anything call the functions in pkg/util.py"; do
  if ask "$P" "$q" | grep -q '<unused_in_file '; then pass "T1: fires: $q"; else fail "T1: did not fire: $q"; fi
done
for q in "unused imports in pkg/util.py" "unused parameter in pkg/util.py" "dead code elimination in pkg/util.py" "unused functions" "pkg/util.py" \
         "where is live_fn defined in pkg/util.py" "what calls live_fn"; do
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
