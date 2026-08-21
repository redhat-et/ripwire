-- main.lua — a table-constructor function definition, and the control-flow shapes whose cyclomatic
-- treatment the port had to get right: `do … end` is a bare scope block (NOT a loop), `repeat … until`
-- IS a loop, and `and`/`or` are the boolean operators.

local greeter = require("greeter")

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

return { handlers = handlers, countdown = countdown }
