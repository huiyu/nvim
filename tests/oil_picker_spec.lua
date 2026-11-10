-- File pickers should reuse the editor area when it contains an Oil listing.
-- Opening/cancelling ;f used to leave a blank split below Oil beside the agent.
local t = dofile("tests/helper.lua")
require("lazy").load({ plugins = { "oil.nvim", "edgy.nvim" } })
vim.o.columns = 240
vim.o.lines = 60

local function settle()
  vim.wait(150, function() return false end, 10)
  vim.cmd.stopinsert()
end

local function press(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
  settle()
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
vim.fn.writefile({ "picked file" }, root .. "/picked.txt")
local bin = root .. "/" .. require("ai.config").providers[require("ai.config").default].native.command
vim.fn.writefile({ "#!/bin/sh", "exec cat" }, bin)
vim.fn.setfperm(bin, "rwx------")

local background = vim.api.nvim_get_current_tabpage()
local background_win = vim.api.nvim_get_current_win()
local background_buf = vim.api.nvim_get_current_buf()
vim.cmd.tabnew()
local tab = vim.api.nvim_get_current_tabpage()
vim.cmd.lcd(root)
local oil_win = vim.api.nvim_get_current_win()
require("oil").open(root)
settle()
local oil_buf = vim.api.nvim_get_current_buf()
local agent = Snacks.terminal.open({ bin }, {
  interactive = false,
  win = { position = "right", width = require("ai.config").panel.width },
})
settle()
local original_layout = vim.fn.winlayout()

local function open_picker()
  press(";f")
  local picker = Snacks.picker.get({ source = "files" })[1]
  t.ok(picker ~= nil, ";f opens the real file picker")
  return assert(picker)
end

local function agent_intact()
  t.eq(vim.api.nvim_win_get_buf(agent.win), agent.buf, "the agent keeps its own terminal window")
  t.eq(vim.fn.jobwait({ vim.bo[agent.buf].channel }, 0)[1], -1, "the agent process stays alive")
end

-- Starting from either side must use the same editor area. Cancelling should
-- not create an extra [No Name] buffer/window below it.
for _, origin in ipairs({ oil_win, agent.win }) do
  vim.api.nvim_set_current_win(origin)
  local layout = vim.fn.winlayout()
  local picker = open_picker()
  t.eq(picker.main, oil_win, "an unmodified Oil window is the file target")
  t.eq(vim.fn.winlayout(), layout, "showing the picker does not create a layout split")
  picker:close()
  settle()
  t.eq(vim.fn.winlayout(), layout, "cancelling leaves the original layout")
  t.eq(vim.api.nvim_win_get_buf(oil_win), oil_buf, "cancelling leaves Oil's listing in place")
  agent_intact()
  -- Keep the failing version's extra window from masking the next case.
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= oil_win and win ~= agent.win then vim.api.nvim_win_close(win, false) end
  end
end

vim.api.nvim_set_current_win(oil_win)
local picker = open_picker()
picker.input:set("picked.txt")
picker:find()
t.ok(vim.wait(2000, function()
  local item = picker:current()
  return not picker:is_active() and item and vim.fs.basename(item.file) == "picked.txt"
end, 10),
  "the picker finds the requested file")
require("snacks.picker.actions").jump(picker, nil, {})
settle()
t.eq(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(oil_win)), root .. "/picked.txt",
  "confirming replaces Oil with the selected file in the same window")
t.eq(vim.fn.winlayout(), original_layout, "confirming keeps one editor and one agent panel")
agent_intact()

-- Directory edits are real pending filesystem operations. They must stay
-- visible and unmodified while the picker uses a different file target.
vim.api.nvim_set_current_win(oil_win)
require("oil").open(root)
settle()
oil_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(oil_buf, -1, -1, false, { "not-written.txt" })
local staged = vim.api.nvim_buf_get_lines(oil_buf, 0, -1, false)
picker = open_picker()
t.ok(picker.main ~= oil_win and picker.main ~= agent.win, "pending Oil edits get a separate file target")
picker:close()
settle()
t.eq(vim.api.nvim_buf_get_lines(oil_buf, 0, -1, false), staged, "pending directory edits are preserved")
t.ok(vim.bo[oil_buf].modified, "pending directory edits are still unsaved")
t.eq(vim.api.nvim_win_get_buf(oil_win), oil_buf, "the modified listing stays visible")
agent_intact()
t.eq(vim.api.nvim_get_current_tabpage(), tab, "file navigation stays in the current tab")
t.eq(vim.api.nvim_tabpage_list_wins(background), { background_win }, "the other tab's layout is untouched")
t.eq(vim.api.nvim_win_get_buf(background_win), background_buf, "the other tab's buffer is untouched")

vim.bo[oil_buf].modified = false
agent:close()
vim.cmd.tabclose()
vim.fn.delete(root, "rf")
t.done()
