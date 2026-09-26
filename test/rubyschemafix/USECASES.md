# rubyschemafix — fixture fact sheet (the Rails schema-column capture)

What this fixture is, and which claims in it are runtime-proven vs stated floors.

## Provenance

`schema.rb` is the rendered schema of a real, running Rails 8.1 application: its `bin/rails
db:schema:dump` output, with the original domain tables and all identifying markers stripped and the
remaining tables renamed to `spike_*`. The dump was verified to load back into that application
(`bin/rails db:schema:load` succeeded), so the shape vocabulary here — `force: :cascade`, `id: false`,
`primary_key:`, the option-pair spellings, the string/symbol column spellings, `null: false` — comes
from a working Rails install, not from a hand-invented guess.

Two spellings no real dump ever emits are restored BY HAND in `schema.rb` and marked in-file:

- `spike_id_uuids` with `id: :uuid` — the source app's dump FAILED for this table ("Could not dump
  table … Unknown type 'uuid' for column 'id'": the dump host lacked the uuid extension). The table's
  shape is the standard Rails rendering for a uuid key; the `id: :uuid` pair is the spelling ripwire's
  id rule reads (the pair KEY names `id`, the uuid TYPE is not modelled — stated floor).
- `spike_timestamps_literal` with a bare `t.timestamps` — rendered schemas expand it into the two
  `t.datetime` pairs (present above it as `spike_timestamps`); the DSL CALL itself exists only in
  migrations. The column names it mints (`created_at`, `updated_at`) are part of Active Record's
  documented timestamps contract.

The model files mirror the source application's runtime shapes (`self.table_name`, `attribute`,
`def name`; a quoted `where("name = ?")` in `floor_case.rb` is the runtime pattern of a raw SQL
fragment). They are indexed as text; nothing here executes at gate time.

## What the gate pins (all measured on the binary, per the repo's honesty rule)

| Query | Pinned answer | Why |
|---|---|---|
| `--uses=name` | defs=19 external=0 count=3 | 9 columns + 9 attr/def defs + 1 yaml key; only the 3 consumers use it — the `where("name = ?")` fragment stays opaque |
| `--uses=id` | defs=14 external=0 count=1 | the multi-def floor: EVERY table carries its key (12 implicit, `id: :uuid`, and the explicit `id: false`-less ones); only `id: false` + the renamed table have none |
| `--uses=created_at` | defs=2 | the rendered `t.datetime "created_at"` column AND the literal `t.timestamps` call |
| `--uses=event_id` | defs=1 | `primary_key: "event_id"` renames the key off `id` |
| `--callers=created_at` | count=1 | `Timestamps.new.created_at` reaches BOTH defs — the Lang::Ruby admission consequence |
| `graph_ambiguous` | 4 on `name` | the rich/new/rec receiver sites split; `self.name` in PairDefColumn pins (0) |

## Stated floors (silence is stated, never silent)

- `t.references :owner` / `t.belongs_to` / `t.polymorphic` / `t.index` name no column (the fixture
  spells `references` + `index` in `spike_quote_symbol`; `owner` stays undefinable).
- A symbol-named table (`create_table :users`) is a migration spelling, not a rendered-schema shape —
  no name-string node ⇒ no schema surface.
- Duplicate column names across tables stay SEPARATE defs (`id` on N tables → defs=N); the map row
  merges them by name with `overloads`, never hiding the multiplicity.
- MIGRATIONS never interfere (the three migration fixtures, all pinned undefinable): a class-wrapped
  `create_table "x"` / `create_table :x` — the migration shape — is refused by the class/module-nest
  gate, so the schema is the ONE source of column names and indexing a migration beside its schema
  cannot double any def; `add_column` / `remove_column` / `change_column` are argument data and read
  nowhere — a column added then dropped (`gonna_die`) never registers.
- `where("price > ?")` string fragments are opaque to any static extractor.
- The DSL calls (`string`, `datetime`, `create_table`, …) stay external-surface references — no def
  named `string` appears; only the NAME args gain defs (same posture as the attr family).
- A column call's receiver must BE the block parameter: `helper.string "unbound_column"` (a different
  bare identifier) names no column — the gate accepts only `t.<type>` (the `|t|` handle) forms.