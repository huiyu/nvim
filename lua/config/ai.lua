-- AI settings. Edit this table, then restart Nvim to apply changes.
-- local-plugin/agent-workbench.nvim/lua/agent_workbench/state.lua validates it and owns the live state; plugin specs wire it
-- into the native terminals and CodeCompanion. Requiring this file only returns data.
return {
  plugin_dirs = {}, -- Local native plugin paths; NVIM_AI_PLUGIN_DIR overrides this list.
  -- Native is built in. Snacks and custom providers use the same lifecycle.
  terminal = { provider = "snacks" },
  native = { codex = { args = { "--no-alt-screen", "--yolo" }, wrap_tmux = true } },
  -- HTTP profile for inline edits and command prompts, not for new chats.
  -- "auto": the first provider API whose key is set, else the first API.
  -- Pin one with its api.name (default: api.adapter), e.g. "openai".
  -- Startup overrides: NVIM_AI_KEY_PROFILE > vim.g.ai_key_profile > this value.
  -- :AI key <name> switches it for this Nvim only; nothing is saved here.
  key_profile = "auto",

  -- Width in columns, shared by native terminals and CodeCompanion chats.
  panel = { width = 90 },

  -- One provider groups related entry points; offer any of tui, acp and api.
  -- Omit a part to hide it. There is no default backend: <leader>an asks.
  -- Entries appear as terminals, then ACP, then API, in provider order.
  -- CodeCompanion's own chats use the first ACP adapter, else the first API.
  --
  -- tui.kind: "codex"; another kind needs a backend implementation.
  -- acp.adapter: an existing CodeCompanion ACP adapter; command checks PATH.
  --   A new adapter must also be registered in lua/plugin/ai/codecompanion.lua.
  -- api.adapter: a CodeCompanion HTTP adapter; api_key names an NVIM_* variable.
  --   Optional: label, model, and name (a unique key profile/adapter name).
  providers = {
    {
      name = "codex",
      label = "Codex",
      cli_api_key = "OPENAI_API_KEY",
      tui = { kind = "codex" },
      -- The ChatGPT login: codex-acp's own default (`api-key`) would bill
      -- OPENAI_API_KEY instead.
      acp = { adapter = "codex", command = "codex-acp", auth_method = "chat-gpt" },
      -- CodeCompanion 20 folded openai_responses into openai, which is the
      -- Responses API now; the old name no longer resolves.
      api = { adapter = "openai", label = "OpenAI", api_key = "NVIM_OPENAI_API_KEY" },
    },
    -- One more key on the same API is one more provider with an `api` part.
    -- Its profile name, `api.name` (default: `api.adapter`), must be unique: it
    -- is also the CodeCompanion adapter it registers, so a chat that
    -- codecompanion-history restores finds its key again by that name.
    -- {
    --   name = "anthropic_work",
    --   label = "Anthropic (work)",
    --   api = { name = "anthropic_work", adapter = "anthropic",
    --           api_key = "NVIM_ANTHROPIC_API_KEY_WORK", model = "claude-sonnet-5" },
    -- },
  },
}
