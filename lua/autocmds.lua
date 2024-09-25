local cmd = vim.api.nvim_create_user_command
local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

--- Window
cmd("WindowCloseOthers", function()
  require("util.window").close_others()
end, { desc = "Close other windows" })

cmd("WindowCloseCurrent", function()
  require("util.window").close_current()
end, { desc = "Close current window" })

autocmd("VimEnter", {
  group = augroup("autoupdate", { clear = true }),
  callback = function()
    require("lazy").update({ show = false })
  end
})
