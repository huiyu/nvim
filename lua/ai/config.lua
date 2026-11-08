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

---Which agent handed over a prompt file, from the temp path its CLI chose.
---Falls back to the active provider, which is what every prompt meant before
---switching existed.
---@param path string
---@return string provider
function M.provider_of_prompt(path)
  for _, name in ipairs(M.names()) do
    if type(path) == "string" and path:find(providers[name].native.prompt_pattern) then return name end
  end
  return M.provider
end

return M
