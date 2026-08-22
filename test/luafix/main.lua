-- main.lua — a table-constructor function definition, and the control-flow shapes whose cyclomatic
-- treatment the port had to get right: `do … end` is a bare scope block (NOT a loop), `repeat … until`
-- IS a loop, and `and`/`or` are the boolean operators.
--
-- Also the negative control for the IIFE module idiom (queries/lua/tags.scm's stated floor): `iife_pick`
-- below is a callable local that ripwire deliberately does NOT define, because the assignment's value is
-- a parenthesized_expression whose RETURN value is the function — nothing a static read can name.

local greeter = require("greeter")

-- the IIFE module idiom, verbatim in shape from plenary.nvim's lua/plenary/path.lua (`local shorten =
-- (function() … end)()`). NO definition of `iife_pick` may appear in the map; luacheck.sh §5 asserts it.
local iife_pick = (function()
  return function(a, b)
    return a or b
  end
end)()

-- ...and a real CALL of it, at file scope so no function's metrics move. This is what makes the floor
-- observable: the name is USED, so --uses has something to report, and what it reports is defs="0"
-- external="1" — "two facts, no definition found here" — instead of inventing a definition.
local iife_default = iife_pick(nil, "world")

local handlers = {
  run = function(name)
    return greeter.fallback(name)
  end,
}

local function countdown(n)
  local total = 0
  do
    total = total + 1
  end
  for i = 1, n do
    total = total + i
  end
  repeat
    total = total - 1
  until total <= 0
  while total < 0 and n > 0 do
    total = total + 1
  end
  return total
end

return { handlers = handlers, countdown = countdown, pick = iife_pick, default = iife_default }
