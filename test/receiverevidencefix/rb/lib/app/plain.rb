require "logger"

module App
  # Plain inherits from an OUTSIDE class (the stdlib Logger): a bare render or flush never reaches Exporter or Base.
  class Plain < ::Logger
    def finish(s)
      flush()
      render(s)
    end
  end
end
