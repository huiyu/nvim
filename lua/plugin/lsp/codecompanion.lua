return {
  "olimorris/codecompanion.nvim",
  cmd = {
    "CodeCompanion",
    "CodeCompanionActions",
    "CodeCompanionChat",
    "CodeCompanionCmd",
    "CodeCompanionHistory",
    "CodeCompanionSummaries",
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "ravitemer/codecompanion-history.nvim",
  },
  -- No `keys`: the <leader>a chat keys belong to the AI facade
  -- (lua/ai/init.lua), which relabels them on every :AI switch. They still load
  -- the plugin on first use -- through `require`, which lazy autoloads -- and
  -- the commands above cover everything typed.
  --
  -- A function, so the plugin starts from the state lua/ai/switch.lua left
  -- behind when it first loads; after that, switching writes the live config
  -- (lua/ai/companion.lua, sync).
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
          -- Agent and API chats look alike once open, and bill differently,
          -- so every reply's header names both the backend and the kind:
          -- "CodeCompanion (Claude Code · ACP)", "CodeCompanion (Anthropic · API)".
          roles = {
            llm = function(adapter)
              return ("CodeCompanion (%s · %s)"):format(adapter.formatted_name, adapter.type == "acp" and "ACP" or "API")
            end,
          },
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
        -- CodeCompanion's own review keeps a second baseline under
        -- refs/worktree/codecompanion/*, taken on every chat submit in the
        -- cwd's repository. Review rounds (lua/ai/review) already cover chats,
        -- per conversation, so this one stays off: there must not be two
        -- baseline systems. `enabled = false` only skips its autocmds; the
        -- command is removed in `config` below, and #{code_review} is offered
        -- to no interaction.
        code_review = { enabled = false },
        shared = {
          editor_context = {
            code_review = { opts = { interactions = {} } },
          },
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
  config = function(_, opts)
    require("codecompanion").setup(opts)
    -- setup() defines :CodeCompanionCodeReview whatever `enabled` says, and its
    -- Branch subcommand would still write refs/worktree/codecompanion/*.
    pcall(vim.api.nvim_del_user_command, "CodeCompanionCodeReview")
  end,
}
