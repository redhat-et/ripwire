#!/usr/bin/env bash
# rubygroupselfcheck.sh — gate for the self of an RSpec example group: a receiver-less call inside `RSpec.describe … do`
# is sent to the example (or, at the group's own body, the group class), and Ruby answers it from THAT object's lookup.
# Before this round a spec file's top level had no self at all (graph.h RubyTopSelf leaves a `.rb` file's top level
# alone), so the call fell to the name tier and bound whichever in-tree method shared its name: FactoryBot's `create`
# an application service's `create`, rspec-mocks' `allow` a module's `def self.allow`, a nested `describe` a service's
# `describe` — 12,460 sites on one Rails application (docs/research/ruby-roadmap.md §2.1).
# THE RULE (ingest_ruby.h captureRubyExampleGroups; graph.h RubyTopSelf; parser version 272 → see kParserVer):
#   * inside an example group's block — describe/context/feature/example_group and their x-/f- spellings, the shared
#     groups, and an `RSpec.configure` block, whose hooks run on examples — self is the group's: a receiver-less call
#     reaches a def written in test code with no class around it (a group's own method, a spec/support top-level def), a
#     reopened Object, Kernel or BasicObject, a method of a module the groups mix in (`config.include M`, `include M`
#     written in a group, and the helper a helper spec describes — rspec-rails mixes it in) and of that module's ancestors,
#     and any candidate whose owner the tree does not define;
#   * any other in-tree class's or module's method is no method of the example, and neither is a def written inside
#     ANOTHER file's group (that group's own) nor another language's definition: it leaves the call's set, and a call left with none is refused as external —
#     the method Ruby runs is RSpec's, FactoryBot's, Capybara's, a `let`'s, outside the index;
#   * a block that hands self to another object (`instance_eval`, `instance_exec`, `class_eval`, `class_exec`,
#     `module_eval`, `module_exec`, `Class.new`, `Module.new`, `Struct.new`, `Data.define`) is left as before, and so is a
#     class or module written inside a group (its own self is RubySelfReach's).
#
# Stated floors, each pinned below:
#   (a) a spec file's top level OUTSIDE every group is left as before (its self is main; the name tier binds).
#   (b) a `FactoryBot.define` block is another self (FactoryBot's definition proxy answers every name); left as before.
#   (c) `config.include M, type: :request` mixes M into every group, not only request specs: the type filter is not read.
#
# Usage:  test/rubygroupselfcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubygroupselfcheck.sh
# Exits non-zero on any failure. Self-contained via mktemp.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

DIR="$( mktemp -d )" || { echo "cannot create a temporary directory — the fixture has nowhere to go"; exit 2; }
trap 'rm -rf "$DIR"' EXIT
FIX="$DIR/fix"
for d in app/models app/services app/helpers app/javascript config/initializers lib spec/support spec/requests spec/models spec/factories spec/helpers spec/views
do
    mkdir -p "$FIX/$d"
done

# An application's methods that share a name with FactoryBot's and RSpec's DSL: the ONE in-tree definition of each name.
cat > "$FIX/app/services/abacus.rb" <<'RUBY'
class Abacus
  def create
    true
  end

  def build
    true
  end

  def describe
    "abacus"
  end
end
RUBY

# the application's JavaScript shares FactoryBot's names too: no Ruby lookup reaches a JavaScript function, so the call is
# refused as external — never `unresolved=` because the only namesake left after the cut was another language's
cat > "$FIX/app/javascript/widgets.js" <<'JS'
export function create( attrs ) { return attrs; }
export function describe( w ) { return String( w ); }
JS

cat > "$FIX/config/initializers/audit_gate.rb" <<'RUBY'
module AuditGate
  def self.allow( reason: )
    yield
  end
end
RUBY

cat > "$FIX/app/models/widget.rb" <<'RUBY'
class Widget
  def spin
    true
  end

  def spin_count
    1
  end
end
RUBY

cat > "$FIX/lib/site.rb" <<'RUBY'
class Object
  def site_name
    "site"
  end
end
RUBY

cat > "$FIX/spec/rails_helper.rb" <<'RUBY'
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include NetHelper, type: :request
  config.before do
    reset_clock # @configure_hook
  end
end
RUBY

cat > "$FIX/spec/support/net_helper.rb" <<'RUBY'
module NetHelper
  include JsonHelper

  def wire_response
    {}
  end
end
RUBY

cat > "$FIX/spec/support/json_helper.rb" <<'RUBY'
module JsonHelper
  def parsed_body
    {}
  end
end
RUBY

cat > "$FIX/spec/support/money_helper.rb" <<'RUBY'
module MoneyHelper
  def cents
    100
  end
end
RUBY

cat > "$FIX/spec/support/clock.rb" <<'RUBY'
def reset_clock
  true
end
RUBY

cat > "$FIX/spec/support/spinning.rb" <<'RUBY'
RSpec.shared_examples "a spinner" do
  it "spins" do
    charge # @shared
  end
end
RUBY

# rspec-rails mixes the helper module a helper spec describes into its groups: by location (spec/helpers/, under
# infer_spec_type_from_file_location!) or by `type: :helper`
cat > "$FIX/app/helpers/badge_helper.rb" <<'RUBY'
module BadgeHelper
  def badge_for( user )
    user.to_s
  end
end
RUBY

cat > "$FIX/app/helpers/title_helper.rb" <<'RUBY'
module TitleHelper
  def title_for( page )
    page.to_s
  end
end
RUBY

cat > "$FIX/spec/helpers/badge_helper_spec.rb" <<'RUBY'
RSpec.describe BadgeHelper do
  it "badges" do
    badge_for( 1 ) # @helper_by_location
  end
end
RUBY

cat > "$FIX/spec/views/title_helper_spec.rb" <<'RUBY'
RSpec.describe TitleHelper, type: :helper do
  it "titles" do
    title_for( 1 ) # @helper_by_type
  end
end
RUBY

# a shared context's defs reach every group that includes it: no other file's group method, a shared one
cat > "$FIX/spec/support/with_clerk.rb" <<'RUBY'
RSpec.shared_context "with clerk" do
  def clerk_headers
    {}
  end
end
RUBY

# Every name the positive arms reach, defined once more where no example's lookup goes: a Decoy target is a wrong edge.
cat > "$FIX/lib/decoy.rb" <<'RUBY'
class Decoy
  def local_helper; end
  def wire_response; end
  def parsed_body; end
  def reset_clock; end
  def site_name; end
  def cents; end
  def charge; end
  def badge_for( u ); end
  def title_for( p ); end
end
RUBY

REQ=spec/requests/widgets_spec.rb
cat > "$FIX/$REQ" <<'RUBY'
require "rails_helper"

RSpec.describe Widget, type: :request do
  let( :widget ) { create( :widget ) } # @let_create

  def local_helper
    1
  end

  before do
    allow( Widget ).to receive( :new ) # @allow
  end

  describe "nested" do # @nested_describe
    it "works" do
      local_helper # @group_def
      wire_response # @included
      parsed_body # @included_ancestor
      reset_clock # @top_def
      site_name # @root
      charge # @foreign
      build( :widget ) # @build
      model_only_helper # @other_group_def
      clerk_headers # @shared_def
    end
  end

  describe "money" do
    include MoneyHelper

    it "counts" do
      cents # @group_include
    end
  end

  it "rebinds self" do
    Widget.new.instance_eval do
      spin # @instance_eval
    end
  end
end

create( :outside ) # @outside_group
RUBY

MODEL=spec/models/widget_spec.rb
cat > "$FIX/$MODEL" <<'RUBY'
RSpec.describe Widget do
  def model_only_helper
    1
  end

  def clerk_headers
    {}
  end

  it "reads the request helper" do
    wire_response # @type_filter
  end
end
RUBY

FACT=spec/factories/widgets.rb
cat > "$FIX/$FACT" <<'RUBY'
FactoryBot.define do
  factory :widget do
    spin_count { 2 } # @factory
  end
end
RUBY

echo "=== the map is well-formed ==="
MAP="$DIR/a.xml"
if ! "$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/a.err"
then
    no "the default map exited non-zero: $( head -3 "$DIR/a.err" )"
fi
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
# line FILE MARK — the line number carrying `# @MARK` (empty when the marker is missing)
line(){
    grep -n "# @$2\$" "$FIX/$1" | head -1 | cut -d: -f1
}
# rows FILE LINE CALLEE — "mechanism<TAB>targets" of each CALLEE call the census records on FILE:LINE
rows(){
    awk -F'\t' -v f="$1" -v l="$2" -v c="$3" '$1 == "C" && $9 == l && $7 == c && index( $6, f "::" ) == 1 { print $2 "\t" $8 }' "$DIR/census.tsv"
}
# reaches CALLEE TARGET FILE MARK WHY — the CALLEE call on the marked line resolves to TARGET (an id fragment) ALONE: one
# row, one target, no Decoy
reaches(){
    local n r; n="$( line "$3" "$4" )"
    [ -n "$n" ] || { no "fixture marker @$4 missing in $3"; return; }
    r="$( rows "$3" "$n" "$1" )"
    if [ -n "$r" ] && [ "$( printf '%s\n' "$r" | wc -l )" -eq 1 ] && printf '%s\n' "$r" | grep -qF "$2" \
        && ! printf '%s\n' "$r" | grep -qF "|" && ! printf '%s\n' "$r" | grep -qF "::Decoy::"
    then
        ok "@$4 :$1 → $2 ($5)"
    else
        no "@$4 ($3:$n) :$1 does not reach $2 alone ($5); census: $( printf '%s' "$r" | tr '\t\n' ' ;' )"
    fi
}
# refused CALLEE FILE MARK WHY — the CALLEE call on the marked line is recorded, and refused as external
refused(){
    local n r; n="$( line "$2" "$3" )"
    [ -n "$n" ] || { no "fixture marker @$3 missing in $2"; return; }
    r="$( rows "$2" "$n" "$1" )"
    if [ -n "$r" ] && ! printf '%s\n' "$r" | grep -qv "^external	\$"
    then
        ok "@$3 :$1 refused as external ($4)"
    else
        no "@$3 ($2:$n) :$1 is not refused ($4); census: $( printf '%s' "$r" | tr '\t\n' ' ;' )"
    fi
}

census "$FIX" || exit 1

echo "=== FactoryBot's and RSpec's DSL is no application method ==="
refused create         $REQ let_create      "FactoryBot's create (config.include FactoryBot::Syntax::Methods), not Abacus#create"
refused allow          $REQ allow           "rspec-mocks' allow, not AuditGate's singleton allow"
refused describe       $REQ nested_describe "a nested group is RSpec's describe, not Abacus#describe"
refused build          $REQ build           "FactoryBot's build, not Abacus#build"
refused charge         $REQ foreign         "an in-tree class's method is no method of the example"
refused charge         spec/support/spinning.rb shared "inside a shared group, too"
refused model_only_helper $REQ other_group_def "a def inside ANOTHER file's group is that group's method, not this one's"

echo "=== what an example's lookup does reach ==="
reaches local_helper   "widgets_spec.rb::local_helper#"   $REQ group_def         "a def written in the group: the group's own method"
reaches wire_response  "NetHelper::wire_response#"        $REQ included          "config.include NetHelper mixes it into the groups"
reaches parsed_body    "JsonHelper::parsed_body#"         $REQ included_ancestor "an ancestor of an included module"
reaches reset_clock    "clock.rb::reset_clock#"           $REQ top_def           "a top-level def in spec/support: a method of Object"
reaches reset_clock    "clock.rb::reset_clock#"           spec/rails_helper.rb configure_hook "a hook in RSpec.configure runs on the example"
reaches site_name      "Object::site_name#"               $REQ root              "a reopened Object answers every self"
reaches clerk_headers  "with_clerk.rb::clerk_headers#"    $REQ shared_def        "a shared context's def: include_context brings it into any group"
reaches badge_for      "BadgeHelper::badge_for#"          spec/helpers/badge_helper_spec.rb helper_by_location "a helper spec (spec/helpers/) mixes in the module it describes"
reaches title_for      "TitleHelper::title_for#"          spec/views/title_helper_spec.rb   helper_by_type     "so does one that says type: :helper"
reaches cents          "MoneyHelper::cents#"              $REQ group_include     "include MoneyHelper written in a group"
reaches spin           "Widget::spin#"                    $REQ instance_eval     "instance_eval hands self to the receiver: left as before"

echo "=== stated floors ==="
pinned(){
    local n r; n="$( line "$2" "$3" )"
    r="$( rows "$2" "$n" "$1" )"
    printf '%s\n' "$r" | grep -qF "$4" && ok "floor ($5) pinned: @$3 :$1 → $4" \
        || no "floor ($5) moved: @$3 ($2:$n) :$1 no longer binds $4 — flip this arm; census: $( printf '%s' "$r" | tr '\t\n' ' ;' )"
}
pinned create        $REQ   outside_group "Abacus::create#"          "a: a spec file's top level outside every group"
pinned spin_count    $FACT  factory       "Widget::spin_count#"      "b: a FactoryBot.define block is another self"
pinned wire_response $MODEL type_filter   "NetHelper::wire_response#" "c: config.include's type: filter is not read"

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
cmp -s "$DIR/cold.xml" "$DIR/warm.xml" && cmp -s "$MAP" "$DIR/cold.xml" && ok "warm run == cold run == --no-cache run" \
    || no "the cache disagrees with the --no-cache run"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
