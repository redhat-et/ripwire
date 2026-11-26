#!/usr/bin/env bash
# rustpathkwcheck.sh — gate for RUST-PATH-KEYWORD: a Rust call whose path starts at a module keyword — `crate::f()`, `self::f()`,
# `super::f()`, `super::super::f()` — binds the free item that module holds, and only that one.
#
# WHAT WAS BROKEN. rustQualifierOf keeps a path call's LAST segment as its qualifier, so `crate::rootfn()` carried qualifier="crate"
# (and `self::f()` "self", `super::f()` "super"). The H4 W3 scope guard (graph.h keepRustQualifiedCandidates) keeps a candidate only
# when its scope IS the qualifier or its file module is NAMED by it, and no def's scope or file module is spelled `crate`/`self`/`super`
# — so every such call was dropped as qualified_external: --uses listed the site, --callers listed nothing. `crate::a::af()` bound
# (qualifier "a" names src/a.rs), which is why the defect hid: only the one-segment keyword spelling died.
#
# The fix reads the whole written path from its keyword root against the crate's module layout (receiverevidence.h
# CallResultTypes::rustKeywordPathHolds), and for a crate the layout cannot see — a `[lib] path = "src/x.rs"` crate with no lib.rs, every
# zed crate — against the Cargo.toml manifest's own root. A candidate survives when it is a FREE item of exactly the module the path
# names (a top-level fn, or an inline `mod`'s member), in the caller's own crate.
#
# EVERY expected count is a literal read by hand off test/rustpathkwfix/*/src/*.rs.
#
# RED-FIRST (measured 2026-11-26, plain build at origin/main f7cfcec7a): 15 of the 23 checks FAIL — every positive keyword arm of §1
# and §2. The 8 that pass on base are the controls (`crate::a::af()`'s two checks, `crate::deep::deep_item()`'s caller row) and the five
# precision arms of §4, which are vacuous there since base binds no keyword call at all; they defend the fix against over-reach, the
# way rustqualcheck §5 does. (A member of an inline mod is named `inner::caller_…` in a row, so §1 matches that spelling.)
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/rustpathkwcheck.sh   |   bash test/rustpathkwcheck.sh asan/ripwire

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="test/rustpathkwfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$ROOT/$FIX" ] || { echo "no $FIX dir — fixture missing"; exit 2; }
cd "$ROOT"
echo "rustpathkwcheck: BIN=$BIN  CORPUS=$FIX"

run(){ perl -e 'alarm 30; exec @ARGV' "$BIN" "$@" 2>/dev/null; }
cnt(){ printf '%s' "$1" | grep -oE ' count="[0-9]+"' | head -1 | tr -dc 0-9; }

# $1 sym  $2 want count  $3 prose  [$4.. caller names that must each be listed]
callers(){
    local sym="$1" want="$2" prose="$3"; shift 3
    local out; out="$( run "$FIX" "--callers=$sym" --no-cache )"
    local got; got="$( cnt "$out" )"
    [ "${got:-REFUSED}" = "$want" ] && ok "--callers=$sym count=$want — $prose" || no "--callers=$sym expected count=$want, got '${got:-REFUSED}' — $prose"
    for n in "$@"; do
        printf '%s' "$out" | grep -q "<s [^>]*n=\"$n\"" && ok "  $sym is called by $n" || no "  $sym is NOT called by $n: ${out#*-->}"
    done
}

# ── §1 the layout-known crate (one/src/lib.rs) ───────────────────────────────────────────────────────────
callers one/src/lib.rs:rootfn 3 "crate::rootfn(), super::rootfn() from b.rs, super::super::rootfn() from b::inner" caller_crate caller_super inner::caller_inner_super2
callers sibling               2 "self::sibling() in b, super::sibling() from b::inner" caller_self inner::caller_inner_super
callers inner_helper          1 "self::inner_helper() inside the inline mod b::inner" inner::caller_inner_self

# ── §2 the manifest-rooted crate (three: [lib] path = src/three.rs, no lib.rs — zed's layout) ─────────────
callers manifest_root 2 "crate::manifest_root() and super::manifest_root() from deep.rs" caller_manifest_crate caller_manifest_super
callers deep_item     3 "self::deep_item(), super::deep_item() from deep/leaf.rs, crate::deep::deep_item()" caller_manifest_self caller_leaf_super caller_leaf_crate_path

# ── §3 controls: the multi-segment spelling bound before the fix and must still ────────────────────────────
callers af 1 "crate::a::af() (control: the file-module test already bound it)" caller_nested

# ── §4 precision: a keyword names ONE module of ONE crate ──────────────────────────────────────────────────
callers two/src/lib.rs:rootfn 0 "crate two's rootfn: crate one's crate::rootfn() never reaches another crate's root"
callers only_in_a             0 "crate::only_in_a(): the root holds no only_in_a, module a's does not answer"
callers paint                 0 "crate::paint(): Widget::paint is a method, never a module item"
W="$( run "$FIX" --callees=caller_wrong_self --no-cache )"
[ "$( cnt "$W" )" = 0 ] && ok "--callees=caller_wrong_self count=0 — self::rootfn() in b names b, not the root" || no "caller_wrong_self bound something: ${W#*-->}"
W="$( run "$FIX" --callees=caller_manifest_wrong --no-cache )"
[ "$( cnt "$W" )" = 0 ] && ok "--callees=caller_manifest_wrong count=0 — crate::deep_item() names three.rs, not deep.rs" || no "caller_manifest_wrong bound something: ${W#*-->}"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "rustpathkwcheck: FAILURES above"; exit 1; }
