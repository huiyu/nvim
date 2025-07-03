---@module "util.string-ext"
---String extension utilities for enhanced string operations
---
---Extends the built-in string table with additional utility methods
---for common string operations like prefix/suffix checking.
---
---@example
---require("util.string-ext")
---print("hello.lua":ends_with(".lua"))    -- true
---print("config":starts_with("con"))      -- true

local M = {}

---Check if string starts with a given prefix
---@param str string The string to check
---@param prefix string The prefix to look for
---@return boolean True if string starts with prefix
function string.starts_with(str, prefix)
  if type(str) ~= "string" or type(prefix) ~= "string" then
    return false
  end
  return str:sub(1, #prefix) == prefix
end

---Check if string ends with a given suffix
---@param str string The string to check
---@param suffix string The suffix to look for
---@return boolean True if string ends with suffix
function string.ends_with(str, suffix)
  if type(str) ~= "string" or type(suffix) ~= "string" then
    return false
  end
  return str:sub(-#suffix) == suffix
end

---Trim whitespace from both ends of string
---@param str string The string to trim
---@return string Trimmed string
function string.trim(str)
  if type(str) ~= "string" then
    return str
  end
  return str:match("^%s*(.-)%s*$")
end

---Split string by delimiter
---@param str string The string to split
---@param delimiter string The delimiter to split by
---@return table Array of string parts
function string.split(str, delimiter)
  if type(str) ~= "string" then
    return {str}
  end
  
  local result = {}
  local pattern = string.format("([^%s]+)", delimiter or "%s")
  
  for match in str:gmatch(pattern) do
    table.insert(result, match)
  end
  
  return result
end

---Check if string is empty or only whitespace
---@param str string The string to check
---@return boolean True if string is empty or whitespace
function string.is_empty(str)
  if type(str) ~= "string" then
    return true
  end
  return str:trim() == ""
end

return M