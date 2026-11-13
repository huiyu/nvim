-- `<leader>bh` deletes the listed file buffers that no window shows. "No
-- window" spans every tabpage: a file open only in another tabpage -- the
-- shape of a CodeDiff or debug tabpage -- is in use and must survive, which is
-- exactly what Snacks.bufdelete.invisible() (current tabpage only) gets wrong.
local t = dofile("tests/helper.lua")
require("lazy").load({ plugins = { "bufferline.nvim", "snacks.nvim" } })

local map = vim.fn.maparg("<leader>bh", "n", false, true)
t.ok(map.lhs ~= nil, "<leader>bh is mapped")
t.eq(map.desc, "Delete hidden buffers", "and carries its desc")

local notices = {}
local notify = vim.notify
vim.notify = function(msg) notices[#notices + 1] = msg end

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local function file(name)
  local path = dir .. "/" .. name
  vim.fn.writefile({ name }, path)
  return path
end
local function listed(buf) return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted end
local function layout()
  local shape = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      shape[#shape + 1] = { tab, win, vim.api.nvim_win_get_buf(win) }
    end
  end
  return shape
end

-- Tabpage 1: shown.lua beside split.lua; hidden.lua was open earlier.
vim.cmd.edit(file("hidden.lua"))
local hidden = vim.api.nvim_get_current_buf()
vim.cmd.edit(file("shown.lua"))
local shown = vim.api.nvim_get_current_buf()
vim.cmd.split(file("split.lua"))
local split = vim.api.nvim_get_current_buf()
-- Tabpage 2: elsewhere.lua, visible only there.
vim.cmd.tabedit(file("elsewhere.lua"))
local elsewhere = vim.api.nvim_get_current_buf()
vim.cmd.tabprevious()
-- Hidden, but not file buffers: none of these may go.
local scratch_unlisted = vim.api.nvim_create_buf(false, true)
local nofile = vim.api.nvim_create_buf(true, false)
vim.bo[nofile].buftype = "nofile"
local acwrite = vim.api.nvim_create_buf(true, false)
vim.bo[acwrite].buftype = "acwrite" -- oil's directory buffers
vim.api.nvim_buf_set_name(acwrite, "oil://" .. dir .. "/")
local job_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_call(job_buf, function() vim.fn.jobstart({ "sh", "-c", "cat" }, { term = true }) end)
t.eq(vim.bo[job_buf].buftype, "terminal", "fixture: a hidden terminal buffer")

local buffer = require("util.buffer")
t.ok(buffer.is_hidden(hidden), "a file no window shows is hidden")
t.ok(not buffer.is_hidden(shown) and not buffer.is_hidden(split), "files in this tabpage's windows are not")
t.ok(not buffer.is_hidden(elsewhere), "a file shown only in another tabpage is not")
t.eq(vim.fn.bufwinnr(elsewhere), -1, "fixture: bufwinnr, which invisible() asks, cannot see it from here")
for name, buf in pairs({ nofile = nofile, acwrite = acwrite, terminal = job_buf }) do
  t.ok(not buffer.is_hidden(buf), "a hidden " .. name .. " buffer is not a file buffer")
end

local before = layout()
local current = vim.api.nvim_get_current_win()
map.callback()
t.ok(not listed(hidden), "the hidden file buffer is deleted")
t.ok(listed(shown) and listed(split), "buffers in this tabpage's windows survive")
t.ok(listed(elsewhere), "the buffer shown only in the other tabpage survives")
t.ok(listed(nofile) and listed(acwrite) and listed(job_buf) and vim.api.nvim_buf_is_valid(scratch_unlisted),
  "non-file and unlisted buffers survive")
t.eq(layout(), before, "no window in any tabpage changed its buffer")
t.eq(vim.api.nvim_get_current_win(), current, "focus stays where it was")
t.eq(notices[#notices], "Deleted 1 hidden buffer", "the count is reported")

-- Nothing left to clean: a notice, not an error.
notices = {}
t.ok(pcall(buffer.delete_hidden), "running with nothing hidden does not error")
t.eq(notices[#notices], "No hidden buffers", "and says so")

-- A modified buffer gets Snacks' save prompt; Cancel keeps it.
vim.cmd.badd(file("modified.lua"))
local modified = vim.fn.bufnr(dir .. "/modified.lua")
vim.fn.bufload(modified)
vim.api.nvim_buf_set_lines(modified, 0, -1, false, { "changed" })
local confirm = vim.fn.confirm
local asked
vim.fn.confirm = function(msg) asked = msg; return 3 end -- Cancel
notices = {}
buffer.delete_hidden()
vim.fn.confirm = confirm
t.ok(asked ~= nil and asked:find("modified.lua", 1, true) ~= nil, "a modified hidden buffer asks before going")
t.ok(listed(modified) and vim.bo[modified].modified, "Cancel keeps it, changes and all")
t.eq(notices[#notices], "Deleted 0 hidden buffers", "and it is not counted as deleted")
vim.api.nvim_buf_delete(modified, { force = true })

-- `<leader>bx` deletes the listed
-- buffers whose files are gone from disk and nothing else: terminals,
-- URI-scheme buffers and unnamed scratch buffers have no file to be missing,
-- and a buffer whose file still exists must survive. After the <leader>bh
-- counts above, so its buffers cannot change them.
local kept, gone = file("kept.lua"), file("gone.lua")
vim.cmd.edit(kept)
local kept_buf = vim.api.nvim_get_current_buf()
vim.cmd.edit(gone)
local gone_buf = vim.api.nvim_get_current_buf()
vim.cmd("badd oil:///tmp")
local uri_buf = vim.fn.bufnr("oil:///tmp")
vim.cmd("badd codediff:////tmp/repo///0123abcd/x.lua")
local codediff_buf = vim.fn.bufnr("codediff:////tmp/repo///0123abcd/x.lua")
local scratch_buf = vim.api.nvim_create_buf(true, false)

vim.fn.delete(gone)

t.ok(buffer.is_missing_file(gone_buf), "a deleted file's buffer is reported missing")
t.ok(not buffer.is_missing_file(kept_buf), "an existing file's buffer is not")
t.ok(not buffer.is_missing_file(uri_buf), "an oil:// buffer is not a missing file")
t.ok(not buffer.is_missing_file(codediff_buf), "a codediff:// buffer is not a missing file")
t.ok(not buffer.is_missing_file(scratch_buf), "an unnamed scratch buffer is not a missing file")

local missing_map = vim.fn.maparg("<leader>bx", "n", false, true)
t.ok(missing_map.lhs ~= nil, "<leader>bx is mapped")
t.eq(missing_map.desc, "Delete buffers of missing files", "and carries its desc")

buffer.delete_missing()

t.ok(not vim.api.nvim_buf_is_valid(gone_buf) or not vim.bo[gone_buf].buflisted,
  "the deleted file's buffer is gone")
t.ok(vim.api.nvim_buf_is_valid(kept_buf) and vim.bo[kept_buf].buflisted,
  "the existing file's buffer survives")
t.ok(vim.api.nvim_buf_is_valid(uri_buf) and vim.api.nvim_buf_is_valid(codediff_buf)
  and vim.api.nvim_buf_is_valid(scratch_buf), "URI and scratch buffers survive")
t.ok(vim.api.nvim_win_is_valid(vim.api.nvim_get_current_win()), "the window layout survives")

-- Nothing left to clean: the second run must be a no-op, not an error.
t.ok(pcall(buffer.delete_missing), "running with nothing to clean does not error")

-- Every window on an unlisted buffer (a dashboard, an agent terminal): Snacks
-- then creates an empty listed buffer to stand in for the last one deleted.
-- Nothing would show it, so it must not stay behind in the bufferline.
vim.cmd("tabonly")
vim.cmd("only")
vim.api.nvim_set_current_buf(scratch_unlisted)
vim.cmd.badd(file("one.lua"))
vim.cmd.badd(file("two.lua"))
-- kept_buf onwards are the <leader>bx block's, which nothing shows now either.
for _, buf in ipairs({ shown, split, elsewhere, nofile, acwrite, kept_buf, uri_buf, codediff_buf, scratch_buf }) do
  vim.bo[buf].buflisted = false
end
vim.fn.jobstop(vim.bo[job_buf].channel)
vim.bo[job_buf].buflisted = false
buffer.delete_hidden()
local left = vim.tbl_filter(function(b) return vim.bo[b].buflisted end, vim.api.nvim_list_bufs())
t.eq(left, {}, "no stray [No Name] buffer is left when the last listed one goes")
t.eq(vim.api.nvim_get_current_buf(), scratch_unlisted, "the window keeps its unlisted buffer")

vim.notify = notify
vim.fn.delete(dir, "rf")
t.done()
