module App
  class SuperYield < Helper           # the superclass is round one's directive: load-time → App::Helper
    def initialize(x)
      super(Validator)                # an argument of `super` is an argument: lazy=1 → App::Validator
      yield User                      # an argument of `yield` is an argument: lazy=1 → App::User
    end
  end
end
