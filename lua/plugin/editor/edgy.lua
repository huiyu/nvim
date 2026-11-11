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
    -- A native agent -- whichever one -- always has an
    -- explicit command; plain bottom terminals have no cmd (default shell).
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
      -- edgy maps these on every panel buffer that does not map them itself.
      -- `<c-q>` (win:hide) and `Q` (edgebar:close) drop a non-pinned window for
      -- good -- the operations window sizing must never use -- and this config
      -- pins none; `<c-q>` goes back to blockwise Visual. `]w`/`[w` are the
      -- global warning jumps, and windows are reached with <C-h/j/k/l>, so the
      -- window cycling on `]w`/`[w`/`]W`/`[W` goes too. `q` and the `<c-w>`
      -- resizers stay.
      keys = {
        ["<c-q>"] = false,
        ["Q"] = false,
        ["]w"] = false,
        ["[w"] = false,
        ["]W"] = false,
        ["[W"] = false,
      },
      options = {
        -- edgy owns the final say on right-sidebar geometry: it re-applies these
        -- sizes on BufWinEnter/WinResized, overriding whatever snacks or
        -- CodeCompanion asked for at open time. Read the shared width so the
        -- three AI panels cannot drift apart.
        right  = { size = ai.panel.width },
        bottom = { size = 15 },
        -- Matches nvim-dap-ui's own default width, so the panels do not jump
        -- between dapui opening them and edgy claiming them.
        left   = { size = 40 },
      },
      -- Debug panels. dapui still decides when these exist; edgy decides where
      -- they sit, the same as every other panel here. The left edge is
      -- otherwise unused: aerial sits inside the editor area on the right
      -- (lua/plugin/editor/aerial.lua) and the AI panels own the right edge.
      left = {
        { title = "DAP Scopes",      ft = "dapui_scopes",      size = { height = 0.25 } },
        { title = "DAP Breakpoints", ft = "dapui_breakpoints", size = { height = 0.25 } },
        { title = "DAP Stacks",      ft = "dapui_stacks",      size = { height = 0.25 } },
        { title = "DAP Watches",     ft = "dapui_watches",     size = { height = 0.25 } },
      },
      right = {
        -- Constant titles: edgy reads them once, and which agent or chat
        -- holds the slot changes after that. With winbar off they are never
        -- drawn anyway.
        {
          title = "AI agent",
          ft = "snacks_terminal",
          filter = is_agent_term,
          size = { width = ai.panel.width },
        },
        {
          title = "CodeCompanion",
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
        {
          title = "DAP REPL",
          ft = "dap-repl",
          size = { height = 0.25 },
        },
        {
          title = "DAP Console",
          ft = "dapui_console",
          -- dapui can show an element in a float (`dapui.float_element`). A
          -- float has no place in the layout, and claiming one drags it into
          -- the edgebar -- the same reason the terminal slot filters floats.
          filter = function(_, win) return vim.api.nvim_win_get_config(win).relative == "" end,
          size = { height = 0.25 },
        },
      },
    }
  end,
}
