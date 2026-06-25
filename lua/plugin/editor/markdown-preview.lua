return {
  "iamcco/markdown-preview.nvim",
  ft = "markdown",
  -- Use the plugin's built-in installer to fetch a prebuilt binary,
  -- avoiding a yarn/node build (no `yarn` dependency required).
  build = function()
    vim.fn["mkdp#util#install"]()
  end,
  keys = {
    { "<leader>cp", "<cmd>MarkdownPreviewToggle<cr>", desc = "Toggle Markdown Preview", ft = "markdown" },
  },
}
