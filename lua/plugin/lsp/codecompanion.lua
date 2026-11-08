local ai = require("ai.config")

return {
  "olimorris/codecompanion.nvim",
  cmd = {
    "CodeCompanion",
    "CodeCompanionActions",
    "CodeCompanionChat",
    "CodeCompanionCmd",
    "CodeCompanionCodeReview",
    "CodeCompanionHistory",
    "CodeCompanionSummaries",
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "ravitemer/codecompanion-history.nvim",
  },
  keys = {
    { "<leader>apc", "<cmd>CodeCompanionChat<cr>",        desc = "New Companion chat" },
    { "<leader>apt", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle Companion chat" },
    { "<leader>apa", "<cmd>CodeCompanionActions<cr>",     desc = "Companion actions", mode = { "n", "x" } },
    { "<leader>api", ":CodeCompanion ",                   desc = "Companion inline prompt", mode = { "n", "x" } },
    { "<leader>apb", "<cmd>CodeCompanionChat Add<cr>",    desc = "Add selection to Companion", mode = "x" },
    { "<leader>aph", "<cmd>CodeCompanionHistory<cr>",     desc = "Companion chat history" },
  },
  opts = {
    adapters = {
      acp = {
        extend = ai.is("codex") and {
          -- Reuse the Codex/ChatGPT login selected by the vix profile.  HTTP
          -- inline prompts use NVIM_OPENAI_API_KEY independently below.
          codex = { defaults = { auth_method = "chat-gpt" } },
        } or {},
      },
      http = {
        -- Inline and command prompts read the dedicated key, never the
        -- variable the agent CLIs bill against (lua/ai/config.lua).
        extend = { [ai.codecompanion.http_adapter] = { env = { api_key = ai.codecompanion.api_key } } },
      },
    },
    interactions = {
      chat = {
        adapter = ai.codecompanion.acp_adapter,
        -- Provider selection belongs to NVIM_AI_PROVIDER for this Nvim process.
        keymaps = { change_adapter = false },
        -- Pinned rather than auto-detected: CodeCompanion takes the first of
        -- telescope, fzf-lua and mini.pick it can require before snacks, so
        -- any plugin that ships one of those would silently swap these pickers.
        -- These five are the picker-backed commands an ACP chat offers.
        slash_commands = {
          ["buffer"] = { opts = { provider = "snacks" } },
          ["file"] = { opts = { provider = "snacks" } },
          ["help"] = { opts = { provider = "snacks" } },
          ["symbols"] = { opts = { provider = "snacks" } },
          ["fetch"] = { opts = { provider = "snacks" } },
        },
      },
      inline = {
        adapter = ai.codecompanion.http_adapter,
      },
      cmd = {
        adapter = ai.codecompanion.http_adapter,
      },
    },
    extensions = {
      history = {
        enabled = true,
        opts = {
          auto_save = true,
          picker = "snacks",
          -- ACP agents already own session state.  Avoid a second model call
          -- solely to title each local History entry; entries remain renameable.
          auto_generate_title = false,
        },
      },
    },
    display = {
      action_palette = {
        provider = "snacks",
      },
      chat = {
        show_header_separator = false,
        start_in_insert_mode = false,
        window = {
          layout = "vertical",
          position = "right",
          full_height = true,
          width = ai.panel.width,
        },
      },
    },
  },
}
