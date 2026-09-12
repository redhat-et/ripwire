module App
  class Service
    validates_with Validator          # a constant ARGUMENT at class-body level: load-time (lazy=0) → App::Validator
    delegate :name, to: Helper        # the VALUE of a keyword pair in the argument list is an argument too: lazy=0 → App::Helper

    def call(record)
      raise Errors::Boom, "bad"       # a constant argument inside a method: lazy=1 → App::Errors::Boom
      raise Errors::Boom              # DEDUPED — same (file, innermost open, written name); a constant loads once
      record.is_a?(User)              # an argument of a RECEIVER'd call is an argument all the same: lazy=1 → App::User
      Mailer.deliver(User)            # receiver AND argument off one call: Mailer is new, User dedupes with the line above
      raise ::App::Errors::Boom       # an absolute spelling is its OWN directive — the reader sees what was written
    rescue Errors::Boom => e          # a RESCUE class: dedupes with the `raise` above (same written name, same nesting)
      nil
    rescue Errors::Bust, Errors::Boom # two classes in one rescue list: Errors::Bust is new, Errors::Boom dedupes
      nil
    end
  end
end
