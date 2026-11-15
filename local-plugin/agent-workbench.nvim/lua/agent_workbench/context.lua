-- Optional host policy has native defaults; no private host modules are loaded.
local M = {}
local function callback(name, fallback, ...)
  return (require("agent_workbench.options").callback(name) or fallback)(...)
end
function M.project_root(path)
  return callback("project_root", function(file)
    local start = file and file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
    return vim.fs.root(start, ".git") or vim.fn.getcwd()
  end, path)
end
function M.editor_win()
  return callback("editor_win", function()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].buftype == "" then return win end
    end
  end)
end
function M.origin_tab(tab)
  return callback("origin_tab", function() return nil end, tab)
end
function M.notify_error(err)
  return callback("notify_error", function(value) vim.notify(tostring(value), vim.log.levels.WARN) end, err)
end
return M
