-- A Snacks terminal must not enter the ordinary buffer navigation list.
-- Selecting its `env` entry replaced the editor's buffer with the agent, then
-- edgy moved that window into the right edge alongside the original panel.
local t = dofile("tests/helper.lua")
require("lazy").load({ plugins = { "bufferline.nvim", "edgy.nvim" } })
vim.o.columns = 240
vim.o.lines = 60

local function settle()
  local done = false
  vim.defer_fn(function() done = true end, 100)
  vim.wait(2000, function() return done end, 10)
  vim.cmd.stopinsert()
  vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = 240 })
end

local function file(name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)
  return buf
end

for _, buf in ipairs(vim.api.nvim_list_bufs()) do vim.bo[buf].buflisted = false end
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local first = file(dir .. "/first.lua")
vim.api.nvim_set_current_buf(first)
local editor = vim.api.nvim_get_current_win()

-- Use the same /usr/bin/env terminal name as the wrapper, without running a
-- real agent or touching a session. Identity follows the default backend.
local bin = dir .. "/" .. require("ai.config").providers[require("ai.config").default].native.command
vim.fn.writefile({ "#!/bin/sh", "exec cat" }, bin)
vim.fn.setfperm(bin, "rwx------")
local panel = Snacks.terminal.open({ "env", bin }, {
  interactive = false,
  win = { position = "right", width = require("ai.config").panel.width },
})
settle()
t.ok(require("edgy.editor").get_win(panel.win) ~= nil, "edgy owns the agent panel")
-- Snacks starts unlisted, but opening a hidden buffer through a picker lists
-- it again. Reproduce the screenshot's listed terminal, not only a fresh one.
vim.bo[panel.buf].buflisted = true

-- A real file named env must still be reachable; filter by buffer kind.
local last = file(dir .. "/env")
vim.api.nvim_set_current_win(editor)
settle()
vim.cmd("BufferLineCycleNext")
settle()
t.eq(vim.api.nvim_win_get_buf(editor), last, "next buffer skips the agent and opens the env file")
t.eq(#vim.api.nvim_tabpage_list_wins(0), 2, "cycling keeps the editor and one agent panel")
t.ok(require("edgy.editor").get_win(editor) == nil, "the editor is not absorbed into the AI edgebar")
t.eq(vim.api.nvim_win_get_buf(panel.win), panel.buf, "the original agent panel keeps its buffer")

-- Restore the editor explicitly so a failure above does not mask this path.
vim.api.nvim_set_current_win(editor)
vim.api.nvim_win_set_buf(editor, last)
settle()
vim.cmd("BufferLineCyclePrev")
settle()
t.eq(vim.api.nvim_win_get_buf(editor), first, "previous buffer also skips the agent")

for _, hidden in ipairs({ false, true }) do
  local picker = Snacks.picker.buffers({ hidden = hidden })
  settle()
  t.ok(not vim.iter(picker:items()):any(function(item) return item.buf == panel.buf end),
    "the buffer picker excludes terminals with hidden=" .. tostring(hidden))
  t.ok(vim.iter(picker:items()):any(function(item) return item.buf == last end),
    "the buffer picker still includes the ordinary env file")
  picker:close()
  settle()
end

local smart = Snacks.picker.smart({ cwd = dir, filter = { cwd = true } })
settle()
t.ok(not vim.iter(smart:items()):any(function(item) return item.buf == panel.buf end),
  "smart find also excludes the terminal from its buffers source")
t.ok(vim.iter(smart:items()):any(function(item) return item.buf == last end),
  "smart find retains ordinary buffers in the selected directory")
smart:close()
settle()

-- Ordinary Snacks shells also have their own focus path (,1..,9 / Ctrl-/).
require("util.terminal").focus(1)
local shell = vim.api.nvim_get_current_buf()
vim.bo[shell].buflisted = true
settle()
t.ok(not vim.iter(require("bufferline").get_elements().elements):any(function(item) return item.id == shell end),
  "even listed numbered shells stay out of the file tabline")
require("util.terminal").toggle()
require("util.terminal").focus(1)
t.eq(vim.api.nvim_get_current_buf(), shell, "terminal shortcuts still hide and reopen the same shell")

panel:close()
vim.api.nvim_chan_send(vim.bo[shell].channel, "exit\n")
vim.wait(2000, function() return not vim.api.nvim_buf_is_valid(shell) end, 10)
vim.fn.delete(dir, "rf")
t.done()
