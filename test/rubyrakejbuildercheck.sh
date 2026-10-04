#!/usr/bin/env bash
# rubyrakejbuildercheck.sh — gate for the two plain-Ruby file kinds a Rails application holds besides `.rb`: a Rake task
# file (`lib/tasks/*.rake`) and a Jbuilder view (`app/views/**/*.json.jbuilder`). Both are Ruby, parsed by the Ruby
# grammar, and before this round neither was crawled: a method only a task or a JSON view called had no caller.
# THE RULE (ingest_crawl.h kLangTable; ingest_binds.h RubyBareCallWalk; graph.h RubyTopSelf; parser version 135):
#   * both extensions index as Ruby, with every Ruby rule the `.rb` files get (typed receivers, bare-word calls);
#   * outside any class, Ruby's self is what runs the file. Rake loads a `.rake` file at top level and calls a task's
#     block as written, so self there is `main`: a receiver-less call reaches a top-level def or a reopened Object,
#     Kernel or BasicObject, and no in-tree class's method. ActionView compiles a template into a method of the view, so
#     self in a `.jbuilder` template is the view: it also reaches each method of a helper module the application
#     defines (Rails' `helper :all`: the modules of the files under app/helpers/) and each controller method a
#     `helper_method` declaration names. Any other namesake — a partial's local (`badge` in `_badge.json.jbuilder`),
#     a route helper, ActionView's own — is refused as external, and so is a def in test code (filter.h
#     isTestSymbol: a def inside an example group's block has no class around it, and is the group's method);
#   * `json` in a template is the template's own JbuilderTemplate (the handler binds it), not a call: a call on it
#     (`json.summary …`, `json.partial! …`) is Jbuilder's — every key is a method_missing — and is refused as external
#     unless the tree opens JbuilderTemplate.
#
# Stated floors, each pinned below:
#   (a) `json.extract! user, :email` names attributes by symbol; they are not read as calls.
#   (b) a `.rb` file's top level is left as before: a block there may run with another self (`describe`,
#       `routes.draw`, `FactoryBot.define`), so a receiver-less call outside any class binds by name.
#
# Usage:  test/rubyrakejbuildercheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyrakejbuildercheck.sh
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
for d in app/controllers app/models app/helpers app/views/users lib/tasks script spec/support spec/views
do
    mkdir -p "$FIX/$d"
done

cat > "$FIX/app/controllers/users_controller.rb" <<'RUBY'
class UsersController < ApplicationController
  helper_method :contact_line

  def show
    @user = User.find( params[:id] )
  end

  private

  def contact_line
    "contact"
  end

  def secret_token
    "token"
  end
end
RUBY

cat > "$FIX/app/models/user.rb" <<'RUBY'
class User < ApplicationRecord
  def display_name
    "name"
  end
end
RUBY

cat > "$FIX/app/helpers/avatar_helper.rb" <<'RUBY'
module AvatarHelper
  def avatar_url_for( user )
    user.to_s
  end
end
RUBY

# a module named like a helper, outside app/helpers/: a spec's, which no view mixes in
cat > "$FIX/spec/support/api_helper.rb" <<'RUBY'
module ApiHelper
  def json_response
    {}
  end
end
RUBY

# a def inside an example group's block has no class around it, and is still the group's method: test code
cat > "$FIX/spec/views/show_spec.rb" <<'RUBY'
RSpec.describe "users/show" do
  def page_title
    "title"
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

cat > "$FIX/lib/indexer.rb" <<'RUBY'
class Indexer
  def rebuild
    true
  end

  def self.purge
    true
  end
end
RUBY

# Every name the fixture's calls might bind to by name alone: a Decoy target is a wrong edge.
cat > "$FIX/lib/decoy.rb" <<'RUBY'
class Decoy
  def json; end
  def summary; end
  def headline; end
  def email; end
  def badge; end
  def json_response; end
  def secret_token; end
  def avatar_url_for( u ); end
  def contact_line; end
  def rebuild; end
  def purge_stale; end
  def cleanup; end
  def report; end
end
RUBY

SHOW=app/views/users/show.json.jbuilder
cat > "$FIX/$SHOW" <<'RUBY'
json.id @user.id # @json_local
json.summary "x" # @json_key
json.display @user.display_name # @dotted
json.avatar avatar_url_for( @user ) # @helper
json.contact contact_line # @helper_method
json.token secret_token # @not_helper_method
json.api json_response # @spec_helper
json.site site_name # @root
json.title page_title # @test_def
json.extract! @user, :email # @extract_floor
json.partial! "users/badge", badge: @user # @partial
json.posts [ 1 ] do |post|
  json.headline post # @in_block
end
RUBY

BADGE=app/views/users/_badge.json.jbuilder
cat > "$FIX/$BADGE" <<'RUBY'
json.label badge # @partial_local
RUBY

RAKE=lib/tasks/search.rake
cat > "$FIX/$RAKE" <<'RUBY'
namespace :search do
  desc "Rebuild the index"
  task reindex: :environment do
    Indexer.new.rebuild # @rake_typed
    purge_stale # @rake_bare
    cleanup # @rake_main
  end
end

def purge_stale
  Indexer.purge
end
RUBY

# floor (b): the same receiver-less call from a `.rb` file's top level still binds by name
cat > "$FIX/script/report.rb" <<'RUBY'
report # @rb_top
RUBY

echo "=== the map: both file kinds are indexed, and the output is well-formed ==="
MAP="$DIR/a.xml"
if ! "$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/a.err"
then
    no "the default map exited non-zero: $( head -3 "$DIR/a.err" )"
fi
head -c 2000 "$MAP" | grep -o 'unindexed="[^"]*"' >"$DIR/unindexed" || true
if grep -qE 'rake|jbuilder' "$DIR/unindexed"
then
    no "the header still lists .rake or .jbuilder files as unindexed: $( cat "$DIR/unindexed" )"
else
    ok "neither .rake nor .jbuilder is in the header's unindexed= ($( cat "$DIR/unindexed" ))"
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

echo "=== a Rake task file is Ruby, and its top level's self is main ==="
reaches rebuild       Indexer::rebuild  $RAKE rake_typed "Indexer.new.rebuild in a task block — the typed receiver answers"
reaches purge_stale   purge_stale       $RAKE rake_bare  "a top-level def of the file: a method of main"
refused cleanup       $RAKE rake_main   "an in-tree class's method is no method of main"

echo "=== a Jbuilder template is Ruby, its json is Jbuilder's, and its self is the view ==="
absent  json          $SHOW json_local  "json is the template's local: no call named json"
refused summary       $SHOW json_key    "json.summary is a Jbuilder key (method_missing), not Decoy's"
refused headline      $SHOW in_block    "inside a block, json is still the template's"
reaches display_name  User::display_name $SHOW dotted "a call on a value reads as in any Ruby file"
reaches avatar_url_for AvatarHelper::avatar_url_for $SHOW helper "a helper module's method (app/helpers/): the view mixes it in"
reaches contact_line  UsersController::contact_line $SHOW helper_method "a controller method helper_method declares"
refused secret_token  $SHOW not_helper_method "a controller method no helper_method declares is not the view's"
refused json_response $SHOW spec_helper "a module outside app/helpers/ is not mixed into the view"
reaches site_name     Object::site_name $SHOW root "a reopened Object answers every self"
refused badge         $BADGE partial_local "a partial's local is no method of the view"
refused page_title    $SHOW test_def    "a def in test code (an example group's) is no method of the view"

echo "=== stated floors ==="
absent  email         $SHOW extract_floor "floor (a): extract!'s symbols are attribute names, not read as calls"
RB_TOP="$( rows script/report.rb "$( line script/report.rb rb_top )" report )"
printf '%s\n' "$RB_TOP" | grep -qF "::Decoy::report#" && ok "floor (b) pinned: script/report.rb's top-level report → Decoy::report" \
    || no "floor (b): script/report.rb's top-level report no longer binds to Decoy::report; census: $( printf '%s' "$RB_TOP" | tr '\t\n' ' ;' )"

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

echo "=== --callers: a helper_method's caller is the template ==="
"$BIN" "$FIX" --no-cache --callers=UsersController::contact_line >"$DIR/callers.xml" 2>/dev/null
grep -q 'show.json.jbuilder' "$DIR/callers.xml" && ok "--callers=UsersController::contact_line names show.json.jbuilder" \
    || no "--callers=UsersController::contact_line does not name the template: $( head -c 400 "$DIR/callers.xml" )"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
