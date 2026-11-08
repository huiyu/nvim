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
  -- A function, so the plugin starts from the state lua/ai/switch.lua left
  -- behind when it first loads; after that, switching writes the live config
  -- (switch.sync_codecompanion).
  opts = function()
    local ai = require("ai.config")

    -- Every key profile reads its own NVIM_* variable, never the one the agent
    -- CLIs bill against (lua/ai/config.lua). Both built-in adapters are
    -- redirected whichever provider started this Nvim, because either can be
    -- the active key profile after a switch.
    local http = { extend = {} }
    for name, profile in pairs(ai.key_profiles) do
      if name == profile.adapter then
        http.extend[name] = { env = { api_key = profile.api_key } }
      else
        -- An adapter of its own name, so a chat restored from history comes
        -- back on this profile rather than on the plain built-in one.
        http[name] = function()
          return require("codecompanion.adapters.http").extend(profile.adapter, {
            name = name,
            formatted_name = profile.label,
            env = { api_key = profile.api_key },
          })
        end
      end
    end

    return {
      adapters = {
        acp = {
          extend = {
            -- Unconditional: a Claude-started Nvim reaches Codex too, and the
            -- adapter's own default (`api-key`) would bill OPENAI_API_KEY
            -- instead of the ChatGPT login.
            codex = { defaults = { auth_method = "chat-gpt" } },
          },
        },
        http = http,
      },
      interactions = {
        chat = {
          adapter = ai.codecompanion.acp_adapter,
          -- A chat's adapter is fixed when it is created; choosing another is
          -- :AI's job (lua/ai/switch.lua), and applies to the next chat.
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
          adapter = ai.http_adapter_spec(),
        },
        cmd = {
          adapter = ai.http_adapter_spec(),
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
    }
  end,
}
