#!/usr/bin/env bash
# rubyclassrecvcheck.sh — gate for a Ruby call on a CLASS: `Report.generate`, `User.where( … )`, `Report.new( 1 )`,
# `JSON.parse( s )`. The receiver is a constant, so the call is sent to the class object, and Ruby's lookup on it answers.
# Before this round such a call bound to whichever in-tree method had the name once the class itself missed it: Rails
# apps' `Hash.new`, `Date.new` and `Service.new` all bound to one controller's `new` action, a model's `where` to a mailer
# preview's mock.
# THE RULE (graph.h RubyTypedReceivers::closedLookup; ingest_binds.h classifyRubyReceiver; parser version 137):
#   * the class the tree opens at the constant answers from its lookup: the class's singleton methods (`def self.m`, a
#     def or an accessor in `class << self`), the modules it extends or includes (a concern's `class_methods do`, a nested
#     `module ClassMethods`), its superclasses' singleton methods, then a reopened Module, Class, Object, Kernel or
#     BasicObject. The shallowest that defines the name decides. A class's instance method is its instances' alone;
#   * `C.new` is Class#new unless a `def self.new` answers first, and Class#new runs the first `initialize` an instance's
#     lookup finds — never an instance method named `new` (a controller's action);
#   * when nothing there defines the name, Ruby's answer is outside the tree — ActiveRecord::Base's `where`,
#     StandardError's initialize — and the call is refused as external, never bound to an unrelated namesake;
#   * a constant the tree never opens (JSON, Time, RSpec, `Point = Struct.new( … )`) answers only from a reopened root;
#     a QUALIFIED constant names an in-tree class only when the tree opens that path (`Stripe::Customer` is not the
#     app's Customer);
#   * a class written below a base that forwards a class object's call to a new instance — a mailer's
#     (ActionMailer::Base, Devise::Mailer), ActiveSupport::CurrentAttributes — answers a name it lacks from its
#     instances' lookup: `UserMailer.welcome( u )` runs UserMailer#welcome;
#   * a class whose lookup holds a method_missing answers any name, and is left as before; so does a name a `class << self`
#     delegates (`delegate :reset, to: :instance`), a class method the tree indexes no def of;
#   * the constant is read as Ruby reads it from the call site, by fully-qualified constant (resolve.h's constant index):
#     lexically — the innermost class or module open around the site, its enclosing ones, the top level — then through
#     the ancestors of that open or of a qualified constant's head (`Sub::Failure` for a Failure Sub's superclass nests).
#     The lookup then walks what the class's superclasses and mixins resolve to, so two classes or modules of one name no
#     longer share it (`BankIntegration.process_event` reaches BankIntegration::HookMethods, not MailIntegration's;
#     `Result.new` inside `module Billing`, Billing::Result's initialize). A constant that names nothing the tree opens
#     from the site is outside it (`Row = Struct.new( … )` beside an unrelated in-tree Row);
#   * a namespace Zeitwerk makes of a directory is opened by no file: a constant whose last two segments or more are one
#     the tree opens names it (`Alerts::Senders::Pay` is the tree's `Senders::Pay`).
#
# Stated floors, each pinned below:
#   (a) a constant the tree assigns (`DEFAULT_LIMITS = Limits.new`) is a value of a class the tree does not type: a
#       call on it binds by name as before.
#   (b) the tree does not tell `include` from `extend`: an included module's instance method answers a call on the class —
#       unless the module nests a `module ClassMethods`, which makes it a concern whose class methods live there.
#   (c) a module's every method answers a call on the module: `module_function` and `extend self` are not read, so a
#       method without either answers too.
#   (d) a tree with no Ruby superclass, mixin or constant reference keeps no constant index: there a constant is read by
#       its final segment, a qualified one only where the tree opens that path, and two classes of one name share a lookup.
#   (e) a module mixed in at run time — `Tool.extend( Tool::Ext )` written as a call on the constant, not a class-body
#       directive — is in no lookup: a call it answers is refused.
#   (f) a class `Struct.new( … ) do … end` or `Data.define( … ) do … end` builds is opened by no file: a def in its block
#       (`def self.from`) answers no call on its constant, which is refused.
#   (g) `class << Clock` opens another object's singleton: its defs read as top-level defs, which no call with a receiver
#       reaches, so `Clock.tick` is refused (activesupport's `class << Benchmark; def ms`).
#
# Usage:  test/rubyclassrecvcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyclassrecvcheck.sh
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
for d in app/mailers app/models app/services app/services/alerts/senders lib/billing lib/shipping lib/mail_integration lib/bank_integration spec
do
    mkdir -p "$FIX/$d"
done

cat > "$FIX/lib/report.rb" <<'RUBY'
class Report
  extend Finders
  include Searchable
  include Taggable
  include Archivable
  include Printable
  include Strikes

  def self.generate( n )
    n
  end

  def initialize( n )
    @n = n
  end

  def render
    "r"
  end
end
RUBY

cat > "$FIX/lib/child_report.rb" <<'RUBY'
class ChildReport < Report
end
RUBY

cat > "$FIX/lib/finders.rb" <<'RUBY'
module Finders
  def lookup( id )
    id
  end
end
RUBY

cat > "$FIX/lib/searchable.rb" <<'RUBY'
module Searchable
  extend ActiveSupport::Concern

  class_methods do
    def search( q )
      q
    end
  end
end
RUBY

cat > "$FIX/lib/taggable.rb" <<'RUBY'
module Taggable
  def self.included( base )
    base.extend ClassMethods
  end

  module ClassMethods
    def tagged_with( t )
      t
    end
  end
end
RUBY

# ActiveSupport::Concern extends a concern's nested ClassMethods onto every includer without a written `extend`
cat > "$FIX/lib/archivable.rb" <<'RUBY'
module Archivable
  extend ActiveSupport::Concern

  module ClassMethods
    def archived
      []
    end
  end
end
RUBY

# another concern's ClassMethods of the same name, which Report never includes
cat > "$FIX/lib/purgeable.rb" <<'RUBY'
module Purgeable
  extend ActiveSupport::Concern

  module ClassMethods
    def archived
      []
    end
  end
end
RUBY

cat > "$FIX/app/mailers/application_mailer.rb" <<'RUBY'
class ApplicationMailer < ActionMailer::Base
end
RUBY

cat > "$FIX/app/mailers/user_mailer.rb" <<'RUBY'
class UserMailer < ApplicationMailer
  def welcome( u )
    u
  end
end
RUBY

cat > "$FIX/app/models/current.rb" <<'RUBY'
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end
RUBY

cat > "$FIX/app/models/application_record.rb" <<'RUBY'
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
RUBY

cat > "$FIX/app/models/user.rb" <<'RUBY'
class User < ApplicationRecord
  def self.admins
    where( admin: true )
  end
end
RUBY

cat > "$FIX/app/models/customer.rb" <<'RUBY'
class Customer < ApplicationRecord
  def self.create_from( params )
    params
  end
end
RUBY

cat > "$FIX/lib/billing/invoice.rb" <<'RUBY'
module Billing
  class Invoice
    def self.issue( n )
      n
    end
  end
end
RUBY

cat > "$FIX/lib/errors.rb" <<'RUBY'
class ValidationFailed < StandardError
end

class Base
  class Failure < StandardError
    def initialize( m )
      super
    end
  end
end

class Sub < Base
end
RUBY

cat > "$FIX/lib/core_ext.rb" <<'RUBY'
class Module
  def cached_name
    name
  end
end

class Time
  def self.zone_now
    now
  end
end
RUBY

cat > "$FIX/lib/limits.rb" <<'RUBY'
class Limits
  def fetch_limit( k )
    k
  end
end

DEFAULT_LIMITS = Limits.new
RUBY

cat > "$FIX/lib/dynamic.rb" <<'RUBY'
class Dynamic
  def self.method_missing( name, *args )
    name
  end
end
RUBY

cat > "$FIX/lib/builder.rb" <<'RUBY'
class Builder
  def self.new( *args )
    super
  end

  def initialize( x )
    @x = x
  end
end
RUBY

# a class method and an instance method of one name, the instance half in a reopening
cat > "$FIX/lib/service.rb" <<'RUBY'
class Service
  def self.call( x )
    new( x ).call
  end
end
RUBY

cat > "$FIX/lib/service_instance.rb" <<'RUBY'
class Service
  def initialize( x )
    @x = x
  end

  def call
    @x
  end
end
RUBY

cat > "$FIX/lib/settings.rb" <<'RUBY'
class Settings
  class << self
    attr_accessor :config

    def build_all
      []
    end
  end

  attr_reader :label
end
RUBY

# an instance method named new, as a controller's action is
cat > "$FIX/lib/pipeline.rb" <<'RUBY'
class Pipeline
  def initialize( steps )
    @steps = steps
  end

  def new
    "an action named new"
  end
end
RUBY

# a concern with an instance method and a ClassMethods method of one name
cat > "$FIX/lib/strikes.rb" <<'RUBY'
module Strikes
  extend ActiveSupport::Concern

  def strike?
    false
  end

  module ClassMethods
    def strike?
      true
    end
  end
end
RUBY

cat > "$FIX/lib/printable.rb" <<'RUBY'
module Printable
  def print_me
    "p"
  end
end
RUBY

cat > "$FIX/lib/util.rb" <<'RUBY'
module Util
  def helper
    1
  end
end
RUBY

cat > "$FIX/lib/registry.rb" <<'RUBY'
class Registry
  class << self
    delegate :reset, to: :instance

    def instance
      @instance ||= new
    end
  end

  def reset
    true
  end
end
RUBY

# Zeitwerk: app/services/alerts/senders/ is the namespace Alerts::Senders, which no file opens
cat > "$FIX/app/services/alerts/senders/pay.rb" <<'RUBY'
module Alerts
  class Senders::Pay
    def self.done?( x )
      x
    end
  end
end
RUBY

# two modules of one name, each extended by its own integration
for m in Mail Bank
do
    f="$( printf '%s' "$m" | tr 'A-Z' 'a-z' )_integration"
    printf 'module %sIntegration\n  extend HookMethods\nend\n' "$m" > "$FIX/lib/$f.rb"
    printf 'module %sIntegration\n  module HookMethods\n    def process_event( id )\n      id\n    end\n  end\nend\n' "$m" > "$FIX/lib/$f/hook_methods.rb"
done

# two classes of one name; a call inside `module Billing` names Billing's
cat > "$FIX/lib/billing/result.rb" <<'RUBY'
module Billing
  class Result
    def initialize( a )
      @a = a
    end
  end
end
RUBY

cat > "$FIX/lib/shipping/result.rb" <<'RUBY'
module Shipping
  class Result
    def initialize( b )
      @b = b
    end
  end
end
RUBY

cat > "$FIX/lib/billing/charge.rb" <<'RUBY'
module Billing
  class Charge
    def settle
      Result.new( 1 ) # @lexical_new
    end
  end
end
RUBY

# a Struct constant local to a class, beside an unrelated in-tree class of that name
cat > "$FIX/lib/exporter.rb" <<'RUBY'
class Exporter
  Row = Struct.new( :a )

  def run
    Row.new( 1 ) # @struct_local
  end
end
RUBY

cat > "$FIX/lib/reports_row.rb" <<'RUBY'
module Reports
  class Row
    def initialize( x )
      @x = x
    end
  end
end
RUBY

# floor (e): a module extended at run time
cat > "$FIX/lib/tool.rb" <<'RUBY'
module Tool
  module Ext
    def tool_reset
      true
    end
  end
end

Tool.extend( Tool::Ext )
RUBY

# floor (f): a def in a Data.define block
cat > "$FIX/lib/filters.rb" <<'RUBY'
class Selection
  Filters = Data.define( :search ) do
    def self.from( h )
      new( search: h[:search] )
    end
  end

  def build( h )
    Filters.from( h ) # @data_block_floor
  end
end
RUBY

# floor (g): another object's singleton class, opened from outside it
cat > "$FIX/lib/clock_ext.rb" <<'RUBY'
class << Clock
  def tick
    1
  end
end
RUBY

cat > "$FIX/lib/helpers.rb" <<'RUBY'
def format_amount( n )
  n.to_s
end
RUBY

# Every name the fixture's calls might bind to by name alone: a Decoy target is a wrong edge.
cat > "$FIX/lib/decoy.rb" <<'RUBY'
class Decoy
  def where( *a ); end
  def find_by( *a ); end
  def parse( s ); end
  def now; end
  def new( *a ); end
  def create_from( p ); end
  def lookup( id ); end
  def search( q ); end
  def tagged_with( t ); end
  def describe( *a ); end
  def anything; end
  def format_amount( n ); end
  def cached_name; end
  def zone_now; end
  def archived; end
  def render; end
  def label; end
  def welcome( u ); end
  def user=( u ); end
  def done?( x ); end
  def tool_reset; end
  def from( h ); end
end
RUBY

CALLER=app/services/caller.rb
cat > "$FIX/$CALLER" <<'RUBY'
class Caller
  def run( s )
    Report.generate( 1 ) # @own
    ChildReport.generate( 2 ) # @inherited
    Report.lookup( 3 ) # @extended
    Report.search( "q" ) # @concern
    Report.tagged_with( "t" ) # @class_methods
    Report.archived # @concern_class_methods
    Billing::Invoice.issue( 4 ) # @qualified_opened
    Customer.create_from( {} ) # @customer
    Report.new( 5 ) # @new
    ChildReport.new( 6 ) # @new_inherited
    ValidationFailed.new( "x" ) # @new_out_of_tree
    Point.new( 1, 2 ) # @struct
    User.where( admin: true ) # @ar_where
    User.find_by( id: 1 ) # @ar_find_by
    Stripe::Customer.create_from( {} ) # @qualified_not_opened
    JSON.parse( s ) # @json
    Time.now # @time
    Time.zone_now # @time_reopened
    Report.cached_name # @root_module
    JSON.cached_name # @root_external
    Report.format_amount( 7 ) # @private_top
    Dynamic.anything # @missing
    DEFAULT_LIMITS.fetch_limit( :a ) # @value_floor
    Service.call( 9 ) # @singleton
    Settings.config # @singleton_accessor
    Settings.build_all # @singleton_class
    Settings.label # @instance_accessor
    Report.render # @instance
    Pipeline.new( [] ) # @new_action
    Builder.new( 8 ) # @self_new
    Report.print_me # @include_floor
    Util.helper # @module_floor
    UserMailer.welcome( 10 ) # @mailer
    Current.user = 11 # @current
    Registry.reset # @class_delegate
    Alerts::Senders::Pay.done?( 12 ) # @zeitwerk
    BankIntegration.process_event( 13 ) # @fqn_mixin
    Billing::Result.new( 14 ) # @qualified_new
    Tool.tool_reset # @runtime_extend_floor
    Report.strike? # @concern_precedence
    Clock.tick # @foreign_singleton_floor
    Sub::Failure.new( "m" ) # @ancestor_const
  end
end

Point = Struct.new( :x, :y )
RUBY

SPEC=spec/report_spec.rb
cat > "$FIX/$SPEC" <<'RUBY'
RSpec.describe Report do # @rspec_describe
  it "generates" do
    described_class.generate( 1 ) # @described
  end
end

RSpec.describe Billing::Invoice do
  it "issues" do
    described_class.issue( 2 ) # @described_qualified
  end
end

RSpec.describe Billing do
  it "issues through the namespace" do
    described_class::Invoice.issue( 3 ) # @described_path
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
# reaches CALLEE SYM FILE MARK WHY — the CALLEE call on the marked line resolves to SYM, and to no Decoy
reaches(){
    local n r; n="$( line "$3" "$4" )"
    [ -n "$n" ] || { no "fixture marker @$4 missing in $3"; return; }
    r="$( rows "$3" "$n" "$1" )"
    if printf '%s\n' "$r" | grep -qF "::$2#" && ! printf '%s\n' "$r" | grep -qF "::Decoy::"
    then
        ok "@$4 :$1 → $2 ($5)"
    else
        no "@$4 ($3:$n) :$1 does not reach $2 alone ($5); census: $( printf '%s' "$r" | tr '\t\n' ' ;' )"
    fi
}
# only CALLEE SYM FILE MARK WHY — the CALLEE call on the marked line has one target, SYM (a trailing id path, or a whole
# `file::id` one)
only(){
    local n r t; n="$( line "$3" "$4" )"
    [ -n "$n" ] || { no "fixture marker @$4 missing in $3"; return; }
    r="$( rows "$3" "$n" "$1" )"
    t="$( printf '%s\n' "$r" | cut -f2 | tr '|' '\n' | grep . | sed 's/#[0-9]*$//' )"
    if [ "$( printf '%s\n' "$t" | grep -c . )" -eq 1 ] && { [ "$t" = "$2" ] || [ "${t%::$2}" != "$t" ]; }
    then
        ok "@$4 :$1 → $2 alone ($5)"
    else
        no "@$4 ($3:$n) :$1 does not reach $2 alone ($5); census: $( printf '%s' "$r" | tr '\t\n' ' ;' )"
    fi
}
# refused CALLEE FILE MARK WHY — the CALLEE call on the marked line is recorded and refused as external
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

echo "=== the class the tree opens answers: its methods, its mixins', its superclasses' ==="
only    generate      Report::generate        $CALLER own              "the class's own def self.generate"
only    generate      Report::generate        $CALLER inherited        "a superclass's class method"
only    lookup        Finders::lookup         $CALLER extended         "a module the class extends"
only    search        Searchable::search      $CALLER concern          "a concern's class_methods block"
only    tagged_with   ClassMethods::tagged_with $CALLER class_methods  "a nested module ClassMethods the concern extends onto its includer"
only    strike?       ClassMethods::strike?   $CALLER concern_precedence "a concern's ClassMethods, not its instance method of the name"
only    archived      lib/archivable.rb::ClassMethods::archived $CALLER concern_class_methods "the ClassMethods of the concern Report includes, not another concern's"
only    issue         Invoice::issue          $CALLER qualified_opened "a qualified constant whose path the tree opens"
only    process_event lib/bank_integration/hook_methods.rb::HookMethods::process_event $CALLER fqn_mixin "BankIntegration's own HookMethods, not MailIntegration's of that name"
only    new           lib/billing/result.rb::Result::initialize lib/billing/charge.rb lexical_new "Result inside module Billing is Billing::Result, not Shipping's"
only    new           lib/billing/result.rb::Result::initialize $CALLER qualified_new "Billing::Result, from outside the namespace"
only    done?         Pay::done?              $CALLER zeitwerk         "Alerts::Senders::Pay ends in Senders::Pay, a path the tree opens"
only    create_from   Customer::create_from   $CALLER customer         "the app's own Customer"
only    generate      Report::generate        $SPEC   described        "described_class is the group's class"
only    issue         Invoice::issue          $SPEC   described_qualified "a qualified described class is read whole"
only    issue         Invoice::issue          $SPEC   described_path   "described_class::Invoice is Billing::Invoice"

echo "=== a class's instance method is its instances' alone ==="
only    call          lib/service.rb::Service::call $CALLER singleton  "def self.call, not the instance call a reopening defines"
only    config        Settings::config        $CALLER singleton_accessor "an accessor class << self declares"
only    build_all     Settings::build_all     $CALLER singleton_class  "a def in class << self"
refused label         $CALLER instance_accessor "an instance attr_reader is no method of the class object"
refused render        $CALLER instance          "Report#render is Report's instances'"

echo "=== a base that forwards to an instance: the instances' lookup answers ==="
only    welcome       UserMailer::welcome     $CALLER mailer           "ActionMailer::Base's class object runs the instance method"
only    user=         Current::user=          $CALLER current          "ActiveSupport::CurrentAttributes forwards to the instance"

echo "=== C.new runs initialize ==="
only    new           Report::initialize      $CALLER new              "Report.new reaches Report#initialize, never a method named new"
only    new           Report::initialize      $CALLER new_inherited    "a subclass with no initialize reaches its superclass's"
refused new           $CALLER new_out_of_tree "StandardError's initialize is outside the tree"
refused new           $CALLER struct          "Point = Struct.new: the tree never opens Point"
refused new           lib/exporter.rb struct_local "Exporter::Row is a Struct: Reports::Row is no constant Exporter names"
only    new           Pipeline::initialize    $CALLER new_action       "an instance method named new (a controller's action) is no Class#new"
only    new           Builder::new            $CALLER self_new         "a def self.new answers first"

echo "=== a lookup that leaves the tree is refused, never handed to a namesake ==="
refused where         $CALLER ar_where        "User.where is ActiveRecord::Base's"
refused find_by       $CALLER ar_find_by      "User.find_by is ActiveRecord::Base's"
refused create_from   $CALLER qualified_not_opened "Stripe::Customer is not the app's Customer: the tree never opens that path"
refused parse         $CALLER json            "JSON is never opened"
refused now           $CALLER time            "Time is opened, and its opening defines no now"
only    zone_now      Time::zone_now          $CALLER time_reopened    "a class the tree reopens answers from the reopening"
refused describe      $SPEC   rspec_describe  "RSpec is never opened"
refused format_amount $CALLER private_top     "a top-level def is a private method of Object: no receiver may call it"

echo "=== a reopened root answers every class object ==="
only    cached_name   Module::cached_name     $CALLER root_module      "a class is a Module"
only    cached_name   Module::cached_name     $CALLER root_external    "so is a class the tree never opens"

echo "=== a method_missing, or a class << self delegation, answers the name: left as before ==="
DELEG="$( rows $CALLER "$( line $CALLER class_delegate )" reset )"
if printf '%s\n' "$DELEG" | grep -qF "::Registry::reset#"
then
    ok "@class_delegate :reset binds by name as before (a class << self delegates it)"
else
    no "@class_delegate :reset no longer binds by name; census: $( printf '%s' "$DELEG" | tr '\t\n' ' ;' )"
fi
MISSING="$( rows $CALLER "$( line $CALLER missing )" anything )"
if printf '%s\n' "$MISSING" | grep -qF "::Decoy::anything#"
then
    ok "@missing :anything binds by name as before (Dynamic answers any name)"
else
    no "@missing :anything no longer binds by name; census: $( printf '%s' "$MISSING" | tr '\t\n' ' ;' )"
fi

echo "=== stated floors ==="
only    fetch_limit   Limits::fetch_limit     $CALLER value_floor      "floor (a): a constant the tree assigns binds by name"
only    print_me      Printable::print_me     $CALLER include_floor    "floor (b): an included module's method answers a call on the class"
refused tool_reset    $CALLER runtime_extend_floor "floor (e): Tool.extend( Tool::Ext ) at run time is in no lookup"
refused from          lib/filters.rb data_block_floor "floor (f): Filters = Data.define do … end is opened by no file"
refused tick          $CALLER foreign_singleton_floor "floor (g): class << Clock is no open of Clock"
only    helper        Util::helper            $CALLER module_floor     "floor (c): a module's method answers a call on the module"
only    new           Failure::initialize     $CALLER ancestor_const   "Sub::Failure is Base::Failure, through Sub's superclass"

# floor (d): a tree with no superclass, mixin or constant reference keeps no constant index
FIX2="$DIR/noindex"; mkdir -p "$FIX2"
printf 'module Alpha\n  class Row\n    def initialize( a )\n      @a = a\n    end\n  end\nend\n' > "$FIX2/alpha.rb"
printf 'module Beta\n  class Row\n    def initialize( b )\n      @b = b\n    end\n  end\nend\n' > "$FIX2/beta.rb"
printf 'class Caller\n  def run\n    Alpha::Row.new( 1 )\n  end\nend\n' > "$FIX2/caller.rb"
if "$BIN" "$FIX2" --no-cache --pin-census="$DIR/noindex.tsv" >/dev/null 2>&1
then
    NOIX="$( awk -F'\t' '$1 == "C" && $7 == "new" && index( $6, "caller.rb::" ) == 1 { print $8 }' "$DIR/noindex.tsv" )"
    if printf '%s' "$NOIX" | grep -qF "alpha.rb::Row::initialize#" && printf '%s' "$NOIX" | grep -qF "beta.rb::Row::initialize#"
    then
        ok "floor (d) pinned: with no constant index, Alpha::Row.new splits over both Rows' initialize"
    else
        no "floor (d): with no constant index, Alpha::Row.new no longer splits over both Rows; census: $NOIX"
    fi
else
    no "--pin-census on the no-index fixture exited non-zero"
fi

echo "=== determinism and warm == cold ==="
"$BIN" "$FIX" --no-cache >"$DIR/b.xml" 2>/dev/null
if cmp -s "$MAP" "$DIR/b.xml"
then
    ok "byte-identical across two --no-cache runs"
else
    no "output differs across runs"
fi
if ! "$BIN" "$FIX" --cache="$DIR/c.bin" >"$DIR/cold.xml" 2>"$DIR/cold.err"
then
    no "the cold cache run exited non-zero: $( head -3 "$DIR/cold.err" )"
fi
if ! "$BIN" "$FIX" --cache="$DIR/c.bin" >"$DIR/warm.xml" 2>"$DIR/warm.err"
then
    no "the warm cache run exited non-zero: $( head -3 "$DIR/warm.err" )"
fi
if cmp -s "$DIR/cold.xml" "$DIR/warm.xml"
then
    ok "warm run == cold run"
else
    no "the warm cache disagrees with the cold run"
fi

echo "=== --callers: Report.new is a caller of Report#initialize ==="
"$BIN" "$FIX" --no-cache --callers=Report::initialize >"$DIR/callers.xml" 2>/dev/null
if grep -q 'caller.rb' "$DIR/callers.xml"
then
    ok "--callers=Report::initialize names app/services/caller.rb"
else
    no "--callers=Report::initialize does not name the caller: $( head -c 400 "$DIR/callers.xml" )"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
