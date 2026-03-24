return {
  "iamcco/markdown-preview.nvim",
  ft = "markdown",
  build = "cd app && yarn install",
  keys = {
    { "<leader>cp", "<cmd>MarkdownPreviewToggle<cr>", desc = "Toggle Markdown Preview", ft = "markdown" },
  },
}
