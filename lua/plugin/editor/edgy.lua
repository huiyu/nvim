return {
  "folke/edgy.nvim",
  event = "VeryLazy",
  init = function()
    -- edgy needs splitkeep="screen" to avoid layout jumps when sidebars open.
    vim.opt.splitkeep = "screen"
  end,
  opts = function()
    local ai = require("ai.config")

    -- snacks.terminal sets vim.b[buf].snacks_terminal = { cmd, id, win, ... }.
    -- The selected native agent always has an explicit command; plain bottom
    -- terminals have no cmd (default shell).
    local function is_agent_term(buf)
      local info = vim.b[buf].snacks_terminal
      if not info then return false end
      return ai.is_native_command(info.cmd)
    end

    -- Terminals float or dock by configuration (vim.g.terminal_position). When
    -- they float, edgy must claim none of them: its bottom slot would pull the
    -- float straight into the layout the moment it opens.
    local terminals_float = require("util.terminal").floats()

    return {
      animate = { enabled = false },
      wo = { winbar = false },
      options = {
        -- edgy owns the final say on right-sidebar geometry: it re-applies these
        -- sizes on BufWinEnter/WinResized, overriding whatever snacks or
        -- CodeCompanion asked for at open time. Read the shared width so the
        -- three AI panels cannot drift apart.
        right  = { size = ai.panel.width },
        bottom = { size = 15 },
      },
      -- snacks explorer (multi-window: list + input) doesn't fit edgy's
      -- single-window-per-slot model; let snacks own its sidebar.
      right = {
        {
          title = ai.label,
          ft = "snacks_terminal",
          filter = is_agent_term,
          size = { width = ai.panel.width },
        },
        {
          title = "CodeCompanion (" .. ai.label .. ")",
          ft = "codecompanion",
          size = { width = ai.panel.width },
        },
      },
      bottom = {
        {
          title = "Terminal",
          ft = "snacks_terminal",
          filter = function(buf)
            return not terminals_float and not is_agent_term(buf)
          end,
          size = { height = 0.3 },
        },
        {
          title = "QuickFix",
          ft = "qf",
          size = { height = 0.25 },
        },
      },
    }
  end,
}
