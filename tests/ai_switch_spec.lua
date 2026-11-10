-- :AI switches the provider and the HTTP key profile in-process
-- (lua/ai/switch.lua over the state in lua/ai/config.lua).
--
-- What is pinned here: a switch changes state, mapping descriptions and
-- CodeCompanion's live defaults and nothing else; `auto` keys follow the
-- provider until a key is pinned; an invalid name changes nothing; a switch
-- loads no plugin; and switching to a provider leaves this Nvim exactly as one
-- started with it. No agent CLI is started and no request is sent.
local t = dofile("tests/helper.lua")

local config = require("ai.config")
local switch = require("ai.switch")
local Config = require("lazy.core.config")
local ERROR, WARN = vim.log.levels.ERROR, vim.log.levels.WARN

local notes = {}
local real_notify = vim.notify
vim.notify = function(msg, level) notes[#notes + 1] = { msg = tostring(msg), level = level or vim.log.levels.INFO } end
local function last() return notes[#notes] or { msg = "", level = -1 } end

local events = {}
vim.api.nvim_create_autocmd("User", {
  pattern = "AIStateChanged",
  callback = function(ev) events[#events + 1] = ev.data end,
})

-- Start from `auto`, whatever the shell exported, so the expectations below
-- can be written relative to the provider alone.
if not config.key.auto then config.use_key("auto") end

local start = config.provider
local other = start == "claude" and "codex" or "claude"
local function label(p) return config.providers[p].label end
local function desc(lhs, mode) return vim.fn.maparg(lhs, mode or "n", false, true).desc end
local function loaded(name)
  local plugin = Config.plugins[name]
  return plugin ~= nil and plugin._.loaded ~= nil
end
local function state()
  return {
    provider = config.provider, label = config.label, native = config.native.command,
    cli_api_key = config.cli_api_key, key = vim.deepcopy(config.key),
    codecompanion = vim.deepcopy(config.codecompanion),
  }
end

---Run `probe` in a fresh Nvim under `env` and decode the JSON it writes.
local function child(env, probe)
  local result = vim.system({
    vim.v.progpath, "--headless", "-u", "init.lua", "-i", "NONE",
    -- Before init.lua, so a notification scheduled during startup is caught.
    "--cmd", "lua _G.spec_notes = {} vim.notify = function(m, l) table.insert(_G.spec_notes, { msg = tostring(m), level = l }) end",
    "-c", "lua " .. probe:gsub("\n", " "),
  }, { env = vim.tbl_extend("force", { NVIM_AI_KEY_PROFILE = "" }, env), text = true }):wait(30000)
  local ok, decoded = pcall(vim.json.decode, (result.stdout or ""):match("{.*}") or "")
  return ok and decoded or { error = (result.stdout or "") .. (result.stderr or "") }
end

---------------------------------------------------------------------------
-- The command
---------------------------------------------------------------------------

t.eq(vim.fn.getcompletion("AI ", "cmdline"), { "provider", "key", "info", "new", "chats" }, ":AI completes its subcommands")
t.eq(vim.fn.getcompletion("AI provider ", "cmdline"), { "claude", "codex" }, ":AI provider completes provider names")
t.eq(vim.fn.getcompletion("AI key ", "cmdline"), { "auto", "anthropic", "openai" },
  ":AI key completes auto and every profile")
t.eq(vim.fn.getcompletion("AI key o", "cmdline"), { "openai" }, "completion filters on what is typed")
t.eq(vim.fn.getcompletion("AI provider codex ", "cmdline"), {}, "nothing completes after a name")
t.eq(vim.fn.exists(":AIInfo"), 2, ":AIInfo is kept as an alias")

t.eq(desc(" ax"), "Switch AI provider / API key", "<leader>ax opens the switcher")
t.eq(config.startup.provider, start, "the startup provider is recorded")

-- Invalid input changes nothing and says so once.
local before = state()
vim.cmd("AI provider nope")
t.eq(last().level, ERROR, "an unknown provider is an error")
t.ok(last().msg:find("Unknown AI provider", 1, true) ~= nil, "naming what was wrong")
vim.cmd("AI key nope")
t.ok(last().level == ERROR and last().msg:find("Unknown AI key profile", 1, true) ~= nil,
  "an unknown key profile is an error too")
vim.cmd("AI bogus")
t.ok(last().level == ERROR and last().msg:find("Usage", 1, true) ~= nil, "an unknown subcommand prints usage")
vim.cmd("AI provider " .. start)
t.ok(last().level ~= ERROR and last().msg:find("already", 1, true) ~= nil, "the current provider only reports itself")
t.eq(state(), before, "none of that changed the state")
t.eq(#events, 0, "and none of it announced a change")

-- :AI info reads both agents' state without loading either plugin for it.
notes = {}
vim.cmd("AI info")
t.ok(last().msg:find("Provider", 1, true) ~= nil and last().msg:find(label(start), 1, true) ~= nil,
  ":AI info summarises the provider")
t.ok(last().msg:find("NVIM_ANTHROPIC_API_KEY", 1, true) and last().msg:find("NVIM_OPENAI_API_KEY", 1, true),
  "and every key profile's variable")
t.ok(last().msg:find("Agents", 1, true) ~= nil, "and both native agents")
vim.cmd("AIInfo")
t.ok(last().msg:find("Provider", 1, true) ~= nil, ":AIInfo prints the same summary")
t.ok(not loaded("claudecode.nvim") and not loaded("codecompanion.nvim"), ":AI info loads no AI plugin")

---------------------------------------------------------------------------
-- Switching the provider
---------------------------------------------------------------------------

-- The note names an old agent that is still running; nothing stops it.
local old_backend = require("ai.backend." .. start)
local real_running = old_backend.running
old_backend.running = function() return true end
notes = {}
vim.cmd("AI provider " .. other)
old_backend.running = real_running

t.eq(config.provider, other, ":AI provider switches the provider")
t.eq(events[#events], { axis = "provider", from = start, to = other }, "User AIStateChanged reports the switch")
t.ok(last().msg:find(label(other), 1, true) ~= nil, "the notification names the new provider")
t.ok(last().msg:find(label(start) .. " keeps running", 1, true) ~= nil,
  "and says the old agent keeps running")
t.ok(not loaded("claudecode.nvim"), "switching loads no plugin")

for _, lhs in ipairs({ " at", " aT" }) do
  local d = desc(lhs) or ""
  t.ok(d:find(label(other), 1, true) ~= nil and d:find(label(start), 1, true) == nil,
    ("<leader>%s now names %s (%s)"):format(lhs:sub(2), label(other), d))
end
-- The chat keys act on the chat on the right (lua/ai/slot.lua), not on the
-- provider, so a switch leaves them as they were: they name no agent.
for _, lhs in ipairs({ " an", " al", " ac", " af", " ar", " aR", " am", " ab", " ai" }) do
  local d = desc(lhs) or ""
  t.ok(d ~= "" and d:find(label(other), 1, true) == nil and d:find(label(start), 1, true) == nil,
    ("<leader>%s names no agent (%s)"):format(lhs:sub(2), d))
end
t.eq({ desc(" as", "x"), desc(" ai", "x") }, { "Add selection to AI chat", "Edit prompt for AI chat" },
  "and neither do Visual <leader>as and <leader>ai")
-- A review round belongs to a conversation, not to the active provider: the
-- review keys are re-applied with the rest and keep naming no agent.
t.eq({ desc(" av"), desc(" aV") }, { "Review changes since round baseline", "Start a review round" },
  "<leader>av/aV survive the switch unchanged")

-- Diffs are Claude's: the keys exist while Claude is active, or once
-- claudecode.nvim is loaded and a diff could still come from it.
local function has(lhs) return next(vim.fn.maparg(lhs, "n", false, true)) ~= nil end
t.eq(has(" aa") and has(" ad"), config.is("claude") or package.loaded["claudecode"] ~= nil,
  "<leader>aa/ad exist exactly while a Claude diff can arrive")
if config.is("claude") then
  t.eq(desc(" aa"), "Accept Claude diff", "<leader>aa says whose diff it answers")
end

-- Switching to a provider leaves this Nvim as one started with it would be.
local fresh = child({ NVIM_AI_PROVIDER = other }, [[
  local c = require("ai.config")
  local keys = {}
  for _, k in ipairs({ " ac", " af", " ar", " aR", " ab", " ai", " at", " aT", " aa", " ad", " ax", " ag", " aG", " ah", " aH", " ae", " av", " aV" }) do
    keys[k] = vim.fn.maparg(k, "n", false, true).desc or vim.NIL
  end
  io.stdout:write(vim.json.encode({
    provider = c.provider, label = c.label, native = c.native.command, cli_api_key = c.cli_api_key,
    key = c.key, codecompanion = c.codecompanion, keys = keys,
  }))
  vim.cmd("qa!")
]])
local here = state()
here.keys = {}
for _, k in ipairs({ " ac", " af", " ar", " aR", " ab", " ai", " at", " aT", " aa", " ad", " ax", " ag", " aG", " ah", " aH", " ae", " av", " aV" }) do
  here.keys[k] = desc(k) or vim.NIL
end
t.eq(here, fresh, ("after :AI provider %s this Nvim matches one started with NVIM_AI_PROVIDER=%s"):format(other, other))

vim.cmd("AI provider " .. start)
t.eq(config.provider, start, "and switching back restores the provider")
t.ok((desc(" at") or ""):find(label(start), 1, true) ~= nil, "with its labels")
t.eq(has(" aa"), config.is("claude") or package.loaded["claudecode"] ~= nil, "and its diff keys")

---------------------------------------------------------------------------
-- The key axis: auto follows, a name pins
---------------------------------------------------------------------------

local follows = config.providers[start].key_profile
local pinned = follows == "anthropic" and "openai" or "anthropic"
t.eq(config.key.name, follows, "auto resolves to the provider's own key profile")

vim.cmd("AI key " .. pinned)
t.eq({ config.key.name, config.key.auto }, { pinned, false }, ":AI key <name> pins that profile")
t.eq(events[#events], { axis = "key", from = "auto", to = pinned }, "and announces it")
t.eq(config.codecompanion.api_key, config.key_profiles[pinned].api_key, "the HTTP key follows the profile")
vim.cmd("AI provider " .. other)
t.eq(config.key.name, pinned, "a pinned key survives a provider switch")
vim.cmd("AI provider " .. start)
vim.cmd("AI key auto")
t.eq({ config.key.name, config.key.auto }, { follows, true }, ":AI key auto follows the provider again")
vim.cmd("AI provider " .. other)
t.eq(config.key.name, config.providers[other].key_profile, "and then moves with it")
vim.cmd("AI provider " .. start)

-- An unset variable still switches, with a warning, because it is about which
-- key rather than whether one is exported yet.
local var = config.key_profiles[pinned].api_key
local saved_var = vim.env[var]
vim.env[var] = nil
notes = {}
vim.cmd("AI key " .. pinned)
t.eq(config.key.name, pinned, "a profile whose variable is unset is still selected")
t.ok(last().level == WARN and last().msg:find(var, 1, true) ~= nil, "with a warning naming the variable")
vim.env[var] = saved_var
vim.cmd("AI key auto")

-- A profile can pin a model; CodeCompanion then gets name and model together.
config.key_profiles.spec_pinned = { adapter = "anthropic", label = "Spec", api_key = "NVIM_SPEC_KEY", model = "spec-model" }
config.use_key("spec_pinned")
t.eq(config.http_adapter_spec(), { name = "spec_pinned", model = "spec-model" }, "a model-pinned profile resolves with its model")
config.use_key("auto")
config.key_profiles.spec_pinned = nil
t.eq(config.http_adapter_spec(), follows, "an unpinned profile is its bare adapter name")

-- The billing guard: a profile may only read an NVIM_* variable.
for _, bad in ipairs({ "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN", "MY_KEY" }) do
  t.ok(not pcall(config.check_key_profile, "x", { adapter = "openai", label = "x", api_key = bad }),
    "a profile reading " .. bad .. " is refused")
end
t.ok(pcall(config.check_key_profile, "x", { adapter = "openai", label = "x", api_key = "NVIM_X_KEY" }),
  "an NVIM_* variable is accepted")

-- NVIM_AI_KEY_PROFILE sets the startup key; a typo falls back to auto.
local pinned_start = child({ NVIM_AI_PROVIDER = start, NVIM_AI_KEY_PROFILE = pinned }, [[
  local c = require("ai.config")
  io.stdout:write(vim.json.encode({ name = c.key.name, auto = c.key.auto, startup = c.startup.key }))
  vim.cmd("qa!")
]])
t.eq(pinned_start, { name = pinned, auto = false, startup = pinned }, "NVIM_AI_KEY_PROFILE pins the startup key")
local typo = child({ NVIM_AI_PROVIDER = start, NVIM_AI_KEY_PROFILE = "anthropik" }, [[
  vim.wait(100, function() return #_G.spec_notes > 0 end)
  local c = require("ai.config")
  io.stdout:write(vim.json.encode({ name = c.key.name, auto = c.key.auto, notes = _G.spec_notes }))
  vim.cmd("qa!")
]])
t.ok(typo.name == follows and typo.auto == true, "a mistyped NVIM_AI_KEY_PROFILE starts on auto")
t.ok(typo.notes and typo.notes[1] and typo.notes[1].level == WARN
  and typo.notes[1].msg:find("anthropik", 1, true) ~= nil, "and says so instead of aborting startup")

---------------------------------------------------------------------------
-- The switcher
---------------------------------------------------------------------------

local real_select = vim.ui.select
local offered, chosen_format
vim.ui.select = function(items, opts, on_choice)
  offered, chosen_format = items, opts.format_item
  on_choice(vim.iter(items):find(function(i) return i.axis == "provider" and i.name == other end))
end
vim.fn.maparg(" ax", "n", false, true).callback()
vim.ui.select = real_select
t.eq(#offered, #config.names() + 1 + #config.key_names(), "the switcher lists both providers, auto and every profile")
local current_rows = vim.tbl_filter(function(i) return i.current end, offered)
t.eq(#current_rows, 2, "with one current entry per axis")
t.ok(chosen_format(current_rows[1]):find("●", 1, true) ~= nil, "marked ●")
t.eq(config.provider, other, "choosing a provider there switches to it")
vim.cmd("AI provider " .. start)

---------------------------------------------------------------------------
-- oil's <leader>aS follows the provider's tree-add capability
---------------------------------------------------------------------------

local oil_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_call(oil_buf, function() vim.cmd("noautocmd setlocal filetype=oil") end)
local function oil_has_tree_add()
  return vim.api.nvim_buf_call(oil_buf, function()
    local m = vim.fn.maparg(" aS", "n", false, true)
    return next(m) ~= nil and m.buffer == 1
  end)
end
require("ai").apply_keymaps()
t.eq(oil_has_tree_add(), config.native.capabilities.tree_add, "<leader>aS exists in oil only with tree-add")
vim.cmd("AI provider " .. other)
t.eq(oil_has_tree_add(), config.native.capabilities.tree_add, "and is added or removed by a switch")
vim.cmd("AI provider " .. start)
vim.api.nvim_buf_delete(oil_buf, { force = true })

---------------------------------------------------------------------------
-- CodeCompanion: loaded on the current state, then kept in step live
---------------------------------------------------------------------------

t.ok(not loaded("codecompanion.nvim"), "CodeCompanion is not loaded yet")
vim.cmd("AI key " .. pinned)
require("lazy").load({ plugins = { "codecompanion.nvim" } })
local cc = require("codecompanion.config")
t.eq(cc.interactions.inline.adapter, pinned, "a key switched before CodeCompanion loads reaches its inline adapter")
t.eq(cc.interactions.cmd.adapter, pinned, "and its command adapter")
t.eq(cc.interactions.chat.adapter, config.providers[start].codecompanion.acp_adapter, "chat starts on the provider's ACP adapter")

vim.cmd("AI provider " .. other)
t.eq(cc.interactions.chat.adapter, config.providers[other].codecompanion.acp_adapter,
  "after loading, a provider switch moves new chats to the other ACP agent")
t.eq(cc.interactions.inline.adapter, pinned, "while the pinned key stays put")
vim.cmd("AI key auto")
t.eq(cc.interactions.inline.adapter, config.providers[other].key_profile, "and auto takes the key along")
t.eq(cc.interactions.cmd.adapter, config.providers[other].key_profile, "for command prompts too")
t.eq(require("codecompanion.adapters").resolve(cc.interactions.inline.adapter).name, config.key.name,
  "the live inline adapter resolves")
t.eq(vim.g.codecompanion_adapter, nil, "vim.g.codecompanion_adapter is never set")
vim.cmd("AI provider " .. start)
t.eq(cc.interactions.chat.adapter, config.providers[start].codecompanion.acp_adapter, "switching back follows too")

---------------------------------------------------------------------------
-- The statusline names a switched state, and only that
---------------------------------------------------------------------------

-- Back where this Nvim started, whatever the shell pinned.
vim.cmd("AI provider " .. config.startup.provider)
vim.cmd("AI key " .. config.startup.key)

local ICON = "󰚩"
local function indicator() return ("%s %s · 󰌆 %s"):format(ICON, config.label, config.key.label) end
---Wait until the rendered statusline does (or does not) carry `text`.
local function statusline_has(text, want)
  local line = ""
  vim.wait(3000, function()
    require("lualine").refresh({ place = { "statusline" }, force = true })
    line = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = 400 }).str
    return (line:find(text, 1, true) ~= nil) == want
  end, 50)
  return (line:find(text, 1, true) ~= nil) == want, vim.trim((line:gsub("%s+", " ")))
end

t.eq(config.switched(), false, "in the startup state nothing has switched")
local ok_line, line = statusline_has(ICON, false)
t.ok(ok_line, "and the statusline shows no AI indicator: " .. line)

vim.cmd("AI provider " .. other)
t.eq(config.switched(), true, "a provider switch counts as switched")
ok_line, line = statusline_has(indicator(), true)
t.ok(ok_line, ("the statusline names the agent and key (%s): %s"):format(indicator(), line))
vim.cmd("AI provider " .. config.startup.provider)
t.eq(config.switched(), false, "switching back to the startup provider is not")
ok_line, line = statusline_has(ICON, false)
t.ok(ok_line, "and the indicator goes away: " .. line)

-- Any pinned name differs from `auto`, and from another pinned name.
local moved_key = config.startup.key ~= pinned and pinned or follows
vim.cmd("AI key " .. moved_key)
t.eq(config.switched(), true, "a key switch counts as switched")
ok_line, line = statusline_has(indicator(), true)
t.ok(ok_line, ("the statusline names the new key (%s): %s"):format(indicator(), line))
vim.cmd("AI key " .. config.startup.key)
t.eq(config.switched(), false, "and back at the startup key it is not")
ok_line, line = statusline_has(ICON, false)
t.ok(ok_line, "with the indicator gone again: " .. line)
vim.cmd("AI key auto")

-- An agent terminal is labelled by the agent it runs, not by the active
-- provider; anything else keeps its own name or title.
local filename_fmt
for _, component in ipairs(require("lualine").get_config().sections.lualine_c) do
  if type(component) == "table" and component[1] == "filename" then filename_fmt = component.fmt end
end
t.ok(type(filename_fmt) == "function", "the filename component formats terminal names")
if filename_fmt then
  t.eq(filename_fmt("init.lua"), "init.lua", "a file keeps its name")
  vim.cmd("enew")
  local term_buf = vim.api.nvim_get_current_buf()
  local job = vim.fn.jobstart({ "cat" }, { term = true })
  local commands = {
    claude = Config.spec.plugins["claudecode.nvim"].opts.terminal_cmd,
    codex = { "codex", "--no-alt-screen", "--yolo" },
  }
  for _, agent in ipairs({ start, other }) do
    vim.b.snacks_terminal = { cmd = commands[agent] }
    local shown = filename_fmt("term://whatever")
    local rival = agent == "claude" and "codex" or "claude"
    t.ok(vim.endswith(shown, " " .. label(agent)) and not shown:find(label(rival), 1, true),
      ("a %s terminal reads %s while %s is active (%q)"):format(agent, label(agent), label(config.provider), shown))
  end
  vim.b.snacks_terminal = { cmd = { vim.o.shell } }
  vim.b.term_title = "spec-title"
  t.ok(vim.endswith(filename_fmt("term://whatever"), " spec-title"), "a shell shows its terminal title")
  vim.fn.jobstop(job)
  vim.api.nvim_buf_delete(term_buf, { force = true })
end

---------------------------------------------------------------------------
-- Ownership by path and by command
---------------------------------------------------------------------------

t.eq(config.provider_of_prompt("/tmp/claude-501/claude-prompt-1a2b-3c4d.md"), "claude", "a claude-prompt-*.md is Claude's")
t.eq(config.provider_of_prompt(vim.env.HOME .. "/.codex/editor/0193.md"), "codex", "an editor/*.md under CODEX_HOME is Codex's")
t.eq(config.provider_of_prompt("/tmp/somewhere/else.md"), nil, "anything else belongs to no agent")

t.eq(config.provider_of_command({ "codex", "--no-alt-screen", "--yolo" }), "codex", "a Codex command is recognised")
t.eq(config.provider_of_command(Config.spec.plugins["claudecode.nvim"].opts.terminal_cmd), "claude",
  "the Claude wrapper command is recognised")
t.eq(config.provider_of_command({ "tmux", "-L", "claude-nvim-1", "-L", "codex-nvim-1" }), nil,
  "a socket name is not an agent")
t.eq(config.provider_of_command({ vim.o.shell }), nil, "a shell is no agent")
t.ok(config.is_native_command({ "claude" }) and config.is_native_command({ "codex" }),
  "is_native_command recognises every configured agent")

---------------------------------------------------------------------------
-- claudecode.nvim is declared, lazily, under both providers
---------------------------------------------------------------------------

local function declared_probe(switch_to)
  return ([[
    local Config = require("lazy.core.config")
    local plugin = Config.plugins["claudecode.nvim"]
    local before = plugin ~= nil and plugin._.loaded ~= nil
    vim.cmd("AI provider %s")
    io.stdout:write(vim.json.encode({
      declared = plugin ~= nil, lazy = plugin ~= nil and plugin.lazy == true,
      opts_table = type((Config.spec.plugins["claudecode.nvim"] or {}).opts) == "table",
      loaded_before = before, loaded_after = plugin ~= nil and plugin._.loaded ~= nil,
      to_clean = #Config.to_clean, stub = vim.fn.exists(":ClaudeCode"),
    }))
    vim.cmd("qa!")
  ]]):format(switch_to)
end
local want = { declared = true, lazy = true, opts_table = true, loaded_before = false, loaded_after = false,
  to_clean = 0, stub = 2 }
for _, case in ipairs({ { "claude", "codex" }, { "codex", "claude" } }) do
  t.eq(child({ NVIM_AI_PROVIDER = case[1] }, declared_probe(case[2])), want,
    ("%s-started: claudecode is declared and lazy, nothing to clean, still unloaded after :AI provider %s")
      :format(case[1], case[2]))
end

vim.notify = real_notify
t.done()
