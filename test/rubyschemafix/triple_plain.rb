# triple arm, spelling (a): plain `def name` alongside `attribute :name`
# and a real `name` column. Ruby lookup is by ancestry — the class-level def
# wins over the module-generated attribute reader regardless of declaration order.
module Spike
  class TriplePlain < ApplicationRecord
    self.table_name = "spike_triples"

    attribute :name

    def name
      "def"
    end
  end
end
