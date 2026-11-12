-- CodeCompanion chats behind the facade (lua/ai/companion.lua, lua/ai/init.lua):
-- created by backend from the new-chat picker (<leader>an) -- an ACP agent on
-- the subscription, or a key profile's API on API credits -- and shown as
-- exactly that chat; plus the inline prompt on <leader>ae, which bills the key
-- profile :AI key picks.
--
-- What is pinned: a chat is created on the adapter (and model) its backend
-- names, never upstream's `last_chat` or default; chats share one window; a
-- missing key or ACP bridge refuses before anything starts, and the picker does
-- not offer what would refuse; a broken internal is reported, never routed to
-- an upstream command aimed at another chat; the internals the slot relies
-- on behave as it expects; and the chat's, the inline request's, the prompt
-- float's and the saved-chat picker's keys stay off keys that mean something
-- else everywhere (Insert <C-c> leaves Insert mode, gx opens a URL).
--
-- CodeCompanion's own code review is off: review rounds (lua/ai/review)
-- replace it, and two baseline systems must not run side by side.
--
-- Nothing is sent. No ACP chat is ever created -- that would spawn the bridge
-- -- so the ACP side runs on its refusal path. HTTP chats are created with fake
-- NVIM_* values set here, are never submitted (codecompanion-history saves on
-- submit and on a finished request, not on creation), and CodeCompanion's curl
-- layer is stubbed before the first one, because creating an API chat already
-- fetches the provider's model list. Questions are answered by a stand-in
-- vim.ui.select.
local t = dofile("tests/helper.lua")

local config = require("ai.config")
local companion = require("ai.companion")
local Config = require("lazy.core.config")
local INFO, WARN, ERROR = vim.log.levels.INFO, vim.log.levels.WARN, vim.log.levels.ERROR

local notes = {}
local real_notify = vim.notify
vim.notify = function(msg, level) notes[#notes + 1] = { msg = tostring(msg), level = level or INFO } end
local function settle() vim.wait(50, function() return false end, 10) end
local function errors()
  settle()
  return vim.tbl_filter(function(n) return n.level == ERROR end, notes)
end

local function loaded() return Config.plugins["codecompanion.nvim"]._.loaded ~= nil end
local function key(lhs, mode) return vim.fn.maparg(lhs, mode or "n", false, true) end
local function press(lhs, mode) return key(lhs, mode).callback() end

-- Fake keys, set inside this spec only. Whatever the shell exported is put
-- back at the end, and the agent CLIs' own variables are never touched.
local VARS = { "NVIM_ANTHROPIC_API_KEY", "NVIM_OPENAI_API_KEY" }
local saved = {}
for _, var in ipairs(VARS) do saved[var] = vim.env[var] end
local function fake_keys()
  vim.env.NVIM_ANTHROPIC_API_KEY = "sk-ant-spec-not-a-key"
  vim.env.NVIM_OPENAI_API_KEY = "sk-spec-not-a-key"
end
fake_keys()

-- Inline edits on the anthropic key, whatever the shell pinned; switching it
-- is :AI's business (tests/ai_switch_spec.lua).
local start_key = config.key_setting()
vim.cmd("AI key anthropic")

-- Questions: each answered by the next entry queued -- a backend id for the
-- new-chat picker, a chat for the switcher. With nothing queued, a question
-- cancels. `offered` keeps what the last one listed.
local answers, offered = {}, {}
local real_select = vim.ui.select
vim.ui.select = function(items, _, on_choice)
  offered = items
  local want = table.remove(answers, 1)
  for _, item in ipairs(items) do
    if want ~= nil and (item.id == want or item.chat == want) then return on_choice(item) end
  end
  on_choice(nil)
end
local function backend(id)
  return vim.iter(config.backends()):find(function(b) return b.id == id end)
end
local function offers(id)
  return vim.iter(offered):any(function(item) return item.id == id end)
end

---------------------------------------------------------------------------
-- Refusals come first, and need nothing loaded
---------------------------------------------------------------------------

t.ok(not loaded(), "the chat keys exist before CodeCompanion loads")
for _, lhs in ipairs({ " ag", " aG", " ah", " aH" }) do
  t.eq(key(lhs), {}, "<leader>" .. lhs:sub(2) .. " is gone: <leader>an starts a chat of either kind")
end

vim.env.NVIM_ANTHROPIC_API_KEY = nil
notes = {}
press(" an")
t.ok(not offers("api:anthropic") and offers("api:openai"),
  "the new-chat picker leaves out an API chat whose profile's variable is unset")
t.eq(companion.create(backend("api:anthropic")), nil, "and creating one anyway is refused")
t.ok(errors()[1] and errors()[1].msg:find("NVIM_ANTHROPIC_API_KEY is not set", 1, true) ~= nil, "naming the variable")
t.eq(key(" ae").callback(), "<Ignore>", "<leader>ae refuses before the command line opens")
t.eq(#errors(), 2, "and says so too, once the textlock is gone")
t.ok(not loaded(), "a refusal loads nothing")

-- The ACP side only ever takes its refusal path here. PATH is cut down to the
-- system directories, so the real bridge is absent -- and could not be spawned
-- even if the refusal failed.
local real_path = vim.env.PATH
vim.env.PATH = "/usr/bin:/bin"
local acp = backend("acp:" .. config.codecompanion.acp_adapter)
if vim.fn.executable(acp.command) == 1 then
  print("skip - " .. acp.command .. " is installed in a system directory")
else
  notes = {}
  press(" an")
  t.ok(not offers(acp.id), "the new-chat picker leaves out an ACP chat whose bridge is missing")
  t.eq(companion.create(acp), nil, "and creating one anyway is refused")
  t.ok(errors()[1] and errors()[1].msg:find(acp.command .. " not found", 1, true) ~= nil, "naming the bridge")
  t.ok(not loaded(), "and loads nothing either")
end
vim.env.PATH = real_path
fake_keys()
t.eq(key(" ae").callback(), ":CodeCompanion ", "with the key set, <leader>ae opens the inline prompt")

---------------------------------------------------------------------------
-- API chats: one per profile, one shared window
---------------------------------------------------------------------------

-- Snapshot both stores a chat could be written to, to show nothing is.
local function store_listing()
  local listing = {}
  for _, dir in ipairs({ vim.fn.stdpath("data") .. "/codecompanion-history", vim.fn.stdpath("data") .. "/codecompanion/sessions" }) do
    if vim.fn.isdirectory(dir) == 1 then
      for name, kind in vim.fs.dir(dir, { depth = 3 }) do
        local stat = kind == "file" and vim.uv.fs_stat(dir .. "/" .. name)
        listing[dir .. "/" .. name] = stat and (stat.mtime.sec .. "." .. stat.mtime.nsec) or kind
      end
    end
  end
  return listing
end
local stores_before = store_listing()

require("lazy").load({ plugins = { "codecompanion.nvim" } })
local Curl = require("codecompanion.utils.curl")
local requests = {}
Curl.request = function(opts)
  requests[#requests + 1] = { method = (opts.method or "GET"):upper(), url = opts.url }
  return {}
end
Curl.request_sync = function(opts)
  requests[#requests + 1] = { method = (opts.method or "GET"):upper(), url = opts.url }
  return nil, { message = "stubbed by companion_spec" }
end
local Chats = require("codecompanion.interactions.chat")

-- CodeCompanion's own code review keeps a second baseline system of its own
-- (refs/worktree/codecompanion/*); review rounds replace it, so it is off, its
-- command is gone and its editor context is offered nowhere.
local cc_config = require("codecompanion.config")
t.eq(cc_config.interactions.code_review.enabled, false, "CodeCompanion's code review is disabled")
t.eq(vim.fn.exists(":CodeCompanionCodeReview"), 0, ":CodeCompanionCodeReview does not exist once CodeCompanion loads")
t.ok(not pcall(vim.api.nvim_get_autocmds, { group = "codecompanion.code_review" }),
  "and its codecompanion.code_review augroup was never created")
t.ok(not vim.tbl_contains(Config.plugins["codecompanion.nvim"].cmd or {}, "CodeCompanionCodeReview"),
  "nor does the lazy spec list it as a trigger")
local contexts = require("codecompanion.interactions.shared.editor_context").new("chat").editor_context
t.ok(contexts.code_review == nil and contexts.buffer ~= nil, "#{code_review} is not offered in a chat; #{buffer} still is")

local editor_win = vim.api.nvim_get_current_win()
vim.cmd.enew()
local source = vim.api.nvim_get_current_buf()
-- Named but never written: the path only has to show up in the chat.
local source_path = vim.fn.tempname() .. "_sample.lua"
vim.api.nvim_buf_set_name(source, source_path)
vim.bo[source].filetype = "lua"
vim.api.nvim_buf_set_lines(source, 0, -1, false, { "local a = 1", "local bc = 2", "local d = 3" })

local function chats()
  return vim.tbl_map(function(entry) return entry.chat end, require("codecompanion").buf_get_chat())
end
local function windows()
  local n = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == "" then n = n + 1 end
  end
  return n
end
local function shown(chat) return chat.ui:is_visible() and not chat.ui:is_visible_non_curtab() end
local function text(chat) return table.concat(vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false), "\n") end

local base_windows = windows()
answers = { "api:anthropic" }
press(" an")
local anthropic = chats()[1]
t.ok(anthropic ~= nil and #chats() == 1, "<leader>an starts the API chat picked")
t.eq({ anthropic.adapter.type, anthropic.adapter.name }, { "http", "anthropic" }, "on the profile its entry names")
t.ok(shown(anthropic) and vim.api.nvim_get_current_win() == anthropic.ui.winnr, "on screen here, and focused")
t.eq(windows(), base_windows + 1, "in one window")
local llm_role = require("codecompanion.config").interactions.chat.roles.llm
t.eq(llm_role(anthropic.adapter), "CodeCompanion (Anthropic · API)", "API replies are headed with the backend and the kind")
-- Resolving an ACP adapter only builds the table; the bridge starts with a chat.
t.eq(llm_role(require("codecompanion.adapters").resolve("claude_code")), "CodeCompanion (Claude Code · ACP)",
  "and so are agent replies")
local slot = anthropic.ui.winnr

vim.api.nvim_set_current_win(editor_win)
press(" ac")
t.ok(not shown(anthropic) and #chats() == 1, "<leader>ac hides it, and starts nothing")
press(" ac")
t.ok(shown(anthropic) and #chats() == 1, "and again brings the same chat back")
slot = anthropic.ui.winnr

-- Another profile is another chat, in the same window -- whatever :AI key
-- says, which is about inline edits.
answers = { "api:openai" }
press(" an")
local openai = vim.iter(chats()):find(function(c) return c ~= anthropic end)
t.ok(openai ~= nil and openai.adapter.name == "openai" and config.key.name == "anthropic",
  "<leader>an starts an OpenAI chat, with the key profile still on Anthropic")
t.ok(shown(openai) and not shown(anthropic), "which takes the place of the Anthropic chat")
t.eq({ openai.ui.winnr, windows() }, { slot, base_windows + 1 }, "in the same window")

answers = { anthropic }
press(" al")
t.ok(shown(anthropic) and not shown(openai) and #chats() == 2, "<leader>al swaps the Anthropic chat back in, starting nothing")
t.eq({ anthropic.ui.winnr, windows() }, { slot, base_windows + 1 }, "still in the one window")

-- A pinned model reaches the new chat with the profile.
local providers = vim.deepcopy(config.providers)
local with_pinned = vim.deepcopy(providers)
with_pinned[#with_pinned + 1] = { name = "spec_pinned", label = "Spec",
  api = { name = "spec_pinned", adapter = "anthropic", api_key = "NVIM_ANTHROPIC_API_KEY", model = "spec-model" } }
config._set_providers(with_pinned)
local pinned = backend("api:spec_pinned")
t.ok(pinned ~= nil and pinned.available, "every key profile has an API chat entry")
local params
local real_chat = require("codecompanion").chat
require("codecompanion").chat = function(args) params = args.params end
companion.create(pinned)
require("codecompanion").chat = real_chat
t.eq(params, { adapter = "spec_pinned", model = "spec-model" }, "a profile's pinned model goes along with its adapter")
config._set_providers(providers)

-- A chat that comes back with earlier turns (what codecompanion-history
-- restores) renders the custom header, and the buffer still parses: the next
-- question is read from the user header after it.
local restored = require("codecompanion").chat({
  params = { adapter = "anthropic" },
  auto_submit = false,
  messages = { { role = "user", content = "hi" }, { role = "llm", content = "hello" }, { role = "user", content = "" } },
})
local restored_lines = vim.api.nvim_buf_get_lines(restored.bufnr, 0, -1, false)
t.ok(vim.tbl_contains(restored_lines, "## CodeCompanion (Anthropic · API)"), "a restored chat shows the custom reply header")
vim.api.nvim_buf_set_lines(restored.bufnr, -1, -1, false, { "next question" })
local parser = require("codecompanion.interactions.chat.parser")
t.eq(parser.messages(restored, parser.headers(restored) + 1), { content = "next question" },
  "and the next question still parses on its own")
restored:close()
require("ai.slot").show_chat(anthropic)
t.ok(shown(anthropic), "the Anthropic chat is back in the slot")

---------------------------------------------------------------------------
-- Upstream internals the slot relies on (lua/ai/companion.lua open/create)
---------------------------------------------------------------------------

-- A chat created hidden: rendered, announced, not on screen, and not
-- upstream's last chat until it is entered.
local events = {}
local event_group = vim.api.nvim_create_augroup("companion_spec_events", { clear = true })
for _, pattern in ipairs({ "CodeCompanionChatCreated", "CodeCompanionChatOpened", "CodeCompanionChatHidden" }) do
  vim.api.nvim_create_autocmd("User", { group = event_group, pattern = pattern,
    callback = function(ev) events[#events + 1] = { pattern, ev.data and ev.data.bufnr } end })
end
local last_before = Chats.last_chat()
vim.api.nvim_set_current_win(editor_win)
local hidden = require("codecompanion").chat({ params = { adapter = "openai" }, hidden = true })
t.ok(hidden ~= nil and not hidden.ui:is_visible(), "chat({ hidden = true }) makes a chat that is not on screen")
t.ok(hidden ~= nil and vim.iter(events):any(function(e) return e[1] == "CodeCompanionChatCreated" and e[2] == hidden.bufnr end),
  "and announces it")
t.ok(hidden and vim.api.nvim_buf_line_count(hidden.bufnr) > 1, "with its buffer rendered all the same")
t.eq(Chats.last_chat(), last_before, "it is not upstream's last chat until it is entered")
-- Handed the window of the chat shown here: hide with keep_window, then
-- Chat.open with that window, which is ui:show_in_win.
local here_win = anthropic.ui.winnr
events = {}
anthropic.ui:hide({ keep_window = true })
t.ok(vim.api.nvim_win_is_valid(here_win), "ui:hide({ keep_window = true }) leaves the window for the next chat")
Chats.open({ ui = hidden.ui, winnr = here_win })
t.eq({ hidden.ui.winnr, vim.api.nvim_win_get_buf(here_win) }, { here_win, hidden.bufnr },
  "Chat.open({ ui, winnr }) shows the chat in exactly that window")
t.ok(not anthropic.ui:is_visible(), "which the other chat no longer has")
t.eq(vim.bo[hidden.bufnr].filetype, "codecompanion", "as a chat buffer")
t.eq(events, { { "CodeCompanionChatHidden", anthropic.bufnr }, { "CodeCompanionChatOpened", hidden.bufnr } },
  "hidden and opened, as upstream's own swap reports them")
t.eq(windows(), base_windows + 1, "one window throughout")
-- With no chat window here, ui:open() splits one of its own.
hidden.ui:hide()
t.eq(windows(), base_windows, "ui:hide() closes the window")
hidden.ui:open()
t.ok(shown(hidden) and windows() == base_windows + 1, "ui:open() opens one here")
t.eq(vim.api.nvim_win_get_cursor(hidden.ui.winnr)[1], vim.api.nvim_buf_line_count(hidden.bufnr),
  "following the conversation to its end")
vim.api.nvim_del_augroup_by_id(event_group)
hidden:close()
vim.api.nvim_set_current_win(editor_win)
require("ai.slot").show_chat(anthropic)
t.ok(shown(anthropic), "the Anthropic chat is back in the slot")

---------------------------------------------------------------------------
-- Keys: upstream's defaults moved off keys that mean something else
-- everywhere (lua/plugins/ai/codecompanion.lua)
---------------------------------------------------------------------------

-- As resolved in the live config.
local chat_keys = cc_config.interactions.chat.keymaps
local function modes(name) return type(chat_keys[name]) == "table" and chat_keys[name].modes or nil end
for name, want in pairs({
  close = { n = "<localleader>q" },
  stop = { n = "<C-c>" },
  hide = { n = "q" },
  send = { n = "<CR>", i = "<C-d>" },
  clear = { n = "<localleader>X" },
  fold_code = { n = "<localleader>z" },
  goto_file_under_cursor = { n = "gf" },
  options = { n = { "?", "g?" } },
  ["Save Current Chat"] = { n = "<localleader>s" },
}) do
  t.eq(modes(name), want, "chat keymap " .. name)
end
for _, name in ipairs({ "next_chat", "previous_chat", "copilot_stats", "change_adapter" }) do
  t.eq(chat_keys[name], nil, "chat keymap " .. name .. " is off")
end
t.eq(cc_config.interactions.inline.keymaps.stop.modes, { n = "<C-c>" },
  "an inline request stops on <C-c>, leaving q to macro recording in the edited file")
t.eq(cc_config.display.input.keymaps.send.modes, { n = "<CR>", i = "<C-d>" },
  "the prompt float sends on <CR>, and <C-d> from Insert mode")

-- As mapped in a real chat buffer.
vim.api.nvim_set_current_win(anthropic.ui.winnr)
local function own(lhs, mode)
  local map = key(lhs, mode)
  return map.buffer == 1 and map.desc or nil
end
for _, case in ipairs({
  { "q", "Hide chat" },
  { "<C-c>", "Stop request" },
  { ",q", "Close chat (ends it)" },
  { ",X", "Clear chat messages" },
  { ",z", "Fold code blocks" },
  { ",s", "Save chat" },
  { "gf", "Go to file under cursor" },
  { "gh", "Browse saved Companion chats" },
  { "?", "Options" },
  { "g?", "Options" },
  { "<CR>", "Send message" },
  { "<C-d>", "Send message", "i" },
}) do
  t.eq(own(case[1], case[3]), case[2], ("the chat maps %s%s"):format(case[3] and "Insert " or "", case[1]))
end
for _, case in ipairs({ { "<C-c>", "i" }, { "<C-s>", "i" }, { "<C-s>" }, { "gx" }, { "gR" }, { "}" }, { "{" },
  { "gS" }, { "sc" }, { "ga" } }) do
  t.eq(own(case[1], case[2]), nil, ("the chat leaves %s%s alone"):format(case[2] and "Insert " or "", case[1]))
end
t.eq(key("gx").desc, "Open URL / local file", "gx in the chat opens the URL under the cursor, as everywhere")
t.eq(key("<C-c>", "i").desc, "Exit Insert mode", "Insert <C-c> in the chat is the global one")
local general = vim.tbl_filter(function(map) return map.lhs:match("^,[hjklrce]") ~= nil end,
  vim.api.nvim_buf_get_keymap(anthropic.bufnr, "n"))
t.eq(general, {}, "and the general comma actions (,h ,j ,k ,l ,r ,c ,e…) keep their meaning")
-- Pressed: Insert <C-c> leaves Insert mode, and the chat stays.
local open_before = #chats()
vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(anthropic.bufnr), 0 })
vim.api.nvim_feedkeys("A" .. vim.keycode("<C-c>"), "x", false)
t.eq(vim.fn.mode(), "n", "Insert <C-c> in the chat leaves Insert mode")
t.ok(shown(anthropic) and #chats() == open_before, "and the chat is still open, on screen")

-- codecompanion-history's saved-chat picker (<leader>ao), built around one
-- stand-in entry and caught before Snacks opens it: nothing is read or saved.
local Storage = require("codecompanion._extensions.history.storage")
local snacks_picker = require("snacks.picker")
local real_get_chats, real_pick = Storage.get_chats, snacks_picker.pick
local picked
Storage.get_chats = function() return { spec = { save_id = "spec", title = "spec", updated_at = 0 } } end
snacks_picker.pick = function(opts) picked = opts end
vim.cmd("CodeCompanionHistory")
Storage.get_chats, snacks_picker.pick = real_get_chats, real_pick
for _, win in ipairs({ "input", "list" }) do
  local keys = {}
  for lhs, spec in pairs(picked and picked.win[win].keys or {}) do keys[spec.mode .. " " .. lhs] = spec[1] end
  t.eq({ keys["n dd"], keys["i <C-x>"], keys["n r"] }, { "delete_item", "delete_item", "rename_item" },
    ("the saved-chat picker's %s deletes on dd / <C-x> and renames on r"):format(win))
  t.ok(keys["n d"] == nil and keys["i <M-d>"] == nil and keys["i <M-r>"] == nil,
    ("and no longer on d, <M-d> (inspect) or <M-r> (toggle_regex) in its %s"):format(win))
  local insert_rename = vim.tbl_filter(function(k) return keys[k] == "rename_item" and k:sub(1, 2) == "i " end, vim.tbl_keys(keys))
  t.eq(insert_rename, { "i <Plug>(codecompanion-history-rename)" }, ("its %s has no Insert key a user types to rename"):format(win))
end

vim.api.nvim_set_current_win(editor_win)

---------------------------------------------------------------------------
-- Visual mode: the selection goes to the chat on the right, or a new one
---------------------------------------------------------------------------

-- last_chat is the Anthropic chat now. Upstream's Add would append there; the
-- OpenAI chat on the right gets it instead.
t.eq(Chats.last_chat(), anthropic, "upstream's last chat is the Anthropic one")
require("ai.slot").show_chat(openai)
vim.api.nvim_set_current_win(editor_win)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.api.nvim_feedkeys("Vj as", "x", false)
t.eq(vim.fn.mode(), "n", "the selection is let go of")
t.ok(text(openai):find("```lua\nlocal bc = 2\nlocal d = 3\n```", 1, true) ~= nil,
  "a linewise selection lands in the OpenAI chat on the right, fenced with its filetype")
t.ok(text(openai):find("Here is some code from " .. vim.api.nvim_buf_get_name(source), 1, true) ~= nil,
  "with the source path")
t.ok(text(anthropic):find("local bc = 2", 1, true) == nil, "and not in upstream's last chat")
t.ok(shown(openai) and vim.api.nvim_get_current_win() == openai.ui.winnr, "which stays on screen, focused")
t.eq(windows(), base_windows + 1, "in the same window")

vim.api.nvim_set_current_win(editor_win)
vim.api.nvim_win_set_cursor(0, { 2, 6 })
vim.api.nvim_feedkeys("vl as", "x", false)
t.ok(text(openai):find("```lua\nbc\n```", 1, true) ~= nil, "a characterwise selection keeps its columns")
t.eq(#chats(), 2, "adding to a chat starts none")

-- From Visual mode <leader>an starts the chat and gives it the selection,
-- inserted once.
openai:close()
vim.api.nvim_set_current_win(editor_win)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
answers = { "api:openai" }
vim.api.nvim_feedkeys("V an", "x", false)
local fresh = vim.iter(chats()):find(function(c) return c ~= anthropic end)
t.ok(fresh ~= nil and fresh.adapter.name == "openai" and #chats() == 2, "Visual <leader>an starts the chat picked")
local _, count = text(fresh or anthropic):gsub("local a = 1", "")
t.eq(count, 1, "holding the selection once")
t.eq(vim.fn.mode(), "n", "leaving Visual all the same")
fresh:close()

---------------------------------------------------------------------------
-- A broken internal is reported, not routed to another chat
---------------------------------------------------------------------------

-- Upstream's :'<,'>CodeCompanionChat Add appends to last_chat, which need not
-- be the chat on the right: nothing falls back to it.
require("ai.slot").show_chat(anthropic)
local real_capture, real_cmd = companion.add_capture, vim.cmd
local ran = {}
companion.add_capture = function() error("spec: add broke") end
notes = {}
vim.api.nvim_set_current_win(editor_win)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd = setmetatable({}, { __call = function(_, command) ran[#ran + 1] = command end, __index = real_cmd })
vim.api.nvim_feedkeys("V as", "x", false)
vim.cmd = real_cmd
companion.add_capture = real_capture
t.eq(vim.tbl_filter(function(c) return type(c) == "string" and c:find("CodeCompanion", 1, true) end, ran), {},
  "a failing add runs no upstream command")
t.ok(#errors() == 1 and errors()[1].msg:find("spec: add broke", 1, true) ~= nil, "and says why, as an error")
t.ok(text(anthropic):find("local a = 1", 1, true) == nil, "adding nothing anywhere")

---------------------------------------------------------------------------
-- Nothing was sent or saved
---------------------------------------------------------------------------

settle()
local posts = vim.tbl_filter(function(r) return r.method ~= "GET" end, requests)
t.eq(posts, {}, "no request but model-list lookups was even attempted")
for _, chat in ipairs(chats()) do
  t.ok(chat.current_request == nil, "chat " .. chat.adapter.name .. " has nothing in flight")
end
t.eq(store_listing(), stores_before, "no chat history or session was written")

for _, chat in ipairs(chats()) do chat:close() end
for _, var in ipairs(VARS) do vim.env[var] = saved[var] end
vim.cmd("silent AI key " .. start_key)
vim.ui.select = real_select
vim.notify = real_notify
t.done()
