module App
  module Admin
    class Audit
      def run
        raise Errors::Boom            # LEXICAL: inside App::Admin, `Errors::Boom` is App::Admin::Errors::Boom, not App::Errors::Boom
      end
    end
  end
end
