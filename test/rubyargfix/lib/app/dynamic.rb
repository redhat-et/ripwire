module App
  class Dynamic
    def run(klass, obj)
      raise klass                     # an identifier argument is nothing
      raise "message"                 # a string argument is nothing
      obj.is_a?(klass)
      wrap repo::Finder               # a scope whose HEAD is not a constant is nothing
      wrap(self.class)
    rescue => e                       # a bare rescue names no class
      nil
    rescue klass                      # an identifier in the rescue list is nothing
      nil
    end
  end
end
