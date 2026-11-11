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
          -- Upstream's defaults, merged key by key (CodeCompanion deep-merges
          -- these), moved where they would repurpose a key that means
          -- something else everywhere: q hides as in every panel, <C-c>
          -- cancels, gx/gf open what is under the cursor, s is the window
          -- prefix and {/} are paragraph motions. What remains is upstream's.
          -- Descriptions are this config's wording where a key is ours or sits
          -- in the comma menu (sentence case, no articles).
          keymaps = {
            -- A chat's adapter is fixed when it is created; another backend
            -- is another chat (<leader>an).
            change_adapter = false,
            -- Switching chats is <leader>al, which the slot answers.
            next_chat = false,
            previous_chat = false,
            copilot_stats = false, -- gS is splitjoin; no Copilot adapter here
            options = { modes = { n = { "?", "g?" } } },
            -- <C-d> submits, as in the prompt editor and the review draft.
            send = { modes = { n = "<CR>", i = "<C-d>" }, description = "Send message" },
            stop = { modes = { n = "<C-c>" }, description = "Stop request" },
            -- Ends the chat (CodeCompanion shows another in its window).
            -- Normal mode only: upstream's Insert <C-c> is removed in `config`
            -- below, so it leaves Insert mode as everywhere (lua/mappings.lua).
            close = { modes = { n = "<localleader>q" }, description = "Close chat (ends it)" },
            -- Exactly <leader>ac from inside the chat: the slot hides it and
            -- keeps it as this tabpage's last chat, so <leader>ac brings it
            -- back. Left out of the chat's action palette, which only runs
            -- upstream's own callbacks.
            hide = {
              modes = { n = "q" },
              callback = function() require("ai").toggle() end,
              description = "Hide chat",
              opts = { chat = { show_in_action_palette = false } },
            },
            clear = { modes = { n = "<localleader>X" }, description = "Clear chat messages" },
            fold_code = { modes = { n = "<localleader>z" }, description = "Fold code blocks" },
            goto_file_under_cursor = { modes = { n = "gf" }, description = "Go to file under cursor" },
          },
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
          -- Mapped on the edited file's buffer while a request runs: <C-c>
          -- cancels, and q stays macro recording there.
          keymaps = { stop = { modes = { n = "<C-c>" } } },
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
            -- In the chat; upstream's `sc` sat inside the s window prefix.
            save_chat_keymap = "<localleader>s",
            save_chat_keymap_description = "Save chat",
            -- The chat's gh and <leader>ao are one browser, worded alike.
            keymap_description = "Browse saved Companion chats",
            -- The saved-chat picker (<leader>ao): delete as in Snacks' own
            -- pickers (dd, <C-x>). Both modes are required -- the extension
            -- indexes each and setup deep-merges, so neither can be dropped --
            -- so rename's Insert key is a <Plug> nobody types: upstream's
            -- <M-r> took every picker's toggle_regex.
            picker_keymaps = {
              delete = { n = "dd", i = "<C-x>" },
              rename = { n = "r", i = "<Plug>(codecompanion-history-rename)" },
            },
          },
        },
      },
      display = {
        action_palette = {
          provider = "snacks",
        },
        -- The prompt float (<leader>ae with no prompt, :CodeCompanion): <C-d>
        -- submits from Insert mode, as in the chat. Upstream's <C-s> is the
        -- tmux prefix here and never arrives (docs/DIAGNOSTICS.md).
        input = {
          keymaps = { send = { modes = { n = "<CR>", i = "<C-d>" } } },
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
    -- setup() deep-merges keymaps, so opts cannot drop a mode: upstream's
    -- Insert <C-c> would end the chat from the key that leaves Insert mode
    -- everywhere else. An empty `i = {}` would map nothing too, but lists as
    -- a blank Insert key in the chat's ? help and action palette.
    local close = require("codecompanion.config").interactions.chat.keymaps.close
    if type(close) == "table" and type(close.modes) == "table" then close.modes.i = nil end
    -- setup() defines :CodeCompanionCodeReview whatever `enabled` says, and its
    -- Branch subcommand would still write refs/worktree/codecompanion/*.
    pcall(vim.api.nvim_del_user_command, "CodeCompanionCodeReview")
  end,
}
