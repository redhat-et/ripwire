#!/usr/bin/env bash
# rubyargcheck.sh — parser version 93 gate: a Ruby CONSTANT ARGUMENT (`raise Errors::Boom`, `validates_with
# Validator`, `delegate :x, to: Helper`, `obj.is_a?(User)`, `super(Validator)`, `yield User`) and a RESCUE CLASS
# (`rescue Errors::Boom => e`) are dependency directives — round three of the Ruby constant work, on the same
# corpus-own index as round one (superclass, mixins, autoload; test/rubyconstcheck.sh) and round two (constant
# receivers; test/rubyrecvcheck.sh), which pinned exactly these two positions as its DISCLOSED FLOOR.
#
# Ruby's own rule is that EVALUATING a constant is what makes the autoloader load its file, and a receiver is
# only one of the places a constant is evaluated. `raise Errors::Boom` loads errors.rb the first time that
# line runs; `validates_with Validator` at class-body level loads validator.rb when the class body runs — at
# load. Round two's floor arm (`expect Boom ''` in rubyrecvcheck) said so and inverts in the same commit.
#
# THE RULE, in six decisions this gate pins (each stated, none asked):
#   1. WHAT is an argument directive: a constant chain (`Name`, `A::B`, `::A::B` — rubyIsConstantChain, the same
#      test a receiver passes) that is a DIRECT positional child of an `argument_list`, or the VALUE of a keyword
#      `pair` directly in that list. An argument_list is the grammar's one node for the arguments of a `call`
#      (with or without parens: `raise X, "m"` and `raise(X)` alike), a `super(...)` and a `yield ...`, so all
#      three carry directives by construction rather than by three rules. Spelled AS WRITTEN, like a receiver.
#   2. WHAT is a rescue directive: every constant chain in a `rescue` clause's exception list (`rescue A, B => e`).
#      A bare `rescue => e` names no class and is nothing.
#   3. NOT an argument directive: the argument list of `include`/`extend`/`prepend`/`autoload`. Those are round
#      one's declarative directives, one record per statement, and a second read of the same list would double
#      every mixin in the corpus. Pinned by mixin.rb: `include Helper` + `extend Validator, User` = 3 records.
#   4. DEDUPE shares round two's key — (file, innermost open, written name) — and its record: a `raise
#      Errors::Boom`, a `rescue Errors::Boom` and an `Errors::Boom.new` in one nesting are ONE directive, the
#      first occurrence in source order carrying the byte. Zeitwerk loads a constant once per process.
#   5. LAZY: an argument is lazy inside a closure (method, singleton method, lambda, block, do-block — round
#      two's kRubyClosureContainers) and load-time at class-body or file level, exactly like a receiver. A RESCUE
#      class is lazy ALWAYS, closure or not: Ruby evaluates a rescue clause's exception list only when an
#      exception is being matched against it — `class X; begin; 1; rescue Nope; end; end` raises nothing, while
#      `raise "a"` inside that begin raises NameError for Nope (measured on ruby 4.0.6). So a class-body rescue
#      is a use, not a load-time dependency (rescue_at_load.rb). The AND over occurrences (parser version 86)
#      still applies: one load-time site of the same written name makes the directive load-time (mixed.rb).
#   6. RESOLUTION is round one's, unchanged — Module.nesting innermost-first then Object, `::` absolute, a
#      wrapper defines nothing, an out-of-tree name is shown and edges nowhere. The STRUCTURE vs USE cut is
#      round two's, unchanged: lazy pairs are in --impact's importer tier and the rows, not in ccd/godfiles.
#
#   7. NOT IMPORT EVIDENCE (PR #139 review; Include::isValueUse, kCacheVersion 21). A value-position constant is a
#      dependency of the FILE — --deps, --impact's importer tier, the lazy-pair count all keep it — but it says
#      nothing about the receiver of a bare call beside it: `notify(Dev::Config)` does not make `record` a
#      Dev::Config. Left in buildGraph's include narrow it did exactly that: on discourse 1,017 call sites newly
#      bound or narrowed, 19 of 20 sampled wrong. buildGraph's fileIncludes now skips value-use records
#      (buildPreciseIncludeAdjWithContext's forCallNarrow); every other consumer reads them as before. The bit is
#      the AND over occurrences like the lazy bit: one receiver occurrence of the same name keeps the record as
#      import evidence. Fixture test/rubyargnarrowfix (the review's repro): two `update!` definitions in different
#      directories, a caller in a third directory that passes `Dev::Config` as an argument and then calls
#      `record.update!`. main declines that call (two global candidates, no evidence); the pre-fix branch bound it
#      to Config#update!; the branch declines it again, and dev/config.rb keeps its importer.
#
# DISCLOSED FLOOR of this round (floor.rb, pinned to yield NOTHING): a constant in any OTHER value position —
# a `when` pattern (Ruby evaluates it eagerly; the next round's first candidate), an array or hash-literal
# element, a splat, an assignment's right-hand side, string interpolation, a binary operand. Each is an
# evaluation Ruby performs and this round does not read; none is a receiver, an argument or a rescue class.
#
# Fixture test/rubyargfix (crawl root = the fixture; 19 .rb files under lib/):
#   lib/app/service.rb        Validator (class body, arg), Helper (pair value), Errors::Boom (raise ×2 + rescue ×2, deduped),
#                             User (is_a? arg + Mailer.deliver arg, deduped), Mailer (receiver), ::App::Errors::Boom (own
#                             spelling), Errors::Bust (rescue list) → 7 rows
#   lib/app/rescue_at_load.rb `Helper.fmt` at class body (load-time) + `rescue Errors::Bust` at class body (STILL lazy)
#   lib/app/mixed.rb          `rescue Errors::Bust` in a method, then `Errors::Bust.new` at class body → ONE directive, load-time
#   lib/app/super_yield.rb    `< Helper` (round one), `super(Validator)`, `yield User` → 3 rows, the last two lazy
#   lib/app/mixin.rb          `include Helper` / `extend Validator, User` → 3 rows, none doubled (mutation control)
#   lib/app/nested.rb         `wrap(step(Validator))` — a nested call's argument; `log(Helper.fmt(2))` — a receiver, not an arg
#   lib/app/floor.rb          every floor position above → NO directive, NO row
#   lib/app/dynamic.rb        identifier / string / `repo::Finder` / `self.class` arguments, bare rescue, identifier rescue → nothing
#   lib/script.rb             no module: `raise App::Errors::Boom if …` at file level → load-time, via Object; `ARGV` a shown receiver
#   lib/app/admin/audit.rb    `raise Errors::Boom` inside App::Admin → App::Admin::Errors::Boom (LEXICAL), not App::Errors::Boom
#   lib/user.rb, lib/decoy/user.rb   two more `User` classes nothing names (mutation controls)
#
# Usage:  test/rubyargcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyargcheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/rubyargfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/rubyargfix — fixture missing"; exit 2; }
echo "rubyargcheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --deps --limit=100000 --no-cache >"$TMP/deps" 2>/dev/null
DEPS="$( cat "$TMP/deps" )"
# a file's FULL row (the one carrying includes=), not its self-closing <godfiles> row; the directive rows of
# one file come out in source order, as one space-joined line
frow(){ printf '%s' "$DEPS" | grep -oE "<f p=\"$1\" includes=[^>]*>" | head -1; }
incs(){ printf '%s' "$DEPS" | grep -oE "<f p=\"$1\" includes=[^>]*>.*" | sed -E 's|</f>.*||' | grep -oE '<inc t="[^"]*"/>' | tr '\n' ' '; }

# ── 0. PRESENCE GUARD: the fixture spells every shape the arms below search for ─────────────────────
grep -q 'raise Errors::Boom, "bad"' "$FIX/lib/app/service.rb" && grep -q 'rescue Errors::Bust, Errors::Boom' "$FIX/lib/app/service.rb" \
    && grep -q 'to: Helper' "$FIX/lib/app/service.rb" && grep -q 'super(Validator)' "$FIX/lib/app/super_yield.rb" \
    && grep -q 'yield User' "$FIX/lib/app/super_yield.rb" && grep -q 'when Errors::Boom' "$FIX/lib/app/floor.rb" \
    && ok 'presence: the fixture spells the raise, rescue-list, keyword-pair, super, yield and when shapes the arms search for' \
    || no 'presence: a fixture shape the arms depend on is missing — the arms below would be searching for nothing'

# ── 1. CAPTURE + DEDUPE: what is an argument / rescue directive, as written, once per (file, nesting, name) ──
[ "$( incs lib/app/service.rb )" = '<inc t="Validator"/> <inc t="Helper"/> <inc t="Errors::Boom"/> <inc t="User"/> <inc t="Mailer"/> <inc t="::App::Errors::Boom"/> <inc t="Errors::Bust"/> ' ] \
    && ok 'capture: service.rb = Validator Helper Errors::Boom User Mailer ::App::Errors::Boom Errors::Bust — source order, AS WRITTEN, each once' \
    || no "capture: service.rb rows: $( incs lib/app/service.rb )"
printf '%s' "$DEPS" | grep -q '<f p="lib/app/service.rb" includes="7"' \
    && ok 'dedupe: service.rb counts 7 directives — `raise` ×2, `rescue` ×2 and the receiver-argument `User` collapse onto one record each' \
    || no "dedupe: service.rb directive count: $( frow lib/app/service.rb )"
[ "$( incs lib/app/super_yield.rb )" = '<inc t="Helper"/> <inc t="Validator"/> <inc t="User"/> ' ] \
    && ok 'capture: `super(Validator)` and `yield User` are arguments — the argument_list is the grammar'"'"'s one node for call, super and yield' \
    || no "capture: super_yield.rb rows: $( incs lib/app/super_yield.rb )"
[ "$( incs lib/app/nested.rb )" = '<inc t="Validator"/> <inc t="Helper"/> ' ] \
    && ok 'capture: a NESTED call'"'"'s argument (`wrap(step(Validator))`) is captured; `log(Helper.fmt(2))` is the receiver it always was' \
    || no "capture: nested.rb rows: $( incs lib/app/nested.rb )"
[ "$( incs lib/app/rescue_at_load.rb )" = '<inc t="Helper"/> <inc t="Errors::Bust"/> ' ] \
    && ok 'capture: a rescue class at class-body level is captured beside the class-body receiver' \
    || no "capture: rescue_at_load.rb rows: $( incs lib/app/rescue_at_load.rb )"
[ "$( incs lib/app/mixed.rb )" = '<inc t="Errors::Bust"/> ' ] \
    && ok 'dedupe: a rescue class and a receiver of the same written name in one nesting are ONE directive' \
    || no "dedupe: mixed.rb rows: $( incs lib/app/mixed.rb )"
[ "$( incs lib/script.rb )" = '<inc t="App::Errors::Boom"/> <inc t="ARGV"/> ' ] \
    && ok 'capture: a file-level argument with no module is captured; the `ARGV` receiver beside it is the shown row it was' \
    || no "capture: script.rb rows: $( incs lib/script.rb )"
[ "$( incs lib/app/mixin.rb )" = '<inc t="Helper"/> <inc t="Validator"/> <inc t="User"/> ' ] \
    && printf '%s' "$DEPS" | grep -q '<f p="lib/app/mixin.rb" includes="3"' \
    && ok 'mutation control: `include Helper` / `extend Validator, User` stay 3 round-one records — a mixin argument list is not read twice' \
    || no "mutation control: mixin.rb rows doubled or missing: $( frow lib/app/mixin.rb ) $( incs lib/app/mixin.rb )"
printf '%s' "$DEPS" | grep -q '<f p="lib/app/floor.rb"' \
    && no "floor: floor.rb has a --deps row — a floor position was captured: $( frow lib/app/floor.rb ) $( incs lib/app/floor.rb )" \
    || ok 'floor: when / array / hash literal / splat / assignment / interpolation / binary operand yield NOTHING — floor.rb has no row'
printf '%s' "$DEPS" | grep -q '<f p="lib/app/dynamic.rb"' \
    && no "mutation control: dynamic.rb has a --deps row — a non-constant argument or rescue was captured: $( incs lib/app/dynamic.rb )" \
    || ok 'mutation control: identifier / string / `repo::Finder` / `self.class` arguments and bare or identifier rescues yield NOTHING'

# ── 2. RESOLUTION + LAZY: --impact's importer tier (`<f via="import" p= lazy=>`, uncapped, path order) ──────
importers(){ "$BIN" "$FIX" --impact="$1" --no-cache 2>/dev/null | sed 's/<!--[^>]*-->//g' | grep -oE '<f via="import" p="[^"]*" lazy="[01]"/>' | tr '\n' ' '; }
expect(){ # expect SYM 'rows'  — exact importer set
    local got; got="$( importers "$1" )"
    if [ "$got" = "$2" ]; then
        ok "$3"
    else
        no "$3 — importers of $1: ${got:-<none>}"
    fi
}
# The importer tier is per FILE (the files that import a file defining SYM), so Boom and Bust — both in errors.rb —
# share one importer set; lazy= is per (importer, errors.rb) pair. floor.rb and admin/audit.rb name errors.rb nowhere.
expect lib/app/errors.rb:Boom \
    '<f via="import" p="lib/app/mixed.rb" lazy="0"/> <f via="import" p="lib/app/rescue_at_load.rb" lazy="1"/> <f via="import" p="lib/app/service.rb" lazy="1"/> <f via="import" p="lib/script.rb" lazy="0"/> ' \
    'resolve: errors.rb is reached by `raise`/`rescue` in a method (service, lazy="1"), a file-level `raise` (script, lazy="0") and the two Bust files; the floor and admin files name it nowhere'
expect lib/app/admin/errors.rb:Boom \
    '<f via="import" p="lib/app/admin/audit.rb" lazy="1"/> ' \
    'resolve: LEXICAL — `raise Errors::Boom` inside App::Admin lands on App::Admin::Errors::Boom'
expect Bust \
    '<f via="import" p="lib/app/mixed.rb" lazy="0"/> <f via="import" p="lib/app/rescue_at_load.rb" lazy="1"/> <f via="import" p="lib/app/service.rb" lazy="1"/> <f via="import" p="lib/script.rb" lazy="0"/> ' \
    'lazy: a RESCUE class is lazy even at class-body level (rescue_at_load lazy="1"); one load-time receiver of the same name makes the pair load-time (mixed lazy="0")'
expect Validator \
    '<f via="import" p="lib/app/mixin.rb" lazy="0"/> <f via="import" p="lib/app/nested.rb" lazy="1"/> <f via="import" p="lib/app/service.rb" lazy="0"/> <f via="import" p="lib/app/super_yield.rb" lazy="1"/> ' \
    'lazy: a class-body argument (`validates_with Validator`) is load-time; a method-body one (nested, super) is lazy'
expect Helper \
    '<f via="import" p="lib/app/mixin.rb" lazy="0"/> <f via="import" p="lib/app/nested.rb" lazy="1"/> <f via="import" p="lib/app/rescue_at_load.rb" lazy="0"/> <f via="import" p="lib/app/service.rb" lazy="0"/> <f via="import" p="lib/app/super_yield.rb" lazy="0"/> ' \
    'lazy: a keyword-pair VALUE at class-body level (`delegate :name, to: Helper`) is a load-time argument'
expect lib/app/user.rb:User \
    '<f via="import" p="lib/app/mixin.rb" lazy="0"/> <f via="import" p="lib/app/service.rb" lazy="1"/> <f via="import" p="lib/app/super_yield.rb" lazy="1"/> ' \
    'resolve: an argument of a receiver'"'"'d call (`record.is_a?(User)`) and of `yield` reach App::User; the top-level and decoy User are untouched'
expect Mailer '<f via="import" p="lib/app/service.rb" lazy="1"/> ' 'mutation control: Mailer is reached by its receiver only — the floor file'"'"'s `target = Mailer` and `Mailer || Helper` name it nowhere'
expect lib/user.rb:User '' 'mutation control: the top-level User has no importer — a file-level `App::Errors::Boom` does not fall back to a bare name'
expect lib/decoy/user.rb:User '' 'mutation control: Decoy::User (same basename as two other User files) has no importer'
expect lib/app.rb:App '' 'mutation control: `::App::Errors::Boom` and `App::Errors::Boom` are chains, not references to App — lib/app.rb receives nothing'

# ── 3. CAPABILITY ────────────────────────────────────────────────────────────────────────────────────
printf '%s' "$DEPS" | grep -q '<health files="19" dep_files="19"' \
    && ok 'capability: all 19 .rb files are dependency-capable' \
    || no "capability: health wrong: $( printf '%s' "$DEPS" | grep -oE '<health [^/]*/>' )"

# ── 4. STRUCTURE vs USE: a lazy edge is in --impact and the rows, not in the load-time structure ────
# Load-time pairs: service→validator, service→helper, rescue_at_load→helper, mixed→errors, super_yield→helper,
# mixin→helper, mixin→validator, mixin→app/user, script→errors. Cones (self included): service 3, mixin 4,
# rescue_at_load 2, mixed 2, super_yield 2, script 2, the other 13 files 1 each → ccd 28, acd 28/19 = 1.5.
# Lazy pairs (resolved, every site inside a closure or a rescue list): service→errors, service→user,
# service→mailer, rescue_at_load→errors, super_yield→validator, super_yield→user, nested→validator,
# nested→helper, admin/audit→admin/errors → lazy_edges 9.
printf '%s' "$DEPS" | grep -q '<health files="19" dep_files="19" ccd="28" acd="1.5" ' \
    && ok 'structure: ccd counts the 9 load-time pairs only — 28 over 19 files, acd 1.5' \
    || no "structure: health: $( printf '%s' "$DEPS" | grep -oE '<health [^/]*/>' )"
printf '%s' "$DEPS" | grep -qE '<health [^>]*lazy_edges="9" dep_langs=' \
    && ok 'structure: <health lazy_edges="9"> discloses the resolved pairs the structure leaves out' \
    || no "structure: lazy_edges= wrong: $( printf '%s' "$DEPS" | grep -oE '<health [^/]*/>' )"
printf '%s' "$DEPS" | grep -oE '<godfiles [^>]*>.*</godfiles>' | sed 's|</godfiles>.*||' | grep -q '^<godfiles total="4" shown="4" capped="0"><f p="lib/app/helper.rb" afferent="4"/>' \
    && ok 'structure: godfiles = the four load-time importees, helper.rb first with afferent 4 (service, rescue_at_load, super_yield, mixin)' \
    || no "structure: godfiles: $( printf '%s' "$DEPS" | grep -oE '<godfiles [^>]*>.*</godfiles>' | sed 's|</godfiles>.*||' )"
# lazy_edges= counts DISTINCT (file, target) pairs. service.rb's Errors::Boom, ::App::Errors::Boom and Errors::Bust all
# resolve to errors.rb with user.rb and mailer.rb resolved BETWEEN them in directive order — the shape under which the
# pre-93 count (a run-of-equal-ids shortcut over an adjacency that is in directive order, not sorted) read 4 for 3 pairs.
[ "$( frow lib/app/service.rb )" = '<f p="lib/app/service.rb" includes="7" lazy_edges="3" afferent="0" instab="1.00" transitive="3">' ] \
    && ok 'structure: service.rb — Validator and Helper are load-time (transitive 3); errors, user and mailer are 3 lazy pairs — three spellings onto errors.rb interleaved with two other files count ONE pair' \
    || no "structure: service.rb row: $( frow lib/app/service.rb )"
[ "$( frow lib/app/rescue_at_load.rb )" = '<f p="lib/app/rescue_at_load.rb" includes="2" lazy_edges="1" afferent="0" instab="1.00" transitive="2">' ] \
    && ok 'structure: rescue_at_load.rb — the class-body receiver is the one load-time edge; the class-body rescue is a lazy pair, not structure' \
    || no "structure: rescue_at_load.rb row: $( frow lib/app/rescue_at_load.rb )"
[ "$( frow lib/app/mixed.rb )" = '<f p="lib/app/mixed.rb" includes="1" afferent="0" instab="1.00" transitive="2">' ] \
    && ok 'structure: ORDER-BLIND — mixed.rb'"'"'s rescue comes first in source, the class-body receiver second: one directive, load-time (no lazy_edges=)' \
    || no "structure: mixed.rb row: $( frow lib/app/mixed.rb )"
[ "$( frow lib/app/super_yield.rb )" = '<f p="lib/app/super_yield.rb" includes="3" lazy_edges="2" afferent="0" instab="1.00" transitive="2">' ] \
    && ok 'structure: super_yield.rb — the superclass is the one load-time edge; super and yield arguments are 2 lazy pairs' \
    || no "structure: super_yield.rb row: $( frow lib/app/super_yield.rb )"
[ "$( frow lib/app/nested.rb )" = '<f p="lib/app/nested.rb" includes="2" lazy_edges="2" afferent="0" instab="0.00" transitive="1">' ] \
    && ok 'structure: nested.rb — both directives inside a method: 2 lazy pairs, no structural edge' \
    || no "structure: nested.rb row: $( frow lib/app/nested.rb )"
[ "$( frow lib/script.rb )" = '<f p="lib/script.rb" includes="2" afferent="0" instab="1.00" transitive="2">' ] \
    && ok 'structure: script.rb — a file-level argument is a load-time edge (transitive 2); `ARGV` resolves nowhere' \
    || no "structure: script.rb row: $( frow lib/script.rb )"
[ "$( frow lib/app/admin/audit.rb )" = '<f p="lib/app/admin/audit.rb" includes="1" lazy_edges="1" afferent="0" instab="0.00" transitive="1">' ] \
    && ok 'structure: admin/audit.rb — one lazy pair onto admin/errors.rb' \
    || no "structure: admin/audit.rb row: $( frow lib/app/admin/audit.rb )"

# ── 5. NOT IMPORT EVIDENCE: the review's repro (test/rubyargnarrowfix) — a value-use record never narrows a call ──
NFIX="$ROOT/test/rubyargnarrowfix"
[ -d "$NFIX" ] || { echo "no test/rubyargnarrowfix — fixture missing"; exit 2; }
grep -q 'notify(Dev::Config)' "$NFIX/lib/app/notify/notifier.rb" && grep -q 'record.update!' "$NFIX/lib/app/notify/notifier.rb" \
    && ok 'presence: the narrow fixture spells the argument and the bare call the arms below depend on' \
    || no 'presence: the narrow fixture is missing its argument or its bare call'
callersTag(){ "$BIN" "$NFIX" --callers="$1" --no-cache --legend=compact 2>/dev/null | sed 's/<!--[^>]*-->//g' | grep -oE '<callers [^>]*>' | grep -oE ' count="[0-9]+"| declined_calls="[0-9]+"' | tr -d '\n'; }
[ "$( callersTag lib/app/dev/config.rb:update! )" = ' count="0" declined_calls="1"' ] \
    && ok 'narrow: `record.update!` beside `notify(Dev::Config)` does NOT bind to Config#update! — 0 callers, the call declined (the pre-fix branch reported 1 false caller)' \
    || no "narrow: Config#update! callers tag: $( callersTag lib/app/dev/config.rb:update! )"
[ "$( callersTag lib/app/ledger.rb:update! )" = ' count="0" declined_calls="1"' ] \
    && ok 'narrow: Ledger#update! has no caller either — two global candidates, no evidence, declined (as main)' \
    || no "narrow: Ledger#update! callers tag: $( callersTag lib/app/ledger.rb:update! )"
"$BIN" "$NFIX" --deps --limit=1000 --no-cache 2>/dev/null | grep -q '<f p="lib/app/notify/notifier.rb" includes="1" lazy_edges="1" afferent="0" instab="0.00" transitive="1"><inc t="Dev::Config"/>' \
    && ok 'narrow: the DEPENDENCY stays — notifier.rb still carries `Dev::Config` as a resolved lazy pair in --deps' \
    || no "narrow: notifier.rb --deps row lost the argument directive: $( "$BIN" "$NFIX" --deps --limit=1000 --no-cache 2>/dev/null | grep -oE '<f p="lib/app/notify/notifier.rb"[^>]*>' )"
"$BIN" "$NFIX" --impact=lib/app/dev/config.rb:Config --no-cache 2>/dev/null | sed 's/<!--[^>]*-->//g' | grep -q '<f via="import" p="lib/app/notify/notifier.rb" lazy="1"/>' \
    && ok 'narrow: --impact still names notifier.rb as a lazy importer of dev/config.rb — the value use is a use, not evidence' \
    || no 'narrow: --impact lost notifier.rb as an importer of dev/config.rb'

# ── 6. root spelling, determinism, warm == cold, well-formed XML ─────────────────────────────────────
( cd "$FIX" && "$BIN" . --deps --limit=100000 --no-cache 2>/dev/null ) | sed 's/ root="[^"]*"//' >"$TMP/dots"
"$BIN" "$FIX" --deps --limit=100000 --no-cache 2>/dev/null | sed 's/ root="[^"]*"//' >"$TMP/abs"
cmp -s "$TMP/dots" "$TMP/abs" \
    && ok 'root spelling: a relative and an absolute crawl root resolve identically' \
    || { no 'root spelling: the two spellings disagree'; diff "$TMP/dots" "$TMP/abs" | head -4; }
"$BIN" "$FIX" --deps --limit=100000 --no-cache >"$TMP/d2" 2>/dev/null
if cmp -s "$TMP/deps" "$TMP/d2"; then
    ok "deterministic (two --no-cache runs identical)"
else
    no "non-deterministic"
fi
"$BIN" "$FIX" --deps --limit=100000 --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --deps --limit=100000 --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
if cmp -s "$TMP/cold" "$TMP/warm"; then
    ok "warm == cold (argument and rescue directives survive the cache round-trip)"
else
    no "warm != cold"
fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/deps" 2>/dev/null; then
        ok "xml well-formed"
    else
        no "xml malformed"
    fi
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
