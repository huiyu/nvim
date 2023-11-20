return {
  "nvimdev/lspsaga.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  config = function()
    require("lspsaga").setup({
      code_action = {
        keys = {
          quit = { "q", "<C-c>" },
          exec = { "<CR>" },
        },
      },
      definition = {
        keys = {
          quit = "q",
          close = "<C-c>",
        },
      },
      diagnostic = {
        keys = {
          quit = { "q", "<ESC>", "<C-c>" },
          quit_in_show = { "q", "<ESC>", "<C-c>" },
        },
      },
      outline = {
        keys = {
          toggle_or_jump = "o",
          quit = { "q", "<C-c>" },
          jump = { "e", "<CR>" },
        },
      },
      rename = {
        keys = {
          quit = { "<C-c>" },
        },
      },
      symbol_in_winbar = {
        enabled = true,
      },
      lightbulbs = {
        enabled = true,
      },
    })
  end,
}
