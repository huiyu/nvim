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
      adapter = "anthropic",
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
      adapter = "openai_responses",
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
  if type(cmd) == "table" then cmd = table.concat(cmd, " ") end
  return type(cmd) == "string" and cmd:find(M.native.command, 1, true) ~= nil
end

return M
