module App::Geometry
  # Module.nesting = [App::Geometry] ONLY: Helper → App::Geometry::Helper, then ::Helper — App::Helper is NOT on
  # the chain (Ruby raises NameError here). Same innermost open as nested_shape.rb, a different chain: the two
  # sites must not share one memoised answer.
  class CompactShape < Helper
  end
end
