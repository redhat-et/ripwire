# pair arm (def, column): the class def shadows the generated attribute reader.
module Spike
  class PairDefColumn < ApplicationRecord
    self.table_name = "spike_pair_def_columns"

    def name
      "def"
    end

    # locality-resolved arm: an INSTANCE method's `self.name`, in the class whose own
    # `def name` sits in this same file — Ruby's method lookup pins THAT def (no via=),
    # never the schema column or the yaml key. (A class-side `def self.lookup` would
    # call the class object's own `name`, Module#name, and bind nothing in the tree.)
    def lookup
      self.name
    end
  end
end
