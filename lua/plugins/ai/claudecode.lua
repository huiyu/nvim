local ai_config = require("ai.state")

-- Declared always, lazy and command-triggered: nothing loads the plugin
-- before the first Claude key does. Never make this spec conditional on the
-- providers (lua/ai/config.lua): lazy then prunes its lock line and lists the
-- plugin in `to_clean`, so `:Lazy clean` / `:Lazy sync` from a config without
-- Claude's `tui` deletes it.

local claude = require("ai.backend.claude")

return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    config = function(_, opts)
      claude.configure(opts)
      -- <leader>aa/ad exist once a Claude diff can arrive, whatever is on the
      -- right (lua/ai/init.lua).
      require("ai").apply_keymaps()
    end,
    cmd = {
      "ClaudeCode",
      -- Shows or starts the session and never hides it: the AI slot's reveal
      -- (lua/ai/backend/claude.lua) goes through it until the plugin has loaded.
      "ClaudeCodeOpen",
      "ClaudeCodeFocus",
      "ClaudeCodeSelectModel",
      "ClaudeCodeAdd",
      "ClaudeCodeSend",
      "ClaudeCodeDiffAccept",
      "ClaudeCodeDiffDeny",
      "ClaudeCodeTreeAdd",
    },
    opts = {
      terminal_cmd = claude.terminal_command(),
      terminal = {
        auto_insert = true,
        split_side = "right",
        provider = "snacks",
        cwd_provider = claude.cwd,
        snacks_win_opts = {
          width = ai_config.panel.width,
          -- No winbar: Snacks titles every split terminal "<n>: <term
          -- title>" unless told otherwise, a line of the panel that only
          -- repeats the command it runs. The agent draws its own header.
          wo = { winfixwidth = true, winbar = "" },
          -- Claude reads a quick double Esc itself; Snacks' own <esc>
          -- double-tap would swallow it. lua/ai/terminal.lua puts Esc back on
          -- the wire and keeps `jk` / <C-]> / <C-\> as the way out of Terminal-mode.
          keys = { term_normal = false },
        },
      },
      -- Bypass proxy for localhost WebSocket connections (IDE integration)
      env = {
        no_proxy = "localhost,127.0.0.1",
      },
      diff_opts = {
        -- A proposed edit opens in a tabpage of its own. In the current one,
        -- claudecode picks its target by skipping 'diff' windows
        -- (claudecode/diff.lua find_main_editor_window), and CodeDiff's panes
        -- never set 'diff': its working-tree pane is an ordinary file window,
        -- so a proposal could land inside a review view.
        open_in_new_tab = true,
      },
    },
  },
}
