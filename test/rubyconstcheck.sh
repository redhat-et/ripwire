#!/usr/bin/env bash
# rubyconstcheck.sh — parser version 82 gate: RUBY CONSTANT REFERENCES are dependencies, resolved through the
# corpus's OWN class/module index (the Ruby twin of the Elixir defmodule index), never a name→path rule.
#
# A Zeitwerk application has no `require` at all — a controller depends on a model by NAMING THE CONSTANT —
# and Rails gems declare their structure with `autoload :Name`. Measured before this round on a Rails app of
# 3532 .rb files (`--deps --limit=100000`, the uncapped <godfiles total=>): 103 files in the whole tree had
# an incoming dependency edge, most of them `rails_helper.rb`-shaped; after it, 385. The four declarative
# spellings this gate pins:
#   superclass          class User < Base
#   mixins              include M / extend M / prepend M           (one directive per constant argument)
#   autoload            autoload :Name                             (ActiveSupport::Autoload: the constant IS the target)
#   autoload with path  autoload :Name, "path"                     (Kernel#autoload: the PATH is what Ruby loads —
#                                                                   the existing load-path rule, one directive, not two)
#
# THE RULE is Ruby's own constant lookup, not a heuristic: a reference `Name` at lexical nesting [A, A::B] is
# looked up as A::B::Name, then A::Name, then Name — innermost first, first hit wins (Module.nesting).
# `::Name` is absolute. The index maps every fully-qualified class/module definition to the ONE file that
# defines it; a constant two files define resolves to NEITHER (unique-or-degrade — which is exactly right for
# a namespace like `module App` that every file reopens). A constant target is never probed as a path.
#
# TWO KINDS OF "DEFINED IN MANY FILES", told apart structurally, never by count:
#   * a NAMESPACE WRAPPER — `module App` whose body holds nothing but nested class/module definitions — defines
#     nothing and is not in the index. This is what makes the rule usable at all: measured on a 3532-file Rails
#     app, 124 constants were "multiply defined" by opens and 5 by bodies.
#   * a REOPENING with a body of its own (a monkey patch, a decorator, a core_ext) is a real second definer, and
#     a reference to that constant edges to EVERY real definer — change any of them and the constant changes.
#     Multiplicity (every answer is right) is not specifier ambiguity (exactly one is); only the latter degrades.
#
# Fixture test/rubyconstfix (crawl root = the fixture; 30 .rb files under lib/):
#   lib/app/user.rb           < Base, include Trackable, extend Searchable, prepend Audited → 4 edges
#   lib/app/audited.rb        `module App::Audited` — compact form, indexed as App::Audited
#   lib/app/admin/user.rb     < ::App::User                → absolute, lib/app/user.rb
#   lib/app/admin/report.rb   < User                       → LEXICAL: App::Admin::User (admin/user.rb), NOT App::User
#   lib/trackable.rb          top-level Trackable — DECOY: App::Trackable must win inside `module App`, and on a
#                             case-insensitive filesystem a path probe for "Trackable" would land here
#   lib/app/services.rb       extend ActiveSupport::Autoload (out of tree), autoload :Mailer, :Job (inside
#                             eager_autoload do), :Worker (inside autoload_under "impl" do — a PATH rule would
#                             need to model autoload_under; the index does not), autoload :Legacy, "lib/legacy_impl"
#   lib/app/dup.rb + lib/other/dup.rb   both OPEN App::Dup; other/dup.rb is a wrapper (one nested class) → uses_dup.rb's
#                             `< Dup` edges to lib/app/dup.rb only
#   lib/app/external.rb       < ActiveRecord::Base, include Comparable → rows, no edge (outside the tree)
#   lib/decoy/user.rb         Decoy::User — same basename as app/user.rb; nothing names it
#   lib/app/selfref.rb        `class UsesInner < Inner` in one file → directive shown, self-include dropped
#   lib/app/uses_point.rb     < Point where `Point = Struct.new` — DISCLOSED FLOOR: aliases are not indexed
#                             (point.rb's own row is the `Struct` receiver, parser version 83)
#   lib/app/dynamic.rb        include <call>, autoload :X, some_path, require some_variable → no directive invented;
#                             its one row is the `Object` receiver of `Object.const_get` (parser version 83)
#   lib/app/user_ext.rb       MONKEY PATCH: reopens App::User with a method → admin/user.rb's `::App::User` edges to
#                             user.rb AND user_ext.rb
#   lib/core_ext/string.rb    MONKEY PATCH of a core class: the tree's only definer of String → shouty.rb's `< String`
#   lib/app.rb + uses_ns.rb   `module App` is opened by 23 wrapper files and given a body by ONE; `include ::App`
#                             edges to that one file only
#   lib/app/geometry/nested_shape.rb + compact_shape.rb   SAME innermost open (App::Geometry), DIFFERENT chains:
#                             `module App; module Geometry` sees App::Helper (lib/app/helper.rb), `module App::Geometry`
#                             does not (Ruby raises NameError). The resolver's memo must be keyed on the whole chain
#                             — keyed on the innermost open alone, whichever file is crawled first fixes the other's answer
#
# Usage:  test/rubyconstcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyconstcheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/rubyconstfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/rubyconstfix — fixture missing"; exit 2; }
echo "rubyconstcheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --deps --limit=100000 --no-cache >"$TMP/deps" 2>/dev/null
DEPS="$( cat "$TMP/deps" )"
# a file's FULL row (the one carrying includes=), not its self-closing <godfiles> row; the directive rows of
# one file come out in source order, as one space-joined line
frow(){ printf '%s' "$DEPS" | grep -oE "<f p=\"$1\" includes=[^>]*>" | head -1; }
incs(){ printf '%s' "$DEPS" | grep -oE "<f p=\"$1\" includes=[^>]*>.*" | sed -E 's|</f>.*||' | grep -oE '<inc t="[^"]*"/>' | tr '\n' ' '; }

# ── 1. CAPTURE: each spelling is a directive, spelled AS WRITTEN ──────────────────────────────────────
printf '%s' "$DEPS" | grep -q '<f p="lib/app/user.rb" includes="4"' \
    && ok 'capture: superclass + include + extend + prepend = 4 directives on user.rb' \
    || no "capture: user.rb directive count: $( frow lib/app/user.rb )"
[ "$( incs lib/app/user.rb )" = '<inc t="Base"/> <inc t="Trackable"/> <inc t="Searchable"/> <inc t="Audited"/> ' ] \
    && ok 'capture: targets are the constants AS WRITTEN, in source order (Base Trackable Searchable Audited)' \
    || no "capture: user.rb rows: $( incs lib/app/user.rb )"
[ "$( incs lib/app/admin/user.rb )" = '<inc t="::App::User"/> ' ] \
    && ok 'capture: an absolute `::App::User` keeps its leading `::`' \
    || no "capture: admin/user.rb rows: $( incs lib/app/admin/user.rb )"
printf '%s' "$DEPS" | grep -q '<f p="lib/app/services.rb" includes="5"' \
    && ok 'capture: services.rb has 5 directives — extend + 3 autoload constants + 1 autoload path' \
    || no "capture: services.rb directive count: $( frow lib/app/services.rb )"
[ "$( incs lib/app/services.rb )" = '<inc t="ActiveSupport::Autoload"/> <inc t="Mailer"/> <inc t="Job"/> <inc t="Worker"/> <inc t="lib/legacy_impl"/> ' ] \
    && ok 'capture: `autoload :Name` yields the CONSTANT; `autoload :Name, "path"` yields the PATH (one directive, not two)' \
    || no "capture: services.rb rows: $( incs lib/app/services.rb )"
[ "$( incs lib/app/external.rb )" = '<inc t="ActiveRecord::Base"/> <inc t="Comparable"/> ' ] \
    && ok 'capture: out-of-tree constants are still SHOWN as directives (ActiveRecord::Base, Comparable)' \
    || no "capture: external.rb rows: $( incs lib/app/external.rb )"
[ "$( incs lib/app/dynamic.rb )" = '<inc t="Object"/> ' ] \
    && ok 'capture: dynamic.rb (include <call>, autoload with a variable path, require variable) invents NO directive — its one row is the `Object` RECEIVER of `Object.const_get` (parser version 83, test/rubyrecvcheck.sh), not the include' \
    || no "capture: dynamic.rb rows — a non-literal include/autoload/require was invented, or the Object receiver went missing: $( frow lib/app/dynamic.rb ) $( incs lib/app/dynamic.rb )"

# ── 2. RESOLUTION: the index + lexical lookup ────────────────────────────────────────────────────────
# Evidence is --impact's importer tier (`<f via="import" p= lazy=>`): UNCAPPED, per defining file (file:name
# disambiguates a reopened constant), and it carries the lazy bit. --deps' <godfiles> is capped at 12 rows
# and this fixture has more importees than that — a capped listing is not evidence of absence.
importers(){ "$BIN" "$FIX" --impact="$1" --no-cache 2>/dev/null | sed 's/<!--[^>]*-->//g' | grep -oE '<f via="import" p="[^"]*" lazy="[01]"/>' | tr '\n' ' '; }
expect(){ # expect SYM 'rows'  — exact importer set
    local got; got="$( importers "$1" )"
    if [ "$got" = "$2" ]; then ok "$3"; else no "$3 — importers of $1: ${got:-<none>}"; fi
}
expect Base       '<f via="import" p="lib/app/user.rb" lazy="0"/> ' 'resolve: `< Base` inside App::User → App::Base (lib/app/base.rb), load-time (lazy="0")'
expect Trackable  '<f via="import" p="lib/app/user.rb" lazy="0"/> ' 'resolve: `include Trackable` → App::Trackable, the INNER one — not the top-level decoy'
expect Searchable '<f via="import" p="lib/app/user.rb" lazy="0"/> ' 'resolve: `extend Searchable` → App::Searchable'
expect Audited    '<f via="import" p="lib/app/user.rb" lazy="0"/> ' 'resolve: `prepend Audited` → the COMPACT `module App::Audited` (indexed as App::Audited)'
expect lib/app/user.rb:User       '<f via="import" p="lib/app/admin/user.rb" lazy="0"/> ' 'resolve: `< ::App::User` (absolute) → lib/app/user.rb; report.rb'"'"'s bare `User` does NOT land here'
expect lib/app/user_ext.rb:User   '<f via="import" p="lib/app/admin/user.rb" lazy="0"/> ' 'resolve: MONKEY PATCH — user_ext.rb reopens App::User with a method and is a real second definer: the same edge lands here too'
expect lib/app/admin/user.rb:User '<f via="import" p="lib/app/admin/report.rb" lazy="0"/> ' 'resolve: LEXICAL — report.rb'"'"'s `< User` inside App::Admin resolves to App::Admin::User, the innermost nesting'
expect Mailer     '<f via="import" p="lib/app/services.rb" lazy="1"/> ' 'resolve: `autoload :Mailer` → App::Services::Mailer, LAZY (lazy="1")'
expect Job        '<f via="import" p="lib/app/services.rb" lazy="1"/> ' 'resolve: `autoload :Job` inside `eager_autoload do … end` → App::Services::Job'
expect Worker     '<f via="import" p="lib/app/services.rb" lazy="1"/> ' 'resolve: `autoload :Worker` inside `autoload_under "impl" do … end` → App::Services::Worker (no path rule needed)'
expect LegacyImpl '<f via="import" p="lib/app/services.rb" lazy="1"/> ' 'resolve: `autoload :Legacy, "lib/legacy_impl"` → the PATH lands through the load-path rule, lazy'
expect String     '<f via="import" p="lib/app/shouty.rb" lazy="0"/> '   'resolve: MONKEY PATCH of a core class — `< String` lands on the tree'"'"'s one definer of String (lib/core_ext/string.rb)'
expect lib/app.rb:App '<f via="import" p="lib/app/uses_ns.rb" lazy="0"/> ' 'resolve: NAMESPACE — `include ::App` edges to lib/app.rb, the one open of App with a body of its own'
expect Helper     '<f via="import" p="lib/app/geometry/nested_shape.rb" lazy="0"/> ' 'resolve: CHAIN — `< Helper` under `module App; module Geometry` reaches App::Helper; under compact `module App::Geometry` (same innermost open) it must NOT — the memo is keyed on the whole nesting chain'
printf '%s' "$DEPS" | grep -q '<f p="lib/app/geometry/compact_shape.rb" includes="1" afferent="0" instab="0.00"' \
    && ok 'resolve: CHAIN — compact_shape.rb'"'"'s `< Helper` is shown and resolves to nothing (App::Helper is not on its nesting chain)' \
    || no "resolve: CHAIN — compact_shape.rb row wrong: $( frow lib/app/geometry/compact_shape.rb )"

# ── 3. MUTATION CONTROLS ─────────────────────────────────────────────────────────────────────────────
expect lib/app/services.rb:App '' 'mutation control: the WRAPPER open of App in services.rb (nested opens only) received nothing from `include ::App`'
expect lib/app/dup.rb:Dup   '<f via="import" p="lib/app/uses_dup.rb" lazy="0"/> ' 'mutation control: `< Dup` → lib/app/dup.rb, the open with a body (empty = defines)'
expect lib/other/dup.rb:Dup ''  'mutation control: lib/other/dup.rb opens App::Dup as a WRAPPER (one nested class, nothing else) and is not a definer'
expect lib/trackable.rb:Trackable '' 'mutation control: top-level Trackable decoy untouched — App::Trackable wins, and no constant is probed as a path'
expect lib/decoy/user.rb:User ''  'mutation control: decoy/user.rb (same basename, other namespace) has no importer — no basename fallback'
printf '%s' "$DEPS" | grep -q '<f p="lib/app/uses_dup.rb" includes="1"' \
    && ok 'mutation control: the directive is SHOWN on uses_dup.rb' \
    || no "mutation control: uses_dup.rb row missing: $( frow lib/app/uses_dup.rb )"
printf '%s' "$DEPS" | grep -q '<f p="lib/app/selfref.rb" includes="1" afferent="0"' \
    && ok 'mutation control: a same-file reference is shown as a directive and dropped as a self-include' \
    || no "mutation control: selfref.rb row wrong: $( frow lib/app/selfref.rb )"
printf '%s' "$DEPS" | grep -q '<f p="lib/app/point.rb" includes="1" afferent="0"' \
    && ok 'floor: `Point = Struct.new` is not an open — uses_point.rb'"'"'s `< Geometry::Point` is shown and resolves to nothing; point.rb'"'"'s own row is its `Struct` receiver (parser version 83), afferent 0' \
    || no "floor: point.rb gained an importer (aliases indexed? move the floor note: tags.scm, this gate) or lost its Struct row: $( frow lib/app/point.rb )"
printf '%s' "$DEPS" | grep -q '<f p="lib/app/uses_point.rb" includes="1"' \
    && ok 'floor: the unresolved `< Geometry::Point` directive is still disclosed on uses_point.rb' \
    || no "floor: uses_point.rb row missing: $( frow lib/app/uses_point.rb )"
printf '%s' "$DEPS" | grep -qE '<f p="lib/(app/external|app/uses_point|app/selfref).rb" includes="[0-9]+" afferent="0" instab="0.00"' \
    && ok 'mutation control: a file whose directives all resolve to nothing has instab="0.00" — an unresolved row is disclosure, not an edge' \
    || no "mutation control: an unresolved directive minted an edge: $( frow lib/app/external.rb )"

# ── 4. CAPABILITY ────────────────────────────────────────────────────────────────────────────────────
printf '%s' "$DEPS" | grep -q '<health files="30" dep_files="30"' \
    && ok 'capability: all 30 .rb files are dependency-capable' \
    || no "capability: health wrong: $( printf '%s' "$DEPS" | grep -oE '<health [^/]*/>' )"

# ── 5. root spelling, determinism, warm == cold, well-formed XML ─────────────────────────────────────
( cd "$FIX" && "$BIN" . --deps --limit=100000 --no-cache 2>/dev/null ) | sed 's/ root="[^"]*"//' >"$TMP/dots"
"$BIN" "$FIX" --deps --limit=100000 --no-cache 2>/dev/null | sed 's/ root="[^"]*"//' >"$TMP/abs"
cmp -s "$TMP/dots" "$TMP/abs" \
    && ok 'root spelling: a relative and an absolute crawl root resolve identically' \
    || { no 'root spelling: the two spellings disagree'; diff "$TMP/dots" "$TMP/abs" | head -4; }
"$BIN" "$FIX" --deps --limit=100000 --no-cache >"$TMP/d2" 2>/dev/null
if cmp -s "$TMP/deps" "$TMP/d2"; then ok "deterministic (two --no-cache runs identical)"; else no "non-deterministic"; fi
"$BIN" "$FIX" --deps --limit=100000 --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --deps --limit=100000 --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
if cmp -s "$TMP/cold" "$TMP/warm"; then ok "warm == cold (constant directives survive the cache round-trip)"; else no "warm != cold"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/deps" 2>/dev/null; then ok "xml well-formed"; else no "xml malformed"; fi
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
