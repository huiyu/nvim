local t = dofile("tests/helper.lua")
local debug_util = require("util.debug")

-- Keep the test silent while exercising the public wrapper installed by
-- init.lua. The return values, including a nil in the middle, must match the
-- built-in vim.print contract.
local original_dump = debug_util._dump
debug_util._dump = function() end
local function pack(...)
  return { n = select("#", ...), ... }
end
local returned = pack(vim.print("sentinel", nil, 42))
debug_util._dump = original_dump

t.eq(returned.n, 3, "vim.print preserves the number of return values")
t.eq(returned[1], "sentinel", "vim.print returns its first argument")
t.eq(returned[2], nil, "vim.print preserves a nil argument")
t.eq(returned[3], 42, "vim.print returns its final argument")

local function probe_location()
  local expected = debug.getinfo(1, "l").currentline + 1
  local location = debug_util.get_loc()
  return expected, location
end

local expected, location = probe_location()
t.ok(location:find("tests/debug_spec.lua", 1, true) ~= nil,
  "debug location names the calling file")
t.eq(tonumber(location:match(":(%d+)$")), expected,
  "debug location reports the call line, not the function definition")

t.done()
