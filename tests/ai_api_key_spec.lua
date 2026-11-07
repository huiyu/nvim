-- CodeCompanion's HTTP Inline/command adapter reads a key of its own
-- (NVIM_ANTHROPIC_API_KEY / NVIM_OPENAI_API_KEY, lua/ai/config.lua), never the
-- variable the agent CLIs bill against: exporting ANTHROPIC_API_KEY or
-- OPENAI_API_KEY for Nvim's sake would move Claude Code or Codex off the
-- subscription. Both providers are checked, the second in a child Nvim,
-- because the provider is fixed per process.
local t = dofile("tests/helper.lua")

-- Resolve the selected provider's HTTP adapter the way CodeCompanion does
-- before a request, under the given environment, in a fresh Nvim.
local function resolve(env)
  local probe = [[
    require("lazy").load({ plugins = { "codecompanion.nvim" } })
    local ai = require("ai.config")
    local ok, adapter = pcall(require("codecompanion.adapters").resolve, ai.codecompanion.http_adapter)
    local key
    if ok and adapter then
      key = require("codecompanion.adapters.utils").get_env_vars(adapter).env_replaced.api_key
    end
    io.stdout:write(vim.json.encode({ name = ok and adapter and adapter.name or vim.NIL, key = key or vim.NIL }))
    vim.cmd("qa!")
  ]]
  local result = vim.system({ vim.v.progpath, "--headless", "-u", "init.lua", "-i", "NONE", "-c", "lua " .. probe:gsub("\n", " ") },
    { env = env, text = true }):wait(30000)
  local ok, decoded = pcall(vim.json.decode, (result.stdout or ""):match("{.*}") or "")
  return ok and decoded or { error = (result.stdout or "") .. (result.stderr or "") }
end

local cases = {
  { provider = "claude", adapter = "anthropic", cli = "ANTHROPIC_API_KEY", own = "NVIM_ANTHROPIC_API_KEY" },
  { provider = "codex", adapter = "openai", cli = "OPENAI_API_KEY", own = "NVIM_OPENAI_API_KEY" },
}

for _, case in ipairs(cases) do
  local both = resolve({ NVIM_AI_PROVIDER = case.provider, [case.cli] = "cli-key", [case.own] = "nvim-key" })
  t.eq(both, { name = case.adapter, key = "nvim-key" },
    ("%s: the %s adapter resolves and reads %s"):format(case.provider, case.adapter, case.own))

  local cli_only = resolve({ NVIM_AI_PROVIDER = case.provider, [case.cli] = "cli-key", [case.own] = "" })
  t.ok(cli_only.name == case.adapter and cli_only.key ~= "cli-key",
    ("%s: %s alone is never used for Inline prompts"):format(case.provider, case.cli))
end

t.done()
