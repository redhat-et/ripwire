module App
  module Geometry
    # DISCLOSED FLOOR: a CamelCase alias is not an open — queries/ruby/tags.scm skips it, and so does the index
    Point = Struct.new(:x, :y)
  end
end
