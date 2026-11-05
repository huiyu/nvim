-- `<leader>bx` deletes the listed buffers whose files are gone from disk and
-- nothing else: terminals, URI-scheme buffers and unnamed scratch buffers have
-- no file to be missing, and a buffer whose file still exists must survive.
local t = dofile("tests/helper.lua")
require("lazy").load({ plugins = { "bufferline.nvim", "snacks.nvim" } })

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local kept = dir .. "/kept.lua"
local gone = dir .. "/gone.lua"
vim.fn.writefile({ "-- kept" }, kept)
vim.fn.writefile({ "-- gone" }, gone)

vim.cmd.edit(kept)
local kept_buf = vim.api.nvim_get_current_buf()
vim.cmd.edit(gone)
local gone_buf = vim.api.nvim_get_current_buf()
vim.cmd("badd oil:///tmp")
local uri_buf = vim.fn.bufnr("oil:///tmp")
vim.cmd("badd diffview://null/x.lua")
local diffview_buf = vim.fn.bufnr("diffview://null/x.lua")
local scratch_buf = vim.api.nvim_create_buf(true, false)

vim.fn.delete(gone)

local buffer = require("util.buffer")
t.ok(buffer.is_missing_file(gone_buf), "a deleted file's buffer is reported missing")
t.ok(not buffer.is_missing_file(kept_buf), "an existing file's buffer is not")
t.ok(not buffer.is_missing_file(uri_buf), "an oil:// buffer is not a missing file")
t.ok(not buffer.is_missing_file(diffview_buf), "a diffview:// buffer is not a missing file")
t.ok(not buffer.is_missing_file(scratch_buf), "an unnamed scratch buffer is not a missing file")

local map = vim.fn.maparg("<leader>bx", "n", false, true)
t.ok(map.lhs ~= nil, "<leader>bx is mapped")
t.eq(map.desc, "Delete buffers of missing files", "and carries its desc")

buffer.delete_missing()

t.ok(not vim.api.nvim_buf_is_valid(gone_buf) or not vim.bo[gone_buf].buflisted,
  "the deleted file's buffer is gone")
t.ok(vim.api.nvim_buf_is_valid(kept_buf) and vim.bo[kept_buf].buflisted,
  "the existing file's buffer survives")
t.ok(vim.api.nvim_buf_is_valid(uri_buf) and vim.api.nvim_buf_is_valid(diffview_buf)
  and vim.api.nvim_buf_is_valid(scratch_buf), "URI and scratch buffers survive")
t.ok(vim.api.nvim_win_is_valid(vim.api.nvim_get_current_win()), "the window layout survives")

-- Nothing left to clean: the second run must be a no-op, not an error.
local ok = pcall(buffer.delete_missing)
t.ok(ok, "running with nothing to clean does not error")

vim.fn.delete(dir, "rf")
t.done()
