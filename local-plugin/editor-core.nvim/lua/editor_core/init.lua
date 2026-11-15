local M = {}
local configured = false
function M.setup(opts)
  assert(not configured, "editor_core.setup() can only run once")
  opts = vim.deepcopy(opts or {})
  configured = true
  require("editor_core.url").setup(opts.url)
  require("editor_core.options").setup(opts.options or {}, opts.theme or {}, opts.formatting or {})
  if opts.keymaps ~= false then
    local keys = opts.keymaps or {}
    if keys.leader then vim.g.mapleader = keys.leader end
    if keys.localleader then vim.g.maplocalleader = keys.localleader end
    if keys.core ~= false then require("editor_core.keymaps").setup(keys) end
    if keys.actions then require("editor_core.keyguide").setup(keys) end
  end
  require("editor_core.autocmds").setup(opts.behaviors or {})
end
return M
