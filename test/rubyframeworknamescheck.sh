#!/usr/bin/env bash
# rubyframeworknamescheck.sh — gate for the framework method names: in a tree that uses Rails, a call whose receiver no rule
# typed and whose name is a method ActiveRecord or ActiveSupport gives its objects (`scope.where( … )`, `rows.pluck( :id )`,
# `params[ :q ].blank?`, `record.save`, `Time.zone.now`) is no evidence for the ONE application method that shares the name.
# Before this round such a call reached the name tier with its spelling as the only evidence and bound that lone method: a
# test double's `where` and `pluck`, a value class's `blank?` and `present?`, a library class's `now` — 20 of 20 sampled
# sites wrong on one Rails application and 18 of 20 on another (docs/research/ruby-roadmap.md §2.2).
# THE RULE (graph.h BuiltinMethodGate, the framework rows; the tables and their generator commands are in
# src/externalnames.h):
#   * a framework's table joins the builtin-method gate when the tree USES the framework — a superclass, mixin or receiver
#     constant written under one of its namespaces (`< ActiveRecord::Base`, `extend ActiveSupport::Concern`) — and does not
#     DEFINE it (no open of the row's home constant, so the Rails gems' own trees keep their maps);
#   * the gate then decides such a call as it decides `h.fetch( k )`: the ladder's targets stand when the caller's file
#     names one's class, and otherwise the call loses its edge — declined, counted on the definitions it could have meant;
#   * a name in no table keeps the ladder, and a tree with no evidence of the framework keeps it for every name.
#
# Stated floors, each pinned below:
#   (a) an object handed in with no mention of its class in the file (an untyped parameter, dependency injection) no longer
#       reaches the application method by name: the call is declined and counted, as the builtin gate's floor (4) says.
#   (b) the evidence is the TREE's: a file in a Rails tree that never touches a model is gated like any other.
#
# Usage:  test/rubyframeworknamescheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyframeworknamescheck.sh
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

# ── the application: a Rails tree (ApplicationRecord < ActiveRecord::Base) ────────────────────────────────────────────────
APP="$DIR/app"
for d in app/models app/services lib spec/support
do
    mkdir -p "$APP/$d"
done
cat > "$APP/app/models/application_record.rb" <<'RUBY'
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
RUBY
cat > "$APP/app/models/order.rb" <<'RUBY'
class Order < ApplicationRecord
  def paid_ids( scope )
    scope.where( paid: true ) # @model_where
  end
end
RUBY
# The ONE in-tree definition of each framework name: a test double, a value class, a form object, a clock.
cat > "$APP/spec/support/fake_scope.rb" <<'RUBY'
class FakeScope
  def where( *conditions )
    self
  end

  def pluck( *columns )
    []
  end

  def rewind
    self
  end
end
RUBY
cat > "$APP/lib/amount.rb" <<'RUBY'
class Amount
  def initialize( cents )
    @cents = cents
  end

  def blank?
    @cents.zero?
  end

  def present?
    !blank?
  end

  def name
    "amount"
  end
end
RUBY
cat > "$APP/lib/enlist_form.rb" <<'RUBY'
class EnlistForm
  def save
    true
  end

  def valid?
    true
  end
end
RUBY
cat > "$APP/lib/wall_clock.rb" <<'RUBY'
class WallClock
  def now
    0
  end
end
RUBY
# The calls: none of these files names FakeScope, Amount, EnlistForm or WallClock.
cat > "$APP/app/services/order_report.rb" <<'RUBY'
class OrderReport
  def initialize( scope, params )
    @scope  = scope
    @params = params
  end

  def ids
    paid = @scope.where( paid: true ) # @where
    paid.pluck( :id ) # @pluck
  end

  def query?
    @params[ :q ].present? # @present
  end

  def stamp
    Time.zone.now # @now
  end

  def persist( record )
    record.save # @save
  end

  def title( record )
    record.name # @name
  end

  def again
    @scope.rewind # @control
  end
end
RUBY
# A file that names the class keeps the edge: a construction is evidence.
cat > "$APP/lib/amount_report.rb" <<'RUBY'
class AmountReport
  def empty?( cents )
    Amount.new( cents ).blank? # @kept_blank
  end

  def label( amount )
    amount.name # @kept_name
  end
end
RUBY
# Two classes define group (an ActiveRecord name); the caller's file names one of them. The ladder's split is kept whole.
cat > "$APP/app/models/fellowship.rb" <<'RUBY'
class Fellowship < ApplicationRecord
  def group
    nil
  end
end
RUBY
cat > "$APP/app/services/flag_presenter.rb" <<'RUBY'
class FlagPresenter
  def group
    nil
  end
end
RUBY
cat > "$APP/app/services/team_service.rb" <<'RUBY'
class TeamService
  def leader( fellowship )
    Fellowship.find( 1 )
    fellowship.group # @split_kept
  end
end
RUBY
# Floor (a): the form arrives as a parameter in a file that never names EnlistForm.
cat > "$APP/app/services/signup_flow.rb" <<'RUBY'
class SignupFlow
  def finish( form )
    form.valid? # @injected
  end
end
RUBY

# ── the framework itself: a tree that opens ActiveRecord::QueryMethods keeps its own edges ────────────────────────────────
FW="$DIR/framework"
mkdir -p "$FW/lib/active_record/relation"
cat > "$FW/lib/active_record/relation/query_methods.rb" <<'RUBY'
module ActiveRecord
  module QueryMethods
    def where( *args )
      self
    end
  end
end
RUBY
cat > "$FW/lib/active_record/internal_metadata.rb" <<'RUBY'
module ActiveRecord
  class InternalMetadata < ActiveRecord::Base
  end
end
RUBY
cat > "$FW/lib/active_record/scoping.rb" <<'RUBY'
module ActiveRecord
  module Scoping
    def scoped( rel )
      rel.where( id: 1 ) # @home_where
    end
  end
end
RUBY

# ── a plain Ruby tree: no Rails constant anywhere, so no framework row applies ────────────────────────────────────────────
PLAIN="$DIR/plain"
mkdir -p "$PLAIN/lib"
cat > "$PLAIN/lib/store.rb" <<'RUBY'
class Store
  def where( query )
    []
  end

  def blank?
    false
  end
end
RUBY
cat > "$PLAIN/lib/finder.rb" <<'RUBY'
class Finder
  def run( store )
    store.where( 1 ) # @plain_where
  end

  def none?( store )
    store.blank? # @plain_blank
  end
end
RUBY

# ── ActiveSupport alone: a Concern, no ActiveRecord constant — ActiveSupport's names are gated, ActiveRecord's are not ─────
AS="$DIR/support"
cp -R "$PLAIN" "$AS"
cat > "$AS/lib/auditable.rb" <<'RUBY'
module Auditable
  extend ActiveSupport::Concern
end
RUBY

# The census (src/pincensus.h): one `C` row per call site the resolver bound or refused as external; a DECLINED site
# writes no row, so each arm reads the rows of ONE line.
census(){
    if ! "$BIN" "$1" --no-cache --pin-census="$DIR/census-$2.tsv" >/dev/null 2>"$DIR/census.err"
    then
        no "--pin-census on $1 exited non-zero: $( head -3 "$DIR/census.err" )"
        return 2
    fi
    return 0
}
for tree in app framework plain support
do
    census "$DIR/$tree" "$tree" || exit 1
done
# line TREE FILE MARK — the line number carrying `# @MARK` (empty when the marker is missing)
line(){
    grep -n "# @$3\$" "$DIR/$1/$2" | head -1 | cut -d: -f1
}
# rows TREE FILE LINE CALLEE — "mechanism<TAB>targets" of each CALLEE call the census records on FILE:LINE
rows(){
    awk -F'\t' -v f="$2" -v l="$3" -v c="$4" '$1 == "C" && $9 == l && $7 == c && index( $6, f "::" ) == 1 { print $2 "\t" $8 }' "$DIR/census-$1.tsv"
}
# binds TREE CALLEE TARGET FILE MARK WHY — the CALLEE call on the marked line binds TARGET (an id fragment) alone
binds(){
    local n r; n="$( line "$1" "$4" "$5" )"
    [ -n "$n" ] || { no "fixture marker @$5 missing in $1/$4"; return; }
    r="$( rows "$1" "$4" "$n" "$2" )"
    if [ -n "$r" ] && [ "$( printf '%s\n' "$r" | wc -l )" -eq 1 ] && printf '%s\n' "$r" | grep -qF "$3" && ! printf '%s\n' "$r" | grep -qF "|"
    then
        ok "@$5 :$2 → $3 ($6)"
    else
        no "@$5 ($1/$4:$n) :$2 does not bind $3 alone ($6); census: $( printf '%s' "$r" | tr '\t\n' ' ;' )"
    fi
}
# splits TREE CALLEE A B FILE MARK WHY — the CALLEE call on the marked line keeps a split holding both A and B
splits(){
    local n r; n="$( line "$1" "$5" "$6" )"
    [ -n "$n" ] || { no "fixture marker @$6 missing in $1/$5"; return; }
    r="$( rows "$1" "$5" "$n" "$2" )"
    if [ "$( printf '%s\n' "$r" | wc -l )" -eq 1 ] && printf '%s\n' "$r" | grep -qF "$3" && printf '%s\n' "$r" | grep -qF "$4" && printf '%s\n' "$r" | grep -qF "|"
    then
        ok "@$6 :$2 stays a split of $3 and $4 ($7)"
    else
        no "@$6 ($1/$5:$n) :$2 is not a split of $3 and $4 ($7); census: $( printf '%s' "$r" | tr '\t\n' ' ;' )"
    fi
}
# declined TREE CALLEE FILE MARK WHY — the CALLEE call on the marked line binds nothing and is not refused as external
declined(){
    local n r; n="$( line "$1" "$3" "$4" )"
    [ -n "$n" ] || { no "fixture marker @$4 missing in $1/$3"; return; }
    r="$( rows "$1" "$3" "$n" "$2" )"
    if [ -z "$r" ]
    then
        ok "@$4 :$2 declined ($5)"
    else
        no "@$4 ($1/$3:$n) :$2 is not declined ($5); census: $( printf '%s' "$r" | tr '\t\n' ' ;' )"
    fi
}
# declines TREE SELECTOR N WHY — the definition's --callers answer counts N declined calls
declines(){
    local got; got="$( "$BIN" "$DIR/$1" --no-cache --callers="$2" --legend=compact 2>/dev/null | grep -o 'declined_calls="[0-9]*"' | head -1 | tr -dc '0-9' )"
    [ "$got" = "$3" ] && ok "--callers=$2 declined_calls=$3 ($4)" || no "--callers=$2 declined_calls=${got:-absent}, want $3 ($4)"
}

SVC=app/services/order_report.rb
echo "=== ActiveRecord's and ActiveSupport's names on an untyped receiver bind no application method ==="
declined app where   $SVC where   "a relation's where, not the test double's"
declined app pluck   $SVC pluck   "a relation's pluck, not the test double's"
declined app present? $SVC present "ActiveSupport's Object#present?, not the value class's"
declined app now     $SVC now     "ActiveSupport::TimeZone#now, not the clock's"
declined app save    $SVC save    "a record's save, not the form object's"
declined app name    $SVC name    "a record's (or a zone's) name, not the value class's"
declined app where   app/models/order.rb model_where "inside a model too"
declines app "lib/amount.rb::Amount::present?" 1 "the decline is counted on the definition it could have meant"
declines app "spec/support/fake_scope.rb::FakeScope::where" 2 "both where calls"

echo "=== evidence keeps the edge, and a name in no table keeps the ladder ==="
binds app blank?  "Amount::blank?"     lib/amount_report.rb kept_blank "the file constructs an Amount"
binds app name    "Amount::name"       lib/amount_report.rb kept_name  "the file names Amount: the evidence is the file's"
binds app rewind  "FakeScope::rewind"  $SVC control  "rewind is in no table"
splits app group "Fellowship::group" "FlagPresenter::group" app/services/team_service.rb split_kept \
    "one evidenced arm keeps the split whole: a framework name never narrows it to the file's class"

echo "=== a tree that is the framework, or does not use it, keeps the ladder ==="
binds framework where "QueryMethods::where" lib/active_record/scoping.rb home_where "the tree opens ActiveRecord::QueryMethods"
binds plain where  "Store::where"  lib/finder.rb plain_where "no Rails constant in the tree"
binds plain blank? "Store::blank?" lib/finder.rb plain_blank "no Rails constant in the tree"
declined support blank? lib/finder.rb plain_blank "an ActiveSupport::Concern is ActiveSupport evidence"
binds support where "Store::where" lib/finder.rb plain_where "but no ActiveRecord evidence: where keeps the ladder"

echo "=== stated floors ==="
declined app valid? app/services/signup_flow.rb injected "a: an injected form, its class never named in the file"

echo "=== determinism and warm == cold ==="
MAP="$DIR/a.xml"
"$BIN" "$APP" --no-cache >"$MAP" 2>/dev/null
"$BIN" "$APP" --no-cache >"$DIR/b.xml" 2>/dev/null
cmp -s "$MAP" "$DIR/b.xml" && ok "byte-identical across two --no-cache runs" || no "output differs across runs"
if command -v xmllint >/dev/null 2>&1
then
    if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi
fi
"$BIN" "$APP" --cache="$DIR/c.bin" >"$DIR/cold.xml" 2>/dev/null || no "the cold cache run exited non-zero"
"$BIN" "$APP" --cache="$DIR/c.bin" >"$DIR/warm.xml" 2>/dev/null || no "the warm cache run exited non-zero"
cmp -s "$DIR/cold.xml" "$DIR/warm.xml" && cmp -s "$MAP" "$DIR/cold.xml" && ok "warm run == cold run == --no-cache run" \
    || no "the cache disagrees with the --no-cache run"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
