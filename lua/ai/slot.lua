-- The AI slot: per tabpage, the right edgebar shows at most one AI window.
--
-- What can occupy it -- a "chat" in the keys' words -- is computed from live
-- state on every call, never registered here:
--
--   native:claude  claudecode's single Snacks terminal (one per Nvim)
--   native:codex   ai.backend.codex's single terminal (one per Nvim)
--   cc:<buf>:<id>  every live CodeCompanion chat, whatever opened it
--
-- Showing one hides the other AI windows in this tabpage through their own
-- owner's hide -- claudecode's cc_hide, Snacks' hide, CodeCompanion's
-- ui:hide -- which keeps every job, tmux client, ACP session and buffer. Never
-- edgy's hide or close (they drop a non-pinned window for good), never a
-- stop, close or wipe, never another tabpage. A window its owner cannot hide
-- is left alone: claudecode's copy of its terminal in a diff tabpage, a chat
-- buffer shown in a second window. Such a copy still counts as shown here:
-- a key delivers to it where it is and opens nothing beside it. Only
-- <leader>ac closes one, a chat's whose own window is in another tabpage
-- (the successor <C-c> leaves there), since the chat stays on screen. Hiding
-- comes first and showing second, so a terminal is not squeezed and redrawn
-- for nothing; when the windows to hide are all the tabpage has, the order
-- turns round (E444).
--
-- Between two chats the window is handed over in place (lua/ai/companion.lua,
-- show). Between a terminal and anything else it cannot be: Snacks' fixbuf
-- sends any other buffer back out of a terminal window, and closes the window
-- when there is nowhere to send it -- so one window closes, another opens.
--
-- A BufWinEnter guard holds the rule for every path that never comes through
-- here: <leader>ao (history), a typed :CodeCompanionChat or :ClaudeCode, the
-- action palette, `}`/`{` in a chat, the chat CodeCompanion puts in the place
-- of one closed with <C-c>, claudecode showing its terminal again after a
-- diff. It records the tabpage when the event fires, and gives up if that is
-- no longer the current one when its scheduled half runs.
--
-- "The chat on the right" (target) is read off the windows alone: the one
-- shown in this tabpage; from a CodeDiff view, the one shown in the tabpage
-- the view came from; otherwise the user is asked. Nothing is ever delivered
-- to a hidden chat, another tabpage's or the default backend without asking.
-- vim.t.ai_slot_last only lets <leader>ac/af bring the last one back.
-- claudecode's passive selection tracking is not part of this: it stays on,
-- so a running Claude still sees the editor's selection while it is hidden.
--
-- Nothing here loads claudecode.nvim or CodeCompanion to answer: a native
-- agent is asked through its backend, chats only once CodeCompanion has loaded
-- and only through lua/ai/companion.lua, which reads a chat's internals.

local config = require("ai.config")

local M = {}

local api = vim.api
local INFO, WARN, ERROR = vim.log.levels.INFO, vim.log.levels.WARN, vim.log.levels.ERROR

local function notify(msg, level) vim.notify(msg, level or INFO, { title = "AI" }) end
local function backend(agent) return require("ai.backend." .. agent) end
local function companion() return require("ai.companion") end

---A backend's answer, or nil when it raised: one agent's failing question must
---not stop the slot from working with the other.
local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
end

local function nonfloat(win)
  return api.nvim_win_is_valid(win) and api.nvim_win_get_config(win).relative == ""
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

---@class ai.SlotItem
---@field id string "native:<agent>" or "cc:<buf>:<chat id>"
---@field kind "native"|"chat"
---@field agent? string native: the provider
---@field chat? table chat: the CodeCompanion.Chat
---@field entry? table chat: what buf_get_chat() says of it
---@field win? integer a window showing it, where one was looked for

---@param agent string
---@return ai.SlotItem
function M.native_item(agent) return { id = "native:" .. agent, kind = "native", agent = agent } end

---@param chat table
---@return ai.SlotItem
function M.chat_item(chat)
  return { id = companion().key(chat), kind = "chat", chat = chat }
end

---The buffer `item` shows in; nil once it is gone.
---@param item ai.SlotItem
---@return integer|nil
function M.buf_of(item)
  if item.kind == "native" then return ask(backend(item.agent).buf) end
  return companion().buf(item.chat)
end

---Every open chat: the native agents that run, then every live CodeCompanion
---chat, oldest first.
---@return ai.SlotItem[]
function M.list()
  local items = {}
  for _, agent in ipairs(config.names()) do
    if ask(backend(agent).running) then items[#items + 1] = M.native_item(agent) end
  end
  for _, entry in ipairs(companion().chats()) do
    local item = M.chat_item(entry.chat)
    item.entry = entry
    items[#items + 1] = item
  end
  return items
end

---The chat `buf` belongs to, if it is one.
---@param buf integer
---@return ai.SlotItem|nil
function M.item_of_buf(buf)
  for _, agent in ipairs(config.names()) do
    if ask(backend(agent).buf) == buf then return M.native_item(agent) end
  end
  local chat = companion().chat_of(buf)
  return chat and M.chat_item(chat) or nil
end

---Bring an id (vim.t.ai_slot_last) back to a live item.
---@param id string?
---@return ai.SlotItem|nil
local function resolve(id)
  if type(id) ~= "string" then return nil end
  local agent = id:match("^native:(.+)$")
  if agent then
    return config.providers[agent] and ask(backend(agent).running) and M.native_item(agent) or nil
  end
  local buf = id:match("^cc:(%d+):")
  local chat = buf and companion().chat_of(tonumber(buf))
  return chat and companion().key(chat) == id and M.chat_item(chat) or nil
end

---What `item` is called in a picker or a notice, its billing included.
---@param item ai.SlotItem
---@return string
function M.label(item)
  if item.kind == "native" then return config.providers[item.agent].label .. " · terminal · subscription" end
  return companion().label(item.chat, item.entry)
end

---The agent's or the chat's short name, for a sentence.
local function name(item)
  if item.kind == "native" then return config.providers[item.agent].label end
  return companion().name(item.chat)
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------

---Every item shown in `tab` by a non-floating window, whoever opened that
---window, in window order; each carries the first such `win`.
---@param tab integer?
---@return ai.SlotItem[]
function M.shown(tab)
  tab = tab or api.nvim_get_current_tabpage()
  local by_buf = {}
  for _, item in ipairs(M.list()) do
    local buf = M.buf_of(item)
    if buf then by_buf[buf] = item end
  end
  local out, seen = {}, {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
    local item = nonfloat(win) and by_buf[api.nvim_win_get_buf(win)]
    if item and not seen[item.id] then
      seen[item.id] = true
      item.win = win
      out[#out + 1] = item
    end
  end
  return out
end

---The tabpage that shows `item` in any non-floating window, this one first.
---@param item ai.SlotItem
---@return integer|nil
local function tab_showing(item)
  local buf = M.buf_of(item)
  if not buf then return nil end
  local tabs = api.nvim_list_tabpages()
  table.insert(tabs, 1, api.nvim_get_current_tabpage())
  for _, tab in ipairs(tabs) do
    for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
      if nonfloat(win) and api.nvim_win_get_buf(win) == buf then return tab end
    end
  end
end

---Where `item`'s owner shows it: in its own window here, in its own window in
---another tabpage, or nowhere. The owner's window only -- a copy (Claude's in
---a diff tabpage) is neither; make_room and reveal look at copies here first.
---@param item ai.SlotItem
---@return "here"|"elsewhere"|"hidden"
function M.state(item)
  if item.kind == "native" then
    local b = backend(item.agent)
    if ask(b.visible) then return "here" end
    return ask(b.window) and "elsewhere" or "hidden"
  end
  return companion().where(item.chat)
end

---The owner's window for a chat, when it is in this tabpage.
local function chat_win_here(chat)
  local win = companion().win(chat)
  if win and api.nvim_win_get_tabpage(win) == api.nvim_get_current_tabpage() then return win end
end

---The AI windows in this tabpage an owner can hide, except `keep`'s.
---@param keep ai.SlotItem?
---@return { item: ai.SlotItem, win?: integer }[]
function M.victims(keep)
  local out = {}
  for _, agent in ipairs(config.names()) do
    if not (keep and keep.id == "native:" .. agent) then
      local b = backend(agent)
      if ask(b.visible) then out[#out + 1] = { item = M.native_item(agent), win = ask(b.window) } end
    end
  end
  for _, entry in ipairs(companion().chats()) do
    local item = M.chat_item(entry.chat)
    item.entry = entry
    local win = chat_win_here(entry.chat)
    if win and not (keep and keep.id == item.id) then out[#out + 1] = { item = item, win = win } end
  end
  return out
end

---Another chat's window in this tabpage, which `item` (a chat) can take over.
---@param item ai.SlotItem
---@return { item: ai.SlotItem, win: integer }|nil
function M.chat_window_here(item)
  for _, v in ipairs(M.victims(item)) do
    if v.item.kind == "chat" then return v end
  end
end

---Would hiding `victims` leave this tabpage without a window?
local function would_empty(victims)
  if #victims == 0 then return false end
  local theirs = {}
  for _, v in ipairs(victims) do
    if v.win then theirs[v.win] = true end
  end
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if nonfloat(win) and not theirs[win] then return false end
  end
  return true
end

---Hide `item` in this tabpage through its owner. A chat that is mid-turn --
---replying, or waiting for a tool approval -- says so as it goes: hidden, it
---would otherwise wait unseen.
---@param item ai.SlotItem
---@param opts? { keep_window?: boolean } a chat: leave its window for the next chat
function M.hide(item, opts)
  local ok, err
  if item.kind == "native" then
    ok, err = pcall(backend(item.agent).hide)
  else
    if companion().busy(item.chat) then
      notify(("%s is still working (replying or waiting for an approval) — hidden; <leader>al brings it back")
        :format(M.label(item)))
    end
    ok, err = companion().hide(item.chat, opts)
  end
  if not ok then require("util.vim_error").notify(err) end
end

---Hide every AI window here an owner can hide, except `keep`'s.
---@param keep ai.SlotItem?
---@return integer hidden how many there were
function M.cover(keep)
  local victims = M.victims(keep)
  for _, v in ipairs(victims) do M.hide(v.item) end
  return #victims
end

---Run `open`, which shows `keep` here, with the rest hidden: before it, or --
---when they are all this tabpage has -- after it.
---@param keep ai.SlotItem
---@param open fun()
function M.around(keep, open)
  local victims = M.victims(keep)
  local later = would_empty(victims)
  if not later then
    for _, v in ipairs(victims) do M.hide(v.item) end
  end
  open()
  if later then M.cover(keep) end
end

---Remember `item` as this tabpage's last chat, for <leader>ac/af.
---@param item ai.SlotItem
function M.remember(item)
  vim.t.ai_slot_last = item.id
end

---Go to the tabpage whose window shows `item`; nothing moves.
---@param item ai.SlotItem
---@param opts? { focus?: boolean }
---@return boolean
function M.jump(item, opts)
  opts = opts or {}
  local win
  if item.kind == "native" then win = ask(backend(item.agent).window) else win = companion().win(item.chat) end
  if not (win and api.nvim_win_is_valid(win)) then return false end
  local tab = api.nvim_win_get_tabpage(win)
  if tab ~= api.nvim_get_current_tabpage() then
    api.nvim_set_current_tabpage(tab)
    notify(("%s is shown in tab %d: went there"):format(name(item), api.nvim_tabpage_get_number(tab)))
  end
  if opts.focus ~= false then
    api.nvim_set_current_win(win)
    if vim.bo[api.nvim_win_get_buf(win)].buftype == "terminal" then vim.cmd("startinsert") end
  end
  return true
end

---A cold start belongs in the editor window, so the agent's root comes from
---the edited file, not from a chat or a term:// buffer.
---@return boolean
local function to_editor()
  local win = require("util.window").editor_win()
  if not win then
    notify("No editor window in this tab to start the agent from", WARN)
    return false
  end
  if win ~= api.nvim_get_current_win() then api.nvim_set_current_win(win) end
  return true
end

---Make room for `item`, which a backend method is about to show or start:
---go to the tabpage showing it, or hide the other AI windows here. The method
---itself shows it -- only on "room": on "here" and "elsewhere" a window shows
---it already. When the windows to hide are all this tabpage has, they stay
---until it does, and the guard hides them then. Nil when refused: a native
---agent to start with no editor window to start it from.
---@param item ai.SlotItem
---@param opts? { jump?: boolean, editor?: boolean } jump to another tabpage (default true); start from the editor window (default true)
---@return "here"|"elsewhere"|"room"|nil
function M.make_room(item, opts)
  opts = opts or {}
  -- On screen here in any window -- claudecode's copy of its terminal in a
  -- diff tabpage too, while its own window is hidden or in another tabpage:
  -- what is delivered goes there, and nothing opens or moves.
  if tab_showing(item) == api.nvim_get_current_tabpage() then return "here" end
  local state = M.state(item)
  if state == "here" then return "here" end
  if state == "elsewhere" then
    if opts.jump ~= false then M.jump(item, { focus = false }) end
    return "elsewhere"
  end
  if item.kind == "native" and opts.editor ~= false and not ask(backend(item.agent).running) then
    if not to_editor() then return nil end
  end
  local victims = M.victims(item)
  if not would_empty(victims) then
    for _, v in ipairs(victims) do M.hide(v.item) end
  end
  return "room"
end

---Show `item` and focus it -- a terminal in Terminal mode, a chat at its
---prompt -- starting a native agent that is not running. Never hides it.
---@param item ai.SlotItem
---@return boolean
function M.reveal(item)
  local buf = M.buf_of(item)
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if buf and nonfloat(win) and api.nvim_win_get_buf(win) == buf then
      -- On screen here already, in whichever window: into it.
      api.nvim_set_current_win(win)
      if item.kind == "native" then
        vim.cmd("startinsert")
      else
        api.nvim_win_set_cursor(win, { api.nvim_buf_line_count(buf), 0 })
      end
      M.remember(item)
      return true
    end
  end
  if M.state(item) == "elsewhere" then return M.jump(item) end
  if item.kind == "chat" then
    companion().focus_prompt(item.chat)
    M.remember(item)
    return true
  end
  local b = backend(item.agent)
  if not ask(b.running) and not to_editor() then return false end
  M.around(item, function() b.reveal() end)
  M.remember(item)
  return true
end

---------------------------------------------------------------------------
-- Asking
---------------------------------------------------------------------------

---Back to the tabpage a key was pressed in, when it asked from another one
---(home: the page a CodeDiff view came from) and then delivered nothing.
---@param tab integer?
local function back_to(tab)
  if tab and api.nvim_tabpage_is_valid(tab) and tab ~= api.nvim_get_current_tabpage() then
    api.nvim_set_current_tabpage(tab)
  end
end

---vim.ui.select, with the choice handled under a guard: it arrives later,
---outside the mapping that asked, where an error would be a traceback. A
---cancel calls nothing and goes `back` (see back_to).
---@param back integer? the tabpage the key was pressed in
local function select(items, opts, on_choice, back)
  vim.ui.select(items, opts, function(choice)
    if choice == nil then return back_to(back) end
    local ok, err = xpcall(on_choice, debug.traceback, choice)
    if not ok then notify("AI: " .. tostring(err), ERROR) end
  end)
end

---Where an item is, as a picker says it.
local function where(item)
  local tab = tab_showing(item)
  if not tab then return "hidden" end
  if tab == api.nvim_get_current_tabpage() then return "● here" end
  return ("tab %d"):format(api.nvim_tabpage_get_number(tab))
end

local function lastused(item)
  local buf = M.buf_of(item)
  local info = buf and vim.fn.getbufinfo(buf)[1]
  return info and info.lastused or 0, buf or 0
end

---Ask for a backend and start a chat on it; `cb` gets the chat. A native
---agent's entry stands for its one session: a running one is offered as it
---is, and `cb` gets it without starting it -- the caller's reveal or delivery
---starts what is not running, and a session that started is announced. A
---CodeCompanion chat is created here, hidden, and announces itself.
---@param cb fun(item: ai.SlotItem)
---@param opts? { prompt?: string, native_only?: boolean, back?: integer } native_only: the terminals alone, for a key a chat cannot take; back: see back_to
function M.pick_new(cb, opts)
  opts = opts or {}
  local entries = vim.tbl_filter(function(b)
    return b.available and (not opts.native_only or b.kind == "native")
  end, config.backends())
  if #entries == 0 then
    back_to(opts.back)
    return notify(opts.native_only and "No native agent is installed (claude, codex)"
      or "No AI backend is available here — see :checkhealth config", WARN)
  end
  local here = api.nvim_get_current_tabpage()
  select(entries, {
    prompt = opts.prompt or "New AI chat",
    kind = "ai_slot_new",
    format_item = function(b)
      local state = ""
      if b.kind == "native" then
        local item = M.native_item(b.agent)
        if ask(backend(b.agent).running) then
          state = tab_showing(item) == here and " · ● here" or " · running"
        end
      end
      return b.label .. state .. (b.warn and (" · ⚠ " .. b.warn) or "")
    end,
  }, function(b)
    if b.kind == "native" then
      local was = ask(backend(b.agent).running)
      cb(M.native_item(b.agent))
      -- Only a session that did start: a cold start can be refused (no
      -- editor window to start it from).
      if not was and ask(backend(b.agent).running) then notify("New chat: " .. b.label) end
      return
    end
    local chat = companion().create(b)
    if chat then cb(M.chat_item(chat)) end
  end, opts.back)
end

---Ask which open chat: the ones shown here first, then the most recently used.
---The last entry starts a new one; with none open, that is all there is to ask.
---@param cb fun(item: ai.SlotItem)
---@param opts? { prompt?: string, items?: ai.SlotItem[], new?: boolean, native_only?: boolean, back?: integer } see pick_new
function M.switch(cb, opts)
  opts = opts or {}
  local items = opts.items or M.list()
  if opts.native_only then
    local natives = vim.tbl_filter(function(item) return item.kind == "native" end, items)
    -- Choosing among the chats shown here, none of them native: those are
    -- what there is, and the caller says what a chat takes instead.
    if #natives > 0 or opts.new ~= false then items = natives end
  end
  if #items == 0 then return M.pick_new(cb, opts) end
  local rank = {}
  for _, item in ipairs(items) do
    local used, buf = lastused(item)
    rank[item.id] = { where(item) == "● here" and 1 or 0, used, buf }
  end
  table.sort(items, function(a, b)
    local x, y = rank[a.id], rank[b.id]
    for i = 1, 3 do
      if x[i] ~= y[i] then return x[i] > y[i] end
    end
    return false
  end)
  local entries = vim.list_extend({}, items)
  if opts.new ~= false then entries[#entries + 1] = { new = true } end
  select(entries, {
    prompt = opts.prompt or "Switch AI chat",
    kind = "ai_slot_switch",
    format_item = function(entry)
      if entry.new then return "New chat…" end
      local busy = entry.kind == "chat" and companion().busy(entry.chat) and " · replying" or ""
      return ("%s · %s%s"):format(M.label(entry), where(entry), busy)
    end,
  }, function(entry)
    if entry.new then return M.pick_new(cb, opts) end
    cb(entry)
  end, opts.back)
end

---The chats on the right of the tabpage the keys act in: this one, or, from a
---CodeDiff view with none of its own, the page the view came from -- which
---becomes the current tabpage, so nothing opens inside the view.
---@return ai.SlotItem[] shown, integer from the tabpage the key was pressed in
local function home()
  local from = api.nvim_get_current_tabpage()
  local shown = M.shown(from)
  if #shown == 0 then
    local origin = require("util.window").origin_tab(from)
    if origin then
      api.nvim_set_current_tabpage(origin)
      shown = M.shown(origin)
    end
  end
  return shown, from
end
M.home = home

---Of several chats shown here, the one in the current window.
local function current_of(shown)
  local buf = api.nvim_get_current_buf()
  for _, item in ipairs(shown) do
    if M.buf_of(item) == buf then return item end
  end
end

---The chat on the right without asking: the one shown in this tabpage, or of
---several the current window's. Nil when that would take a question.
---@return ai.SlotItem|nil
function M.target_now()
  local shown = M.shown()
  if #shown == 1 then return shown[1] end
  return current_of(shown)
end

---The chat on the right without asking and without going anywhere: the one
---shown in this tabpage, else -- from a prefix-blocking view (CodeDiff) -- the
---one shown in the page the view came from; of several, the current
---window's. Nil where only a question could tell. For callers that may
---neither ask nor move, such as the review loop's owner fallbacks
---(lua/ai/review/rounds.lua).
---@return ai.SlotItem|nil
function M.shown_here()
  local tab = api.nvim_get_current_tabpage()
  local shown = M.shown(tab)
  if #shown == 0 then
    local origin = require("util.window").origin_tab(tab)
    if origin then shown = M.shown(origin) end
  end
  if #shown == 1 then return shown[1] end
  return current_of(shown)
end

---Resolve the chat on the right, then call `cb` with it: the one shown here
---(see home); of several, the current window's, else the one picked among
---them; with none, the one picked among every open chat, or a new one. A
---cancelled question calls nothing, and goes back to the tabpage the key
---was pressed in. `native_only` asks among the native agents alone, for a key
---only they take: a chat would be shown or created for nothing.
---@param cb fun(item: ai.SlotItem, from: integer)
---@param opts? { prompt?: string, native_only?: boolean }
function M.target(cb, opts)
  opts = opts or {}
  local shown, from = home()
  local function done(item) cb(item, from) end
  if #shown == 1 then return done(shown[1]) end
  local ask_opts = { prompt = opts.prompt, native_only = opts.native_only, back = from }
  if #shown > 1 then
    local item = current_of(shown)
    if item then return done(item) end
    return M.switch(done, vim.tbl_extend("force", ask_opts, { items = shown, new = false }))
  end
  return M.switch(done, ask_opts)
end

---Say where a delivery went when that was not the tabpage the key was
---pressed in.
---@param item ai.SlotItem
---@param from integer?
function M.went(item, from)
  local now = api.nvim_get_current_tabpage()
  if from and from ~= now then
    notify(("Sent to %s (tab %d)"):format(name(item), api.nvim_tabpage_get_number(now)))
  end
end

---------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------

---With nothing on the right: the last chat this tabpage showed, when it is
---alive and not shown in another one; else the only open chat; else ask.
---@param back integer? see back_to
local function bring_back(cb, back)
  local last = resolve(vim.t.ai_slot_last)
  if last and M.state(last) ~= "elsewhere" then return cb(last) end
  local items = M.list()
  if #items == 1 then return cb(items[1]) end
  return M.switch(cb, { back = back })
end

---Close this tabpage's copies of chats whose own window is in another
---tabpage: <C-c> shows its successor in the closed chat's window, which
---becomes the successor's own, and leaves the successor's buffer in the
---window that showed it before. The chat stays on screen in its own window,
---so nothing is hidden, stopped or wiped; never the last window here.
---@param shown ai.SlotItem[]
---@return integer closed
local function close_copies(shown)
  local closed = 0
  for _, item in ipairs(shown) do
    if item.kind == "chat" and M.state(item) == "elsewhere" then
      local buf = M.buf_of(item)
      for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
        if nonfloat(win) and api.nvim_win_get_buf(win) == buf then
          local others = vim.tbl_filter(function(w) return w ~= win and nonfloat(w) end, api.nvim_tabpage_list_wins(0))
          if #others > 0 then
            api.nvim_win_close(win, false)
            closed = closed + 1
          end
        end
      end
    end
  end
  return closed
end

---<leader>ac: hide what is on the right, or bring a chat back.
function M.toggle()
  local shown, from = home()
  if #shown == 0 then return bring_back(M.reveal, from) end
  local victims = M.victims()
  -- Each owner would answer differently -- CodeCompanion's :hide closes the
  -- tabpage, Snacks leaves an empty window, claudecode none -- so none does.
  if would_empty(victims) then
    return notify(("%s is this tabpage's only window: <leader>ac would leave nothing in its place")
      :format(name(victims[1].item)))
  end
  if M.cover() > 0 then return end
  if close_copies(shown) > 0 then return end
  local item = shown[1]
  if item.kind == "native" and item.agent == "claude" then
    return notify("This is Claude Code's diff tabpage: answer it with <leader>aa / <leader>ad")
  end
  notify(("%s is shown here in a window it cannot hide"):format(name(item)))
end

---<leader>af: into the chat on the right, never hiding it; with none, the
---way <leader>ac brings one back.
function M.focus()
  local shown, from = home()
  if #shown == 0 then return bring_back(M.reveal, from) end
  local item = #shown == 1 and shown[1] or current_of(shown)
  if item then return M.reveal(item) end
  return M.switch(M.reveal, { items = shown, new = false, back = from })
end

---The native agent on the right, else the one asked for -- the installed
---agents, the default's first; with one installed, that one -- for the keys
---only a native agent answers (resume, continue, model).
---@param cb fun(agent: string)
---@param opts? { prompt?: string }
function M.native_target(cb, opts)
  opts = opts or {}
  local shown, from = home()
  local natives = vim.tbl_filter(function(item) return item.kind == "native" end, shown)
  if #natives == 1 then return cb(natives[1].agent) end
  local current = #natives > 1 and current_of(natives)
  if current then return cb(current.agent) end
  local agents = {}
  for _, b in ipairs(config.backends()) do
    if b.kind == "native" and b.available then agents[#agents + 1] = b.agent end
  end
  if #agents == 0 then
    back_to(from)
    return notify("No native agent is installed (claude, codex)", WARN)
  end
  if #agents == 1 then return cb(agents[1]) end
  select(agents, {
    prompt = opts.prompt or "Which native agent?",
    kind = "ai_slot_agent",
    format_item = function(agent) return config.providers[agent].label end,
  }, cb, from)
end

---------------------------------------------------------------------------
-- The guard
---------------------------------------------------------------------------

-- Windows a buffer entered since the guard last ran, per tabpage, in order.
local entered = {}

---An AI buffer entered a window by any path: once the event is over, hide the
---other AI windows of the tabpage it happened in. Files are skipped at once;
---floats (a picker previewing a chat) never count. The events of one tick are
---handled together and the latest AI one wins: a guard scheduled for an
---earlier reveal must not hide what was opened after it.
local function on_buf_win_enter(ev)
  local buf = ev.buf
  if not api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype == "" then return end
  local win, tab = api.nvim_get_current_win(), api.nvim_get_current_tabpage()
  if not nonfloat(win) then return end
  local queued = entered[tab]
  entered[tab] = queued or {}
  table.insert(entered[tab], { win = win, buf = buf })
  if queued then return end
  vim.schedule(function()
    local events = entered[tab] or {}
    entered[tab] = nil
    local ok, err = xpcall(function()
      -- Another tabpage by now: hiding there would be a cross-tab change.
      if api.nvim_get_current_tabpage() ~= tab then return end
      for i = #events, 1, -1 do
        local e = events[i]
        -- A window that shows something else by now saw a transition (a split
        -- that showed the old buffer first).
        if api.nvim_win_is_valid(e.win) and api.nvim_win_get_buf(e.win) == e.buf then
          local item = M.item_of_buf(e.buf)
          if item then
            M.remember(item)
            M.cover(item)
            return
          end
        end
      end
    end, debug.traceback)
    if not ok then notify("AI slot guard failed:\n" .. tostring(err), WARN) end
  end)
end

---A chat asks for a tool approval while no tabpage shows it.
local function on_approval(ev)
  local chat = companion().chat_of(ev.data and ev.data.bufnr or -1)
  if not chat or companion().where(chat) ~= "hidden" then return end
  notify(("%s is waiting for a tool approval — <leader>al shows it"):format(M.label(M.chat_item(chat))))
end

function M.setup()
  local group = api.nvim_create_augroup("ai_slot", { clear = true })
  local function guarded(what, fn)
    return function(ev)
      local ok, err = xpcall(fn, debug.traceback, ev)
      if not ok then notify(("AI slot %s failed:\n%s"):format(what, err), WARN) end
    end
  end
  api.nvim_create_autocmd("BufWinEnter", { group = group, callback = guarded("guard", on_buf_win_enter) })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeCompanionToolApprovalRequested",
    callback = guarded("approval notice", on_approval),
  })
end

return M
