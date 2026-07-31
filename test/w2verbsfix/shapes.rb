# shapes.rb — Wave-2 cross-verb fixture (w2verbscheck.sh).
#
# leaf_rb(x):                1 param, 0 nesting, 0 calls, loc=3
# deep_nest_rb(a, b, c):     3 params, 3-deep nesting (if > while > if), calls nothing in-repo
# calls_both_rb(x):          1 param, 0 nesting, calls leaf_rb()+deep_nest_rb() -> cbo=2

def leaf_rb(x)
  x + 1
end

def deep_nest_rb(a, b, c)
  if a > 0
    while b > 0
      if c > 0
        return a + b + c
      end
      b -= 1
    end
  end
  0
end

def calls_both_rb(x)
  leaf_rb(x) + deep_nest_rb(x, x, x)
end
