-- Copy file locations and Git permalinks without reading or changing the
-- selection until an action is invoked. Requiring this module changes nothing.
local M = {}

-- <leader>y path keys. Each copies to the clipboard and the unnamed register,
-- and says what it copied.
local function yank(text)
  vim.fn.setreg("+", text); vim.fn.setreg('"', text)
  vim.notify("Yanked: " .. text)
end

---@return string? path the current buffer's absolute path, nil (with a warning) when it has none
local function buffer_path()
  local path = vim.fn.expand("%:p")
  if path == "" then
    vim.notify("Buffer has no file", vim.log.levels.WARN)
    return nil
  end
  return path
end

-- Relative to the git root, falling back to the cwd outside a repository.
local function project_path(path)
  local root = Snacks.git.get_root() or vim.fn.getcwd()
  return (path:find(root, 1, true) == 1) and path:sub(#root + 2) or vim.fn.fnamemodify(path, ":~:.")
end

-- The cursor line in Normal mode; in Visual the selected lines, after leaving
-- Visual so a copy ends the selection the way `y` does.
---@return integer first, integer last
local function target_lines()
  local first, last = vim.fn.line("."), vim.fn.line(".")
  if vim.fn.mode():find("^[vV\22]") then
    first, last = math.min(first, vim.fn.line("v")), math.max(first, vim.fn.line("v"))
    vim.cmd.normal({ vim.keycode("<Esc>"), bang = true })
  end
  return first, last
end

-- `path:12` / `path:12-18`, as read by gF, terminal links and agent prompts.
function M.line()
  local first, last = target_lines()
  local path = buffer_path()
  if not path then return end
  local lines = first == last and tostring(first) or ("%d-%d"):format(first, last)
  yank(project_path(path) .. ":" .. lines)
end

function M.absolute()
  local path = buffer_path()
  if path then yank(path) end
end

function M.relative()
  local path = buffer_path()
  if path then yank(project_path(path)) end
end

-- Pin the file's last commit: after the branch moves on the link stays put.
-- With uncommitted edits above the selection its line numbers can still drift.
function M.permalink()
  local first, last = target_lines()
  if not buffer_path() then return end
  Snacks.gitbrowse({
    what = "permalink",
    line_start = first,
    line_end = last,
    -- Its own notice would say "Opening"; yank() reports the copy instead.
    notify = false,
    open = yank,
  })
end

return M
