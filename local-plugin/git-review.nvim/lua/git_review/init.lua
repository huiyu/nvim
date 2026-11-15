local M = {}
local opts = { history_limit = 100, max_file_size = 10 * 1024 * 1024, retention = { saved = 10 } }
local function validate(value)
  local function positive(v) return type(v) == "number" and v > 0 and v < math.huge and v % 1 == 0 end
  local fields = { history_limit = true, max_file_size = true, retention = true, resolve = true,
    labels = true, review_vars = true, close_aux = true }
  for key in pairs(value) do assert(fields[key], "git_review." .. tostring(key) .. " is not a supported setting") end
  assert(value.history_limit == false or positive(value.history_limit), "git_review.history_limit must be a positive integer or false")
  assert(positive(value.max_file_size), "git_review.max_file_size must be a positive integer")
  assert(type(value.retention) == "table", "git_review.retention must be a table")
  for key in pairs(value.retention) do assert(key == "saved", "git_review.retention." .. tostring(key) .. " is not a supported setting") end
  assert(positive(value.retention.saved), "git_review.retention.saved must be a positive integer")
  for _, key in ipairs({ "resolve", "labels", "review_vars", "close_aux" }) do
    assert(value[key] == nil or type(value[key]) == "function", "git_review." .. key .. " must be a function")
  end
  return value
end
function M.setup(value)
  opts = validate(vim.tbl_deep_extend("force", vim.deepcopy(opts), vim.deepcopy(value or {})))
end
function M.options()
  local value = vim.deepcopy(opts)
  return validate(value.resolve and vim.tbl_deep_extend("force", value, value.resolve()) or value)
end
return M
