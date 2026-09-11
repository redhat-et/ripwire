#!/usr/bin/env bash
# luarequirecheck.sh — kParserVer 81 gate: LUA `require "a.b"` is a physical dependency.
#
# `require` is an ordinary global function in Lua, which is why this tool read it as a call and emitted no
# Include record. It is also how an entire module system spells its dependencies — package.searchers turns
# the dotted name into a FILE through package.path — so reading it as a call made every Lua tree report a
# horizontal, edge-free architecture. test/luacheck.sh used to ASSERT that emptiness; its §2 now asserts
# the opposite and this gate carries the detail.
#
# Fixture test/luarequirefix (the resolve.h::resolveLuaRequire contract, one line each):
#   require "a.b"        -> a/b.lua            dotted name, dots become directory separators
#   require("pkg")       -> pkg/init.lua       the package form
#   require 'srcmod'     -> src/srcmod.lua     found under the src/ source root
#   require("socket")    -> no edge            an external rock: nothing in the tree answers
#   require(dynamic)     -> not captured       not a string literal, so there is nothing to read
#   require("a".."b")    -> not captured       concatenated: no single literal
#   require("shared")    -> no edge            AMBIGUOUS: ./shared.lua and src/shared.lua both answer
#   decoy/b.lua                                a same-BASENAME file `a.b` must never reach
#   plus require("a.b") / require("pkg") inside a function body, an if, and a table constructor
#
# Usage:  test/luarequirecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/luarequirecheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/luarequirefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/luarequirefix — fixture missing"; exit 2; }
echo "luarequirecheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --deps --no-cache >"$TMP/deps" 2>/dev/null
DEPS="$( cat "$TMP/deps" )"

# ── 1. CAPTURE: the clean dotted specifier, not the quoted call text ──────────────────────────────────
for t in 'a.b' 'pkg' 'srcmod' 'socket' 'shared'; do
    printf '%s' "$DEPS" | grep -qF "<inc t=\"$t\"/>" \
        && ok "capture: <inc t=\"$t\"/> (specifier read through string_content — no quotes, no parens)" \
        || no "capture: no <inc t=\"$t\"/> row"
done
printf '%s' "$DEPS" | grep -q '<f p="main.lua" includes="8"' \
    && ok 'capture: exactly 8 directives — the two non-literal requires are NOT invented' \
    || no "capture: directive count wrong: $( printf '%s' "$DEPS" | grep -oE '<f p="main.lua" includes="[0-9]*"' )"

# ── 2. RESOLUTION: the package.path convention, by exact afferent count ──────────────────────────────
# a/b.lua is required THREE times (top level, inside a function, inside a table constructor) and
# pkg/init.lua twice (top level + inside an if): the counts are the container-walk arms.
printf '%s' "$DEPS" | grep -q '<f p="a/b.lua" afferent="3"/>' \
    && ok 'resolve: `require "a.b"` -> a/b.lua, afferent="3" (top level + function body + table field)' \
    || no "resolve: a/b.lua afferent wrong: $( printf '%s' "$DEPS" | grep -oE '<f p="a/b.lua" afferent="[0-9]*"/>' )"
printf '%s' "$DEPS" | grep -q '<f p="pkg/init.lua" afferent="2"/>' \
    && ok 'resolve: `require("pkg")` -> pkg/init.lua, afferent="2" (top level + inside an if)' \
    || no "resolve: pkg/init.lua afferent wrong: $( printf '%s' "$DEPS" | grep -oE '<f p="pkg/init.lua" afferent="[0-9]*"/>' )"
printf '%s' "$DEPS" | grep -q '<f p="src/srcmod.lua" afferent="1"/>' \
    && ok 'resolve: a bare name found under the src/ source root' \
    || no "resolve: src/srcmod.lua has no importer"

# ── 3. MUTATION CONTROLS ──────────────────────────────────────────────────────────────────────────────
# (a) unique-or-degrade: "shared" is answered by ./shared.lua AND src/shared.lua. A resolver that took the
#     first probe would pass every arm above and only fail here. main.lua's cone is therefore exactly
#     {itself, a/b.lua, pkg/init.lua, src/srcmod.lua} = 4.
printf '%s' "$DEPS" | grep -q '<f p="main.lua" includes="8" afferent="0" instab="1.00" transitive="4">' \
    && ok 'mutation control: the ambiguous `require("shared")` degrades — cone is 4, not 5 or 6' \
    || no "mutation control: the ambiguous require resolved: $( printf '%s' "$DEPS" | grep -oE '<f p="main.lua"[^>]*>' )"
printf '%s' "$DEPS" | grep -qE '<f p="(src/)?shared.lua" afferent=' \
    && no "mutation control: one of the two shared.lua files took the ambiguous edge" \
    || ok 'mutation control: neither shared.lua gained an importer'
# (b) no basename fallback: decoy/b.lua shares its basename with a/b.lua and is never named.
printf '%s' "$DEPS" | grep -q '<f p="decoy/b.lua" afferent=' \
    && no "mutation control: decoy/b.lua gained an importer — `a.b` was basename-matched" \
    || ok 'mutation control: decoy/b.lua has no importer (the dotted name is a PATH, not a basename)'
# (c) an unresolvable rock is a MISS, not an invention: `socket` shows as a row with no edge behind it.
printf '%s' "$DEPS" | grep -q '<inc t="socket"/>' \
    && ok 'floor: the external rock `socket` is disclosed as its own row and adds no edge' \
    || no "floor: the external require vanished instead of being shown"

# ── 4. CAPABILITY ─────────────────────────────────────────────────────────────────────────────────────
printf '%s' "$DEPS" | grep -q '<health files="7" dep_files="7"' \
    && ok 'capability: all 7 .lua files are dependency-capable (dep_files == files)' \
    || no "capability: dep_files wrong: $( printf '%s' "$DEPS" | grep -oE '<health [^/]*/>' )"
printf '%s' "$DEPS" | grep -qE 'dep_langs="[^"]*,lua[,"]' \
    && ok 'capability: <health dep_langs=> discloses lua in the capable set' \
    || no "capability: dep_langs= does not name lua"

# ── 5. root spelling, determinism, warm == cold, well-formed XML ──────────────────────────────────────
( cd "$FIX" && "$BIN" . --deps --no-cache 2>/dev/null ) | sed 's/ root="[^"]*"//' >"$TMP/dots"
"$BIN" "$FIX" --deps --no-cache 2>/dev/null | sed 's/ root="[^"]*"//' >"$TMP/abs"
cmp -s "$TMP/dots" "$TMP/abs" \
    && ok 'root spelling: a relative and an absolute crawl root resolve identically' \
    || { no 'root spelling: the source-root probes are anchored differently under the two spellings'; diff "$TMP/dots" "$TMP/abs" | head -4; }
"$BIN" "$FIX" --deps --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --deps --no-cache >"$TMP/d2" 2>/dev/null
cmp -s "$TMP/d1" "$TMP/d2" && ok "deterministic (two --no-cache runs identical)" || no "non-deterministic"
"$BIN" "$FIX" --deps --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --deps --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
cmp -s "$TMP/cold" "$TMP/warm" && ok "warm == cold (directives survive the cache round-trip)" || no "warm != cold"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
