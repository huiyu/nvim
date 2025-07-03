---@module "util.lsp"
---LSP utility functions with comprehensive error handling
---
---Provides safe wrappers around LSP operations with proper error handling
---and logging integration.

local logger = require("util.logger")

local M = {}

---Safely attaches a callback to the LspAttach event for a specific or any LSP client
---@param on_attach function The callback function to be executed when LSP attaches
---@param name? string Optional name of the LSP client to attach to
---@return number autocmd_id The ID of the created autocommand
function M.on_attach(on_attach, name)
  -- Validate input parameters
  if type(on_attach) ~= "function" then
    logger.error("on_attach must be a function, got %s", type(on_attach))
    error("on_attach must be a function", 2)
  end
  
  if name and type(name) ~= "string" then
    logger.error("LSP client name must be a string, got %s", type(name))
    error("LSP client name must be a string", 2)
  end
  
  logger.debug("Setting up LSP attach for client: %s", name or "any")
  
  return vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
      local success, result = logger.safe_call(function()
        local buffer = args.buf ---@type number
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        
        if not client then
          logger.warn("Failed to get LSP client with ID: %s", args.data.client_id)
          return
        end
        
        if name and client.name ~= name then
          logger.debug("Skipping LSP attach for %s (waiting for %s)", client.name, name)
          return
        end
        
        logger.info("LSP client attached: %s (buffer: %d)", client.name, buffer)
        return on_attach(client, buffer)
      end, string.format("LSP attach for %s", name or "any client"))
      
      if not success then
        logger.error("LSP attach failed: %s", result)
      end
      
      return result
    end,
  })
end

---Safe LSP code action execution with error handling
---Uses a metatable to dynamically create functions for each action
---@example
---local lsp = require("util.lsp")
---lsp.action["source.organizeImports"]()  -- Organize imports
---lsp.action["quickfix"]()                -- Apply quickfix
M.action = setmetatable({}, {
  __index = function(_, action)
    return function()
      if type(action) ~= "string" then
        logger.error("LSP action must be a string, got %s", type(action))
        return
      end
      
      logger.debug("Executing LSP action: %s", action)
      
      local success, result = logger.safe_call(function()
        -- Check if LSP is available
        local clients = vim.lsp.get_active_clients({ bufnr = 0 })
        if #clients == 0 then
          logger.warn("No active LSP clients for current buffer")
          return false
        end
        
        vim.lsp.buf.code_action({
          apply = true,
          context = {
            only = { action },
            diagnostics = {},
          }
        })
        
        return true
      end, string.format("LSP action: %s", action))
      
      if not success then
        logger.error("LSP action failed: %s", result)
      else
        logger.debug("LSP action completed: %s", action)
      end
      
      return success
    end
  end
})

---Check if LSP is available for current buffer
---@return boolean available True if at least one LSP client is active
---@return table clients Array of active LSP clients
function M.is_available()
  local clients = vim.lsp.get_active_clients({ bufnr = 0 })
  return #clients > 0, clients
end

---Get LSP client by name
---@param name string LSP client name
---@return table|nil client LSP client or nil if not found
function M.get_client(name)
  if type(name) ~= "string" then
    logger.error("Client name must be a string, got %s", type(name))
    return nil
  end
  
  local clients = vim.lsp.get_active_clients({ bufnr = 0 })
  for _, client in ipairs(clients) do
    if client.name == name then
      return client
    end
  end
  
  logger.debug("LSP client not found: %s", name)
  return nil
end

---Safely execute LSP buffer command with error handling
---@param command string LSP command name (e.g., "hover", "definition")
---@param ... any Additional arguments for the command
---@return boolean success True if command executed successfully
function M.buf_command(command, ...)
  if type(command) ~= "string" then
    logger.error("LSP command must be a string, got %s", type(command))
    return false
  end
  
  local available, clients = M.is_available()
  if not available then
    logger.warn("No LSP clients available for command: %s", command)
    return false
  end
  
  logger.debug("Executing LSP command: %s", command)
  
  -- Capture the arguments to pass to the nested function
  local args = {...}
  local success, result = logger.safe_call(function()
    local fn = vim.lsp.buf[command]
    if type(fn) ~= "function" then
      error(string.format("Unknown LSP command: %s", command))
    end
    
    return fn(unpack(args))
  end, string.format("LSP command: %s", command))
  
  if not success then
    logger.error("LSP command failed: %s", result)
  else
    logger.debug("LSP command completed: %s", command)
  end
  
  return success
end

return M
