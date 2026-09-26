# quote-spelling arm: column declared t.string :name (symbol).
module Spike
  class QuoteSymbol < ApplicationRecord
    self.table_name = "spike_quote_symbol"
  end
end
