---@module "util.lsp"
---LSP code actions with error handling
---
---Wraps vim.lsp.buf.code_action with a client check and logging.

local logger = require("util.logger")

local M = {}

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
        local clients = vim.lsp.get_clients({ bufnr = 0 })
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
      elseif result == false then
        logger.debug("LSP action skipped: %s", action)
      else
        logger.debug("LSP action completed: %s", action)
      end
      
      return success and result ~= false
    end
  end
})

return M
