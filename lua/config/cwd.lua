--- The working directory at startup. lua/config/init.lua requires this first,
--- before options and plugins: a deleted cwd is recovered before anything can
--- trip over it, and the first argument is captured now to pick the startup cwd
--- at VimEnter (util.cwd.startup_dir).
local cwd = require("util.cwd")

local report = cwd.recover()

-- Capture an absolute argument before plugins can change the buffer or cwd.
-- Apply only once, after startup has resolved every relative file argument.
local first = vim.fn.argc() > 0 and vim.fn.argv(0) or nil
if type(first) == "string" and first ~= "-" and not first:match("^%a[%w+.-]*://") then
  local path = vim.fn.fnamemodify(first, ":p")
  local initial_cwd = vim.fn.getcwd()
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("startup_cwd", { clear = true }),
    once = true,
    desc = "Set startup cwd from the first file or directory",
    callback = function()
      -- Respect an explicit :cd/:lcd/:tcd or a restored session's directory.
      if vim.fn.getcwd() ~= initial_cwd or vim.fn.haslocaldir() ~= 0 then return end
      local target = cwd.startup_dir(path)
      if target then vim.cmd.cd(vim.fn.fnameescape(target)) end
    end,
  })
end

if report then
  -- At init time vim.notify is the builtin echo, and the dashboard's first
  -- draw wipes the command line. The snacks notifier, which keeps the report
  -- on screen and in its history, is in place once lazy has set snacks up;
  -- this handler is registered before lazy's, so the notify is scheduled past
  -- the whole VeryLazy chain rather than fired inside it.
  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    once = true,
    callback = function()
      vim.schedule(function() vim.notify(report, vim.log.levels.WARN) end)
    end,
  })
end
