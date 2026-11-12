return {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown", "codecompanion" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  keys = {
    -- ,m stays local to rendered buffers and preserves ,r for LSP rename.
    { "<localleader>m", "<cmd>RenderMarkdown toggle<cr>", desc = "Toggle Markdown render", mode = "n",
      ft = { "markdown", "codecompanion" } },
  },
  opts = {},
}
