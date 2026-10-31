#!/usr/bin/env bash
# reexportcheck.sh — ALIAS-IMPORT (lane alias-import): a --for answer about a definition the task names carries the
# re-export statements that make it reachable under another module path (src/forreexport.h renderForReexports), from the
# TS/JS ReExport records the binds channel writes (src/ingest_importcap.h webReexportBindOf) and the Rust `use` records.
#
# Before the lane the answer printed the definition and stopped: no `pub use` / `export … from` statement was a row.
#
# Fixture test/reexportfix (a Cargo workspace of five crates + a TS tree):
#   R1  `where Boom used in main.rs is defined`: core_x/src/errors/mod.rs:2 `pub use shell::Boom` (item), core_x/src/lib.rs:4
#       `pub use errors::*` (glob="1"), engine/src/prelude.rs:1 `pub use core_x::{Boom, Other}` (a crate by its Cargo name
#       core-x), facade/src/lib.rs:1 `pub use core_x::errors` (a MODULE re-export), u app/src/main.rs:1 (the task-named file).
#   R2  NEAR MISSES: engine/src/alias.rs `pub use core_x::Boom as Bang` is a RENAME (#445): never a row, counted as_skipped="1";
#       engine/src/private.rs `use core_x::Boom` is not `pub`: never a row; other/src/lib.rs's same-named Boom has no re-export:
#       no def row of its own and none of core_x's rows.
#   T1  `where sayHello used in use.ts is defined`: ts/m/index.ts:1 `export { sayHello } from './impl'`, ts/alias.ts:1 as="sayHi",
#       ts/barrel.ts:1 `export * from './m'` (glob="1"), u ts/use.ts:1.
#   T2  `export * as ns from './impl'` (ts/m/index.ts:3) is a namespace: never a row; `export type { Shape }` IS a row (it moves a
#       name) and never a call edge: --callers=sayHello lists no ts/m/index.ts row.
#   C1  cycles terminate: core_x a.rs/b.rs glob each other; ts cyc1.ts/cyc2.ts star each other (one row each).
#   N2  a task spelling `(…)` / `[…]` around file names terminates (the tokenizer once spun on a `)` it never skipped).
#   N3  no cue word and no task-named file on the chain: no block; a task-named directory (app_main) alone suffices.
#   P1  `X from <module>` keeps only definitions under that package's directory (`from @x/ts`: ts/…, never core_x/…).
#   N1  a task with no code-shaped name prints no block; --json prints none; RIPWIRE_NO_REEXPORT_HOPS=1 removes exactly the block.
#
#   Fix round 1 (rv-alias-import F1-F4, L-1/L-2, N-3), fixture test/reexportfix2 (crate c + decoys) and one runtime TS chain:
#   F1  `pub mod private { pub use crate::m::Xray; }` publishes `c::private::Xray` (the inline mod is in the path), never `c::Xray`; the
#       next hop `pub use c::private::Xray` (facade) chains from it.
#   F2  `src/main.rs` beside lib.rs and `src/bin/**` are binary crates: a private `struct Widget` in main.rs is never the lib's Widget,
#       and a `pub struct Gizmo` in src/bin/tool.rs gets no block at all.
#   F3  `use crate::inner; pub use inner::Thing;` reads `inner` through its own import: the row belongs to c's Thing, never to the
#       workspace crate that happens to be named `inner`.
#       a `use` inside a sibling inline mod binds nothing at file level (`mod scoped { use crate::inner as m; } pub use m::Zed;` is c::Zed).
#       `extern crate dup as inner; pub use inner::Thing;` binds `inner` to the crate dup: refused, never the workspace crate `inner`.
#   F4  `pub(crate) use inner::Hidden;` is labelled vis="restricted", never a bare public path.
#   G1  two manifests that spell one crate name: cands="2" hedge on the row, and the twin definition prints same="1".
#   G2  `pub use super::n::SupItem;` resolves `super::` and publishes `c::m::p::SupItem`.
#   N-3 a 300-deep `export *` chain stops at 256 spellings and says capped="1" (a short chain never does).
#
#   Train 42b T-2 (rv-alias-import-delta NEW-1; runtime fixture: crate c with src/inner.rs beside a workspace crate `inner`, both
#   defining the items): a Rust import is in scope only in its OWN module and never from a function body.
#   X1a `use crate::inner; pub mod z { pub use inner::Thing5; }`: the child mod inherits no parent `use`, so the path is the crate inner.
#   X1b `fn helper() { use crate::inner; } pub use inner::Thing4;`: the fn-body import binds nothing at file level: the crate inner.
#   X1c twin: `pub mod scope2 { use crate::inner; pub use inner::Thing2; }` (same module) still reads through the import: c's Thing2.
#
# Usage: bash test/reexportcheck.sh [BIN]     (default build/ripwire; exits non-zero on any failure)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/reexportfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "FAIL: no binary at $BIN"; exit 1; }
echo "reexportcheck: $( "$BIN" --version 2>/dev/null )"

ask(){ ( cd "$FIX" || exit 1; HOME="$TMP" "$BIN" "$FIX" --no-cache "$@" </dev/null 2>/dev/null ); }
block(){ grep -o '<reexports>.*</reexports>' "$1"; }
has(){ local f="$1" what="$2" pat="$3"; if block "$f" | grep -qF -- "$pat"; then ok "$what"; else no "$what (missing: $pat)"; fi; }
hasnt(){ local f="$1" what="$2" pat="$3"; if block "$f" | grep -qF -- "$pat"; then no "$what (present: $pat)"; else ok "$what"; fi; }

ask "--for=where Boom used in main.rs is defined" >"$TMP/r1.xml"
has  "$TMP/r1.xml" "R1 def row core_x Boom"            '<def n="Boom" p="core_x/src/errors/shell.rs" l="1" at="core_x::errors::shell::Boom"'
has  "$TMP/r1.xml" "R1 item re-export errors/mod.rs:2"  '<rx p="core_x/src/errors/mod.rs" l="2" use="shell::Boom" at="core_x::errors::Boom"/>'
has  "$TMP/r1.xml" "R1 glob hop lib.rs:4 hedged"        '<rx p="core_x/src/lib.rs" l="4" use="errors::*" at="core_x::Boom" glob="1"/>'
has  "$TMP/r1.xml" "R1 cross-crate prelude.rs:1"        '<rx p="engine/src/prelude.rs" l="1" use="core_x::Boom" at="engine::prelude::Boom"/>'
has  "$TMP/r1.xml" "R1 module re-export facade"         '<rx p="facade/src/lib.rs" l="1" use="core_x::errors"'
n=$( block "$TMP/r1.xml" | grep -o '<rx p="facade/src/lib.rs"' | wc -l | tr -d ' ' )
if [ "$n" = 1 ]; then ok "R1 one statement, one row (the module re-export publishes two spellings)"; else no "R1 facade/src/lib.rs printed $n times"; fi
has  "$TMP/r1.xml" "R1 task-named use site main.rs:1"   '<u p="app/src/main.rs" l="1" use="engine::prelude::*" glob="1"/>'
has  "$TMP/r1.xml" "R2 rename counted (#445)"           'as_skipped="1"'
hasnt "$TMP/r1.xml" "R2 rename not a row"               'engine/src/alias.rs'
hasnt "$TMP/r1.xml" "R2 private use not a row"          'engine/src/private.rs'
hasnt "$TMP/r1.xml" "R2 same-named Boom keeps identity" 'other/src/lib.rs'

ask "--for=where sayHello used in use.ts is defined" >"$TMP/t1.xml"
has  "$TMP/t1.xml" "T1 barrel export-from index.ts:1"   '<rx p="ts/m/index.ts" l="1" from="./impl"/>'
has  "$TMP/t1.xml" "T1 renamed export-from as="         '<rx p="ts/alias.ts" l="1" from="./m/index" as="sayHi"/>'
has  "$TMP/t1.xml" "T1 star hop hedged"                 '<rx p="ts/barrel.ts" l="1" from="./m" glob="1"/>'
has  "$TMP/t1.xml" "T1 task-named import use.ts:1"      '<u p="ts/use.ts" l="1" from="./barrel"/>'
hasnt "$TMP/t1.xml" "T2 namespace export not a row"     'p="ts/m/index.ts" l="3"'
ask "--for=where Shape is defined" >"$TMP/t2.xml"
has  "$TMP/t2.xml" "T2 type-only re-export is a row"    '<rx p="ts/m/index.ts" l="2" from="./impl"/>'
ask --callers=sayHello >"$TMP/t2c.xml"
if grep -q 'ts/m/index.ts' "$TMP/t2c.xml"; then no "T2 a re-export is never a caller row"; else ok "T2 a re-export is never a caller row"; fi

ask "--for=where cycFn is defined" >"$TMP/c1.xml"; rc1=$?
ask "--for=where loopyFn is defined" >"$TMP/c2.xml"; rc2=$?
if [ "$rc1" = 0 ] && [ "$rc2" = 0 ]; then ok "C1 cyclic globs terminate (rc 0)"; else no "C1 rc $rc1 / $rc2"; fi
has  "$TMP/c1.xml" "C1 Rust glob cycle one row"         'total="1"'
has  "$TMP/c2.xml" "C1 TS star cycle one row"           'total="1"'

# N2: a task-file token ending at a break the skip loop did not eat (`)`, `]`) once spun forever (S1 kysely-02 timed out at 900 s)
( cd "$FIX" && HOME="$TMP" perl -e 'my $p = fork; if( !$p ) { open STDIN, "<", "/dev/null"; open STDOUT, ">", shift @ARGV; open STDERR, ">", "/dev/null"; exec @ARGV; exit 127 } $SIG{ALRM} = sub { kill 9, $p; waitpid( $p, 0 ); exit 124 }; alarm 120; waitpid( $p, 0 ); exit( $? >> 8 )' "$TMP/n2.xml" "$BIN" "$FIX" --no-cache "--for=where Boom (in main.rs) [see lib.rs] is defined)." )   # the child is KILLED at 120 s, never orphaned
n2rc=$?
if [ "$n2rc" = 0 ] && grep -q '<reexports>' "$TMP/n2.xml"; then ok "N2 a task with ) and ] terminates"; else no "N2 a task with ) and ] did not finish in 120 s (or printed no block)"; fi
# N3 (the WHEN gate): a code-shaped name with re-exports, but a task that does not ask where it comes from and names no file
# on its chain, prints nothing; the same name with only a task-named directory on the chain (no cue word) prints the block
ask "--for=how does Boom work at runtime" >"$TMP/n3.xml"
if grep -q '<reexports>' "$TMP/n3.xml"; then no "N3 uncued task, no task-named file: no block"; else ok "N3 uncued task, no task-named file: no block"; fi
ask "--for=Boom in the app_main example" >"$TMP/n4.xml"
has  "$TMP/n4.xml" "N3 uncued task whose chain reaches a task-named directory" '<u p="app_main/src/main.rs" l="1"'
ask "--for=where Shape from @fix/m is defined" >"$TMP/p1.xml"
has  "$TMP/p1.xml" "P1 a from-module keeps the def in its package"   '<def n="Shape" p="ts/m/impl.ts"'
ask "--for=where Boom from @fix/ts is defined" >"$TMP/p2.xml"
if grep -q '<reexports>' "$TMP/p2.xml"; then no "P1 a def outside the named package prints nothing"; else ok "P1 a def outside the named package prints nothing"; fi
ask "--for=add a new built-in filter command" >"$TMP/n1.xml"
if grep -q '<reexports>' "$TMP/n1.xml"; then no "N1 no code-shaped name: no block"; else ok "N1 no code-shaped name: no block"; fi
ask --json "--for=where Boom used in main.rs is defined" >"$TMP/n2.json"
if grep -q 'reexports' "$TMP/n2.json"; then no "N1 --json carries no block"; else ok "N1 --json carries no block"; fi
( cd "$FIX" || exit 1; RIPWIRE_NO_REEXPORT_HOPS=1 HOME="$TMP" "$BIN" "$FIX" --no-cache "--for=where Boom used in main.rs is defined" </dev/null 2>/dev/null ) >"$TMP/off.xml"
sed 's|<reexports>.*</reexports>||' "$TMP/r1.xml" >"$TMP/r1.stripped"
if cmp -s "$TMP/off.xml" "$TMP/r1.stripped"; then ok "N1 the off switch removes exactly the block"; else no "N1 the off switch changed more than the block"; fi
# ── fix round 1: the Rust module-identity guards (fixture test/reexportfix2) ────────────────────────────────────────────
FIX2="$ROOT/test/reexportfix2"
ask2(){ ( cd "$FIX2" || exit 1; HOME="$TMP" "$BIN" "$FIX2" --no-cache "$@" </dev/null 2>/dev/null ); }
ask2 "--for=where Xray is defined" >"$TMP/f1.xml"
has   "$TMP/f1.xml" "F1 a pub use inside an inline mod carries the mod in its path" '<rx p="c/src/lib.rs" l="4" use="crate::m::Xray" at="c::private::Xray"/>'
hasnt "$TMP/f1.xml" "F1 never the outer path"                                       'at="c::Xray"'
has   "$TMP/f1.xml" "F1 the next hop chains from the inline spelling"               '<rx p="facade/src/lib.rs" l="1" use="c::private::Xray" at="facade::Xray"/>'
ask2 "--for=where Widget is defined" >"$TMP/f2.xml"
has   "$TMP/f2.xml" "F2 the lib's Widget is the def"                                '<def n="Widget" p="c/src/lib.rs"'
hasnt "$TMP/f2.xml" "F2 main.rs is a binary crate: its private Widget is no def"    'c/src/main.rs'
ask2 "--for=where Gizmo is defined" >"$TMP/f2b.xml"
if grep -q '<reexports>' "$TMP/f2b.xml"; then no "F2 a src/bin/** type is no module of the lib: no block"; else ok "F2 a src/bin/** type is no module of the lib: no block"; fi
ask2 "--for=where Thing is defined" >"$TMP/f3.xml"
has   "$TMP/f3.xml" "F3 a path through a use-imported name resolves through the import" '<rx p="c/src/x/y.rs" l="2" use="inner::Thing" at="c::x::y::Thing"/>'
hasnt "$TMP/f3.xml" "F3 never the same-named workspace crate's Thing"               '<def n="Thing" p="inner/src/lib.rs"'
hasnt "$TMP/f3.xml" "F3 an extern crate alias is no same-named workspace crate"    'p="c/src/x/z.rs"'
ask2 "--for=where Zed is defined" >"$TMP/f3b.xml"
has   "$TMP/f3b.xml" "F3 an import inside another inline mod is not in scope here"   '<rx p="c/src/lib.rs" l="8" use="m::Zed" at="c::Zed"/>'
ask2 "--for=where Hidden is defined" >"$TMP/f4.xml"
has   "$TMP/f4.xml" "F4 pub(crate) use is labelled restricted"                      'use="inner::Hidden" at="c::Hidden" vis="restricted"/>'
ask2 "--for=where Entry is defined" >"$TMP/g1.xml"
has   "$TMP/g1.xml" "G1 two manifests spell the crate name: cands hedge"            'cands="2"'
has   "$TMP/g1.xml" "G1 the twin definition reached by the same statement is same" 'same="1"'
ask2 "--for=where SupItem is defined" >"$TMP/g2.xml"
has   "$TMP/g2.xml" "G2 a super:: path resolves"                                    '<rx p="c/src/m/p.rs" l="1" use="super::n::SupItem" at="c::m::p::SupItem"/>'
hasnt "$TMP/r1.xml" "N-3 a short chain is never capped"                             'capped="1"'
DEEP="$TMP/deep"; mkdir -p "$DEEP"
printf 'export function deepFn() {}\n' >"$DEEP/f0.ts"
for i in $( seq 1 300 ); do printf "export * from './f%d';\n" $(( i - 1 )) >"$DEEP/f$i.ts"; done
( cd "$DEEP" && HOME="$TMP" "$BIN" "$DEEP" --no-cache "--for=where deepFn is defined" </dev/null 2>/dev/null ) >"$TMP/n3deep.xml"
has   "$TMP/n3deep.xml" "N-3 the 256-spelling stop is disclosed beside total="       'capped="1"'
n=$( grep -o '<rx ' "$TMP/n3deep.xml" | wc -l | tr -d ' ' )
if [ "$n" = 8 ]; then ok "N-3 the row cap prints 8 of the capped chain's rows"; else no "N-3 the capped chain printed $n rx rows (cap 8)"; fi
T2="$TMP/t2"; mkdir -p "$T2/c/src/x" "$T2/inner/src"
printf '[package]\nname = "c"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\ninner = { path = "../inner" }\n' >"$T2/c/Cargo.toml"
printf '[package]\nname = "inner"\nversion = "0.1.0"\n' >"$T2/inner/Cargo.toml"
printf 'pub mod inner;\npub mod x;\npub mod scope2 { use crate::inner; pub use inner::Thing2; }\n' >"$T2/c/src/lib.rs"
printf 'pub struct Thing2;\npub struct Thing4;\npub struct Thing5;\n' >"$T2/c/src/inner.rs"
printf 'pub mod v;\npub mod y;\n' >"$T2/c/src/x/mod.rs"
printf 'use crate::inner;\npub mod z { pub use inner::Thing5; }\nfn uses() { let _ = inner::Thing2; }\n' >"$T2/c/src/x/v.rs"
printf 'fn helper() { use crate::inner; let _ = 1; }\npub use inner::Thing4;\n' >"$T2/c/src/x/y.rs"
printf 'pub struct Thing2;\npub struct Thing4;\npub struct Thing5;\n' >"$T2/inner/src/lib.rs"
ask3(){ ( cd "$T2" || exit 1; HOME="$TMP" "$BIN" "$T2" --no-cache "$@" </dev/null 2>/dev/null ); }
ask3 "--for=where Thing5 is defined" >"$TMP/t2a.xml"
has   "$TMP/t2a.xml" "X1a a child mod inherits no parent use: the workspace crate inner's Thing5"  '<def n="Thing5" p="inner/src/lib.rs"'
hasnt "$TMP/t2a.xml" "X1a never c's own Thing5 through the parent's import"                    '<def n="Thing5" p="c/src/inner.rs"'
ask3 "--for=where Thing4 is defined" >"$TMP/t2b.xml"
has   "$TMP/t2b.xml" "X1b a fn-body use binds nothing at file level: the crate inner's Thing4"   '<def n="Thing4" p="inner/src/lib.rs"'
hasnt "$TMP/t2b.xml" "X1b never c's own Thing4 through the fn-body import"                      '<def n="Thing4" p="c/src/inner.rs"'
ask3 "--for=where Thing2 is defined" >"$TMP/t2c.xml"
has   "$TMP/t2c.xml" "X1c twin: a same-module import is still read through: c's Thing2"         '<def n="Thing2" p="c/src/inner.rs"'
# ── CR pre-pass 42b (budget-audit honesty item): the block under --token-budget ────────────────────────────────────────────
# A token budget is a request the block must obey: the rows sit outside est_tokens, so under one they are NOT printed and a held marker
# names the count. RED on train head b50d9518 (rows printed, no marker); H3/H4 are twins that hold on both.
HB="--for=where sayHello used in use.ts is defined"
ask --token-budget=3000 "$HB" >"$TMP/h1.xml"
( cd "$FIX" || exit 1; RIPWIRE_NO_REEXPORT_HOPS=1 HOME="$TMP" "$BIN" "$FIX" --no-cache --token-budget=3000 "$HB" </dev/null 2>/dev/null ) >"$TMP/h1off.xml"
if grep -qE '<(def|rx|u) ' "$TMP/h1.xml"; then no "H1 --token-budget=3000 prints no re-export row"; else ok "H1 --token-budget=3000 prints no re-export row"; fi
if grep -qF '<reexports held="budget" defs="1"/>' "$TMP/h1.xml"; then ok "H2 the held marker names the definitions (defs=1)"; else no "H2 the held marker names the definitions (defs=1)"; fi
sed 's|<!-- reexports held=[^>]*-->||; s|<reexports held="budget"[^>]*/>||' "$TMP/h1.xml" >"$TMP/h1.stripped"
if cmp -s "$TMP/h1off.xml" "$TMP/h1.stripped"; then ok "H3 the answer minus the marker is the off-switch answer, est_tokens included"; else no "H3 the held marker changed more than itself"; fi
ask "$HB" >"$TMP/h4.xml"
if grep -qF '<rx p="ts/m/index.ts"' "$TMP/h4.xml" && ! grep -qF 'held="budget"' "$TMP/h4.xml"; then ok "H4 twin: no budget, the rows print and no marker"; else no "H4 twin: no budget, the rows print and no marker"; fi
ask --token-budget=3000 "--for=add a new built-in filter command" >"$TMP/h5.xml"
if grep -qF 'reexports' "$TMP/h5.xml"; then no "H5 twin: a task with no chain carries no marker under a budget"; else ok "H5 twin: a task with no chain carries no marker under a budget"; fi
if command -v xmllint >/dev/null 2>&1; then
    for f in f1 f3 f4 g1 n3deep t2a t2b t2c h1; do if xmllint --noout "$TMP/$f.xml" 2>/dev/null; then ok "xml well-formed $f"; else no "xml malformed $f"; fi; done
fi
if command -v xmllint >/dev/null 2>&1; then
    for f in r1 t1 t2 c1; do if xmllint --noout "$TMP/$f.xml" 2>/dev/null; then ok "xml well-formed $f"; else no "xml malformed $f"; fi; done
fi

[ "$fail" = 0 ] && { echo "reexportcheck: PASS"; exit 0; }
echo "reexportcheck: FAIL"; exit 1
