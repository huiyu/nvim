---@module "util.common"
---Common utility functions for table manipulation and data processing
---
---Provides a functional programming interface for table operations
---including mapping, filtering, and searching. Useful for plugin
---configuration and data transformation tasks.
---
---@example
---local common = require("util.common")
---local tbl = common.table({a = 1, b = 2, c = 3})
---local keys = tbl:keys():get() -- {a, b, c}
---local doubled = tbl:map(function(k, v) return k, v * 2 end):get()

local M = {}

---Determines if a key represents an array element (positive integer index)
---@param tbl table The table to check against
---@param key any The key to evaluate
---@return boolean True if the key is a valid array index
local function is_array_element(tbl, key)
  if type(key) ~= "number" or key <= 0 or math.floor(key) ~= key then
    return false
  end
  -- Check if the key is within the array bounds
  -- This assumes that the array part of the table is continuous
  return key <= #tbl
end

---Creates a new table wrapper object with utility methods
---@param tbl table The table to wrap
---@return table A table wrapper with chainable utility methods
---@example
---local tbl = M.table({1, 2, 3})
---local doubled = tbl:map(function(k, v) return k, v * 2 end)
M.table = function(tbl)
  if type(tbl) ~= "table" then error("Expected a table as the argument", 2) end
  local self = {}

  --- Get the wrapped table
  -- @return The original table
  function self:get()
    return tbl
  end

  ---Map function over table elements
  ---@param func function Function to apply to each key-value pair (key, value, table) -> (new_key, new_value)
  ---@return table A new table wrapper with the mapped results
  ---@example
  ---tbl:map(function(k, v) return k, v * 2 end) -- Double all values
  ---tbl:map(function(k, v) return v end) -- Convert to array of values
  function self:map(func)
    if type(func) ~= "function" then error("Expected a function as the argument", 2) end

    local result = {}
    for k, v in pairs(tbl) do
      local a, b = func(k, v, tbl)
      -- If only one return value, treat as array element
      if b == nil and a ~= nil then
        result[#result + 1] = a
      -- If two return values, treat as key-value pair
      else
        result[a] = b
      end
    end
    return M.table(result)
  end

  --- Get all keys of the table
  -- @return A new table wrapper containing all keys
  function self:keys()
    if type(tbl) ~= "table" then error("Expected a table as the first argument", 2) end

    local results = {}
    for k, _ in pairs(tbl) do
      results[#results + 1] = k
    end
    return M.table(results)
  end

  --- Get all values of the table
  -- @return A new table wrapper containing all values
  function self:values()
    if type(tbl) ~= "table" then error("Expected a table as the first argument", 2) end

    local results = {}
    for _, v in pairs(tbl) do
      results[#results + 1] = v
    end
    return M.table(results)
  end

  --- Check if the table contains a specific value
  -- @param item The value to search for
  -- @return true if the value is found, false otherwise
  function self:containsValue(item)
    for _, v in pairs(tbl) do
      if item == v then
        return true
      end
    end
    return false
  end

  --- Check if the table contains a specific key or value
  -- @param item The key or value to search for
  -- @return true if the key or value is found, false otherwise
  function self:contains(item)
    for k, v in pairs(tbl) do
      if is_array_element(tbl, k) then
        if v == item then return true end
      else
        if k == item then return true end
      end
    end
    return false
  end

  --- Check if the table contains a specific key
  -- @param item The key to search for
  -- @return true if the key is found, false otherwise
  function self:containsKey(item)
    for k, _ in pairs(tbl) do
      if item == k then
        return true
      end
    end
    return false
  end

  return self
end

return M
