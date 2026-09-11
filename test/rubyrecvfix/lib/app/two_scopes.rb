module App
  class Sync
    def run
      User.find(1)                # App::User
    end
  end

  module Admin
    class Resync
      def run
        User.find(1)              # App::Admin::User — same file, same written name, DIFFERENT nesting: its own directive
      end
    end
  end
end
