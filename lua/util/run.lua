-- Run the current file with a per-filetype command.
--
-- Language modules (lua/lang/*.lua) register their runner via M.register(ft,
-- builder); a single <leader>cx keymap (see lua/mappings.lua) dispatches by the
-- current buffer's filetype. Scope is deliberately small: "quickly run this
-- script", not a task runner or build/debug system.
local M = {}

---@type table<string, fun(path: string): string>
local runners = {}

--- Register a runner for one or more filetypes.
---@param ft string|string[] filetype(s) this runner handles
---@param builder fun(path: string): string builds the shell command for a file path
function M.register(ft, builder)
  for _, f in ipairs(type(ft) == "table" and ft or { ft }) do
    runners[f] = builder
  end
end

--- Write and run the current buffer's file in a split terminal.
function M.run_current()
  local ft = vim.bo.filetype
  local builder = runners[ft]
  if not builder then
    vim.notify("No runner registered for filetype: " .. (ft ~= "" and ft or "(none)"),
      vim.log.levels.WARN)
    return
  end
  local path = vim.fn.expand("%:p")
  if path == "" then
    vim.notify("Run current file: buffer is not backed by a file on disk", vim.log.levels.WARN)
    return
  end
  vim.cmd("write")
  vim.cmd("split | terminal " .. builder(path))
end

return M
