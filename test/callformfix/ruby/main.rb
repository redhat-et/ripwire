# RUBY CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.
# Expected counts are literals read off this file. A bare, receiver-less, parenthesis-less name is
# a call or a local read by Ruby's LEXICAL rule (ingest_binds.h::captureRubyBareCalls): it is a
# local exactly when an assignment earlier in the same scope binds it. Row 6 is the call; row 7 is
# the same name after such an assignment, and is absent BY DESIGN.

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

def caller_bare
  # 6. a bare, receiver-less, paren-less call — no binding of the name precedes it in this def
  bare_noparen_fn
end

def caller_absent
  # 7. ABSENT BY DESIGN — the assignment makes the name a local, so the second line is a read
  bare_noparen_fn = 7
  bare_noparen_fn
end
