---@module "util.dev"
---Development utilities and commands for configuration maintenance
---
---Provides useful commands for debugging, testing, and maintaining
---the Neovim configuration during development.

local logger = require("util.logger")
local test = require("util.test")
local performance = require("util.performance")
local validate = require("util.validate")

local M = {}

---Reload a module and all its dependencies
---@param module_name string Module name to reload
---@return boolean success True if reload succeeded
function M.reload_module(module_name)
  if type(module_name) ~= "string" then
    logger.error("Module name must be a string")
    return false
  end
  
  logger.info("Reloading module: %s", module_name)
  
  -- Clear from package.loaded
  package.loaded[module_name] = nil
  
  -- Try to reload
  local success, result = pcall(require, module_name)
  if not success then
    logger.error("Failed to reload module %s: %s", module_name, result)
    return false
  end
  
  logger.info("Successfully reloaded module: %s", module_name)
  return true
end

---Reload configuration and re-source init.lua
function M.reload_config()
  logger.info("Reloading Neovim configuration...")
  
  -- Clear specific modules that need reloading
  local modules_to_clear = {
    "options",
    "mappings", 
    "autocmds",
    "bootstrap",
  }
  
  for _, module in ipairs(modules_to_clear) do
    package.loaded[module] = nil
  end
  
  -- Clear all plugin modules
  for module_name, _ in pairs(package.loaded) do
    if module_name:match("^plugin%.") or module_name:match("^lang%.") then
      package.loaded[module_name] = nil
    end
  end
  
  -- Re-source init.lua
  local success, error_msg = pcall(function()
    dofile(vim.fn.stdpath("config") .. "/init.lua")
  end)
  
  if not success then
    logger.error("Failed to reload configuration: %s", error_msg)
    vim.notify("Configuration reload failed: " .. error_msg, vim.log.levels.ERROR)
  else
    logger.info("Successfully reloaded configuration")
    vim.notify("Configuration reloaded successfully", vim.log.levels.INFO)
  end
  
  return success
end

---Run configuration tests
function M.run_tests()
  logger.info("Running configuration tests...")
  test.reset_stats()
  
  -- Load and run test files
  local test_files = {
    "test.config_test",
  }
  
  for _, test_file in ipairs(test_files) do
    local success, error_msg = pcall(require, test_file)
    if not success then
      logger.error("Failed to load test file %s: %s", test_file, error_msg)
    end
  end
  
  -- Run tests and return result
  return test.run()
end

---Validate all plugin configurations
function M.validate_plugins()
  logger.info("Validating plugin configurations...")
  
  local plugin_dirs = {
    "plugin.editor",
    "plugin.lsp", 
    "plugin.ui",
    "plugin.vcs",
    "lang",
  }
  
  local total_plugins = 0
  local valid_plugins = 0
  local errors = {}
  
  for _, dir in ipairs(plugin_dirs) do
    -- Get all plugin files in directory
    local success, plugins = pcall(require, dir)
    if success and type(plugins) == "table" then
      for i, plugin_spec in ipairs(plugins) do
        if type(plugin_spec) == "table" then
          total_plugins = total_plugins + 1
          local valid, plugin_errors = validate.plugin_spec(plugin_spec)
          
          if valid then
            valid_plugins = valid_plugins + 1
          else
            local plugin_name = plugin_spec[1] or string.format("%s[%d]", dir, i)
            table.insert(errors, {
              plugin = plugin_name,
              errors = plugin_errors
            })
          end
        end
      end
    end
  end
  
  logger.info("Plugin validation complete: %d/%d valid", valid_plugins, total_plugins)
  
  if #errors > 0 then
    logger.warn("Found %d plugin configuration errors:", #errors)
    for _, error_info in ipairs(errors) do
      logger.error("Plugin %s: %s", error_info.plugin, table.concat(error_info.errors, ", "))
    end
  end
  
  return #errors == 0, {
    total = total_plugins,
    valid = valid_plugins,
    errors = errors
  }
end

---Show system information useful for debugging
function M.system_info()
  local info = {
    neovim_version = vim.version(),
    lua_version = _VERSION,
    os = vim.uv.os_uname(),
    config_path = vim.fn.stdpath("config"),
    data_path = vim.fn.stdpath("data"),
    log_level = logger.get_level(),
    startup_time = performance.get_startup_time(),
    memory = performance.get_memory_info(),
  }
  
  print("\n" .. string.rep("=", 50))
  print("SYSTEM INFORMATION")
  print(string.rep("=", 50))
  
  print(string.format("Neovim Version: %s", vim.inspect(info.neovim_version)))
  print(string.format("Lua Version: %s", info.lua_version))
  print(string.format("OS: %s %s", info.os.sysname, info.os.release))
  print(string.format("Config Path: %s", info.config_path))
  print(string.format("Data Path: %s", info.data_path))
  print(string.format("Log Level: %s", info.log_level))
  
  if info.startup_time then
    print(string.format("Startup Time: %.2f ms", info.startup_time))
  else
    print("Startup Time: Not measured")
  end
  
  print(string.format("Memory Usage: %.2f MB", info.memory.lua_memory_mb))
  
  print(string.rep("=", 50))
  
  return info
end

---Profile a function and show results
---@param name string Function name for logging
---@param fn function Function to profile
---@param ... any Arguments to pass to function
---@return any result Function result
function M.profile_function(name, fn, ...)
  local timer = performance.start_timer(name)
  local success, result = logger.safe_call(fn, name)
  local duration = timer:stop()
  
  if success then
    logger.info("Profiled %s: %.2f ms", name, duration)
  else
    logger.error("Profiled %s failed after %.2f ms: %s", name, duration, result)
  end
  
  return result
end

---Show plugin loading status
function M.plugin_status()
  local lazy_ok, lazy = pcall(require, "lazy")
  if not lazy_ok then
    logger.error("Lazy.nvim not available")
    return
  end
  
  local plugins = lazy.plugins()
  local stats = {
    total = 0,
    loaded = 0,
    not_loaded = 0,
    failed = 0,
  }
  
  print("\n" .. string.rep("=", 60))
  print("PLUGIN STATUS")
  print(string.rep("=", 60))
  print(string.format("%-30s %-10s %s", "Plugin", "Status", "Load Time"))
  print(string.rep("-", 60))
  
  for _, plugin in ipairs(plugins) do
    stats.total = stats.total + 1
    
    local status = "not loaded"
    local load_time = ""
    
    if plugin._.loaded then
      stats.loaded = stats.loaded + 1
      status = "loaded"
      if plugin._.loaded.time then
        load_time = string.format("%.1f ms", plugin._.loaded.time)
      end
    elseif plugin._.installed == false then
      stats.failed = stats.failed + 1
      status = "failed"
    else
      stats.not_loaded = stats.not_loaded + 1
    end
    
    print(string.format("%-30s %-10s %s", 
                       plugin.name:sub(1, 30), status, load_time))
  end
  
  print(string.rep("-", 60))
  print(string.format("Total: %d | Loaded: %d | Not Loaded: %d | Failed: %d",
                     stats.total, stats.loaded, stats.not_loaded, stats.failed))
  print(string.rep("=", 60))
  
  return stats
end

-- Register development commands
vim.api.nvim_create_user_command("DevReload", function()
  M.reload_config()
end, { desc = "Reload Neovim configuration" })

vim.api.nvim_create_user_command("DevTest", function()
  M.run_tests()
end, { desc = "Run configuration tests" })

vim.api.nvim_create_user_command("DevValidate", function()
  local valid, results = M.validate_plugins()
  if valid then
    vim.notify(string.format("All %d plugins valid", results.total), vim.log.levels.INFO)
  else
    vim.notify(string.format("%d/%d plugins have errors", 
                            #results.errors, results.total), vim.log.levels.WARN)
  end
end, { desc = "Validate plugin configurations" })

vim.api.nvim_create_user_command("DevInfo", function()
  M.system_info()
end, { desc = "Show system information" })

vim.api.nvim_create_user_command("DevPlugins", function()
  M.plugin_status()
end, { desc = "Show plugin loading status" })

vim.api.nvim_create_user_command("DevProfile", function(opts)
  if opts.args == "" then
    performance.report()
  else
    performance.monitor_memory(5, tonumber(opts.args) or 30)
  end
end, { 
  desc = "Show performance report or monitor memory", 
  nargs = "?",
  complete = function() return {"30", "60", "120"} end 
})

vim.api.nvim_create_user_command("DevReloadModule", function(opts)
  if opts.args == "" then
    vim.notify("Please specify a module name", vim.log.levels.WARN)
    return
  end
  M.reload_module(opts.args)
end, { 
  desc = "Reload a specific module", 
  nargs = 1,
  complete = function(arg_lead)
    local modules = {}
    for module_name, _ in pairs(package.loaded) do
      if module_name:match("^" .. vim.pesc(arg_lead)) then
        table.insert(modules, module_name)
      end
    end
    return modules
  end
})

logger.debug("Development utilities loaded")

return M