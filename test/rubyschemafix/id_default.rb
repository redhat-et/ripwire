# id arm: implicit default id.
module Spike
  class IdDefault < ApplicationRecord
    self.table_name = "spike_id_defaults"
  end
end
