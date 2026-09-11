module App
  class User < Base
    include Trackable
    extend Searchable
    prepend Audited
  end
end
