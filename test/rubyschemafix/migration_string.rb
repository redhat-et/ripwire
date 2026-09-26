# migration arm, STRING-named table: a real migration wraps its create_table in a class body.
# The schema capture must NOT mint from it — the same columns the migration created are already
# minted from the rendered db/schema.rb, and indexing both would DOUBLE the defs (and the
# PageRank weight) on every corpus that carries migrations. The suppression is the
# class/module-nest gate: a rendered schema's tables live at file level or under
# ActiveRecord::Schema[].define, never inside a class. `email` here stays undefinable; the
# table's implicit id is NOT added to the id multi-def floor (the gate pins both).
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table "spike_migrated" do |t|
      t.string "email"
    end
  end
end