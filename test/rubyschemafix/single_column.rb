# single-source arm: column `name` only (no def, no attr).
module Spike
  class SingleColumn < ApplicationRecord
    self.table_name = "spike_single_columns"
  end
end
