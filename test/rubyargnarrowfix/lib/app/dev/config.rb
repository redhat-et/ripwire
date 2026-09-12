module App
  module Dev
    class Config
      def update!(**opts)             # one of two `update!` definitions, in different directories
        opts
      end
    end
  end
end
