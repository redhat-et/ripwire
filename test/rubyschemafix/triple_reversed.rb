# triple arm, spelling (a) reversed: `def name` declared BEFORE `attribute :name`.
# Same winner as triple_plain — proof that lookup is by ancestry, not declaration order.
module Spike
  class TripleReversed < ApplicationRecord
    self.table_name = "spike_triples"

    def name
      "def"
    end

    attribute :name
  end
end
