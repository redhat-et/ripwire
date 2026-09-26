# quote-spelling arm: column declared `t.string 'name'` (single quotes).
module Spike
  class QuoteSingle < ApplicationRecord
    self.table_name = "spike_quote_single"
  end
end
