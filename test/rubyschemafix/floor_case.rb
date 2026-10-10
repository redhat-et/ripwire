# floor arm: a raw SQL string fragment. The `name` inside it is opaque to any
# static extractor — this is a DISCLOSED floor (no def, no use), proven only that
# the query runs.
module Spike
  class FloorCase < ApplicationRecord
    self.table_name = "spike_single_columns"

    def self.find_named( value )
      where( "name = ?", value ).to_a
    end
  end
end
