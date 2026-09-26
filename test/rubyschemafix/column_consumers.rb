# consumer arm: EXPLICIT model receivers — `Spike::SingleColumn.new.name` reaches the
# column def set by name (the sameRoot+langCompatible admission the plan calls out);
# `Spike::IdDefault.new.id` sits on the multi-table implicit id floor (14 id defs).
module Spike
  def self.single_name
    SingleColumn.new.name
  end

  def self.default_id
    IdDefault.new.id
  end

  def self.literal_stamp
    Timestamps.new.created_at
  end
end
