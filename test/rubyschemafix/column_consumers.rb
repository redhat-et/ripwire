# consumer arm: EXPLICIT model receivers — `Spike::SingleColumn.new.name` resolves to the
# column def set by name; `Spike::IdDefault.new.id` sits on the multi-table implicit id
# floor (14 id defs). Definitions-only per the review round: these calls match the defs
# but columns take NO call edges, so the gate's §3 arms are count="0" assertions.
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
