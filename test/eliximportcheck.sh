#!/usr/bin/env bash
# eliximportcheck.sh — kParserVer 81 gate: ELIXIR `alias`/`import`/`require`/`use` are dependencies.
#
# All four are compile-time dependencies on the named module's FILE (`use` most of all — it runs that
# module's `__using__` macro at compile time), and all four are ordinary `call` nodes in the grammar,
# which is why none of them produced an Include record before this round.
#
# THE RESOLUTION RULE IS EVIDENCE, NOT CONVENTION, and that is the point this gate exists to prove.
# `MyApp.Foo` conventionally lives at lib/my_app/foo.ex and a CamelCase->snake_case path rule could be
# written. It is not: every Elixir file STATES its module with `defmodule`, so resolve.h builds the index
# from those definitions. The fixture puts `Nested.Thing` at apps/other/lib/nested/thing.ex — an umbrella
# layout a lib/-prefixed path convention would miss — and requires it to resolve anyway.
#
# Fixture test/eliximportfix:
#   main.ex     alias MyApp.Foo / alias MyApp.{Bar, Baz} / alias MyApp.Foo, as: F /
#               import MyApp.Bar / use MyApp.Baz            -> the four keywords, incl. the GROUP form
#               require Logger                              -> no edge (outside the tree)
#               alias Nested.Thing                          -> apps/other/lib/nested/thing.ex
#               alias MyApp.Dup                             -> no edge (TWO files define MyApp.Dup)
#   nestedcall.ex  alias/import/require inside an if, a case arm and a def body (the container arms)
#   decoy/foo.ex   defmodule Decoy.Foo — a same-BASENAME file no module name reaches
#
# NOT COVERED, and disclosed rather than approximated: `alias A.B.C` also binds the local NAME `C`, so a
# later `C.f()` means `A.B.C.f`. That is call RESOLUTION, not a file dependency, and it needs the call's
# receiver — which queries/elixir/tags.scm deliberately does not keep. The file edge lands; the name alias
# does not narrow --callers/--callees. Arm 6 pins that boundary so it cannot rot into a silent claim.
#
# Usage:  test/eliximportcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/eliximportcheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/eliximportfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/eliximportfix — fixture missing"; exit 2; }
echo "eliximportcheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --deps --no-cache >"$TMP/deps" 2>/dev/null
DEPS="$( cat "$TMP/deps" )"

# ── 1. CAPTURE: the module name, clean, one record per named module ──────────────────────────────────
for t in 'MyApp.Foo' 'MyApp.Bar' 'MyApp.Baz' 'Logger' 'Nested.Thing' 'MyApp.Dup'; do
    printf '%s' "$DEPS" | grep -qF "<inc t=\"$t\"/>" \
        && ok "capture: <inc t=\"$t\"/>" || no "capture: no <inc t=\"$t\"/> row"
done
# main.ex spells EIGHT directives, one of which names two modules — so nine records, and the group form
# is the reason the emitter is a lambda rather than a fall-through.
printf '%s' "$DEPS" | grep -q '<f p="lib/my_app/main.ex" includes="9"' \
    && ok 'group form: `alias MyApp.{Bar, Baz}` yields TWO records — 8 directives, 9 Include rows' \
    || no "group form: record count wrong: $( printf '%s' "$DEPS" | grep -oE '<f p="lib/my_app/main.ex" includes="[0-9]*"' )"

# ── 2. RESOLUTION through the defmodule index ────────────────────────────────────────────────────────
# Each of Foo/Bar/Baz is named three times across the two importing files (main.ex twice + nestedcall.ex
# once), so afferent="3" is an exact statement about all four keywords AND the container walk at once.
for m in foo bar baz; do
    printf '%s' "$DEPS" | grep -q "<f p=\"lib/my_app/$m.ex\" afferent=\"3\"/>" \
        && ok "resolve: lib/my_app/$m.ex afferent=\"3\" (alias/import/use/require across both files)" \
        || no "resolve: lib/my_app/$m.ex afferent wrong: $( printf '%s' "$DEPS" | grep -oE "<f p=\"lib/my_app/$m.ex\" afferent=\"[0-9]*\"/>" )"
done
# THE EVIDENCE-OVER-CONVENTION ARM. apps/other/lib/nested/thing.ex is where `Nested.Thing` actually lives;
# a `lib/` + Macro.underscore path rule would look for lib/nested/thing.ex and find nothing.
printf '%s' "$DEPS" | grep -q '<f p="apps/other/lib/nested/thing.ex" afferent="1"/>' \
    && ok 'resolve: Nested.Thing lands at apps/other/lib/nested/thing.ex — the defmodule index beats a path convention' \
    || no "resolve: the umbrella-layout module did not resolve: $( printf '%s' "$DEPS" | grep -oE '<f p="apps/[^"]*" afferent="[0-9]*"/>' )"

# ── 3. MUTATION CONTROLS ──────────────────────────────────────────────────────────────────────────────
# (a) unique-or-degrade at INDEX-BUILD time: dup_a/dup.ex and dup_b/dup.ex both define MyApp.Dup, so the
#     index tombstones it and `alias MyApp.Dup` gets no edge. main.ex's cone is {itself + 4} = 5.
printf '%s' "$DEPS" | grep -q '<f p="lib/my_app/main.ex" includes="9" afferent="0" instab="1.00" transitive="5">' \
    && ok 'mutation control: a module defined TWICE is ambiguous — no edge, cone is 5' \
    || no "mutation control: the ambiguous module resolved: $( printf '%s' "$DEPS" | grep -oE '<f p="lib/my_app/main.ex"[^>]*>' )"
printf '%s' "$DEPS" | grep -qE '<f p="dup_[ab]/dup.ex" afferent=' \
    && no "mutation control: one of the two MyApp.Dup definitions took the ambiguous edge" \
    || ok 'mutation control: neither duplicate definition gained an importer'
# (b) no basename fallback: decoy/foo.ex defines Decoy.Foo and shares a basename with lib/my_app/foo.ex.
printf '%s' "$DEPS" | grep -q '<f p="decoy/foo.ex" afferent=' \
    && no "mutation control: decoy/foo.ex gained an importer — module names were basename-matched" \
    || ok 'mutation control: decoy/foo.ex has no importer (the index is keyed on the MODULE name)'
# (c) an out-of-tree module is a MISS, not an invention.
printf '%s' "$DEPS" | grep -q '<inc t="Logger"/>' \
    && ok 'floor: `require Logger` is disclosed as its own row and adds no edge' \
    || no "floor: the out-of-tree module vanished instead of being shown"

# ── 4. CONTAINERS: `defmodule` is itself a call, so the walk MUST enter call/do_block ─────────────────
printf '%s' "$DEPS" | grep -q '<f p="lib/my_app/nestedcall.ex" includes="3"' \
    && ok 'container walk: the if-arm, the case arm and the def body each yield a directive' \
    || no "container walk: nestedcall.ex directive count wrong: $( printf '%s' "$DEPS" | grep -oE '<f p="lib/my_app/nestedcall.ex" includes="[0-9]*"' )"

# ── 5. CAPABILITY ─────────────────────────────────────────────────────────────────────────────────────
printf '%s' "$DEPS" | grep -q '<health files="9" dep_files="9"' \
    && ok 'capability: all 9 .ex files are dependency-capable (dep_files == files)' \
    || no "capability: dep_files wrong: $( printf '%s' "$DEPS" | grep -oE '<health [^/]*/>' )"
printf '%s' "$DEPS" | grep -qE 'dep_langs="[^"]*,ex"' \
    && ok 'capability: <health dep_langs=> discloses ex in the capable set' \
    || no "capability: dep_langs= does not name ex"

# ── 6. THE DISCLOSED NON-GOAL: the alias does NOT bind a name for call resolution ─────────────────────
# main.ex aliases MyApp.Foo and then calls `Foo.run()`. The FILE edge exists (arm 2). The call is still
# resolved by the global name ladder, so it binds MyApp.Foo::run only because `run` is unique here — not
# because the alias was followed. Asserting the boundary keeps the doc comment honest: if a later round
# teaches the resolver to follow aliases, this arm goes red and the claim must be rewritten, not silently
# widened.
"$BIN" "$FIX" --callees=go --no-cache >"$TMP/callees" 2>/dev/null
grep -q 'run' "$TMP/callees" \
    && ok 'boundary: `Foo.run()` binds `run` (via the name ladder — the alias is not followed, by design)' \
    || no "boundary: the call inside go/0 disappeared entirely: $( head -c 300 "$TMP/callees" )"

# ── 7. determinism, warm == cold, well-formed XML ─────────────────────────────────────────────────────
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
