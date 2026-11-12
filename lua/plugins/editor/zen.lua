return {
  "folke/snacks.nvim",
  optional = true,
  keys = {
    {
      "sz",
      function()
        if vim.bo.buftype == "" then Snacks.zen() end
      end,
      desc = "Toggle zen mode (file window)",
    },
  },
  opts = {
    zen = {
      win = { width = 100 },
    },
  },
}
