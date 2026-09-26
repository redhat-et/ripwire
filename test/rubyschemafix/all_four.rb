# all-four arm: def + attribute + column in ONE model, and the yaml source in
# config/spike_names.yml. This is the canonical collision; runtime dispatch winner
# is the def, the static picker order (def > attr > column > yaml) is pinned in C.
module Spike
  class AllFour < ApplicationRecord
    self.table_name = "spike_all_fours"

    attribute :name

    def name
      "def"
    end
  end
end
