-- GitHub reading buffers and Oil listings belong to the editor area.
-- Opening/cancelling ;f must not leave a blank split below an issue, or below
-- Oil, beside the agent panel. The agent panel's own way into Oil (-, ;o,
-- <C-,>) follows as a block of its own.
local t = dofile("tests/helper.lua")
require("lazy").load({ plugins = { "oil.nvim", "edgy.nvim" } })
-- The last block runs at the size it was written for.
local columns, lines = vim.o.columns, vim.o.lines
vim.o.columns = 240
vim.o.lines = 60

-- Raised for the last block: its stand-in's exit and Oil's listings take longer.
local settle_ms = 150
local function settle()
  vim.wait(settle_ms, function() return false end, 10)
  vim.cmd.stopinsert()
end

local function press(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
  settle()
end

--- An `exec cat` stand-in in `dir`, named after the first listed agent's CLI,
--- so a terminal running it has that agent's identity without a real session.
local function stand_in(dir)
  local bin = dir .. "/" .. require("ai.config").agents[require("ai.config").agent_names()[1]].command
  vim.fn.writefile({ "#!/bin/sh", "exec cat" }, bin)
  vim.fn.setfperm(bin, "rwx------")
  return bin
end

local function agent_intact(term)
  t.ok(term:win_valid() and vim.api.nvim_win_get_buf(term.win) == term.buf,
    "the agent keeps its terminal window")
  t.eq(vim.fn.jobwait({ vim.bo[term.buf].channel }, 0)[1], -1, "the agent process stays alive")
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
vim.fn.writefile({ "picked file" }, root .. "/picked.txt")
local bin = stand_in(root)

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

--- The issue/PR picker <leader>Gi/<leader>Gp open, listing nothing, so no
--- request reaches GitHub.
local function open_gh_picker(kind)
  local picker = Snacks.picker["gh_" .. kind]({
    finder = function() return {} end,
    format = "text",
    preview = "none",
  })
  settle()
  return picker
end

-- An unmodified Oil listing is a reading view too: oil buffers are `acwrite`,
-- like GitHub's, and ;f used to leave a blank split below Oil.
for _, kind in ipairs({ "oil", "issue", "pr" }) do
  vim.api.nvim_set_current_win(reading_win)
  local buf, gh
  if kind == "oil" then
    require("oil").open(root)
    settle()
    buf = vim.api.nvim_get_current_buf()
  else
    local item = Item.new({
      number = 23,
      title = "Reading fixture",
      author = { login = "fixture" },
      state = "OPEN",
      body = "# Goal\n\n## Review\n\n- first\n- second",
    }, { repo = "fixture/repo", type = kind })
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, item.uri)
    vim.api.nvim_win_set_buf(reading_win, buf)
    gh = Buf.new(buf, item)
    settle()
    t.eq(vim.bo[buf].filetype, "markdown.gh", kind .. " uses the actual GitHub reading view")
    t.eq(vim.wo[reading_win].foldcolumn, "0", kind .. " hides the fold depth column")
    t.ok(not vim.wo[reading_win].number and not vim.wo[reading_win].relativenumber,
      kind .. " keeps the reading view free of line numbers")
  end

  -- Starting from either side must use the same editor area. Cancelling
  -- should not create an extra [No Name] buffer/window below it.
  for _, origin in ipairs({ reading_win, agent.win }) do
    vim.api.nvim_set_current_win(origin)
    local picker = open_picker()
    t.eq(picker.main, reading_win, kind .. " is the file target from either side")
    t.eq(vim.fn.winlayout(), original_layout, "showing the picker creates no layout split")
    picker:close()
    settle()
    t.eq(vim.fn.winlayout(), original_layout, "cancelling preserves the original layout")
    t.eq(vim.api.nvim_win_get_buf(reading_win), buf, "cancelling leaves the reading buffer visible")
    agent_intact(agent)
    -- "Open in buffer" from the issue/PR pickers jumps to the same target.
    -- Upstream's fallback is the window of the least recently used buffer,
    -- which put the next PR into the chat or agent panel beside the view.
    if gh then
      local gh_picker = open_gh_picker(kind)
      t.eq(gh_picker.main, reading_win, kind .. " picker opens into the reading view from either side")
      gh_picker:close()
      settle()
    end
    -- Keep the failing version's extra window from masking the next case.
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
  if gh then
    t.ok(vim.api.nvim_buf_is_valid(buf), "the issue/PR buffer is kept for returning later")
    t.eq(vim.wo[reading_win].foldcolumn, "1", "the file keeps its ordinary fold column")
    t.ok(vim.wo[reading_win].number, "the file keeps its ordinary line numbers")
  end
  agent_intact(agent)

  if gh then
    -- Re-entering and refreshing apply the gh view options again.
    vim.api.nvim_win_set_buf(reading_win, buf)
    gh:render()
    settle()
    t.eq(vim.wo[reading_win].foldcolumn, "0", "returning/refreshing keeps the fold column hidden")
  end
end

-- A caller that names its own target keeps it: CodeCompanion's /file and
-- /buffer pass `main`, so the file picked is added to the chat it came from.
vim.api.nvim_set_current_win(agent.win)
local own = Snacks.picker.files({ main = { file = false, float = true } })
settle()
t.eq(own.main, agent.win, "a picker given its own main keeps it")
own:close()
settle()

-- Only unmodified reading views may be replaced. Keep any pending content
-- visible rather than broadening the exception to every acwrite buffer.
vim.api.nvim_set_current_win(reading_win)
local buf = vim.api.nvim_get_current_buf()
vim.bo[buf].modifiable = true
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "pending content" })
local pending = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
-- Most of the PR picker's actions open nothing (browse, checkout, comment), so
-- with no window to take a buffer it leaves the layout alone instead.
local gh_picker = open_gh_picker("pr")
t.eq(vim.fn.winlayout(), original_layout, "the PR picker splits nothing when no window can take a buffer")
gh_picker:close()
settle()
local picker = open_picker()
t.ok(picker.main ~= reading_win and picker.main ~= agent.win, "pending edits get a separate file target")
picker:close()
settle()
t.eq(vim.api.nvim_win_get_buf(reading_win), buf, "the modified reading buffer stays visible")
t.eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), pending, "pending content is preserved")
t.ok(vim.bo[buf].modified, "pending content stays unsaved")
agent_intact(agent)
vim.bo[buf].modified = false

-- Directory edits are real pending filesystem operations. They must stay
-- visible and unmodified while the picker uses a different file target.
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if win ~= reading_win and win ~= agent.win then vim.api.nvim_win_close(win, false) end
end
vim.api.nvim_set_current_win(reading_win)
require("oil").open(root)
settle()
local oil_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(oil_buf, -1, -1, false, { "not-written.txt" })
local staged = vim.api.nvim_buf_get_lines(oil_buf, 0, -1, false)
picker = open_picker()
t.ok(picker.main ~= reading_win and picker.main ~= agent.win, "pending Oil edits get a separate file target")
picker:close()
settle()
t.eq(vim.api.nvim_buf_get_lines(oil_buf, 0, -1, false), staged, "pending directory edits are preserved")
t.ok(vim.bo[oil_buf].modified, "pending directory edits are still unsaved")
t.eq(vim.api.nvim_win_get_buf(reading_win), oil_buf, "the modified listing stays visible")
agent_intact(agent)
vim.bo[oil_buf].modified = false

t.eq(vim.api.nvim_get_current_tabpage(), tab, "file navigation stays in the current tab")
t.eq(vim.api.nvim_tabpage_list_wins(background), { background_win }, "the other tab's layout is untouched")
t.eq(vim.api.nvim_win_get_buf(background_win), background_buf, "the other tab's buffer is untouched")
api.view = view
agent:close()
vim.cmd.tabclose()
vim.fn.delete(root, "rf")

---------------------------------------------------------------------------
-- Oil from the agent panel
---------------------------------------------------------------------------
-- Both native agents use a Snacks terminal docked by Edgy. An agent-named
-- stand-in exercises those rules without starting a real agent session.
do
  vim.o.columns, vim.o.lines = columns, lines
  settle_ms = 250
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/child", "p")
  root = vim.uv.fs_realpath(root)
  local bin = stand_in(root)
  vim.fn.writefile({ "original editor" }, root .. "/original.txt")
  vim.fn.writefile({ "picked file" }, root .. "/child/picked.txt")

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
    t.ok(require("ai.terminal").is_agent_buf(term.buf), "the panel has the first listed agent's identity")
    t.eq(vim.fn.maparg("-", "t"), "", "typing - in terminal input still belongs to the agent")
    return term
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
      agent_intact(term)
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

  -- <C-,> counts an oil listing as the editor area. oil buffers are `acwrite`,
  -- so a middle window showing a directory used to be invisible to the jump:
  -- the key reported "No editor window in this tab" from the panel, and inside
  -- oil it had nothing to toggle back from.
  vim.cmd("only!")
  require("oil").open(root .. "/child")
  settle()
  t.eq(vim.bo.filetype, "oil", "the remaining window holds an oil listing")
  local oil_win = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  vim.cmd("terminal sleep 30")
  local term_win = vim.api.nvim_get_current_win()
  settle()
  vim.cmd("stopinsert")
  t.ok(term_win ~= oil_win, "the terminal opened in its own window")
  press("<C-,>")
  t.eq(vim.api.nvim_get_current_win(), oil_win, "Ctrl-comma reaches the oil listing from a terminal")
  press("<C-,>")
  t.eq(vim.api.nvim_get_current_win(), term_win, "Ctrl-comma toggles back out of the oil listing")
  vim.cmd("only!")

  vim.api.nvim_set_current_tabpage(current_tab)
  vim.cmd("tabclose!")
  vim.api.nvim_set_current_tabpage(background_tab)
  vim.fn.delete(root, "rf")
end

t.done()
