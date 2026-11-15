local M = {}
local configured = false
function M.setup(opts)
  assert(not configured, "editor_core.setup() can only run once")
  opts = vim.deepcopy(opts or {})
  configured = true
  require("editor_core.url").setup(opts.url)
  require("editor_core.options").setup(opts.options or {}, opts.theme or {}, opts.formatting or {})
  require("editor_core.keymaps").setup(opts.keymaps or {})
  if opts.whichkey then require("editor_core.keyguide").setup(opts.whichkey, opts.keymaps) end
  require("editor_core.autocmds").setup(opts.behaviors or {})
end
return M
