return {
  "stevearc/aerial.nvim",
  cmd = { "AerialToggle", "AerialOpen" },
  keys = {
    { "<leader>cO", "<cmd>AerialToggle<cr>", desc = "Code outline", mode = "n" },
  },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  opts = {
    backends = { "treesitter", "lsp", "markdown", "man" },
    layout = {
      min_width = 30,
      default_direction = "prefer_right",
    },
  },
}
