# RUBY CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.
# Expected counts are literals read off this file. The ABSENT row is absent BY DESIGN, stated in
# queries/ruby/tags.scm's own header: a bare, receiver-less, parenthesis-less call is
# indistinguishable from a local-variable read, so it is deliberately not captured.

def bare_paren_fn
  1
end

def bare_noparen_fn
  2
end

class Widget
  def member_fn
    3
  end
end

module Util
  def self.receiver_fn
    4
  end

  def self.colon_fn
    5
  end

  module Deep
    def self.deep_fn
      6
    end
  end
end

def caller
  a = bare_paren_fn()          # 1. bare call WITH parentheses
  w = Widget.new
  a += w.member_fn             # 2. method call through a receiver (no parens, receiver present)
  a += Util.receiver_fn        # 3. module-function call, dot receiver
  a += Util::colon_fn          # 4. `::` used as the method-call operator
  a += Util::Deep.deep_fn      # 5. scope_resolution receiver, then a dot call
  a
end

def caller_absent
  # 6. ABSENT BY DESIGN — a bare, receiver-less, paren-less call parses as an identifier and is
  #    indistinguishable from a local-variable read. Capturing it would spray every local name.
  bare_noparen_fn
end
