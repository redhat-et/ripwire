module App
  module Admin
    class Audit
      def run
        User.find(1)              # LEXICAL: App::Admin::User (admin/user.rb), NOT App::User
      end
    end
  end
end
