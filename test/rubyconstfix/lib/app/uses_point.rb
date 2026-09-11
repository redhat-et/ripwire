module App
  # DISCLOSED FLOOR: `Geometry::Point` is `Point = Struct.new` — an alias, not an open — so this resolves to nothing
  class UsesPoint < Geometry::Point
  end
end
