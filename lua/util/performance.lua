---@module "util.performance"
---Performance monitoring and profiling utilities
---
---Provides tools for measuring startup time, plugin loading performance,
---and general function execution timing.
---
---@example
---local perf = require("util.performance")
---perf.profile_startup()
---
---local timer = perf.start_timer("my_operation")
----- ... do work ...
---timer:stop()

local logger = require("util.logger")

local M = {}

-- Performance data storage
local timers = {}
local profiles = {}
local startup_time = nil

---High-resolution timer implementation
---@class Timer
---@field name string Timer name
---@field start_time number Start time in nanoseconds
---@field end_time? number End time in nanoseconds
local Timer = {}
Timer.__index = Timer

---Create a new timer
---@param name string Timer name
---@return Timer timer New timer instance
function Timer:new(name)
  local timer = {
    name = name,
    start_time = vim.uv.hrtime(),
    end_time = nil,
  }
  setmetatable(timer, Timer)
  return timer
end

---Stop the timer and record duration
---@return number duration Duration in milliseconds
function Timer:stop()
  if self.end_time then
    logger.warn("Timer %s already stopped", self.name)
    return self:duration()
  end
  
  self.end_time = vim.uv.hrtime()
  local duration = self:duration()
  
  logger.debug("Timer %s: %.2f ms", self.name, duration)
  
  -- Store in global timers for reporting
  if not timers[self.name] then
    timers[self.name] = {}
  end
  table.insert(timers[self.name], duration)
  
  return duration
end

---Get timer duration in milliseconds
---@return number duration Duration in milliseconds
function Timer:duration()
  if not self.end_time then
    -- Return current duration if not stopped
    return (vim.uv.hrtime() - self.start_time) / 1000000
  end
  return (self.end_time - self.start_time) / 1000000
end

---Start a new timer
---@param name string Timer name
---@return Timer timer New timer instance
function M.start_timer(name)
  if type(name) ~= "string" then
    error("Timer name must be a string", 2)
  end
  
  local timer = Timer:new(name)
  logger.debug("Started timer: %s", name)
  return timer
end

---Time a function execution
---@param name string Operation name
---@param fn function Function to time
---@param ... any Arguments to pass to function
---@return any result Function result
---@return number duration Duration in milliseconds
function M.time_function(name, fn, ...)
  if type(name) ~= "string" then
    error("Operation name must be a string", 2)
  end
  
  if type(fn) ~= "function" then
    error("Expected function to time", 2)
  end
  
  local timer = M.start_timer(name)
  local success, result = pcall(fn, ...)
  local duration = timer:stop()
  
  if not success then
    logger.error("Timed function %s failed: %s", name, result)
    error(result)
  end
  
  return result, duration
end

---Profile startup time
function M.profile_startup()
  -- Only profile if enabled via environment variable
  if not vim.env.NVIM_PROFILE then
    return
  end
  
  local start_time = vim.uv.hrtime()
  logger.debug("Startup profiling enabled")
  
  -- Profile VimEnter
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
      startup_time = (vim.uv.hrtime() - start_time) / 1000000
      logger.info("Startup time: %.2f ms", startup_time)
      
      -- Store startup profile
      profiles.startup = {
        total_time = startup_time,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
      }
      
      -- Show startup time if verbose profiling is enabled
      if vim.env.NVIM_PROFILE_VERBOSE then
        vim.notify(string.format("🚀 Startup time: %.1f ms", startup_time), 
                  vim.log.levels.INFO, { title = "Performance" })
      end
    end,
  })
  
  -- Profile plugin loading
  vim.api.nvim_create_autocmd("User", {
    pattern = "LazyLoad",
    callback = function(event)
      local plugin = event.data
      logger.debug("Plugin loaded: %s", plugin)
    end,
  })
end

---Get startup time
---@return number? startup_time Startup time in milliseconds, nil if not measured
function M.get_startup_time()
  return startup_time
end

---Get timer statistics
---@param name? string Timer name, nil for all timers
---@return table stats Timer statistics
function M.get_timer_stats(name)
  if name then
    local measurements = timers[name]
    if not measurements or #measurements == 0 then
      return {
        name = name,
        count = 0,
        total = 0,
        average = 0,
        min = 0,
        max = 0,
      }
    end
    
    local total = 0
    local min = measurements[1]
    local max = measurements[1]
    
    for _, duration in ipairs(measurements) do
      total = total + duration
      min = math.min(min, duration)
      max = math.max(max, duration)
    end
    
    return {
      name = name,
      count = #measurements,
      total = total,
      average = total / #measurements,
      min = min,
      max = max,
    }
  else
    local stats = {}
    for timer_name, _ in pairs(timers) do
      stats[timer_name] = M.get_timer_stats(timer_name)
    end
    return stats
  end
end

---Clear timer data
---@param name? string Timer name, nil to clear all
function M.clear_timers(name)
  if name then
    timers[name] = nil
    logger.debug("Cleared timer: %s", name)
  else
    timers = {}
    logger.debug("Cleared all timers")
  end
end

---Profile function calls for a module
---@param module_name string Module name to profile
---@param methods? table Array of method names to profile (nil for all)
---@return table profiled_module Module with profiled methods
function M.profile_module(module_name, methods)
  local ok, module = pcall(require, module_name)
  if not ok then
    logger.error("Failed to load module for profiling: %s", module_name)
    return {}
  end
  
  if type(module) ~= "table" then
    logger.warn("Module %s is not a table, cannot profile", module_name)
    return module
  end
  
  local profiled = {}
  
  for key, value in pairs(module) do
    if type(value) == "function" then
      local should_profile = not methods or vim.tbl_contains(methods, key)
      
      if should_profile then
        profiled[key] = function(...)
          local timer_name = string.format("%s.%s", module_name, key)
          return M.time_function(timer_name, value, ...)
        end
      else
        profiled[key] = value
      end
    else
      profiled[key] = value
    end
  end
  
  logger.debug("Profiled module: %s", module_name)
  return profiled
end

---Memory usage profiling
---@return table memory_info Memory usage information
function M.get_memory_info()
  -- Force garbage collection to get accurate measurement
  collectgarbage("collect")
  
  local memory_kb = collectgarbage("count")
  local memory_mb = memory_kb / 1024
  
  return {
    lua_memory_kb = memory_kb,
    lua_memory_mb = memory_mb,
    timestamp = os.time(),
  }
end

---Monitor memory usage over time
---@param interval? number Monitoring interval in seconds (default: 5)
---@param duration? number Total monitoring duration in seconds (default: 60)
function M.monitor_memory(interval, duration)
  interval = interval or 5
  duration = duration or 60
  
  local samples = {}
  local start_time = os.time()
  
  logger.info("Starting memory monitoring for %ds (interval: %ds)", duration, interval)
  
  local function sample_memory()
    local current_time = os.time()
    if current_time - start_time >= duration then
      -- Stop monitoring and report
      local total_samples = #samples
      if total_samples > 0 then
        local min_memory = samples[1].lua_memory_mb
        local max_memory = samples[1].lua_memory_mb
        local total_memory = 0
        
        for _, sample in ipairs(samples) do
          min_memory = math.min(min_memory, sample.lua_memory_mb)
          max_memory = math.max(max_memory, sample.lua_memory_mb)
          total_memory = total_memory + sample.lua_memory_mb
        end
        
        local avg_memory = total_memory / total_samples
        
        logger.info("Memory monitoring complete:")
        logger.info("  Samples: %d", total_samples)
        logger.info("  Average: %.2f MB", avg_memory)
        logger.info("  Min: %.2f MB", min_memory)
        logger.info("  Max: %.2f MB", max_memory)
        logger.info("  Growth: %.2f MB", max_memory - min_memory)
      end
      return
    end
    
    -- Take memory sample
    local memory_info = M.get_memory_info()
    table.insert(samples, memory_info)
    logger.debug("Memory sample: %.2f MB", memory_info.lua_memory_mb)
    
    -- Schedule next sample
    vim.defer_fn(sample_memory, interval * 1000)
  end
  
  -- Start monitoring
  sample_memory()
end

---Print performance report
function M.report()
  print("\n" .. string.rep("=", 60))
  print("PERFORMANCE REPORT")
  print(string.rep("=", 60))
  
  -- Startup time
  if startup_time then
    print(string.format("Startup Time: %.2f ms", startup_time))
  else
    print("Startup Time: Not measured")
  end
  
  -- Memory usage
  local memory_info = M.get_memory_info()
  print(string.format("Current Memory: %.2f MB", memory_info.lua_memory_mb))
  
  -- Timer statistics
  local all_stats = M.get_timer_stats()
  if vim.tbl_count(all_stats) > 0 then
    print("\nTimer Statistics:")
    print(string.rep("-", 40))
    print(string.format("%-20s %8s %8s %8s %8s", "Name", "Count", "Total", "Avg", "Max"))
    print(string.rep("-", 40))
    
    for name, stats in pairs(all_stats) do
      print(string.format("%-20s %8d %8.2f %8.2f %8.2f", 
                         name:sub(1, 20), stats.count, stats.total, stats.average, stats.max))
    end
  else
    print("\nNo timer data available")
  end
  
  print(string.rep("=", 60))
end

-- Auto-setup commands if profiling is enabled
if vim.env.NVIM_PROFILE then
  vim.api.nvim_create_user_command("PerfReport", function()
    M.report()
  end, { desc = "Show performance report" })
  
  vim.api.nvim_create_user_command("PerfClear", function()
    M.clear_timers()
    print("Performance data cleared")
  end, { desc = "Clear performance data" })
  
  vim.api.nvim_create_user_command("PerfMemory", function(opts)
    local args = vim.split(opts.args, " ")
    local interval = tonumber(args[1]) or 5
    local duration = tonumber(args[2]) or 60
    M.monitor_memory(interval, duration)
  end, { 
    desc = "Monitor memory usage", 
    nargs = "*",
    complete = function()
      return {"5", "10", "30", "60"}
    end
  })
  
  -- Auto-profile startup
  M.profile_startup()
end

return M