module App
  # DISCLOSED FLOOR: `Point = Struct.new` is an alias, not an open — nothing resolves TO Point;
  # but `Struct` is a constant receiver like any other and is shown (unresolved, out of tree)
  Point = Struct.new(:x, :y)
end
