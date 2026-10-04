#!/usr/bin/env bash
# rubyreachcheck.sh — gate for what a Ruby BARE call can reach. A receiver-less `m` / `m( x )` inside a class or module
# is a send to self, and Ruby's method lookup decides which `def` answers it: the class, its included, extended and
# prepended modules, its superclass and theirs — and, because self may be any instance below the defining class, what
# a subclass or an includer adds (the template-method and concern idioms). A method of any OTHER class can never answer
# it; neither can an enclosing class's method (lexical nesting is constant lookup, not method lookup — `outer_helper`
# from inside `Outer::Inner` is a NoMethodError). Before this round three things broke that:
#   * mixins were no ancestor: `include Hub::SignalMixin` put nothing in the caller's base walk, so `signal`
#     split between the mixin's def and an unrelated `Hub#signal` in the same file, and a concern's call to its
#     includer's method (`audit_target`) declined;
#   * a class-BODY call ran against the enclosing namespace: `define_section :first` inside `Ns::Catalog` read Rule 1's
#     self as `Ns` and bound to `Ns.define_section`, not `Catalog.define_section`;
#   * a candidate no lookup can reach still bound by name: `render` in a controller to a component's `def render`,
#     `request` to the `Rating#request` of a class the controller merely names, `errors` in an ActiveModel form to a
#     stub's `def errors` — the method Ruby runs is the framework's, outside the tree.
# THE RULE (graph.h RubySelfReach, buildRubyCha; resolve.h rubyScopeMixinReferences): mixins are Ruby bases — one
# written inside a concern's `included do … end` too — scoped by Ruby's constant lookup like a superclass, and read
# only by a Ruby call to self, as is a concern's nested `module ClassMethods` (extended onto its includer); a class-body
# call's self is the class; and a bare call inside a class or module keeps only the candidates
# whose owner lies in that reach — the caller's ancestors, and the ancestors of every class below it — plus top-level
# defs (private methods of Object, reachable from anywhere). When none is left it declines (declined=): the method is
# outside the indexed tree, and the tool says so rather than naming a namesake.
#
# Stated floors, each pinned below where a fixture can show it:
#   (a) a class whose lookup can leave the class — a `SimpleDelegator`/`Delegator` or Draper decorator in reach, a
#       `method_missing` or a `delegate_missing_to` in reach — refuses nothing: its bare calls bind as before. A computed
#       superclass (`< DelegateClass( User )`) names no base, so its class is not seen as one.
#   (b) the delegation DSL — ActiveSupport's `delegate :a, to: :x` and `delegate_missing_to`, Forwardable's
#       `def_delegator(s)` — defines methods the tree does not index, so a class that writes it (or one whose reach holds
#       such a class) refuses nothing: its bare calls bind by name as before. Indexing the delegated names as methods
#       is a later round's (they must answer a call to self only — a receiver call of that name is no evidence).
#   (h) a top-level def is a private method of Object, and any ancestor answers before Object does: a class whose
#       reach holds an out-of-tree superclass or mixin (ActionController::Base) does not reach a top-level def.
#   (i) a mixin written inside a METHOD body runs when the method does (activerecord's `primary_key=` includes
#       CompositePrimaryKey; `attr_readonly` includes HasReadonlyAttributes) and is not read: calls that need it decline.
#   (j) Rails mixes every app/helpers module into one view object at run time; the tree says nothing of it, so a helper
#       module's bare call to another helper module's method declines.
#   (k) a core class's own ancestry is not modelled beyond every self's roots (BasicObject, Object, Kernel, and Module
#       and Class): a reopened `class Array` calling a reopened `module Enumerable`'s method declines.
#   (c) instance and class methods share one name space here, as everywhere in the graph: `extend M` and `include M`
#       both put M in reach, so an instance method's call to an extended module's method is admitted.
#   (d) inside `instance_eval`/`class_eval`/`instance_exec` blocks self changes; the rule reads the lexical self, as
#       Rule 1 always has, so a DSL block run against another in-tree object declines its calls there.
#   (e) reach is read by class NAME, as the inheritance graph is keyed: two classes sharing a name share their reach,
#       which refuses less, never more.
#   (f) a call outside any class — a script's top level, an RSpec example group's blocks — is untouched by the rule.
#   (g) `prepend M` is read as `include M`: a prepended override is not preferred over the class's own method.
#
# Usage:  test/rubyreachcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyreachcheck.sh
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
for d in lib/coord lib/app lib/ns lib/dsl lib/other lib/services lib/tmpl lib/impls lib/concerns lib/orders lib/util lib/deco \
         lib/models lib/ghost lib/forms lib/stubs app/models spec lib/feed lib/feed/shared lib/feed/catalog lib/sql lib/quoting \
         lib/attrs lib/core_ext
do
    mkdir -p "$FIX/$d"
done

cat > "$FIX/app/models/application_record.rb" <<'RUBY'
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
RUBY
cat > "$FIX/app/models/post.rb" <<'RUBY'
class Post < ApplicationRecord
  scope :published, -> { where(published: true) }
end
RUBY
cat > "$FIX/lib/app/ctl.rb" <<'RUBY'
class Ctl
  include Hub::SignalMixin

  def act
    signal(:acted)
  end
end
RUBY
cat > "$FIX/lib/app/outer.rb" <<'RUBY'
class Outer
  def outer_helper
    6
  end

  class Inner
    def m
      outer_helper
    end
  end
end
RUBY
cat > "$FIX/lib/app/pages_controller.rb" <<'RUBY'
class PagesController < ActionController::Base
  def show
    render
    request
    Rating.check
  end
end
RUBY
cat > "$FIX/lib/app/registry.rb" <<'RUBY'
class Registry
  extend RegistryDsl

  register :a
end
RUBY
cat > "$FIX/lib/app/uses_top.rb" <<'RUBY'
class UsesTop
  def m
    top_helper
  end
end
RUBY
cat > "$FIX/lib/concerns/auditable.rb" <<'RUBY'
module Auditable
  def audit
    audit_target
  end
end
RUBY
cat > "$FIX/lib/coord/hub.rb" <<'RUBY'
class Hub
  def signal(name)
    name
  end

  module SignalMixin
    def signal(name)
      name
    end
  end
end
RUBY
cat > "$FIX/lib/deco/user_deco.rb" <<'RUBY'
class UserDeco < SimpleDelegator
  def label
    display_name
  end
end
RUBY
cat > "$FIX/lib/dsl/registry_dsl.rb" <<'RUBY'
module RegistryDsl
  def register(name)
    name
  end
end
RUBY
cat > "$FIX/lib/forms/signup_form.rb" <<'RUBY'
class SignupForm
  include ActiveModel::Model

  def check
    errors
  end
end
RUBY
cat > "$FIX/lib/ghost/ghost.rb" <<'RUBY'
class Ghost
  def method_missing(name, *args)
    name
  end

  def respond_to_missing?(name, include_private = false)
    true
  end

  def m
    phantom
  end
end
RUBY
cat > "$FIX/lib/impls/impl.rb" <<'RUBY'
class Impl < BaseTemplate
  def hook
    1
  end
end
RUBY
cat > "$FIX/lib/models/user_model.rb" <<'RUBY'
class UserModel
  def display_name
    "u"
  end

  def phantom
    "p"
  end
end
RUBY
cat > "$FIX/lib/ns/catalog.rb" <<'RUBY'
module Ns
  def self.define_section(name)
    name
  end

  class Catalog
    def self.define_section(name)
      name
    end

    define_section :first
  end
end
RUBY
cat > "$FIX/lib/orders/order.rb" <<'RUBY'
class Order
  include Auditable

  def audit_target
    4
  end
end
RUBY
cat > "$FIX/lib/other/component.rb" <<'RUBY'
class Component
  def render
    "component"
  end
end
RUBY
cat > "$FIX/lib/other/robot.rb" <<'RUBY'
class Robot
  def register(name)
    name
  end
end
RUBY
cat > "$FIX/lib/other/spec_support.rb" <<'RUBY'
def spec_only_helper
  7
end
RUBY
cat > "$FIX/lib/other/unrelated.rb" <<'RUBY'
class Unrelated
  def hook
    2
  end

  def audit_target
    3
  end
end
RUBY
cat > "$FIX/lib/services/rating.rb" <<'RUBY'
class Rating
  def self.check
    true
  end

  def request
    nil
  end
end
RUBY
cat > "$FIX/lib/stubs/link_stub.rb" <<'RUBY'
class LinkStub
  def errors
  end

  def where(conditions)
    conditions
  end
end
RUBY
cat > "$FIX/lib/tmpl/base_template.rb" <<'RUBY'
class BaseTemplate
  def template
    hook
  end
end
RUBY
cat > "$FIX/lib/util/helpers.rb" <<'RUBY'
def top_helper
  5
end
RUBY
cat > "$FIX/spec/page_spec.rb" <<'RUBY'
describe "pages" do
  it "works" do
    spec_only_helper
  end
end
RUBY
# A concern's call reaches its includer's superclass (Renderer's attr_reader), while the one namesake in a file the
# concern REFERENCES (CommentsMod) is out of reach: Rule 3's include narrow must choose among the reachable only.
cat > "$FIX/lib/feed/renderer.rb" <<'RUBY'
class Renderer
  attr_reader :story
end
RUBY
cat > "$FIX/lib/feed/shared/comments_mod.rb" <<'RUBY'
module CommentsMod
  def self.version
    1
  end

  def story
    nil
  end
end
RUBY
cat > "$FIX/lib/feed/shared/group_content.rb" <<'RUBY'
module GroupContent
  def summary
    story
  end

  def self.helper
    CommentsMod.version
  end
end
RUBY
cat > "$FIX/lib/feed/catalog/reacted.rb" <<'RUBY'
class Reacted < Renderer
  include GroupContent
end
RUBY
# A class that writes the delegation DSL (ActiveSupport's `delegate`/`delegate_missing_to`, Forwardable's
# `def_delegator(s)`) defines methods the tree does not index, so it is exempt: its bare calls bind by name as before.
# The Quoting module and Pool class hold the only definitions of the delegated names, out of reach.
cat > "$FIX/lib/quoting/quoting.rb" <<'RUBY'
module Quoting
  def quote_name(n)
    n
  end

  def owner_name
    "o"
  end
end
RUBY
cat > "$FIX/lib/quoting/pool.rb" <<'RUBY'
class Pool
  def size
    0
  end

  def checkout
    nil
  end

  def forwarded_anywhere
    nil
  end

  def computed_name
    nil
  end
end
RUBY
cat > "$FIX/lib/sql/creation.rb" <<'RUBY'
class Creation
  delegate :quote_name, to: :@conn, private: true
  delegate :name, to: :owner, prefix: true

  def build
    quote_name(:t)
  end

  def label
    owner_name
  end
end
RUBY
cat > "$FIX/lib/sql/counter.rb" <<'RUBY'
class Counter
  def_delegators :@pool, :checkout

  def count
    checkout
  end
end
RUBY
cat > "$FIX/lib/sql/top_ctl.rb" <<'RUBY'
class TopCtl < ActionController::Base
  def display
    top_helper
  end
end
RUBY
cat > "$FIX/lib/sql/forwarder.rb" <<'RUBY'
class Forwarder
  delegate_missing_to :target

  def go
    forwarded_anywhere
  end
end
RUBY
cat > "$FIX/lib/sql/computed.rb" <<'RUBY'
class Computed
  NAMES = %i[computed_name].freeze
  delegate( *NAMES, to: :inner )

  def go
    computed_name
  end
end
RUBY
# A concern's `included do … end` runs in the INCLUDER, so a mixin written there joins the includer's ancestors —
# activerecord's AttributeMethods assembles Write and PrimaryKey this way; PrimaryKey#id= reaches Write through it.
cat > "$FIX/lib/attrs/attribute_methods.rb" <<'RUBY'
module AttributeMethods
  extend ActiveSupport::Concern

  included do
    include Write
    include PrimaryKey
  end
end
RUBY
cat > "$FIX/lib/attrs/write.rb" <<'RUBY'
module Write
  def _write_attribute(name, value)
    value
  end
end
RUBY
cat > "$FIX/lib/attrs/primary_key.rb" <<'RUBY'
module PrimaryKey
  def id=(value)
    _write_attribute(:id, value)
  end
end
RUBY
cat > "$FIX/lib/attrs/record_base.rb" <<'RUBY'
class RecordBase
  include AttributeMethods
end
RUBY
cat > "$FIX/lib/other/writer_decoy.rb" <<'RUBY'
class WriterDecoy
  def _write_attribute(name, value)
    name
  end
end
RUBY
# A reopened Object is every self's ancestor (activesupport's core_ext: Object#blank?, Kernel#silence_warnings).
cat > "$FIX/lib/core_ext/object.rb" <<'RUBY'
class Object
  def blank_ish?
    false
  end
end
RUBY
cat > "$FIX/lib/app/uses_object.rb" <<'RUBY'
class UsesObject
  def probe_blank
    blank_ish?
  end
end
RUBY
cat > "$FIX/lib/other/blank_decoy.rb" <<'RUBY'
class BlankDecoy
  def blank_ish?
    true
  end
end
RUBY
# A concern's nested `module ClassMethods` is extended onto its includer (ActiveSupport::Concern): the includer's
# class-body DSL call reaches it.
cat > "$FIX/lib/concerns/callbacky.rb" <<'RUBY'
module Callbacky
  extend ActiveSupport::Concern

  module ClassMethods
    def define_hooks(*names)
      names
    end
  end
end
RUBY
cat > "$FIX/lib/app/wrapper.rb" <<'RUBY'
class Wrapper
  include Callbacky

  define_hooks :run
end
RUBY
cat > "$FIX/lib/other/hook_decoy.rb" <<'RUBY'
class HookDecoy
  def define_hooks(*names)
    names
  end
end
RUBY

MAP="$DIR/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/map.err"
if [ $? -eq 0 ]; then ok "default map exits 0"; else no "default map exited non-zero: $( cat "$DIR/map.err" )"; fi
if [ -s "$DIR/map.err" ]; then no "unexpected stderr: $( head -3 "$DIR/map.err" )"; else ok "clean stderr"; fi
if command -v xmllint >/dev/null 2>&1
then
    if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi
fi

# callers ROOT SYM — the --callers=SYM caller rows, one per line, in $DIR/c.rows; returns 2 when the run failed, so an
# absence arm can never read a crashed run as "no caller".
callers(){
    if ! "$BIN" "$1" --no-cache --callers="$2" >"$DIR/c.out" 2>"$DIR/c.err"
    then
        no "--callers=$2 exited non-zero: $( head -3 "$DIR/c.err" )"
        return 2
    fi
    sed 's/></>\n</g' "$DIR/c.out" | grep '^<s t="' >"$DIR/c.rows"
    return 0
}
# reaches SYM CALLER WHY — CALLER (a symbol name) is a caller of SYM
reaches(){
    callers "$FIX" "$1" || return
    grep -q " n=\"$2\"" "$DIR/c.rows" && ok "$2 → $1 ($3)" \
        || no "$2 does not reach $1 ($3); callers: $( tr '\n' ' ' <"$DIR/c.rows" )"
}
# misses SYM CALLER WHY — CALLER is NOT a caller of SYM
misses(){
    callers "$FIX" "$1" || return
    grep -q " n=\"$2\"" "$DIR/c.rows" && no "$2 reaches $1 — $3" || ok "$2 does not reach $1 ($3)"
}

echo "=== a mixin is an ancestor: the base walk reaches it, ahead of a same-file namesake ==="
reaches SignalMixin::signal act "include Hub::SignalMixin — the mixin's def answers"
misses  Hub::signal act "Hub is not an ancestor of Ctl, only the mixin's namespace"
reaches RegistryDsl::register Registry "extend RegistryDsl — the class-body DSL call reaches the extended module"
misses  Robot::register       Registry "Robot is no ancestor of Registry"

echo "=== a class-body call runs with the class as self ==="
reaches Catalog::define_section Catalog "define_section :first inside Ns::Catalog names Catalog.define_section"
misses  Ns::define_section      Catalog "the enclosing namespace's method is not self's"

echo "=== below the caller: a subclass's or an includer's method answers a self call ==="
reaches Impl::hook           template "BaseTemplate#template's hook dispatches to Impl < BaseTemplate"
misses  Unrelated::hook      template "Unrelated is neither above nor below BaseTemplate"
reaches Order::audit_target  audit    "Auditable#audit's audit_target dispatches to its includer Order"
misses  Unrelated::audit_target audit "Unrelated does not include Auditable"

reaches Renderer::story       summary  "GroupContent#summary's story reaches Reacted's superclass Renderer through the includer"
misses  CommentsMod::story    summary  "naming CommentsMod in the concern's file does not put it in reach — the include narrow picks the reachable"

reaches Write::_write_attribute       "id=" "a mixin inside a concern's included block joins its includer's ancestors"
misses  WriterDecoy::_write_attribute "id=" "WriterDecoy is neither above nor below PrimaryKey"

reaches ClassMethods::define_hooks Wrapper "include Callbacky extends its ClassMethods onto Wrapper (the Concern convention)"
misses  HookDecoy::define_hooks    Wrapper "an unrelated class's namesake stays out of reach"

echo "=== out of reach: the method Ruby runs is not in the tree, so the call declines ==="
misses Component::render     show    "a controller's render is ActionController's, not a component's"
misses Rating::request   show    "naming Rating does not make its methods self's"
misses LinkStub::errors      check   "an ActiveModel form's errors is ActiveModel's"
misses LinkStub::where       Post    "a scope lambda's where runs on the model's relation"
misses Outer::outer_helper   m       "Outer::Inner does not inherit from Outer: lexical nesting is not lookup"

echo "=== floor (b): a class that delegates is exempt — its bare calls bind by name as before ==="
reaches Quoting::quote_name        build "delegate :quote_name, to: :@conn — the delegated method is not indexed, Creation is exempt"
reaches Quoting::owner_name        label "delegate … prefix: true — exempt the same way"
reaches Pool::checkout             count "def_delegators :@pool, :checkout — Forwardable, exempt"
reaches Pool::forwarded_anywhere   go    "delegate_missing_to forwards any name, as method_missing does"
reaches Pool::computed_name        go    "delegate( *NAMES, … ) — the names are computed, the class is exempt"

echo "=== a top-level def is reachable only while every ancestor in reach is in the tree ==="
misses  top_helper display "TopCtl < ActionController::Base: the out-of-tree ancestor answers before Object's private method"

echo "=== a reopened Object, Kernel, Module or Class is every self's ancestor ==="
reaches Object::blank_ish?     probe_blank "class Object; def blank_ish? — any self reaches it"
misses  BlankDecoy::blank_ish? probe_blank "an unrelated class's namesake stays out of reach"

echo "=== what the rule leaves alone ==="
reaches top_helper              m      "a top-level def is a private method of Object, reachable from any self"
reaches UserModel::display_name label  "floor (a): a SimpleDelegator subclass forwards what it lacks"
reaches UserModel::phantom      m      "floor (a): a class with method_missing answers any name"
reaches spec_only_helper "&lt;file-scope&gt;" "floor (f): an example group's block is in no class"

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

echo "=== mutation: drop the include → the concern no longer reaches Order ==="
MUT="$DIR/mut"; cp -R "$FIX" "$MUT"
grep -v '^  include Auditable$' "$FIX/lib/orders/order.rb" >"$MUT/lib/orders/order.rb"
grep -q 'include Auditable' "$MUT/lib/orders/order.rb" && no "mutation did not apply"
if callers "$MUT" "Order::audit_target"
then
    grep -q ' n="audit"' "$DIR/c.rows" && no "mutation: without the include, audit still reaches Order::audit_target" \
        || ok "mutation: without the include, audit no longer reaches Order::audit_target"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
