module App
  class Cache
    def self.get
      nil
    end

    def read
      Cache.get                   # names its OWN class: shown as a directive, dropped as a self-include
    end
  end
end
