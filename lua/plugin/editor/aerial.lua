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
  init = function()
    -- Pin aerial window width so other splits (e.g. edgy's bottom terminal)
    -- can't squeeze it. Aerial sits between the editor and Claude on the right.
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "aerial",
      callback = function()
        vim.wo.winfixwidth = true
      end,
    })
  end,
  opts = {
    backends = { "treesitter", "lsp", "markdown", "man" },
    layout = {
      min_width = 30,
      default_direction = "prefer_right",
      -- "window" = open next to the current window (not at the editor edge),
      -- so aerial lands between editor and Claude when triggered from editor.
      placement = "window",
    },
  },
}
