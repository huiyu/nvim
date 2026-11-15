-- Whole-editor quit policy. Requiring this module installs nothing.
local M = {}

--- Buffers Nvim would refuse to quit over, including modified `acwrite`
--- buffers such as oil's. `getbufinfo()` exposes the raw changed flag, so
--- read the 'modified' option too: scratch, terminal and prompt buffers never
--- block a quit even when their raw flag is set.
local function unsaved_buffers()
  return vim.tbl_filter(function(info)
    return vim.bo[info.bufnr].modified
  end, vim.fn.getbufinfo({ bufmodified = 1 }))
end

local function refuse_quit(unsaved)
  local names = vim.tbl_map(function(info)
    return info.name ~= "" and vim.fn.fnamemodify(info.name, ":~:.") or "[No Name]"
  end, unsaved)
  vim.notify(
    "Not quitting: unsaved changes in " .. table.concat(names, ", ")
      .. "\nSave them, or <leader>qQ to quit without saving.",
    vim.log.levels.WARN
  )
end

--- Snacks closes terminal windows in ExitPre. Nvim drops a quit when an
--- autocommand closes its current window, so close them before issuing it.
--- This deliberately spans tabpages: a background terminal can block exiting
--- too. Hidden terminals and buffers stay alive for ExitPre to clean up.
local function close_snacks_terminals()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win)
      and vim.b[vim.api.nvim_win_get_buf(win)].snacks_terminal then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

-- Tests capture the command here without taking the editor down.
M._quit = function(command) vim.cmd(command) end

--- Quit Nvim, including from inside a Snacks terminal window.
--- Check unsaved changes before touching the layout or issuing :qall: ExitPre
--- runs before Nvim's own modified-buffer refusal and would cost the panel.
--- A refusal is one warning naming the buffers, without a Lua traceback.
--- Typed :qa still follows Nvim's own path.
---@param force boolean? issue `qall!`, discarding unsaved changes
function M.all(force)
  if not force then
    local unsaved = unsaved_buffers()
    if #unsaved > 0 then
      refuse_quit(unsaved)
      return
    end
  end
  close_snacks_terminals()
  M._quit(force and "qall!" or "qall")
end

return M
