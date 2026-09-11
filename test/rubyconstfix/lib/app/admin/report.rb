module App
  module Admin
    # lexical lookup: App::Admin::User (../admin/user.rb) shadows App::User — Ruby resolves this to the
    # innermost nesting that defines the constant, and so must the edge.
    class Report < User
    end
  end
end
