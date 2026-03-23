return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      -- Wrap in tmux to fix DEC mode 2026 rendering glitches
      -- Use -e to explicitly pass env vars that claudecode.nvim needs
      -- Use PID-based session name so multiple Neovim instances don't conflict
      terminal_cmd = (
        "tmux kill-session -t claude-nvim-%d 2>/dev/null; tmux new-session -s claude-nvim-%d"
        .. " -e CLAUDE_CODE_SSE_PORT=$CLAUDE_CODE_SSE_PORT -e ENABLE_IDE_INTEGRATION=$ENABLE_IDE_INTEGRATION"
        .. " claude"
        .. (vim.env.CLAUDE_PLUGIN_DIR
          and (" " .. table.concat(vim.tbl_map(function(d) return "--plugin-dir " .. d end, vim.split(vim.env.CLAUDE_PLUGIN_DIR, ",")), " "))
          or "")
      ):format(vim.fn.getpid(), vim.fn.getpid()),
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
