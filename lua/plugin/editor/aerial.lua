return {
  "stevearc/aerial.nvim",
  cmd = { "AerialToggle", "AerialOpen" },
  keys = {
    { ",O", "<cmd>AerialToggle<cr>", desc = "Toggle code outline", mode = "n" },
  },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  init = function()
    -- Pin aerial window width so other splits (e.g. edgy's bottom terminal)
    -- can't squeeze it. Aerial sits between the editor and AI pane on the right.
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
      -- so aerial lands between editor and the AI pane when triggered from editor.
      placement = "window",
    },
    -- <C-j>/<C-k> are window navigation everywhere (lua/mappings.lua), as in
    -- oil, which turns off <C-h>/<C-l> for the same reason. j/k plus `p`
    -- (scroll to the symbol) still do what the defaults combined.
    keymaps = {
      ["<C-j>"] = false,
      ["<C-k>"] = false,
    },
  },
}
