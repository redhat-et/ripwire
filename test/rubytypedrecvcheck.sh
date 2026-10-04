#!/usr/bin/env bash
# rubytypedrecvcheck.sh — gate for a Ruby call whose RECEIVER has a type the code states. `c = Client.new( url )` then
# `c.get`, `u = User.find( id )` then `u.display_name`, `Client.new.close`, and in a spec `let( :user ) { create( :user ) }`
# then `user.activate!`: the receiver is an instance of one class, and Ruby's method lookup on that class decides which
# `def` answers. Before this round every such call bound by NAME alone — same file, same directory, the one definer in
# the tree, else no edge — so `c.get` declined between Client#get and Other#get, `u.email` (a column Rails generates)
# bound to an unrelated Post#email, and in a spec that also builds a Post, every `user.…` call bound to Post's method
# through the include narrow (the file names Post as a receiver; it names User only as a describe argument).
# THE RULE (ingest_binds.h rubyTypeReceivers; graph.h rubyTypedReceiver): a receiver is TYPED when the code builds it in
# one of these shapes, read lexically by Ruby's own local rule —
#   * a local whose every assignment in its def (or block, or file scope) is one of the shapes below and names one class;
#   * an RSpec `let`/`let!`/`subject` whose block's value is one — the innermost visible definition, as RSpec runs it —
#     and a group's implicit `subject`, which is `described_class.new`;
#   * the receiver written directly: `Foo.new( … ).m`, `Foo.find_by( … ).m`, `create( :user ).m`.
# The shapes: `Const.new`, an Active Record finder on a constant (`find`, `find_by`, `create`, `first`, … — kRubyTypedFinders),
# `described_class.new`, and a FactoryBot build (`create`/`build`/`build_stubbed( :factory, … )` inside an example group),
# whose class is the factory's (`class:` as written, a nested factory's parent's, else the name camelised) read from the
# tree's `FactoryBot.define` blocks. A typed call answers from the class's lookup — the class, its mixins, its superclass
# chain, then a reopened Object/Kernel/BasicObject — and, when none of those defines it, from a class BELOW it (Active
# Record's STI hands back a subclass); with no definer in reach the method is outside the tree (a column, an association,
# a framework method) and the call is refused as external.
#
# Stated floors, each pinned below:
#   (a) a type the tree does not define (`Net::HTTP.new`, `SimpleDelegator.new`, a `Point = Struct.new( … )` constant)
#       changes nothing: the call binds by name as before — and neither does a QUALIFIED constant whose path the tree
#       never opens (`Vendor::Client.new` beside an in-tree `Client`: classes are keyed by final segment everywhere else).
#   (b) a class that defines its own `self.find` / `self.new` (or one of its ancestors does) may return anything: a local
#       built that way is untyped.
#   (c) a local assigned any other shape anywhere in its scope, or bound as a parameter or block parameter there, is
#       untyped everywhere in that scope — the rule reads no control flow.
#   (d) instance variables, method return values, `x.class`, and a `let` defined in a shared context in another file are
#       not typed: those calls bind by name as before.
#   (e) a class whose lookup can leave it (a delegator, `method_missing`, the delegation DSL — rubyreachcheck floor (a)/(b))
#       refuses nothing: its typed calls bind by name as before.
#   (f) two factories sharing a name in different files, with different classes, type nothing.
#   (g) a method defined only through `alias`/`alias_method` is no def the tree indexes, so a typed call to it finds no
#       definer in reach and is refused — not bound to another class's namesake.
#
# Usage:  test/rubytypedrecvcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubytypedrecvcheck.sh
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
for d in app/models/concerns app/services lib/net lib/core_ext lib/misc spec/models spec/factories spec/support
do
    mkdir -p "$FIX/$d"
done

cat > "$FIX/app/models/application_record.rb" <<'RUBY'
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  def stamp_audit
    :base
  end
end
RUBY
cat > "$FIX/app/models/user.rb" <<'RUBY'
class User < ApplicationRecord
  include Notifiable

  def display_name
    "user"
  end

  def activate!
    true
  end

  def title_line
    display_name
  end
end
RUBY
cat > "$FIX/app/models/super_user.rb" <<'RUBY'
class SuperUser < User
  def power
    9
  end
end
RUBY
cat > "$FIX/app/models/post.rb" <<'RUBY'
class Post < ApplicationRecord
  def display_name
    "post"
  end

  def activate!
    false
  end

  def email
    "decoy"
  end

  def notify!
    :post
  end

  def stamp_audit
    :post
  end
end
RUBY
cat > "$FIX/app/models/admin.rb" <<'RUBY'
class Admin
  def display_name
    "admin"
  end
end
RUBY
cat > "$FIX/app/models/concerns/notifiable.rb" <<'RUBY'
module Notifiable
  extend ActiveSupport::Concern

  def notify!
    :notified
  end
end
RUBY
cat > "$FIX/app/models/widget.rb" <<'RUBY'
class Widget
  def self.find(id)
    Gadget.new
  end

  def spin
    :widget
  end
end
RUBY
cat > "$FIX/app/models/gadget.rb" <<'RUBY'
class Gadget
  def spin
    :gadget
  end
end
RUBY
cat > "$FIX/app/models/user_presenter.rb" <<'RUBY'
class UserPresenter < SimpleDelegator
end
RUBY
cat > "$FIX/lib/net/client.rb" <<'RUBY'
class Client
  def initialize(url = nil)
    @url = url
  end

  def get(path)
    path
  end

  def close
    nil
  end

  def wrap
    Other.new
  end

  alias_method :fetch, :get
end
RUBY
cat > "$FIX/lib/net/other.rb" <<'RUBY'
class Other
  def get(path)
    path
  end

  def fetch(path)
    path
  end

  def close
    nil
  end
end
RUBY
cat > "$FIX/lib/net/pool.rb" <<'RUBY'
module Transport
  class Pool
    def drain
      []
    end
  end
end
RUBY
cat > "$FIX/lib/core_ext/object.rb" <<'RUBY'
class Object
  def try_it
    self
  end
end
RUBY
cat > "$FIX/lib/misc/thing.rb" <<'RUBY'
class Thing
  def try_it
    :thing
  end

  def power
    0
  end

  def drain
    :thing
  end
end
RUBY
cat > "$FIX/lib/misc/rating.rb" <<'RUBY'
class Rating
  def request(req)
    req
  end
end
RUBY
cat > "$FIX/app/services/sync.rb" <<'RUBY'
class Sync
  def run(cond, req)
    c = Client.new("u")
    c.get("/x") # @local_new
    u = User.find(1)
    u.display_name # @local_finder
    u.email # @local_column
    u.notify! # @local_mixin
    u.stamp_audit # @local_super
    u.power # @local_subclass
    Client.new.close # @direct_new
    User.find_by(id: 1).activate! # @direct_finder
    c.try_it # @implicit_root
    c.fetch("/a") # @alias_floor
    r = Client.new
    r = r.wrap
    r.close # @reassigned
    k = Other.new if cond
    k = Client.new unless cond
    k.get("/z") # @conflict
    w = Widget.find(1)
    w.spin # @own_finder
    h = Net::HTTP.new("host")
    h.request(req) # @out_of_tree
    pr = UserPresenter.new(u)
    pr.title_line # @delegator
    pl = Transport::Pool.new
    th = Thing.new
    pl.drain # @qualified_in
    ext = Vendor::Client.new
    ext.get("/v") # @qualified_out
  end

  def shadowed
    c = Client.new
    [1].each { |c| c.get("/q") } # @block_param
  end

  def ivar_floor
    @client = Client.new
    @client.get("/i") # @ivar
  end

  def client
    Client.new
  end

  def return_floor
    client.get("/r") # @return
  end
end
RUBY
cat > "$FIX/spec/factories/users.rb" <<'RUBY'
FactoryBot.define do
  factory :user do
    name { "x" }

    factory :admin do
      admin { true }
    end
  end

  factory :editor, class: "User"
  factory :twin, class: "User"
end
RUBY
cat > "$FIX/spec/factories/posts.rb" <<'RUBY'
FactoryBot.define do
  factory :article, class: Post do
    title { "t" }
  end

  factory :twin, class: "Admin"
end
RUBY
cat > "$FIX/spec/support/shared_user.rb" <<'RUBY'
RSpec.shared_context "with a shared user" do
  let(:shared_user) { create(:user) }
end
RUBY
cat > "$FIX/spec/models/user_spec.rb" <<'RUBY'
require "rails_helper"

RSpec.describe User do
  let(:user) { create(:user) }
  let(:admin) { create(:admin) }
  let(:editor) { build(:editor) }
  let(:article) { create(:article) }
  let(:plain) { Post.new }
  let(:found) { User.find_by(id: 1) }
  subject(:svc) { described_class.new }
  let(:mystery) { make_thing }
  let(:twin) { create(:twin) }

  it "types each let by what its block builds" do
    user.display_name # @let_factory
    admin.display_name # @let_nested_factory
    editor.display_name # @let_class_string
    article.display_name # @let_class_const
    plain.display_name # @let_new
    found.display_name # @let_finder
    svc.display_name # @let_described
    user.email # @let_column
    mystery.title_line # @let_untyped
    twin.email # @let_twin_factory
    u2 = create(:user)
    u2.display_name # @spec_local
  end

  context "a nested group overrides the let" do
    let(:user) { create(:article) }

    it { user.display_name } # @let_override
  end

  it "a local shadows the let" do
    user = Post.new
    user.display_name # @local_shadows_let
  end
end
RUBY
cat > "$FIX/spec/models/post_spec.rb" <<'RUBY'
require "rails_helper"

RSpec.describe Post do
  include_context "with a shared user"

  it { subject.display_name } # @implicit_subject
  it { shared_user.title_line } # @shared_let
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

# The census (src/pincensus.h): one `C` row per call site the resolver decided or refused — mechanism, caller, callee,
# targets, line — so each arm reads ONE call site. (`--uses` cannot: it lists a caller's every same-named call under each
# target that caller reaches, and a spec's example blocks are all one caller, the file scope.)
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
# targets FILE LINE — every target the census names for the call on FILE:LINE, one per line
targets(){
    awk -F'\t' -v f="$1" -v l="$2" '$1 == "C" && $9 == l && index( $6, f "::" ) == 1 { n = split( $8, t, "|" ); for( i = 1; i <= n; ++i ) print t[ i ] }' \
        "$DIR/census.tsv"
}
# reaches SYM FILE MARK WHY — the call on the marked line resolves to SYM
reaches(){
    local n; n="$( line "$FIX" "$2" "$3" )"
    [ -n "$n" ] || { no "fixture marker @$3 missing in $2"; return; }
    targets "$2" "$n" | grep -qF "::$1#" && ok "@$3 → $1 ($4)" \
        || no "@$3 ($2:$n) does not reach $1 ($4); it reaches: $( targets "$2" "$n" | tr '\n' ' ' )"
}
# misses SYM FILE MARK WHY — the call on the marked line does NOT resolve to SYM
misses(){
    local n; n="$( line "$FIX" "$2" "$3" )"
    [ -n "$n" ] || { no "fixture marker @$3 missing in $2"; return; }
    targets "$2" "$n" | grep -qF "::$1#" && no "@$3 ($2:$n) reaches $1 — $4" || ok "@$3 does not reach $1 ($4)"
}

census "$FIX" || exit 1

S=app/services/sync.rb
U=spec/models/user_spec.rb
P=spec/models/post_spec.rb

echo "=== a local built by Const.new or a finder answers from its class ==="
reaches Client::get              $S local_new     "c = Client.new — Client#get, where the name alone declined"
misses  Other::get               $S local_new     "Other is not c's class"
reaches User::display_name       $S local_finder  "u = User.find( 1 ) — an Active Record finder returns a User"
misses  Post::display_name       $S local_finder  "Post is not u's class"
misses  Post::email              $S local_column  "no class in User's lookup defines email: a column, outside the tree — refused"
reaches Notifiable::notify!      $S local_mixin   "User includes Notifiable: the mixin answers"
misses  Post::notify!            $S local_mixin   "Post's namesake is not in User's lookup"
reaches ApplicationRecord::stamp_audit $S local_super "User < ApplicationRecord: the superclass answers"
misses  Post::stamp_audit        $S local_super   "a sibling's override is not User's"
reaches SuperUser::power         $S local_subclass "no ancestor defines power: a subclass may (STI hands one back)"
misses  Thing::power             $S local_subclass "Thing is neither above nor below User"
reaches Object::try_it           $S implicit_root "a reopened Object is every instance's ancestor"
misses  Thing::try_it            $S implicit_root "Thing is not in Client's lookup"
reaches Pool::drain              $S qualified_in  "pl = Transport::Pool.new — the tree opens Transport::Pool"
misses  Thing::drain             $S qualified_in  "Thing is not pl's class"

echo "=== a receiver written as the construction answers the same way ==="
reaches Client::close            $S direct_new    "Client.new.close"
misses  Other::close             $S direct_new    "Other is not the receiver's class"
reaches User::activate!          $S direct_finder "User.find_by( … ).activate!"
misses  Post::activate!          $S direct_finder "Post is not the receiver's class"

echo "=== an RSpec let answers from what its block builds ==="
reaches User::display_name       $U let_factory          "let( :user ) { create( :user ) } — factory :user builds a User"
misses  Post::display_name       $U let_factory          "the include narrow's Post is not user's class"
reaches User::display_name       $U let_nested_factory   "factory :admin nests in factory :user: it builds a User"
misses  Admin::display_name      $U let_nested_factory   "a nested factory's class is its parent's, not its camelised name"
reaches User::display_name       $U let_class_string     "factory :editor, class: \"User\""
reaches Post::display_name       $U let_class_const      "factory :article, class: Post"
misses  User::display_name       $U let_class_const      "article is a Post"
reaches Post::display_name       $U let_new              "let( :plain ) { Post.new }"
reaches User::display_name       $U let_finder           "let( :found ) { User.find_by( … ) }"
reaches User::display_name       $U let_described        "subject( :svc ) { described_class.new } inside describe User"
misses  Post::email              $U let_column           "a User column is outside the tree — refused, not Post#email"
reaches User::display_name       $U spec_local           "u2 = create( :user ) inside an example"
reaches Post::display_name       $U let_override         "the nested group's let( :user ) { create( :article ) } is the one RSpec runs"
misses  User::display_name       $U let_override         "the outer let is overridden"
reaches Post::display_name       $U local_shadows_let    "a local named user hides the let"
misses  User::display_name       $U local_shadows_let    "the let is not what user reads there"
reaches Post::display_name       $P implicit_subject     "a group's implicit subject is described_class.new"

echo "=== what the rule leaves alone ==="
misses  Client::close            $S reassigned    "floor (c): r = r.wrap reassigns r — untyped"
misses  Client::get              $S conflict      "floor (c): k is assigned an Other and a Client — untyped"
misses  Other::get               $S conflict      "floor (c): neither class is k's"
misses  Widget::spin             $S own_finder    "floor (b): Widget defines self.find — w is untyped"
reaches Rating::request      $S out_of_tree   "floor (a): Net::HTTP is outside the tree — the call binds by name as before"
misses  Client::get              $S qualified_out "floor (a): the tree opens no Vendor::Client — its final segment is no in-tree Client"
misses  Other::fetch             $S alias_floor   "floor (g): Client's fetch is an alias_method, which the tree indexes as no def — refused, not Other#fetch"
reaches User::title_line         $S delegator     "floor (e): UserPresenter < SimpleDelegator forwards what it lacks"
misses  Client::get              $S block_param   "floor (c): a block parameter c makes c untyped in its scope"
misses  Client::get              $S ivar          "floor (d): an instance variable is not typed"
misses  Client::get              $S return        "floor (d): a method's return value is not typed"
reaches User::title_line         $U let_untyped   "a let whose block builds nothing typed binds by name as before"
reaches Post::email              $U let_twin_factory "floor (f): factory :twin names User in one file and Admin in another — untyped, binds by name"
reaches User::title_line         $P shared_let    "floor (d): a shared context's let is not seen in the including file — binds by name as before"

echo "=== a qualified constant in a tree with no superclass, mixin or constant reference ==="
# The base scope and the resolver's constant index are built only for a tree that has those; the opens a qualified type
# is checked against must not depend on them.
FLAT="$DIR/flat"; mkdir -p "$FLAT/lib"
cat > "$FLAT/lib/pool.rb" <<'RUBY'
module Transport
  class Pool
    def drain
      :pool
    end
  end
end
RUBY
cat > "$FLAT/lib/sink.rb" <<'RUBY'
class Sink
  def drain
    :sink
  end

  def flush
    :sink
  end
end
RUBY
cat > "$FLAT/lib/run.rb" <<'RUBY'
class Runner
  def go
    pool = Transport::Pool.find( 1 )
    pool.drain # @flat_finder
    pool.flush # @flat_refused
  end
end
RUBY
n="$( line "$FLAT" lib/run.rb flat_finder )"
m="$( line "$FLAT" lib/run.rb flat_refused )"
if census "$FLAT"
then
    targets lib/run.rb "$n" | grep -qF "::Pool::drain#" && ok "@flat_finder → Pool::drain (Transport::Pool is opened, though nothing else in the tree is scoped)" \
        || no "@flat_finder (lib/run.rb:$n) does not reach Pool::drain; it reaches: $( targets lib/run.rb "$n" | tr '\n' ' ' )"
    targets lib/run.rb "$n" | grep -qF "::Sink::drain#" && no "@flat_finder reaches Sink::drain — Sink is not pool's class" \
        || ok "@flat_finder does not reach Sink::drain"
    targets lib/run.rb "$m" | grep -qF "::Sink::flush#" && no "@flat_refused reaches Sink::flush — nothing in Pool's lookup defines flush" \
        || ok "@flat_refused does not reach Sink::flush (refused: no definer in Pool's lookup)"
fi

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

echo "=== mutation: the factory's class moves → the let follows it ==="
MUT="$DIR/mut"; cp -R "$FIX" "$MUT"
sed 's/factory :article, class: Post do/factory :article, class: "User" do/' "$FIX/spec/factories/posts.rb" >"$MUT/spec/factories/posts.rb"
grep -q 'class: "User" do' "$MUT/spec/factories/posts.rb" || no "mutation did not apply"
n="$( line "$MUT" "$U" let_class_const )"
if census "$MUT"
then
    targets "$U" "$n" | grep -qF "::User::display_name#" && ok "mutation: factory :article, class: \"User\" — article.display_name now reaches User" \
        || no "mutation: with the factory's class changed, article.display_name does not reach User"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
