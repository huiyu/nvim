local t = dofile("tests/helper.lua")

local function temp_directory()
  local path = vim.fn.tempname()
  t.eq(vim.fn.mkdir(path, "p"), 1, "temporary directory is created")
  return path
end

local function nonfloating_windows()
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative == ""
  end, vim.api.nvim_tabpage_list_wins(0))
end

-- BufNew also covers buffers that are never displayed. Adding a directory in
-- the background must neither load Oil nor replace the active editor buffer.
vim.cmd("enew")
local origin = vim.api.nvim_get_current_buf()
local background_dir = temp_directory()
vim.cmd("badd " .. vim.fn.fnameescape(background_dir))
vim.wait(50, function() return false end, 10)
t.eq(vim.api.nvim_get_current_buf(), origin,
  ":badd of a directory keeps the current buffer")
t.ok(package.loaded.oil == nil,
  ":badd of a directory does not eagerly load Oil")

-- A displayed directory still becomes Oil, and opening a command-only picker
-- on top of that single-panel tab must not manufacture an editor split.
local visible_dir = temp_directory()
vim.cmd("edit " .. vim.fn.fnameescape(visible_dir))
t.ok(vim.wait(1000, function() return vim.bo.filetype == "oil" end, 10),
  ":edit of a directory opens it in Oil")
local before = #nonfloating_windows()
local picker = Snacks.picker.commands()
vim.wait(100, function() return false end, 10)
t.eq(#nonfloating_windows(), before,
  "a non-file picker does not split a single Oil window")
if picker then picker:close() end

vim.fn.delete(background_dir, "d")
vim.fn.delete(visible_dir, "d")
t.done()
