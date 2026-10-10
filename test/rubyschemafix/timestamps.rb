# timestamps arm: `t.timestamps` yields created_at / updated_at columns.
module Spike
  class Timestamps < ApplicationRecord
    self.table_name = "spike_timestamps"
  end
end
