require_relative "shapes"

class Panel < Base
  def typed
    base = Widget.new
    base.render
  end

  def untyped
    base = Outside.make
    base.render
  end
end
