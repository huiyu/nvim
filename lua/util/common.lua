local M = {}

local function is_array_element(tbl, key)
  if type(key) ~= "number" or key <= 0 or math.floor(key) ~= key then
    return false
  end
  -- Check if the key is less than or equal to the array length
  -- This assumes that the array part of the table is continuous
  return key <= #tbl
end

--- Table manipulation module
-- @module M

--- Creates a new table wrapper object
-- @param tbl The table to wrap
-- @return A table wrapper object with various utility methods
M.table = function(tbl)
  if type(tbl) ~= "table" then error("Expected a table as the argument", 2) end
  local self = {}

  --- Get the wrapped table
  -- @return The original table
  function self:get()
    return tbl
  end

  --- Map function over table elements
  -- @param func The function to apply to each key-value pair
  -- @return A new table wrapper with the mapped results
  function self:map(func)
    if type(func) ~= "function" then error("Expected a function as the argument", 2) end

    local result = {}
    for k, v in pairs(tbl) do
      local a, b = func(k, v, tbl)
      if b == nil and a ~= nil then
        result[#result + 1] = a
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
    for _, v in ipairs(tbl) do
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
    for k, v in ipairs(tbl) do
      if is_array_element(tbl, k) then
        if v == item then return true end
      else
        if k == item then return true end
      end
    end
  end

  --- Check if the table contains a specific key
  -- @param item The key to search for
  -- @return true if the key is found, false otherwise
  function self:containsKey(item)
    for k, _ in ipairs(tbl) do
      if item == k then
        return true
      end
    end
    return false
  end

  return self
end

return M
