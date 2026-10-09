# migration arm, SYMBOL-named table: the other common spelling. Already floored by the
# string-name gate (a symbol-named create_table is a migration spelling, not a rendered
# schema), kept as a fixture so the floor is pinned from BOTH sides — the class-nest gate
# and the name-string gate both refuse, and the widget columns stay undefinable.
class CreateWidgets < ActiveRecord::Migration[8.1]
  def change
    create_table :spike_widgets do |t|
      t.string "widget_name"
    end
  end
end