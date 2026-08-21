-- greeter.lua — the metatable "class" idiom, plus a colon method and a plain local function.

local util = require("util")

local Greeter = {}
Greeter.__index = Greeter

function Greeter.new(name)
  return setmetatable({ name = name }, Greeter)
end

function Greeter:greet()
  return util.shout(self.name)
end

local function fallback(n)
  if n == nil then
    return "world"
  elseif n == "" then
    return "world"
  end
  return n
end

return {
  new = Greeter.new,
  fallback = fallback,
}
