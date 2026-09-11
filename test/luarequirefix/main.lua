-- package.path's dotted convention, one shape per line.
local ab   = require "a.b"            -- dotted -> a/b.lua
local pk   = require("pkg")           -- package form -> pkg/init.lua
local ms   = require 'srcmod'         -- found under the src/ source root
local ext  = require("socket")        -- external rock: no in-tree file, no edge
local dyn  = require(dynamic_name)    -- not a string literal: nothing to read
local cat  = require("a" .. ".b")     -- concatenated: nothing to read
local amb  = require("shared")        -- AMBIGUOUS: answered by ./shared.lua AND src/shared.lua

local function lazy()
  local inner = require("a.b")        -- inside a function body: still a real directive
end

if ab then
  local cond = require("pkg")         -- inside an if: the container walk must reach it
end

local M = { dep = require("a.b") }    -- inside a table constructor
return M
