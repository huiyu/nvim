-- The split `:Gitsigns diffthis` (<leader>gd) opens: a window for each
-- revision of the file -- the index, or ours and theirs for a file with
-- conflicts (also <leader>gD's there) -- in diff mode beside the file's own
-- window, in the current tabpage. gitsigns has no command that closes it, and
-- <leader>gq only knew CodeDiff's views; close() is that command, for
-- <leader>gq, and toggle() is <leader>gd and <leader>gD around it.
--
-- A revision window is told by its buffer's name: gitsigns names every buffer
-- it reads from git `gitsigns://<gitdir>//<rev>:<path>`, and keys its own
-- attach on that prefix. tests/gitsigns_spec.lua fails if <leader>gd stops
-- opening one.
local M = {}

local vim_error = require("util.vim_error")

local PREFIX = "gitsigns://"

---@param tab integer
---@return integer[]
local function layout_wins(tab)
  -- ui2 keeps its floats in every tabpage; only split windows make a layout.
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative == ""
  end, vim.api.nvim_tabpage_list_wins(tab))
end

---@param tab integer
---@return integer[]
local function diff_wins(tab)
  return vim.tbl_filter(function(win) return vim.wo[win].diff end, layout_wins(tab))
end

---@param win integer
local function diffoff(win)
  -- :diffoff, not 'nodiff': it also restores the foldmethod, scrollbind and
  -- the rest that diff mode saved when it started.
  vim.api.nvim_win_call(win, function() vim.cmd("diffoff") end)
end

---@param tab integer? tabpage, 0 or nil for the current one
---@return integer
local function tabpage(tab)
  if tab == nil or tab == 0 then return vim.api.nvim_get_current_tabpage() end
  return tab
end

--- The tabpage's windows that show a gitsigns revision in diff mode.
---@param tab integer? tabpage, 0 or nil for the current one
---@return integer[]
function M.revision_wins(tab)
  return vim.tbl_filter(function(win)
    return vim.startswith(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)), PREFIX)
  end, diff_wins(tabpage(tab)))
end

--- Close the gitsigns diff split in `tab`: its revision windows, then diff
--- mode in every window of `tab`. Other tabpages are not touched.
---@param tab integer? tabpage, 0 or nil for the current one
---@return boolean found whether `tab` had one, closed or refused
function M.close(tab)
  tab = tabpage(tab)
  local revisions = M.revision_wins(tab)
  if #revisions == 0 then return false end
  -- The index side is editable -- :w stages it -- and gitsigns wipes its
  -- buffer once no window shows it, so closing with unsaved edits would lose
  -- them; Nvim refuses that with E37, which would stop the loop below after
  -- some windows were already gone. Refuse before closing any.
  for _, win in ipairs(revisions) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].modified then
      vim.notify("The diff's index side has unsaved changes: :w stages them, :e! drops them", vim.log.levels.WARN)
      return true
    end
  end
  for _, win in ipairs(revisions) do
    -- Ours and theirs with the file's window closed by hand: the last one is
    -- the tabpage's last split, and closing it would close the tabpage. It
    -- stays; diff mode ends below.
    if vim.api.nvim_win_is_valid(win) and #layout_wins(tab) > 1 then
      local ok, err = pcall(vim.api.nvim_win_close, win, false)
      if not ok then vim_error.notify(err) end
    end
  end
  -- Vim compares every diff window of a tabpage with every other, as one
  -- view, and what is left of it would go on comparing: a :split of the
  -- file's window inherits diff mode, and so does a second file whose split
  -- `:Gitsigns diffthis` added beside the first (<leader>gd moves the split
  -- instead). 'diffopt' closeoff only ends diff mode in the last window left.
  -- End it in all of them, as :diffoff! would in this tabpage.
  for _, win in ipairs(diff_wins(tab)) do diffoff(win) end
  return true
end

--- <leader>gd (no `opts`) and <leader>gD (`{ unified = true }`): from a
--- window of the current tabpage's split, close it; otherwise open gitsigns'
--- diffthis with `opts` for the current window.
---@param opts? { unified?: boolean }
function M.toggle(opts)
  opts = opts or {}
  local win = vim.api.nvim_get_current_win()
  if vim.wo[win].diff and #M.revision_wins() > 0 then
    M.close()
    return
  end
  -- A split elsewhere in the tabpage moves here: beside it, the new one
  -- would be compared with the other file too. Unless it stays open over
  -- unsaved index edits. The inline view sets no diff mode and stays out.
  if not opts.unified and M.close() and #M.revision_wins() > 0 then return end
  -- gitsigns' diffthis ignores a window in diff mode, and one comparing
  -- nothing is common: a buffer last shown in a diff window carries diff
  -- mode into the next window that opens it (`:tabnew` of the file).
  if vim.wo[win].diff and #diff_wins(0) == 1 then diffoff(win) end
  require("gitsigns").diffthis(nil, opts)
end

return M
