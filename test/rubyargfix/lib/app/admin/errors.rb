module App
  module Admin
    module Errors
      class Boom < StandardError      # App::Admin::Errors::Boom — the LEXICAL target of `Errors::Boom` inside App::Admin
      end
    end
  end
end
