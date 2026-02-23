---@module "autocmds"
---Auto commands and user commands for Neovim configuration
---
---Defines custom commands and automatic behaviors for improved workflow.
---Includes window management commands and performance optimizations.

-- API shortcuts for creating commands and autocommands
local cmd = vim.api.nvim_create_user_command
local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

--- Window Management Commands
--- Custom commands for efficient window handling

-- Close all windows except current one (useful for cleaning up splits)
cmd("WindowCloseOthers", function()
  require("util.window").close_others()
end, { desc = "Close other windows" })

-- Close current window safely
cmd("WindowCloseCurrent", function()
  require("util.window").close_current()
end, { desc = "Close current window" })

-- Set cwd when opening a directory
autocmd("VimEnter", {
  callback = function(data)
    if vim.fn.isdirectory(data.file) == 1 then
      vim.cmd.cd(data.file)
    end
  end
})
