-- CodeCompanion's HTTP adapters read keys of their own (NVIM_ANTHROPIC_API_KEY /
-- NVIM_OPENAI_API_KEY, lua/ai/config.lua), never the variables the agent CLIs
-- bill against: exporting ANTHROPIC_API_KEY or OPENAI_API_KEY for Nvim's sake
-- would move Claude Code or Codex off the subscription.
--
-- Either key profile can be active after :AI key, and <leader>an starts an
-- API chat on either, so BOTH HTTP adapters are checked under several
-- provider lists (lua/ai/config.lua), each in a fresh child Nvim -- the
-- shipped one, Codex alone (the built-in anthropic adapter must still read
-- its NVIM_* key) and Claude alone (the built-in openai adapter too) -- plus
-- the Codex ACP adapter, which must stay on the ChatGPT login even when no
-- provider offers it. The order of a list changes only `auto` and the inline
-- adapter, which this does not read, so Codex first is not run again.
local t = dofile("tests/helper.lua")

-- Resolve every adapter the way CodeCompanion does before a request, under the
-- given environment, in a fresh Nvim. The provider list is set before the
-- plugin loads, the way an edit of config.lua would be, with an api-only
-- provider added: a second key on the anthropic adapter.
local function resolve(env, order)
  local probe = [[
    local ai = require("ai.config")
    local by_name = {}
    for _, p in ipairs(ai.providers) do by_name[p.name] = p end
    local list = {}
    for name in vim.env.SPEC_ORDER:gmatch("[^,]+") do list[#list + 1] = by_name[name] end
    list[#list + 1] = { name = "spec_work", label = "Spec work",
      api = { name = "spec_work", adapter = "anthropic", api_key = "NVIM_SPEC_WORK_KEY" } }
    ai._set_providers(list)
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
  env = vim.tbl_extend("force", env, { SPEC_ORDER = order })
  local result = vim.system({ vim.v.progpath, "--headless", "-u", "init.lua", "-i", "NONE", "-c", "lua " .. probe:gsub("\n", " ") },
    { env = env, text = true }):wait(30000)
  local ok, decoded = pcall(vim.json.decode, (result.stdout or ""):match("{.*}") or "")
  return ok and decoded or { error = (result.stdout or "") .. (result.stderr or "") }
end

local adapters = {
  anthropic = { cli = "ANTHROPIC_API_KEY", own = "NVIM_ANTHROPIC_API_KEY" },
  openai = { cli = "OPENAI_API_KEY", own = "NVIM_OPENAI_API_KEY" },
}

for _, order in ipairs({ "claude,codex", "codex", "claude" }) do
  local both = resolve({
    NVIM_AI_KEY_PROFILE = "",
    ANTHROPIC_API_KEY = "cli-anthropic", NVIM_ANTHROPIC_API_KEY = "nvim-anthropic",
    OPENAI_API_KEY = "cli-openai", NVIM_OPENAI_API_KEY = "nvim-openai",
    NVIM_SPEC_WORK_KEY = "nvim-spec-work",
  }, order)
  for name in pairs(adapters) do
    t.eq(both[name], { name = name, type = "http", key = "nvim-" .. name },
      ("%s: the %s adapter reads %s"):format(order, name, adapters[name].own))
  end
  t.eq(both.spec_work, { name = "spec_work", type = "http", key = "nvim-spec-work" },
    ("%s: a custom key profile is an adapter of its own, reading its own variable"):format(order))
  t.eq(both.codex_auth, "chat-gpt",
    ("%s: the Codex ACP adapter uses the ChatGPT login, not OPENAI_API_KEY"):format(order))
  t.eq(both.codecompanion_adapter, vim.NIL, ("%s: vim.g.codecompanion_adapter stays unset"):format(order))

  local cli_only = resolve({
    NVIM_AI_KEY_PROFILE = "",
    ANTHROPIC_API_KEY = "cli-anthropic", NVIM_ANTHROPIC_API_KEY = "",
    OPENAI_API_KEY = "cli-openai", NVIM_OPENAI_API_KEY = "",
  }, order)
  for name, vars in pairs(adapters) do
    t.ok(cli_only[name] and cli_only[name].name == name and cli_only[name].key ~= "cli-" .. name,
      ("%s: %s alone is never used by the %s adapter"):format(order, vars.cli, name))
  end
end

t.done()
