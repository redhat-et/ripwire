#!/usr/bin/env bash
# rubygeneratedcheck.sh — gate for the methods Ruby GENERATES (docs/research/ruby-roadmap.md R3): a class body's Rails DSL
# defines methods the source never spells as `def` — `has_many :bills` defines `bills` and `bills=`, `scope :active`
# a class method, `delegate :email, to: :owner` an instance method, an enum a predicate, a bang and two scopes per value — and
# Ruby's lookup on the class answers a call with them. Before this round such a call on a receiver the code built
# (`workspace.bills`, `Workspace.active`, a bare `bills` in one of Workspace's methods) found nothing in the class's lookup:
# refused as external when the tree held a namesake elsewhere, undefined when it held none.
# THE RULE (ingest_ruby.h captureRubyGeneratedDefs, src/ruby_generated.h; graph.h RubyClassObjects, RubyTypedReceivers; parser
# version 277):
#   * each declaration written at a class body's level, or in a concern's `included do`, mints the methods Rails generates
#     from it (src/ruby_generated.h kRubyGeneratedVerbs) as definitions of the class or concern: kind sec, the token naming
#     them their extent. A scope and an enum's value scopes are the class object's (and, from a concern, each includer's);
#   * a generated method is a definition ONLY a lookup that reached its class finds — a call to self, a receiver the code
#     builds, a class object, a relation — and it answers only when no written method in that lookup does: Rails keeps the
#     association and attribute methods in modules included before the body's own `include`s, so a written `def`, in the class
#     or in a module it includes, comes first;
#   * it never joins the name tier: an untyped `record.bills` is decided exactly as before.
#
# Stated floors, each pinned below:
#   (a) an association's value is not typed: `workspace.bills.first.total` is not Bill#total;
#   (b) a scope's value is not typed as a relation: `Workspace.active.recent` is not Workspace's recent;
#   (c) a collection's `bill_ids` and an enum's pluralized class method (`Workspace.plans`) are not minted (they need the
#       inflector);
#   (d) a declaration inside `with_options … do` is not read;
#   (e) a superclass's written method answers before the class's own generated one (Ruby runs the generated: its module sits
#       below the class, above the superclass);
#   (f) `delegate`, `alias_method` and `define_method` define on the class itself in Ruby, so they beat a module the class
#       includes; here a written method of the module answers first.
#
# Usage:  test/rubygeneratedcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubygeneratedcheck.sh
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
for d in app/models/concerns app/services lib spec/models spec/factories
do
    mkdir -p "$FIX/$d"
done

# ── the models: Workspace declares one of each family; Archivable is a concern; the rest carry the guards and floors ─────────
cat > "$FIX/app/models/application_record.rb" <<'EOF'
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
EOF
cat > "$FIX/app/models/workspace.rb" <<'EOF'
class Workspace < ApplicationRecord
  include Archivable

  has_many :bills, dependent: :destroy
  has_one :dossier
  belongs_to :owner, class_name: "Patron"
  has_and_belongs_to_many :topics

  scope :active, -> { where( active: true ) }
  scope :recent, -> { order( created_at: :desc ) }

  delegate :email, :locale, to: :owner
  delegate :currency, to: :dossier, prefix: true
  delegate :region, to: :dossier, prefix: :home

  enum :status, { trial: 0, paid: 1 }, prefix: true
  enum plan: { basic: 0, premium: 1 }

  has_one_attached :logo
  accepts_nested_attributes_for :dossier

  alias_method :customer, :owner
  alias buyer owner
  define_method( :summary ) { "summary" }

  with_options dependent: :destroy do
    has_many :drafts
  end

  def renew
    bills.each( &:void! )   # @self_assoc
  end

  def self.dormant
    active   # @self_scope
  end
end
EOF
cat > "$FIX/app/models/concerns/archivable.rb" <<'EOF'
module Archivable
  extend ActiveSupport::Concern

  included do
    has_many :archives
    scope :archived, -> { where( archived: true ) }
  end

  def archive!
    archives.create!( at: 1 )   # @concern_self
  end
end
EOF
cat > "$FIX/app/models/enterprise.rb" <<'EOF'
class Enterprise < Workspace
end
EOF
cat > "$FIX/app/models/bill.rb" <<'EOF'
class Bill < ApplicationRecord
  belongs_to :workspace

  def total
    1
  end
end
EOF
cat > "$FIX/app/models/shipment.rb" <<'EOF'
class Shipment < ApplicationRecord
  belongs_to :carrier

  def carrier
    super
  end
end
EOF
cat > "$FIX/app/models/team.rb" <<'EOF'
class Team < ApplicationRecord
  include Labelled

  has_many :badges
end
EOF
cat > "$FIX/app/models/concerns/labelled.rb" <<'EOF'
module Labelled
  def badges
    []
  end
end
EOF
cat > "$FIX/app/models/vehicle.rb" <<'EOF'
class Vehicle < ApplicationRecord
  def wheels
    4
  end
end
EOF
cat > "$FIX/app/models/truck.rb" <<'EOF'
class Truck < Vehicle
  has_many :wheels
end
EOF
cat > "$FIX/lib/greeter.rb" <<'EOF'
module Greeter
  def greeting
    "hello"
  end
end
EOF
cat > "$FIX/lib/kiosk.rb" <<'EOF'
class Kiosk
  include Greeter

  define_method( :greeting ) { "hi" }
end
EOF
# a class whose method calls one of its own methods named `scope`: no declaration
cat > "$FIX/lib/builder.rb" <<'EOF'
class Builder
  def configure
    scope :drafts
  end

  def scope( name )
    name
  end
end
EOF
# namesakes of the generated methods, in a class no receiver below is: they make the name tier answer when nothing else does
cat > "$FIX/lib/mailbox.rb" <<'EOF'
class Mailbox
  def bills
    []
  end

  def dossier
    nil
  end

  def owner
    nil
  end

  def owner=( value )
    value
  end

  def email
    ""
  end

  def active
    true
  end

  def recent
    []
  end

  def summary
    ""
  end

  def logo
    nil
  end

  def customer
    nil
  end

  def total
    0
  end

  def premium
    false
  end
end
EOF

# ── the calls ─────────────────────────────────────────────────────────────────────────────────────────────────────────
cat > "$FIX/app/services/billing.rb" <<'EOF'
class Billing
  def run
    workspace = Workspace.new
    workspace.bills   # @typed_has_many
    workspace.dossier   # @typed_has_one
    workspace.owner   # @typed_belongs_to
    workspace.topics   # @typed_habtm
    workspace.owner = Patron.new   # @typed_writer
    workspace.build_dossier   # @typed_build
    workspace.reload_owner   # @typed_reload
    workspace.owner_changed?   # @typed_changed
    workspace.email   # @typed_delegate
    workspace.locale   # @typed_delegate_second
    workspace.dossier_currency   # @typed_delegate_prefix
    workspace.home_region   # @typed_delegate_named
    workspace.status_trial?   # @typed_enum_prefix
    workspace.basic?   # @typed_enum_value
    workspace.premium!   # @typed_enum_bang
    workspace.plan   # @typed_enum_attr
    workspace.logo   # @typed_attachment
    workspace.logo_attachment   # @typed_attachment_record
    workspace.dossier_attributes = {}   # @typed_nested
    workspace.customer   # @typed_alias_method
    workspace.buyer   # @typed_alias
    workspace.summary   # @typed_define_method
    workspace.archives   # @typed_concern
    Workspace.active   # @class_scope
    Workspace.where( id: 1 ).recent   # @relation_scope
    Workspace.archived   # @class_concern_scope
    Workspace.premium   # @class_enum_scope
    Workspace.not_basic   # @class_enum_not
    Workspace.status_paid   # @class_enum_prefix_scope
    Workspace.with_attached_logo   # @class_attachment_scope
    Enterprise.new.bills   # @sti_assoc
  end
end
EOF
cat > "$FIX/app/services/guards.rb" <<'EOF'
class Guards
  def untyped( record )
    record.bills   # @untyped_namesake
    record.topics   # @untyped_generated_only
  end

  def sides
    Workspace.new.active   # @instance_scope
    Workspace.bills   # @class_assoc
    Workspace.new.currency   # @prefix_raw
    Builder.drafts   # @body_dsl
  end

  def written
    Shipment.new.carrier   # @written_same_class
    Team.new.badges   # @written_in_mixin
  end
end
EOF
cat > "$FIX/app/services/gaps.rb" <<'EOF'
class Gaps
  def floors
    workspace = Workspace.new
    workspace.bills.first.total   # @assoc_chain
    Workspace.active.recent   # @scope_chain
    workspace.bill_ids   # @collection_ids
    Workspace.plans   # @enum_plural
    workspace.drafts   # @with_options
    Truck.new.wheels   # @super_written
    Kiosk.new.greeting   # @own_level
  end
end
EOF
cat > "$FIX/spec/factories/workspaces.rb" <<'EOF'
FactoryBot.define do
  factory :workspace do
  end
end
EOF
cat > "$FIX/spec/models/workspace_spec.rb" <<'EOF'
RSpec.describe Workspace do
  let( :workspace ) { create( :workspace ) }

  it "bills" do
    workspace.bills   # @let_assoc
    workspace.email   # @let_delegate
  end
end
EOF

# ── the map: well-formed, exit 0 ──────────────────────────────────────────────────────────────────────────────────────
MAP="$DIR/map.xml"
if "$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/map.err"
then
    ok "the map run exits 0"
else
    no "the map run exited non-zero: $( head -3 "$DIR/map.err" )"
fi
if command -v xmllint >/dev/null 2>&1
then
    if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi
fi

# The census (src/pincensus.h): one `C` row per call site the resolver decided or refused, so each arm reads ONE line; one
# `S` row per definition, its kind beside it.
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
# kindof ID — the kind the census's S row gives definition ID
kindof(){
    awk -F'\t' -v id="$1" '$1 == "S" && $2 == id { print $3; exit }' "$DIR/census.tsv"
}
# only FILE MARK CALLEE SYM KIND WHY — the marked call's one row binds SYM, a definition of kind KIND, and nothing else
only(){
    local n r; n="$( line "$1" "$2" )"
    [ -n "$n" ] || { no "fixture marker @$2 missing in $1"; return; }
    r="$( rows "$1" "$n" "$3" )"
    local t="${r#*$'\t'}"
    if [ "$( printf '%s\n' "$r" | grep -c . )" = 1 ] && [ "${t#*|}" = "$t" ] && printf '%s' "$t" | grep -qF "::$4#" \
        && [ "$( kindof "$t" )" = "$5" ]
    then
        ok "@$2 :$3 → $4 ($5) alone ($6)"
    else
        no "@$2 ($1:$n) :$3 does not reach $4 ($5) alone ($6); census: $( printf '%s' "$r" | tr '\t\n' '  ' ) kind: $( kindof "$t" )"
    fi
}
# norow FILE MARK CALLEE WHY — the census records no row for the marked call: no definition the resolver may consider names it
norow(){
    local n; n="$( line "$1" "$2" )"
    [ -n "$n" ] || { no "fixture marker @$2 missing in $1"; return; }
    if [ -z "$( rows "$1" "$n" "$3" )" ]
    then
        ok "@$2 :$3 has no row ($4)"
    else
        no "@$2 ($1:$n) :$3 has a row ($4); census: $( rows "$1" "$n" "$3" | tr '\t\n' '  ' )"
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
# misses FILE MARK CALLEE SYM WHY — SYM is not among the marked call's targets
misses(){
    local n; n="$( line "$1" "$2" )"
    [ -n "$n" ] || { no "fixture marker @$2 missing in $1"; return; }
    rows "$1" "$n" "$3" | cut -f2 | tr '|' '\n' | grep -qF "::$4#" && no "@$2 ($1:$n) :$3 reaches $4 — $5" \
        || ok "@$2 :$3 does not reach $4 ($5)"
}

census "$FIX" || exit 1
A=app/models/workspace.rb
B=app/services/billing.rb
G=app/services/guards.rb
P=app/services/gaps.rb
S=spec/models/workspace_spec.rb

echo "=== a typed receiver answers from the methods its class's declarations generate ==="
only    $B typed_has_many          bills               Workspace::bills               sec    "has_many :bills"
only    $B typed_has_one           dossier             Workspace::dossier             sec    "has_one :dossier"
only    $B typed_belongs_to        owner               Workspace::owner               sec    "belongs_to :owner"
only    $B typed_habtm             topics              Workspace::topics              sec    "has_and_belongs_to_many :topics"
only    $B typed_writer            owner=              Workspace::owner=              sec    "the association's writer"
only    $B typed_build             build_dossier       Workspace::build_dossier       sec    "has_one builds build_dossier"
only    $B typed_reload            reload_owner        Workspace::reload_owner        sec    "belongs_to's reload_owner"
only    $B typed_changed           owner_changed?      Workspace::owner_changed?      sec    "belongs_to's owner_changed?"
only    $B typed_delegate          email               Workspace::email               sec    "delegate :email, :locale, to: :owner"
only    $B typed_delegate_second   locale              Workspace::locale              sec    "…each name of it"
only    $B typed_delegate_prefix   dossier_currency    Workspace::dossier_currency    sec    "prefix: true names it after to:"
only    $B typed_delegate_named    home_region         Workspace::home_region         sec    "prefix: :home"
only    $B typed_enum_prefix       status_trial?       Workspace::status_trial?       sec    "enum :status, …, prefix: true"
only    $B typed_enum_value        basic?              Workspace::basic?              sec    "enum plan: { basic: 0 }"
only    $B typed_enum_bang         premium!            Workspace::premium!            sec    "an enum value's bang"
only    $B typed_enum_attr         plan                Workspace::plan                sec    "the enum's attribute"
only    $B typed_attachment        logo                Workspace::logo                sec    "has_one_attached :logo"
only    $B typed_attachment_record logo_attachment     Workspace::logo_attachment     sec    "…and its attachment record"
only    $B typed_nested            dossier_attributes= Workspace::dossier_attributes= sec    "accepts_nested_attributes_for :dossier"
only    $B typed_alias_method      customer            Workspace::customer            sec    "alias_method :customer, :owner"
only    $B typed_alias             buyer               Workspace::buyer               sec    "alias buyer owner"
only    $B typed_define_method     summary             Workspace::summary             sec    "define_method( :summary )"
only    $B typed_concern           archives            Archivable::archives           sec    "a concern's included do: has_many :archives"
only    $B sti_assoc               bills               Workspace::bills               sec    "Enterprise < Workspace: the superclass's association"
only    $S let_assoc               bills               Workspace::bills               sec    "a FactoryBot let builds a Workspace"
only    $S let_delegate            email               Workspace::email               sec    "…and its delegate"

echo "=== a class object and a relation answer from the scopes its declarations generate ==="
only    $B class_scope             active              Workspace::active              sec    "scope :active"
only    $B relation_scope          recent              Workspace::recent              sec    "Workspace.where( … ).recent: a relation answers its class's scope"
only    $B class_concern_scope     archived            Archivable::archived           sec    "a concern's included do: scope :archived is each includer's"
only    $B class_enum_scope        premium             Workspace::premium             sec    "an enum value's scope"
only    $B class_enum_not          not_basic           Workspace::not_basic           sec    "…and its not_ scope"
only    $B class_enum_prefix_scope status_paid         Workspace::status_paid         sec    "a prefixed enum's scope"
only    $B class_attachment_scope  with_attached_logo  Workspace::with_attached_logo  sec    "has_one_attached's with_attached_logo"

echo "=== a call to self answers from them ==="
only    $A self_assoc              bills               Workspace::bills               sec    "a bare bills in one of Workspace's methods"
only    $A self_scope              active              Workspace::active              sec    "a bare active in def self.dormant: the class object's scope"
only app/models/concerns/archivable.rb concern_self archives Archivable::archives sec "a concern's method calls what its included do generates"

echo "=== guards: what the lookup does not reach is left as before ==="
only    $G untyped_namesake        bills               Mailbox::bills                 method "an untyped receiver: the name tier, which never sees a generated method"
misses  $G untyped_namesake        bills               Workspace::bills                      "…so Workspace's bills is not among its targets"
norow   $G untyped_generated_only  topics                                                    "a name only a generated method carries is undefined to the name tier"
misses  $G instance_scope          active              Workspace::active                     "a scope is the class object's: an instance does not answer it"
misses  $G class_assoc             bills               Workspace::bills                      "an association reader is an instance's: the class object does not answer it"
misses  $G prefix_raw              currency            Workspace::currency                   "prefix: true renamed the delegate: currency is not generated"
refused $G body_dsl                drafts                                                    "a scope call inside a method body declares nothing: Builder's lookup misses, as before"
only    $G written_same_class      carrier             Shipment::carrier              method "a written def carrier answers before belongs_to :carrier's reader"
only    $G written_in_mixin        badges              Labelled::badges               method "a module Team includes answers before Team's has_many :badges (Rails includes its generated module first)"

echo "=== stated floors ==="
misses  $P assoc_chain             total               Bill::total                           "floor (a): an association's value is not typed"
misses  $P scope_chain             recent              Workspace::recent                     "floor (b): a scope's value is not typed as a relation"
norow   $P collection_ids          bill_ids                                                  "floor (c): a collection's _ids reader is not minted"
refused $P enum_plural             plans                                                     "floor (c): an enum's pluralized class method is not minted: Workspace's lookup misses"
norow   $P with_options            drafts                                                    "floor (d): a declaration inside with_options is not read"
only    $P super_written           wheels              Vehicle::wheels                method "floor (e): Vehicle's written wheels answers before Truck's has_many :wheels"
only    $P own_level               greeting            Greeter::greeting              method "floor (f): Greeter's written greeting answers before Kiosk's define_method"

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
