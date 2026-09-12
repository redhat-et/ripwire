module App
  class Floor                         # DISCLOSED FLOOR of this round: a constant in a VALUE position that is not a
    def run(x)                        # receiver, an argument or a rescue class is NOT captured. This file yields nothing.
      case x
      when Errors::Boom then 1        # a `when` pattern (Ruby evaluates it eagerly — the next round's first candidate)
      end
      list = [Errors::Bust]           # an array element
      opts = { klass: Validator }     # a hash-literal value (a keyword PAIR in an argument list is captured; a literal is not)
      wrap({ klass: Helper })         # a hash literal INSIDE the parens — not a direct pair of the argument list
      wrap(*User)                     # a splat
      target = Mailer                 # an assignment's right-hand side
      "#{Errors::Boom}"               # string interpolation
      Mailer || Helper                # a binary operand
      [list, opts, target]
    end
  end
end
