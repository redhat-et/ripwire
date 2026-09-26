# id arm: create_table carried `id: false` — there is NO id column; the model
# declares its own primary key.
module Spike
  class IdFalse < ApplicationRecord
    self.table_name = "spike_id_false"
    self.primary_key = "ref"
  end
end
