return {
  "lewis6991/gitsigns.nvim",
  event = "BufReadPost",
  keys = {
    -- nav_hunk, not the deprecated next_hunk/prev_hunk. Inside an inline diff
    -- (<leader>gD) it steps through that view's hunks.
    { "]h",         "<cmd>Gitsigns nav_hunk next<cr>",  desc = "Next hunk" },
    { "[h",         "<cmd>Gitsigns nav_hunk prev<cr>",  desc = "Prev hunk" },
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
    -- The file against the index in a split. Pressed again from any window of
    -- that split, it closes it, as <leader>gq does (gitsigns' own diffthis
    -- ignores a window in diff mode); from another window it moves the split
    -- there. util.diffsplit says why.
    { "<leader>gd", function() require("util.diffsplit").toggle() end, desc = "Toggle diff split" },
    -- The same comparison inside this window: lines removed since the index
    -- are drawn where they were (a changed line's old text right above it),
    -- no second window. Pressing it again closes the view. A file with merge
    -- conflicts still gets the three-way split, which a second press closes
    -- as <leader>gd's does.
    { "<leader>gD", function() require("util.diffsplit").toggle({ unified = true }) end,
      desc = "Toggle inline diff" },
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
