-- GitHub reading buffers belong to the editor area. Opening/cancelling ;f
-- must not leave a blank split below an issue beside the agent panel.
local t = dofile("tests/helper.lua")
require("lazy").load({ plugins = { "edgy.nvim" } })
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

-- Keep the real GitHub buffer setup/rendering, supplying the remote data
-- locally so the spec never needs GitHub credentials or makes a request.
local api = require("snacks.gh.api")
local view = api.view
api.view = function(callback, item) callback(item, false) end
local Item = require("snacks.gh.item")
local Buf = require("snacks.gh.buf")

local background = vim.api.nvim_get_current_tabpage()
local background_win = vim.api.nvim_get_current_win()
local background_buf = vim.api.nvim_get_current_buf()
vim.cmd.tabnew()
local tab = vim.api.nvim_get_current_tabpage()
vim.cmd.lcd(root)
local reading_win = vim.api.nvim_get_current_win()
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
  t.eq(vim.api.nvim_win_get_buf(agent.win), agent.buf, "the agent keeps its terminal window")
  t.eq(vim.fn.jobwait({ vim.bo[agent.buf].channel }, 0)[1], -1, "the agent process stays alive")
end

for _, kind in ipairs({ "issue", "pr" }) do
  vim.api.nvim_set_current_win(reading_win)
  local item = Item.new({
    number = 23,
    title = "Reading fixture",
    author = { login = "fixture" },
    state = "OPEN",
    body = "# Goal\n\n## Review\n\n- first\n- second",
  }, { repo = "fixture/repo", type = kind })
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, item.uri)
  vim.api.nvim_win_set_buf(reading_win, buf)
  local gh = Buf.new(buf, item)
  settle()
  t.eq(vim.bo[buf].filetype, "markdown.gh", kind .. " uses the actual GitHub reading view")
  t.eq(vim.wo[reading_win].foldcolumn, "0", kind .. " hides the fold depth column")
  t.ok(not vim.wo[reading_win].number and not vim.wo[reading_win].relativenumber,
    kind .. " keeps the reading view free of line numbers")

  for _, origin in ipairs({ reading_win, agent.win }) do
    vim.api.nvim_set_current_win(origin)
    local picker = open_picker()
    t.eq(picker.main, reading_win, kind .. " is the file target from either side")
    t.eq(vim.fn.winlayout(), original_layout, "showing the picker creates no layout split")
    picker:close()
    settle()
    t.eq(vim.fn.winlayout(), original_layout, "cancelling preserves the original layout")
    t.eq(vim.api.nvim_win_get_buf(reading_win), buf, "cancelling leaves the reading buffer visible")
    agent_intact()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= reading_win and win ~= agent.win then vim.api.nvim_win_close(win, false) end
    end
  end

  vim.api.nvim_set_current_win(reading_win)
  local picker = open_picker()
  picker.input:set("picked.txt")
  picker:find()
  t.ok(vim.wait(2000, function()
    local item = picker:current()
    return not picker:is_active() and item and vim.fs.basename(item.file) == "picked.txt"
  end, 10), "the picker finds the requested file")
  require("snacks.picker.actions").jump(picker, nil, {})
  settle()
  t.eq(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(reading_win)), root .. "/picked.txt",
    "confirming opens the file in the reading view's window")
  t.eq(vim.fn.winlayout(), original_layout, "confirming keeps the same layout")
  t.ok(vim.api.nvim_buf_is_valid(buf), "the issue/PR buffer is kept for returning later")
  t.eq(vim.wo[reading_win].foldcolumn, "1", "the file keeps its ordinary fold column")
  t.ok(vim.wo[reading_win].number, "the file keeps its ordinary line numbers")
  agent_intact()

  -- Re-entering and refreshing apply the gh view options again.
  vim.api.nvim_win_set_buf(reading_win, buf)
  gh:render()
  settle()
  t.eq(vim.wo[reading_win].foldcolumn, "0", "returning/refreshing keeps the fold column hidden")
end

-- Only unmodified reading views may be replaced. Keep any pending content
-- visible rather than broadening the exception to every acwrite buffer.
vim.api.nvim_set_current_win(reading_win)
local buf = vim.api.nvim_get_current_buf()
vim.bo[buf].modifiable = true
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "pending content" })
local pending = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
local picker = open_picker()
t.ok(picker.main ~= reading_win and picker.main ~= agent.win, "pending edits get a separate file target")
picker:close()
settle()
t.eq(vim.api.nvim_win_get_buf(reading_win), buf, "the modified reading buffer stays visible")
t.eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), pending, "pending content is preserved")
t.ok(vim.bo[buf].modified, "pending content stays unsaved")
agent_intact()
vim.bo[buf].modified = false

t.eq(vim.api.nvim_get_current_tabpage(), tab, "file navigation stays in the current tab")
t.eq(vim.api.nvim_tabpage_list_wins(background), { background_win }, "the other tab's layout is untouched")
t.eq(vim.api.nvim_win_get_buf(background_win), background_buf, "the other tab's buffer is untouched")
api.view = view
agent:close()
vim.cmd.tabclose()
vim.fn.delete(root, "rf")
t.done()
