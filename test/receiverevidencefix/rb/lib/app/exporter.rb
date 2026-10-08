module App
  class Exporter
    def flush
      puts "exporter flush"
    end

    def render(s)
      "<#{s}>"
    end
  end
end
