-- CodeCompanion chats, for the facade (lua/ai/init.lua) and the AI slot
-- (lua/ai/slot.lua). Two kinds, by transport and billing:
--
--   acp   agent chat  an agent CLI over ACP, on the subscription
--   http  API chat    a key profile over HTTP, on API credits
--
-- A chat is created by spec (create: one of ai.config.backends(), hidden at
-- first) and then put on screen as exactly that chat (show). <leader>ag/aG and
-- <leader>ah/aH still pick "the chat of a kind on its current adapter" (find),
-- which upstream's Toggle and Add cannot do: they only know `last_chat`.
--
-- show() never calls upstream's Chat.open without a window. That path closes
-- `last_chat` wherever it is shown, another tabpage included. Instead: a chat
-- shown in another tabpage is gone to, not moved here; a chat window here is
-- handed over in place (the shown chat's ui:hide({ keep_window = true }), then
-- Chat.open({ ui, winnr }), which is ui:show_in_win); with none, ui:open()
-- splits a window of its own after the slot has hidden what else is shown
-- here. Chats are created with `hidden = true` for the same reason -- upstream
-- opens a visible new chat through that same window-less Chat.open -- which
-- also means one is not upstream's last_chat until it is first entered.
--
-- That reaches into CodeCompanion's chat internals: `chat.adapter`, `chat.ui`
-- (is_visible / is_visible_non_curtab / open / hide / winnr), `chat.title`,
-- `chat.bufnr`, `chat.id`, `chat.prompt:add`, `interactions.chat.open`, the
-- `hidden` chat argument and buf_get_chat()'s entries. This module is the one
-- reader: the slot asks it (key, buf, name, win, where, win_here, hide) rather
-- than reading a chat itself. The facade pcall-wraps toggle and add and falls
-- back to the upstream commands with a WARN, and tests/companion_spec.lua pins
-- the behaviour. Text goes to one exact chat through add_text (review
-- feedback, a captured selection), which also reads `chat.current_request`
-- and the private `chat._turn_in_progress` (busy), and refuses rather than
-- raise when they have changed.
--
-- Nothing here requires CodeCompanion at the top level. The first call that
-- needs it does, and lazy's module autoload loads the plugin then -- so the
-- keys can be defined at startup without loading anything.

local config = require("ai.config")

local M = {}

local INFO, ERROR, WARN = vim.log.levels.INFO, vim.log.levels.ERROR, vim.log.levels.WARN

---@alias ai.CompanionKind "acp"|"http"

---Has CodeCompanion loaded? Before it has, no chat can exist, so nothing needs
---to load it to find out.
local function loaded()
  local plugin = require("lazy.core.config").plugins["codecompanion.nvim"]
  return plugin ~= nil and plugin._.loaded ~= nil
end
M.loaded = loaded

local function valid_buf(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

---The CodeCompanion adapter a new chat of `kind` gets in the current state.
---@param kind ai.CompanionKind
---@return string
function M.adapter_name(kind)
  return kind == "acp" and config.codecompanion.acp_adapter or config.codecompanion.http_adapter
end

---The backend (ai.config.backends) a new chat of `kind` comes from now.
---@param kind ai.CompanionKind
---@return ai.Backend
local function spec_of(kind)
  local id = (kind == "acp" and "acp:" or "api:") .. M.adapter_name(kind)
  for _, b in ipairs(config.backends()) do
    if b.id == id then return b end
  end
  error(("no AI backend %s"):format(id))
end

---Refuse before CodeCompanion turns a missing key into a 401, or a missing ACP
---bridge into an asynchronous connection error. Only what starts something is
---checked here: creating a chat (an agent chat spawns its bridge at once, an
---API chat may fetch the model list with the key) and the inline prompt.
---@param what ai.CompanionKind|ai.Backend a kind on its current adapter, or one backend
---@return boolean ok
function M.preflight(what)
  local spec = type(what) == "table" and what or spec_of(what)
  local problem
  if spec.kind == "http" then
    if (vim.env[spec.api_key] or "") == "" then
      problem = ("%s is not set\nnothing sent: export it, or :AI key <profile>"):format(spec.api_key)
    end
  elseif vim.fn.executable(spec.command) ~= 1 then
    problem = ("%s not found — no agent chat\nsee :checkhealth config"):format(spec.command)
  end
  if problem then
    -- Two short lines: the notifier cuts a long one off at its width.
    -- Scheduled: <leader>ae asks from an expr mapping, under textlock, where
    -- opening the notifier's float is not allowed.
    vim.schedule(function() vim.notify(problem, ERROR, { title = "AI" }) end)
  end
  return problem == nil
end

local function nonfloat(win)
  return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == ""
end

---The chat's own window -- `chat.ui.winnr`, while it still shows the chat --
---in whichever tabpage; nil while it is hidden. Read in a pcall and checked,
---so a chat whose ui has changed shape upstream counts as hidden.
---@param chat table a CodeCompanion.Chat
---@return integer|nil
function M.win(chat)
  local ok, win = pcall(function() return chat.ui.winnr end)
  if not (ok and type(win) == "number" and vim.api.nvim_win_is_valid(win)) then return nil end
  if not valid_buf(chat.bufnr) or vim.api.nvim_win_get_buf(win) ~= chat.bufnr then return nil end
  return win
end

---Where the chat's own window is: in this tabpage, in another one, or nowhere,
---as upstream's ui:is_visible() and ui:is_visible_non_curtab() say -- never
---raising.
---@param chat table
---@return "here"|"elsewhere"|"hidden"
function M.where(chat)
  local ok, visible, other = pcall(function() return chat.ui:is_visible(), chat.ui:is_visible_non_curtab() end)
  if not (ok and visible) then return "hidden" end
  return other and "elsewhere" or "here"
end

---A window of this tabpage showing the chat: its own, else another one.
---<C-c> shows its successor in the closed chat's window, which becomes the
---successor's own, and leaves the successor's buffer in the window that
---showed it before -- in another tabpage, a window that is not its own.
---@param chat table
---@return integer|nil
function M.win_here(chat)
  if M.where(chat) == "here" and M.win(chat) then return M.win(chat) end
  if not valid_buf(chat.bufnr) then return nil end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if nonfloat(win) and vim.api.nvim_win_get_buf(win) == chat.bufnr then return win end
  end
end

---Is the chat on screen in this tabpage, in its own window?
local function here(chat)
  return M.where(chat) == "here"
end

---Hide the chat's own window through its ui (ui:hide), never raising.
---@param chat table
---@param opts? { keep_window?: boolean } leave the window for the next chat
---@return boolean ok, any err
function M.hide(chat, opts)
  return pcall(function() chat.ui:hide(opts) end)
end

---The slot's id for a chat: its buffer and its chat id, since a buffer number
---alone can be reused by a later chat.
---@param chat table
---@return string
function M.key(chat)
  return ("cc:%s:%s"):format(tostring(chat.bufnr), tostring(chat.id))
end

---The chat's buffer, while it is still this chat's (see live).
---@param chat table
---@return integer|nil
function M.buf(chat)
  local live = M.live(chat)
  return live and live.bufnr or nil
end

---The chat's adapter as a sentence names it.
---@param chat table
---@return string
function M.name(chat)
  local adapter = type(chat) == "table" and type(chat.adapter) == "table" and chat.adapter or {}
  return adapter.formatted_name or adapter.name or "The chat"
end

---Compare two rank tuples, most significant field first.
local function outranks(a, b)
  if not b then return true end
  for i = 1, #a do
    if a[i] ~= b[i] then return a[i] > b[i] end
  end
  return false
end

---Every live chat, whatever its adapter or however it was opened, oldest
---first, each with what buf_get_chat() knows of it. Empty before CodeCompanion
---has loaded, which is not loaded to answer.
---@return { chat: table, title?: string, description?: string }[]
function M.chats()
  if not loaded() then return {} end
  local ok, list = pcall(function() return require("codecompanion").buf_get_chat() end)
  local out = {}
  for _, entry in ipairs(ok and type(list) == "table" and list or {}) do
    local chat = entry.chat
    if type(chat) == "table" and valid_buf(chat.bufnr) and chat.ui then
      out[#out + 1] = { chat = chat, title = entry.title, description = entry.description }
    end
  end
  table.sort(out, function(a, b) return a.chat.bufnr < b.chat.bufnr end)
  return out
end

---The chat shown in `buf`, if it is one. Loads nothing.
---@param buf integer
---@return table|nil
function M.chat_of(buf)
  if not loaded() or not valid_buf(buf) then return nil end
  local ok, chat = pcall(function() return require("codecompanion").buf_get_chat(buf) end)
  if ok and type(chat) == "table" and chat.bufnr == buf and chat.ui then return chat end
  return nil
end

---What a chat is called in a picker: its backend, its kind and billing, and a
---name -- its title, else what the registry or codecompanion-history calls it,
---else its buffer number.
---@param chat table
---@param entry? { title?: string, description?: string }
---@return string
function M.label(chat, entry)
  local adapter = chat.adapter or {}
  local kind = adapter.type == "acp" and "ACP · subscription" or "API · API credits"
  local name = chat.title or (entry and entry.title)
  if not name and entry and entry.description and entry.description ~= "[No messages]" then name = entry.description end
  if not name and valid_buf(chat.bufnr) then
    local bufname = vim.fs.basename(vim.api.nvim_buf_get_name(chat.bufnr))
    -- Upstream's own "[CodeCompanion] <n>", which codecompanion-history
    -- renames "✨ [CodeCompanion] <id>" until it has a title, names nothing.
    -- History pads it with a non-ASCII space, which %s does not match.
    local bare = bufname:gsub("^✨%s*", "")
    if bufname ~= "" and not bare:match("^%[CodeCompanion%]%D*%d+$") then name = bufname end
  end
  return ("%s · %s · %s"):format(adapter.formatted_name or adapter.name or "?", kind, name or ("#" .. chat.bufnr))
end

---The chat of `kind` on that kind's current adapter, if any: the one on
---screen in this tabpage first, then upstream's last chat, then the most
---recently entered. `lastused` only has a resolution of seconds, so the buffer number
---(newer chats get higher ones) breaks the remaining ties.
---@param kind ai.CompanionKind
---@return CodeCompanion.Chat|nil
function M.find(kind)
  if not loaded() then return nil end
  local want = M.adapter_name(kind)
  local last = require("codecompanion").last_chat()
  local best, best_rank
  for _, entry in ipairs(require("codecompanion").buf_get_chat()) do
    local chat = entry.chat
    local adapter = chat and chat.adapter
    if adapter and adapter.type == kind and adapter.name == want and vim.api.nvim_buf_is_valid(chat.bufnr) then
      local info = vim.fn.getbufinfo(chat.bufnr)[1] or {}
      local rank = { here(chat) and 1 or 0, chat == last and 1 or 0, info.lastused or 0, chat.bufnr }
      if outranks(rank, best_rank) then best, best_rank = chat, rank end
    end
  end
  return best
end

local function focus(chat)
  local win = chat and M.win_here(chat)
  if win then vim.api.nvim_set_current_win(win) end
end

---Put exactly `chat` on screen. Shown in this tabpage already, in any window:
---there. Else shown in another tabpage: go there, nothing moves. Else in this
---tabpage, the slot's way (lua/ai/slot.lua): a chat window here hands itself
---over, or the AI windows here make way for a new one.
---@param chat table a CodeCompanion.Chat
---@param opts? { focus?: boolean, toggled?: boolean } focus defaults to true; toggled keeps the cursor where it was left
---@return boolean shown, "jumped"? how
function M.show(chat, opts)
  opts = opts or {}
  local ui = chat.ui
  if here(chat) or M.win_here(chat) then
    if opts.focus ~= false then focus(chat) end
    return true
  end
  local slot = require("ai.slot")
  local item = slot.chat_item(chat)
  if M.where(chat) == "elsewhere" then
    slot.jump(item, { focus = opts.focus ~= false })
    return true, "jumped"
  end
  local from = vim.api.nvim_get_current_win()
  local donor = slot.chat_window_here(item)
  if donor then
    slot.hide(donor.item, { keep_window = true })
    require("codecompanion.interactions.chat").open({ ui = ui, winnr = donor.win, toggled = opts.toggled })
    slot.cover(item)
  else
    slot.around(item, function() ui:open({ toggled = opts.toggled }) end)
  end
  slot.remember(item)
  if opts.focus ~= false then
    focus(chat)
  elseif vim.api.nvim_win_is_valid(from) then
    -- ui:open splits from the current window and stays in the split.
    vim.api.nvim_set_current_win(from)
  end
  return here(chat)
end

---Start a chat on one backend (an "acp" or "http" entry of
---ai.config.backends()), hidden: show() puts it on screen. Refused before
---anything starts when its key or bridge is missing. The chat is created from
---the editor window, so its context and its review root are the edited file's.
---@param spec ai.Backend
---@param extra table? more CodeCompanion.chat() arguments
---@return table|nil chat
function M.create(spec, extra)
  if not M.preflight(spec) then return nil end
  local win = require("util.window").editor_win()
  if win and win ~= vim.api.nvim_get_current_win() then vim.api.nvim_set_current_win(win) end
  local args = vim.tbl_extend("force", { params = { adapter = spec.adapter, model = spec.model } }, extra or {})
  args.hidden = true
  local chat = require("codecompanion").chat(args)
  if chat then vim.notify("New chat: " .. spec.label, INFO, { title = "AI" }) end
  return chat
end

---Start a chat of `kind` on the current adapter (and the profile's model), and
---show it.
---@param kind ai.CompanionKind
---@return CodeCompanion.Chat|nil
function M.new(kind)
  local chat = M.create(spec_of(kind))
  if chat then M.show(chat) end
  return chat
end

---Show or hide the chat of `kind`, starting one when there is none.
---@param kind ai.CompanionKind
---@return CodeCompanion.Chat|nil
function M.toggle(kind)
  local chat = M.find(kind)
  if not chat then return M.new(kind) end
  if here(chat) then
    M.hide(chat)
    return chat
  end
  M.show(chat, { toggled = true })
  return chat
end

---A captured selection (ai.selection.capture) as chat text: fenced, with its
---source -- what :'<,'>CodeCompanionChat Add writes. Nothing is submitted.
---@param chat table a CodeCompanion.Chat
---@param cap ai.Capture
---@return boolean ok, string? why "disabled", or add_text's reason
function M.add_capture(chat, cap)
  if not require("codecompanion.config").can_send_code() then return false, "disabled" end
  local code = require("codecompanion.utils.markdown").form_codeblock(table.concat(cap.lines, "\n"), { ft = cap.filetype })
  local source = cap.path ~= "" and cap.path or "[No Name]"
  return M.add_text(chat, ("\nHere is some code from %s:\n%s\n"):format(source, code))
end

---Say why add_capture or add_text took nothing.
---@param why string?
function M.refused(why)
  local msg = ({
    disabled = "Sending code to CodeCompanion is disabled",
    busy = "The chat is replying: nothing was added",
    gone = "That chat no longer exists: nothing was added",
  })[why] or ("Could not add to the chat: " .. tostring(why))
  vim.notify(msg, WARN, { title = "AI" })
end

---Add the Visual selection to the chat of `kind` (CodeCompanion.add, aimed at
---one kind instead of `last_chat`), starting one when there is none. Nothing
---is submitted.
---@param kind ai.CompanionKind
---@return CodeCompanion.Chat|nil
function M.add_selection(kind)
  local cap, err = require("ai.selection").capture()
  if not cap then
    vim.notify(err, WARN, { title = "AI" })
    return nil
  end
  local chat = M.find(kind)
  -- A refusal needs nothing loaded; with no chat yet, this one would start it.
  if not chat and not M.preflight(kind) then return nil end
  if not require("codecompanion.config").can_send_code() then return M.refused("disabled") end
  chat = chat or M.create(spec_of(kind), { stop_context_insertion = true })
  if not chat then return nil end
  local ok, why = M.add_capture(chat, cap)
  if not ok then return M.refused(why) end
  M.show(chat)
  return chat
end

---Is `chat` in the middle of a turn, where text added to its prompt would land
---inside the reply? A request in flight, or a tool loop between two of its
---steps: there Chat:done has already cleared `current_request` and the next
---step's ready_for_input made the buffer editable again, and only the private
---`_turn_in_progress` is still set (interactions/chat/init.lua, done and
---ready_for_input). A buffer that is not modifiable is mid-turn too. A chat
---whose buffer is gone is not busy; it is gone.
---@param chat table a CodeCompanion.Chat
---@return boolean
function M.busy(chat)
  if type(chat) ~= "table" then return false end
  if chat.current_request ~= nil then return true end
  -- Private: read defensively, so a rename upstream drops this signal only.
  local ok, in_turn = pcall(function() return chat._turn_in_progress end)
  if ok and in_turn == true then return true end
  return valid_buf(chat.bufnr) and not vim.bo[chat.bufnr].modifiable
end

---The live chat `chat` still is: its buffer valid and, once CodeCompanion has
---loaded, the chat CodeCompanion keeps for that buffer, with the same id. No
---other chat stands in for it -- not find(kind)'s pick, not a newer chat that
---reuses the buffer.
---@param chat table
---@return table|nil
local function exact(chat)
  if type(chat) ~= "table" or chat.id == nil or not valid_buf(chat.bufnr) then return nil end
  if not loaded() then return chat end
  local ok, live = pcall(function() return require("codecompanion").buf_get_chat(chat.bufnr) end)
  if ok and type(live) == "table" and live.id == chat.id and live.bufnr == chat.bufnr then return live end
  return nil
end
M.live = exact

---Append `text` to the prompt of exactly `chat`, without submitting it.
---prompt:add writes at the buffer's last column, so text that is to follow
---what the user already typed should start with "\n" -- without it, a second
---add glued itself to the end of the half-typed line. At the start of a new
---user block the newline is dropped by prompt:add itself.
---
---Refused while the chat is busy (mid-turn, see busy) or gone; nothing has
---changed then.
---@param chat table a CodeCompanion.Chat
---@param text string
---@return boolean ok, "gone"|"busy"|"failed"|nil why, string? err
function M.add_text(chat, text)
  local live = exact(chat)
  if not live then return false, "gone" end
  if M.busy(live) then return false, "busy" end
  local ok, err = pcall(function() live.prompt:add({ content = text }) end)
  if not ok then return false, "failed", tostring(err) end
  return true
end

---Put `chat` on screen (show) and the cursor at the end of its prompt. With
---`insert`, in Insert mode too -- unless the chat is mid-turn, whose buffer is
---locked: the first key typed would be E21, so it says so instead.
---@param chat table a CodeCompanion.Chat
---@param insert boolean?
function M.focus_prompt(chat, insert)
  if not (here(chat) or M.win_here(chat)) then M.show(chat) end
  local win = M.win_here(chat)
  if not win then return end
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(chat.bufnr), 0 })
  if not insert then return end
  if M.busy(chat) then
    vim.notify("The chat is replying: type once it is done", INFO, { title = "AI" })
    return
  end
  vim.cmd("startinsert!")
end

---Put `chat` on screen, the cursor at the end of its prompt, in Insert mode:
---where text add_text appended is to be read and finished.
---@param chat table a CodeCompanion.Chat
function M.show_input(chat)
  return M.focus_prompt(chat, true)
end

---Keys for <leader>ae: the inline prompt's command line, or nothing when the
---key is missing. An expr mapping, so the refusal comes before the command
---line opens rather than after a prompt has been typed.
---@return string
function M.inline_keys()
  return M.preflight("http") and ":CodeCompanion " or "<Ignore>"
end

---Point CodeCompanion's defaults for new chats and requests at the current
---state. A no-op until the plugin has loaded: its `opts` read the same state
---at load time (lua/plugin/lsp/codecompanion.lua). The live config is written
---directly, never `vim.g.codecompanion_adapter`, which v20's cmd.lua resolves
---through `config.adapters[name]` -- nil -- and so falls back to the ACP chat
---adapter.
function M.sync()
  if not loaded() then return end
  local cc = require("codecompanion.config")
  cc.interactions.chat.adapter = config.codecompanion.acp_adapter
  cc.interactions.inline.adapter = config.http_adapter_spec()
  cc.interactions.cmd.adapter = config.http_adapter_spec()
end

return M
