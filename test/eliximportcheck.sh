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
# Arm 6 also checks alias-based call resolution with a same-named decoy and a mutated alias target.
# test/elixirsemanticcheck.sh covers lexical scope, arity and the other name-resolution rules.
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
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
printf '%s' "$DEPS" | grep -qE 'dep_langs="[^"]*,ex[,"]' \
    && ok 'capability: <health dep_langs=> discloses ex in the capable set' \
    || no "capability: dep_langs= does not name ex"

# ── 6. ALIAS RESOLUTION: a receiver's module wins over a same-named function elsewhere ──────────────
python3 - "$BIN" "$FIX" "$TMP" <<'PY'
import pathlib, shutil, subprocess, sys, xml.etree.ElementTree as ET
binary, source, tmp = sys.argv[1:]
fixture = pathlib.Path(tmp) / 'alias-control'
shutil.copytree(source, fixture)
(fixture / 'decoy/foo.ex').write_text('defmodule Decoy.Foo do\n  def run(), do: :decoy\nend\n')
def paths():
    tree = ET.fromstring(subprocess.check_output([binary, str(fixture), '--callees=go', '--no-cache']))
    return [s.get('p') for s in tree.iter('s')]
assert paths() and all(p.startswith('lib/my_app/foo.ex:') for p in paths()), paths()
main = fixture / 'lib/my_app/main.ex'
before = main.read_text()
after = before.replace('alias MyApp.Foo\n', 'alias Missing.Foo\n')
assert before != after
main.write_text(after)
assert not paths(), 'an unknown alias target fell back to a same-named function'
PY
[ "$?" -eq 0 ] && ok 'alias: exact module target, same-name decoy excluded, mutated unknown target unresolved' \
    || no 'alias call resolution failed'

# ── 7. determinism, warm == cold, well-formed XML ─────────────────────────────────────────────────────
"$BIN" "$FIX" --deps --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --deps --no-cache >"$TMP/d2" 2>/dev/null
if cmp -s "$TMP/d1" "$TMP/d2"; then ok "deterministic (two --no-cache runs identical)"; else no "non-deterministic"; fi
"$BIN" "$FIX" --deps --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --deps --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
if cmp -s "$TMP/cold" "$TMP/warm"; then ok "warm == cold (directives survive the cache round-trip)"; else no "warm != cold"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/d1" 2>/dev/null; then ok "xml well-formed"; else no "xml malformed"; fi
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
