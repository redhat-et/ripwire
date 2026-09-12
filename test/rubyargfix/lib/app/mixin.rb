module App
  class Mixin
    include Helper                    # a mixin argument is round one's directive, ONCE — never also an argument constant
    extend Validator, User            # two constants, two round-one records, none doubled
  end
end
