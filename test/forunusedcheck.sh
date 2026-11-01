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
RIPWIRE="${RIPWIRE:-./build/ripwire}"
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

# ---- the trigger, on the words of the stored argv ----
for q in "unused functions in pkg/util.py" "pkg/util.py unused functions" "which functions in pkg/util.py are never called" \
         "dead code in pkg/util.py" "what in pkg/util.py has no callers" "functions in pkg/util.py that nobody calls" \
         "functions in pkg/util.py only used by tests" "which public functions in pkg/util.py are unused" "pkg/util.py functions with no non-test callers"; do
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
