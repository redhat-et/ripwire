module App
  module Admin
    class Export
      def run
        ::App::User.find(1)       # ABSOLUTE: lib/app/user.rb, even though App::Admin::User is nearer
      end
    end
  end
end
