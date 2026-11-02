#!/usr/bin/env bash
# rubyrecvevidencecheck.sh — gate for more evidence for a Ruby receiver's type (docs/research/ruby-roadmap.md R4): an
# instance variable, a method's return value, and an Active Record relation are values the code BUILDS, and Ruby's lookup on
# what they build answers a call on them, as it already does for a local built by `Client.new` (test/rubytypedrecvcheck.sh).
# Before this round `@client.fetch`, `connection.close` (a memoised `@connection ||= ApiClient.new`) and
# `User.where( … ).recent_first` reached the name tier with the spelling as their only evidence: a split over every class's
# `fetch`, or a decline.
# THE RULE (ingest_binds.h RubyBareCallWalk, src/ruby_receivers.h; graph.h RubyTypedReceivers::classOf, RubyClassObjects::of;
# parser version 275):
#   * an instance variable read in an instance method of a class or module is typed when every assignment to it in that
#     class body (this file) builds the same thing — `@x = C.new`, a finder, `@x ||= …`, a relation, a typed method's value —
#     and nothing else can assign it: an `attr_writer`/`attr_accessor` of its name, `@x += …` or a multiple assignment leaves
#     it untyped, and so does a read or write inside a block that hands self to another object (`instance_eval` and kin);
#   * a bare-word receiver in an instance method (`connection.close`, no local or let of the name) is a call to self's
#     method: typed when the class body defines that method exactly once, with no parameters and no `return`, and its body's
#     value builds one thing (an endless `def store = Store.new`, a memoising `@x ||= C.new`, an ivar's value), or an
#     `attr_reader` reads a typed ivar;
#   * `C.where( … )`, `C.all`, `C.order( … )` and a chain of such links build a relation of C, answered by C's CLASS-side
#     lookup (a scope's `def self.m` reaches through it; Active Record's own `pluck` is outside the tree: refused as
#     external) — but a name ActiveRecord::Relation answers itself (`find_each`, `count`, `map`: externalnames.h
#     kRubyActiveRecordRelationMethodNames) never reaches the class side, whatever the class defines; a finder at the end of
#     a chain (`C.where( … ).first`) builds an instance; a class whose lookup defines any link of the chain
#     (`def self.where`) is left as before.
#
# Stated floors, each pinned below:
#   (a) an instance variable is read from its own class body in its own file: a subclass or a reopening elsewhere that
#       assigns it differently is not seen (the parent's type answers);
#   (b) a block parameter is not typed, even over a relation (`User.where( … ).each { |u| u.display_name }`);
#   (c) a local assigned from a typed ivar or method (`c = @client`) is not typed.
#
# Usage:  test/rubyrecvevidencecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyrecvevidencecheck.sh
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
for d in app/models app/services lib
do
    mkdir -p "$FIX/$d"
done

# ── the models: User answers a relation's scope as a class method; Post and FakeScope carry instance namesakes ─────────────
cat > "$FIX/app/models/application_record.rb" <<'EOF'
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
EOF
cat > "$FIX/app/models/user.rb" <<'EOF'
class User < ApplicationRecord
  def self.recent_first
    order( created_at: :desc )
  end

  def self.find_each( batch: 100 )
    super
  end

  def display_name
    name
  end

  def activate!
    update( active: true )
  end
end
EOF
cat > "$FIX/app/models/post.rb" <<'EOF'
class Post < ApplicationRecord
  def recent_first
    self
  end

  def display_name
    title
  end

  def activate!
    true
  end
end
EOF
cat > "$FIX/app/models/tuned.rb" <<'EOF'
class Tuned < ApplicationRecord
  def self.where( *args )
    super
  end

  def self.recent_first
    all
  end
end
EOF
cat > "$FIX/lib/fake_scope.rb" <<'EOF'
class FakeScope
  def pluck( *columns )
    columns
  end

  def recent_first
    self
  end
end
EOF
cat > "$FIX/lib/api_client.rb" <<'EOF'
class ApiClient
  def fetch( path )
    path
  end

  def close
    true
  end
end
EOF
cat > "$FIX/lib/other_client.rb" <<'EOF'
class OtherClient
  def fetch( path )
    path
  end

  def close
    false
  end
end
EOF
cat > "$FIX/lib/gateway.rb" <<'EOF'
class Gateway
  def charge( amount )
    amount
  end
end
EOF
cat > "$FIX/lib/purse.rb" <<'EOF'
class Purse
  def charge( amount )
    -amount
  end
end
EOF
cat > "$FIX/lib/store.rb" <<'EOF'
class Store
  def save_all
    true
  end
end
EOF
cat > "$FIX/lib/archive.rb" <<'EOF'
class Archive
  def save_all
    false
  end
end
EOF

# ── the arms: each marked call is one census row. Every arm file calls each decoy class too (`decoys`): a constant receiver
# is a dependency edge, and the include narrow would otherwise pick the one class the file calls, typed or not. ──────────────────────────────────────────────────────────────────────
cat > "$FIX/app/services/report.rb" <<'EOF'
class Report
  attr_reader :gateway

  def initialize( user_id )
    @client  = ApiClient.new
    @user    = User.find( user_id )
    @gateway = Gateway.new
    @admins  = User.where( admin: true )
  end

  def run
    @client.fetch( "/a" ) # @ivar_new
    @user.activate! # @ivar_finder
    gateway.charge( 10 ) # @attr_reader
    @admins.recent_first # @ivar_relation
    connection.close # @memo_def
    store.save_all # @endless_def
    User.where( active: true ).recent_first # @relation_chain
    User.where( active: true ).order( :name ).recent_first # @relation_links
    User.where( active: true ).first.display_name # @relation_finder
    User.where( active: true ).pluck( :id ) # @relation_external
    User.where( active: true ).find_each { |u| u } # @relation_own
    scope = User.order( :name )
    scope.recent_first # @local_relation
    Tuned.where( x: 1 ).recent_first # @redefined_link
  end

  def connection
    @connection ||= ApiClient.new
  end

  def store = Store.new

  def decoys
    [OtherClient.new, Post.first, Purse.new, Archive.new, FakeScope.new]
  end
end
EOF
cat > "$FIX/app/services/guards.rb" <<'EOF'
class Mixed
  def initialize
    @client = ApiClient.new
  end

  def reset!
    @client = OtherClient.new
  end

  def run
    @client.fetch( "/m" ) # @ivar_disagree
  end
end

class Exposed
  attr_accessor :client

  def initialize
    @client = ApiClient.new
  end

  def run
    @client.fetch( "/e" ) # @ivar_accessor
  end
end

class ClassLevel
  @client = OtherClient.new

  def self.run
    @client.fetch( "/c" ) # @class_ivar
  end

  def initialize
    @client = ApiClient.new
  end
end

class Replies
  def client
    return OtherClient.new if ENV["X"]
    ApiClient.new
  end

  def run
    client.fetch( "/r" ) # @def_return
  end
end

class Rebound
  def initialize
    @client = ApiClient.new
  end

  def run( other )
    other.instance_eval { @client.fetch( "/i" ) } # @rebound
  end
end

class SideCheck
  def self.client
    ApiClient.new
  end

  def run
    client.fetch( "/s" ) # @class_side_def
  end

  def decoys
    [ApiClient.new, OtherClient.new]
  end
end
EOF
cat > "$FIX/app/services/gaps.rb" <<'EOF'
class Gaps
  def initialize
    @client = ApiClient.new
  end

  def iterate
    User.where( active: true ).each { |u| u.display_name } # @block_param
  end

  def through_local
    c = @client
    c.close # @local_from_ivar
  end

  def decoys
    [OtherClient.new, Post.first]
  end
end
EOF
cat > "$FIX/lib/base_job.rb" <<'EOF'
class BaseJob
  def initialize
    @client = ApiClient.new
  end

  def perform
    @client.fetch( "/b" ) # @inherited_assign
  end

  def fallback = OtherClient.new
end
EOF
cat > "$FIX/lib/special_job.rb" <<'EOF'
class SpecialJob < BaseJob
  def initialize
    @client = OtherClient.new
  end
end
EOF

MAP="$DIR/map.xml"
if ! "$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/map.err"
then
    no "the map run exited non-zero: $( head -3 "$DIR/map.err" )"
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
# only FILE MARK CALLEE SYM WHY — the marked call's one row binds SYM and nothing else
only(){
    local n r; n="$( line "$1" "$2" )"
    [ -n "$n" ] || { no "fixture marker @$2 missing in $1"; return; }
    r="$( rows "$1" "$n" "$3" )"
    local t="${r#*$'\t'}"
    if [ "$( printf '%s\n' "$r" | grep -c . )" = 1 ] && [ "${t#*|}" = "$t" ] && printf '%s' "$t" | grep -qF "::$4#"
    then
        ok "@$2 :$3 → $4 alone ($5)"
    else
        no "@$2 ($1:$n) :$3 does not reach $4 alone ($5); census: $( printf '%s' "$r" | tr '\t\n' '  ' )"
    fi
}
# refused FILE MARK CALLEE WHY — the marked call is refused as external (its method is outside the tree)
refused(){
    local n r; n="$( line "$1" "$2" )"
    [ -n "$n" ] || { no "fixture marker @$2 missing in $1"; return; }
    r="$( rows "$1" "$n" "$3" )"
    if [ "$( printf '%s\n' "$r" | grep -c . )" = 1 ] && [ "$( printf '%s' "$r" | cut -f1 )" = external ]
    then
        ok "@$2 :$3 refused as external ($4)"
    else
        no "@$2 ($1:$n) :$3 is not refused as external ($4); census: $( printf '%s' "$r" | tr '\t\n' '  ' )"
    fi
}
# notonly FILE MARK CALLEE SYM WHY — the marked call is NOT bound to SYM alone: whatever the name tier decides (a split, a
# decline), the receiver's type was not read
notonly(){
    local n r; n="$( line "$1" "$2" )"
    [ -n "$n" ] || { no "fixture marker @$2 missing in $1"; return; }
    r="$( rows "$1" "$n" "$3" )"
    local t="${r#*$'\t'}"
    if [ "$( printf '%s\n' "$r" | grep -c . )" = 1 ] && [ "${t#*|}" = "$t" ] && printf '%s' "$t" | grep -qF "::$4#"
    then
        no "@$2 ($1:$n) :$3 is bound to $4 alone — $5"
    else
        ok "@$2 :$3 is not narrowed to $4 ($5)"
    fi
}
# reaches FILE MARK CALLEE SYM WHY — SYM is among the marked call's targets (an untyped call keeps its namesakes)
reaches(){
    local n; n="$( line "$1" "$2" )"
    [ -n "$n" ] || { no "fixture marker @$2 missing in $1"; return; }
    rows "$1" "$n" "$3" | cut -f2 | tr '|' '\n' | grep -qF "::$4#" && ok "@$2 :$3 still reaches $4 ($5)" \
        || no "@$2 ($1:$n) :$3 does not reach $4 ($5); census: $( rows "$1" "$n" "$3" | tr '\t\n' '  ' )"
}
# misses FILE MARK CALLEE SYM WHY — SYM is not among the marked call's targets
misses(){
    local n; n="$( line "$1" "$2" )"
    [ -n "$n" ] || { no "fixture marker @$2 missing in $1"; return; }
    rows "$1" "$n" "$3" | cut -f2 | tr '|' '\n' | grep -qF "::$4#" && no "@$2 ($1:$n) :$3 reaches $4 — $5" \
        || ok "@$2 :$3 does not reach $4 ($5)"
}

census "$FIX" || exit 1
R=app/services/report.rb
G=app/services/guards.rb
P=app/services/gaps.rb

echo "=== an instance variable answers from what every assignment to it builds ==="
only    $R ivar_new        fetch        ApiClient::fetch   "@client = ApiClient.new in initialize"
only    $R ivar_finder     activate!    User::activate!    "@user = User.find( id ): a finder returns a User"
only    $R ivar_relation   recent_first User::recent_first "@admins = User.where( … ): a relation answers from User's class side"

echo "=== a call to self's method answers from what the method returns ==="
only    $R attr_reader     charge       Gateway::charge    "attr_reader :gateway reads @gateway = Gateway.new"
only    $R memo_def        close        ApiClient::close   "def connection; @connection ||= ApiClient.new; end"
only    $R endless_def     save_all     Store::save_all    "def store = Store.new"

echo "=== an Active Record relation answers from its model's class side ==="
only    $R relation_chain  recent_first User::recent_first "User.where( … ).recent_first: a scope written as def self.recent_first"
only    $R relation_links  recent_first User::recent_first "two links, where and order, still a relation of User"
only    $R relation_finder display_name User::display_name "User.where( … ).first: a finder at the end builds an instance"
refused $R relation_external pluck                         "User.where( … ).pluck: Active Record's pluck, not FakeScope's"
refused $R relation_own    find_each                       "a relation answers its own find_each: User's def self.find_each is the class object's"
only    $R local_relation  recent_first User::recent_first "scope = User.order( :name ): a local holding a relation"

echo "=== guards: what cannot be trusted is left as before ==="
notonly $R redefined_link  recent_first Tuned::recent_first "Tuned defines def self.where: its chain may return anything"
notonly $G ivar_disagree   fetch        ApiClient::fetch   "two assignments build two classes: untyped"
notonly $G ivar_disagree   fetch        OtherClient::fetch "…neither class is the answer"
notonly $G ivar_accessor   fetch        ApiClient::fetch   "attr_accessor :client lets anyone assign it: untyped"
notonly $G class_ivar      fetch        ApiClient::fetch   "a class method's @client is the class object's, not an instance's"
notonly $G def_return      fetch        ApiClient::fetch   "an explicit return: the def's value is not one thing"
notonly $G rebound         fetch        ApiClient::fetch   "instance_eval hands self to another object: its @client is not ours"
notonly $G class_side_def  fetch        ApiClient::fetch   "def self.client is the class's: an instance's bare client is not it"

echo "=== stated floors ==="
notonly $P block_param     display_name User::display_name "floor (b): a block parameter is not typed, even over a relation"
notonly $P local_from_ivar close        ApiClient::close   "floor (c): a local assigned from a typed ivar is not typed"
only    lib/base_job.rb inherited_assign fetch ApiClient::fetch "floor (a): SpecialJob's own @client = OtherClient.new is not seen"

echo "=== determinism and warm == cold ==="
"$BIN" "$FIX" --no-cache >"$DIR/a.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$DIR/b.xml" 2>/dev/null
cmp -s "$DIR/a.xml" "$DIR/b.xml" && ok "byte-identical across two --no-cache runs" || no "two --no-cache runs differ"
"$BIN" "$FIX" >"$DIR/cold.xml" 2>/dev/null
"$BIN" "$FIX" >"$DIR/warm.xml" 2>/dev/null
cmp -s "$DIR/cold.xml" "$DIR/warm.xml" && cmp -s "$DIR/cold.xml" "$DIR/a.xml" && ok "warm run == cold run == --no-cache run" \
    || no "warm, cold and --no-cache runs differ"

echo
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "SOME CHECKS FAILED"; fi
exit "$fail"
