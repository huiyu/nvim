return {
  "folke/trouble.nvim",
  cmd = "Trouble",
  keys = {
    { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>",              desc = "Diagnostics",        mode = "n" },
    { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer diagnostics", mode = "n" },
    { "<leader>xL", "<cmd>Trouble loclist toggle<cr>",                  desc = "Location list",      mode = "n" },
    { "<leader>xQ", "<cmd>Trouble qflist toggle<cr>",                   desc = "Quickfix list",      mode = "n" },
    { "<leader>xs", "<cmd>Trouble symbols toggle focus=false<cr>",      desc = "Symbols",            mode = "n" },
  },
  opts = {},
}
