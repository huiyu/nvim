return {
  "iamcco/markdown-preview.nvim",
  ft = "markdown",
  build = "cd app && npm install",
  keys = {
    { "<leader>cp", "<cmd>MarkdownPreviewToggle<cr>", desc = "Toggle Markdown Preview", ft = "markdown" },
  },
}
