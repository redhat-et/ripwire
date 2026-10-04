#!/usr/bin/env bash
# rubydeclrefcheck.sh — gate for a Ruby method named by a SYMBOL that Rails or Ruby later calls. `before_action
# :authenticate`, `after_save :reindex`, `validate :name_present`, `rescue_from …, with: :not_found`, an `if:` / `unless:`
# condition, and `send( :render_user )` / `try( :assist )` / `method( :log_one )`: each names a method the framework calls
# on that object, but nothing in the source CALLS it, so before this round every callback method in a Rails app had no
# caller — it looked dead, ranked as a leaf, and `--callers` answered nothing.
# THE RULE (ingest_binds.h RubyBareCallWalk::noteDeclaredCalls; parser version 134): the symbol is a call to that method,
#   * for a callback macro at class-body position — receiver-less, its nearest enclosing def-or-class wall a class or
#     module body (an `included do` block inside a concern counts) — its positional symbols, and the symbols of its `if:`,
#     `unless:` (a symbol or an array of them) and, for `rescue_from`, `with:` options; for `validates`/`validates_*_of`
#     only the `if:`/`unless:` options (its positional symbols are attributes). Ruby's self there is the class, and the
#     callback runs on its instances, whose lookup is the class's: the call resolves like any call to self from the class
#     body (rubyreachcheck);
#   * for `send`/`public_send`/`__send__`/`try`/`try!`/`method` whose first argument is a literal symbol — a call to that
#     method on the same receiver, typed or not (`helper.try( :assist )` answers from Helper, rubytypedrecvcheck).
#
# Stated floors, each pinned below:
#   (a) option values that are not calls make none: `only:`/`except:` (action names), `on:` (an event), `prepend:`; and
#       `validates`' attribute names make none.
#   (b) `skip_before_action :x` removes a callback and calls nothing: no reference.
#   (c) `set_callback :save, :before, :x` and other ActiveSupport::Callbacks plumbing are not read.
#   (d) a string or computed name (`send( "render_user" )`, `send( name )`) is not read.
#   (e) a callback macro inside a method body is not read (it is not at class-body position).
#
# Usage:  test/rubydeclrefcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubydeclrefcheck.sh
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
for d in app/controllers app/models/concerns app/jobs app/helpers lib
do
    mkdir -p "$FIX/$d"
done

cat > "$FIX/app/controllers/application_controller.rb" <<'RUBY'
class ApplicationController < ActionController::Base
  before_action :authenticate # @before_action
  rescue_from ActiveRecord::RecordNotFound, with: :not_found # @rescue_with

  private

  def authenticate
    true
  end

  def ensure_admin
    true
  end

  def not_found
    :not_found
  end
end
RUBY
cat > "$FIX/app/controllers/users_controller.rb" <<'RUBY'
class UsersController < ApplicationController
  before_action :load_user, only: [ :show ] # @only_floor
  before_action :ensure_admin # @inherited_cb
  before_action :authenticate_user! # @generated
  after_action :track, if: :tracking? # @after_if
  around_action :with_locale, except: :index # @around
  skip_before_action :authenticate # @skip_floor
  set_callback :process_action, :before, :set_trace # @set_callback_floor

  def show
    send( :render_user ) # @send_bare
    send( "render_user" ) # @send_string_floor
    helper = Helper.new
    helper.try( :assist ) # @try_typed
    [ 1 ].each( &method( :log_one ) ) # @method_ref
  end

  def self.configure
    before_action :late_hook # @in_def_floor
  end

  def index
    :index
  end

  private

  def load_user
    true
  end

  def track
    true
  end

  def tracking?
    true
  end

  def with_locale
    yield
  end

  def render_user
    true
  end

  def log_one( x )
    x
  end

  def set_trace
    true
  end

  def late_hook
    true
  end
end
RUBY
cat > "$FIX/app/helpers/helper.rb" <<'RUBY'
class Helper
  def assist
    :helper
  end
end
RUBY
cat > "$FIX/app/models/application_record.rb" <<'RUBY'
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
RUBY
cat > "$FIX/app/models/user.rb" <<'RUBY'
class User < ApplicationRecord
  include Auditable
  before_save :normalize_name # @before_save
  after_commit :reindex, on: :create # @on_floor
  validate :name_present # @validate
  validates :email, presence: true, unless: :guest? # @validates_unless
  before_validation :trim_name, :lower_email # @two_symbols
  after_create_commit :notify_team, if: [ :active?, :confirmed? ] # @if_array

  def normalize_name
    true
  end

  def reindex
    true
  end

  def name_present
    true
  end

  def guest?
    false
  end

  def trim_name
    true
  end

  def lower_email
    true
  end

  def notify_team
    true
  end

  def active?
    true
  end

  def confirmed?
    true
  end
end
RUBY
cat > "$FIX/app/models/concerns/auditable.rb" <<'RUBY'
module Auditable
  extend ActiveSupport::Concern

  included do
    after_save :write_audit # @concern_cb
  end

  def write_audit
    true
  end
end
RUBY
cat > "$FIX/app/jobs/sync_job.rb" <<'RUBY'
class SyncJob < ApplicationJob
  before_perform :check_lock # @job_cb

  def perform
    true
  end

  def check_lock
    true
  end
end
RUBY
# the namesakes a wrong reading would bind to: every name above, on a class outside every caller's reach
cat > "$FIX/lib/decoy.rb" <<'RUBY'
class Decoy
  def authenticate; end
  def not_found; end
  def ensure_admin; end
  def authenticate_user!; end
  def load_user; end
  def track; end
  def tracking?; end
  def with_locale; end
  def render_user; end
  def assist; end
  def log_one( x ); end
  def set_trace; end
  def late_hook; end
  def normalize_name; end
  def reindex; end
  def name_present; end
  def guest?; end
  def trim_name; end
  def lower_email; end
  def notify_team; end
  def active?; end
  def confirmed?; end
  def write_audit; end
  def check_lock; end
  def show; end
  def index; end
  def create; end
  def email; end
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
# absent CALLEE FILE MARK WHY — no CALLEE call is recorded on the marked line (a Decoy namesake would catch one)
absent(){
    local n r; n="$( line "$2" "$3" )"
    [ -n "$n" ] || { no "fixture marker @$3 missing in $2"; return; }
    r="$( rows "$2" "$n" "$1" )"
    if [ -z "$r" ]
    then
        ok "@$3 makes no :$1 call ($4)"
    else
        no "@$3 ($2:$n) records a :$1 call ($4); census: $( printf '%s' "$r" | tr '\t\n' ' ;' )"
    fi
}

census "$FIX" || exit 1

AC=app/controllers/application_controller.rb
UC=app/controllers/users_controller.rb
UM=app/models/user.rb

echo "=== a callback names a method the framework calls on the class's instances ==="
reaches authenticate  ApplicationController::authenticate $AC before_action "before_action :authenticate — the class's own method"
reaches not_found     ApplicationController::not_found    $AC rescue_with   "rescue_from …, with: :not_found"
reaches load_user     UsersController::load_user          $UC only_floor    "before_action :load_user"
reaches ensure_admin  ApplicationController::ensure_admin $UC inherited_cb  "a callback in a subclass reaches the superclass's method"
refused authenticate_user! $UC generated "a method the tree does not define in reach (Devise's) is refused, not bound to Decoy's"
reaches track         UsersController::track              $UC after_if      "after_action :track"
reaches tracking?     UsersController::tracking?          $UC after_if      "if: :tracking? — the condition is called too"
reaches with_locale   UsersController::with_locale        $UC around        "around_action :with_locale"
reaches normalize_name User::normalize_name               $UM before_save   "before_save :normalize_name"
reaches reindex       User::reindex                       $UM on_floor      "after_commit :reindex"
reaches name_present  User::name_present                  $UM validate      "validate :name_present"
reaches guest?        User::guest?                        $UM validates_unless "validates …, unless: :guest?"
reaches trim_name     User::trim_name                     $UM two_symbols   "before_validation's first symbol"
reaches lower_email   User::lower_email                   $UM two_symbols   "… and its second"
reaches notify_team   User::notify_team                   $UM if_array      "after_create_commit :notify_team"
reaches active?       User::active?                       $UM if_array      "if: [ :active?, … ] — each symbol of the array"
reaches confirmed?    User::confirmed?                    $UM if_array      "… and the next"
reaches write_audit   Auditable::write_audit              app/models/concerns/auditable.rb concern_cb "a concern's included do block runs in the including class"
reaches check_lock    SyncJob::check_lock                 app/jobs/sync_job.rb job_cb "before_perform :check_lock"

echo "=== send and its kin call the named method on the same receiver ==="
reaches render_user   UsersController::render_user        $UC send_bare     "send( :render_user ) is a call to self"
reaches assist        Helper::assist                      $UC try_typed     "helper.try( :assist ) on a Helper — the typed receiver answers"
reaches log_one       UsersController::log_one            $UC method_ref    "method( :log_one ) names self's log_one"

echo "=== floors ==="
absent  show          $UC only_floor    "floor (a): only: [ :show ] names actions, calls none"
absent  index         $UC around        "floor (a): except: :index names an action"
absent  create        $UM on_floor      "floor (a): on: :create is an event"
absent  email         $UM validates_unless "floor (a): validates' :email is an attribute"
absent  authenticate  $UC skip_floor    "floor (b): skip_before_action removes a callback"
absent  set_trace     $UC set_callback_floor "floor (c): set_callback is not read"
absent  render_user   $UC send_string_floor  "floor (d): a string name is not read"
absent  late_hook     $UC in_def_floor  "floor (e): a callback macro inside a def is not at class-body position"

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

echo "=== --callers: a callback method has its class as a caller ==="
"$BIN" "$FIX" --no-cache --callers=User::normalize_name >"$DIR/callers.xml" 2>/dev/null
grep -q 'n="User"' "$DIR/callers.xml" && ok "--callers=User::normalize_name names User" \
    || no "--callers=User::normalize_name does not name User: $( head -c 400 "$DIR/callers.xml" )"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
