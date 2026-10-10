module Rake
  class TaskLib
    include Rake::DSL
  end

  class MakefileLoader
    include Rake::DSL

    def load(fn)
      include Helpers
    end
  end

  class Singleton
    extend Rake::DSL
  end

  module Helpers
  end

  module Ping
    include Pong
  end

  module Pong
    include Ping
  end

  class Pinged
    include Ping
  end
end
