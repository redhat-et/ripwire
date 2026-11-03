#!/usr/bin/env bash
# rubycolumncheck.sh — gate for a db/schema.rb COLUMN as a reader of its model (docs/research/ruby-roadmap.md R3b, the
# follow-up #339's review left open: "bind a column only when the receiver is shown to be that model"). A rendered schema's
# `t.string "label"` in `create_table "parcels"` is the attribute reader `label` every Parcel instance answers, and #339
# made it a definition with no call edges: `Parcel.find( id ).label`, a bare `label` in one of Parcel's methods and
# `self.weight` found nothing in Parcel's lookup.
# THE RULE (ingest_ruby.h captureRubyTables, src/ruby_generated.h buildRubyGenerated; parser version 279):
#   * a model's table is the one its class body names with `self.table_name =`; else, for a class written
#     `< ApplicationRecord`, its name underscored and pluralized (+s, +es after s/x/z/ch/sh, a consonant's y to ies);
#   * each column of that table answers the model's instance lookup as a reader, as a method Rails generates does (R3,
#     test/rubygeneratedcheck.sh): only once the lookup reached the class (a call to self, a receiver the code builds), and
#     only when no written method or generated declaration answers (a written `def status`, an enum's `priority`);
#   * an STI subclass reads its base class's table, by the same lookup walk;
#   * the name tier is unchanged: an untyped `record.label` is decided as before (#339's measurements stay pinned there).
#
# Stated floors, each pinned below:
#   (a) a column's writer (`label=`), predicate (`label?`) and dirty-tracking affixes are not minted;
#   (b) Rails' irregular and uncountable plurals are not ported: `Sheep` reads no `sheep` table;
#   (c) a class under a module defining `table_name_prefix`, or nested in a model, reads no table (Rails prefixes its name);
#   (d) a subclass of an abstract intermediate class reads no table of its own name;
#   (e) a class written directly `< ActiveRecord::Base` reads no table by its name (a Ruby inherit reference keeps only the
#       final segment, `Base`, which names no root by itself); its `self.table_name =` is read;
#   (f) a receiver whose class is known only by name (a FactoryBot build keys its class by final segment) reads no column
#       when its ancestors' names are several models' (Fleet::Base and Depot::Base, each with its table): it is shown to be
#       neither.
#
# Usage:  test/rubycolumncheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubycolumncheck.sh
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
for d in app/models/parcel app/services db spec/factories spec/models
do
    mkdir -p "$FIX/$d"
done

# ── the schema: one table per rule, and a decoy table for each guard ───────────────────────────────────────────────────────
cat > "$FIX/db/schema.rb" <<'EOF'
ActiveRecord::Schema[8.1].define(version: 2026_11_03_000000) do
  create_table "parcels", force: :cascade do |t|
    t.string "label" # @parcels_label
    t.integer "weight" # @parcels_weight
    t.string "status"
    t.integer "priority"
    t.timestamps # @parcels_stamps
  end

  create_table "tally_rows", force: :cascade do |t|
    t.decimal "amount" # @tally_amount
    t.string "label" # @tally_label
    t.timestamps
  end

  create_table "categories", force: :cascade do |t|
    t.string "title" # @categories_title
  end

  create_table "boxes", force: :cascade do |t|
    t.integer "depth" # @boxes_depth
  end

  create_table "vehicles", force: :cascade do |t|
    t.string "plate" # @vehicles_plate
    t.string "type"
  end

  create_table "trucks", force: :cascade do |t|
    t.integer "axles"
  end

  create_table "couriers", force: :cascade do |t|
    t.string "callsign"
  end

  create_table "crates", force: :cascade do |t|
    t.string "barcode"
  end

  create_table "seals", force: :cascade do |t|
    t.string "wax"
  end

  create_table "sheep", force: :cascade do |t|
    t.string "fleece"
  end

  create_table "relics", force: :cascade do |t|
    t.string "era"
  end

  create_table "almanacs", force: :cascade do |t|
    t.string "edition"
  end

  create_table "fleets", force: :cascade do |t|
    t.string "code"
  end

  create_table "depots", force: :cascade do |t|
    t.string "code"
  end
end
EOF

# ── the models ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
cat > "$FIX/app/models/application_record.rb" <<'EOF'
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
EOF
cat > "$FIX/app/models/parcel.rb" <<'EOF'
class Parcel < ApplicationRecord
  enum priority: { low: 0, high: 1 }

  def status
    "sealed"
  end

  def describe
    label # @self_bare
  end

  def heavy?
    self.weight > 10 # @self_dot
  end

  def stamped
    created_at # @self_stamp
  end
end
EOF
cat > "$FIX/app/models/tally.rb" <<'EOF'
class Tally < ApplicationRecord
  self.table_name = "tally_rows"
end
EOF
cat > "$FIX/app/models/category.rb" <<'EOF'
class Category < ApplicationRecord
end
EOF
cat > "$FIX/app/models/box.rb" <<'EOF'
class Box < ApplicationRecord
end
EOF
cat > "$FIX/app/models/vehicle.rb" <<'EOF'
class Vehicle < ApplicationRecord
end
EOF
cat > "$FIX/app/models/truck.rb" <<'EOF'
class Truck < Vehicle
end
EOF
cat > "$FIX/app/models/courier.rb" <<'EOF'
class Courier < ActiveRecord::Base
end
EOF
cat > "$FIX/app/models/freight.rb" <<'EOF'
module Freight
  def self.table_name_prefix
    "freight_"
  end

  class Crate < ApplicationRecord
  end
end
EOF
cat > "$FIX/app/models/parcel/seal.rb" <<'EOF'
class Parcel
  class Seal < ApplicationRecord
  end
end
EOF
cat > "$FIX/app/models/sheep.rb" <<'EOF'
class Sheep < ApplicationRecord
end
EOF
cat > "$FIX/app/models/relic.rb" <<'EOF'
class Heirloom < ApplicationRecord
  self.abstract_class = true
end

class Relic < Heirloom
end
EOF
cat > "$FIX/app/models/almanac.rb" <<'EOF'
class Almanac
  def initialize
    @pages = []
  end
end
EOF

cat > "$FIX/app/models/fleet.rb" <<'EOF'
module Fleet
  class Base < ApplicationRecord
    self.table_name = "fleets"
  end

  class Van < Base
  end
end
EOF
cat > "$FIX/app/models/depot.rb" <<'EOF'
module Depot
  class Base < ApplicationRecord
    self.table_name = "depots"
  end
end
EOF
cat > "$FIX/spec/factories/parcels.rb" <<'EOF'
FactoryBot.define do
  factory :parcel do
    label { "fragile" }
  end

  factory :van, class: "Fleet::Van" do
  end
end
EOF
cat > "$FIX/spec/models/parcel_spec.rb" <<'EOF'
RSpec.describe Parcel do
  let(:parcel) { create(:parcel) }
  let(:van) { create(:van) }

  it "weighs" do
    expect(parcel.weight).to eq(1) # @factory_column
    expect(van.code).to eq("V") # @floor_shared_name
  end
end
EOF

# ── the calls ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
cat > "$FIX/app/services/shipping.rb" <<'EOF'
class Shipping
  def call( id )
    parcel = Parcel.find( id )
    parcel.label # @typed_label
    parcel.created_at # @typed_stamp
    parcel.status # @written_wins
    parcel.priority # @enum_wins
    Tally.new.amount # @explicit_table
    Tally.new.label # @explicit_namesake
    Category.find( id ).title # @plural_ies
    Box.new.depth # @plural_es
    Truck.new.plate # @sti_base
  end

  def guards( id, record )
    record.label # @untyped
    Parcel.label # @class_side
    Truck.new.axles # @sti_own_name
    Almanac.new.edition # @not_a_model
  end

  def floors( id )
    parcel = Parcel.find( id )
    parcel.label = "fragile" # @floor_writer
    parcel.label? # @floor_predicate
    Sheep.new.fleece # @floor_uncountable
    Freight::Crate.new.barcode # @floor_prefix
    Parcel::Seal.new.wax # @floor_nested
    Relic.new.era # @floor_abstract
    Courier.new.callsign # @floor_active_record_base
  end
end
EOF

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
# srow ID — "kind<TAB>line" the census's S row gives definition ID
srow(){
    awk -F'\t' -v id="$1" '$1 == "S" && $2 == id { print $3 "\t" $4; exit }' "$DIR/census.tsv"
}
# column FILE MARK CALLEE COLMARK WHY — the marked call's one row binds the one schema column on db/schema.rb's COLMARK line
column(){
    local n r c; n="$( line "$1" "$2" )"; c="$( line db/schema.rb "$4" )"
    [ -n "$n" ] && [ -n "$c" ] || { no "fixture marker @$2 or @$4 missing"; return; }
    r="$( rows "$1" "$n" "$3" )"
    local t="${r#*$'\t'}"
    local name="$3"; name="${name%=}"
    if [ "$( printf '%s\n' "$r" | grep -c . )" = 1 ] && [ "${t#*|}" = "$t" ] && [ "${t%#*}" = "db/schema.rb::$name" ] \
        && [ "$( srow "$t" )" = "sec	$c" ]
    then
        ok "@$2 :$3 → the $3 column on schema.rb:$c alone ($5)"
    else
        no "@$2 ($1:$n) :$3 does not reach the column on schema.rb:$c alone ($5); census: $( printf '%s' "$r" | tr '\t\n' '  ' ) def: $( srow "$t" | tr '\t' ' ' )"
    fi
}
# only FILE MARK CALLEE SYM KIND WHY — the marked call's one row binds SYM, a definition of kind KIND, and nothing else
only(){
    local n r; n="$( line "$1" "$2" )"
    [ -n "$n" ] || { no "fixture marker @$2 missing in $1"; return; }
    r="$( rows "$1" "$n" "$3" )"
    local t="${r#*$'\t'}"
    if [ "$( printf '%s\n' "$r" | grep -c . )" = 1 ] && [ "${t#*|}" = "$t" ] && printf '%s' "$t" | grep -qF "::$4#" \
        && [ "$( srow "$t" | cut -f1 )" = "$5" ]
    then
        ok "@$2 :$3 → $4 ($5) alone ($6)"
    else
        no "@$2 ($1:$n) :$3 does not reach $4 ($5) alone ($6); census: $( printf '%s' "$r" | tr '\t\n' '  ' )"
    fi
}
# nocolumn FILE MARK CALLEE WHY — no schema column is among the marked call's targets
nocolumn(){
    local n; n="$( line "$1" "$2" )"
    [ -n "$n" ] || { no "fixture marker @$2 missing in $1"; return; }
    rows "$1" "$n" "$3" | cut -f2 | tr '|' '\n' | grep -q '^db/schema\.rb::' \
        && no "@$2 ($1:$n) :$3 reaches a schema column — $4; census: $( rows "$1" "$n" "$3" | tr '\t\n' '  ' )" \
        || ok "@$2 :$3 reaches no schema column ($4)"
}
# norow FILE MARK CALLEE WHY — the census records no row for the marked call
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

census "$FIX" || exit 1
M=app/models/parcel.rb
C=app/services/shipping.rb
P=spec/models/parcel_spec.rb

echo "=== a receiver the code builds answers from its model's columns ==="
column  $C typed_label        label      parcels_label      "Parcel.find( id ): parcels' label"
column  $C typed_stamp        created_at parcels_stamps     "t.timestamps: parcels' created_at, not tally_rows'"
column  $C explicit_table     amount     tally_amount       "self.table_name = \"tally_rows\""
column  $C explicit_namesake  label      tally_label        "the label of Tally's table, not of parcels"
column  $C plural_ies         title      categories_title   "Category reads categories"
column  $C plural_es          depth      boxes_depth        "Box reads boxes"
column  $C sti_base           plate      vehicles_plate     "Truck < Vehicle reads vehicles, its base class's table"
column  $P factory_column     weight     parcels_weight     "let(:parcel) { create(:parcel) }: a FactoryBot build"

echo "=== a call to self answers from them ==="
column  $M self_bare          label      parcels_label      "a bare label in one of Parcel's methods"
column  $M self_dot           weight     parcels_weight     "self.weight"
column  $M self_stamp         created_at parcels_stamps     "a bare created_at"

echo "=== what the class writes or declares answers first ==="
only    $C written_wins       status     Parcel::status     method "Parcel's written def status, before the status column"
only    $C enum_wins          priority   Parcel::priority   sec    "enum priority: generates the reader (R3), before the priority column"

echo "=== guards: what the lookup does not reach is left as before ==="
norow   $C untyped            label                                "an untyped receiver: the name tier, which never sees a column"
nocolumn $C class_side        label                                "a column is an instance's reader: the class object does not answer it"
nocolumn $C sti_own_name      axles                                "an STI subclass reads its base's table, not the table of its own name"
nocolumn $C not_a_model       edition                              "a class that is no model reads no table of its name"

echo "=== stated floors ==="
nocolumn $C floor_writer      label=                               "floor (a): a column's writer is not minted"
nocolumn $C floor_predicate   label?                               "floor (a): a column's predicate is not minted"
nocolumn $C floor_uncountable fleece                               "floor (b): Rails' uncountable sheep is not ported"
nocolumn $C floor_prefix      barcode                              "floor (c): under a module's table_name_prefix, not crates"
nocolumn $C floor_nested      wax                                  "floor (c): nested in a model, Rails reads parcel_seals, not seals"
nocolumn $C floor_abstract    era                                  "floor (d): below an abstract intermediate class, no table is read"
nocolumn $C floor_active_record_base callsign                        "floor (e): a class directly < ActiveRecord::Base reads no table by name"
nocolumn $P floor_shared_name code                                   "floor (f): known only as Van, whose ancestor Base is two models: neither's code"

echo "=== the surfaces ==="
callers="$( "$BIN" "$FIX" --callers=amount --no-cache 2>/dev/null | grep -oE 'of="amount" defs="[0-9]+" count="[0-9]+"' | head -1 )"
[ "$callers" = 'of="amount" defs="1" count="1"' ] && ok "--callers=amount names its one caller ($callers)" \
    || no "--callers=amount: $callers (want defs=1 count=1)"

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
