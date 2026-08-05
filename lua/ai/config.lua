local selected = vim.env.NVIM_AI_PROVIDER or vim.g.ai_provider or "claude"
selected = selected:lower()

local providers = {
  claude = {
    label = "Claude Code",
    native = {
      command = "claude",
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
      http_adapter = "anthropic",
      api_key = "ANTHROPIC_API_KEY",
    },
  },
  codex = {
    label = "Codex",
    native = {
      command = "codex",
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
      http_adapter = "openai_responses",
      api_key = "OPENAI_API_KEY",
    },
  },
}

if not providers[selected] then
  error(("Invalid NVIM_AI_PROVIDER=%q; expected 'claude' or 'codex'"):format(selected))
end

local M = vim.deepcopy(providers[selected])
M.provider = selected

function M.is(provider)
  return M.provider == provider
end

function M.is_native_command(cmd)
  if type(cmd) == "table" then
    for _, part in ipairs(cmd) do
      if M.is_native_command(tostring(part)) then return true end
    end
    return false
  end
  if type(cmd) ~= "string" then return false end
  for token in cmd:gmatch("[^%s]+") do
    token = token:gsub("^[\"']+", ""):gsub("[\"';]+$", "")
    if vim.fs.basename(token) == M.native.command then return true end
  end
  return false
end

return M
