local t = dofile("tests/helper.lua")
local config = require("ai.config")

-- Both native providers use a Snacks terminal docked by Edgy. A provider-named
-- stand-in exercises those rules without starting a real agent session.
vim.cmd("Lazy! load edgy.nvim")
vim.cmd("Lazy! load oil.nvim")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/child", "p")
root = vim.uv.fs_realpath(root)
local bin = root .. "/" .. config.native.command
vim.fn.writefile({ "#!/bin/sh", "exec cat" }, bin)
vim.fn.setfperm(bin, "rwx------")
vim.fn.writefile({ "original editor" }, root .. "/original.txt")
vim.fn.writefile({ "picked file" }, root .. "/child/picked.txt")

local function settle()
  vim.wait(250, function() return false end, 10)
end

local function press(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
  settle()
end

local function panel()
  local term = Snacks.terminal.open({ bin }, {
    cwd = root .. "/child",
    auto_insert = true,
    start_insert = true,
    auto_close = true,
    win = { position = "right", width = 0.4, keys = { term_normal = false } },
  })
  settle()
  vim.api.nvim_set_current_win(term.win)
  vim.cmd("stopinsert")
  t.ok(require("util.terminal").is_agent_buf(term.buf), "the panel has the active provider's identity")
  t.eq(vim.fn.maparg("-", "t"), "", "typing - in terminal input still belongs to the agent")
  return term
end

local function alive(term)
  t.ok(term:win_valid() and vim.api.nvim_win_get_buf(term.win) == term.buf,
    "Oil leaves the agent panel visible with its terminal buffer")
  t.eq(vim.fn.jobwait({ vim.bo[term.buf].channel }, 0)[1], -1,
    "the agent process is still running")
end

-- An editor in another tab must never become the target.
vim.cmd("edit " .. vim.fn.fnameescape(root .. "/original.txt"))
local background_tab = vim.api.nvim_get_current_tabpage()
local background_win = vim.api.nvim_get_current_win()
local background_buf = vim.api.nvim_get_current_buf()
vim.cmd("tabnew")
vim.cmd("lcd " .. vim.fn.fnameescape(root .. "/child"))
local current_tab = vim.api.nvim_get_current_tabpage()

for _, only_panel in ipairs({ false, true }) do
  vim.cmd("enew")
  local editor_win = vim.api.nvim_get_current_win()
  local editor_buf = vim.api.nvim_get_current_buf()
  local term = panel()
  if only_panel then
    vim.api.nvim_win_close(editor_win, false)
    settle()
  end

  for _, key in ipairs({ "-", ";o" }) do
    vim.api.nvim_set_current_win(term.win)
    vim.cmd("stopinsert")
    press(key)
    t.eq(vim.bo.filetype, "oil", key .. " focuses Oil from the agent panel")
    if vim.bo.filetype == "oil" then
      local oil_win = vim.api.nvim_get_current_win()
      t.ok(oil_win ~= term.win, key .. " opens outside the protected terminal window")
      t.eq(vim.api.nvim_get_current_tabpage(), current_tab, "Oil stays in the current tab")
      t.eq(vim.uv.fs_realpath(require("oil").get_current_dir()), root .. "/child",
        "Oil starts in the terminal window's working directory")
      if key == "-" then
        if not only_panel then
          t.eq(oil_win, editor_win, "Oil reuses the existing editor window")
        end
        press("-")
        t.eq(vim.uv.fs_realpath(require("oil").get_current_dir()), root,
          "pressing - again navigates Oil without returning focus to the agent")
      end
      press("q")
      t.ok(vim.bo.filetype ~= "oil", "q closes Oil")
      t.eq(vim.bo.buftype, "", "q returns to an ordinary editor buffer")
      if not only_panel then
        t.eq(vim.api.nvim_get_current_buf(), editor_buf, "q restores the original editor buffer")
      end
    end
    alive(term)
    t.eq(vim.api.nvim_win_get_buf(background_win), background_buf,
      "the other tab's editor is untouched")
    if only_panel and key == "-" and vim.bo.buftype == "" then
      vim.api.nvim_win_close(vim.api.nvim_get_current_win(), false)
      settle()
    end
  end
  vim.api.nvim_chan_send(vim.bo[term.buf].channel, "\4")
  t.ok(vim.wait(1000, function() return not term:buf_valid() end, 10),
    "the stand-in agent exits cleanly during test cleanup")
  settle()
end

vim.api.nvim_set_current_tabpage(current_tab)
vim.cmd("tabclose!")
vim.api.nvim_set_current_tabpage(background_tab)
vim.fn.delete(root, "rf")
t.done()
