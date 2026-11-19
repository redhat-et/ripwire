#!/usr/bin/env bash
# rustmacrocallcheck.sh — BX2 FIX 5: a call written inside a Rust `macro_rules!` TRANSCRIBER is a call of that macro
# (ingest_names.h scanTranscriberCalls; lane BS1's axum-02 shape, results/BS1_BLINDSPOT_1118).
#
#   test/rustmacrocallcheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# axum calls Route::oneshot_inner_owned only inside the fn-local `call!` macro_rules of MethodRouter::call_with_state
# (`return route.oneshot_inner_owned($req);`). A token tree is not parsed, so no tags pattern saw the call: --callers listed
# route.rs and mod.rs and missed method_routing.rs. The transcriber is now scanned the way a C macro body is (a lexical floor):
# `name(`, `.name(`, `a::name(` and `$crate::a::name(` are Call references of the macro, so its span owns them.
#
# Arm classes: [P] positive — RED on the parent binary (integration/0.6.11-batch 259352fc0); [N] near miss — a shape the scan
# must not read as a call; [C] control — holds on every binary.
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

echo "rustmacrocallcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }

# ── the corpus, written here (no file of this tree is read as a fixture) ─────────────────────────────────────────────
# route.rs  Route::oneshot_owned (the target), helper_fn, decoy_fn, string_fn, matcher_fn, shadow_fn — each a real function.
# method.rs the axum shape: a fn-local `call!` whose transcriber calls route.oneshot_owned($req) (a member call).
# top.rs    `wrap!` calls $crate::route::helper_fn($x) (a $crate path call) and route::plain_fn (a path call); its matcher spells
#           `matcher_fn ( $x:expr )` (a matcher is never scanned); its transcriber defines `fn shadow_fn()` (a definition),
#           calls `$f(1)` (a metavariable), names "string_fn(" in a string and decoy_fn( in a comment, and `if (`.
mkdir -p "$DIR/src"
cat >"$DIR/src/route.rs" <<'R'
pub struct Route;
impl Route {
    pub fn oneshot_owned(self, req: u32) -> u32 { req }
    pub fn call_owned(self, req: u32) -> u32 { self.oneshot_owned(req) }
}
pub fn helper_fn(x: u32) -> u32 { x }
pub fn plain_fn(x: u32) -> u32 { x }
pub fn decoy_fn() {}
pub fn string_fn() {}
pub fn matcher_fn() {}
pub fn shadow_fn() {}
R
cat >"$DIR/src/method.rs" <<'R'
use crate::route::Route;
pub struct Router { get: Option<Route> }
impl Router {
    pub fn call_with_state(&self, req: u32) -> u32 {
        macro_rules! call {
            ($req:expr, $svc:expr) => {
                if let Some(route) = $svc {
                    return route.oneshot_owned($req);
                }
            };
        }
        call!(req, self.get.clone());
        0
    }
}
R
cat >"$DIR/src/top.rs" <<'R'
#[macro_export]
macro_rules! wrap {
    (matcher_fn ( $x:expr ), $f:ident) => {
        {
            fn shadow_fn() {}
            let _s = "string_fn(";
            // decoy_fn(
            if ($x > 0) { $f(1); }
            $crate::route::helper_fn($x) + route::plain_fn($x)
        }
    };
}
pub fn user() -> u32 { wrap!(matcher_fn(3), drop) }
R
printf 'mod route;\nmod method;\nmod top;\n' >"$DIR/src/lib.rs"
cd "$DIR" || exit 1
export TMPDIR="$DIR/tmp"; mkdir -p "$TMPDIR"
rw(){ "$BIN" "$@" 2>/dev/null; }

echo "[P] a call inside a transcriber is a call of its macro"
a="$( rw . --callers=oneshot_owned )"
has "$a" 'n="Router::call" p="src/method.rs:5"' "[P1] --callers=oneshot_owned lists the fn-local call! macro (its row: method.rs:5)"
has "$a" 'p="src/route.rs:4"' "[C1] the direct caller Route::call_owned stays"
a="$( rw . --callers=helper_fn )"
has "$a" 'n="wrap" p="src/top.rs:2"' "[P2] a \$crate::route::helper_fn( path call is a call of wrap!"
a="$( rw . --callers=plain_fn )"
has "$a" 'n="wrap" p="src/top.rs:2"' "[P3] a route::plain_fn( path call is a call of wrap!"
a="$( rw . --impact=oneshot_owned )"
has "$a" 'Router::call' "[P4] --impact reaches the macro (and so call_with_state) as a caller"

echo "[N] what the scan must not read as a call"
for f in decoy_fn string_fn matcher_fn shadow_fn; do
    a="$( rw . --callers=$f )"
    hasnt "$a" 'p="src/top.rs' "[N] --callers=$f lists nothing in top.rs (comment, string, matcher, fn definition)"
done
a="$( rw . --callers=drop )"
hasnt "$a" 'src/top.rs' "[N5] a metavariable call \$f( is no call of anything named f"

echo "[C] the macro's own row and determinism"
a="$( rw . --callees=call_with_state )"
has "$a" 'n="Router::call"' "[C2] call_with_state still calls its call! macro"
b="$( rw . --callers=oneshot_owned )"
if [ "$( rw . --callers=oneshot_owned )" = "$b" ]; then ok "[C3] two runs byte-identical"; else no "[C3] two runs differ"; fi

if [ "$fail" -eq 0 ]; then echo "rustmacrocallcheck: ALL PASS"; else echo "rustmacrocallcheck: FAIL"; fi
exit "$fail"
