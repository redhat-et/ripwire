#!/usr/bin/env bash
# rubyrecvcheck.sh — parser version 83 gate: a RUBY CONSTANT RECEIVER (`User.find`, `App::Mailer.deliver`,
# `Struct.new`) is a dependency directive — round two of the Ruby constant work, on top of parser version 82's
# declarative shapes (superclass, mixins, autoload; test/rubyconstcheck.sh) and the same corpus-own index.
#
# This is the Zeitwerk dependency proper. An application file almost never says `require`; it says `User.find`
# and the autoloader loads lib/app/user.rb on that first reference. Measured with the Prism prototype on the
# four Ruby corpora (receiver references → distinct (file, nesting, written name) → resolved edge records
# before → after dedupe): activesupport lib 1156 → 703 refs, 2062 → 1368 edges; activerecord lib 2050 → 1365,
# 1794 → 988; a Rails app of 3532 .rb files 16680 → 9296, 10198 → 5592; a second Rails app of 1895 .rb files
# 9487 → 4986, 3971 → 1832. The declarative round reached 385 importee files on the first app; receivers are
# where the rest of the graph is.
#
# THE RULE, in four decisions this gate pins (each stated, none asked):
#   1. WHAT is a receiver directive: a `call` whose receiver is a constant or a constant chain (`A::B::C`,
#      `::A::B`), spelled AS WRITTEN. A receiver whose chain head is not a constant (`repo::Finder`,
#      `self.class`, an identifier, an ivar) is nothing. A constant that is an ARGUMENT (`raise Errors::Boom`,
#      `validates_with Foo`) or a RESCUE class is NOT a receiver — a DISCLOSED FLOOR of this round.
#   2. DEDUPE at extraction, per (file, innermost nesting open, written name): Zeitwerk loads a constant ONCE per
#      process, on its first reference; the second `User.find` in the same body is not a new dependency. The
#      FIRST occurrence in source order carries the byte; the lazy bit is the AND over every occurrence — one
#      load-time site makes the directive load-time, whichever order the sites come in (a receiver inside a
#      method written ABOVE the same receiver at class-body level was, before parser version 86, a lazy
#      directive, and the load-time dependency vanished from the structure). The declarative shapes stay
#      one directive per occurrence (each IS a statement). The nesting is IN the key: `User` inside `module
#      Admin` and `User` at file level may be different constants, and are in this fixture. A different spelling
#      of the same constant (`Time` and `::Time`) is a different directive — the spelling is what the reader sees.
#   3. LAZY: a receiver inside a `method`, `singleton_method`, `lambda`, `block` or `do_block` is lazy="1" — it
#      runs when and if that closure runs, exactly the TS/JS function-body rule (parser version 72) applied to
#      Ruby's closure kinds. A receiver at class-body or file level runs at load: lazy="0". --impact's importer
#      tier says lazy="1" only when EVERY edge from that importer into the target is lazy.
#   4. RESOLUTION is round one's, unchanged: Module.nesting innermost-first then Object, `::` absolute, a
#      namespace wrapper defines nothing, a genuine reopening fans out, a same-file reference is shown and
#      dropped as a self-include, an out-of-tree receiver (`Time`, `Struct`, `Object`) is SHOWN and edges nowhere
#      — the same posture every Python `import os` row already has.
#   5. STRUCTURE vs USE. A LAZY edge — every occurrence of the pair written inside a closure (or an autoload,
#      or a TS/JS require() inside a function) — is a USE, not a load-time dependency: it is in --impact's
#      importer tier (lazy="1") and in the file's own <inc t=> rows, and it is NOT in the load-time STRUCTURE
#      --deps/--arch measure — afferent, instab, transitive, godfiles, stabledeps, cycles, ccd/acd/nccd/shape.
#      Under runtime references a Rails app is one strongly-connected core (measured: a 3532-file app went
#      ccd 12 740 → 1 407 232, every corpus "tangled"), and a lens that reads the same everywhere is not a
#      lens. The cut is disclosed where it is made: <health lazy_edges=N> counts the resolved pairs the
#      structure leaves out, and a file row carries lazy_edges=N for its own. A lazy edge is not an
#      unresolved one: the unresolved row has no lazy_edges= and no importer; the lazy row has both.
#
# The receiver chain is validated ITERATIVELY (parser version 86): `A::B::…::Z` is a left-nested scope_resolution
# and a recursive check overflowed a parse worker's stack at ~5000 segments (SIGBUS, measured on macOS, the
# whole run gone). A chain of 150 000 segments is generated at gate time and must come out as ONE directive.
#
# Fixture test/rubyrecvfix (crawl root = the fixture; 18 .rb files under lib/):
#   lib/app/report.rb         Helper (class body, lazy=0), User ×2 (deduped), App::Mailer, Time ×2 (deduped),
#                             ::Time (own spelling), `raise Errors::Boom` + `rescue Errors::Boom` (floor) → 5 rows
#   lib/app/two_scopes.rb     `User.find` under App::Sync AND under App::Admin::Resync — same file, same written
#                             name, two nestings → TWO directives, to lib/app/user.rb and lib/app/admin/user.rb
#   lib/app/lazy_levels.rb    Helper at class-body level (lazy=0); Mailer in a lambda, User in a singleton method,
#                             Admin::User in a do-block (all lazy=1)
#   lib/app/eager_after_lazy.rb  `Helper.fmt` inside a method FIRST, then at class-body level → ONE directive, lazy=0
#   lib/app/admin/audit.rb    `User.find` inside App::Admin → App::Admin::User (LEXICAL), not App::User
#   lib/app/admin/export.rb   `::App::User.find` inside App::Admin → lib/app/user.rb (ABSOLUTE)
#   lib/script.rb             no module: `User.find` at file level → the top-level `class User` (lib/user.rb), lazy=0
#   lib/app/self_use.rb       `Cache.get` inside App::Cache → shown, dropped as a self-include
#   lib/app/dynamic.rb        identifier / self.class / ivar / `repo::Finder` / receiver-less → nothing; the one
#                             constant receiver in it (`Object`) is its one row
#   lib/app/point.rb          `Point = Struct.new` — the alias is still not indexed (floor), `Struct` is a shown row
#   lib/decoy/user.rb         Decoy::User — same basename as app/user.rb and user.rb; nothing names it
#   lib/app/errors.rb         App::Errors::Boom — named only as an argument and a rescue class → no importer (floor)
#
# Usage:  test/rubyrecvcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyrecvcheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/rubyrecvfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/rubyrecvfix — fixture missing"; exit 2; }
echo "rubyrecvcheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --deps --limit=100000 --no-cache >"$TMP/deps" 2>/dev/null
DEPS="$( cat "$TMP/deps" )"
# a file's FULL row (the one carrying includes=), not its self-closing <godfiles> row; the directive rows of
# one file come out in source order, as one space-joined line
frow(){ printf '%s' "$DEPS" | grep -oE "<f p=\"$1\" includes=[^>]*>" | head -1; }
incs(){ printf '%s' "$DEPS" | grep -oE "<f p=\"$1\" includes=[^>]*>.*" | sed -E 's|</f>.*||' | grep -oE '<inc t="[^"]*"/>' | tr '\n' ' '; }

# ── 1. CAPTURE + DEDUPE: what is a receiver directive, spelled as written, once per (file, nesting, name) ──
[ "$( incs lib/app/report.rb )" = '<inc t="Helper"/> <inc t="User"/> <inc t="App::Mailer"/> <inc t="Time"/> <inc t="::Time"/> ' ] \
    && ok 'capture: report.rb = Helper User App::Mailer Time ::Time — source order, AS WRITTEN, each constant ONCE (User ×2 and Time ×2 deduped), `::Time` its own spelling' \
    || no "capture: report.rb rows: $( incs lib/app/report.rb )"
printf '%s' "$DEPS" | grep -q '<f p="lib/app/report.rb" includes="5"' \
    && ok 'dedupe: report.rb counts 5 directives, not the 7 receiver sites it has (nor the 9 constant mentions)' \
    || no "dedupe: report.rb directive count: $( frow lib/app/report.rb )"
[ "$( incs lib/app/two_scopes.rb )" = '<inc t="User"/> <inc t="User"/> ' ] \
    && ok 'dedupe: the nesting is IN the key — `User` under App::Sync and `User` under App::Admin::Resync are two directives in one file' \
    || no "dedupe: two_scopes.rb rows: $( incs lib/app/two_scopes.rb )"
[ "$( incs lib/app/lazy_levels.rb )" = '<inc t="Helper"/> <inc t="Mailer"/> <inc t="User"/> <inc t="Admin::User"/> ' ] \
    && ok 'capture: a receiver is captured at class-body level, inside a lambda, inside a singleton method and inside a do-block' \
    || no "capture: lazy_levels.rb rows: $( incs lib/app/lazy_levels.rb )"
[ "$( incs lib/app/dynamic.rb )" = '<inc t="Object"/> ' ] \
    && ok 'capture: identifier / self.class / ivar / `repo::Finder` (non-constant chain head) / receiver-less yield NOTHING; the one constant receiver (`Object`) is the one row' \
    || no "capture: dynamic.rb rows: $( incs lib/app/dynamic.rb )"
[ "$( incs lib/script.rb )" = '<inc t="User"/> ' ] \
    && ok 'capture: a file-level receiver with no module is captured (once — `User.find` and `User.name` dedupe)' \
    || no "capture: script.rb rows: $( incs lib/script.rb )"
[ "$( incs lib/app/point.rb )" = '<inc t="Struct"/> ' ] \
    && ok 'capture: `Point = Struct.new` — the `Struct` receiver is a shown directive (the alias itself is still not indexed)' \
    || no "capture: point.rb rows: $( incs lib/app/point.rb )"

# ── 2. RESOLUTION + LAZY: --impact's importer tier (`<f via="import" p= lazy=>`, uncapped, path order) ──────
importers(){ "$BIN" "$FIX" --impact="$1" --no-cache 2>/dev/null | sed 's/<!--[^>]*-->//g' | grep -oE '<f via="import" p="[^"]*" lazy="[01]"/>' | tr '\n' ' '; }
expect(){ # expect SYM 'rows'  — exact importer set
    local got; got="$( importers "$1" )"
    if [ "$got" = "$2" ]; then ok "$3"; else no "$3 — importers of $1: ${got:-<none>}"; fi
}
expect lib/app/user.rb:User \
    '<f via="import" p="lib/app/admin/export.rb" lazy="1"/> <f via="import" p="lib/app/lazy_levels.rb" lazy="1"/> <f via="import" p="lib/app/report.rb" lazy="1"/> <f via="import" p="lib/app/two_scopes.rb" lazy="1"/> ' \
    'resolve: App::User is reached by `User.find` (report, two_scopes, lazy_levels) and `::App::User.find` (admin/export) — all inside closures, lazy="1"'
expect lib/app/admin/user.rb:User \
    '<f via="import" p="lib/app/admin/audit.rb" lazy="1"/> <f via="import" p="lib/app/lazy_levels.rb" lazy="1"/> <f via="import" p="lib/app/two_scopes.rb" lazy="1"/> ' \
    'resolve: LEXICAL — `User.find` inside App::Admin (audit, two_scopes'"'"' second nesting) and `Admin::User.find` inside App (lazy_levels) land on App::Admin::User'
expect lib/user.rb:User \
    '<f via="import" p="lib/script.rb" lazy="0"/> ' \
    'resolve: OBJECT LEVEL — script.rb has no module, so `User` is the top-level class; a file-level receiver is load-time (lazy="0")'
expect Helper \
    '<f via="import" p="lib/app/eager_after_lazy.rb" lazy="0"/> <f via="import" p="lib/app/lazy_levels.rb" lazy="0"/> <f via="import" p="lib/app/report.rb" lazy="0"/> ' \
    'lazy: a receiver at CLASS-BODY level runs at load — `Helper.fmt` in report.rb (constant initializer), lazy_levels.rb (bare statement) and eager_after_lazy.rb (below a lazy site) are lazy="0"'
expect Mailer \
    '<f via="import" p="lib/app/lazy_levels.rb" lazy="1"/> <f via="import" p="lib/app/report.rb" lazy="1"/> ' \
    'lazy: a receiver inside a LAMBDA (lazy_levels `-> { Mailer.deliver }`) and inside a method body (report) is lazy="1"'
expect lib/decoy/user.rb:User '' 'mutation control: Decoy::User (same basename as two other User files) has no importer — no basename fallback, no bare-name fallback'
expect lib/app.rb:App '' 'mutation control: `App::Mailer` is a receiver chain, not a reference to App — lib/app.rb receives nothing'
expect Boom '' 'floor: App::Errors::Boom is named only as `raise` argument and `rescue` class — not receivers, not captured (disclosed floor)'
printf '%s' "$DEPS" | grep -q '<f p="lib/app/self_use.rb" includes="1" afferent="0"' \
    && ok 'mutation control: `Cache.get` inside App::Cache is shown as a directive and dropped as a self-include' \
    || no "mutation control: self_use.rb row wrong: $( frow lib/app/self_use.rb )"
printf '%s' "$DEPS" | grep -qE '<f p="lib/app/dynamic.rb" includes="1" afferent="0" instab="0.00"' \
    && ok 'mutation control: an out-of-tree receiver (`Object`) is a shown row with no edge — instab="0.00", never a guessed edge' \
    || no "mutation control: dynamic.rb row wrong: $( frow lib/app/dynamic.rb )"
printf '%s' "$DEPS" | grep -q '<f p="lib/app/errors.rb" includes="1" afferent="0"' \
    && ok 'round one still holds: errors.rb'"'"'s `< StandardError` is the declarative directive it was (shown, unresolved)' \
    || no "round one regression: errors.rb row: $( frow lib/app/errors.rb )"

# ── 3. CAPABILITY ────────────────────────────────────────────────────────────────────────────────────
printf '%s' "$DEPS" | grep -q '<health files="18" dep_files="18"' \
    && ok 'capability: all 18 .rb files are dependency-capable' \
    || no "capability: health wrong: $( printf '%s' "$DEPS" | grep -oE '<health [^/]*/>' )"

# ── 4. STRUCTURE vs USE: a lazy edge is in --impact and the rows, not in the load-time structure ────
# Load-time edges in this fixture: report.rb → helper.rb (class-body `Helper.fmt`), lazy_levels.rb → helper.rb
# (class-body), eager_after_lazy.rb → helper.rb (class-body site below a method site), script.rb → lib/user.rb
# (file level). Everything else resolved is inside a closure: 9 pairs.
# ccd = Σ transitive cones (self included): 14 files × 1 + 4 files × 2 = 22; acd = 22/18 = 1.2.
printf '%s' "$DEPS" | grep -q '<health files="18" dep_files="18" ccd="22" acd="1.2" ' \
    && ok 'structure: ccd counts the 4 load-time edges only — 22 over 18 files, acd 1.2 (with the 9 lazy edges in it would be one tangle)' \
    || no "structure: health: $( printf '%s' "$DEPS" | grep -oE '<health [^/]*/>' )"
printf '%s' "$DEPS" | grep -qE '<health [^>]*shape="horizontal" lazy_edges="9" dep_langs=' \
    && ok 'structure: <health lazy_edges="9"> discloses the resolved pairs the structure leaves out; the shape stays horizontal' \
    || no "structure: lazy_edges=/shape= wrong: $( printf '%s' "$DEPS" | grep -oE '<health [^/]*/>' )"
[ "$( printf '%s' "$DEPS" | grep -oE '<godfiles [^>]*>.*</godfiles>' | sed 's|</godfiles>.*||' )" = '<godfiles total="2" shown="2" capped="0"><f p="lib/app/helper.rb" afferent="3"/><f p="lib/user.rb" afferent="1"/>' ] \
    && ok 'structure: godfiles = the two load-time importees (helper.rb ×3, lib/user.rb ×1); App::User with its 4 lazy importers is not a god file' \
    || no "structure: godfiles: $( printf '%s' "$DEPS" | grep -oE '<godfiles [^>]*>.*</godfiles>' | sed 's|</godfiles>.*||' )"
printf '%s' "$DEPS" | grep -q '<f p="lib/app/user.rb"' \
    && no "structure: lib/app/user.rb has a --deps row — its importers are all lazy, so it has no load-time afferent and no directive of its own: $( frow lib/app/user.rb )" \
    || ok 'structure: lib/app/user.rb has NO --deps row (no directive, no load-time importer) — and --impact still names its 4 lazy importers (arm above)'
[ "$( frow lib/app/two_scopes.rb )" = '<f p="lib/app/two_scopes.rb" includes="2" lazy_edges="2" afferent="0" instab="0.00" transitive="1">' ] \
    && ok 'structure: two_scopes.rb — 2 directives, both resolved, both lazy: lazy_edges="2", no structural edge (transitive 1, instab 0.00)' \
    || no "structure: two_scopes.rb row: $( frow lib/app/two_scopes.rb )"
[ "$( frow lib/app/report.rb )" = '<f p="lib/app/report.rb" includes="5" lazy_edges="2" afferent="0" instab="1.00" transitive="2">' ] \
    && ok 'structure: report.rb — Helper is load-time (transitive 2), User + App::Mailer are lazy (lazy_edges 2), Time/::Time unresolved (neither)' \
    || no "structure: report.rb row: $( frow lib/app/report.rb )"
[ "$( frow lib/app/lazy_levels.rb )" = '<f p="lib/app/lazy_levels.rb" includes="4" lazy_edges="3" afferent="0" instab="1.00" transitive="2">' ] \
    && ok 'structure: lazy_levels.rb — the class-body Helper is the one load-time edge; lambda, singleton method and do-block are 3 lazy edges' \
    || no "structure: lazy_levels.rb row: $( frow lib/app/lazy_levels.rb )"
[ "$( frow lib/script.rb )" = '<f p="lib/script.rb" includes="1" afferent="0" instab="1.00" transitive="2">' ] \
    && ok 'structure: script.rb — a file-level receiver is a load-time edge: transitive 2, no lazy_edges= attribute' \
    || no "structure: script.rb row: $( frow lib/script.rb )"
[ "$( frow lib/app/eager_after_lazy.rb )" = '<f p="lib/app/eager_after_lazy.rb" includes="1" afferent="0" instab="1.00" transitive="2">' ] \
    && ok 'structure: ORDER-BLIND — eager_after_lazy.rb'"'"'s method-body `Helper.fmt` comes first in source, the class-body one second: one directive, load-time (transitive 2, no lazy_edges=)' \
    || no "structure: eager_after_lazy.rb row (a lazy first occurrence must not hide the load-time site below it): $( frow lib/app/eager_after_lazy.rb )"
[ "$( frow lib/app/dynamic.rb )" = '<f p="lib/app/dynamic.rb" includes="1" afferent="0" instab="0.00" transitive="1">' ] \
    && ok 'structure: LAZY ≠ UNRESOLVED — dynamic.rb'"'"'s `Object` row resolves to nothing: no lazy_edges= attribute (two_scopes.rb, same instab, carries lazy_edges="2")' \
    || no "structure: dynamic.rb row: $( frow lib/app/dynamic.rb )"

# ── 5. DEEP CHAIN: the constant-chain check must not recurse per segment ─────────────────────────────
mkdir -p "$TMP/deep/lib"
python3 -c 'import sys; open(sys.argv[1], "w").write("class Deep\n  " + "::".join(["A"] * 150000) + ".call\nend\n")' "$TMP/deep/lib/deep.rb" 2>/dev/null \
    || awk 'BEGIN { printf "class Deep\n  A"; for( i = 1; i < 150000; ++i ) { printf "::A" }; printf ".call\nend\n" }' >"$TMP/deep/lib/deep.rb"
"$BIN" "$TMP/deep" --deps --limit=10 --no-cache >"$TMP/deepout" 2>/dev/null
deepRc=$?
[ "$deepRc" -eq 0 ] && grep -q '<f p="lib/deep.rb" includes="1"' "$TMP/deepout" \
    && ok 'deep chain: a 150 000-segment constant receiver is ONE directive and the run exits 0 (a recursive chain check overflowed a worker stack at ~5000)' \
    || no "deep chain: exit=$deepRc row=$( grep -oE '<f p="lib/deep.rb"[^>]*>' "$TMP/deepout" | head -1 )"

# ── 6. root spelling, determinism, warm == cold, well-formed XML ─────────────────────────────────────
( cd "$FIX" && "$BIN" . --deps --limit=100000 --no-cache 2>/dev/null ) | sed 's/ root="[^"]*"//' >"$TMP/dots"
"$BIN" "$FIX" --deps --limit=100000 --no-cache 2>/dev/null | sed 's/ root="[^"]*"//' >"$TMP/abs"
cmp -s "$TMP/dots" "$TMP/abs" \
    && ok 'root spelling: a relative and an absolute crawl root resolve identically' \
    || { no 'root spelling: the two spellings disagree'; diff "$TMP/dots" "$TMP/abs" | head -4; }
"$BIN" "$FIX" --deps --limit=100000 --no-cache >"$TMP/d2" 2>/dev/null
if cmp -s "$TMP/deps" "$TMP/d2"; then ok "deterministic (two --no-cache runs identical)"; else no "non-deterministic"; fi
"$BIN" "$FIX" --deps --limit=100000 --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --deps --limit=100000 --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
if cmp -s "$TMP/cold" "$TMP/warm"; then ok "warm == cold (receiver directives survive the cache round-trip)"; else no "warm != cold"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/deps" 2>/dev/null; then ok "xml well-formed"; else no "xml malformed"; fi
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
