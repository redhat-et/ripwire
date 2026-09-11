module App
  class Dynamic
    def run(repo, name)
      repo.find(1)                # identifier receiver — not a constant
      self.class.find(1)          # `self.class` — not a constant
      @store.fetch(name)          # ivar receiver
      repo::Finder.call           # a scope whose HEAD is not a constant — nothing
      send(:find, 1)              # receiver-less
      Object.const_get(name).new  # `Object` IS a constant receiver — but see below: it is the ONE row this file gets
    end
  end
end
