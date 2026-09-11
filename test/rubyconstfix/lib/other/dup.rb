# App::Dup is ALSO opened here — but as a NAMESPACE WRAPPER (its body is one nested open and nothing else), so
# this open defines nothing of App::Dup and uses_dup.rb's `< Dup` edges to lib/app/dup.rb alone.
module App
  class Dup
    class Inner
    end
  end
end
