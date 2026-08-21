-- util.lua — the module-table idiom: `local M = {}` … `return M`.

local M = {}

function M.trim(s)
  return (string.gsub(s, "^%s+", ""))
end

function M.shout(s)
  return string.upper(M.trim(s))
end

M.pad = function(s)
  return " " .. s
end

return M
