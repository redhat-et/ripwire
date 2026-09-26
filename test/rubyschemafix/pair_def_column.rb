# pair arm (def, column): the class def shadows the generated attribute reader.
module Spike
  class PairDefColumn < ApplicationRecord
    self.table_name = "spike_pair_def_columns"

    def name
      "def"
    end

    # locality-resolved arm: a `self.name` read at class level, in the class whose own
    # `def name` sits in this same file — the receiver pins the enclosing class, so
    # the resolver picks THAT def (amb=0), never splitting over the schema column or
    # the yaml key.
    def self.lookup
      self.name
    end
  end
end
