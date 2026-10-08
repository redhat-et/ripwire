require_relative "helpers"

module App
  class Base
    def flush()
      puts "base flush"
    end
  end

  # A bare call is self.method: its own class, a superclass, an included module. Never an unrelated class.
  class Logger < Base
    include Helpers

    def line(s)
      stamp(s)
    end

    def close
      flush()
      reset()
      top_level_note("closed")
    end

    private

    def reset()
      puts "reset"
    end
  end
end
