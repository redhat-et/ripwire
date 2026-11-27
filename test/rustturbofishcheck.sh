#!/usr/bin/env bash
# rustturbofishcheck.sh — RUST-TURBOFISH: a Rust call written with a turbofish on the callee is a call.
#
#   test/rustturbofishcheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# tree-sitter-rust parses `W::f::<T>(x)` and `w.m::<T>(y)` as call_expression( function: generic_function( function:
# scoped_identifier | field_expression ) ). queries/rust/tags.scm captured only the bare `f::<T>(x)` nesting
# (generic_function over an identifier), so a turbofish on a PATH function or a METHOD was no reference at all: --callers on
# zed listed 4 of 8 caller files (the M2's report). A `macro_rules!` transcriber is scanned lexically (ingest_names.h
# scanTranscriberCalls) and its path reader stopped at `::<`, so `$w.m::<T>(..)` there was no call either.
#
# Arm classes: [P] positive — RED on the parent binary (origin/main 5f4b50415); [C] control — the same callee without a
# turbofish, or the bare turbofish H4 already captured: holds on every binary; [N] near miss — a shape that must not read as a
# call (holds on the parent binary too, so it guards the fix, it does not prove it).
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
fail=0
# every verdict is an if/else: a failed write of a PASS line must never print FAIL for an arm that passed (gateexitcheck G2)
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
has(){ if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else no "$3 — missing: $2"; fi; }
hasnt(){ if printf '%s' "$1" | grep -qF -- "$2"; then no "$3 — present: $2"; else ok "$3"; fi; }

echo "rustturbofishcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }

# ── the corpus, written here (no file of this tree is read as a fixture) ─────────────────────────────────────────────
# lib.rs    W::tf_meth (a generic method), W::tf_assoc (a generic associated fn), tf_free (a generic free fn), Gen::make.
# util.rs   tf_deep (a generic fn one module down).
# lib.rs    also W::tf_dup / W::tf_mk and V::tf_dup / V::tf_mk: two definitions per name, so the receiver's type / the path
#           qualifier must pick one (c_typed.rs).
# c_*.rs    one caller file per form; c_plain.rs calls all four WITHOUT a turbofish (the control every arm is measured beside).
mkdir -p "$DIR/src"
printf '[package]\nname = "tf"\nversion = "0.1.0"\nedition = "2021"\n' >"$DIR/Cargo.toml"
cat >"$DIR/src/lib.rs" <<'R'
pub mod util;
pub mod c_free; pub mod c_path; pub mod c_mod; pub mod c_method; pub mod c_nested; pub mod c_macro; pub mod c_trans; pub mod c_trans2; pub mod c_plain; pub mod c_typed;
pub struct W;
impl W {
    pub fn tf_meth<T>(&self, x: T) -> T { x }
    pub fn tf_assoc<T>(x: T) -> T { x }
}
pub fn tf_free<T>(x: T) -> T { x }
pub fn tf_decoy() {}
pub struct Gen<T>(T);
impl<T> Gen<T> { pub fn make(x: T) -> Gen<T> { Gen(x) } }
pub struct V;
impl W { pub fn tf_dup<T>(&self, x: T) -> T { x } pub fn tf_mk<T>(x: T) -> T { x } }
impl V { pub fn tf_dup<T>(&self, x: T) -> T { x } pub fn tf_mk<T>(x: T) -> T { x } }
R
cat >"$DIR/src/util.rs" <<'R'
pub fn tf_deep<T>(x: T) -> T { x }
R
cat >"$DIR/src/c_free.rs" <<'R'
use crate::tf_free;
pub fn call_free() -> u32 { tf_free::<u32>(1) }
R
cat >"$DIR/src/c_path.rs" <<'R'
use crate::W;
pub fn call_path() -> u8 { W::tf_assoc::<u8>(2) }
R
cat >"$DIR/src/c_mod.rs" <<'R'
pub fn call_mod() -> u8 { crate::util::tf_deep::<u8>(3) }
R
cat >"$DIR/src/c_method.rs" <<'R'
use crate::W;
pub fn call_method(w: &W) -> u32 { w.tf_meth::<u32>(4) }
R
cat >"$DIR/src/c_nested.rs" <<'R'
use crate::{tf_free, W};
pub fn call_nested(w: &W) -> usize {
    let a = tf_free::<Vec<Option<u8>>>(vec![]);
    let b = W::tf_assoc::<std::collections::HashMap<u8, Vec<u8>>>(Default::default());
    let c = crate::util::tf_deep::<Box<dyn Fn(u8) -> u8>>(Box::new(|x| x));
    w.tf_meth::<Option<Vec<u8>>>(None).map(|v| v.len()).unwrap_or(a.len() + b.len() + c(1) as usize)
}
R
cat >"$DIR/src/c_macro.rs" <<'R'
use crate::W;
pub fn call_macro(w: &W) {
    println!("{} {}", w.tf_meth::<u16>(5), W::tf_assoc::<i8>(6));
    assert_eq!(crate::util::tf_deep::<u8>(7), 7);
}
R
cat >"$DIR/src/c_trans.rs" <<'R'
macro_rules! go {
    ($w:expr) => {
        $w.tf_meth::<u64>(8)
            + crate::W::tf_assoc::<Vec<u64>>(vec![9]).len() as u64
            + $crate::util::tf_deep::<u64>(10)
    };
}
macro_rules! near {
    () => {
        { let _f = crate::tf_free::<u8>; crate::Gen::<u8>::make(11) }
    };
}
pub fn call_trans(w: &crate::W) -> u64 { near!(); go!(w) }
R
cat >"$DIR/src/c_trans2.rs" <<'R'
macro_rules! arr {
    () => {
        crate::W::tf_assoc::<[u8; 4]>([0; 4])
    };
}
macro_rules! cmt {
    () => {
        crate::tf_free::</* > tf_decoy() */ u8>(1)
    };
}
pub fn call_trans2() { arr!(); cmt!(); }
R
cat >"$DIR/src/c_plain.rs" <<'R'
use crate::{tf_free, W};
pub fn call_plain(w: &W) -> u32 { tf_free(1) + W::tf_assoc(2) + w.tf_meth(3) + crate::util::tf_deep(4) }
R

cat >"$DIR/src/c_typed.rs" <<'R'
use crate::W;
pub fn call_typed(w: &W) -> u8 { w.tf_dup::<u8>(12) + W::tf_mk::<u8>(13) }
R

cd "$DIR" || exit 1
callers(){ "$BIN" . --no-cache --callers="$1" --legend=compact 2>/dev/null; }
uses(){ "$BIN" . --no-cache --uses="$1" --legend=compact 2>/dev/null; }
CM="$( callers tf_meth )";  UM="$( uses tf_meth )"
CA="$( callers tf_assoc )"; UA="$( uses tf_assoc )"
CD="$( callers tf_deep )";  UD="$( uses tf_deep )"
CF="$( callers tf_free )";  UF="$( uses tf_free )"
CG="$( callers Gen )"; UY="$( uses tf_decoy )"
CWD="$( callers W::tf_dup )"; CVD="$( callers V::tf_dup )"
CWM="$( callers W::tf_mk )";  CVM="$( callers V::tf_mk )"

echo "── [P] a turbofish on a path function or a method is a call (--callers file, --uses site)"
has "$CA" 'n="call_path" p="src/c_path.rs:2"'                 "[P1] path fn W::tf_assoc::<u8>(2): --callers tf_assoc lists c_path.rs"
has "$UA" '<u role="call" p="src/c_path.rs:2" in_id="call_path"/>'   "[P1] --uses tf_assoc has the c_path.rs:2 call"
has "$CD" 'n="call_mod" p="src/c_mod.rs:1"'                   "[P2] module path crate::util::tf_deep::<u8>(3): --callers tf_deep lists c_mod.rs"
has "$UD" '<u role="call" p="src/c_mod.rs:1" in_id="call_mod"/>'     "[P2] --uses tf_deep has the c_mod.rs:1 call"
has "$CM" 'n="call_method" p="src/c_method.rs:2"'             "[P3] method w.tf_meth::<u32>(4): --callers tf_meth lists c_method.rs"
has "$UM" '<u role="call" p="src/c_method.rs:2" in_id="call_method"/>' "[P3] --uses tf_meth has the c_method.rs:2 call"
has "$CA" 'n="call_nested" p="src/c_nested.rs:2"'             "[P4] nested generics W::tf_assoc::<HashMap<u8, Vec<u8>>>: --callers tf_assoc lists c_nested.rs"
has "$UA" '<u role="call" p="src/c_nested.rs:4" in_id="call_nested"/>' "[P4] --uses tf_assoc has the c_nested.rs:4 call"
has "$CD" 'n="call_nested" p="src/c_nested.rs:2"'             "[P4] nested generics with an Fn(u8) -> u8 argument: --callers tf_deep lists c_nested.rs"
has "$UD" '<u role="call" p="src/c_nested.rs:5" in_id="call_nested"/>' "[P4] --uses tf_deep has the c_nested.rs:5 call"
has "$CM" 'n="call_nested" p="src/c_nested.rs:2"'             "[P4] nested generics w.tf_meth::<Option<Vec<u8>>>: --callers tf_meth lists c_nested.rs"
has "$UM" '<u role="call" p="src/c_nested.rs:6" in_id="call_nested"/>' "[P4] --uses tf_meth has the c_nested.rs:6 call"
has "$CM" 'n="call_macro" p="src/c_macro.rs:2"'               "[P5] inside println! arguments: --callers tf_meth lists c_macro.rs"
has "$UM" '<u role="call" p="src/c_macro.rs:3" in_id="call_macro"/>' "[P5] --uses tf_meth has the c_macro.rs:3 call"
has "$CA" 'n="call_macro" p="src/c_macro.rs:2"'               "[P5] inside println! arguments: --callers tf_assoc lists c_macro.rs"
has "$UA" '<u role="call" p="src/c_macro.rs:3" in_id="call_macro"/>' "[P5] --uses tf_assoc has the c_macro.rs:3 call"
has "$CD" 'n="call_macro" p="src/c_macro.rs:2"'               "[P5] inside assert_eq! arguments: --callers tf_deep lists c_macro.rs"
has "$UD" '<u role="call" p="src/c_macro.rs:4" in_id="call_macro"/>' "[P5] --uses tf_deep has the c_macro.rs:4 call"
has "$CM" 'n="go" p="src/c_trans.rs:1"'                       "[P6] macro_rules! transcriber \$w.tf_meth::<u64>(8): --callers tf_meth lists the go macro"
has "$UM" '<u role="call" p="src/c_trans.rs:3" in_id="go"/>'         "[P6] --uses tf_meth has the c_trans.rs:3 transcriber call"
has "$CA" 'n="go" p="src/c_trans.rs:1"'                       "[P6] transcriber crate::W::tf_assoc::<Vec<u64>>(..): --callers tf_assoc lists the go macro"
has "$UA" '<u role="call" p="src/c_trans.rs:4" in_id="go"/>'         "[P6] --uses tf_assoc has the c_trans.rs:4 transcriber call"
has "$CD" 'n="go" p="src/c_trans.rs:1"'                       "[P6] transcriber \$crate::util::tf_deep::<u64>(10): --callers tf_deep lists the go macro"
has "$UD" '<u role="call" p="src/c_trans.rs:5" in_id="go"/>'         "[P6] --uses tf_deep has the c_trans.rs:5 transcriber call"
has "$CWD" 'n="call_typed" p="src/c_typed.rs:2"'             "[P7] typed receiver w: &W, w.tf_dup::<u8>(12): --callers W::tf_dup lists c_typed.rs"
has "$CWM" 'n="call_typed" p="src/c_typed.rs:2"'             "[P7] qualifier W in W::tf_mk::<u8>(13): --callers W::tf_mk lists c_typed.rs"

has "$UA" '<u role="call" p="src/c_trans2.rs:3" in_id="arr"/>'  "[P8] transcriber turbofish with an array type W::tf_assoc::<[u8; 4]>(..): --uses tf_assoc has the arr call"
has "$UF" '<u role="call" p="src/c_trans2.rs:8" in_id="cmt"/>'  "[P8] transcriber turbofish holding a comment tf_free::</* > */ u8>(1): --uses tf_free has the cmt call"

echo "── [C] the same callees without a turbofish, and the bare turbofish H4 already read"
has "$CF" 'n="call_free" p="src/c_free.rs:2"'                 "[C1] bare turbofish tf_free::<u32>(1): --callers tf_free lists c_free.rs"
has "$CF" 'n="call_nested" p="src/c_nested.rs:2"'             "[C2] bare nested turbofish tf_free::<Vec<Option<u8>>>: --callers tf_free lists c_nested.rs"
for t in tf_free tf_assoc tf_meth tf_deep; do
    case $t in tf_free) C=$CF ;; tf_assoc) C=$CA ;; tf_meth) C=$CM ;; tf_deep) C=$CD ;; esac
    has "$C" 'n="call_plain" p="src/c_plain.rs:2"'            "[C3] plain call of $t: --callers $t lists c_plain.rs"
done

echo "── [N] near misses: a turbofish that is no call"
hasnt "$CF" 'n="go"'                                          "[N1] a fn-pointer value crate::tf_free::<u8> in a transcriber is no call of tf_free"
hasnt "$CF" 'n="near"'                                        "[N1] ... nor a call of tf_free by the near macro"
hasnt "$CG" 'n="near"'                                        "[N2] a turbofish on a TYPE segment crate::Gen::<u8>::make(..) is no call of Gen"
hasnt "$UY" 'in_id="cmt"'                                          "[N4] a > and a call inside a comment in a turbofish is no call of tf_decoy"
hasnt "$CVD" 'n="call_typed"'                                 "[N3] the receiver's type still decides: --callers V::tf_dup does not list call_typed"
hasnt "$CVM" 'n="call_typed"'                                 "[N3] the qualifier still decides: --callers V::tf_mk does not list call_typed"

if [ "$fail" -ne 0 ]; then
    echo "rustturbofishcheck: FAIL"
    exit 1
fi
echo "rustturbofishcheck: PASS"
