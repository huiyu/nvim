return {
  "lewis6991/gitsigns.nvim",
  event = "BufReadPost",
  keys = {
    { "]h",         "<cmd>Gitsigns next_hunk<cr>",      desc = "Next hunk" },
    { "[h",         "<cmd>Gitsigns prev_hunk<cr>",      desc = "Prev hunk" },
    { "<leader>gl", "<cmd>Gitsigns blame_line<cr>",     desc = "Blame line" },
    { "<leader>gL", "<cmd>Gitsigns blame<cr>",          desc = "Blame buffer" },
    { "<leader>gp", "<cmd>Gitsigns preview_hunk<cr>",   desc = "Preview hunk" },
    { "<leader>gr", "<cmd>Gitsigns reset_hunk<cr>",     desc = "Reset hunk" },
    { "<leader>gR", "<cmd>Gitsigns reset_buffer<cr>",   desc = "Reset buffer" },
    { "<leader>gS", "<cmd>Gitsigns stage_hunk<cr>",     desc = "Stage/unstage hunk" },
    -- Visual mode passes the selection explicitly: a <Cmd> mapping gives the
    -- command no range, so `:Gitsigns stage_hunk` would act on the whole hunk
    -- under the cursor instead of the selected lines. gitsigns makes the call
    -- dot-repeatable with that range captured, so `.` afterwards replays the
    -- same absolute lines, not the lines under the cursor.
    { "<leader>gr", function() require("gitsigns").reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end,
      desc = "Reset selected lines", mode = "x" },
    { "<leader>gS", function() require("gitsigns").stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end,
      desc = "Stage/unstage selected lines", mode = "x" },
    { "<leader>gd", "<cmd>Gitsigns diffthis<cr>",       desc = "Diff" },
    { "<leader>gT", "<cmd>Gitsigns toggle_current_line_blame<cr>", desc = "Toggle line blame" },
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
