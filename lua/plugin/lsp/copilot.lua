return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      -- Wrap claude in tmux to handle DEC mode 2026 (synchronized output)
      -- This fixes TUI rendering glitches in Neovim's built-in terminal
      -- Kill existing session first to ensure fresh env vars (SSE port, etc.)
      terminal_cmd = "tmux kill-session -t claude-$(basename $PWD) 2>/dev/null; tmux new-session -s claude-$(basename $PWD) claude",
      terminal = {
        split_side = "right",
        split_width_percentage = 0.40,
        provider = "snacks",
        snacks_win_opts = {
          auto_insert = false,
          width = 90,
        },
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
