-- Nvim's own line for a refused Ex command or API call.
--
-- `vim.cmd` and the `nvim_*` API turn a refusal -- last window, read-only
-- file, no client attached -- into a Lua error, and a mapping or command
-- callback that lets it escape prints an E5108 block with a stack traceback
-- for what `:q` typed by hand shows as one line. `pcall` the call, hand the
-- error here, and that one line is what the user gets.
local M = {}

--- The message Nvim would have printed, without what Lua wraps around it.
---
--- "vim/_core/editor.lua:0: nvim_exec2(), line 1: Vim(write):E45: ..." from
--- `vim.cmd` and "Vim:E444: ..." from the API both come back as their tail,
--- "E45: ..." and "E444: ...". Anything else is returned as it is.
---@param err any the error value `pcall` returned
---@return string
function M.message(err)
  local text = tostring(err)
  return text:match("Vim%b():%s*(.-)%s*$") or text:match("Vim:%s*(.-)%s*$") or text
end

--- Notify that line at WARN: a refusal of the current state is something to
--- act on, not a fault.
---@param err any the error value `pcall` returned
---@param context string? the action, prefixed as "Run current file: ..."
function M.notify(err, context)
  local line = M.message(err)
  vim.notify(context and (context .. ": " .. line) or line, vim.log.levels.WARN)
end

return M
