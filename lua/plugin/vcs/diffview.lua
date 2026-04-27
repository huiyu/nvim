return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  keys = {
    { "<leader>gv", "<cmd>DiffviewOpen<cr>",          desc = "Diff view",     mode = "n" },
    { "<leader>gV", "<cmd>DiffviewFileHistory %<cr>",  desc = "File history",  mode = "n" },
    { "<leader>gH", "<cmd>DiffviewFileHistory<cr>",    desc = "Git log (all)", mode = "n" },
  },
  opts = {},
}
