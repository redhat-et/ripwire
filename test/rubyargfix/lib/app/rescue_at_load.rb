module App
  class RescueAtLoad
    begin
      Helper.fmt(1)                   # a receiver at class-body level: load-time (lazy=0)
    rescue Errors::Bust               # a rescue class OUTSIDE any closure is STILL lazy: Ruby evaluates the exception
      nil                             # list only when an exception is being matched (`rescue Nope` with no raise is silent)
    end
  end
end
