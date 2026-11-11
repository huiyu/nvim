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
  -- No `keys`: the <leader>a keys belong to the AI facade (lua/ai/init.lua),
  -- which relabels <leader>ae on :AI key. They still load the plugin on first
  -- use -- through `require`, which lazy autoloads -- and the commands above
  -- cover everything typed.
  --
  -- A function, so the plugin starts from the key profile :AI key left behind
  -- when it first loads; after that, :AI key writes the live inline/cmd
  -- adapters (lua/ai/companion.lua, sync).
  opts = function()
    local ai = require("ai.config")

    -- Every key profile reads its own NVIM_* variable, never the one the agent
    -- CLIs bill against (lua/ai/config.lua). The two built-in adapters are
    -- redirected whichever providers are listed, so a restored chat or an
    -- upstream path naming one never reads a CLI's variable; a provider's
    -- `api` naming the built-in itself sets its own key over that.
    local http = { extend = {} }
    for adapter, var in pairs(ai.builtin_http_keys) do
      http.extend[adapter] = { env = { api_key = var } }
    end
    for _, name in ipairs(ai.key_names()) do
      local profile = ai.key_profiles[name]
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

    -- The subscription login for the built-in ACP adapters whichever
    -- providers are listed (Codex: `chat-gpt`; its own default, `api-key`,
    -- would bill OPENAI_API_KEY), then each provider's own `acp.auth_method`.
    local acp_extend = {}
    for adapter, method in pairs(ai.builtin_acp_auth) do
      acp_extend[adapter] = { defaults = { auth_method = method } }
    end
    for _, acp in ipairs(ai.acp) do
      if acp.auth_method then acp_extend[acp.adapter] = { defaults = { auth_method = acp.auth_method } } end
    end

    return {
      adapters = {
        acp = { extend = acp_extend },
        http = http,
      },
      interactions = {
        chat = {
          -- Only for CodeCompanion's own paths that name no adapter (a typed
          -- :CodeCompanionChat, the action palette): the first `acp` in
          -- lua/ai/config.lua's provider order, else the first `api`. Every
          -- chat <leader>an starts names its own.
          adapter = ai.codecompanion.chat_adapter,
          -- A chat's adapter is fixed when it is created; another backend is
          -- another chat (<leader>an).
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
