#!/usr/bin/env bash
# rustrootscheck.sh — RUST-ROOTS-A gate: the Rust import probe (resolve.h resolveRustImport, buildRustCrateRoots,
# resolveRustUseTree) reads every path from the INCLUDER's own crate and module, by Rust's module-file rule.
#   F1  `crate::` anchors at the crate the file is compiled in: the nearest Cargo.toml's target (a 2-crate workspace,
#       a custom `[lib] path`, a `src/bin/` binary crate), never the first lib.rs of the tree.
#   F2  `mod b;` in a non-mod.rs file `a.rs` is `a/b.rs`, never a same-named `src/b.rs`.
#   F3  `super::` in a plain file `a/x.rs` is module `a`; `super::super::` climbs twice; `self::` is the file's module.
#   SUB `use crate::a::b` where a/b.rs exists draws a/b.rs although a.rs exists too (tiers: full path first, parent
#       module file second; unique-or-degrade inside a tier, never across one).
#   BR  brace groups resolve each member; an `as` rename resolves the path it renames.
#   IN  a directive inside an INLINE `mod x { }` (`#[cfg(test)] mod tests { use super::*; }`) reads from the inline module:
#       the first `super`s and `self::` stay inside the file (no edge), `super` past the inline depth climbs from the file's
#       module, and `mod y;` lives in the inline module's own directory (`mod outer { mod y; }` in lib.rs is src/outer/y.rs).
# Every arm reads `--impact=FILE` (the file's importers) and checks the command's exit code and that the answer
# parsed (an <impact> element), so a crash or an empty answer is RED, never a pass. Absence arms each have a positive
# twin in the same fixture.
#
# RED-first (2026-11-05): against the base binary (main 292a26dec) arms F1a F1b F1c F2a F3a F3b SUBa BRa BRb ALa are
# RED; the positive twins and degrade arms pass on both. Two mutants, each RED: (1) one global crate root (the first
# lib.rs's directory for every file); (2) parent-wins (tier 2 probed before tier 1).
#
#   test/rustrootscheck.sh                 # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/rustrootscheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "rustrootscheck: BIN=$BIN"

mk(){ mkdir -p "$( dirname "$1" )" && printf '%s\n' "$2" > "$1"; }

# ── fixture W: a 3-crate workspace (F1) ─────────────────────────────────────────────────────────────
W="$TMP/w"
mk "$W/Cargo.toml"            '[workspace]
members = ["aaa", "bbb", "ccc"]'
mk "$W/aaa/Cargo.toml"        '[package]
name = "aaa"'
mk "$W/aaa/src/lib.rs"        'pub mod x;'
mk "$W/aaa/src/x.rs"          'pub fn x() {}'
mk "$W/aaa/src/helper.rs"     'pub fn h() {}'
mk "$W/bbb/Cargo.toml"        '[package]
name = "bbb"'
mk "$W/bbb/src/lib.rs"        'pub mod x;
pub mod y;
pub mod helper;'
mk "$W/bbb/src/x.rs"          'pub fn x() {}'
mk "$W/bbb/src/y.rs"          'use crate::x::x;
pub fn y() { x(); }'
mk "$W/bbb/src/helper.rs"     'pub fn h() {}'
mk "$W/bbb/src/bin/tool.rs"   'mod helper;
mod other;
fn main() {}'
mk "$W/bbb/src/bin/helper.rs" 'pub fn h() {}'
mk "$W/bbb/src/bin/other.rs"  'use crate::helper::h;
pub fn o() { h(); }'
mk "$W/ccc/Cargo.toml"        '[package]
name = "ccc"

[lib]
path = "lib.rs"'
mk "$W/ccc/lib.rs"            'pub mod u;
pub mod w;'
mk "$W/ccc/u.rs"              'pub fn u() {}'
mk "$W/ccc/w.rs"              'use crate::u::u;
pub fn w() { u(); }'

# ── fixture M: one crate, the module rules (F2 F3 SUB BR) ─────────────────────────────────────────────
M="$TMP/m"
mk "$M/Cargo.toml"            '[package]
name = "m"'
mk "$M/src/lib.rs"            'pub mod a;
pub mod b;
pub mod c;
pub mod d;
pub mod e;
pub mod f;
pub mod q;
pub mod amb;
pub mod p;'
mk "$M/src/b.rs"              'pub fn g() {}'
mk "$M/src/a.rs"              'pub mod b;
pub mod s1;
pub fn af() {}'
mk "$M/src/a/b.rs"            'pub fn g() {}'
mk "$M/src/a/s1.rs"           'pub mod k;
use super::b::g;
use super::af;
use self::k::kf;
pub fn s() { g(); af(); kf(); }'
mk "$M/src/a/s1/k.rs"         'use super::super::af;
pub fn kf() { af(); }'
mk "$M/src/c.rs"              'use crate::a::b;
use crate::a::af;
use crate::amb::z;
use crate::q::r;
pub fn c() { b::g(); af(); }'
mk "$M/src/d.rs"              'use crate::{a::b::g, e::{self, E}};
pub fn d() { g(); }'
mk "$M/src/e.rs"              'pub struct E;'
mk "$M/src/f.rs"              'use crate::e::E as EE;
pub fn f(_: EE) {}'
mk "$M/src/amb.rs"            'pub fn z() {}'
mk "$M/src/amb/mod.rs"        'pub fn z() {}'
mk "$M/src/p.rs"              '#[path = "pp.rs"]
mod pp;'
mk "$M/src/pp.rs"             'pub fn pp() {}'
mk "$M/src/q.rs"              'pub mod r;'
mk "$M/src/q/r.rs"            'pub fn r() {}'
mk "$M/src/q/r/mod.rs"        'pub fn r() {}'

# ── fixture I: directives inside inline modules (RV-RUST-ROOTS-A) ──
I="$TMP/i"
mk "$I/Cargo.toml"            '[package]
name = "i"'
mk "$I/src/lib.rs"            'pub mod a;
pub mod b;
pub mod k;
mod outer {
    mod inner;
    mod deep {
        mod z;
    }
}'
mk "$I/src/b.rs"              'pub fn g() {}'
mk "$I/src/inner.rs"          'pub fn decoy() {}'
mk "$I/src/z.rs"              'pub fn decoy() {}'
mk "$I/src/outer/z.rs"        'pub fn decoy() {}'
mk "$I/src/outer/inner.rs"    'pub fn truth() {}'
mk "$I/src/outer/deep/z.rs"   'pub fn truth() {}'
mk "$I/src/a/mod.rs"          'pub mod x;
pub mod y;
pub struct Foo;'
mk "$I/src/a/x.rs"            'pub fn bar() {}
#[cfg(test)]
mod tests {
    use super::*;
    use super::bar;
    use self::helper;
}'
mk "$I/src/a/x/helper.rs"     'pub fn helper() {}'
mk "$I/src/a/y.rs"            'use super::Foo;
use self::helper;'
mk "$I/src/a/y/helper.rs"     'pub fn helper() {}'
mk "$I/src/k.rs"              'pub mod j;
pub mod m;
pub fn kf() {}
mod outer2 {
    mod inn;
}'
mk "$I/src/k/b.rs"            'pub fn g() {}'
mk "$I/src/k/inn.rs"          'pub fn decoy() {}'
mk "$I/src/inn.rs"            'pub fn decoy() {}'
mk "$I/src/k/outer2/inn.rs"   'pub fn truth() {}'
mk "$I/src/k/j.rs"            'use super::kf;
#[cfg(test)]
mod tests {
    use super::super::b::g;
}'
mk "$I/src/k/m.rs"            'mod t1 {
    mod t2 {
        use super::super::super::b::g;
    }
}
mod t3 {
    use super::kf;
}'


# importers <tree> <file> -> "$TMP/imp" holds one importer path per line; RED on a nonzero exit or no <impact> answer
importers(){
  local out="$TMP/imp.xml" rc
  ( cd "$1" || exit 9; "$BIN" "$1" --impact="$2" --no-cache >"$out" 2>"$TMP/imp.err" ); rc=$?
  : > "$TMP/imp"
  if [ "$rc" -ne 0 ] || ! grep -q '<impact ' "$out"; then
    no "--impact=$2 on $(basename "$1"): exit $rc or no <impact> answer"; sed -n '1,5p' "$TMP/imp.err"; return 1
  fi
  grep -oE '<f via="[a-z]+" p="[^"]+"' "$out" | sed -E 's/.* p="([^"]+)"/\1/' | sort > "$TMP/imp"
  return 0
}
has(){   # arm tree file importer
  importers "$2" "$3" || return
  if grep -qxF "$4" "$TMP/imp"; then ok "$1: $4 imports $3"; else no "$1: $4 does not import $3 (got: $(tr '\n' ' ' < "$TMP/imp"))"; fi
}
hasnt(){ # arm tree file importer
  importers "$2" "$3" || return
  if grep -qxF "$4" "$TMP/imp"; then no "$1: $4 imports $3 (a false edge)"; else ok "$1: $4 does not import $3"; fi
}

echo "-- F1: per-crate roots"
has   F1a  "$W" bbb/src/x.rs        bbb/src/y.rs          # crate:: in bbb is bbb's crate
hasnt F1a- "$W" aaa/src/x.rs        bbb/src/y.rs          # ... never aaa's (the first lib.rs in sorted order)
has   F1b  "$W" ccc/u.rs            ccc/w.rs              # [lib] path = "lib.rs": the crate root is ccc/
has   F1c  "$W" bbb/src/bin/helper.rs bbb/src/bin/other.rs   # src/bin/tool.rs is its own crate: crate:: is src/bin/
hasnt F1c- "$W" bbb/src/helper.rs   bbb/src/bin/other.rs  # ... not the lib's src/helper.rs
hasnt F1c2 "$W" aaa/src/helper.rs   bbb/src/bin/other.rs
has   F1d  "$W" bbb/src/bin/helper.rs bbb/src/bin/tool.rs    # twin: `mod helper;` in a bin root resolves beside it

echo "-- F2: mod b; in a non-mod.rs file"
has   F2a  "$M" src/a/b.rs          src/a.rs              # src/a.rs `mod b;` is src/a/b.rs
hasnt F2a- "$M" src/b.rs            src/a.rs              # ... never src/b.rs
has   F2b  "$M" src/b.rs            src/lib.rs            # twin: lib.rs owns src/
has   F2c  "$M" src/a/s1/k.rs       src/a/s1.rs           # nested: s1.rs `mod k;` is a/s1/k.rs
has   F2d  "$M" src/pp.rs           src/p.rs              # #[path] shape: no src/p/pp.rs, the includer's directory is read

echo "-- F3: super / self in a plain file"
has   F3a  "$M" src/a/b.rs          src/a/s1.rs           # super::b::g in a/s1.rs is module a's b
hasnt F3a- "$M" src/b.rs            src/a/s1.rs
has   F3b  "$M" src/a.rs            src/a/s1.rs           # super::af: an item of module a's own file
has   F3c  "$M" src/a.rs            src/a/s1/k.rs         # super::super::af from a/s1/k.rs
hasnt F3c- "$M" src/lib.rs          src/a/s1/k.rs

echo "-- SUB: the full-path module file is the dependency"
has   SUBa "$M" src/a/b.rs          src/c.rs              # use crate::a::b with a.rs + a/b.rs
has   SUBb "$M" src/a.rs            src/c.rs              # twin: use crate::a::af stays a.rs (tier 2)
hasnt SUBc "$M" src/amb.rs          src/c.rs              # tier 2 ambiguous (amb.rs + amb/mod.rs): degrade
hasnt SUBc2 "$M" src/amb/mod.rs     src/c.rs
hasnt SUBd "$M" src/q.rs            src/c.rs              # tier 1 ambiguous (q/r.rs + q/r/mod.rs): never falls to q.rs
hasnt SUBd2 "$M" src/q/r.rs         src/c.rs

echo "-- BR: brace groups and as renames"
has   BRa  "$M" src/a/b.rs          src/d.rs              # crate::{a::b::g, ...}
has   BRb  "$M" src/e.rs            src/d.rs              # ... e::{self, E}
has   ALa  "$M" src/e.rs            src/f.rs              # crate::e::E as EE
hasnt BRc  "$M" src/b.rs            src/d.rs              # twin: a member names a::b, not src/b.rs

echo "-- IN: directives inside an inline mod read from the inline module"
hasnt INa  "$I" src/a/mod.rs        src/a/x.rs            # mod tests { use super::*; } in a/x.rs is module a::x itself
has   INb  "$I" src/a/mod.rs        src/a/y.rs            # twin: a file-level use super::Foo in a/y.rs is module a
hasnt INc  "$I" src/a/x/helper.rs   src/a/x.rs            # self:: inside mod tests is the inline module, not a::x
has   INd  "$I" src/a/y/helper.rs   src/a/y.rs            # twin: a file-level use self::helper in a/y.rs is a/y/helper.rs
has   INe  "$I" src/k/b.rs          src/k/j.rs            # super::super:: across one inline boundary: k's b
hasnt INe- "$I" src/b.rs            src/k/j.rs            # ... not the crate root's b (the file-level super::super)
has   INf  "$I" src/k.rs            src/k/j.rs            # twin: file-level use super::kf in k/j.rs is k.rs
has   ING  "$I" src/k/b.rs          src/k/m.rs            # super^3 across two nested inline mods climbs one: k's b
hasnt ING- "$I" src/b.rs            src/k/m.rs
hasnt INh  "$I" src/k.rs            src/k/m.rs            # mod t3 { use super::kf; } names m itself: no edge to k.rs
has   INi  "$I" src/outer/inner.rs  src/lib.rs            # mod outer { mod inner; } in lib.rs is src/outer/inner.rs
hasnt INi- "$I" src/inner.rs        src/lib.rs            # ... never a same-named src/inner.rs
has   INj  "$I" src/outer/deep/z.rs src/lib.rs            # two inline levels: src/outer/deep/z.rs
hasnt INj- "$I" src/z.rs            src/lib.rs
hasnt INj2 "$I" src/outer/z.rs      src/lib.rs
has   INk  "$I" src/k/outer2/inn.rs src/k.rs              # in a plain file k.rs: src/k/outer2/inn.rs
hasnt INk- "$I" src/k/inn.rs        src/k.rs
hasnt INk2 "$I" src/inn.rs          src/k.rs
has   INl  "$I" src/b.rs            src/lib.rs            # twin: a plain `pub mod b;` in lib.rs

echo "-- determinism"
( cd "$M" && "$BIN" "$M" --deps --no-cache > "$TMP/d1.xml" 2>/dev/null ); r1=$?
( cd "$M" && "$BIN" "$M" --deps --no-cache > "$TMP/d2.xml" 2>/dev/null ); r2=$?
if [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && grep -q '<deps ' "$TMP/d1.xml" && cmp -s "$TMP/d1.xml" "$TMP/d2.xml"; then ok "--deps twice: byte-identical"
else no "--deps not deterministic or failed (exit $r1/$r2)"; fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "SOME FAILED"; fi
exit "$fail"
