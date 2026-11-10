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
local function codediff_key(lhs)
  for _, key in ipairs(require("lazy.core.config").plugins["codediff.nvim"].keys) do
    if key[1] == lhs then return key[2] end
  end
end
local outside = vim.fn.tempname()
vim.fn.mkdir(outside, "p")
local cwd = vim.fn.getcwd()
vim.cmd("lcd " .. vim.fn.fnameescape(outside))
local tabs = #vim.api.nvim_list_tabpages()
reset()
ok = pcall(codediff_key("<leader>gm"))
t.ok(ok, "<leader>gm outside a repository does not raise")
t.ok(said("not a git repository"), "it reports git's own reason")
t.eq(#vim.api.nvim_list_tabpages(), tabs, "and opens no diff view")
reset()
ok = pcall(codediff_key("<leader>gM"))
t.ok(ok, "<leader>gM outside a repository does not raise")
t.ok(said("not a git repository"), "it reports git's own reason as well")
for _, lhs in ipairs({ "<leader>gv", "<leader>gH" }) do
  reset()
  ok = pcall(codediff_key(lhs))
  t.ok(ok and said("not a git repository"), lhs .. " outside a repository reports git's reason")
end
t.eq(#vim.api.nvim_list_tabpages(), tabs, "and none of them opens a view")
vim.cmd("lcd " .. vim.fn.fnameescape(cwd))

-- <leader>at when the transcript view fails. With no native agent on the
-- right it asks whose transcript, among the agents installed -- stand-ins on
-- PATH here -- the default first: that one is answered.
local transcript = require("ai.transcript")
local ai_config = require("ai.config")
local real_open, real_select, real_path = transcript.open_current, vim.ui.select, vim.env.PATH
local stand_ins = vim.fn.tempname()
vim.fn.mkdir(stand_ins, "p")
for _, name in ipairs({ "claude", "codex" }) do
  vim.fn.writefile({ "#!/bin/sh", "exec cat" }, stand_ins .. "/" .. name)
  vim.fn.setfperm(stand_ins .. "/" .. name, "rwx------")
end
vim.env.PATH = stand_ins .. ":" .. real_path
local asked_for
transcript.open_current = function(agent)
  asked_for = agent
  error("boom")
end
vim.ui.select = function(items, _, on_choice) on_choice(items[1]) end
reset()
ok = pcall(require("ai").transcript)
vim.ui.select, vim.env.PATH = real_select, real_path
vim.fn.delete(stand_ins, "rf")
t.ok(ok, "<leader>at does not raise when the transcript view fails")
t.eq(last() and last().level, vim.log.levels.ERROR, "it reports the failure")
t.ok(said("boom"), "with its cause")
t.eq(asked_for, ai_config.default, "for the agent it was asked for, the default first")
transcript.open_current = real_open

-- :AI with a subcommand or a name it does not know, and the one it no longer
-- has.
local key_before = ai_config.key_setting()
reset()
ok = pcall(vim.cmd, "AI key nope")
t.ok(ok, ":AI key with an unknown name does not raise")
t.eq(#notified, 1, "it notifies once")
t.ok(last() and last().level == vim.log.levels.ERROR and said("Unknown AI key profile"), "with the reason, as an error")
t.eq(ai_config.key_setting(), key_before, "and the key profile is unchanged")
reset()
ok = pcall(vim.cmd, "AI provider codex")
t.ok(ok and #notified == 1 and last().level == vim.log.levels.ERROR and said(":AI new"),
  ":AI provider is gone, and says where its job went")

-- <leader>aa answers Claude's diffs whatever is on the right, so a failure
-- there is reported against Claude.
local claude_backend = require("ai.backend.claude")
local real_accept = claude_backend.accept_diff
claude_backend.accept_diff = function() error("no pending diff") end
reset()
ok = pcall(require("ai").accept_diff)
t.ok(ok, "<leader>aa does not raise when the diff command fails")
t.ok(said("Claude Code accept_diff failed") and said("no pending diff"),
  "it names Claude, whose diff it was, whichever agent is the default")
claude_backend.accept_diff = real_accept

vim.notify = real_notify
t.done()
