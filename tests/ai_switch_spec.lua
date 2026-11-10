-- The AI state (lua/ai/config.lua) and :AI (lua/ai/switch.lua): a default
-- backend fixed at startup, and an HTTP key profile :AI key switches.
--
-- What is pinned: the default comes from NVIM_AI_PROVIDER > vim.g.ai_provider
-- > claude and only decides defaults -- the pickers' first entry, the `auto`
-- key, CodeCompanion's chat adapter for its own paths, Claude's watchdog at
-- VimEnter -- never what a key is called or where it acts; nothing switches
-- it in-process (`:AI provider` is gone, and says where its job went); a key
-- switch changes state, <leader>ae's description and CodeCompanion's
-- inline/cmd adapters and nothing else, `auto` follows the default until a
-- key is pinned, an invalid name changes nothing, and nothing loads a plugin.
-- No agent CLI is started and no request is sent.
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
-- can be written relative to the default alone.
local start_key = config.key_setting()
if not config.key.auto then config.use_key("auto") end

local default = config.default
local other = default == "claude" and "codex" or "claude"
local function label(p) return config.providers[p].label end
local function desc(lhs, mode) return vim.fn.maparg(lhs, mode or "n", false, true).desc end
local function loaded(name)
  local plugin = Config.plugins[name]
  return plugin ~= nil and plugin._.loaded ~= nil
end
local function state()
  return { default = config.default, key = vim.deepcopy(config.key), codecompanion = vim.deepcopy(config.codecompanion) }
end

---Run `probe` in a fresh Nvim under `env` and decode the JSON it writes.
---@param pre? string a Vim command run before init.lua (--cmd)
local function child(env, probe, pre)
  local cmd = {
    vim.v.progpath, "--headless", "-u", "init.lua", "-i", "NONE",
    -- Before init.lua, so a notification scheduled during startup is caught.
    "--cmd", "lua _G.spec_notes = {} vim.notify = function(m, l) table.insert(_G.spec_notes, { msg = tostring(m), level = l }) end",
  }
  if pre then vim.list_extend(cmd, { "--cmd", pre }) end
  vim.list_extend(cmd, { "-c", "lua " .. probe:gsub("\n", " ") })
  local result = vim.system(cmd, { env = vim.tbl_extend("force", { NVIM_AI_KEY_PROFILE = "" }, env), text = true })
    :wait(30000)
  local ok, decoded = pcall(vim.json.decode, (result.stdout or ""):match("{.*}") or "")
  return ok and decoded or { error = (result.stdout or "") .. (result.stderr or ""), code = result.code }
end

-- Every <leader>a key a default could have touched, Normal mode, but
-- <leader>ae, which names the key profile -- and so the default's under auto.
local LHS = { " an", " al", " ac", " af", " ar", " aR", " am", " ab", " ai", " at", " aT", " av", " aV", " ax",
  " ap", " ao", " aa", " ad", " ag", " aG", " ah", " aH" }

---------------------------------------------------------------------------
-- The command
---------------------------------------------------------------------------

t.eq(vim.fn.getcompletion("AI ", "cmdline"), { "new", "key", "info" }, ":AI completes its subcommands")
t.eq(vim.fn.getcompletion("AI key ", "cmdline"), { "auto", "anthropic", "openai" },
  ":AI key completes auto and every profile")
t.eq(vim.fn.getcompletion("AI key o", "cmdline"), { "openai" }, "completion filters on what is typed")
t.eq(vim.fn.getcompletion("AI key openai ", "cmdline"), {}, "nothing completes after a name")
t.eq(vim.fn.exists(":AIInfo"), 2, ":AIInfo is kept as an alias")
t.eq(desc(" ax"), "Switch API key profile", "<leader>ax picks the API key profile")

-- Bare :AI is the switcher; with nothing open it is the new-chat picker.
local real_select = vim.ui.select
local prompts = {}
vim.ui.select = function(_, opts, on_choice)
  prompts[#prompts + 1] = opts.prompt
  on_choice(nil)
end
vim.cmd("AI")
vim.cmd("AI new")
vim.ui.select = real_select
t.eq(prompts, { "New AI chat", "New AI chat" }, ":AI asks which chat (none open: the new-chat picker), :AI new too")

-- Invalid input changes nothing and says so once.
local before = state()
for _, cmd in ipairs({ "AI provider", "AI provider " .. other, "AI provider nope" }) do
  notes = {}
  vim.cmd(cmd)
  t.ok(#notes == 1 and last().level == ERROR and last().msg:find(":AI new", 1, true) ~= nil
    and last().msg:find("startup", 1, true) ~= nil,
    (":%s is gone, and says where its job went: %s"):format(cmd, last().msg))
end
vim.cmd("AI key nope")
t.ok(last().level == ERROR and last().msg:find("Unknown AI key profile", 1, true) ~= nil,
  "an unknown key profile is an error")
vim.cmd("AI bogus")
t.ok(last().level == ERROR and last().msg:find("Usage", 1, true) ~= nil, "an unknown subcommand prints usage")
vim.cmd("AI key auto")
t.ok(last().level ~= ERROR and last().msg:find("already", 1, true) ~= nil, "the current key only reports itself")
t.eq(state(), before, "none of that changed the state")
t.eq(#events, 0, "and none of it announced a change")

-- :AI info: the default, the key, the chats -- loading nothing for them.
notes = {}
vim.cmd("AI info")
local info = last().msg
t.ok(info:find("Default", 1, true) ~= nil and info:find(label(default), 1, true) ~= nil,
  ":AI info names the default backend")
t.ok(info:find(config.default_source, 1, true) ~= nil, "and where it came from (" .. config.default_source .. ")")
t.ok(info:find("NVIM_ANTHROPIC_API_KEY", 1, true) and info:find("NVIM_OPENAI_API_KEY", 1, true),
  "and every key profile's variable")
t.ok(info:find("Chats     none open", 1, true) ~= nil, "and the open chats: none yet")
t.ok(info:find("Provider", 1, true) == nil, "with no provider line left")
vim.cmd("AIInfo")
t.eq(last().msg, info, ":AIInfo prints the same summary")
t.ok(not loaded("claudecode.nvim") and not loaded("codecompanion.nvim"), ":AI info loads no AI plugin")

---------------------------------------------------------------------------
-- The default backend: fixed at startup, deciding defaults only
---------------------------------------------------------------------------

t.ok(config.provider == nil and config.use_provider == nil and config.is == nil and config.switched == nil,
  "there is no active provider to read or switch")
t.eq(config.backends()[1].id, default, "the default's terminal is the new-chat picker's first entry")
t.eq(config.key.name, config.providers[default].key_profile, "auto resolves to the default's own key profile")
t.eq(config.codecompanion.acp_adapter, config.providers[default].codecompanion.acp_adapter,
  "and CodeCompanion's chat default is the default's ACP agent")

local probe = [[
  local c = require("ai.config")
  local keys = {}
  for _, k in ipairs(vim.json.decode(vim.env.SPEC_LHS)) do keys[k] = vim.fn.maparg(k, "n", false, true).desc or vim.NIL end
  local ok, watchdog = pcall(vim.api.nvim_get_autocmds, { group = "ClaudeTmuxWatchdog", event = "VimEnter" })
  io.stdout:write(vim.json.encode({
    default = c.default, source = c.default_source, key = c.key.name, acp = c.codecompanion.acp_adapter,
    first = c.backends()[1].id, keys = keys, watchdog = ok and #watchdog or 0,
    ae = vim.fn.maparg(" ae", "n", false, true).desc,
  }))
  vim.cmd("qa!")
]]
local lhs_json = vim.json.encode(LHS)
local started = {}
for _, case in ipairs({
  { env = { NVIM_AI_PROVIDER = "claude" }, default = "claude", source = "NVIM_AI_PROVIDER" },
  { env = { NVIM_AI_PROVIDER = "CODEX" }, default = "codex", source = "NVIM_AI_PROVIDER" },
  { env = { NVIM_AI_PROVIDER = "" }, pre = "let g:ai_provider = 'codex'", default = "codex", source = "vim.g.ai_provider" },
  { env = { NVIM_AI_PROVIDER = "" }, default = "claude", source = "built-in" },
}) do
  local got = child(vim.tbl_extend("force", case.env, { SPEC_LHS = lhs_json }), probe, case.pre)
  local what = ("%s (%s)"):format(case.default, case.source)
  t.eq({ got.default, got.source }, { case.default, case.source }, what .. ": the default and where it came from")
  t.eq({ got.first, got.key, got.acp }, { case.default, config.providers[case.default].key_profile,
    config.providers[case.default].codecompanion.acp_adapter }, what .. ": first entry, auto key and chat adapter follow")
  t.eq(got.watchdog, case.default == "claude" and 1 or 0,
    what .. ": Claude's watchdog waits for VimEnter only when Claude is the default")
  t.eq(got.ae, ("Inline edit · %s (HTTP)"):format(config.key_profiles[config.providers[case.default].key_profile].label),
    what .. ": <leader>ae names the key auto resolves to")
  started[case.default] = got.keys
end
local here = {}
for _, k in ipairs(LHS) do here[k] = desc(k) or vim.NIL end
t.eq(started.claude, started.codex, "every <leader>a key reads the same whichever agent is the default")
t.eq(here, started[default], "and the same as here")
for _, lhs in ipairs({ " ag", " aG", " ah", " aH", " aa", " ad" }) do
  t.eq(here[lhs], vim.NIL, "<leader>" .. lhs:sub(2) .. " is not mapped at startup")
end

local bad = vim.system({ vim.v.progpath, "--headless", "-u", "init.lua", "-i", "NONE", "+qa" },
  { env = { NVIM_AI_PROVIDER = "gemini" }, text = true }):wait(30000)
t.ok(((bad.stdout or "") .. (bad.stderr or "")):find('Invalid NVIM_AI_PROVIDER="gemini"', 1, true) ~= nil,
  "an unknown NVIM_AI_PROVIDER is an error at startup, naming it")

---------------------------------------------------------------------------
-- Claude's diff keys exist once claudecode.nvim has loaded
---------------------------------------------------------------------------

local function has(lhs) return next(vim.fn.maparg(lhs, "n", false, true)) ~= nil end
t.ok(not has(" aa") and not has(" ad"), "<leader>aa/ad do not exist before claudecode.nvim loads")
local real_cc = package.loaded["claudecode"]
package.loaded["claudecode"] = {}
require("ai").apply_keymaps()
t.ok(has(" aa") and has(" ad"), "and exist once it has, whichever agent is the default")
t.eq({ desc(" aa"), desc(" ad") }, { "Accept Claude diff", "Deny Claude diff" }, "naming whose diff they answer")
package.loaded["claudecode"] = real_cc
require("ai").apply_keymaps()
t.ok(not has(" aa"), "(gone again with the stand-in)")

---------------------------------------------------------------------------
-- The key profile: auto follows the default, a name pins
---------------------------------------------------------------------------

local follows = config.providers[default].key_profile
local pinned = follows == "anthropic" and "openai" or "anthropic"
t.eq(desc(" ae"), ("Inline edit · %s (HTTP)"):format(config.key_profiles[follows].label), "<leader>ae names the key")

notes = {}
vim.cmd("AI key " .. pinned)
t.eq({ config.key.name, config.key.auto }, { pinned, false }, ":AI key <name> pins that profile")
t.eq(events[#events], { axis = "key", from = "auto", to = pinned }, "and announces it")
t.eq(config.codecompanion.api_key, config.key_profiles[pinned].api_key, "the HTTP key follows the profile")
t.eq(desc(" ae"), ("Inline edit · %s (HTTP)"):format(config.key_profiles[pinned].label), "<leader>ae is relabelled")
t.eq(config.default, default, "the default backend stays where it was")
vim.cmd("AI key auto")
t.eq({ config.key.name, config.key.auto }, { follows, true }, ":AI key auto follows the default again")

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
for _, bad_var in ipairs({ "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN", "MY_KEY" }) do
  t.ok(not pcall(config.check_key_profile, "x", { adapter = "openai", label = "x", api_key = bad_var }),
    "a profile reading " .. bad_var .. " is refused")
end
t.ok(pcall(config.check_key_profile, "x", { adapter = "openai", label = "x", api_key = "NVIM_X_KEY" }),
  "an NVIM_* variable is accepted")

-- NVIM_AI_KEY_PROFILE sets the startup key; a typo falls back to auto.
local pinned_start = child({ NVIM_AI_PROVIDER = default, NVIM_AI_KEY_PROFILE = pinned }, [[
  local c = require("ai.config")
  io.stdout:write(vim.json.encode({ name = c.key.name, auto = c.key.auto }))
  vim.cmd("qa!")
]])
t.eq(pinned_start, { name = pinned, auto = false }, "NVIM_AI_KEY_PROFILE pins the startup key")
local typo = child({ NVIM_AI_PROVIDER = default, NVIM_AI_KEY_PROFILE = "anthropik" }, [[
  vim.wait(100, function() return #_G.spec_notes > 0 end)
  local c = require("ai.config")
  io.stdout:write(vim.json.encode({ name = c.key.name, auto = c.key.auto, notes = _G.spec_notes }))
  vim.cmd("qa!")
]])
t.ok(typo.name == follows and typo.auto == true, "a mistyped NVIM_AI_KEY_PROFILE starts on auto")
t.ok(typo.notes and typo.notes[1] and typo.notes[1].level == WARN
  and typo.notes[1].msg:find("anthropik", 1, true) ~= nil, "and says so instead of aborting startup")

---------------------------------------------------------------------------
-- The key picker
---------------------------------------------------------------------------

local offered, chosen_format
vim.ui.select = function(items, opts, on_choice)
  offered, chosen_format = items, opts.format_item
  on_choice(vim.iter(items):find(function(i) return i.name == pinned end))
end
vim.fn.maparg(" ax", "n", false, true).callback()
vim.ui.select = real_select
t.eq(#offered, 1 + #config.key_names(), "<leader>ax lists auto and every profile, nothing else")
t.eq(offered[1].name, "auto", "auto first")
t.ok(chosen_format(offered[1]):find("auto → " .. config.key_profiles[follows].label, 1, true) ~= nil,
  "saying what auto resolves to")
local current_rows = vim.tbl_filter(function(i) return i.current end, offered)
t.ok(#current_rows == 1 and current_rows[1].name == "auto" and chosen_format(current_rows[1]):find("●", 1, true) ~= nil,
  "with the current one marked ●")
t.eq(config.key.name, pinned, "choosing a profile there pins it")
vim.cmd("AI key auto")

---------------------------------------------------------------------------
-- oil's <leader>aS is in every listing, whichever agent is the default
---------------------------------------------------------------------------

-- Without oil.nvim's own FileType handling: apply_keymaps finds the buffer.
local oil_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_call(oil_buf, function() vim.cmd("noautocmd setlocal filetype=oil") end)
require("ai").apply_keymaps()
local tree_key = vim.api.nvim_buf_call(oil_buf, function() return vim.fn.maparg(" aS", "n", false, true) end)
t.ok(tree_key.buffer == 1 and tree_key.desc == "Add file under cursor to Claude Code",
  "<leader>aS is mapped in an oil buffer, naming Claude Code")
vim.api.nvim_buf_delete(oil_buf, { force = true })
local other_oil = child({ NVIM_AI_PROVIDER = other }, [[
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_call(buf, function() vim.cmd("noautocmd setlocal filetype=oil") end)
  require("ai").apply_keymaps()
  local m = vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(" aS", "n", false, true) end)
  io.stdout:write(vim.json.encode({ desc = m.desc or vim.NIL, buffer = m.buffer or vim.NIL }))
  vim.cmd("qa!")
]])
t.eq(other_oil, { desc = "Add file under cursor to Claude Code", buffer = 1 }, "and so it is with " .. other .. " the default")

---------------------------------------------------------------------------
-- CodeCompanion: loaded on the current key, then kept in step by :AI key
---------------------------------------------------------------------------

t.ok(not loaded("codecompanion.nvim"), "CodeCompanion is not loaded yet")
vim.cmd("AI key " .. pinned)
require("lazy").load({ plugins = { "codecompanion.nvim" } })
local cc = require("codecompanion.config")
t.eq(cc.interactions.inline.adapter, pinned, "a key pinned before CodeCompanion loads reaches its inline adapter")
t.eq(cc.interactions.cmd.adapter, pinned, "and its command adapter")
t.eq(cc.interactions.chat.adapter, config.providers[default].codecompanion.acp_adapter,
  "its chat adapter, for its own paths that name none, is the default's ACP agent")

vim.cmd("AI key auto")
t.eq(cc.interactions.inline.adapter, follows, "after loading, :AI key auto moves inline prompts back")
t.eq(cc.interactions.cmd.adapter, follows, "and command prompts")
t.eq(cc.interactions.chat.adapter, config.providers[default].codecompanion.acp_adapter, "and leaves the chat adapter alone")
t.eq(require("codecompanion.adapters").resolve(cc.interactions.inline.adapter).name, config.key.name,
  "the live inline adapter resolves")
t.eq(vim.g.codecompanion_adapter, nil, "vim.g.codecompanion_adapter is never set")

---------------------------------------------------------------------------
-- The statusline names a pinned key, and only that
---------------------------------------------------------------------------

local ICON = "󰌆"
local function indicator() return ("%s %s"):format(ICON, config.key.label) end
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

local ok_line, line = statusline_has(ICON, false)
t.ok(ok_line, "with the key on auto the statusline shows no key: " .. line)
t.ok(not line:find("󰚩", 1, true), "and no agent either: " .. line)
vim.cmd("AI key " .. pinned)
ok_line, line = statusline_has(indicator(), true)
t.ok(ok_line, ("a pinned key is named (%s): %s"):format(indicator(), line))
vim.cmd("AI key auto")
ok_line, line = statusline_has(ICON, false)
t.ok(ok_line, "and back on auto the indicator goes away: " .. line)

-- An agent terminal is labelled by the agent it runs, whichever is the
-- default; anything else keeps its own name or title.
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
  for _, agent in ipairs({ default, other }) do
    vim.b.snacks_terminal = { cmd = commands[agent] }
    local shown = filename_fmt("term://whatever")
    local rival = agent == "claude" and "codex" or "claude"
    t.ok(vim.endswith(shown, " " .. label(agent)) and not shown:find(label(rival), 1, true),
      ("a %s terminal reads %s with %s the default (%q)"):format(agent, label(agent), label(default), shown))
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
-- claudecode.nvim is declared, lazily, whichever agent is the default
---------------------------------------------------------------------------

local declared_probe = [[
  local Config = require("lazy.core.config")
  local plugin = Config.plugins["claudecode.nvim"]
  io.stdout:write(vim.json.encode({
    declared = plugin ~= nil, lazy = plugin ~= nil and plugin.lazy == true,
    opts_table = type((Config.spec.plugins["claudecode.nvim"] or {}).opts) == "table",
    loaded = plugin ~= nil and plugin._.loaded ~= nil,
    to_clean = #Config.to_clean, stub = vim.fn.exists(":ClaudeCode"), open = vim.fn.exists(":ClaudeCodeOpen"),
  }))
  vim.cmd("qa!")
]]
local want = { declared = true, lazy = true, opts_table = true, loaded = false, to_clean = 0, stub = 2, open = 2 }
for _, name in ipairs({ "claude", "codex" }) do
  t.eq(child({ NVIM_AI_PROVIDER = name }, declared_probe), want,
    ("%s the default: claudecode is declared and lazy, nothing to clean, unloaded, :ClaudeCodeOpen a trigger")
      :format(name))
end

if start_key ~= "auto" then config.use_key(start_key) end
vim.notify = real_notify
t.done()
