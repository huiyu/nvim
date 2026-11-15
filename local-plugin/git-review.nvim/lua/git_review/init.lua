local M = {}
local opts = { history_limit = 100, max_file_size = 10 * 1024 * 1024, retention = { saved = 10 } }
function M.setup(value) opts = vim.tbl_deep_extend("force", vim.deepcopy(opts), vim.deepcopy(value or {})) end
function M.options()
  local value = vim.deepcopy(opts)
  return value.resolve and vim.tbl_deep_extend("force", value, value.resolve()) or value
end
return M
