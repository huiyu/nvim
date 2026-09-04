-- Refused actions surface as one notification, never as a traceback.
--
-- `vim.cmd` and the `nvim_*` API turn Nvim's refusal of an ordinary state --
-- last window, read-only file, no LSP client, no git repository -- into a Lua
-- error, and a mapping or command callback that lets it escape prints an
-- E5108 block with a stack traceback for what `:q` typed by hand shows as one
-- line. Each block below is one such entry point.
local t = dofile("tests/helper.lua")

local notified = {}
local real_notify = vim.notify
vim.notify = function(msg, level) notified[#notified + 1] = { msg = tostring(msg), level = level } end
local function last() return notified[#notified] end
local function reset() notified = {} end
local function said(text) return last() ~= nil and last().msg:find(text, 1, true) ~= nil end

-- util.vim_error: Nvim's own line, without what Lua wraps around it.
local vim_error = require("util.vim_error")
t.eq(vim_error.message("vim/_core/editor.lua:0: nvim_exec2(), line 1: Vim(write):E45: 'readonly' option is set (add ! to override)"),
  "E45: 'readonly' option is set (add ! to override)", "a vim.cmd error keeps only Nvim's line")
t.eq(vim_error.message("Vim:E444: Cannot close last window"),
  "E444: Cannot close last window", "an API error keeps only Nvim's line")
t.eq(vim_error.message("Vim(lsp):No clients attached to current buffer"),
  "No clients attached to current buffer", "an Ex error without a number keeps its text")
t.eq(vim_error.message("something else"), "something else", "anything else passes through")

-- sd on the last window.
local window = require("util.window")
reset()
local ok = pcall(window.close_current)
t.ok(ok, "sd on the last window does not raise")
t.eq(last() and last().level, vim.log.levels.WARN, "it warns instead")
t.ok(said("E444"), "with Nvim's own E444 line")

-- so from a float over a single editor window.
local editor_win = vim.api.nvim_get_current_win()
local float_buf = vim.api.nvim_create_buf(false, true)
local float = vim.api.nvim_open_win(float_buf, true,
  { relative = "editor", row = 1, col = 1, width = 10, height = 3 })
reset()
ok = pcall(window.close_others)
t.ok(ok, "so from a float does not raise")
t.ok(vim.api.nvim_win_is_valid(editor_win), "the last editor window is kept")
t.ok(said("E444"), "and the refusal is reported")
vim.api.nvim_win_close(float, true)

-- ,x on a read-only file with unsaved edits.
local run = require("util.run")
run.register("refusal_spec", function(path) return "true " .. vim.fn.shellescape(path) end)
local file = vim.fn.tempname() .. ".txt"
vim.fn.writefile({ "x" }, file)
vim.cmd("edit " .. vim.fn.fnameescape(file))
vim.bo.filetype = "refusal_spec"
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "edited" })
vim.bo.readonly = true
local wins = #vim.api.nvim_tabpage_list_wins(0)
reset()
ok = pcall(run.run_current)
t.ok(ok, ",x on a read-only buffer with edits does not raise")
t.ok(said("E45"), "it reports Nvim's E45 line")
t.eq(#vim.api.nvim_tabpage_list_wins(0), wins, "and opens no terminal")

-- ...while without edits there is nothing to write, so it runs.
vim.bo.modified = false
reset()
ok = pcall(run.run_current)
t.ok(ok, ",x on a clean read-only buffer does not raise")
t.eq(#notified, 0, "and says nothing")
t.eq(#vim.api.nvim_tabpage_list_wins(0), wins + 1, "because it ran")
vim.cmd("only")

-- :GoplsRebuildIndex with no LSP client attached.
vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, true))
reset()
ok = pcall(vim.cmd, "GoplsRebuildIndex")
t.ok(ok, "GoplsRebuildIndex with no client does not raise")
t.eq(last() and last().level, vim.log.levels.WARN, "it warns")
t.ok(said("No LSP client"), "that there is nothing to restart")

-- <leader>gm and <leader>gM outside a git repository.
local function diffview_key(lhs)
  for _, key in ipairs(require("lazy.core.config").plugins["diffview.nvim"].keys) do
    if key[1] == lhs then return key[2] end
  end
end
local outside = vim.fn.tempname()
vim.fn.mkdir(outside, "p")
local cwd = vim.fn.getcwd()
vim.cmd("lcd " .. vim.fn.fnameescape(outside))
local tabs = #vim.api.nvim_list_tabpages()
reset()
ok = pcall(diffview_key("<leader>gm"))
t.ok(ok, "<leader>gm outside a repository does not raise")
t.ok(said("not a git repository"), "it reports git's own reason")
t.eq(#vim.api.nvim_list_tabpages(), tabs, "and opens no diff view")
reset()
ok = pcall(diffview_key("<leader>gM"))
t.ok(ok, "<leader>gM outside a repository does not raise")
t.ok(said("not a git repository"), "it reports git's own reason as well")
vim.cmd("lcd " .. vim.fn.fnameescape(cwd))

-- <leader>at when the transcript view fails.
local transcript = require("ai.transcript")
local real_open = transcript.open_current
transcript.open_current = function() error("boom") end
reset()
ok = pcall(require("ai").transcript)
t.ok(ok, "<leader>at does not raise when the transcript view fails")
t.eq(last() and last().level, vim.log.levels.ERROR, "it reports the failure")
t.ok(said("boom"), "with its cause")
transcript.open_current = real_open

vim.notify = real_notify
t.done()
