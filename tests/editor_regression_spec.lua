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

-- Oil's URL is a local directory, while terminal names are never file paths.
local cwd = require("util.cwd")
t.eq(vim.uv.fs_realpath(cwd.buffer_dir()), vim.uv.fs_realpath(visible_dir),
  "directory-scoped actions use the displayed Oil directory")
vim.cmd("enew")
vim.api.nvim_buf_set_name(0, visible_dir .. "/new file.lua")
t.eq(vim.uv.fs_realpath(cwd.buffer_dir()), vim.uv.fs_realpath(visible_dir),
  "a new file resolves to its existing parent")
vim.cmd("enew")
vim.cmd("lcd " .. vim.fn.fnameescape(background_dir))
local local_cwd = vim.fn.getcwd()
t.eq(cwd.buffer_dir(), local_cwd, "an unnamed buffer uses the window cwd")
local job = vim.fn.jobstart({ "sh", "-c", "cat" }, { term = true })
local terminal_buf = vim.api.nvim_get_current_buf()
vim.cmd("stopinsert")
t.eq(vim.bo.buftype, "terminal", "the regression starts in a real terminal buffer")
t.ok(vim.api.nvim_buf_get_name(0):match("^term://") ~= nil,
  "the terminal has the URI that broke directory browsing")
t.eq(cwd.buffer_dir(), local_cwd, "the terminal resolves to the window cwd")

vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
vim.wait(50, function() return false end, 10)
for _, entry in ipairs({ { ";d", "explorer" }, { ";F", "files" }, { ";D", "grep" } }) do
  vim.api.nvim_set_current_buf(terminal_buf)
  local mapping = vim.fn.maparg(entry[1], "n", false, true)
  t.ok(type(mapping.callback) == "function", entry[1] .. " has a live Normal-mode mapping")
  if mapping.callback then mapping.callback() end
  local opened
  vim.wait(1000, function()
    opened = Snacks.picker.get({ source = entry[2] })[1]
    return opened ~= nil
  end, 10)
  t.ok(opened ~= nil, entry[1] .. " opens its picker from the terminal")
  if opened then
    t.eq(opened.opts.cwd, local_cwd, entry[1] .. " receives an existing directory, not term://")
    vim.wait(100, function() return false end, 10)
    opened:close()
  end
end
vim.fn.jobstop(job)
vim.api.nvim_set_current_buf(origin)
vim.cmd("lcd " .. vim.fn.fnameescape(vim.fn.stdpath("config")))

vim.fn.delete(background_dir, "d")
vim.fn.delete(visible_dir, "d")
t.done()
