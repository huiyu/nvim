return {
  "lewis6991/gitsigns.nvim",
  event = "BufReadPost",
  keys = {
    { "]h",         "<cmd>Gitsigns next_hunk<cr>",      desc = "Next hunk" },
    { "[h",         "<cmd>Gitsigns prev_hunk<cr>",      desc = "Prev hunk" },
    { "<leader>gl", "<cmd>Gitsigns blame_line<cr>",     desc = "Blame line" },
    { "<leader>gL", "<cmd>Gitsigns blame<cr>",          desc = "Blame buffer" },
    { "<leader>gp", "<cmd>Gitsigns preview_hunk<cr>",   desc = "Preview hunk" },
    { "<leader>gr", "<cmd>Gitsigns reset_hunk<cr>",     desc = "Reset hunk",       mode = { "n", "v" } },
    { "<leader>gR", "<cmd>Gitsigns reset_buffer<cr>",   desc = "Reset buffer" },
    { "<leader>gS", "<cmd>Gitsigns stage_hunk<cr>",     desc = "Stage hunk",       mode = { "n", "v" } },
    { "<leader>gu", "<cmd>Gitsigns undo_stage_hunk<cr>", desc = "Undo stage hunk" },
    { "<leader>gd", "<cmd>Gitsigns diffthis<cr>",       desc = "Diff" },
    { "<leader>gb", "<cmd>Gitsigns toggle_current_line_blame<cr>", desc = "Toggle line blame" },
    { "<leader>gB", function() Snacks.gitbrowse() end,  desc = "Git browse (open)" },
  },
  opts = {
    current_line_blame = true,
    current_line_blame_opts = {
      delay = 300,
      virt_text_pos = "eol",
    },
  },
}
