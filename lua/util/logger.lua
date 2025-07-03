---@module "util.logger"
---Structured logging framework for Neovim configuration
---
---Provides leveled logging with proper formatting and notification integration.
---Supports different log levels and can be configured for development vs production.
---
---@example
---local logger = require("util.logger")
---logger.set_level("DEBUG")
---logger.info("Configuration loaded successfully")
---logger.error("Failed to load plugin: %s", plugin_name)

local M = {}

-- Log levels with numeric values for comparison
local levels = {
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
}

-- Default log level
local current_level = levels.INFO

-- Log history for debugging (keep last 100 entries)
local log_history = {}
local max_history = 100

---Set the current logging level
---@param level string Log level: "DEBUG", "INFO", "WARN", "ERROR"
function M.set_level(level)
  if not levels[level] then
    M.warn("Invalid log level: %s. Using INFO.", level)
    current_level = levels.INFO
    return
  end
  
  current_level = levels[level]
  M.debug("Log level set to: %s", level)
end

---Get the current logging level
---@return string Current log level name
function M.get_level()
  for name, value in pairs(levels) do
    if value == current_level then
      return name
    end
  end
  return "INFO"
end

---Internal logging function
---@param level string Log level name
---@param message string Log message with format specifiers
---@param ... any Format arguments
local function log_internal(level, message, ...)
  local level_num = levels[level]
  if not level_num or level_num < current_level then
    return
  end
  
  -- Format the message
  local formatted = string.format(message, ...)
  local timestamp = os.date("%H:%M:%S")
  local log_entry = string.format("[%s] %s: %s", timestamp, level, formatted)
  
  -- Add to history
  table.insert(log_history, {
    timestamp = timestamp,
    level = level,
    message = formatted,
    full = log_entry
  })
  
  -- Keep history size manageable
  if #log_history > max_history then
    table.remove(log_history, 1)
  end
  
  -- Map our levels to vim.log.levels
  local vim_levels = {
    DEBUG = vim.log.levels.DEBUG,
    INFO = vim.log.levels.INFO,
    WARN = vim.log.levels.WARN,
    ERROR = vim.log.levels.ERROR,
  }
  
  -- Send to Neovim's notification system
  vim.notify(formatted, vim_levels[level], {
    title = string.format("Neovim Config (%s)", level),
  })
end

---Log debug message (lowest priority)
---@param message string Log message with format specifiers
---@param ... any Format arguments
function M.debug(message, ...)
  log_internal("DEBUG", message, ...)
end

---Log info message
---@param message string Log message with format specifiers
---@param ... any Format arguments
function M.info(message, ...)
  log_internal("INFO", message, ...)
end

---Log warning message
---@param message string Log message with format specifiers
---@param ... any Format arguments
function M.warn(message, ...)
  log_internal("WARN", message, ...)
end

---Log error message (highest priority)
---@param message string Log message with format specifiers
---@param ... any Format arguments
function M.error(message, ...)
  log_internal("ERROR", message, ...)
end

---Get recent log entries
---@param count? number Number of recent entries to return (default: 10)
---@return table Array of log entries
function M.get_recent(count)
  count = count or 10
  local start_idx = math.max(1, #log_history - count + 1)
  local recent = {}
  
  for i = start_idx, #log_history do
    table.insert(recent, log_history[i])
  end
  
  return recent
end

---Clear log history
function M.clear_history()
  log_history = {}
  M.debug("Log history cleared")
end

---Print recent log entries to command line
---@param count? number Number of recent entries to show (default: 10)
function M.show_recent(count)
  local recent = M.get_recent(count)
  print("Recent log entries:")
  print(string.rep("-", 50))
  
  for _, entry in ipairs(recent) do
    print(entry.full)
  end
  
  if #recent == 0 then
    print("No log entries found")
  end
end

---Safe function execution with error logging
---@param fn function Function to execute
---@param context? string Context description for error messages
---@return boolean success, any result_or_error
function M.safe_call(fn, context)
  if type(fn) ~= "function" then
    M.error("safe_call: expected function, got %s", type(fn))
    return false, "Invalid function"
  end
  
  context = context or "unknown operation"
  
  local ok, result = pcall(fn)
  if not ok then
    M.error("Error in %s: %s", context, result)
    return false, result
  end
  
  return true, result
end

-- Initialize logger based on environment
local function init()
  -- Set log level based on environment variable
  local env_level = vim.env.NVIM_LOG_LEVEL
  if env_level then
    M.set_level(env_level)
  else
    -- Default to WARN in production, DEBUG in development
    local is_dev = vim.env.NVIM_DEV == "1"
    M.set_level(is_dev and "DEBUG" or "WARN")
  end
  
  M.debug("Logger initialized with level: %s", M.get_level())
end

-- Auto-initialize when module is loaded
init()

return M