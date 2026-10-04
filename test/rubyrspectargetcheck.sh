#!/usr/bin/env bash
# rubyrspectargetcheck.sh — gate for a call on one of RSpec's own targets. `expect( x ).to eq( 1 )`, `expect { … }.to`,
# `is_expected.to`, `allow( x ).to receive( … )`: inside an example group the receiver of `to` is the value RSpec's
# `expect`/`allow` returns — an RSpec::Expectations::ValueExpectationTarget (a BlockExpectationTarget for a block), an
# RSpec::Mocks::AllowanceTarget, an AnyInstance…Target — and its `to`/`not_to`/`to_not` are RSpec's. Before this round the
# receiver was untyped, so the call bound by NAME alone: on a Rails app whose only `def to` is a presenter's, every one of
# its 13,740 expectations bound to that presenter, which then ranked first in the default map.
# A matcher's chain is RSpec's too (parser version 136): `receive( :m ).with( 1 )`, the `to` of `change { }.from( 1 ).to( 2 )`
# and every later link (`.and_return( 2 )`) are called on the matcher the receiver-less builder at the chain's root returns.
# THE RULE (ingest_binds.h rubyValueType; model.h kRspecTargets; graph.h RubyTypedReceivers): inside an example group's
# block — a describe/context or a shared group, a `def` in one included — a receiver-less `expect`, `allow`,
# `expect_any_instance_of`, `allow_any_instance_of` call and a bare `is_expected` build a value of that RSpec class, typed
# like any built receiver (written in place or held by a local); so do the matcher builders `receive`, `have_received`,
# `change`, `raise_error`, `output`, `be_within` and their kin, and a call on a chain rooted at one of them is typed as
# the root (ingest_binds.h rubyMatcherChainType). A call on it answers from the class's lookup: when the
# tree never opens the class, only a reopened Object/Kernel/BasicObject can answer, and otherwise the call is refused as
# external (the method Ruby runs is RSpec's); a tree that opens the class (RSpec's own, or a patch) answers from it as from
# any in-tree class.
#
# Stated floors, each pinned below:
#   (a) outside an example group — a helper module in spec/support that a `config.include` mixes in — the call binds by
#       name as before.
#   (b) a tree that defines a method named `expect` (or `allow`, `change`, …) where an example group's self can reach it — a
#       top-level def, a reopened Object's, a def inside a group's block, a module's in test code (what a `config.include`
#       mixes in) — types nothing from that name: the call binds by name as before. A class's method is not in a group's
#       lookup, nor an application module's: a migration's `def change`, or its mixin's, shadows nothing; an application
#       module a `config.include` does mix in is not read as one.
#   (c) a chain is read through at most 8 links from its builder: a later link binds by name as before.
#   (d) an `expect` with a receiver (`helper.expect( 1 )`) is not RSpec's builder: untyped.
#
# Usage:  test/rubyrspectargetcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyrspectargetcheck.sh
# Exits non-zero on any failure. Self-contained via mktemp.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
FIX="$DIR/fix"
for d in app/presenters app/models app/mailers lib/core_ext spec/models spec/support db/migrate
do
    mkdir -p "$FIX/$d"
done

# the app's only `def to` / `not_to` / `to_not` / `with` — the namesakes every expectation bound to by name
cat > "$FIX/app/presenters/link_presenter.rb" <<'RUBY'
class LinkPresenter
  def to
    :presenter
  end

  def not_to
    :presenter
  end

  def to_not
    :presenter
  end

  def with
    :presenter
  end

  def and_return
    :presenter
  end

  def twice
    :presenter
  end
end
RUBY
# a class's `def change` — every Rails migration has one — and an application module's are no methods of an example
# group: they shadow no builder
cat > "$FIX/db/migrate/001_add_name.rb" <<'RUBY'
class AddName < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :name, :string
  end
end
RUBY
cat > "$FIX/db/migration_mixin.rb" <<'RUBY'
module MigrationMixin
  def change
    :mixin
  end
end
RUBY
cat > "$FIX/app/models/user.rb" <<'RUBY'
class User
  def activate!
    true
  end
end
RUBY
cat > "$FIX/app/mailers/mailer.rb" <<'RUBY'
class Mailer
  def address( email )
    email.to # @untyped
  end
end
RUBY
cat > "$FIX/lib/core_ext/object.rb" <<'RUBY'
class Object
  def to_widget
    :widget
  end
end
RUBY
cat > "$FIX/spec/support/helpers.rb" <<'RUBY'
module Helpers
  def check_one( x )
    expect( x ).to eq( 1 ) # @support
  end
end
RUBY
cat > "$FIX/spec/models/user_spec.rb" <<'RUBY'
RSpec.describe User do
  let( :user ) { User.new }

  it "value" do
    expect( user ).to eq( user ) # @expect_value
  end

  it "block" do
    expect { raise "x" }.to raise_error( RuntimeError ) # @expect_block
  end

  it "negated" do
    expect( user ).not_to be_nil # @not_to
    expect( user ).to_not be_nil # @to_not
  end

  it "mocks" do
    allow( user ).to receive( :activate! ) # @allow
    expect_any_instance_of( User ).to receive( :activate! ) # @any_expect
    allow_any_instance_of( User ).to receive( :activate! ) # @any_allow
  end

  it "local" do
    target = expect( user )
    target.to eq( user ) # @local
  end

  it { is_expected.to be_a( User ) } # @is_expected

  it "root" do
    expect( user ).to_widget # @root
  end

  context "nested" do
    def nested_helper
      expect( 1 ).to eq( 1 ) # @group_def
    end
  end

  shared_examples "shared" do
    it { expect( 1 ).to eq( 1 ) } # @shared
  end

  it "matcher chains" do
    expect( user ).to receive( :activate! ).with( 1 ) # @receive_with
    expect { 1 }.to change { 1 }.from( 1 ).to( 2 ) # @change_to
    allow( user ).to receive( :activate! ).with( 1 ).and_return( 2 ) # @chain_link
    expect( user ).to have_received( :activate! ).with( 1 ) # @have_received
    allow( user ).to receive( :activate! ).with( 1 ).with( 2 ).with( 3 ).with( 4 ).with( 5 ).with( 6 ).with( 7 ).with( 8 ).twice # @chain_floor
  end

  it "a receiver" do
    helper_object.expect( 1 ).to eq( 1 ) # @recv_expect
  end
end
RUBY

# the shadow tree: it defines `expect` itself, so `expect( 1 )` is the tree's Wrapper, not RSpec's target
SHADOW="$DIR/shadow"
mkdir -p "$SHADOW/lib" "$SHADOW/spec/support" "$SHADOW/spec/models"
cat > "$SHADOW/lib/wrapper.rb" <<'RUBY'
class Wrapper
  def initialize( v )
    @v = v
  end

  def to( matcher )
    :wrapped
  end
end
RUBY
cat > "$SHADOW/spec/support/shim.rb" <<'RUBY'
module Shim
  def expect( v )
    Wrapper.new( v )
  end
end
RUBY
cat > "$SHADOW/spec/models/thing_spec.rb" <<'RUBY'
RSpec.describe "thing" do
  it { expect( 1 ).to eq( 1 ) } # @shadow
end
RUBY

MAP="$DIR/a.xml"
"$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/map.err"
if [ $? -eq 0 ]; then ok "default map exits 0"; else no "default map exited non-zero: $( cat "$DIR/map.err" )"; fi
if [ -s "$DIR/map.err" ]; then no "unexpected stderr: $( head -3 "$DIR/map.err" )"; else ok "clean stderr"; fi
if command -v xmllint >/dev/null 2>&1
then
    if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi
fi

# The census (src/pincensus.h): one `C` row per call site the resolver decided or refused, so each arm reads ONE line.
census(){
    if ! "$BIN" "$1" --no-cache --pin-census="$DIR/census.tsv" >/dev/null 2>"$DIR/census.err"
    then
        no "--pin-census on $1 exited non-zero: $( head -3 "$DIR/census.err" )"
        return 2
    fi
    return 0
}
# line ROOT FILE MARK — the line number carrying `# @MARK` (empty when the marker is missing)
line(){
    grep -n "# @$3\$" "$1/$2" | head -1 | cut -d: -f1
}
# targets FILE LINE — every target the census names for a call on FILE:LINE, one per line
targets(){
    awk -F'\t' -v f="$1" -v l="$2" '$1 == "C" && $9 == l && index( $6, f "::" ) == 1 { n = split( $8, t, "|" ); for( i = 1; i <= n; ++i ) print t[ i ] }' \
        "$DIR/census.tsv"
}
# rows FILE LINE CALLEE — "mechanism<TAB>targets" of each CALLEE call the census records on FILE:LINE
rows(){
    awk -F'\t' -v f="$1" -v l="$2" -v c="$3" '$1 == "C" && $9 == l && $7 == c && index( $6, f "::" ) == 1 { print $2 "\t" $8 }' "$DIR/census.tsv"
}
# reaches SYM FILE MARK WHY [ROOT] — a call on the marked line resolves to SYM
reaches(){
    local n; n="$( line "${5:-$FIX}" "$2" "$3" )"
    [ -n "$n" ] || { no "fixture marker @$3 missing in $2"; return; }
    targets "$2" "$n" | grep -qF "::$1#" && ok "@$3 → $1 ($4)" \
        || no "@$3 ($2:$n) does not reach $1 ($4); it reaches: $( targets "$2" "$n" | tr '\n' ' ' )"
}
# refused CALLEE FILE MARK WHY — every CALLEE call on the marked line is refused as external: no target, mechanism external
refused(){
    local n r; n="$( line "$FIX" "$2" "$3" )"
    [ -n "$n" ] || { no "fixture marker @$3 missing in $2"; return; }
    r="$( rows "$2" "$n" "$1" )"
    if [ -n "$r" ] && ! printf '%s\n' "$r" | grep -qv "^external	\$"
    then
        ok "@$3 .$1 refused as external ($4)"
    else
        no "@$3 ($2:$n) .$1 is not refused ($4); census: $( printf '%s' "$r" | tr '\t\n' ' ;' )"
    fi
}

census "$FIX" || exit 1

U=spec/models/user_spec.rb

echo "=== a call on the target RSpec's builder returns is RSpec's ==="
refused to      $U expect_value "expect( v ) is a ValueExpectationTarget — its to is RSpec's, not LinkPresenter#to"
refused to      $U expect_block "expect { … } is a BlockExpectationTarget"
refused not_to  $U not_to       "not_to is the target's"
refused to_not  $U to_not       "to_not is the target's"
refused to      $U allow        "allow( v ) is an RSpec::Mocks::AllowanceTarget"
refused to      $U any_expect   "expect_any_instance_of( K ) is an AnyInstanceExpectationTarget"
refused to      $U any_allow    "allow_any_instance_of( K ) is an AnyInstanceAllowanceTarget"
refused to      $U local        "a local bound only to expect( v ) holds the target"
refused to      $U is_expected  "is_expected is expect( subject )"
refused to      $U group_def    "a def inside an example group runs in it"
refused to      $U shared       "a shared group's examples run in the including group"
reaches Object::to_widget $U root "a reopened Object answers on every instance, RSpec's targets included"

echo "=== a matcher's chain is RSpec's: each link is called on the matcher its root builder returns ==="
refused with       $U receive_with  "receive( :m ) is an RSpec::Mocks::Matchers::Receive — its with is RSpec's"
refused to         $U change_to     "change { }.from( 1 ) is a Change matcher's chain — its to is RSpec's (a migration's def change, and its mixin's, shadow nothing)"
refused and_return $U chain_link    "receive( … ).with( 1 ).and_return — two links from the builder"
refused with       $U have_received "have_received( :m ).with"

echo "=== floors: what is not RSpec's target, or not read as one ==="
reaches LinkPresenter::to    app/mailers/mailer.rb untyped "an untyped receiver outside a spec binds by name as before"
reaches LinkPresenter::to    spec/support/helpers.rb support "floor (a): a helper module outside a group binds by name as before"
reaches LinkPresenter::twice $U chain_floor  "floor (c): a link more than 8 from its builder binds by name as before"
reaches LinkPresenter::to    $U recv_expect  "floor (d): helper.expect( 1 ) is not RSpec's builder — binds by name"

census "$SHADOW" || exit 1
reaches Wrapper::to spec/models/thing_spec.rb shadow "floor (b): the tree defines expect — expect( 1 ) is its Wrapper, bound by name" "$SHADOW"

echo "=== determinism and warm == cold ==="
"$BIN" "$FIX" --no-cache >"$DIR/b.xml" 2>/dev/null
cmp -s "$MAP" "$DIR/b.xml" && ok "byte-identical across two --no-cache runs" \
    || no "output differs across runs"
if ! "$BIN" "$FIX" --cache="$DIR/c.bin" >"$DIR/cold.xml" 2>"$DIR/cold.err"
then
    no "the cold cache run exited non-zero: $( head -3 "$DIR/cold.err" )"
fi
if ! "$BIN" "$FIX" --cache="$DIR/c.bin" >"$DIR/warm.xml" 2>"$DIR/warm.err"
then
    no "the warm cache run exited non-zero: $( head -3 "$DIR/warm.err" )"
fi
cmp -s "$DIR/cold.xml" "$DIR/warm.xml" && ok "warm run == cold run" \
    || no "the warm cache disagrees with the cold run"

echo "=== mutation: the tree opens RSpec's target class → it answers from the tree ==="
MUT="$DIR/mut"; cp -R "$FIX" "$MUT"
cat > "$MUT/spec/support/target_patch.rb" <<'RUBY'
module RSpec
  module Expectations
    class ValueExpectationTarget
      def to_widget
        :patched
      end
    end
  end
end
RUBY
n="$( line "$MUT" "$U" root )"
m="$( line "$MUT" "$U" expect_value )"
if census "$MUT"
then
    targets "$U" "$n" | grep -qF "::ValueExpectationTarget::to_widget#" && ok "mutation: the patched target's to_widget answers expect( v ).to_widget" \
        || no "mutation: with ValueExpectationTarget opened, expect( v ).to_widget does not reach it; it reaches: $( targets "$U" "$n" | tr '\n' ' ' )"
    targets "$U" "$m" | grep -qF "::LinkPresenter::to#" && no "mutation: expect( v ).to reaches LinkPresenter#to with the target opened" \
        || ok "mutation: expect( v ).to still reaches no namesake — the opened class defines no to"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
