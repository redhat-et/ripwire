# id arm: `id: :uuid` — the key is present, still named `id`, uuid type.
module Spike
  class IdUuid < ApplicationRecord
    self.table_name = "spike_id_uuids"
  end
end
