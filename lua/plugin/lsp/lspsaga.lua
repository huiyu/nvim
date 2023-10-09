return {
  "nvimdev/lspsaga.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  config = function()
    require("lspsaga").setup({
      symbol_in_winbar = {
        enabled = true,
      },
      lightbulbs = {
        enabled = true,
      },
    })
  end,
}
