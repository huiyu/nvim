return {
  "folke/edgy.nvim",
  event = "VeryLazy",
  init = function()
    -- edgy needs splitkeep="screen" to avoid layout jumps when sidebars open.
    vim.opt.splitkeep = "screen"
  end,
  opts = function()
    -- snacks.terminal sets vim.b[buf].snacks_terminal = { cmd, id, win, ... }.
    -- Claude is launched via a tmux-wrapped command containing "claude"; plain
    -- bottom terminals have no cmd (default shell).
    local function is_claude_term(buf)
      local info = vim.b[buf].snacks_terminal
      if not info then return false end
      local cmd = info.cmd
      if type(cmd) == "table" then cmd = table.concat(cmd, " ") end
      return cmd ~= nil and cmd:match("claude") ~= nil
    end

    return {
      animate = { enabled = false },
      wo = { winbar = false },
      options = {
        right  = { size = 90 },
        bottom = { size = 15 },
      },
      -- snacks explorer (multi-window: list + input) doesn't fit edgy's
      -- single-window-per-slot model; let snacks own its sidebar.
      right = {
        {
          title = "Claude",
          ft = "snacks_terminal",
          filter = is_claude_term,
          size = { width = 90 },
        },
      },
      bottom = {
        {
          title = "Terminal",
          ft = "snacks_terminal",
          filter = function(buf) return not is_claude_term(buf) end,
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
