# Ruby call-form fixture.
module Util
  def self.tool; end
  module Deep
    def self.deepfn; end
  end
end
class Widget
  def self.make
    Widget.new
  end
  def bump; end
end
def free; end

def caller
  free()               # 1. bare call with parens
  w = Widget.make      # 2. Const.method
  w.bump               # 3. receiver.method
  Util.tool            # 4. Module.method
  Util::Deep.deepfn    # 5. scope-resolution receiver + .method
  Util::tool           # 6. :: as method-call operator
  Widget.new           # 7. constructor call
  free                 # 8. bare no-paren call (parses as identifier)
end
