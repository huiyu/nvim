local M = {}

-- Attaches a callback to the LspAttach event for a specific or any LSP client
-- @param on_attach function: The callback function to be executed when LSP attaches
-- @param name string|nil: Optional name of the LSP client to attach to
function M.on_attach(on_attach, name)
  return vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
      local buffer = args.buf ---@type number
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and (not name or client.name == name) then
        return on_attach(client, buffer)
      end
    end,
  })
end

-- Table for executing specific LSP code actions
-- Uses a metatable to dynamically create functions for each action
M.action = setmetatable({}, {
  __index = function(_, action)
    return function()
      vim.lsp.buf.code_action({
        apply = true,
        context = {
          only = { action },
          diagnostics = {},
        }
      })
    end
  end
})

return M
