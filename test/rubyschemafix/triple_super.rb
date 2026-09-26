# triple arm, spelling (b): `def name; super; end` + `attribute :name` +
# column. Bare `super` reaches the generated attribute reader, which reads the
# column-backed @attributes store. There is no separate "column method" — the
# column IS the storage. Expected chain: def -> super -> generated attr reader -> column.
module Spike
  class TripleSuper < ApplicationRecord
    self.table_name = "spike_triples"

    attribute :name

    def name
      super
    end
  end
end
