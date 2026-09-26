# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2000_01_01_000001) do
  create_table "spike_all_fours", force: :cascade do |t|
    t.string "name"
  end

  create_table "spike_column_yamls", force: :cascade do |t|
    t.string "name"
  end

  create_table "spike_id_defaults", force: :cascade do |t|
  end

  create_table "spike_id_false", id: false, force: :cascade do |t|
    t.string "ref", null: false
  end

  create_table "spike_id_renamed", primary_key: "event_id", force: :cascade do |t|
  end

# Could not dump table "spike_id_uuids" because of following StandardError
#   Unknown type 'uuid' for column 'id'
# Restored by hand: the standard Rails rendering for a uuid table — `id: :uuid` (the value is a
# simple_symbol), the spelling the capture's id rule reads.
  create_table "spike_id_uuids", id: :uuid, force: :cascade do |t|
  end

  create_table "spike_pair_attr_columns", force: :cascade do |t|
    t.string "name"
  end

  create_table "spike_pair_def_columns", force: :cascade do |t|
    t.string "name"
  end

  create_table "spike_plain", force: :cascade do |t|
  end

  create_table "spike_quote_double", force: :cascade do |t|
    t.string "name"
  end

  create_table "spike_quote_single", force: :cascade do |t|
    t.string "name"
  end

create_table "spike_quote_symbol", force: :cascade do |t|
    t.string :name
    t.references :owner
    t.index ["name"], name: "idx_spike"
    helper.string "unbound_column"
  end

  create_table "spike_single_columns", force: :cascade do |t|
    t.string "name"
  end

  create_table "spike_timestamps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

# Migration spelling, added by hand: the rendered dump expands `t.timestamps` into the two datetime
# columns above; the DSL CALL itself (the rule under test) names both columns literally.
  create_table "spike_timestamps_literal", force: :cascade do |t|
    t.timestamps
  end

  create_table "spike_triples", force: :cascade do |t|
    t.string "name"
  end

end
