-- One AI chat slot per tabpage (lua/ai/slot.lua, issue #28).
--
-- What is pinned: the right of a tabpage shows at most one AI window --
-- native Claude, native Codex or a CodeCompanion chat -- and showing one hides
-- the others there through their owner's hide, never stopping them and never
-- touching another tabpage; the keys act on the chat on the right, asking when
-- there is none and never delivering to a hidden chat, another tabpage's or
-- the default backend silently; a CodeDiff view hands the keys to the page it
-- came from; a guard holds the rule for upstream's own paths.
--
-- The agents are stand-ins: scripts named after each CLI that run `cat`, ahead
-- of the real ones on PATH. Codex runs through its real backend (unwrapped);
-- Claude through stand-ins of claudecode's modules around a real Snacks
-- terminal, so the plugin, its WebSocket server and lockfile stay out of it.
-- Chats are real API chats on fake NVIM_* keys with CodeCompanion's curl layer
-- stubbed; none is submitted, and no ACP chat is ever created (that spawns the
-- bridge). Questions are answered by a stand-in vim.ui.select. Nothing here
-- depends on which provider is the default: run it under NVIM_AI_PROVIDER=codex
-- too when the slot changes.
local t = dofile("tests/helper.lua")

local api = vim.api
local config = require("ai.config")
local Config = require("lazy.core.config")
local INFO, WARN, ERROR = vim.log.levels.INFO, vim.log.levels.WARN, vim.log.levels.ERROR

local function loaded(name) return Config.plugins[name]._.loaded ~= nil end
local function settle(ms) vim.wait(ms or 80, function() return false end, 10) end

-- `notes` is what a case reads, reset as it likes; `all_notes` keeps every
-- notice of the run, for the check at the end that nothing went wrong.
local notes, all_notes = {}, {}
local real_notify = vim.notify
vim.notify = function(msg, level)
  local note = { msg = tostring(msg), level = level or INFO }
  notes[#notes + 1] = note
  all_notes[#all_notes + 1] = note
end
local function noted(text)
  for _, n in ipairs(notes) do
    if n.msg:find(text, 1, true) then return n end
  end
end

---------------------------------------------------------------------------
-- Before anything opens
---------------------------------------------------------------------------

t.eq(type(package.loaded["ai.slot"]), "table", "the slot is set up at startup")
t.ok(#api.nvim_get_autocmds({ group = "ai_slot", event = "BufWinEnter" }) == 1, "with its BufWinEnter guard")
t.ok(not loaded("claudecode.nvim") and not loaded("codecompanion.nvim"), "and loads neither AI plugin")
t.ok(vim.tbl_contains(Config.plugins["claudecode.nvim"].cmd or {}, "ClaudeCodeOpen"),
  ":ClaudeCodeOpen is a lazy trigger: the slot reveals Claude through it before claudecode has loaded")

-- Stand-in agents, a repository with a space in its path, fake API keys.
local scratch = vim.fn.tempname()
local bin = scratch .. "/bin"
vim.fn.mkdir(bin, "p")
for _, name in ipairs({ "claude", "codex" }) do
  vim.fn.writefile({ "#!/bin/sh", "exec cat" }, bin .. "/" .. name)
  vim.fn.setfperm(bin .. "/" .. name, "rwx------")
end
local saved = {
  path = vim.env.PATH, wrap = vim.env.CODEX_WRAP_TMUX, select = vim.ui.select,
  anthropic = vim.env.NVIM_ANTHROPIC_API_KEY, openai = vim.env.NVIM_OPENAI_API_KEY,
  cc = package.loaded["claudecode"], cc_terminal = package.loaded["claudecode.terminal"],
  chan_send = api.nvim_chan_send,
}
vim.env.PATH = bin .. ":" .. saved.path
vim.env.CODEX_WRAP_TMUX = "0"
vim.env.NVIM_ANTHROPIC_API_KEY = "sk-ant-spec-not-a-key"
vim.env.NVIM_OPENAI_API_KEY = "sk-spec-not-a-key"
local repo = scratch .. "/a repo"
vim.fn.mkdir(repo .. "/.git", "p")
vim.fn.mkdir(repo .. "/src", "p")
local file = repo .. "/src/app.lua"
vim.fn.writefile({ "local a = 1", "local bc = 2", "local d = 3", "return a" }, file)

t.ok(vim.fn.exepath("codex") == bin .. "/codex" and vim.fn.exepath("claude") == bin .. "/claude",
  "both CLIs resolve to the stand-ins")

-- Questions: each answered by the next function queued, which gets the items
-- and how the picker formats them. With nothing queued, a question cancels.
-- Like a real picker, it has left Visual mode by the time the answer comes.
local asked, answers = {}, {}
vim.ui.select = function(items, opts, on_choice)
  local shown = vim.tbl_map(function(item) return opts.format_item and opts.format_item(item) or tostring(item) end, items)
  asked[#asked + 1] = { prompt = opts.prompt, items = items, shown = shown }
  if vim.fn.mode():match("^[vV\22]") then vim.cmd("normal! \27") end
  local answer = table.remove(answers, 1)
  on_choice(answer and answer(items, shown) or nil)
end
---Answer the next question with the entry whose formatted text holds `text`.
local function choose(text)
  answers[#answers + 1] = function(items, shown)
    for i, s in ipairs(shown) do
      if s:find(text, 1, true) then return items[i] end
    end
  end
end
---Answer with exactly `chat`: once several chats share an adapter, its name
---is no longer enough.
local function pick(chat)
  answers[#answers + 1] = function(items)
    for _, item in ipairs(items) do
      if item.chat == chat then return item end
    end
  end
end
local function backend_choice(id)
  answers[#answers + 1] = function(items)
    for _, item in ipairs(items) do
      if item.id == id then return item end
    end
  end
end

-- Codex's channel: what the real backend writes to it.
local typed = {}
api.nvim_chan_send = function(chan, data)
  typed[#typed + 1] = { chan = chan, data = data }
  return saved.chan_send(chan, data)
end
local function writes(buf)
  return vim.tbl_filter(function(entry)
    return buf ~= nil and api.nvim_buf_is_valid(buf) and entry.chan == vim.bo[buf].channel
  end, typed)
end
---Was `text` typed into the agent's box as one paste, and not submitted? The
---payload is exactly ESC[200~ ... ESC[201~, with no Enter after it.
local function typed_into(buf, text)
  for _, entry in ipairs(writes(buf)) do
    if entry.data:find(text, 1, true) then
      return entry.data:sub(1, 6) == "\27[200~" and entry.data:sub(-6) == "\27[201~"
    end
  end
  return false
end
---Was exactly `data` written to the agent's terminal?
local function sent(buf, data)
  for _, entry in ipairs(writes(buf)) do
    if entry.data == data then return true end
  end
  return false
end

-- claudecode, standing in: one Snacks terminal running the stand-in, opened,
-- shown and hidden the way the backend drives claudecode's.
local Snacks = require("snacks")
local claude_term
-- open: the arguments of each call, and the window it was called from.
local cc_calls = { open = {}, open_win = {}, mentions = {}, texts = {}, sends = {} }
package.loaded["claudecode"] = {
  send_at_mention = function(path, s, e)
    cc_calls.mentions[#cc_calls.mentions + 1] = { path, s, e }
    return true
  end,
}
package.loaded["claudecode.terminal"] = {
  get_active_terminal_bufnr = function() return claude_term and claude_term:buf_valid() and claude_term.buf or nil end,
  open = function(_, args)
    cc_calls.open[#cc_calls.open + 1] = args or ""
    cc_calls.open_win[#cc_calls.open_win + 1] = api.nvim_get_current_win()
    if claude_term and claude_term:buf_valid() then
      claude_term:show()
      claude_term:focus()
    else
      claude_term = Snacks.terminal.open({ bin .. "/claude" },
        { win = { position = "right", width = config.panel.width, wo = { winbar = "" }, keys = { term_normal = false } } })
    end
  end,
  ensure_visible = function() end,
  send_to_terminal = function(text, opts)
    cc_calls.texts[#cc_calls.texts + 1] = { text, opts }
    return true
  end,
}
-- A directory listing's selection goes through :ClaudeCodeSend, which reads
-- the live Visual selection. Defining it replaces lazy's stub, which would load
-- the real plugin.
api.nvim_create_user_command("ClaudeCodeSend", function(o)
  cc_calls.sends[#cc_calls.sends + 1] = { buf = api.nvim_get_current_buf(), mode = vim.fn.mode() }
end, { range = true })

local ai, slot, companion = require("ai"), require("ai.slot"), require("ai.companion")
local claude, codex = require("ai.backend.claude"), require("ai.backend.codex")

local function wins()
  return vim.tbl_filter(function(w) return api.nvim_win_get_config(w).relative == "" end, api.nvim_tabpage_list_wins(0))
end
local function shown_ids(tab)
  return vim.tbl_map(function(item) return item.id end, slot.shown(tab))
end
local function alive(buf)
  return buf ~= nil and api.nvim_buf_is_valid(buf) and vim.fn.jobwait({ vim.bo[buf].channel }, 0)[1] == -1
end
local function editor()
  for _, w in ipairs(wins()) do
    if api.nvim_buf_get_name(api.nvim_win_get_buf(w)) == file then
      api.nvim_set_current_win(w)
      return w
    end
  end
end

vim.cmd.edit(vim.fn.fnameescape(file))
-- As Nvim names it: the temp directory can sit behind a symlink (/var on macOS).
file = api.nvim_buf_get_name(0)
local editor_win = api.nvim_get_current_win()
local root = vim.fs.dirname(vim.fs.dirname(file))

---------------------------------------------------------------------------
-- The backends the new-chat picker offers
---------------------------------------------------------------------------

local ids = function(list) return vim.tbl_map(function(b) return b.id end, list) end
t.eq(ids(config.backends("claude")), { "claude", "codex", "acp:claude_code", "acp:codex", "api:anthropic", "api:openai" },
  "terminals, ACP chats, API chats: Claude's first in each when it is the default")
t.eq(ids(config.backends("codex")), { "codex", "claude", "acp:codex", "acp:claude_code", "api:openai", "api:anthropic" },
  "and Codex's first when it is")
local by_id = {}
for _, b in ipairs(config.backends()) do by_id[b.id] = b end
t.eq(by_id.claude.label, "Claude Code · terminal · subscription", "a terminal says what it is and who bills it")
t.eq(by_id["acp:codex"].label, "Codex · CodeCompanion ACP · subscription", "an agent chat too")
t.eq(by_id["api:openai"].label, "OpenAI · CodeCompanion API · API credits", "and an API chat")
vim.env.NVIM_OPENAI_API_KEY = nil
local openai_off = vim.tbl_filter(function(b) return b.id == "api:openai" end, config.backends())[1]
t.eq({ openai_off.available, openai_off.why }, { false, "NVIM_OPENAI_API_KEY is not set" },
  "an API profile without its key is unavailable, saying why")
vim.env.NVIM_OPENAI_API_KEY = "sk-spec-not-a-key"

-- Only available backends are offered: with a PATH that holds the Claude
-- stand-in alone -- not prepended to the real one, where the CLIs may be --
-- neither Codex entry is, nor an ACP chat whose bridge is missing.
local only_claude = scratch .. "/only-claude"
vim.fn.mkdir(only_claude, "p")
vim.fn.writefile({ "#!/bin/sh", "exec cat" }, only_claude .. "/claude")
vim.fn.setfperm(only_claude .. "/claude", "rwx------")
vim.env.PATH = only_claude
asked = {}
ai.new_chat()
vim.env.PATH = bin .. ":" .. saved.path
local offered = asked[1] and asked[1].shown or {}
t.ok(#vim.tbl_filter(function(s) return s:find("^Claude Code · terminal") ~= nil end, offered) == 1
  and #vim.tbl_filter(function(s) return s:find("Codex", 1, true) or s:find("ACP", 1, true) end, offered) == 0,
  "the new-chat picker lists only the backends that can start (" .. table.concat(offered, " | ") .. ")")
t.ok(not loaded("claudecode.nvim") and not loaded("codecompanion.nvim"), "asking loads nothing")

---------------------------------------------------------------------------
-- Nothing open: the keys ask with the new-chat picker
---------------------------------------------------------------------------

asked, notes = {}, {}
ai.toggle()
t.eq(#asked, 1, "<leader>ac with nothing open asks")
t.eq(asked[1] and asked[1].prompt, "New AI chat", "with the new-chat picker")
t.ok(asked[1] and asked[1].shown[1]:find(config.label .. " · terminal", 1, true) == 1,
  "the default backend's terminal first, so <CR> starts it")
t.eq(#wins(), 1, "cancelled, nothing opens")

-- CodeCompanion, with nothing sent anywhere.
require("lazy").load({ plugins = { "codecompanion.nvim" } })
local Curl = require("codecompanion.utils.curl")
local requests = {}
Curl.request = function(opts)
  requests[#requests + 1] = { method = (opts.method or "GET"):upper(), url = opts.url }
  return {}
end
Curl.request_sync = function(opts)
  requests[#requests + 1] = { method = (opts.method or "GET"):upper(), url = opts.url }
  return nil, { message = "stubbed by ai_slot_spec" }
end
local Chats = require("codecompanion.interactions.chat")
-- Every chat created, with the window it was created from.
local created = {}
local real_chat = require("codecompanion").chat
require("codecompanion").chat = function(args)
  created[#created + 1] = vim.deepcopy(args)
  created[#created].win = api.nvim_get_current_win()
  return real_chat(args)
end
-- The first chat on `adapter`, whatever the default provider makes of a kind.
local function chat_on(adapter)
  for _, entry in ipairs(companion.chats()) do
    if entry.chat.adapter.name == adapter then return entry.chat end
  end
end

-- A selection, with nothing on the right: captured first, then the question.
editor()
api.nvim_win_set_cursor(0, { 2, 0 })
asked, notes = {}, {}
backend_choice("api:anthropic")
api.nvim_feedkeys("Vj", "x", false)
ai.send_selection()
t.eq(vim.fn.mode(), "n", "<leader>as leaves Visual before it asks")
t.eq(asked[1] and asked[1].prompt, "Add selection to", "with no chat open it asks for a new one")
local anthropic = chat_on("anthropic")
t.ok(anthropic ~= nil and #companion.chats() == 1, "the chat is created on the backend picked")
t.eq(created[1] and created[1].hidden, true, "hidden at first: it is put on screen as exactly this chat")
t.ok(noted("New chat: Anthropic · CodeCompanion API · API credits") ~= nil, "a new chat says what it is and who bills it")
local function text(chat) return table.concat(api.nvim_buf_get_lines(chat.bufnr, 0, -1, false), "\n") end
t.ok(anthropic and text(anthropic):find("```lua\nlocal bc = 2\nlocal d = 3\n```", 1, true) ~= nil,
  "the selection captured before the question lands in it, fenced")
t.ok(anthropic and text(anthropic):find("Here is some code from " .. file, 1, true) ~= nil, "with its source")
t.ok(anthropic and companion.show and anthropic.ui:is_visible() and not anthropic.ui:is_visible_non_curtab(),
  "and it is shown here")
t.eq(#wins(), 2, "in one window beside the file")

-- Nothing on the right and no last chat: <leader>ac brings the only open chat
-- back, without asking.
editor()
ai.toggle()
vim.t.ai_slot_last = nil
asked = {}
ai.toggle()
t.ok(anthropic.ui:is_visible() and #asked == 0, "with no last chat, <leader>ac brings back the only open chat unasked")
local slot_win = anthropic and anthropic.ui.winnr
t.eq(vim.t.ai_slot_last, anthropic and slot.chat_item(anthropic).id, "remembered as this tabpage's last chat")

---------------------------------------------------------------------------
-- Chat to chat: one window, handed over
---------------------------------------------------------------------------

editor()
backend_choice("api:openai")
ai.new_chat()
local openai = chat_on("openai")
t.ok(openai ~= nil, "<leader>an makes a second chat")
t.eq(openai and openai.ui.winnr, slot_win, "in the window the first one had")
t.ok(not anthropic.ui:is_visible() and api.nvim_buf_is_valid(anthropic.bufnr), "which is hidden, not closed")
t.eq(#wins(), 2, "still one AI window")
t.eq(api.nvim_get_current_win(), slot_win, "the new chat is focused")
settle()
t.eq(shown_ids(), { openai and slot.chat_item(openai).id }, "the slot shows the new chat only")

-- Two open, neither on the right, no last chat: <leader>ac asks which, the one
-- used last first. getbufinfo()'s lastused counts seconds, so the older chat
-- is looked at -- in a float, which the slot ignores -- a second later.
editor()
ai.toggle()
vim.t.ai_slot_last = nil
settle(1100)
local peek = api.nvim_open_win(anthropic.bufnr, true, { relative = "editor", row = 1, col = 1, width = 20, height = 3 })
vim.cmd("wincmd p")
api.nvim_win_close(peek, true)
editor()
asked = {}
choose("New chat…")
ai.toggle()
local order = asked[1] and asked[1].shown or {}
t.eq(asked[1] and asked[1].prompt, "Switch AI chat", "with no last chat and two open, <leader>ac asks which")
t.ok((order[1] or ""):find("^Anthropic") and (order[2] or ""):find("^OpenAI"),
  "the one used last first, not the newest (" .. table.concat(order, " | ") .. ")")
t.eq(asked[2] and asked[2].prompt, "New AI chat", "its last entry, New chat…, asks for a backend")
t.eq(#wins(), 1, "cancelled there, nothing opens")
choose("OpenAI")
ai.toggle()
t.ok(openai.ui:is_visible(), "the one picked comes back")
slot_win = openai.ui.winnr
settle()

-- The switcher: what is here first, the rest by use, then "New chat…". A chat
-- with no title is named by its buffer: upstream's "[CodeCompanion] <n>",
-- which codecompanion-history decorates, names nothing.
asked = {}
choose("Anthropic")
ai.switch_chat()
local list = asked[1] and asked[1].shown or {}
t.eq(asked[1] and asked[1].prompt, "Switch AI chat", "<leader>al asks which open chat")
t.ok(list[1] and list[1]:find(("^OpenAI · API · API credits · #%d · ● here$"):format(openai.bufnr)) ~= nil,
  "the one here first, marked ● (" .. tostring(list[1]) .. ")")
t.ok(list[2] and list[2]:find(("^Anthropic · API · API credits · #%d · hidden$"):format(anthropic.bufnr)) ~= nil,
  "a hidden one says so (" .. tostring(list[2]) .. ")")
t.eq(list[#list], "New chat…", "and a new chat is the last entry")
t.eq(anthropic.ui.winnr, slot_win, "the chat picked takes the same window back")
t.ok(not openai.ui:is_visible() and api.nvim_buf_is_valid(openai.bufnr), "the other is hidden, not closed")

-- <leader>ac hides it and brings back the same one.
editor()
ai.toggle()
t.ok(not anthropic.ui:is_visible() and #wins() == 1, "<leader>ac hides the chat on the right")
asked = {}
ai.toggle()
t.ok(anthropic.ui:is_visible() and #asked == 0, "and brings the last one back without asking")

---------------------------------------------------------------------------
-- A native agent: started from the editor window, the chat hidden for it
---------------------------------------------------------------------------

-- From inside the chat: the cold start still belongs to the edited file.
api.nvim_set_current_win(anthropic.ui.winnr)
notes = {}
backend_choice("codex")
ai.new_chat()
vim.cmd("stopinsert")
local codex_buf = codex.buf()
t.ok(codex_buf ~= nil and alive(codex_buf), "<leader>an starts Codex")
t.eq(codex_buf and vim.b[codex_buf].snacks_terminal.cwd, root, "from the editor window: its root is the edited file's")
t.ok(codex.visible() and not anthropic.ui:is_visible(), "the chat makes way for it")
t.ok(api.nvim_buf_is_valid(anthropic.bufnr), "hidden, not closed")
t.eq(#wins(), 2, "one AI window")
t.ok(noted("New chat: Codex · terminal · subscription") ~= nil, "a native session it starts is announced, billing too")

-- The new-chat picker offers a running session as it is, saying where.
local function offered_as(prefix)
  for _, line in ipairs(asked[#asked] and asked[#asked].shown or {}) do
    if line:find(prefix, 1, true) == 1 then return line end
  end
  return ""
end
editor()
ai.new_chat()
t.ok(offered_as("Codex · terminal"):find("Codex · terminal · subscription · ● here", 1, true) == 1,
  "a running agent shown here is marked so (" .. offered_as("Codex · terminal") .. ")")
t.ok(not offered_as("Claude Code · terminal"):find("●", 1, true) and not offered_as("Claude Code · terminal"):find("running", 1, true),
  "one not running is not")

-- And back: Codex hidden, its job running.
choose("Anthropic")
ai.switch_chat()
settle()
t.ok(anthropic.ui:is_visible() and not codex.visible(), "a chat picked hides Codex here")
t.ok(alive(codex_buf), "which keeps running")
t.eq(#wins(), 2, "still one AI window")
editor()
ai.new_chat()
t.ok(offered_as("Codex · terminal"):find("Codex · terminal · subscription · running", 1, true) == 1,
  "a hidden one is marked running (" .. offered_as("Codex · terminal") .. ")")

-- Claude, the other native agent, through claudecode's open.
editor()
backend_choice("claude")
ai.new_chat()
vim.cmd("stopinsert")
settle()
t.ok(claude.visible() and not anthropic.ui:is_visible() and not codex.visible(), "<leader>an shows Claude Code, alone")
t.eq(cc_calls.open, { "" }, "through claudecode's open, which never hides it")
t.ok(noted("New chat: Claude Code · terminal · subscription") ~= nil, "announced like Codex")

-- Native to native.
choose("Codex")
ai.switch_chat()
vim.cmd("stopinsert")
settle()
t.ok(codex.visible() and not claude.visible() and alive(claude.buf()), "Codex replaces Claude, which keeps running")
choose("Claude Code")
ai.switch_chat()
vim.cmd("stopinsert")
settle()
t.ok(claude.visible() and not codex.visible() and alive(codex_buf), "and the other way round")

-- <leader>af goes in and never hides; <leader>ac hides and brings back.
editor()
ai.focus()
vim.cmd("stopinsert")
t.eq(api.nvim_get_current_buf(), claude.buf(), "<leader>af goes into the chat on the right")
ai.focus()
vim.cmd("stopinsert")
t.ok(claude.visible(), "and pressed in it, leaves it shown")
editor()
ai.toggle()
t.ok(not claude.visible() and alive(claude.buf()), "<leader>ac hides Claude, which keeps running")
ai.toggle()
vim.cmd("stopinsert")
t.ok(claude.visible(), "and brings it back")

---------------------------------------------------------------------------
-- The guard: upstream's own paths
---------------------------------------------------------------------------

-- A chat opened the way a typed :CodeCompanionChat opens one.
editor()
local upstream = real_chat({ params = { adapter = "anthropic" } })
settle()
t.ok(upstream and upstream.ui:is_visible(), "a chat opened by upstream is shown")
t.ok(not claude.visible() and alive(claude.buf()), "and the guard hides Claude for it, without stopping it")
t.eq(#wins(), 2, "one AI window")
t.eq(vim.t.ai_slot_last, upstream and slot.chat_item(upstream).id, "the guard remembers it as the last chat")
if upstream then upstream:close() end
settle()

-- A float on an agent's buffer -- a picker's preview -- is no slot window.
editor()
choose("Codex")
ai.switch_chat()
vim.cmd("stopinsert")
settle()
editor()
local float = api.nvim_open_win(anthropic.bufnr, false, { relative = "editor", row = 1, col = 1, width = 20, height = 3 })
settle()
t.ok(codex.visible(), "a float showing a chat hides nothing")
api.nvim_win_close(float, true)

---------------------------------------------------------------------------
-- Delivery goes to the chat on the right
---------------------------------------------------------------------------

-- Codex on the right: a selection is typed into its box, not submitted.
editor()
api.nvim_win_set_cursor(0, { 2, 0 })
asked, typed = {}, {}
api.nvim_feedkeys("Vj", "x", false)
ai.send_selection()
t.ok(vim.wait(2000, function() return typed_into(codex_buf, "@src/app.lua lines 2-3 ") end, 20),
  "<leader>as types the selection into Codex on the right")
t.eq(#asked, 0, "without asking")
vim.cmd("stopinsert")
editor()
typed = {}
ai.add_buffer()
t.ok(vim.wait(2000, function() return typed_into(codex_buf, "@src/app.lua ") end, 20), "<leader>ab mentions the file to Codex")
vim.cmd("stopinsert")
-- An unsaved change cannot be mentioned: the text itself goes, saying so.
editor()
api.nvim_buf_set_lines(0, 3, 4, false, { "return a -- edited" })
api.nvim_win_set_cursor(0, { 4, 0 })
typed, notes = {}, {}
api.nvim_feedkeys("V", "x", false)
ai.send_selection()
t.ok(vim.wait(2000, function() return typed_into(codex_buf, "return a -- edited") end, 20),
  "a selection with unsaved changes is typed into Codex as text")
t.ok(noted("Buffer has unsaved changes") ~= nil, "saying why it is no mention")
vim.cmd("stopinsert")
editor()
vim.cmd("silent edit!")

-- Two chats, one on the right and the other upstream's last chat: the
-- selection goes to the one on the right.
editor()
companion.show(anthropic, { focus = false })
t.eq(api.nvim_get_current_buf(), api.nvim_win_get_buf(editor_win), "shown without focus, the cursor stays in the file")
-- Upstream's last chat is the chat buffer entered last.
api.nvim_exec_autocmds("BufEnter", { buffer = openai.bufnr, modeline = false })
t.ok(anthropic.ui:is_visible() and Chats.last_chat() == openai, "the Anthropic chat is on the right, the other is last_chat")
local before = text(openai)
api.nvim_win_set_cursor(0, { 4, 0 })
api.nvim_feedkeys("V", "x", false)
ai.send_selection()
t.ok(text(anthropic):find("```lua\nreturn a\n```", 1, true) ~= nil, "<leader>as adds to the chat on the right")
t.eq(text(openai), before, "and nothing to upstream's last chat")
-- Sending code to CodeCompanion turned off: refused, nothing added.
local cc_config = require("codecompanion.config")
local real_can_send = cc_config.can_send_code
cc_config.can_send_code = function() return false end
before, notes = text(anthropic), {}
editor()
api.nvim_feedkeys("V", "x", false)
ai.send_selection()
cc_config.can_send_code = real_can_send
t.ok(noted("Sending code to CodeCompanion is disabled") ~= nil and text(anthropic) == before,
  "with sending code turned off, <leader>as refuses and adds nothing")

-- <leader>ab has nothing for a chat but a pointer.
editor()
notes = {}
ai.add_buffer()
t.ok(noted("A chat takes a selection") ~= nil, "<leader>ab on a chat says what to use instead")

-- <leader>ai on a chat: its own prompt; from Visual, the selection first.
editor()
ai.compose()
t.eq({ api.nvim_get_current_buf(), api.nvim_win_get_cursor(0)[1] }, { anthropic.bufnr, api.nvim_buf_line_count(anthropic.bufnr) },
  "<leader>ai goes to the end of the chat's prompt")
vim.cmd("stopinsert")
editor()
api.nvim_win_set_cursor(0, { 1, 0 })
api.nvim_feedkeys("V", "x", false)
ai.compose()
vim.cmd("stopinsert")
t.ok(text(anthropic):find("```lua\nlocal a = 1\n```", 1, true) ~= nil, "from Visual, the selection goes in first")
-- Mid-turn the buffer is locked: the cursor goes there, Insert mode does not.
editor()
anthropic._turn_in_progress = true
notes = {}
ai.compose()
t.ok(noted("The chat is replying") ~= nil and vim.fn.mode() == "n", "a chat that is replying gets the cursor, not Insert mode")
anthropic._turn_in_progress = nil

-- A native agent on the right gets <leader>ai, whichever is the default.
local other = config.provider == "claude" and "codex" or "claude"
editor()
choose(config.providers[other].label .. " · terminal")
ai.switch_chat()
vim.cmd("stopinsert")
settle()
local prompts = { claude = {}, codex = {} }
local real_edit = { claude = claude.edit_prompt, codex = codex.edit_prompt }
claude.edit_prompt = function(o) table.insert(prompts.claude, o) end
codex.edit_prompt = function(o) table.insert(prompts.codex, o) end
editor()
api.nvim_win_set_cursor(0, { 1, 0 })
api.nvim_feedkeys("V", "x", false)
ai.compose()
claude.edit_prompt, codex.edit_prompt = real_edit.claude, real_edit.codex
t.eq({ #prompts[other], #prompts[config.provider] }, { 1, 0 },
  "<leader>ai opens the prompt of the agent on the right (" .. other .. "), not the default's")
t.eq(prompts[other][1] and prompts[other][1].seed, "@src/app.lua lines 1-1 ", "seeded with the selection")

-- Claude running but hidden, picked for <leader>ai: shown here through
-- claudecode's open, then asked for its prompt editor.
editor()
ai.toggle()
cc_calls.open = {}
choose("Claude Code")
ai.compose()
vim.cmd("stopinsert")
settle()
t.ok(#cc_calls.open == 1 and claude.visible(), "<leader>ai shows a hidden Claude here before asking for its prompt")
require("ai.editor").stage_seed(nil, { provider = "claude" })

---------------------------------------------------------------------------
-- Claude on the right: a mention of the captured lines; its own session keys
---------------------------------------------------------------------------

editor()
choose("Claude Code")
ai.switch_chat()
vim.cmd("stopinsert")
settle()
editor()
api.nvim_win_set_cursor(0, { 2, 0 })
cc_calls.mentions = {}
api.nvim_feedkeys("Vj", "x", false)
ai.send_selection()
t.eq(cc_calls.mentions, { { file, 1, 2 } }, "<leader>as mentions the captured lines to Claude Code (0-based, as claudecode takes them)")
t.eq(api.nvim_get_current_win(), editor_win, "and the cursor stays in the file")

-- <leader>ab: the file, through claudecode's API -- :ClaudeCodeAdd would split
-- "a repo/src/app.lua" at its space.
editor()
cc_calls.mentions = {}
ai.add_buffer()
t.eq(cc_calls.mentions, { { file } }, "<leader>ab mentions the file to Claude Code, its path whole")

-- A buffer with no file has nothing to mention.
editor()
vim.cmd("enew")
local no_file = api.nvim_get_current_buf()
api.nvim_buf_set_lines(no_file, 0, -1, false, { "scratch" })
cc_calls.mentions, notes = {}, {}
api.nvim_feedkeys("V", "x", false)
ai.send_selection()
t.ok(noted("This buffer has no file") ~= nil and #cc_calls.mentions == 0,
  "a selection in a buffer with no file is refused for Claude Code, saying why")
api.nvim_win_set_buf(0, vim.fn.bufnr(file))
api.nvim_buf_delete(no_file, { force = true })

-- Claude hidden and picked in the question: shown first, then mentioned.
editor()
ai.toggle()
t.ok(not claude.visible() and alive(claude.buf()), "Claude hidden")
cc_calls.open, cc_calls.mentions = {}, {}
choose("Claude Code")
api.nvim_win_set_cursor(0, { 2, 0 })
api.nvim_feedkeys("Vj", "x", false)
ai.send_selection()
vim.cmd("stopinsert")
t.ok(#cc_calls.open == 1 and claude.visible(), "<leader>as shows a hidden Claude picked in the question")
t.eq(cc_calls.mentions, { { file, 1, 2 } }, "then mentions the lines")

-- A running session is shown and left as it is: no toggle, no arguments.
editor()
cc_calls.open, notes = {}, {}
ai.resume()
vim.cmd("stopinsert")
t.ok(claude.visible(), "<leader>ar on a running Claude leaves it shown")
t.ok(noted("Claude Code is already running: use /resume in it") ~= nil, "and says how to resume from it")
t.eq(cc_calls.open, {}, "into its window: no toggle, no --resume")
editor()
notes = {}
ai.continue()
vim.cmd("stopinsert")
t.ok(claude.visible() and noted("Claude Code is already running") ~= nil, "<leader>aR too")
editor()
cc_calls.texts, notes = {}, {}
ai.select_model()
vim.cmd("stopinsert")
t.ok(claude.visible() and noted("Claude Code is already running: use /model in it") ~= nil,
  "<leader>am on a running Claude shows it and says how")
t.eq(cc_calls.texts, {}, "typing nothing: its box may hold a draft, which an Enter would submit")

-- Codex the same way.
editor()
choose("Codex")
ai.switch_chat()
vim.cmd("stopinsert")
settle()
editor()
notes = {}
ai.continue()
vim.cmd("stopinsert")
t.ok(codex.visible() and noted("Codex is already running: this is its session") ~= nil,
  "<leader>aR on a running Codex shows it and says so")
editor()
typed, notes = {}, {}
ai.select_model()
vim.cmd("stopinsert")
settle(400)
t.ok(codex.visible() and noted("Codex is already running: use /model in it") ~= nil,
  "<leader>am on a running Codex shows it and says how")
t.eq(#writes(codex_buf), 0, "typing nothing into its box")

-- No native agent on the right: the native keys ask which, the default first.
editor()
choose("Anthropic")
ai.switch_chat()
settle()
editor()
asked = {}
ai.resume()
t.eq(asked[1] and asked[1].prompt, "Which native agent?", "with a chat on the right, <leader>ar asks which agent")
t.eq(asked[1] and asked[1].shown[1], config.label, "the default first")
t.ok(anthropic.ui:is_visible(), "cancelled, the chat stays")
-- With one agent installed there is nothing to ask.
vim.env.PATH = only_claude
asked = {}
ai.resume()
vim.env.PATH = bin .. ":" .. saved.path
vim.cmd("stopinsert")
t.eq(#asked, 0, "with one native agent installed, <leader>ar asks nothing")
t.ok(claude.visible() and not anthropic.ui:is_visible(), "and shows that one, the chat hidden for it")
editor()
choose("Anthropic")
ai.switch_chat()
settle()

---------------------------------------------------------------------------
-- Covering a chat that is busy, and one asking for an approval unseen
---------------------------------------------------------------------------

anthropic._turn_in_progress = true
asked, notes = {}, {}
choose("Codex")
ai.switch_chat()
vim.cmd("stopinsert")
settle()
t.eq(#vim.tbl_filter(function(line) return line:find("^Anthropic .* · ● here · replying$") ~= nil end,
  asked[1] and asked[1].shown or {}), 1, "the switcher marks a chat that is replying")
t.ok(noted("is still working (replying or waiting for an approval) — hidden") ~= nil,
  "hiding a chat mid-turn says so")
anthropic._turn_in_progress = nil
notes = {}
api.nvim_exec_autocmds("User", { pattern = "CodeCompanionToolApprovalRequested", data = { bufnr = anthropic.bufnr } })
t.ok(noted("is waiting for a tool approval — <leader>al shows it") ~= nil, "an approval asked by a hidden chat is announced")
choose("Anthropic")
ai.switch_chat()
settle()
notes = {}
api.nvim_exec_autocmds("User", { pattern = "CodeCompanionToolApprovalRequested", data = { bufnr = anthropic.bufnr } })
t.eq(notes, {}, "one on screen needs no notice")

---------------------------------------------------------------------------
-- Tabpages: another one's chat is gone to, never moved or hidden
---------------------------------------------------------------------------

local first_tab = api.nvim_get_current_tabpage()
local function layout(tab)
  return vim.tbl_map(function(w) return { w, api.nvim_win_get_buf(w) } end, api.nvim_tabpage_list_wins(tab))
end
vim.cmd("tabnew")
local second_tab = api.nvim_get_current_tabpage()
local first_layout = layout(first_tab)
notes = {}
pick(anthropic)
ai.switch_chat()
t.eq(api.nvim_get_current_tabpage(), first_tab, "a chat shown in another tabpage is gone to")
t.eq(layout(first_tab), first_layout, "and nothing there moved")
t.ok(noted("is shown in tab 1: went there") ~= nil, "saying so")

-- From the second tabpage, another chat shown there leaves the first one's alone
-- -- upstream's window-less open would have hidden it there.
api.nvim_set_current_tabpage(second_tab)
choose("OpenAI")
ai.switch_chat()
t.ok(openai.ui:is_visible() and api.nvim_win_get_tabpage(openai.ui.winnr) == second_tab, "a hidden chat is shown here")
t.eq(layout(first_tab), first_layout, "the first tabpage keeps its chat")

-- A native agent shown in another tabpage is gone to as well, picked in a
-- native key's question or in the switcher; nothing here makes way for it.
-- Its own show focuses its window anyway, so the notice is what tells.
api.nvim_set_current_tabpage(first_tab)
editor()
choose("Codex")
ai.switch_chat()
vim.cmd("stopinsert")
settle()
t.ok(codex.visible(), "Codex shown in the first tabpage")
local codex_layout = layout(first_tab)
for _, key in ipairs({ { "<leader>ar", ai.resume }, { "<leader>al", ai.switch_chat } }) do
  api.nvim_set_current_tabpage(second_tab)
  notes = {}
  choose("Codex")
  key[2]()
  vim.cmd("stopinsert")
  settle()
  t.eq(api.nvim_get_current_tabpage(), first_tab, key[1] .. " from the second tabpage goes to Codex in the first")
  t.ok(noted("Codex is shown in tab 1: went there") ~= nil, key[1] .. " says so")
  t.eq(layout(first_tab), codex_layout, key[1] .. ": nothing there moved")
  t.eq(api.nvim_win_get_tabpage(openai.ui.winnr), second_tab, key[1] .. ": the second tabpage keeps its chat")
end
editor()
pick(anthropic)
ai.switch_chat()
settle()
first_layout = layout(first_tab)

-- Nothing on the right of a new tabpage: <leader>ac leaves its last chat
-- where another tabpage shows it, and asks; <leader>af brings back a last
-- chat that is hidden.
api.nvim_set_current_tabpage(second_tab)
vim.cmd("tabnew")
local spare_tab = api.nvim_get_current_tabpage()
vim.t.ai_slot_last = slot.chat_item(anthropic).id
asked = {}
ai.toggle()
t.eq({ api.nvim_get_current_tabpage(), asked[1] and asked[1].prompt }, { spare_tab, "Switch AI chat" },
  "<leader>ac does not go to a last chat shown in another tabpage: it asks")
vim.t.ai_slot_last = "native:codex"
ai.focus()
vim.cmd("stopinsert")
t.ok(codex.visible() and api.nvim_get_current_tabpage() == spare_tab, "<leader>af with nothing on the right brings the last chat here")
vim.cmd("tabclose")
api.nvim_set_current_tabpage(second_tab)

-- Nothing shown here and a delivery: it asks; cancelled, nothing is sent.
vim.cmd("tabnew")
local third_tab = api.nvim_get_current_tabpage()
vim.cmd.edit(vim.fn.fnameescape(file))
local before_a, before_o = text(anthropic), text(openai)
asked, typed = {}, {}
api.nvim_feedkeys("V", "x", false)
ai.send_selection()
t.eq(asked[1] and asked[1].prompt, "Add selection to", "with nothing on the right, <leader>as asks")
t.eq({ text(anthropic), text(openai), #typed }, { before_a, before_o, 0 }, "cancelled, nothing is delivered anywhere")
local function listed(pattern)
  return #vim.tbl_filter(function(line) return line:find(pattern) ~= nil end, asked[1] and asked[1].shown or {}) == 1
end
t.ok(listed("^Anthropic · API · API credits · .* · tab 1$") and listed("^OpenAI · API · API credits · .* · tab 2$"),
  "the chats shown in other tabpages say which")

-- Picked, a chat shown in another tabpage is gone to, and gets it.
local function count(haystack, needle) return select(2, haystack:gsub(vim.pesc(needle), "")) end
local d_lines = count(text(anthropic), "local d = 3")
asked, notes = {}, {}
pick(anthropic)
api.nvim_win_set_cursor(0, { 3, 0 })
api.nvim_feedkeys("V", "x", false)
ai.send_selection()
t.eq(api.nvim_get_current_tabpage(), first_tab, "<leader>as to a chat shown in another tabpage goes there")
t.eq(count(text(anthropic), "local d = 3"), d_lines + 1, "and adds the selection to it")
t.eq(layout(first_tab), first_layout, "nothing there moved")
t.ok(noted("is shown in tab 1: went there") ~= nil and noted("Sent to Anthropic (tab 1)") ~= nil, "saying where it went")
api.nvim_set_current_tabpage(third_tab)

-- <leader>ab asks among the native agents alone: a chat picked or made there
-- would only refuse it.
local chats_before = #companion.chats()
asked = {}
choose("New chat…")
ai.add_buffer()
local function terminals_only(question)
  local lines = vim.tbl_filter(function(line) return line ~= "New chat…" end, question and question.shown or {})
  return #lines > 0 and #vim.tbl_filter(function(line) return not line:find(" · terminal · ", 1, true) end, lines) == 0
end
t.eq(asked[1] and asked[1].prompt, "Add buffer to", "<leader>ab with nothing on the right asks")
t.ok(terminals_only(asked[1]), "among the native agents only (" .. table.concat(asked[1] and asked[1].shown or {}, " | ") .. ")")
t.ok(terminals_only(asked[2]), "and its New chat… offers the terminals only")
t.eq(#companion.chats(), chats_before, "no chat is created for it")

-- A tabpage of nothing but an AI window: the new one is shown first, then the
-- old one hidden (E444 otherwise).
choose("Codex")
ai.switch_chat()
vim.cmd("stopinsert")
vim.cmd("only")
t.eq(#wins(), 1, "a tabpage with only the Codex panel")
notes = {}
ai.toggle()
t.ok(codex.visible() and #wins() == 1, "<leader>ac leaves a tabpage's only window shown")
t.ok(noted("Codex is this tabpage's only window") ~= nil, "saying why")
notes = {}
backend_choice("api:anthropic")
ai.new_chat()
settle()
local third_chat
for _, entry in ipairs(companion.chats()) do
  if entry.chat.ui:is_visible() and api.nvim_win_get_tabpage(entry.chat.ui.winnr) == third_tab then third_chat = entry.chat end
end
t.ok(third_chat ~= nil and not codex.visible() and alive(codex_buf), "the chat is shown and Codex hidden, still running")
t.eq(#wins(), 1, "the chat is the tabpage's one window")
t.eq(vim.tbl_filter(function(n) return n.msg:find("E444", 1, true) end, notes), {}, "without E444")
notes = {}
ai.toggle()
t.ok(api.nvim_tabpage_is_valid(third_tab) and third_chat.ui:is_visible() and #wins() == 1,
  "nor a chat that is the only window: CodeCompanion's hide would close the tabpage")
t.ok(noted("is this tabpage's only window") ~= nil and #vim.tbl_filter(function(n) return n.msg:find("E444", 1, true) end, notes) == 0,
  "saying why, without E444")

---------------------------------------------------------------------------
-- From a CodeDiff view: the keys work in the page the view came from
---------------------------------------------------------------------------

-- Two views opened in a row after the first tabpage, which shows a chat.
api.nvim_set_current_tabpage(first_tab)
vim.cmd("tabnew")
local view_a = api.nvim_get_current_tabpage()
vim.t.blocks_global_prefixes = true
vim.cmd("tabnew")
local view_b = api.nvim_get_current_tabpage()
vim.t.blocks_global_prefixes = true
local util_window = require("util.window")
t.eq({ util_window.origin_tab(view_b), util_window.origin_tab(view_a), util_window.origin_tab(first_tab) },
  { first_tab, first_tab, nil }, "a view's origin is the first page before it that is no view")
vim.cmd.edit(vim.fn.fnameescape(file))
local view_layout = layout(view_b)
before_a = text(anthropic)
notes = {}
api.nvim_win_set_cursor(0, { 3, 0 })
api.nvim_feedkeys("V", "x", false)
ai.send_selection()
t.eq(api.nvim_get_current_tabpage(), first_tab, "<leader>as from the second view goes to the page both came from")
t.ok(text(anthropic) ~= before_a and text(anthropic):find("local d = 3", 1, true) ~= nil, "and to the chat on its right")
t.ok(noted("Sent to Anthropic (tab 1)") ~= nil, "saying where it went")
t.eq(layout(view_b), view_layout, "the view opened nothing")
-- The pickers too: what is picked opens in that page, never in the view.
api.nvim_set_current_tabpage(view_b)
choose("Claude Code")
ai.switch_chat()
vim.cmd("stopinsert")
t.eq(api.nvim_get_current_tabpage(), first_tab, "<leader>al from a view shows a hidden chat in the page it came from")
t.ok(claude.visible() and not anthropic.ui:is_visible(), "in place of the one there")
t.eq(layout(view_b), view_layout, "and the view keeps its windows")
pick(anthropic)
ai.switch_chat()

-- A question asked for a view and then cancelled leaves the user in the view.
editor()
ai.toggle()
t.ok(not anthropic.ui:is_visible(), "the page the views came from shows nothing on the right")
api.nvim_set_current_tabpage(view_b)
asked = {}
api.nvim_feedkeys("V", "x", false)
ai.send_selection()
t.eq({ asked[1] and asked[1].prompt, api.nvim_get_current_tabpage() }, { "Add selection to", view_b },
  "from a view whose page shows nothing <leader>as asks; cancelled, the user is back in the view")
ai.switch_chat()
t.eq({ #asked, api.nvim_get_current_tabpage() }, { 2, view_b }, "<leader>al too")
ai.resume()
t.eq({ #asked, api.nvim_get_current_tabpage() }, { 3, view_b }, "and <leader>ar")
t.eq(layout(view_b), view_layout, "the view opened nothing")
api.nvim_set_current_tabpage(first_tab)
pick(anthropic)
ai.switch_chat()
settle()

---------------------------------------------------------------------------
-- A chat shown in a window that is not its own: <C-c>'s successor
---------------------------------------------------------------------------

-- A chat started from a scratch window is created from the editor window:
-- its context and its review root are the edited file's.
vim.cmd("tabnew")
local cc_tab = api.nvim_get_current_tabpage()
vim.cmd.edit(vim.fn.fnameescape(file))
local cc_editor = api.nvim_get_current_win()
vim.cmd("botright new")
vim.bo.buftype = "nofile"
backend_choice("api:anthropic")
ai.new_chat()
settle()
local doomed = created[#created] and companion.chat_of(api.nvim_win_get_buf(api.nvim_get_current_win()))
t.eq(created[#created].win, cc_editor, "a chat picked from a scratch window is created from the editor window")
t.ok(doomed ~= nil and doomed ~= anthropic and doomed.ui:is_visible(), "and shown here")
-- <C-c> in it, with Anthropic -- shown in the first tabpage -- as the chat
-- upstream puts in its place (keymaps close: Chat.open into its window, then
-- close): that window becomes Anthropic's own, and the first tabpage still
-- shows Anthropic, in a window that no longer is.
local doomed_win = doomed.ui.winnr
Chats.open({ ui = anthropic.ui, winnr = doomed_win, window_opts = { default = true } })
doomed:close()
settle()
t.eq(anthropic.ui.winnr, doomed_win, "the successor's own window is the closed chat's")
api.nvim_set_current_tabpage(first_tab)
local function anthropic_wins(tab)
  return #vim.tbl_filter(function(w) return api.nvim_win_get_buf(w) == anthropic.bufnr end, api.nvim_tabpage_list_wins(tab))
end
t.eq(anthropic_wins(first_tab), 1, "and the first tabpage still shows it")
-- There it is the chat on the right: delivered to where it is, no jump.
editor()
local copy_layout = layout(first_tab)
d_lines, notes = count(text(anthropic), "local d = 3"), {}
api.nvim_win_set_cursor(0, { 3, 0 })
api.nvim_feedkeys("V", "x", false)
ai.send_selection()
t.eq(api.nvim_get_current_tabpage(), first_tab, "<leader>as to a chat shown here in a window not its own stays here")
t.eq(count(text(anthropic), "local d = 3"), d_lines + 1, "and adds the selection")
t.eq(layout(first_tab), copy_layout, "nothing opens or moves")
-- <leader>ac closes that window: the chat stays on screen in its own.
editor()
ai.toggle()
t.eq(anthropic_wins(first_tab), 0, "<leader>ac closes the copy here")
t.ok(anthropic.ui:is_visible() and api.nvim_win_get_tabpage(anthropic.ui.winnr) == cc_tab,
  "the chat stays shown in its own window, in the other tabpage")
api.nvim_set_current_tabpage(cc_tab)
vim.cmd("tabclose")
api.nvim_set_current_tabpage(first_tab)
editor()
pick(anthropic)
ai.switch_chat()
settle()

---------------------------------------------------------------------------
-- The guard leaves other tabpages, and claudecode's diff copy, alone
---------------------------------------------------------------------------

-- A chat buffer put into a window of another tabpage: the event is that
-- tabpage's, the guard runs here -- it does nothing.
api.nvim_set_current_tabpage(third_tab)
vim.cmd("vsplit")
local third_plain = api.nvim_get_current_win()
vim.cmd.enew()
api.nvim_set_current_tabpage(first_tab)
local third_layout_before = #api.nvim_tabpage_list_wins(third_tab)
api.nvim_win_set_buf(third_plain, openai.bufnr)
settle()
t.ok(third_chat.ui:is_visible() and api.nvim_win_get_buf(third_plain) == openai.bufnr,
  "a buffer set into another tabpage's window makes the guard touch nothing there")
t.eq(#api.nvim_tabpage_list_wins(third_tab), third_layout_before, "not a window")

-- claudecode's diff tabpage shows a copy of its terminal, which is not its own
-- window (display_terminal_in_new_tab: a split given the terminal's buffer):
-- the target there, but nothing the slot can hide. Claude's own window is
-- hidden meanwhile.
t.ok(claude.running() and not claude.window(), "Claude runs, its own window hidden")
vim.cmd("tabnew")
local diff_tab = api.nvim_get_current_tabpage()
vim.cmd.edit(vim.fn.fnameescape(file))
local diff_file_win = api.nvim_get_current_win()
vim.cmd("vsplit")
api.nvim_win_set_buf(0, claude.buf())
settle()
t.eq(shown_ids(diff_tab), { "native:claude" }, "Claude's copy in a diff tabpage is the chat on the right there")
notes = {}
ai.toggle()
t.eq(#wins(), 2, "<leader>ac cannot hide it")
t.ok(noted("answer it with <leader>aa / <leader>ad") ~= nil, "and says what to do instead")
-- Everything that reaches Claude there goes to that copy: claudecode's own
-- open judges by its own window, and would split a second Claude beside it.
local function claude_wins()
  return #vim.tbl_filter(function(w) return api.nvim_win_get_buf(w) == claude.buf() end, api.nvim_tabpage_list_wins(diff_tab))
end
local function in_diff_tab(what)
  t.eq({ api.nvim_get_current_tabpage(), claude_wins(), #cc_calls.open }, { diff_tab, 1, 0 },
    what .. " in claudecode's diff tabpage goes to its copy: one Claude window, nothing opened")
  api.nvim_set_current_win(diff_file_win)
  vim.cmd("stopinsert")
end
api.nvim_set_current_win(diff_file_win)
cc_calls.open, cc_calls.mentions = {}, {}
api.nvim_win_set_cursor(0, { 2, 0 })
api.nvim_feedkeys("V", "x", false)
ai.send_selection()
in_diff_tab("<leader>as")
ai.add_buffer()
in_diff_tab("<leader>ab")
t.eq(cc_calls.mentions, { { file, 1, 1 }, { file } }, "both mentioned")
notes = {}
ai.resume()
in_diff_tab("<leader>ar")
t.ok(noted("Claude Code is already running") ~= nil, "<leader>ar says so")
ai.compose()
in_diff_tab("<leader>ai")
ai.feed("claude", "edit_prompt", { seed = "review feedback" })
in_diff_tab("Review feedback for Claude")
require("ai.editor").stage_seed(nil, { provider = "claude" })
-- Claude's own window in the first tabpage, the copy here: still here, no jump.
api.nvim_set_current_tabpage(first_tab)
editor()
choose("Claude Code")
ai.switch_chat()
vim.cmd("stopinsert")
settle()
t.ok(claude.visible(), "Claude's own window in the first tabpage")
api.nvim_set_current_tabpage(diff_tab)
api.nvim_set_current_win(diff_file_win)
cc_calls.open, cc_calls.mentions, notes = {}, {}, {}
api.nvim_feedkeys("V", "x", false)
ai.send_selection()
in_diff_tab("<leader>as with its own window in another tabpage")
ai.add_buffer()
in_diff_tab("<leader>ab with its own window in another tabpage")
t.eq({ #cc_calls.mentions, noted("went there") }, { 2 }, "delivered to the copy, never gone from it")
vim.cmd("tabclose")
api.nvim_set_current_tabpage(first_tab)
editor()
pick(anthropic)
ai.switch_chat()
settle()

---------------------------------------------------------------------------
-- A directory listing's selection, and the commands
---------------------------------------------------------------------------

api.nvim_set_current_tabpage(second_tab)
for _, w in ipairs(wins()) do
  if api.nvim_win_get_buf(w) ~= openai.bufnr then api.nvim_set_current_win(w) end
end
vim.cmd.enew()
local listing = api.nvim_get_current_buf()
api.nvim_buf_set_lines(listing, 0, -1, false, { "a.lua", "b.lua" })
vim.bo[listing].filetype = "oil"
local listing_win = api.nvim_get_current_win()
notes = {}
api.nvim_feedkeys("Vj", "x", false)
ai.send_selection()
t.eq(vim.fn.mode(), "n", "a directory selection leaves Visual")
t.ok(noted("Only Claude Code takes files from a directory listing") ~= nil, "and refuses a chat on the right")
-- Nothing on the right: it cannot wait for a question, Visual being gone by
-- the answer.
ai.toggle()
asked, notes = {}, {}
api.nvim_feedkeys("Vj", "x", false)
ai.send_selection()
t.ok(noted("A directory selection cannot wait for a question") ~= nil and #asked == 0 and vim.fn.mode() == "n",
  "with nothing on the right, a directory selection is refused unasked")
-- Claude Code on the right takes it, through :ClaudeCodeSend on the live
-- selection.
choose("Claude Code")
ai.switch_chat()
vim.cmd("stopinsert")
api.nvim_set_current_win(listing_win)
cc_calls.sends = {}
api.nvim_feedkeys("Vj", "x", false)
ai.send_selection()
vim.cmd("normal! \27")
t.eq(#cc_calls.sends, 1, "Claude Code on the right takes a directory selection")
t.ok(cc_calls.sends[1] and cc_calls.sends[1].buf == listing and cc_calls.sends[1].mode:find("^[vV]") ~= nil,
  "through :ClaudeCodeSend, on the listing's live Visual selection")
vim.bo[listing].filetype = ""

asked = {}
vim.cmd("AI new")
t.eq(asked[1] and asked[1].prompt, "New AI chat", ":AI new opens the new-chat picker")
vim.cmd("AI chats")
t.eq(asked[2] and asked[2].prompt, "Switch AI chat", ":AI chats opens the switcher")

-- From Visual, the pickers take the selection along to the chat they show.
vim.cmd.edit(vim.fn.fnameescape(file))
api.nvim_win_set_cursor(0, { 1, 0 })
typed = {}
choose("Codex")
api.nvim_feedkeys("V", "x", false)
ai.switch_chat()
vim.cmd("stopinsert")
t.ok(vim.wait(2000, function() return typed_into(codex_buf, "@src/app.lua lines 1-1 ") end, 20),
  "Visual <leader>al shows Codex and types the selection into it")
t.ok(codex.visible(), "Codex is on the right here now")

-- Two AI windows here at once -- shown by hand, before the guard has run:
-- <leader>as asks among exactly those two; from inside one, that one.
editor()
local events = vim.o.eventignore
vim.o.eventignore = "BufWinEnter"
vim.cmd("vsplit")
api.nvim_win_set_buf(0, openai.bufnr)
local openai_copy = api.nvim_get_current_win()
vim.o.eventignore = events
t.eq(#slot.shown(), 2, "two AI windows shown here")
editor()
asked = {}
api.nvim_feedkeys("V", "x", false)
ai.send_selection()
t.eq(asked[1] and asked[1].prompt, "Add selection to", "<leader>as from the file asks which of them")
t.eq(#(asked[1] and asked[1].items or {}), 2, "among those two alone, no New chat… (" .. table.concat(asked[1] and asked[1].shown or {}, " | ") .. ")")
api.nvim_set_current_win(openai_copy)
asked = {}
ai.focus()
t.eq({ #asked, api.nvim_get_current_buf() }, { 0, openai.bufnr }, "from inside one of them, <leader>af takes that one unasked")
api.nvim_win_close(openai_copy, true)

-- A cold start from a window that is neither the file nor an AI window --
-- a scratch buffer nothing hides -- still takes the file's root: the slot
-- starts it from the editor window. A stopped Codex picked for <leader>am
-- gets /model submitted into its fresh box; nothing can be in it yet.
local first_codex = codex_buf
vim.fn.jobstop(vim.bo[codex_buf].channel)
t.ok(vim.wait(3000, function() return not codex.running() end, 20), "Codex exits")
settle()
notes = {}
editor()
vim.cmd("botright new")
vim.bo.buftype = "nofile"
local scratch_win = api.nvim_get_current_win()
typed = {}
choose("Codex")
ai.select_model()
vim.cmd("stopinsert")
local codex_again = codex.buf()
t.eq(codex_again and vim.b[codex_again].snacks_terminal.cwd, root,
  "<leader>am starts a stopped Codex from the editor window, not the scratch one: the file's root")
t.ok(vim.wait(2000, function() return sent(codex_again, "/model\r") end, 20), "and submits /model into its box")
if codex_again then codex_buf = codex_again end
api.nvim_win_close(scratch_win, true)

-- Review feedback goes to its round's agent (ai.feed): a chat shown here
-- gives way to that agent's panel like any other AI window.
editor()
choose("OpenAI")
ai.switch_chat()
settle()
editor()
t.ok(openai.ui:is_visible() and not codex.visible(), "a chat on the right, Codex hidden")
ai.feed("codex", "edit_prompt", { seed = "review feedback" })
vim.cmd("stopinsert")
settle()
t.ok(codex.visible() and not openai.ui:is_visible() and api.nvim_buf_is_valid(openai.bufnr),
  "ai.feed hides the chat for the agent it feeds")
require("ai.editor").stage_seed(nil, { provider = "codex" })

-- Claude stopped: <leader>ar and <leader>aR start it with their arguments,
-- from the editor window even when pressed in a chat.
for _, case in ipairs({ { "<leader>ar", ai.resume, "--resume" }, { "<leader>aR", ai.continue, "--continue" } }) do
  local old = claude.buf()
  if old then
    pcall(vim.fn.jobstop, vim.bo[old].channel)
    pcall(api.nvim_buf_delete, old, { force = true })
  end
  claude_term = nil
  editor()
  choose("OpenAI")
  ai.switch_chat()
  settle()
  local file_win = editor()
  api.nvim_set_current_win(openai.ui.winnr)
  cc_calls.open, cc_calls.open_win = {}, {}
  choose("Claude Code")
  case[2]()
  vim.cmd("stopinsert")
  settle()
  t.eq(cc_calls.open, { case[3] }, case[1] .. " starts a stopped Claude with " .. case[3])
  t.eq(cc_calls.open_win[1], file_win, case[1] .. ": from the editor window, not the chat")
  t.ok(claude.visible() and not openai.ui:is_visible(), case[1] .. ": shown in place of the chat")
end

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------

settle()
local posts = vim.tbl_filter(function(r) return r.method ~= "GET" end, requests)
t.eq(posts, {}, "no request but model-list lookups was attempted")
-- Every warning or error of the run is one a case above asked for: a guard
-- that raises, or a hide that fails, says so at WARN through the facade's
-- own guards, and would otherwise pass unseen.
local expected = {
  "NVIM_OPENAI_API_KEY is not set",
  "Buffer has unsaved changes",
  "Sending code to CodeCompanion is disabled",
  "This buffer has no file",
  "Only Claude Code takes files from a directory listing",
  "A directory selection cannot wait for a question",
  "is this tabpage's only window",
  "Terminal exited with code", -- Snacks, for the Codex stopped on purpose
}
local unexpected = vim.tbl_filter(function(n)
  if n.level < WARN then return false end
  for _, text in ipairs(expected) do
    if n.msg:find(text, 1, true) then return false end
  end
  return true
end, all_notes)
t.eq(unexpected, {}, "and nothing went wrong on the way")
t.ok(not loaded("claudecode.nvim"), "claudecode.nvim was never loaded: its stand-ins took every call")

require("codecompanion").chat = real_chat
for _, entry in ipairs(companion.chats()) do entry.chat:close() end
vim.cmd("silent! tabonly")
for _, buf in ipairs({ first_codex, codex_buf, claude.buf() }) do
  if buf and api.nvim_buf_is_valid(buf) then
    pcall(vim.fn.jobstop, vim.bo[buf].channel)
    pcall(api.nvim_buf_delete, buf, { force = true })
  end
end
api.nvim_chan_send = saved.chan_send
vim.ui.select = saved.select
package.loaded["claudecode"], package.loaded["claudecode.terminal"] = saved.cc, saved.cc_terminal
vim.env.PATH, vim.env.CODEX_WRAP_TMUX = saved.path, saved.wrap
vim.env.NVIM_ANTHROPIC_API_KEY, vim.env.NVIM_OPENAI_API_KEY = saved.anthropic, saved.openai
vim.notify = real_notify
vim.fn.delete(scratch, "rf")
t.done()
