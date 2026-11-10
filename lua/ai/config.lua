-- Two independent axes of AI state, both switchable in-process (lua/ai/switch.lua):
--
--   provider     which agent CLI backs the native terminal and CodeCompanion's
--                ACP chat. Billed to the subscription login.
--   key profile  which HTTP adapter and NVIM_* key CodeCompanion's inline and
--                command prompts use. Billed to API credits. `auto` follows the
--                provider (claude -> anthropic, codex -> openai).
--
-- Startup defaults: NVIM_AI_PROVIDER > vim.g.ai_provider > claude, and
-- NVIM_AI_KEY_PROFILE > vim.g.ai_key_profile > auto. Nothing is persisted.
--
-- Every consumer holds this one table and reads it per call, so switching
-- mutates it in place rather than handing out a new one.

local selected = (vim.env.NVIM_AI_PROVIDER or vim.g.ai_provider or "claude"):lower()

local providers = {
  claude = {
    label = "Claude Code",
    native = {
      command = "claude",
      -- The temp file Claude hands to $EDITOR (scripts/agent-editor), which is
      -- how a prompt float knows whose prompt it is.
      prompt_pattern = "claude%-prompt%-[^/]*%.md$",
      capabilities = {
        continue = true,
        diff = true,
        model = true,
        tree_add = true,
      },
    },
    codecompanion = {
      acp_adapter = "claude_code",
      acp_command = "claude-agent-acp",
    },
    -- What the `auto` key profile resolves to under this provider.
    key_profile = "anthropic",
    -- The variable the CLI itself bills against, checked by :checkhealth config.
    cli_api_key = "ANTHROPIC_API_KEY",
  },
  codex = {
    label = "Codex",
    native = {
      command = "codex",
      prompt_pattern = "/editor/[^/]*%.md$", -- $CODEX_HOME/editor/*.md
      capabilities = {
        continue = true,
        diff = false,
        model = true,
        tree_add = false,
      },
    },
    codecompanion = {
      acp_adapter = "codex",
      acp_command = "codex-acp",
    },
    key_profile = "openai",
    cli_api_key = "OPENAI_API_KEY",
  },
}

-- HTTP key profiles. The table key is the CodeCompanion adapter name, so a chat
-- that codecompanion-history restores finds its adapter again by that name.
--
-- api_key is always a variable of our own. Claude Code and claude-agent-acp
-- prefer ANTHROPIC_API_KEY over the subscription login, and Codex and codex-acp
-- can use OPENAI_API_KEY in place of the ChatGPT login, so exporting either one
-- for CodeCompanion would bill every agent started from here to the API.
local key_profiles = {
  anthropic = { adapter = "anthropic", label = "Anthropic", api_key = "NVIM_ANTHROPIC_API_KEY" },
  -- CodeCompanion 20 folded openai_responses into openai, which is the
  -- Responses API now; the old name no longer resolves.
  openai = { adapter = "openai", label = "OpenAI", api_key = "NVIM_OPENAI_API_KEY" },
  -- A second key for the same API is one more entry, under a name of its own:
  -- anthropic_work = { adapter = "anthropic", label = "Anthropic (work)",
  --                    api_key = "NVIM_ANTHROPIC_API_KEY_WORK", model = "claude-sonnet-5" },
}

-- Variables a CLI reads in place of its subscription login.
local CLI_KEYS = { ANTHROPIC_API_KEY = true, OPENAI_API_KEY = true, CLAUDE_CODE_OAUTH_TOKEN = true }

local M = {
  providers = providers,
  key_profiles = key_profiles,
  codecompanion = {},
  key = { auto = true },
}

---Refuse a key profile that would read a CLI's own billing variable. Raised at
---load, so a bad entry stops startup instead of reaching a request.
---@param name string
---@param profile { adapter: string, label: string, api_key: string, model?: string }
function M.check_key_profile(name, profile)
  local var = type(profile) == "table" and profile.api_key or nil
  if type(var) ~= "string" or CLI_KEYS[var] or not var:match("^NVIM_[%w_]+$") then
    error(("AI key profile %q must read an NVIM_* variable, not %s"):format(name, tostring(var)), 0)
  end
end

for name, profile in pairs(key_profiles) do
  M.check_key_profile(name, profile)
end
-- Both built-in adapters are always redirected to their NVIM_* variable,
-- whichever provider started the process (lua/plugin/lsp/codecompanion.lua).
assert(key_profiles.anthropic and key_profiles.openai, "the anthropic and openai key profiles are required")

if not providers[selected] then
  error(("Invalid NVIM_AI_PROVIDER=%q; expected 'claude' or 'codex'"):format(selected))
end

-- Shared geometry for every AI side panel: the native Claude/Codex terminals
-- and the CodeCompanion chat window. Width is in columns (absolute, not a
-- fraction) so the three panels stay interchangeable in the same layout.
M.panel = {
  width = 90,
}

local function sorted(t)
  local keys = vim.tbl_keys(t)
  table.sort(keys)
  return keys
end

---@return string[] every configured provider, sorted
function M.names() return sorted(providers) end
---@return string[] every key profile, sorted
function M.key_names() return sorted(key_profiles) end

function M.is(provider)
  return M.provider == provider
end

---Select the HTTP key profile. `auto` follows the provider; any other name pins
---it, so a later provider switch leaves the key alone. Validates before it
---mutates anything.
---@param name string
function M.use_key(name)
  name = (name or ""):lower()
  local auto = name == "auto"
  local id = auto and providers[M.provider].key_profile or name
  local profile = key_profiles[id]
  if not profile then
    error(("Unknown AI key profile %q; expected auto, %s"):format(name, table.concat(M.key_names(), ", ")), 0)
  end
  M.key.name, M.key.label, M.key.auto = id, profile.label, auto
  -- The adapter *name*, as before: a profile's name is its CodeCompanion adapter.
  M.codecompanion.http_adapter = id
  M.codecompanion.api_key = profile.api_key
  M.codecompanion.model = profile.model
end

---Select the provider. Validates before it mutates anything.
---@param name string
function M.use_provider(name)
  name = (name or ""):lower()
  local provider = providers[name]
  if not provider then
    error(("Unknown AI provider %q; expected %s"):format(name, table.concat(M.names(), ", ")), 0)
  end
  M.provider, M.label, M.native, M.cli_api_key = name, provider.label, provider.native, provider.cli_api_key
  M.codecompanion.acp_adapter = provider.codecompanion.acp_adapter
  M.codecompanion.acp_command = provider.codecompanion.acp_command
  if M.key.auto then M.use_key("auto") end
end

---The inline/cmd adapter as CodeCompanion takes it: a bare name, or name plus
---model when the profile pins one.
---@return string|{ name: string, model: string }
function M.http_adapter_spec()
  local c = M.codecompanion
  return c.model and { name = c.http_adapter, model = c.model } or c.http_adapter
end

---The key axis as a user spells it: "auto" or a profile name.
---@return string
function M.key_setting()
  return M.key.auto and "auto" or M.key.name
end

local function is_set(var) return (vim.env[var] or "") ~= "" end

---A way to start a chat, as the new-chat picker (lua/ai/slot.lua) offers it.
---@class ai.Backend
---@field id string "claude", "codex", "acp:<adapter>" or "api:<profile>"
---@field kind "native"|"acp"|"http"
---@field vendor string the provider it belongs to, which orders the list
---@field agent? string native: the provider
---@field adapter? string acp, http: the CodeCompanion adapter
---@field command? string native, acp: the executable it needs
---@field profile? string http: the key profile
---@field api_key? string http: the profile's NVIM_* variable
---@field model? string http: the profile's pinned model
---@field label string what it is, where it runs and who bills it
---@field available boolean whether it can start here
---@field why? string why it cannot
---@field warn? string a CLI billing variable that is set, so "subscription" may not hold

---Every way to start a chat, available or not: the native terminals, the ACP
---chats and one API chat per key profile, in that order, with `default`'s
---entry first in each group -- so the very first is its native terminal.
---Answering reads PATH and the environment only; it loads no plugin.
---@param default string? a provider; the active one when nil
---@return ai.Backend[]
function M.backends(default)
  default = default or M.provider
  -- Per group: the default's entries, then the others, each in listed order.
  local groups = {}
  for _, kind in ipairs({ "native", "acp", "http" }) do groups[kind] = { first = {}, rest = {} } end
  local function add(kind, entry)
    local list = entry.vendor == default and groups[kind].first or groups[kind].rest
    list[#list + 1] = entry
  end
  for _, name in ipairs(M.names()) do
    local p = providers[name]
    local warn = is_set(p.cli_api_key) and (p.cli_api_key .. " is set — it may bill the API") or nil
    local native_ok = vim.fn.executable(p.native.command) == 1
    add("native", {
      id = name, kind = "native", vendor = name, agent = name, command = p.native.command,
      label = p.label .. " · terminal · subscription",
      available = native_ok, why = not native_ok and (p.native.command .. " not found") or nil, warn = warn,
    })
    local acp = p.codecompanion
    local acp_ok = vim.fn.executable(acp.acp_command) == 1
    add("acp", {
      id = "acp:" .. acp.acp_adapter, kind = "acp", vendor = name, adapter = acp.acp_adapter, command = acp.acp_command,
      label = p.label .. " · CodeCompanion ACP · subscription",
      available = acp_ok, why = not acp_ok and (acp.acp_command .. " not found") or nil, warn = warn,
    })
  end
  for _, name in ipairs(M.key_names()) do
    local kp = key_profiles[name]
    local vendor
    for _, pname in ipairs(M.names()) do
      if key_profiles[providers[pname].key_profile].adapter == kp.adapter then vendor = pname end
    end
    local ok = is_set(kp.api_key)
    add("http", {
      id = "api:" .. name, kind = "http", vendor = vendor or "", adapter = name, profile = name,
      api_key = kp.api_key, model = kp.model,
      label = kp.label .. " · CodeCompanion API · API credits",
      available = ok, why = not ok and (kp.api_key .. " is not set") or nil,
    })
  end
  local all = {}
  for _, kind in ipairs({ "native", "acp", "http" }) do
    vim.list_extend(all, groups[kind].first)
    vim.list_extend(all, groups[kind].rest)
  end
  return all
end

M.use_provider(selected)
local key_default = vim.env.NVIM_AI_KEY_PROFILE or vim.g.ai_key_profile
-- A typo in this optional knob falls back to auto instead of aborting startup.
if key_default and key_default ~= "" and not pcall(M.use_key, key_default) then
  vim.schedule(function()
    vim.notify(("NVIM_AI_KEY_PROFILE=%q is not a key profile; using auto"):format(key_default), vim.log.levels.WARN)
  end)
end
M.startup = { provider = M.provider, key = M.key_setting() }

---Has either axis moved since startup?
---@return boolean
function M.switched()
  return M.provider ~= M.startup.provider or M.key_setting() ~= M.startup.key
end

-- The directory an agent session belongs to. Shared because three callers need
-- the same answer: the backend picks the terminal's cwd, the selection helper
-- makes paths relative to it, and the transcript adapters use it to find which
-- recorded sessions belong to this project.
---@param path string? a file path; "" or nil means "use the working directory"
---@return string
function M.project_root(path)
  local start = (path and path ~= "") and vim.fs.dirname(path)
    or (vim.uv.cwd() or vim.fn.getcwd())
  return vim.fs.root(start, ".git") or vim.uv.cwd() or vim.fn.getcwd()
end

---Which configured agent a terminal command runs, if any. Every CLI counts, not
---only the active one: after a switch both agents can be running at once, and
---each panel keeps its own input rules, edgy slot and statusline label.
---@param cmd string|string[]|nil
---@return string|nil provider
function M.provider_of_command(cmd)
  if type(cmd) == "table" then
    for _, part in ipairs(cmd) do
      local provider = M.provider_of_command(tostring(part))
      if provider then return provider end
    end
    return nil
  end
  if type(cmd) ~= "string" then return nil end
  for token in cmd:gmatch("[^%s]+") do
    local base = vim.fs.basename((token:gsub("^[\"']+", ""):gsub("[\"';]+$", "")))
    for _, name in ipairs(M.names()) do
      if base == providers[name].native.command then return name end
    end
  end
  return nil
end

function M.is_native_command(cmd)
  return M.provider_of_command(cmd) ~= nil
end

---Which agent handed over a prompt file, from the temp path its CLI chose;
---nil for a path neither CLI uses (an agent's pane running `git commit`, say).
---Such a prompt has no owner: it takes no seed and attaches no image, since
---either would go to an agent guessed at.
---@param path string
---@return string|nil provider
function M.provider_of_prompt(path)
  for _, name in ipairs(M.names()) do
    if type(path) == "string" and path:find(providers[name].native.prompt_pattern) then return name end
  end
  return nil
end

return M
