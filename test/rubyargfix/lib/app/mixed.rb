module App
  class Mixed
    def guard
      yield
    rescue Errors::Bust               # a LAZY site first in source order …
      nil
    end
    Errors::Bust.new                  # … and a load-time receiver of the SAME written name below it: ONE directive, load-time (AND rule)
  end
end
