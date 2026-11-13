-- The tabline and the tabpages: it never hides itself, the first tabpage stays
-- one the global prefixes work in, and neither a file-tab click nor buffer
-- navigation takes an agent panel's window.
local t = dofile("tests/helper.lua")

-- bufferline loads on VeryLazy, after the first frame. Until then the row
-- comes from lua/config/options.lua: a `1` there would leave the first frame without
-- it, and the whole screen would move down a line once bufferline turned it on.
t.eq(vim.o.showtabline, 2, "the tabline is on before bufferline loads")
-- VeryLazy has not fired while a spec runs.
require("lazy").load({ plugins = { "bufferline.nvim" } })

local function settle()
  vim.wait(150, function() return false end, 10)
  vim.cmd.stopinsert()
  vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = 240 })
end

local function unlist_everything()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then vim.bo[buf].buflisted = false end
  end
end

--- An `exec cat` stand-in at `dir/name`, so a terminal running it carries
--- that agent's identity without starting a real session.
local function stand_in(dir, name)
  local bin = dir .. "/" .. name
  vim.fn.writefile({ "#!/bin/sh", "exec cat" }, bin)
  vim.fn.setfperm(bin, "rwx------")
  return bin
end

---------------------------------------------------------------------------
-- The tabline never hides itself
---------------------------------------------------------------------------
-- Left to itself bufferline hides the whole tabline whenever it has at most one
-- buffer to show, and its count never looks at tabpages. Opening a diff with no
-- files loaded therefore hid the far-right `1`/`2` tabpage indicators along
-- with the buffer list -- at the one moment they matter most, since CodeDiff
-- disables the global prefixes inside its tabpage and knowing another one
-- exists is the way out.
do
  --- The rendered tabline, as Nvim would draw it.
  local function rendered()
    return vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = 120 }).str
  end

  vim.cmd("tabonly")
  unlist_everything()
  vim.cmd("doautocmd BufAdd")
  settle()
  t.eq(vim.o.showtabline, 2, "nothing listed and one tabpage still shows the tabline")

  -- The bug was bufferline turning it off again from the tabline's own redraw
  -- (`_G.nvim_bufferline`), so a draw has to leave it alone.
  rendered()
  settle()
  t.eq(vim.o.showtabline, 2, "a tabline redraw does not turn it off")

  vim.cmd("tabnew")
  settle()
  t.eq(vim.o.showtabline, 2, "a second tabpage keeps it shown")
  t.ok(rendered():match("%f[%w]1%f[%W].*%f[%w]2%f[%W]") ~= nil,
    "and the tabpage indicators are actually drawn")

  vim.cmd("tabclose")
  unlist_everything()
  vim.cmd("badd init.lua")
  vim.cmd("doautocmd BufAdd")
  settle()
  t.eq(vim.o.showtabline, 2, "a single buffer keeps it shown")

  -- The filter that keeps CodeDiff's revision buffers out of the bufferline
  -- still applies; it just no longer decides whether the tabline exists.
  vim.cmd("badd codediff:////tmp/repo///0123abcd/a.lua")
  settle()
  t.ok(rendered():match("a%.lua") == nil, "CodeDiff's revision buffers stay out of the list")

  -- The permanent tabline must not draw a band across the top when it is empty.
  -- The colorscheme runs with `transparent`, which clears Normal but leaves
  -- TabLineFill opaque, and bufferline's unset `fill` background inherits that
  -- group rather than reaching the terminal -- so both have to be clear.
  for _, group in ipairs({ "BufferLineFill", "TabLineFill" }) do
    t.eq(vim.api.nvim_get_hl(0, { name = group, link = false }).bg, nil,
      group .. " has no background, so an empty tabline stays invisible")
  end
end

---------------------------------------------------------------------------
-- The first tabpage is one the global prefixes work in
---------------------------------------------------------------------------
-- CodeDiff disables `;` and `s` inside its own tabpage. Views open after the
-- editing page already -- `tab split` inserts after the current tabpage -- so
-- the invariant breaks only when the pages in front of a view go away, and
-- then there is nowhere left to run `;f` from. The guard notices that
-- state and puts a fresh page back in front.
do
  local win = require("util.window")

  local function filetypes(tabpage)
    local fts = {}
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
      if vim.api.nvim_win_get_config(w).relative == "" then
        fts[#fts + 1] = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
      end
    end
    return fts
  end

  local editor_tab = vim.api.nvim_get_current_tabpage()

  -- A real CodeDiff tabpage is a git operation and a whole plugin load; the
  -- guard reads the tabpage variable util.codediff sets while the view is open,
  -- so setting it is the honest stand-in for one. Two ordinary windows, as a
  -- single-file `:CodeDiff file` has: no panel to recognise it by.
  vim.cmd("tabnew")
  local view_tab = vim.api.nvim_get_current_tabpage()
  vim.t.blocks_global_prefixes = true
  vim.cmd("vsplit")
  vim.cmd("enew")
  t.eq(vim.bo.buftype, "", "the stand-in carries an ordinary file window, as CodeDiff does")
  t.ok(win.blocks_global_prefixes(view_tab), "the tabpage variable marks a prefix-blocking view")
  t.ok(not win.blocks_global_prefixes(editor_tab), "and only where it is set")

  win.protect_first_tab()
  t.eq(#vim.api.nvim_list_tabpages(), 2, "a view behind an editing page is left alone")
  t.eq(vim.api.nvim_list_tabpages()[1], editor_tab, "and the editing page stays first")

  -- The reported end state: nothing in front of the view.
  vim.api.nvim_set_current_tabpage(view_tab)
  vim.cmd("noautocmd " .. vim.api.nvim_tabpage_get_number(editor_tab) .. "tabclose")
  t.eq(#vim.api.nvim_list_tabpages(), 1, "leaving the view as the only tabpage")

  win.protect_first_tab()
  t.eq(#vim.api.nvim_list_tabpages(), 2, "the guard restores a page in front of the view")
  t.eq(vim.api.nvim_list_tabpages()[2], view_tab, "the view keeps its windows, moved back one place")
  t.eq(vim.api.nvim_get_current_tabpage(), view_tab, "the repair does not steal focus")

  local restored = vim.api.nvim_list_tabpages()[1]
  local fts = filetypes(restored)
  t.eq(#fts, 1, "the restored page is a single window")
  t.eq(vim.bo[vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_list_wins(restored)[1])].buftype, "",
    "and it is a page a file can be opened into")

  win.protect_first_tab()
  t.eq(#vim.api.nvim_list_tabpages(), 2, "running the guard again adds nothing")

  -- A panel CodeDiff left on screen after its session went: the variable is
  -- cleared then, and the explorer's filetype still identifies the page.
  vim.t[view_tab].blocks_global_prefixes = nil
  t.ok(not win.blocks_global_prefixes(view_tab), "without the variable or a panel the page is ordinary")
  vim.api.nvim_set_current_tabpage(view_tab)
  vim.cmd("vnew")
  vim.bo.buftype = "nofile"
  vim.bo.filetype = "codediff-explorer"
  local explorer = vim.api.nvim_get_current_buf()
  t.ok(win.blocks_global_prefixes(view_tab), "a CodeDiff explorer window marks the page too")
  vim.api.nvim_set_current_tabpage(restored)
  vim.cmd("noautocmd tabclose")
  t.eq(#vim.api.nvim_list_tabpages(), 1, "closing the page in front leaves only the view")
  win.protect_first_tab()
  t.eq(#vim.api.nvim_list_tabpages(), 2, "and the guard puts a page back in front of it")
  restored = vim.api.nvim_list_tabpages()[1]

  -- The debug view is deliberately not protected against: its keys stay global
  -- and it carries a file window, so it is a perfectly good first page.
  vim.api.nvim_set_current_tabpage(restored)
  vim.bo.filetype = "dapui_scopes"
  win.protect_first_tab()
  t.eq(#vim.api.nvim_list_tabpages(), 2, "a debug panel does not make a page unusable")

  -- Hand the next blocks one ordinary tabpage, none of these stand-ins and an
  -- empty buffer list: edgy, loaded next, would take a dapui_scopes window.
  vim.bo.filetype = ""
  vim.cmd("tabonly")
  if vim.api.nvim_buf_is_valid(explorer) then vim.api.nvim_buf_delete(explorer, {}) end
  unlist_everything()
end

---------------------------------------------------------------------------
-- A file-tab click from an agent panel
---------------------------------------------------------------------------
-- Clicking a file tab from an agent panel must leave the panel on screen.
-- Exercise bufferline's real mouse dispatcher, Snacks' fixbuf and Edgy.
require("lazy").load({ plugins = { "edgy.nvim" } })
vim.o.columns = 240
vim.o.lines = 60

do
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
    local bin = stand_in(root, provider)
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
  -- Oil goes through the same target: from the chat it used to take the
  -- chat's own window, since only a terminal was sent to the editor.
  vim.api.nvim_set_current_win(chat_win)
  vim.api.nvim_feedkeys("-", "mx", false)
  settle()
  t.ok(vim.api.nvim_win_get_buf(chat_win) == chat and vim.api.nvim_get_current_win() ~= chat_win
    and vim.bo.filetype == "oil", "- from the chat opens Oil in the editor")
  vim.api.nvim_set_current_buf(files[1])
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
  vim.cmd("tabonly")
  vim.fn.delete(root, "rf")
end

---------------------------------------------------------------------------
-- Buffer navigation skips terminals
---------------------------------------------------------------------------
-- A Snacks terminal must not enter the ordinary buffer navigation list.
-- Selecting its `env` entry replaced the editor's buffer with the agent, then
-- edgy moved that window into the right edge alongside the original panel.
do
  local function file(name)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)
    return buf
  end

  unlist_everything()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local first = file(dir .. "/first.lua")
  vim.api.nvim_set_current_buf(first)
  local editor = vim.api.nvim_get_current_win()

  -- Use the same /usr/bin/env terminal name as the wrapper, without running a
  -- real agent or touching a session. Identity follows the first listed agent.
  local bin = stand_in(dir, require("ai.config").agents[require("ai.config").agent_names()[1]].command)
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
  -- Non-floating windows only: incline's label is a float in the tabpage.
  t.eq(#vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative == "" end,
    vim.api.nvim_tabpage_list_wins(0)), 2, "cycling keeps the editor and one agent panel")
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

  panel:close()
  vim.api.nvim_chan_send(vim.bo[shell].channel, "exit\n")
  vim.wait(2000, function() return not vim.api.nvim_buf_is_valid(shell) end, 10)
  vim.fn.delete(dir, "rf")
end

t.done()
