-- Clicking a file tab from an agent panel must leave the panel on screen.
-- Exercise bufferline's real mouse dispatcher, Snacks' fixbuf and Edgy.
local t = dofile("tests/helper.lua")
require("lazy").load({ plugins = { "bufferline.nvim", "edgy.nvim" } })
vim.o.columns = 240
vim.o.lines = 60

local function settle()
  vim.wait(150, function() return false end, 10)
  vim.cmd.stopinsert()
  vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = 240 })
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local files = {}
for _, name in ipairs({ "first.txt", "second.txt" }) do
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, root .. "/" .. name)
  files[#files + 1] = buf
end

vim.api.nvim_set_current_buf(files[1])
local background_tab = vim.api.nvim_get_current_tabpage()
local background_win = vim.api.nvim_get_current_win()
vim.cmd("tabnew")
local current_tab = vim.api.nvim_get_current_tabpage()

for _, provider in ipairs({ "claude", "codex" }) do
  local bin = root .. "/" .. provider
  vim.fn.writefile({ "#!/bin/sh", "exec cat" }, bin)
  vim.fn.setfperm(bin, "rwx------")
  vim.api.nvim_set_current_buf(files[1])
  local editor = vim.api.nvim_get_current_win()
  local term = Snacks.terminal.open({ bin }, {
    interactive = false,
    win = { position = "right", width = require("ai.config").panel.width },
  })
  settle()
  local channel = vim.bo[term.buf].channel

  for _, only_panel in ipairs({ false, true }) do
    if only_panel then vim.api.nvim_win_close(editor, false); settle() end
    for _, buf in ipairs({ files[2], files[1], files[2] }) do
      if term:win_valid() then vim.api.nvim_set_current_win(term.win) end
      _G.___bufferline_private.handle_click(buf, 1, "l")
      settle()
      t.ok(term:win_valid() and vim.api.nvim_win_get_buf(term.win) == term.buf,
        provider .. ": clicking a file keeps the panel visible (only_panel=" .. tostring(only_panel) .. ")")
      t.eq(vim.fn.jobwait({ channel }, 0)[1], -1, provider .. ": the session keeps running")
      t.eq(vim.api.nvim_get_current_buf(), buf, "the clicked file gets focus")
      t.eq(vim.api.nvim_get_current_tabpage(), current_tab, "the click stays in this tabpage")
      t.eq(vim.api.nvim_win_get_buf(background_win), files[1], "the other tabpage stays untouched")
    end
  end
  term:close()
  vim.fn.jobstop(channel)
  settle()
  vim.cmd("only")
end

-- A chat buffer does not have Snacks' terminal fixbuf fallback. Its window
-- must still survive a file-tab click, with and without a separate editor.
vim.api.nvim_set_current_buf(files[1])
local editor = vim.api.nvim_get_current_win()
local chat = vim.api.nvim_create_buf(false, true)
vim.bo[chat].filetype = "codecompanion"
local chat_win = vim.api.nvim_open_win(chat, true, { split = "right", width = 80 })
settle()
for _, only_panel in ipairs({ false, true }) do
  if only_panel then vim.api.nvim_win_close(editor, false); settle() end
  vim.api.nvim_set_current_win(chat_win)
  _G.___bufferline_private.handle_click(files[2], 1, "l")
  settle()
  t.ok(vim.api.nvim_win_is_valid(chat_win) and vim.api.nvim_win_get_buf(chat_win) == chat,
    "chat stays visible (only_panel=" .. tostring(only_panel) .. ")")
  t.eq(vim.api.nvim_get_current_buf(), files[2], "the clicked file opens outside chat")
  t.eq(vim.api.nvim_get_current_tabpage(), current_tab, "chat's file click stays in this tabpage")
end
-- The buffer-list keys act as a click does: bufferline opens a buffer in the
-- current window, so ]B / [B from the chat put the file in the chat's own
-- window, and ]b / [b found no chat buffer in the list to cycle from.
local elements = require("bufferline").get_elements().elements
for _, case in ipairs({ { "]B", elements[#elements].id }, { "[B", elements[1].id }, { "]b" }, { "[b" } }) do
  vim.api.nvim_set_current_win(chat_win)
  local before = vim.api.nvim_win_get_buf(require("util.window").ensure_editor_win())
  vim.api.nvim_feedkeys(vim.keycode(case[1]), "mx", false)
  settle()
  t.ok(vim.api.nvim_win_is_valid(chat_win) and vim.api.nvim_win_get_buf(chat_win) == chat,
    case[1] .. " from the chat leaves it on screen")
  t.ok(vim.api.nvim_get_current_win() ~= chat_win and vim.api.nvim_get_current_buf() == (case[2] or vim.api.nvim_get_current_buf())
    and (case[2] or vim.api.nvim_get_current_buf() ~= before),
    case[1] .. " acts on the editor's buffer list, in the editor")
end
vim.api.nvim_win_close(chat_win, false)
vim.api.nvim_buf_delete(chat, {})

-- File tabs still act on the focused editor split, even if another editor
-- was last recorded before leaving it. They do not always pick the widest.
vim.cmd("vsplit")
local focused_editor = vim.api.nvim_get_current_win()
_G.___bufferline_private.handle_click(files[1], 1, "l")
settle()
t.eq(vim.api.nvim_get_current_win(), focused_editor, "a file click keeps the focused editor split")
t.eq(vim.api.nvim_get_current_buf(), files[1], "that split receives the file")

vim.api.nvim_set_current_tabpage(background_tab)
vim.fn.delete(root, "rf")
t.done()
