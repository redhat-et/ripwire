module App
  class Nested
    def run
      wrap(step(Validator))           # an argument of a NESTED call is an argument: lazy=1 → App::Validator
      log(Helper.fmt(2))              # `Helper` is a receiver (round two); the call is the argument, not a constant
    end
  end
end
