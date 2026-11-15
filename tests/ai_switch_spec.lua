-- Codex-only host choices, ordered transport/profile fixtures and live HTTP switching.
-- No agent, ACP connection or HTTP request is started.
local t = dofile("tests/helper.lua")
local state = require("agent_workbench.state")
local agent = require("agent_workbench")
local switch = require("agent_workbench.switch")
local original = vim.deepcopy(state.providers)
local original_key = state.key_setting()
local settings = assert(loadfile("lua/config/ai.lua"))
setfenv(settings, {})
t.eq(settings(), require("config.ai"), "editable AI declarations are plain data")
t.eq(state.providers, require("config.ai").providers, "runtime resolved the declared provider list")
t.eq(state.agent_names(), { "codex" }, "only Codex is an implemented/enabled native backend")
t.eq(vim.fn.exists(":ClaudeCode"), 0, "no Claude command is offered")
t.eq(vim.fn.maparg("<leader>aa", "n"), "", "no Claude proposal accept key")
t.eq(vim.fn.maparg("<leader>ad", "n"), "", "no Claude proposal reject key")
local notes, events = {}, {}
local notify = vim.notify
vim.notify = function(message, level) notes[#notes + 1] = { message = tostring(message), level = level } end
vim.api.nvim_create_autocmd("User", { pattern = "AIStateChanged", callback = function(ev) events[#events + 1] = ev.data end })
local fixture = {
  { name = "codex", label = "Codex", cli_api_key = "OPENAI_API_KEY", tui = { kind = "codex" },
    acp = { adapter = "codex", command = "codex-acp", auth_method = "chat-gpt" },
    api = { adapter = "openai", label = "OpenAI", api_key = "NVIM_OPENAI_API_KEY" } },
  { name = "work", label = "Work", api = { adapter = "openai", name = "work", label = "Work OpenAI", api_key = "NVIM_WORK_OPENAI_KEY" } },
  { name = "anthropic", label = "Anthropic", api = { adapter = "anthropic", api_key = "NVIM_ANTHROPIC_API_KEY" } },
}
local vars = { "NVIM_OPENAI_API_KEY", "NVIM_WORK_OPENAI_KEY", "NVIM_ANTHROPIC_API_KEY" }
local saved = {}
for _, name in ipairs(vars) do saved[name] = vim.env[name] or false; vim.env[name] = nil end
local function ids() return vim.tbl_map(function(backend) return backend.id end, state.backends()) end
state._set_providers(fixture)
t.eq(ids(), { "codex", "acp:codex", "api:openai", "api:work", "api:anthropic" }, "transports group first, provider order applies within each group")
t.eq(state.key_names(), { "openai", "work", "anthropic" }, "each API profile has its own stable adapter identity")
t.eq(state.codecompanion.chat_adapter, "codex", "unqualified Companion chats use the first ACP adapter")
t.ok(state.default == nil and state.provider == nil and state.use_provider == nil, "there is no implicit default backend")
t.eq(state.auto_key(), "openai", "auto without exported keys selects first API profile")
vim.env.NVIM_WORK_OPENAI_KEY = "offline-test-only"
t.eq(state.auto_key(), "work", "auto selects the first exported key")
vim.env.NVIM_OPENAI_API_KEY = "offline-test-only"
t.eq(state.auto_key(), "openai", "provider order breaks ties between exported keys")
state._set_providers({ fixture[2], fixture[1], fixture[3] })
t.eq(ids(), { "codex", "acp:codex", "api:work", "api:openai", "api:anthropic" }, "reordering profiles does not change transport grouping")
t.eq(state.auto_key(), "work", "provider order also changes auto's preference")
state._set_providers(fixture)
agent.apply_keymaps()
t.eq(vim.fn.getcompletion("AI ", "cmdline"), { "new", "key", "info" }, "AI command exposes its subcommands")
t.eq(vim.fn.getcompletion("AI key ", "cmdline"), { "auto", "openai", "work", "anthropic" }, "key completion follows configured profiles")
t.eq(vim.fn.getcompletion("AI key w", "cmdline"), { "work" }, "key completion filters typed prefix")
t.eq(vim.fn.getcompletion("AI key work ", "cmdline"), {}, "no arguments follow a profile name")
t.eq(vim.fn.exists(":AIInfo"), 2, "documented AIInfo entry remains available")
local before = agent.sessions()
vim.cmd("AI key work")
t.eq(state.key_setting(), "work", "command pins one HTTP profile")
t.eq(state.codecompanion.http_adapter, "work", "inline/cmd use that profile's registered adapter")
t.ok((vim.fn.maparg("<leader>ae", "n", false, true).desc or ""):find("Work OpenAI", 1, true), "HTTP mapping names the selected billing profile")
t.eq(events[#events] and events[#events].axis, "key", "profile change announces its axis")
t.eq(agent.sessions(), before, "key switching starts no native session")
t.ok(package.loaded["codecompanion"] == nil, "switching a key does not load CodeCompanion")
local snapshot, count = vim.deepcopy(state.key), #events
vim.cmd("AI key missing")
t.eq(state.key, snapshot, "unknown key leaves effective state intact")
t.eq(#events, count, "unknown key emits no state change")
t.eq(notes[#notes].level, vim.log.levels.ERROR, "unknown key reports one actionable error")
vim.cmd("AI key work")
t.eq(#events, count, "selecting the same pinned profile is a no-op")
vim.env.NVIM_OPENAI_API_KEY = nil
vim.cmd("AI key auto")
t.eq({ state.key.name, state.key.auto }, { "work", true }, "auto re-resolves current environment")
vim.env.NVIM_OPENAI_API_KEY = "offline-test-only"
vim.cmd("AI key auto")
t.eq(state.key.name, "openai", "selecting auto again sees newly exported keys")
local choose = vim.ui.select
local prompts = {}
vim.ui.select = function(_, opts, callback) prompts[#prompts + 1] = opts.prompt; callback(nil) end
vim.cmd("AI")
vim.cmd("AI new")
vim.ui.select = choose
t.eq(prompts, { "New AI chat", "New AI chat" }, "cancelled new-chat questions start nothing")
t.eq(agent.sessions(), before, "cancelled choices preserve existing sessions")
for _, command in ipairs({ "AI provider", "AI provider codex" }) do
  vim.cmd(command)
  t.ok(notes[#notes].message:find(":AI new", 1, true), "removed provider command explains the replacement")
end
vim.cmd("AI info")
local info = notes[#notes].message
t.ok(info:find("Codex", 1, true) and info:find("NVIM_WORK_OPENAI_KEY", 1, true), "info lists configured providers and variable names")
t.ok(not info:find("offline-test-only", 1, true), "info never prints key values")
t.ok(info:find("codex (ACP)", 1, true), "info names the unqualified chat adapter and transport")
local function refused(list, text, label)
  local ok, err = pcall(state.build, list)
  t.ok(not ok and tostring(err):find(text, 1, true), label .. ": " .. tostring(err))
end
refused({}, "non-empty", "empty provider list")
refused({ fixture[1], fixture[1] }, "listed twice", "duplicate provider name")
local duplicate = vim.deepcopy(fixture[1]); duplicate.name = "other"
refused({ fixture[1], duplicate }, 'tui kind "codex" is already offered', "duplicate native kind")
refused({ { name = "bad", label = "Bad", tui = { kind = "claude" } } }, "tui.kind", "unimplemented Claude backend")
refused({ { name = "bad", label = "Bad", acp = { adapter = "codex" } } }, "acp needs", "ACP needs an executable")
refused({ { name = "bad", label = "Bad", api = { adapter = "openai", api_key = "OPENAI_API_KEY" } } }, "NVIM_", "API profile cannot consume CLI billing variable")
refused({ fixture[1], { name = "dup", label = "Duplicate", api = { adapter = "openai", api_key = "NVIM_OTHER" } } }, "used twice", "duplicate API adapter needs a distinct profile name")
local model = vim.deepcopy(fixture[2]); model.api.model = "offline-fixture-model"
t.eq(state.build({ model }).key_profiles.work.model, "offline-fixture-model", "profile can pin its own model")
-- Setup CodeCompanion, without constructing a chat or sending any request.
require("codecompanion")
vim.cmd("AI key work")
local cc = require("codecompanion.config")
t.eq(cc.interactions.inline.adapter, "work", "live inline adapter follows key switch")
t.eq(cc.interactions.cmd.adapter, "work", "live command adapter follows key switch")
t.eq(cc.interactions.chat.adapter, "codex", "existing/default chat adapter is independent of HTTP profile")
t.eq(agent.sessions(), before, "loading/syncing optional Companion creates no native session")
local native_only = vim.deepcopy(fixture[1]); native_only.api, native_only.acp = nil, nil
state._set_providers({ native_only })
agent.apply_keymaps()
t.eq(state.key.name, nil, "native-only configurations have no HTTP key")
t.eq(require("agent_workbench.companion").inline_keys(), "<Ignore>", "inline edit refuses cleanly with no API profile")
state._set_providers(original)
state.use_key(original_key)
for name, value in pairs(saved) do vim.env[name] = value or nil end
agent.apply_keymaps()
vim.notify = notify
t.done()
