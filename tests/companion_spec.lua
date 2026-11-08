-- CodeCompanion's two chat kinds behind the facade's <leader>a keys
-- (lua/ai/companion.lua, lua/ai/init.lua): agent chat (ACP, the provider, on
-- the subscription) on g/G and API chat (HTTP, the key profile, on API credits)
-- on h/H, plus the inline prompt on e.
--
-- What is pinned: each key reaches a chat of its own kind and the current
-- adapter, never upstream's `last_chat` of either kind; the kinds share one
-- chat window; a missing key or ACP bridge refuses before anything starts; and
-- an upgrade that breaks the internals falls back to the upstream commands.
--
-- Nothing is sent. No ACP chat is ever created -- that would spawn the bridge
-- -- so the ACP side runs on its refusal path and on stubbed chat lists. HTTP
-- chats are created with fake NVIM_* values set here, are never submitted
-- (codecompanion-history saves on submit and on a finished request, not on
-- creation), and CodeCompanion's curl layer is stubbed before the first one,
-- because creating an API chat already fetches the provider's model list.
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

-- Start from Claude with the anthropic key, whatever started this Nvim; the
-- other combinations are :AI's business (tests/ai_switch_spec.lua).
local start_provider = config.provider
vim.cmd("silent AI provider claude")
vim.cmd("AI key anthropic")

---------------------------------------------------------------------------
-- Refusals come first, and need nothing loaded
---------------------------------------------------------------------------

t.ok(not loaded(), "the chat keys exist before CodeCompanion loads")
t.eq(key(" ah").desc, "API chat · Anthropic (HTTP)", "<leader>ah names the key profile it reaches")
t.eq(key(" ag").desc, "Agent chat · Claude Code (ACP)", "<leader>ag names the agent it reaches")

vim.env.NVIM_ANTHROPIC_API_KEY = nil
notes = {}
press(" ah")
press(" aH")
t.eq(#errors(), 2, "<leader>ah and <leader>aH refuse while the profile's variable is unset")
t.ok(errors()[1].msg:find("NVIM_ANTHROPIC_API_KEY is not set", 1, true) ~= nil, "naming the variable")
t.eq(key(" ae").callback(), "<Ignore>", "<leader>ae refuses before the command line opens")
t.eq(#errors(), 3, "and says so too, once the textlock is gone")
t.ok(not loaded(), "a refusal loads nothing")

-- The ACP side only ever takes its refusal path here. PATH is cut down to the
-- system directories, so the real bridge is absent -- and could not be spawned
-- even if the refusal failed.
local real_path = vim.env.PATH
vim.env.PATH = "/usr/bin:/bin"
local bridge = config.codecompanion.acp_command
if vim.fn.executable(bridge) == 1 then
  print("skip - " .. bridge .. " is installed in a system directory")
else
  notes = {}
  press(" ag")
  press(" aG")
  t.eq(#errors(), 2, "<leader>ag and <leader>aG refuse without the ACP bridge")
  t.ok(errors()[1].msg:find(bridge .. " not found", 1, true) ~= nil, "naming the bridge")
  t.ok(not loaded(), "and load nothing either")
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
press(" ah")
local anthropic = companion.find("http")
t.ok(anthropic ~= nil and #chats() == 1, "<leader>ah starts an API chat when there is none")
t.eq({ anthropic.adapter.type, anthropic.adapter.name }, { "http", "anthropic" }, "on the active key profile")
t.ok(shown(anthropic) and vim.api.nvim_get_current_win() == anthropic.ui.winnr, "on screen here, and focused")
t.eq(windows(), base_windows + 1, "in one window")
local llm_role = require("codecompanion.config").interactions.chat.roles.llm
t.eq(llm_role(anthropic.adapter), "CodeCompanion (Anthropic · API)", "API replies are headed with the backend and the kind")
-- Resolving an ACP adapter only builds the table; the bridge starts with a chat.
t.eq(llm_role(require("codecompanion.adapters").resolve("claude_code")), "CodeCompanion (Claude Code · ACP)",
  "and so are agent replies")
local slot = anthropic.ui.winnr

vim.api.nvim_set_current_win(editor_win)
press(" ah")
t.ok(not shown(anthropic) and #chats() == 1, "<leader>ah again hides it, and starts nothing")
press(" ah")
t.ok(shown(anthropic) and #chats() == 1, "and again brings the same chat back")
slot = anthropic.ui.winnr

-- Another profile is another chat, in the same window.
vim.cmd("AI key openai")
t.eq(key(" ah").desc, "API chat · OpenAI (HTTP)", "a key switch relabels <leader>ah")
press(" ah")
local openai = companion.find("http")
t.ok(openai ~= nil and openai ~= anthropic and openai.adapter.name == "openai",
  "after :AI key openai, <leader>ah finds no OpenAI chat and starts one")
t.ok(shown(openai) and not shown(anthropic), "which takes the place of the Anthropic chat")
t.eq({ openai.ui.winnr, windows() }, { slot, base_windows + 1 }, "in the same window")

vim.cmd("AI key anthropic")
press(" ah")
t.eq(companion.find("http"), anthropic, "back on anthropic, <leader>ah finds that profile's chat")
t.ok(shown(anthropic) and not shown(openai) and #chats() == 2, "and swaps it back in, starting nothing")
t.eq({ anthropic.ui.winnr, windows() }, { slot, base_windows + 1 }, "still in the one window")

-- A pinned model reaches the new chat with the profile.
config.key_profiles.spec_pinned = { adapter = "anthropic", label = "Spec", api_key = "NVIM_ANTHROPIC_API_KEY", model = "spec-model" }
config.use_key("spec_pinned")
local params
local real_chat = require("codecompanion").chat
require("codecompanion").chat = function(args) params = args.params end
companion.new("http")
require("codecompanion").chat = real_chat
t.eq(params, { adapter = "spec_pinned", model = "spec-model" }, "a profile's pinned model goes along with its adapter")
config.key_profiles.spec_pinned = nil
vim.cmd("AI key anthropic")

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
press(" ah")
t.ok(shown(anthropic), "the Anthropic chat is back in the slot")

---------------------------------------------------------------------------
-- Visual mode: the selection goes to the chat of the key's kind and profile
---------------------------------------------------------------------------

-- last_chat is the Anthropic chat now. Upstream's Add would append there; the
-- OpenAI key must reach the OpenAI chat instead, hidden or not.
t.eq(Chats.last_chat(), anthropic, "upstream's last chat is the Anthropic one")
vim.cmd("AI key openai")
vim.api.nvim_set_current_win(editor_win)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.api.nvim_feedkeys("Vj ah", "x", false)
t.eq(vim.fn.mode(), "n", "the selection is let go of")
t.ok(text(openai):find("```lua\nlocal bc = 2\nlocal d = 3\n```", 1, true) ~= nil,
  "a linewise selection lands in the OpenAI chat, fenced with its filetype")
t.ok(text(openai):find("Here is some code from " .. vim.api.nvim_buf_get_name(source), 1, true) ~= nil,
  "with the source path")
t.ok(text(anthropic):find("local bc = 2", 1, true) == nil, "and not in upstream's last chat")
t.ok(shown(openai) and vim.api.nvim_get_current_win() == openai.ui.winnr, "which comes on screen, focused")
t.eq(windows(), base_windows + 1, "in the same window")

vim.api.nvim_set_current_win(editor_win)
vim.api.nvim_win_set_cursor(0, { 2, 6 })
vim.api.nvim_feedkeys("vl ah", "x", false)
t.ok(text(openai):find("```lua\nbc\n```", 1, true) ~= nil, "a characterwise selection keeps its columns")
t.eq(#chats(), 2, "adding to a chat starts none")

-- With no chat of the kind yet, adding starts one, without the selection
-- inserted twice.
openai:close()
t.eq(companion.find("http"), nil, "with the OpenAI chat closed there is none to add to")
vim.api.nvim_set_current_win(editor_win)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys("V ah", "x", false)
local fresh = companion.find("http")
t.ok(fresh ~= nil and fresh.adapter.name == "openai" and #chats() == 2,
  "a selection with no chat of its profile starts one")
local _, count = text(fresh):gsub("local a = 1", "")
t.eq(count, 1, "holding the selection once")

-- An unset key refuses here too, before a chat is started for it.
fresh:close()
vim.env.NVIM_OPENAI_API_KEY = nil
notes = {}
vim.api.nvim_set_current_win(editor_win)
vim.api.nvim_feedkeys("V ah", "x", false)
t.eq(#errors(), 1, "adding a selection refuses while the key is unset")
t.ok(companion.find("http") == nil, "and starts no chat")
t.eq(vim.fn.mode(), "n", "leaving Visual all the same")
fake_keys()
vim.cmd("AI key anthropic")

---------------------------------------------------------------------------
-- Agent chats: found by kind and adapter, from a stubbed chat list
---------------------------------------------------------------------------

local function fake(adapter_type, name, opts)
  opts = opts or {}
  local chat = { bufnr = vim.api.nvim_create_buf(false, true), adapter = { type = adapter_type, name = name } }
  chat.ui = {
    is_visible = function() return opts.visible == true end,
    is_visible_non_curtab = function() return false end,
    hide = function() chat.hidden_by_spec = true end,
  }
  return chat
end
local cc = require("codecompanion")
local real_list, real_last = cc.buf_get_chat, cc.last_chat
local list, last = {}, nil
cc.buf_get_chat = function() return vim.tbl_map(function(c) return { chat = c } end, list) end
cc.last_chat = function() return last end

local older = fake("acp", "claude_code")
local newer = fake("acp", "claude_code")
local codex = fake("acp", "codex", { visible = true })
local api = fake("http", "claude_code", { visible = true }) -- same name, other kind
list = { codex, api, older, newer }
t.eq(companion.find("acp"), newer, "agent chat: the newest Claude chat, not one of another agent or kind")
last = older
t.eq(companion.find("acp"), older, "upstream's last chat wins among those of the right kind")
local visible = fake("acp", "claude_code", { visible = true })
list[#list + 1] = visible
t.eq(companion.find("acp"), visible, "and one on screen here wins over both")
companion.toggle("acp")
t.ok(visible.hidden_by_spec == true, "<leader>ag on a shown agent chat hides it")

config.use_provider("codex")
t.eq(companion.find("acp"), codex, "with Codex active, the Codex agent chat is the one")
config.use_provider("claude")
config.use_key("anthropic")
list = { older }
last = nil
t.eq(companion.find("http"), nil, "an agent chat is never taken for an API chat")
cc.buf_get_chat, cc.last_chat = real_list, real_last

---------------------------------------------------------------------------
-- A broken internal falls back to upstream, with a warning
---------------------------------------------------------------------------

local real_toggle, real_add = companion.toggle, companion.add_selection
local real_cmd = vim.cmd
local ran = {}
companion.toggle = function() error("spec: toggle broke") end
companion.add_selection = function() error("spec: add broke") end
notes = {}
vim.cmd = function(command) ran[#ran + 1] = command end
press(" ah")
press(" ag", "x")
vim.cmd = real_cmd
companion.toggle, companion.add_selection = real_toggle, real_add
t.eq(ran, { "CodeCompanionChat Toggle", "'<,'>CodeCompanionChat Add" }, "a failing toggle or add runs the upstream command")
t.ok(#notes == 2 and notes[1].level == WARN and notes[1].msg:find("spec: toggle broke", 1, true) ~= nil,
  "and says why, as a warning")

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
vim.cmd("silent AI provider " .. start_provider)
vim.notify = real_notify
t.done()
