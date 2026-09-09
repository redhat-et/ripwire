module App
  class Warmup
    def prime
      Helper.fmt(1)                   # inside a method: the FIRST occurrence in source order is LAZY
    end
    Helper.fmt(0)                     # class-body level, AFTER it: LOAD-TIME — one load-time site makes the pair load-time
  end
end
