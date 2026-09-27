# migration arm, column lifecycle: an OLD migration adds "bla", a LATER one removes it —
# only the rendered schema is the source of column names. `add_column` / `remove_column`
# are not read anywhere (the DSL call is a reference, its arguments are data), so a column
# added then dropped never registers, and a column that STILL exists is registered by the
# schema, not by the migration that added it. `bla` and `gonna_die` stay undefinable.
class MoreColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :spike_single_columns, "bla", :string
    change_column :spike_single_columns, :ref, :text
    add_column :spike_single_columns, "gonna_die", :string
    remove_column :spike_single_columns, "gonna_die"
  end
end