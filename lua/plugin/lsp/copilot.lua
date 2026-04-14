return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      terminal_cmd = "claude" .. (vim.env.CLAUDE_PLUGIN_DIR
        and (" " .. table.concat(vim.tbl_map(function(d) return "--plugin-dir " .. d end, vim.split(vim.env.CLAUDE_PLUGIN_DIR, ",")), " "))
        or ""),
      terminal = {
        split_side = "right",
        provider = "snacks",
        snacks_win_opts = {
          auto_insert = false,
          width = 90,
          wo = { winfixwidth = true },
        },
      },
      -- Bypass proxy for localhost WebSocket connections (IDE integration)
      env = {
        no_proxy = "localhost,127.0.0.1",
      },
      diff_opts = {
        auto_close_on_accept = true,
        vertical_split = true,
      },
    },
    keys = {
      { "<leader>ac", "<cmd>ClaudeCode<cr>",              desc = "Toggle Claude" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>",         desc = "Focus Claude" },
      { "<leader>ar", "<cmd>ClaudeCode --resume<cr>",     desc = "Resume Claude" },
      { "<leader>aR", "<cmd>ClaudeCode --continue<cr>",   desc = "Continue Claude" },
      { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>",   desc = "Select model" },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>",         desc = "Add current buffer" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>",          desc = "Send to Claude",  mode = "v" },
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>",    desc = "Accept diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>",      desc = "Deny diff" },
      {
        "<leader>aS",
        "<cmd>ClaudeCodeTreeAdd<cr>",
        desc = "Add file from tree",
        mode = "n",
        ft = { "NvimTree", "neo-tree", "oil", "minifiles", "snacks_explorer" },
      },
    },
  },
}
