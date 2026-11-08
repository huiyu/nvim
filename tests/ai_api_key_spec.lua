-- CodeCompanion's HTTP adapters read keys of their own (NVIM_ANTHROPIC_API_KEY /
-- NVIM_OPENAI_API_KEY, lua/ai/config.lua), never the variables the agent CLIs
-- bill against: exporting ANTHROPIC_API_KEY or OPENAI_API_KEY for Nvim's sake
-- would move Claude Code or Codex off the subscription.
--
-- Either key profile can be active after :AI key, and either provider after
-- :AI provider, so BOTH HTTP adapters are checked under BOTH startup providers,
-- each in a fresh child Nvim -- plus the Codex ACP adapter, which must stay on
-- the ChatGPT login whichever provider started the process.
local t = dofile("tests/helper.lua")

-- Resolve every adapter the way CodeCompanion does before a request, under the
-- given environment, in a fresh Nvim. A custom profile is registered before
-- the plugin loads, the way an entry added to config.lua would be.
local function resolve(env)
  local probe = [[
    local ai = require("ai.config")
    ai.key_profiles.spec_work = { adapter = "anthropic", label = "Spec work", api_key = "NVIM_SPEC_WORK_KEY" }
    require("lazy").load({ plugins = { "codecompanion.nvim" } })
    local adapters = require("codecompanion.adapters")
    local utils = require("codecompanion.adapters.utils")
    local out = {}
    for _, name in ipairs({ "anthropic", "openai", "spec_work" }) do
      local ok, adapter = pcall(adapters.resolve, name)
      local key
      if ok and adapter then key = utils.get_env_vars(adapter).env_replaced.api_key end
      out[name] = { name = ok and adapter and adapter.name or vim.NIL, type = ok and adapter and adapter.type or vim.NIL,
        key = key or vim.NIL }
    end
    local ok, codex = pcall(adapters.resolve, "codex")
    out.codex_auth = ok and codex and codex.defaults and codex.defaults.auth_method or vim.NIL
    out.codecompanion_adapter = vim.g.codecompanion_adapter or vim.NIL
    io.stdout:write(vim.json.encode(out))
    vim.cmd("qa!")
  ]]
  local result = vim.system({ vim.v.progpath, "--headless", "-u", "init.lua", "-i", "NONE", "-c", "lua " .. probe:gsub("\n", " ") },
    { env = env, text = true }):wait(30000)
  local ok, decoded = pcall(vim.json.decode, (result.stdout or ""):match("{.*}") or "")
  return ok and decoded or { error = (result.stdout or "") .. (result.stderr or "") }
end

local adapters = {
  anthropic = { cli = "ANTHROPIC_API_KEY", own = "NVIM_ANTHROPIC_API_KEY" },
  openai = { cli = "OPENAI_API_KEY", own = "NVIM_OPENAI_API_KEY" },
}

for _, provider in ipairs({ "claude", "codex" }) do
  local both = resolve({
    NVIM_AI_PROVIDER = provider, NVIM_AI_KEY_PROFILE = "",
    ANTHROPIC_API_KEY = "cli-anthropic", NVIM_ANTHROPIC_API_KEY = "nvim-anthropic",
    OPENAI_API_KEY = "cli-openai", NVIM_OPENAI_API_KEY = "nvim-openai",
    NVIM_SPEC_WORK_KEY = "nvim-spec-work",
  })
  for name in pairs(adapters) do
    t.eq(both[name], { name = name, type = "http", key = "nvim-" .. name },
      ("%s-started: the %s adapter reads %s"):format(provider, name, adapters[name].own))
  end
  t.eq(both.spec_work, { name = "spec_work", type = "http", key = "nvim-spec-work" },
    ("%s-started: a custom key profile is an adapter of its own, reading its own variable"):format(provider))
  t.eq(both.codex_auth, "chat-gpt",
    ("%s-started: the Codex ACP adapter uses the ChatGPT login, not OPENAI_API_KEY"):format(provider))
  t.eq(both.codecompanion_adapter, vim.NIL, ("%s-started: vim.g.codecompanion_adapter stays unset"):format(provider))

  local cli_only = resolve({
    NVIM_AI_PROVIDER = provider, NVIM_AI_KEY_PROFILE = "",
    ANTHROPIC_API_KEY = "cli-anthropic", NVIM_ANTHROPIC_API_KEY = "",
    OPENAI_API_KEY = "cli-openai", NVIM_OPENAI_API_KEY = "",
  })
  for name, vars in pairs(adapters) do
    t.ok(cli_only[name] and cli_only[name].name == name and cli_only[name].key ~= "cli-" .. name,
      ("%s-started: %s alone is never used by the %s adapter"):format(provider, vars.cli, name))
  end
end

t.done()
