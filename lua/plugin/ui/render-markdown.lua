return {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown", "codecompanion" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  keys = {
    { "<leader>hR", "<cmd>RenderMarkdown toggle<cr>", desc = "Toggle Markdown render", mode = "n" },
  },
  opts = {},
}
