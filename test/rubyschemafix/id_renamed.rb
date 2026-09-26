# id arm: `t.primary_key "event_id"` renames the key off `id`.
module Spike
  class IdRenamed < ApplicationRecord
    self.table_name = "spike_id_renamed"
  end
end
