# consumer arm, spam: a call site with NO locality evidence — `rec.name` where rec is
# an ordinary local. Every in-repo def named `name` is a candidate (the 9 columns, the
# attr Vars, the method defs, the yaml key); the resolver SPLITS and says so (amb=K),
# never silently picks. The call edges land on the def set, not on nothing.
module Spike
  class ConsumerAmbiguous < ApplicationRecord
    def render_label( rec )
      rec.name
    end
  end
end