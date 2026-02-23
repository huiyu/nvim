return {
  "lewis6991/gitsigns.nvim",
  event = "BufReadPost",
  keys = {
    { "<leader>gj", "<cmd>Gitsigns next_hunk<cr>",      desc = "Next hunk",       mode = { "n", "v" } },
    { "<leader>gk", "<cmd>Gitsigns prev_hunk<cr>",      desc = "Prev hunk",       mode = { "n", "v" } },
    { "<leader>gl", "<cmd>Gitsigns blame_line<cr>",      desc = "Blame line",      mode = { "n", "v" } },
    { "<leader>gL", "<cmd>Gitsigns blame<cr>",           desc = "Blame buffer",    mode = { "n", "v" } },
    { "<leader>gp", "<cmd>Gitsigns preview_hunk<cr>",    desc = "Preview hunk",    mode = { "n", "v" } },
    { "<leader>gr", "<cmd>Gitsigns reset_hunk<cr>",      desc = "Reset hunk",      mode = { "n", "v" } },
    { "<leader>gR", "<cmd>Gitsigns reset_buffer<cr>",    desc = "Reset buffer",    mode = { "n", "v" } },
    { "<leader>gs", "<cmd>Gitsigns stage_hunk<cr>",      desc = "Stage hunk",      mode = { "n", "v" } },
    { "<leader>gu", "<cmd>Gitsigns undo_stage_hunk<cr>", desc = "Undo stage hunk", mode = { "n", "v" } },
    { "<leader>gd", "<cmd>Gitsigns diffthis<cr>",        desc = "Diff",            mode = { "n", "v" } },
  },
  opts = {},
}
